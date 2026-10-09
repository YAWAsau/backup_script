package com.xayah.dex;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Process;
import com.google.gson.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;

/** Structured, merge-only SMS/MMS and call history backup. Never copies provider databases.
 * Format is SpeedBackup-specific; it is not Android-DataBackup's JSON format.
 * No message content, addresses or numbers are printed in diagnostics.
 */
public final class TelephonyUtil {
    static final Gson G = new Gson();
    static final int MAX_JSON = 4 * 1024 * 1024;
    static final String[] SMS = fields("address body date date_sent type read seen status protocol reply_path_present subject service_center locked error_code sub_id");
    static final String[] CALL = fields("number date duration type new is_read number_presentation subscription_component_name subscription_id features post_dial_digits via_number data_usage phone_account_address");
    static final String[] MMS = fields("date date_sent msg_box read seen m_id sub sub_cs ct_t exp m_cls m_type v m_size pri rr rpt_a resp_st st tr_id retr_st retr_txt retr_txt_cs read_status ct_cls resp_txt d_tm d_rpt locked sub_id text_only");
    static final String[] ADDR = fields("address type charset");
    static final String[] PART = fields("seq ct name chset cd fn cid cl ctt_s ctt_t text");
    static String[] fields(String s) { return s.split(" "); }
    static ContentResolver resolver;
    static int targetUser;
    // Fixed synthetic provider only; never accepts an arbitrary URI from an archive.
    static final boolean FIXTURE="1".equals(System.getenv("SB_TELEPHONY_FIXTURE"));
    static long inserted, skipped;
    static boolean verifyOnly;
    static Set<String> targetSubscriptions;
    static String restoreSubscription(String value) {
        return targetSubscriptions!=null && !targetSubscriptions.contains(value) ? "-1" : value;
    }
    // FakeContext binds each provider through ActivityManager for targetUser.
    // Keep transport URIs unqualified; never ask the resolver to switch users.
    static Uri uri(String p) { return Uri.parse("content://" + (FIXTURE?"com.speedbackup.telephonyfixture/":"") + p); }
    static String path(String kind) { return kind.equals("calls") ? "call_log/calls" : kind; }
    static String[] columns(String kind) { return kind.equals("sms") ? SMS : kind.equals("calls") ? CALL : MMS; }
    static String str(JsonObject o, String k) { return !o.has(k) || o.get(k).isJsonNull() ? "" : o.get(k).getAsString(); }
    static String hex(byte[] b) { StringBuilder s=new StringBuilder(); for(byte x:b)s.append(String.format(Locale.ROOT,"%02x",x & 255)); return s.toString(); }
    static String digest(InputStream in, OutputStream out) throws Exception {
        MessageDigest md=MessageDigest.getInstance("SHA-256"); byte[] b=new byte[65536]; int n;
        while((n=in.read(b))!=-1) { md.update(b,0,n); if(out!=null)out.write(b,0,n); }
        return hex(md.digest());
    }
    static JsonObject row(Cursor c, String[] names) {
        JsonObject o=new JsonObject();
        for(String k:names) { int i=c.getColumnIndex(k); if(i<0)continue; if(c.isNull(i))o.add(k,JsonNull.INSTANCE); else o.addProperty(k,c.getString(i)); }
        return o;
    }
    static Cursor query(String p, String selection, String[] args) throws Exception {
        Cursor c=resolver.query(uri(p),null,selection,args,"_id ASC");
        if(c==null)throw new IOException("PROVIDER_QUERY_NULL"); return c;
    }
    static JsonObject record(String kind, Cursor c, boolean attachmentHashes) throws Exception {
        JsonObject o=new JsonObject(); o.addProperty("kind",kind); o.add("data",row(c,columns(kind)));
        if(kind.equals("mms")) {
            String id=c.getString(c.getColumnIndexOrThrow("_id"));
            JsonArray addr=new JsonArray();
            try(Cursor a=query("mms/"+id+"/addr",null,null)) { while(a.moveToNext())addr.add(row(a,ADDR)); }
            o.add("addr",addr); JsonArray parts=new JsonArray();
            try(Cursor p=query("mms/"+id+"/part",null,null)) {
                while(p.moveToNext()) {
                    JsonObject part=new JsonObject(); part.add("data",row(p,PART));
                    int di=p.getColumnIndex("_data"); boolean binary=di>=0 && !p.isNull(di) && !p.getString(di).isEmpty();
                    part.addProperty("binary",binary);
                    if(binary) {
                        String pid=p.getString(p.getColumnIndexOrThrow("_id"));
                        part.addProperty("source",pid);
                        if(attachmentHashes)try(InputStream in=resolver.openInputStream(uri("mms/part/"+pid))) {
                            if(in==null)throw new IOException("MMS_PART_UNREADABLE"); part.addProperty("sha256",digest(in,null));
                        }
                    }
                    parts.add(part);
                }
            }
            o.add("parts",parts);
        }
        return o;
    }
    static String identity(JsonObject o) throws Exception {
        JsonObject d=o.getAsJsonObject("data"), id=new JsonObject(); String kind=str(o,"kind"); id.addProperty("kind",kind);
        String[] keys=kind.equals("sms")?fields("address body date date_sent type sub_id"):
                kind.equals("calls")?fields("number date duration type subscription_component_name subscription_id"):
                fields("date date_sent msg_box m_id tr_id sub sub_cs m_type sub_id");
        // Cursor values and imported values use strings so 64-bit dates never round through double.
        for(String k:keys)id.addProperty(k,k.equals("sub_id")?restoreSubscription(str(d,k)):str(d,k));
        if(kind.equals("mms")) {
            List<String> addrs=new ArrayList<>(); for(JsonElement a:o.getAsJsonArray("addr"))addrs.add(a.toString());
            Collections.sort(addrs); id.add("addr",G.toJsonTree(addrs)); JsonArray ps=new JsonArray();
            for(JsonElement e:o.getAsJsonArray("parts")) { JsonObject p=e.getAsJsonObject().deepCopy(); p.remove("source"); ps.add(p); }
            id.add("parts",ps);
        }
        return hex(MessageDigest.getInstance("SHA-256").digest(G.toJson(id).getBytes(StandardCharsets.UTF_8)));
    }
    static void json(ZipOutputStream z, String name, JsonObject o) throws Exception {
        byte[] b=G.toJson(o).getBytes(StandardCharsets.UTF_8); if(b.length>MAX_JSON)throw new IOException("RECORD_TOO_LARGE");
        z.putNextEntry(new ZipEntry(name)); z.write(b); z.closeEntry();
    }
    static void exportArchive(String group, OutputStream output) throws Exception {
        ZipOutputStream z=new ZipOutputStream(new BufferedOutputStream(output,65536));
        z.setLevel(1); JsonObject header=new JsonObject(); header.addProperty("format","SpeedBackup.Telephony");
        header.addProperty("version",1); header.addProperty("group",group); json(z,"header.json",header);
        long n=0;
        for(String kind:group.equals("messages")?fields("sms mms"):fields("calls")) {
            try(Cursor c=query(path(kind),null,null)) { while(c.moveToNext()) {
                // Snapshot each MMS attachment once into a private bounded-on-disk spool.
                // The checksum and exported bytes now describe the same captured generation.
                JsonObject r=record(kind,c,false);
                List<File> spool=new ArrayList<>(); File spoolDir=null;
                try {
                    if(kind.equals("mms")) {
                        File parent=new File("/data/.speedbackup_telephony");
                        if(!parent.exists() && !parent.mkdir())throw new IOException("SPOOL_CREATE_FAILED");
                        android.system.StructStat st=android.system.Os.lstat(parent.getPath());
                        if(st.st_uid!=0 || !android.system.OsConstants.S_ISDIR(st.st_mode))throw new IOException("SPOOL_PARENT_INVALID");
                        android.system.Os.chmod(parent.getPath(),0700);
                        spoolDir=java.nio.file.Files.createTempDirectory(parent.toPath(),"mms-").toFile();
                        android.system.Os.chmod(spoolDir.getPath(),0700);
                        JsonArray parts=r.getAsJsonArray("parts");
                        for(int i=0;i<parts.size();i++) {
                            JsonObject part=parts.get(i).getAsJsonObject();
                            File file=new File(spoolDir,Integer.toString(i)); spool.add(file);
                            if(!part.get("binary").getAsBoolean())continue;
                            try(InputStream in=resolver.openInputStream(uri("mms/part/"+str(part,"source")));
                                OutputStream captured=new BufferedOutputStream(new FileOutputStream(file),65536)) {
                                if(in==null)throw new IOException("MMS_PART_UNREADABLE");
                                part.addProperty("sha256",digest(in,captured));
                            }
                        }
                    }
                    JsonObject wire=r.deepCopy();
                    if(kind.equals("mms"))for(JsonElement part:wire.getAsJsonArray("parts"))part.getAsJsonObject().remove("source");
                    json(z,"r/"+n+".json",wire);
                    for(int i=0;i<spool.size();i++) {
                        File file=spool.get(i); if(!file.isFile())continue;
                        z.putNextEntry(new ZipEntry("p/"+n+"/"+i));
                        try(InputStream captured=new FileInputStream(file)) {
                            byte[] buffer=new byte[65536]; int count;
                            while((count=captured.read(buffer))!=-1)z.write(buffer,0,count);
                        }
                        z.closeEntry();
                    }
                } finally {
                    for(File file:spool)java.nio.file.Files.deleteIfExists(file.toPath());
                    if(spoolDir!=null)java.nio.file.Files.deleteIfExists(spoolDir.toPath());
                }
                n++;
            }}
        }
        JsonObject end=new JsonObject(); end.addProperty("records",n); json(z,"complete.json",end);
        z.finish(); z.flush(); DiagnosticInfo.write("TELEPHONY_BACKUP_OK group="+group+" records="+n);
    }
    static byte[] readJson(InputStream in) throws Exception {
        ByteArrayOutputStream b=new ByteArrayOutputStream(); byte[] buf=new byte[8192]; int n;
        while((n=in.read(buf))!=-1) { if(b.size()+n>MAX_JSON)throw new IOException("RECORD_TOO_LARGE"); b.write(buf,0,n); } return b.toByteArray();
    }
    static JsonObject object(ZipInputStream z) throws Exception { return JsonParser.parseString(new String(readJson(z),StandardCharsets.UTF_8)).getAsJsonObject(); }
    static void entry(ZipInputStream z,String expected) throws Exception {
        ZipEntry e=z.getNextEntry(); if(e==null || !e.getName().equals(expected))throw new IOException("ARCHIVE_ENTRY_INVALID");
    }
    static void validateData(JsonObject d,String[] allowed) throws Exception {
        Set<String> a=new HashSet<>(Arrays.asList(allowed));
        for(Map.Entry<String,JsonElement> e:d.entrySet()) {
            if(!a.contains(e.getKey()) || (!e.getValue().isJsonNull() && (!e.getValue().isJsonPrimitive() || !e.getValue().getAsJsonPrimitive().isString())))throw new IOException("FIELD_INVALID");
        }
    }
    static void validateRecord(JsonObject r,String group) throws Exception {
        String k=str(r,"kind");
        if(!(group.equals("messages")?(k.equals("sms")||k.equals("mms")):k.equals("calls")))throw new IOException("KIND_INVALID");
        validateData(r.getAsJsonObject("data"),columns(k));
        JsonObject d=r.getAsJsonObject("data");
        if(str(d,"date").isEmpty())throw new IOException("DATE_REQUIRED"); Long.parseLong(str(d,"date"));
        if(k.equals("mms")) {
            if(r.getAsJsonArray("parts").size()>4096 || r.getAsJsonArray("addr").size()>4096)throw new IOException("MMS_TOO_MANY_PARTS");
            for(JsonElement a:r.getAsJsonArray("addr"))validateData(a.getAsJsonObject(),ADDR);
            for(JsonElement a:r.getAsJsonArray("parts")) { JsonObject p=a.getAsJsonObject(); validateData(p.getAsJsonObject("data"),PART);
                if(p.get("binary").getAsBoolean() && !str(p,"sha256").matches("[0-9a-f]{64}"))throw new IOException("MMS_HASH_INVALID");
                if(p.has("source"))throw new IOException("MMS_SOURCE_PATH_FORBIDDEN");
            }
        }
    }
    static ContentValues values(JsonObject o) {
        ContentValues v=new ContentValues(); for(Map.Entry<String,JsonElement> e:o.entrySet()) {
            if(e.getValue().isJsonNull())v.putNull(e.getKey()); else v.put(e.getKey(),e.getValue().getAsString());
        } return v;
    }
    static Uri insert(String p,JsonObject o) throws Exception {
        Uri u=resolver.insert(uri(p),values(o)); if(u==null)throw new IOException("INSERT_NULL"); return u;
    }
    static String id(Uri u) throws Exception { String id=u.getLastPathSegment(); if(id==null || !id.matches("[0-9]+"))throw new IOException("INSERT_ID_INVALID"); return id; }
    static String metadataIdentity(JsonObject r) throws Exception {
        JsonObject copy=r.deepCopy();
        for(JsonElement part:copy.getAsJsonArray("parts")) part.getAsJsonObject().remove("sha256");
        return identity(copy);
    }
    static void resolveMmsCandidates(JsonObject record, Map<String,List<JsonObject>> lazy, Map<String,Integer> existing) throws Exception {
        List<JsonObject> candidates=lazy.remove(metadataIdentity(record));
        if(candidates==null)return;
        for(JsonObject candidate:candidates) {
            for(JsonElement element:candidate.getAsJsonArray("parts")) {
                JsonObject part=element.getAsJsonObject(); if(!part.get("binary").getAsBoolean())continue;
                try(InputStream in=resolver.openInputStream(uri("mms/part/"+str(part,"source")))) {
                    if(in==null)throw new IOException("MMS_PART_UNREADABLE");
                    part.addProperty("sha256",digest(in,null));
                }
            }
            String key=identity(candidate); existing.put(key,existing.getOrDefault(key,0)+1);
        }
    }
    static Map<String,Integer> inventory(String group, Map<String,List<JsonObject>> lazyMms) throws Exception {
        Map<String,Integer> ids=new HashMap<>();
        for(String k:group.equals("messages")?fields("sms mms"):fields("calls"))try(Cursor c=query(path(k),null,null)) {
            while(c.moveToNext()) {
                JsonObject r=record(k,c,false);
                if(k.equals("mms")) { lazyMms.computeIfAbsent(metadataIdentity(r), key -> new ArrayList<>()).add(r); }
                else { String h=identity(r); ids.put(h,ids.getOrDefault(h,0)+1); }
            }
        }
        return ids;
    }
    static void consume(InputStream input,String group,boolean restore) throws Exception {
        if(restore && group.equals("messages") && !FIXTURE) {
            targetSubscriptions=new HashSet<>();
            try(Cursor c=resolver.query(uri("telephony/siminfo"),new String[]{"_id"},null,null,null)) {
                if(c==null)throw new IOException("SUBSCRIPTIONS_QUERY_FAILED");
                while(c.moveToNext())targetSubscriptions.add(c.getString(0));
            } catch(Exception e) {
                if(targetUser==0)throw e;
                // Some ROMs expose subscription metadata only through an owner
                // singleton. Never switch users for it; use unassigned SIM IDs.
                targetSubscriptions.clear();
                System.err.println("TELEPHONY_SIM_MAPPING_UNAVAILABLE user="+targetUser);
            }
        }
        ZipInputStream z=new ZipInputStream(new BufferedInputStream(input,65536)); entry(z,"header.json"); JsonObject h=object(z);
        if(!str(h,"format").equals("SpeedBackup.Telephony") || h.get("version").getAsInt()!=1 || !str(h,"group").equals(group))throw new IOException("FORMAT_INVALID");
        Map<String,List<JsonObject>> lazyMms=new HashMap<>();
        Map<String,Integer> existing=restore?inventory(group,lazyMms):new HashMap<>(); Map<String,Integer> seen=new HashMap<>(); long n=0;
        while(true) {
            ZipEntry e=z.getNextEntry(); if(e==null)throw new IOException("COMPLETION_MISSING");
            if(e.getName().equals("complete.json")) { if(object(z).get("records").getAsLong()!=n)throw new IOException("COUNT_MISMATCH"); break; }
            if(!e.getName().equals("r/"+n+".json"))throw new IOException("RECORD_ORDER_INVALID");
            JsonObject r=object(z); validateRecord(r,group); String key=identity(r), kind=str(r,"kind");
            if(restore && kind.equals("mms"))resolveMmsCandidates(r,lazyMms,existing);
            int occurrence=seen.getOrDefault(key,0)+1; seen.put(key,occurrence);
            boolean add=restore && occurrence>existing.getOrDefault(key,0); Uri created=null;
            if(verifyOnly && add)throw new IOException("VERIFY_RECORD_MISSING");
            try {
                if(add) {
                    JsonObject data=r.getAsJsonObject("data").deepCopy();
                    // A subscription ID belongs to the source device. Unknown IDs
                    // are restored without a SIM association; never guess a SIM.
                    if(targetSubscriptions!=null && !kind.equals("calls"))data.addProperty("sub_id",restoreSubscription(str(data,"sub_id")));
                    if(kind.equals("mms")) {
                        Set<String> recipients=new HashSet<>();
                        for(JsonElement a:r.getAsJsonArray("addr")) { String address=str(a.getAsJsonObject(),"address"); if(!address.isEmpty() && !address.equals("insert-address-token"))recipients.add(address); }
                        if(recipients.isEmpty())throw new IOException("MMS_RECIPIENTS_MISSING");
                        data.addProperty("thread_id",FIXTURE?"1":Long.toString(android.provider.Telephony.Threads.getOrCreateThreadId(resolverContext(),recipients)));
                    }
                    created=insert(path(kind),data);
                    if(kind.equals("mms"))for(JsonElement a:r.getAsJsonArray("addr"))insert("mms/"+id(created)+"/addr",a.getAsJsonObject());
                }
                if(kind.equals("mms")) {
                    JsonArray parts=r.getAsJsonArray("parts");
                    for(int i=0;i<parts.size();i++) {
                        JsonObject p=parts.get(i).getAsJsonObject(); Uri target=null;
                        if(add)target=insert("mms/"+id(created)+"/part",p.getAsJsonObject("data"));
                        if(p.get("binary").getAsBoolean()) {
                            entry(z,"p/"+n+"/"+i);
                            if(add)try(OutputStream out=resolver.openOutputStream(target)) {
                                if(out==null || !digest(z,out).equals(str(p,"sha256")))throw new IOException("MMS_PAYLOAD_INVALID");
                            } else if(!digest(z,null).equals(str(p,"sha256")))throw new IOException("MMS_PAYLOAD_INVALID");
                        }
                    }
                }
                if(add)inserted++; else if(restore)skipped++;
            } catch(Exception ex) {
                System.err.println("TELEPHONY_RECORD_FAILED kind="+kind+" index="+n+" sub_id="+str(r.getAsJsonObject("data"),"sub_id").replaceAll("[^0-9-]", ""));
                if(created!=null) { try { if(resolver.delete(created,null,null)!=1)throw new IOException("ROLLBACK_COUNT"); } catch(Exception rollback) { System.err.println("TELEPHONY_ROLLBACK_FAILED"); } }
                throw ex;
            }
            n++;
        }
        if(z.getNextEntry()!=null)throw new IOException("EXTRA_ENTRY");
        System.err.println("TELEPHONY_"+(verifyOnly?"VERIFY":restore?"RESTORE":"VALIDATE")+"_OK group="+group+" records="+n+" inserted="+inserted+" skipped="+skipped);
    }
    static android.content.Context resolverContext() throws Exception {
        return new android.content.ContextWrapper(HiddenApiHelper.getContext()) {
            @Override public ContentResolver getContentResolver() { return resolver; }
        };
    }
    /** Two bounded frames allow validation and restore in one process without spooling
     * an archive to disk. EOF or a producer failure cannot become a successful frame. */
    static final class FramedInput extends InputStream {
        final InputStream source;
        int remaining;
        boolean ended;
        FramedInput(InputStream source) { this.source=source; }
        @Override public int read() throws IOException {
            byte[] b=new byte[1];return read(b,0,1)<0?-1:b[0]&255;
        }
        @Override public int read(byte[] b,int off,int len) throws IOException {
            if(len==0)return 0;
            if(ended)return -1;
            if(remaining==0) {
                int a=source.read(),c=source.read(),d=source.read(),e=source.read();
                if((a|c|d|e)<0)throw new EOFException("FRAME_TRUNCATED");
                long n=((long)a<<24)|((long)c<<16)|((long)d<<8)|e;
                if(n>65536)throw new IOException("FRAME_TOO_LARGE");
                if(n==0) { ended=true;return -1; }
                remaining=(int)n;
            }
            int n=source.read(b,off,Math.min(len,remaining));
            if(n<0)throw new EOFException("FRAME_TRUNCATED");
            remaining-=n;return n;
        }
        void finish() throws IOException { byte[] b=new byte[65536];while(read(b)!=-1){} }
    }
    static void restoreSession(InputStream input,String group) throws Exception {
        // The same user-bound resolver is used for both phases; never switch users.
        FramedInput checked=new FramedInput(input);
        consume(checked,group,false);
        checked.finish();
        System.err.println("TELEPHONY_SESSION_VALIDATED group="+group);
        FramedInput restore=new FramedInput(input);
        inserted=0;skipped=0;verifyOnly=false;
        consume(restore,group,true);
        restore.finish();
        if(input.read()!=-1)throw new IOException("EXTRA_FRAME");
    }
    public static void main(String[] args) {
        int rc=0;
        try {
            if(args.length!=3 || !(args[1].equals("messages")||args[1].equals("calls")) || !args[2].matches("[0-9]{1,5}"))throw new IOException("INVALID_USER");
            targetUser=Integer.parseInt(args[2]);
            String command=args[0],group=args[1];
            if(!command.equals("validate")) {
                if(Process.myUid()!=0)throw new IOException("ROOT_REQUIRED");
                HiddenApiBypassBridge.installExemptionsOnce();
                android.content.Context context=HiddenApiHelper.getContext();
                android.os.UserManager users=(android.os.UserManager)context.getSystemService(android.content.Context.USER_SERVICE);
                if(users.getClass().getMethod("getUserInfo",int.class).invoke(users,targetUser)==null)throw new IOException("USER_NOT_FOUND");
                if(!users.isUserUnlocked(android.os.UserHandleHidden.of(targetUser)))throw new IOException("USER_LOCKED_OR_STOPPED");
                resolver=new FakeContext(context,true,targetUser,targetUser!=0).getContentResolver();
            }
            switch(command) {
                case "backup": exportArchive(group,System.out); break;
                case "validate": consume(System.in,group,false); break;
                case "restore": consume(System.in,group,true); break;
                case "restore-session": restoreSession(System.in,group); break;
                case "verify": verifyOnly=true; consume(System.in,group,true); break;
                case "probe":
                    for(String k:group.equals("messages")?fields("sms mms"):fields("calls"))try(Cursor c=query(path(k),null,null)) { System.out.println("PROVIDER_OK kind="+k); }
                    break;
                default: throw new IOException("COMMAND_INVALID");
            }
        } catch(Throwable e) {
            rc=1; System.err.println("TELEPHONY_FAILED reason="+e.getClass().getSimpleName()+" inserted="+inserted+" skipped="+skipped);
            if((e instanceof IOException || e instanceof SecurityException) && e.getMessage()!=null && e.getMessage().matches("[A-Z_]+"))System.err.println("TELEPHONY_ERROR_CODE="+e.getMessage());
            if("1".equals(System.getenv("TELEPHONY_DEBUG"))) for(StackTraceElement frame:e.getStackTrace())System.err.println(frame.toString());
            // Exception messages can contain provider SQL including private data: never log them.
        }
        System.exit(rc);
    }
}
