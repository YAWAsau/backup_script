package com.xayah.dex;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.system.Os;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;

/** Lossless account-neutral capture: logged-out histories never depend on account discovery. */
final class TimelineArchiveV3 {
    static final String INDEX="timeline-index.json";
    static void need(boolean ok,String why)throws IOException { TimelineDatabase.require(ok,why); }
    static String selector(String gaia)throws Exception {
        need(gaia!=null&&!gaia.isEmpty()&&gaia.length()<=128,"timeline_source_identity_invalid");
        return TimelineDatabase.digest(("SpeedBackup:timeline-gaia:"+gaia).getBytes(StandardCharsets.UTF_8));
    }
    static SortedSet<String> identities(File directory)throws Exception {
        SortedSet<String> ids=new TreeSet<>();
        for(String table:new String[]{"semantic_segment_table","edited_segment_table","aux_semantic_segment_table"}) {
            try(SQLiteDatabase db=TimelineDatabase.open(new File(directory,table.startsWith("aux")?"aux.db":"odlh.db"),TimelineDatabase.RO);
                Cursor c=db.rawQuery("SELECT DISTINCT obfuscated_gaia_id FROM "+table,null)) {
                while(c.moveToNext()){String id=c.getString(0);selector(id);ids.add(id);}
            }
        }
        need(ids.size()<=32,"timeline_collection_count_invalid");return ids;
    }
    static JSONObject index(ZipFile zip)throws Exception {
        ZipEntry e=zip.getEntry(INDEX);if(e==null)return null;
        need(e.getSize()>0&&e.getSize()<=131072,"timeline_archive_index_invalid");
        byte[] bytes=new byte[(int)e.getSize()];
        try(DataInputStream in=new DataInputStream(zip.getInputStream(e))){in.readFully(bytes);need(in.read()==-1,"timeline_archive_index_invalid");}
        JSONObject m=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
        need(m.getInt("format")==3,"timeline_archive_format_invalid");
        JSONObject files=m.getJSONObject("files");Set<String> expected=new HashSet<>();expected.add(INDEX);
        need(files.length()>=3&&files.length()<=34,"timeline_archive_file_count_invalid");
        for(Iterator<String> it=files.keys();it.hasNext();) {
            String name=it.next();need(name.matches("odlh\\.db|aux\\.db|geller-[a-f0-9]{64}\\.db"),"timeline_archive_entry_invalid");
            JSONObject spec=files.getJSONObject(name);ZipEntry item=zip.getEntry(name);
            need(spec.getLong("bytes")>0&&spec.getString("sha256").matches("[a-f0-9]{64}")&&item!=null&&item.getSize()==spec.getLong("bytes"),"timeline_archive_size_mismatch");expected.add(name);
        }
        need(expected.contains("odlh.db")&&expected.contains("aux.db"),"timeline_archive_incomplete");
        Set<String> actual=new HashSet<>();Enumeration<? extends ZipEntry> entries=zip.entries();
        while(entries.hasMoreElements()){ZipEntry item=entries.nextElement();need(!item.isDirectory()&&expected.contains(item.getName())&&actual.add(item.getName()),"timeline_archive_entry_invalid");}
        need(actual.equals(expected),"timeline_archive_incomplete");
        JSONArray sources=m.getJSONArray("sources");Set<String> ids=new HashSet<>();
        need(sources.length()>0&&sources.length()<=32,"timeline_collection_count_invalid");
        for(int i=0;i<sources.length();i++){JSONObject source=sources.getJSONObject(i);String id=source.getString("gaia");need(selector(id).equals(source.getString("selector"))&&ids.add(id),"timeline_source_identity_invalid");}
        return m;
    }
    static String sources(File archive)throws Exception {
        try(ZipFile zip=new ZipFile(archive)){JSONObject m=index(zip);if(m==null)return null;StringBuilder text=new StringBuilder();JSONArray rows=m.getJSONArray("sources");
            for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);text.append(r.getString("selector")).append('\t').append(GoogleAccountNames.clean(r.optString("label","未識別帳號"))).append('\n');}return text.toString();}
    }
    static void retainTimelineGeller(File file)throws Exception {
        try(SQLiteDatabase db=TimelineDatabase.open(file,SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            db.beginTransaction();try {
                TimelineDatabase.require(TimelineDatabase.number(db,"SELECT count(*) FROM geller_file_table WHERE data_type='"+TimelineDatabase.TYPE+"'")==0,"file_based_timeline_unsupported");
                db.execSQL("DELETE FROM geller_key_table WHERE data_type<>?",new Object[]{TimelineDatabase.TYPE});
                db.execSQL("DELETE FROM geller_data_table WHERE _id NOT IN (SELECT data_id FROM geller_key_table)");
                db.execSQL("DELETE FROM geller_metadata_table WHERE data_type<>?",new Object[]{TimelineDatabase.TYPE});
                db.execSQL("DELETE FROM geller_file_table");db.execSQL("DELETE FROM geller_database_info_table");db.setTransactionSuccessful();
            }finally{db.endTransaction();}db.execSQL("VACUUM");
        }
    }
    static long publish(File capture,File destination,int user,int uid,List<GoogleAccountNames.Account> known)throws Exception {
        need(!destination.exists(),"backup_destination_exists");JSONObject files=new JSONObject();long input=0;
        File[] entries=capture.listFiles();need(entries!=null,"timeline_archive_capture_missing");Arrays.sort(entries,Comparator.comparing(File::getName));
        for(File file:entries)if(file.getName().matches("odlh\\.db|aux\\.db|geller-[a-f0-9]{64}\\.db")) {
            TimelineDatabase.regular(file);if(file.getName().startsWith("geller-"))retainTimelineGeller(file);TimelineDatabase.integrity(file);input=Math.addExact(input,file.length());
            files.put(file.getName(),new JSONObject().put("bytes",file.length()).put("sha256",TimelineDatabase.hash(file)).put("schema",TimelineDatabase.schema(file)));
        }
        JSONArray sources=new JSONArray();
        for(String id:identities(capture)) {
            String label="未登入／未識別帳號（"+selector(id).substring(0,8)+"）",geller="";
            for(GoogleAccountNames.Account account:known)if(account.gaia.equals(id)){label=GoogleAccountNames.label(account);String candidate="geller-"+account.selector+".db";if(files.has(candidate))geller=candidate;}
            sources.put(new JSONObject().put("gaia",id).put("selector",selector(id)).put("label",label).put("geller",geller));
        }
        need(sources.length()>0,"timeline_history_not_initialized");
        byte[] metadata=new JSONObject().put("format",3).put("user",user).put("uid",uid).put("files",files).put("sources",sources).toString().getBytes(StandardCharsets.UTF_8);
        need(metadata.length<=131072,"timeline_archive_index_invalid");
        File temp=Files.createTempFile(destination.getAbsoluteFile().getParentFile().toPath(),".timeline-",".partial").toFile();
        try {
            Os.chmod(temp.getPath(),0600);
            try(FileOutputStream out=new FileOutputStream(temp);ZipOutputStream zip=new ZipOutputStream(out)) {
                zip.setLevel(1);zip.putNextEntry(new ZipEntry(INDEX));zip.write(metadata);zip.closeEntry();
                for(File file:entries)if(files.has(file.getName())){zip.putNextEntry(new ZipEntry(file.getName()));Files.copy(file.toPath(),zip);zip.closeEntry();}
                zip.finish();zip.flush();out.getFD().sync();
            }
            try(ZipFile zip=new ZipFile(temp)){index(zip);}
            need(temp.renameTo(destination),"backup_publish_failed");TimelineUtil.syncDirectory(destination.getAbsoluteFile().getParentFile());
            return Math.addExact(input,metadata.length);
        }finally{Files.deleteIfExists(temp.toPath());}
    }
    static File stage(File archive,File work,String selected)throws Exception {
        try(ZipFile zip=new ZipFile(archive)) {
            JSONObject index=index(zip);if(index==null)return null;
            JSONObject source=null;JSONArray sources=index.getJSONArray("sources");
            for(int i=0;i<sources.length();i++){JSONObject candidate=sources.getJSONObject(i);if(candidate.getString("selector").equals(selected))source=candidate;}
            need(source!=null,"timeline_source_selection_required");
            JSONObject files=index.getJSONObject("files");String geller=source.optString("geller","");boolean unknown=geller.isEmpty();
            if(unknown){List<String> keys=new ArrayList<>();for(Iterator<String> it=files.keys();it.hasNext();){String k=it.next();if(k.startsWith("geller-"))keys.add(k);}Collections.sort(keys);need(!keys.isEmpty(),"timeline_archive_incomplete");geller=keys.get(0);}
            need(geller.matches("geller-[a-f0-9]{64}\\.db")&&files.has(geller),"timeline_archive_account_invalid");
            File input=new File(work,"input");need(input.mkdir(),"backup_output_invalid");Os.chmod(input.getPath(),0700);
            String[] names={"odlh.db","aux.db",geller};long required=67108864;
            for(String name:names)required=Math.addExact(required,Math.multiplyExact(3,files.getJSONObject(name).getLong("bytes")));
            need(required<input.getUsableSpace(),"timeline_archive_space_insufficient");
            for(int i=0;i<names.length;i++) {
                JSONObject spec=files.getJSONObject(names[i]);File target=new File(input,TimelineDatabase.FILES[i]);long total=0,limit=spec.getLong("bytes");
                try(InputStream in=zip.getInputStream(zip.getEntry(names[i]));FileOutputStream out=new FileOutputStream(target)){Os.chmod(target.getPath(),0600);byte[] buffer=new byte[65536];int n;while((n=in.read(buffer))!=-1){total=Math.addExact(total,n);need(total<=limit,"timeline_archive_size_exceeded");out.write(buffer,0,n);}out.getFD().sync();}
                need(total==limit&&TimelineDatabase.hash(target).equals(spec.getString("sha256")),"snapshot_hash_mismatch");
                need(TimelineDatabase.schema(target).equals(spec.getString("schema")),"snapshot_schema_mismatch");TimelineDatabase.integrity(target);
            }
            String gaia=source.getString("gaia");need(identities(input).contains(gaia),"timeline_source_identity_mismatch");
            TimelineDatabase.filterAccount(input,gaia);
            if(unknown)TimelineDatabase.clearImportGeller(input);
            JSONObject inventory=new JSONObject();
            for(String name:TimelineDatabase.FILES){File file=new File(input,name);inventory.put(name,new JSONObject().put("sha256",TimelineDatabase.hash(file)).put("bytes",file.length()).put("schema",TimelineDatabase.schema(file)).put("wal",false));}
            JSONObject manifest=new JSONObject().put("format",1).put("user",index.getInt("user")).put("uid",index.getInt("uid")).put("device","").put("account",selected).put("selective",true).put("source_display_name",source.optString("label","未識別帳號")).put("files",inventory);
            File marker=new File(input,"manifest.json");Files.write(marker.toPath(),manifest.toString().getBytes(StandardCharsets.UTF_8));Os.chmod(marker.getPath(),0600);
            return input;
        }
    }
    static void cleanup(File capture)throws Exception {
        File[] entries=capture.listFiles();if(entries==null)return;
        for(File file:entries){need(file.getName().matches("(odlh|aux|geller)\\.db(-wal|-shm|-journal)?|geller-[a-f0-9]{64}\\.db(-wal|-shm|-journal)?"),"timeline_archive_cleanup_invalid");need(!file.isDirectory(),"timeline_archive_cleanup_invalid");Files.delete(file.toPath());}
        Files.delete(capture.toPath());
    }
}
