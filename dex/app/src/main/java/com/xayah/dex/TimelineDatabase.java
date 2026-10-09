package com.xayah.dex;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.system.Os;
import android.system.OsConstants;
import org.json.JSONObject;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Arrays;

/** SQL storage layer. The caller owns the backup lock and bounded GMS UID freeze. */
final class TimelineDatabase {
    static final String TYPE = "ENCRYPTED_ONDEVICE_LOCATION_HISTORY";
    static final String[] FILES = {"odlh.db", "aux.db", "geller.db"};
    static final String[] ODLH = {"semantic_segment_table", "edited_segment_table", "geller_metadata", "geller_sync_status"};
    static final String[] AUX = {"aux_semantic_segment_table", "sqlite_sequence"};
    static final int RO = SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS;
    static final int RW = SQLiteDatabase.OPEN_READWRITE | SQLiteDatabase.NO_LOCALIZED_COLLATORS | SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING;

    interface Barrier { void check() throws Exception; }

    static final class Live {
        final File odlh, aux, geller;
        final File actualAux;
        final boolean auxiliaryAbsent;
        final int user, uid;
        final boolean[] wal=new boolean[3];
        Live(int user,boolean recoverJournals,String selected) throws Exception {
            this(user,recoverJournals,selected,null);
        }
        Live(int user,boolean recoverJournals,String selected,File work) throws Exception {
            this(user,recoverJournals,selected,work,new File("/data/user/"+user+"/com.google.android.gms/databases"));
        }
        Live(int user,boolean recoverJournals,String selected,File work,File base) throws Exception {
            require(user >= 0 && user <= 1000, "user_invalid");
            this.user=user;
            odlh=new File(base,"odlh-storage.db"); actualAux=new File(base,"aux-odlh-storage.db");
            auxiliaryAbsent=missing(actualAux);
            aux=auxiliaryAbsent && work!=null?emptyAux(work):actualAux;
            File[] matches=base.listFiles((dir,name)->name.startsWith("portable_geller_") && name.endsWith(".db"));
            if(selected!=null && !selected.isEmpty()) {
                require(selected.matches("[a-f0-9]{64}"),"account_selector_invalid");
                java.util.ArrayList<File> filtered=new java.util.ArrayList<>();
                if(matches!=null) for(File candidate:matches)
                    if(digest(candidate.getName().getBytes(StandardCharsets.UTF_8)).equals(selected)) filtered.add(candidate);
                matches=filtered.toArray(new File[0]);
            }
            require(matches!=null && matches.length==1,"requires_one_selected_geller_account");
            geller=matches[0];
            regular(odlh); regular(aux); regular(geller);
            uid=Os.stat(odlh.getPath()).st_uid;
            require(uid/100000==user && uid%100000>=10000 && uid%100000<99000,"gms_uid_invalid");
            require(Os.stat(aux.getPath()).st_uid==(auxiliaryAbsent?0:uid) && Os.stat(geller.getPath()).st_uid==uid,"database_owner_mismatch");
            // After SIGKILL SQLite may need to replay a hot rollback journal.
            // READONLY cannot do that. Only explicit recovery opens a writer;
            // SQLite itself resolves its journal before any Timeline SQL runs.
            if(recoverJournals) for(File file:files()) {
                try(SQLiteDatabase d=open(file,SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                    scalar(d,"PRAGMA user_version");
                }
                fixSidecars(file);
            }
            File[] modes=files();
            for(int i=0;i<modes.length;i++) try(SQLiteDatabase d=open(modes[i],RO)) { wal[i]="wal".equalsIgnoreCase(scalar(d,"PRAGMA journal_mode")); }
            try(SQLiteDatabase d=open(odlh,RO)) { require(number(d,"PRAGMA user_version")==12,"odlh_schema_unsupported"); }
            try(SQLiteDatabase d=open(aux,RO)) { require(number(d,"PRAGMA user_version")==1,"aux_schema_unsupported"); }
            try(SQLiteDatabase d=open(geller,RO)) { require(number(d,"PRAGMA user_version")==9,"geller_schema_unsupported"); }
        }
        File[] files() { return new File[]{odlh,aux,geller}; }
        void checkAuxiliary() throws Exception {
            require(missing(actualAux)==auxiliaryAbsent,"aux_presence_changed");
        }
    }

    static boolean missing(File file) throws Exception {
        try { Os.lstat(file.getPath());return false; }
        catch(android.system.ErrnoException e) { if(e.errno==OsConstants.ENOENT)return true;throw e; }
    }
    // GMS creates this database lazily. An absent database represents no auxiliary
    // rows, not a damaged primary history. Keep its empty representation private;
    // never create a database inside GMS or discard incoming auxiliary records.
    private static File emptyAux(File work) throws Exception {
        require(work!=null && Os.stat(work.getPath()).st_uid==0,"aux_work_invalid");
        File dir=new File(work,"auxiliary");
        require(dir.getCanonicalFile().equals(dir.getAbsoluteFile()),"aux_work_invalid");
        if(!dir.exists())require(dir.mkdir(),"aux_work_create_failed");
        require(OsConstants.S_ISDIR(Os.lstat(dir.getPath()).st_mode) && Os.stat(dir.getPath()).st_uid==0,"aux_work_invalid");
        Os.chmod(dir.getPath(),0700);
        File file=new File(dir,"aux.db");
        if(missing(file)) {
            try(SQLiteDatabase d=open(file,SQLiteDatabase.CREATE_IF_NECESSARY|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                d.execSQL("CREATE TABLE android_metadata (locale TEXT)");
                d.execSQL("CREATE TABLE aux_semantic_segment_table (_id INTEGER PRIMARY KEY AUTOINCREMENT, obfuscated_gaia_id TEXT NOT NULL, sub_identifier INTEGER, start_timestamp_millis INTEGER NOT NULL, end_timestamp_millis INTEGER NOT NULL, segment_id TEXT NOT NULL UNIQUE, segment_type INTEGER NOT NULL, hierarchy_level INTEGER, semantic_segment BLOB NOT NULL)");
                d.setVersion(1);
            }
            Os.chmod(file.getPath(),0600);
        }
        regular(file);require(Os.stat(file.getPath()).st_uid==0,"aux_work_invalid");
        try(SQLiteDatabase d=open(file,SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            require(number(d,"PRAGMA user_version")==1 && number(d,"SELECT count(*) FROM aux_semantic_segment_table")==0,"aux_private_not_empty");
        }
        return file;
    }
    private static void checkIncomingAuxiliary(Live live,File input) throws Exception {
        if(live.auxiliaryAbsent)try(SQLiteDatabase d=open(new File(input,"aux.db"),RO)) {
            require(number(d,"SELECT count(*) FROM aux_semantic_segment_table")==0,"aux_missing_nonempty_backup");
        }
    }

    static void require(boolean ok,String code) throws IOException { if(!ok) throw new IOException(code); }
    static void regular(File f) throws Exception {
        require(OsConstants.S_ISREG(Os.lstat(f.getPath()).st_mode),"database_not_regular");
        require(f.length()>0,"database_empty");
    }
    static SQLiteDatabase open(File f,int flags) { return SQLiteDatabase.openDatabase(f.getPath(),null,flags); }
    private static String context(File file) throws Exception {
        Object value=Class.forName("android.os.SELinux").getMethod("getFileContext",String.class).invoke(null,file.getPath());
        require(value instanceof String && !((String)value).isEmpty(),"database_context_unavailable");
        return (String)value;
    }
    static void fixSidecars(File database) throws Exception {
        android.system.StructStat original=Os.stat(database.getPath());
        String label=context(database);
        java.lang.reflect.Method set=Class.forName("android.os.SELinux").getMethod("setFileContext",String.class,String.class);
        for(String suffix:Arrays.asList("-journal","-wal","-shm")) {
            File sidecar=new File(database.getPath()+suffix);
            if(!sidecar.exists()) continue;
            require(OsConstants.S_ISREG(Os.lstat(sidecar.getPath()).st_mode),"sidecar_not_regular");
            Os.chown(sidecar.getPath(),original.st_uid,original.st_gid);
            Os.chmod(sidecar.getPath(),original.st_mode&0777);
            require(Boolean.TRUE.equals(set.invoke(null,sidecar.getPath(),label)),"sidecar_context_restore_failed");
            require(label.equals(context(sidecar)),"sidecar_context_verify_failed");
        }
    }
    static void restoreModes(Live live,File manifestDirectory) throws Exception {
        JSONObject inventory=manifestDirectory==null?null:new JSONObject(new String(Files.readAllBytes(new File(manifestDirectory,"manifest.json").toPath()),StandardCharsets.UTF_8)).getJSONObject("files");
        File[] files=live.files();
        for(int i=0;i<files.length;i++) {
            boolean wanted=inventory==null?live.wal[i]:inventory.getJSONObject(FILES[i]).optBoolean("wal",live.wal[i]);
            // WAL is persistent; rollback-journal variants are connection-local.
            if(wanted) try(SQLiteDatabase d=open(files[i],RW)) {
                require(d.enableWriteAheadLogging() && "wal".equalsIgnoreCase(scalar(d,"PRAGMA journal_mode")),"journal_mode_restore_failed");
            }
            fixSidecars(files[i]);
        }
    }
    static String scalar(SQLiteDatabase d,String sql) {
        try(Cursor c=d.rawQuery(sql,null)) { if(!c.moveToFirst()) throw new IllegalStateException("missing_scalar"); return c.getString(0); }
    }
    static long number(SQLiteDatabase d,String sql) { return Long.parseLong(scalar(d,sql)); }
    static String digest(byte[] bytes) throws Exception { return hex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
    static String hex(byte[] bytes) {
        StringBuilder out=new StringBuilder(bytes.length*2);
        for(byte b:bytes) out.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        return out.toString();
    }
    static String hash(File f) throws Exception {
        MessageDigest d=MessageDigest.getInstance("SHA-256");
        try(java.io.InputStream in=Files.newInputStream(f.toPath())) {
            byte[] buf=new byte[65536]; int n; while((n=in.read(buf))!=-1) d.update(buf,0,n);
        }
        return hex(d.digest());
    }
    static String schema(File file) throws Exception {
        return schema(file,false);
    }
    static String schema(File file,boolean portableOdlh) throws Exception {
        StringBuilder b=new StringBuilder();
        try(SQLiteDatabase d=open(file,RO); Cursor c=d.rawQuery("SELECT type,name,tbl_name,coalesce(sql,'') FROM sqlite_master ORDER BY type,name",null)) {
            while(c.moveToNext()) for(int i=0;i<4;i++) {
                String s=c.getString(i);
                if(portableOdlh && i==3 && "table".equals(c.getString(0))
                        && Arrays.asList("semantic_segment_table","edited_segment_table").contains(c.getString(1))) {
                    String quoted="CREATE TABLE \""+c.getString(1)+"\"";
                    if(s.startsWith(quoted+"("))s="CREATE TABLE "+c.getString(1)+s.substring(quoted.length());
                }
                if(portableOdlh && i==3 && "table".equals(c.getString(0)) && "semantic_segment_table".equals(c.getString(1)))
                    s=s.replaceAll("database_id INTEGER NOT NULL DEFAULT -?[0-9]+", "database_id INTEGER NOT NULL DEFAULT DEVICE_LOCAL_ID");
                b.append(s.length()).append(':').append(s);
            }
        }
        return digest(b.toString().getBytes(StandardCharsets.UTF_8));
    }
    static void integrity(File file) throws Exception {
        try(SQLiteDatabase d=open(file,RO)) {
            require("ok".equals(scalar(d,"PRAGMA integrity_check")),"database_integrity_failed");
            try(Cursor c=d.rawQuery("PRAGMA foreign_key_check",null)) { require(!c.moveToFirst(),"database_foreign_key_failed"); }
        }
    }
    static void snapshot(File source,File destination) throws Exception {
        require(!destination.exists(),"snapshot_exists");
        try(SQLiteDatabase d=open(source,RO)) {
            String[] v=scalar(d,"SELECT sqlite_version()").split("\\.");
            require(v.length>=2 && (Integer.parseInt(v[0])>3 || Integer.parseInt(v[0])==3 && Integer.parseInt(v[1])>=27),"sqlite_too_old");
            d.execSQL("VACUUM main INTO ?",new Object[]{destination.getPath()});
        }
        Os.chmod(destination.getPath(),0600);
    }
    static void capture(Live live,File out,Barrier guard) throws Exception {
        require(out.isDirectory() && !new File(out,"manifest.json").exists(),"backup_output_invalid");
        guard.check();live.checkAuxiliary();
        File[] source=live.files();
        for(int i=0;i<FILES.length;i++) {
            guard.check(); snapshot(source[i],new File(out,FILES[i]));
            fixSidecars(source[i]);
        }
        guard.check();
    }
    // Run after releasing the live-source guard: only owned snapshots are changed here.
    static void filterAccount(File out,String gaia) throws Exception {
        for(String name:Arrays.asList("odlh.db","aux.db")) {
            try(SQLiteDatabase db=open(new File(out,name),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                db.beginTransaction();try {
                    for(String table:name.equals("odlh.db")?new String[]{"semantic_segment_table","edited_segment_table"}:new String[]{"aux_semantic_segment_table"})
                        db.execSQL("DELETE FROM "+table+" WHERE obfuscated_gaia_id IS NOT ?",new Object[]{gaia});
                    // Shared sync ranges no longer describe this filtered subset; GMS rebuilds them.
                    if(name.equals("odlh.db"))db.execSQL("DELETE FROM geller_sync_status");
                    db.setTransactionSuccessful();
                }finally{db.endTransaction();}
                db.execSQL("VACUUM");
            }
        }
    }
    static void finishBackup(Live live,File out,String deviceBinding,boolean selective) throws Exception {
        require(out.isDirectory() && !new File(out,"manifest.json").exists(),"backup_output_invalid");
        if(selective) {
            String account=rowAccount(new File(out,"odlh.db"),"semantic_segment_table");
            String edited=rowAccount(new File(out,"odlh.db"),"edited_segment_table");
            String auxiliary=rowAccount(new File(out,"aux.db"),"aux_semantic_segment_table");
            require(account!=null,"timeline_history_not_initialized");
            require((edited==null || edited.equals(account)) && (auxiliary==null || auxiliary.equals(account)),"cross_row_account_mismatch");
        }
        JSONObject manifest=new JSONObject();
        manifest.put("format",1).put("user",live.user).put("uid",live.uid)
                .put("device",deviceBinding).put("account",digest(live.geller.getName().getBytes(StandardCharsets.UTF_8)))
                .put("selective",selective);
        if(selective) {
            String gaia=rowAccount(new File(out,"odlh.db"),"semantic_segment_table");
            require(GoogleAccountNames.select(live.user,manifest.getString("account")).gaia.equals(gaia),"timeline_source_account_mismatch");
            for(GoogleAccountNames.Account account:GoogleAccountNames.read(live.user))
                if(account.gaia.equals(gaia))manifest.put("source_display_name",GoogleAccountNames.label(account));
        }
        JSONObject inventory=new JSONObject();
        for(int i=0;i<FILES.length;i++) {
            File target=new File(out,FILES[i]); regular(target);
            if(i==2 && selective) {
                try(SQLiteDatabase d=open(target,SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                    d.beginTransaction();
                    try {
                        require(number(d,"SELECT count(*) FROM geller_file_table WHERE data_type='"+TYPE+"'")==0,"file_based_timeline_unsupported");
                        d.execSQL("DELETE FROM geller_key_table WHERE data_type<>?",new Object[]{TYPE});
                        d.execSQL("DELETE FROM geller_data_table WHERE _id NOT IN (SELECT data_id FROM geller_key_table)");
                        d.execSQL("DELETE FROM geller_metadata_table WHERE data_type<>?",new Object[]{TYPE});
                        d.execSQL("DELETE FROM geller_file_table");
                        d.execSQL("DELETE FROM geller_database_info_table");
                        d.setTransactionSuccessful();
                    } finally { d.endTransaction(); }
                    d.execSQL("VACUUM");
                }
            }
            integrity(target);
            inventory.put(FILES[i],new JSONObject().put("sha256",hash(target)).put("schema",schema(target)).put("bytes",target.length()).put("wal",live.wal[i]));
        }
        manifest.put("files",inventory);
        File marker=new File(out,"manifest.json");
        Files.write(marker.toPath(),manifest.toString(2).getBytes(StandardCharsets.UTF_8));
        Os.chmod(marker.getPath(),0600);
    }

    static JSONObject validate(Live live,File input,String binding) throws Exception {
        return validate(live,input,binding,false,null);
    }
    static String rowAccount(File file,String table) throws Exception {
        try(SQLiteDatabase d=open(file,RO); Cursor c=d.rawQuery("SELECT DISTINCT obfuscated_gaia_id FROM "+table,null)) {
            if(!c.moveToFirst())return null;
            String value=c.getString(0);
            require(value!=null && !value.isEmpty() && !c.moveToNext(),"cross_account_rows_ambiguous");
            return value;
        }
    }
    static JSONObject validateSnapshot(File input) throws Exception {
        File mf=new File(input,"manifest.json"); regular(mf);
        require(mf.length()<=32768,"manifest_too_large");
        JSONObject m=new JSONObject(new String(Files.readAllBytes(mf.toPath()),StandardCharsets.UTF_8));
        require(m.getInt("format")==1 && m.getInt("user")>=0 && m.getInt("uid")>=10000,"manifest_identity_mismatch");
        for(String name:FILES) {
            File f=new File(input,name);regular(f);
            JSONObject spec=m.getJSONObject("files").getJSONObject(name);
            require(f.length()==spec.getLong("bytes")&&hash(f).equals(spec.getString("sha256")),"snapshot_hash_mismatch");
            require(schema(f).equals(spec.getString("schema")),"snapshot_schema_mismatch");integrity(f);
        }
        return m;
    }
    static JSONObject validate(Live live,File input,String binding,boolean cross,String importGaia) throws Exception {
        JSONObject m=validateSnapshot(input);
        checkIncomingAuxiliary(live,input);
        if(!cross) {
            require(m.getInt("user")==live.user && m.getInt("uid")==live.uid,"manifest_identity_mismatch");
            require(binding.equals(m.getString("device")),"same_device_required");
        } else require(m.getBoolean("selective"),"cross_requires_selective_backup");
        require(digest(live.geller.getName().getBytes(StandardCharsets.UTF_8)).equals(m.getString("account")),"same_account_required");
        File[] targets=live.files();
        for(int i=0;i<FILES.length;i++) {
            File f=new File(input,FILES[i]); regular(f);
            require(schema(targets[i],cross && i==0).equals(schema(f,cross && i==0)),"snapshot_schema_mismatch_"+FILES[i].replace(".db",""));
        }
        if(cross) {
            String account=importGaia==null?rowAccount(live.odlh,"semantic_segment_table"):importGaia;
            if(importGaia!=null)require(GoogleAccountNames.select(live.user,m.getString("account")).gaia.equals(importGaia),"timeline_target_account_changed");
            require(account!=null && account.equals(rowAccount(new File(input,"odlh.db"),"semantic_segment_table")),"cross_row_account_mismatch");
            for(File folder:importGaia==null?Arrays.asList(input,live.odlh.getParentFile()):Arrays.asList(input)) {
                File odlh=folder.equals(input)?new File(input,"odlh.db"):live.odlh;
                File aux=folder.equals(input)?new File(input,"aux.db"):live.aux;
                String edited=rowAccount(odlh,"edited_segment_table"), auxiliary=rowAccount(aux,"aux_semantic_segment_table");
                require((edited==null || edited.equals(account)) && (auxiliary==null || auxiliary.equals(account)),"cross_row_account_mismatch");
            }
        }
        return m;
    }

    /** Mutates only the validated, root-private staged input. Original backup stays immutable. */
    static void prepareAccountImport(Live live,File input,String binding,GoogleAccountNames.Account target) throws Exception {
        JSONObject manifest=validateSnapshot(input);
        checkIncomingAuxiliary(live,input);
        require(manifest.getBoolean("selective"),"cross_requires_selective_backup");
        File[] targets=live.files();
        for(int i=0;i<FILES.length;i++)require(schema(targets[i],i==0).equals(schema(new File(input,FILES[i]),i==0)),"snapshot_schema_mismatch_"+FILES[i].replace(".db",""));
        String source=rowAccount(new File(input,"odlh.db"),"semantic_segment_table");
        require(source!=null,"timeline_history_not_initialized");
        for(String table:Arrays.asList("edited_segment_table","aux_semantic_segment_table")) {
            String account=rowAccount(new File(input,table.startsWith("aux")?"aux.db":"odlh.db"),table);
            require(account==null||account.equals(source),"cross_row_account_mismatch");
        }
        if(!source.equals(target.gaia)) {
            for(String name:Arrays.asList("odlh.db","aux.db"))try(SQLiteDatabase db=open(new File(input,name),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                db.beginTransaction();try {
                    String trigger=null;
                    if(name.equals("odlh.db")) {
                        trigger=scalar(db,"SELECT sql FROM sqlite_master WHERE type='trigger' AND name='semantic_segment_table_update_timestamp_millis_trigger'");
                        require(trigger!=null&&trigger.startsWith("CREATE TRIGGER"),"timeline_update_trigger_unsupported");
                        db.execSQL("DROP TRIGGER semantic_segment_table_update_timestamp_millis_trigger");
                    }
                    for(String table:name.equals("odlh.db")?new String[]{"semantic_segment_table","edited_segment_table"}:new String[]{"aux_semantic_segment_table"}) {
                        try(Cursor c=db.rawQuery("SELECT count(*) FROM "+table+" WHERE instr(semantic_segment,CAST(? AS BLOB))>0",new String[]{source})) {
                            c.moveToFirst();require(c.getLong(0)==0,"timeline_embedded_account_unsupported");
                        }
                        db.execSQL("UPDATE "+table+" SET obfuscated_gaia_id=? WHERE obfuscated_gaia_id=?",new Object[]{target.gaia,source});
                    }
                    if(trigger!=null)db.execSQL(trigger);
                    db.setTransactionSuccessful();
                } finally { db.endTransaction(); }
            }
            // Account-bound encrypted/sync payloads cannot be transplanted to another account.
            // Import the verified semantic history only; keep unrelated live Geller data untouched.
            clearImportGeller(input);
        }
        if(TimelineIdentity.rekeyConflicts(input,live.odlh,live.aux,target.gaia))clearImportGeller(input);
        Files.delete(new File(input,"manifest.json").toPath());
        finishBackup(live,input,binding,true);
        validate(live,input,binding,true,target.gaia);
    }

    private static void clearImportGeller(File input)throws Exception {
        try(SQLiteDatabase db=open(new File(input,"geller.db"),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            db.beginTransaction();try {
                for(String table:Arrays.asList("geller_key_table","geller_file_table","geller_data_table","geller_metadata_table","geller_database_info_table"))db.execSQL("DELETE FROM "+table);
                db.setTransactionSuccessful();
            }finally{db.endTransaction();}
            db.execSQL("VACUUM");
        }
    }
    static void attach(SQLiteDatabase d,File file,String alias) { d.execSQL("ATTACH DATABASE ? AS "+alias,new Object[]{file.getPath()}); }
    static void equalTable(SQLiteDatabase d,String a,String b,String table) throws Exception {
        require(number(d,"SELECT count(*) FROM (SELECT * FROM "+a+"."+table+" EXCEPT SELECT * FROM "+b+"."+table+")")==0,"restore_compare_failed");
        require(number(d,"SELECT count(*) FROM (SELECT * FROM "+b+"."+table+" EXCEPT SELECT * FROM "+a+"."+table+")")==0,"restore_compare_failed");
    }
    private static void equalRows(SQLiteDatabase d,String a,String b,String[] args,String reason) throws Exception {
        for(String sql:Arrays.asList("SELECT count(*) FROM ("+a+" EXCEPT "+b+")","SELECT count(*) FROM ("+b+" EXCEPT "+a+")"))
            try(Cursor c=d.rawQuery(sql,args)){c.moveToFirst();require(c.getLong(0)==0,reason);}
    }
    /** Replace only the selected account. _id is local storage identity; origin_id and payload stay intact. */
    private static void restoreAccountRows(SQLiteDatabase d,String database,String table,String gaia,int slot) throws Exception {
        String source="saved_"+database+"."+table, live=database+"."+table, prior="prior_"+database+"."+table;
        try(Cursor c=d.rawQuery("SELECT count(*) FROM "+source+" s JOIN "+live+" l ON l.segment_id=s.segment_id WHERE l.obfuscated_gaia_id IS NOT ?",new String[]{gaia})) {
            c.moveToFirst();require(c.getLong(0)==0,"timeline_segment_conflict_other_account");
        }
        String map="account_id_map_"+slot;
        long max;
        try(Cursor c=d.rawQuery("SELECT max(coalesce((SELECT max(_id) FROM "+live+" WHERE obfuscated_gaia_id IS NOT ?),0),coalesce((SELECT max(_id) FROM "+source+"),0))",new String[]{gaia})){c.moveToFirst();max=c.getLong(0);}
        long count=number(d,"SELECT count(*) FROM "+source);
        require(max>=0&&count>=0&&max<Long.MAX_VALUE-count,"data_id_overflow");
        d.execSQL("CREATE TEMP TABLE "+map+"(old_id INTEGER PRIMARY KEY,new_id INTEGER NOT NULL UNIQUE)");
        d.execSQL("INSERT INTO "+map+" SELECT s._id,?+row_number() OVER (ORDER BY s._id) FROM "+source+" s JOIN "+live+" l ON l._id=s._id WHERE l.obfuscated_gaia_id IS NOT ?",new Object[]{max,gaia});
        StringBuilder columns=new StringBuilder(),values=new StringBuilder();
        try(Cursor c=d.rawQuery("PRAGMA saved_"+database+".table_info("+table+")",null)) {
            while(c.moveToNext()) {
                String column=c.getString(1);require(column.matches("[a-z_]+"),"timeline_column_invalid");
                if(columns.length()>0){columns.append(',');values.append(',');}
                columns.append(column);
                values.append(column.equals("_id")?"coalesce((SELECT new_id FROM "+map+" WHERE old_id=s._id),s._id)":"s."+column);
            }
        }
        String expected="SELECT "+values+" FROM "+source+" s";
        d.execSQL("DELETE FROM "+live+" WHERE obfuscated_gaia_id=?",new Object[]{gaia});
        d.execSQL("INSERT INTO "+live+" ("+columns+") "+expected);
        equalRows(d,"SELECT * FROM "+live+" WHERE obfuscated_gaia_id=?",expected,new String[]{gaia},"restored_account_rows_mismatch");
        equalRows(d,"SELECT * FROM "+live+" WHERE obfuscated_gaia_id IS NOT ?","SELECT * FROM "+prior+" WHERE obfuscated_gaia_id IS NOT ?",new String[]{gaia,gaia},"other_account_rows_changed");
    }
    static void restore(Live live,File input,File rollback,String binding,Barrier guard) throws Exception {
        restore(live,input,rollback,binding,guard,false,null);
    }
    static void restore(Live live,File input,File rollback,String binding,Barrier guard,boolean cross,String importGaia) throws Exception {
        validate(live,input,binding,cross,importGaia); validate(live,rollback,binding); guard.check();live.checkAuxiliary();
        try(SQLiteDatabase d=open(live.geller,RW)) {
            attach(d,new File(input,"geller.db"),"incoming");
            attach(d,live.odlh,"odlh"); attach(d,live.aux,"aux");
            attach(d,new File(input,"odlh.db"),"saved_odlh"); attach(d,new File(input,"aux.db"),"saved_aux");
            // Recovery reads the same snapshot as both input and baseline. Attaching
            // a rollback-journal file twice makes SQLite lock against itself.
            String prior=input.getCanonicalFile().equals(rollback.getCanonicalFile())?"incoming":"prior";
            if(prior.equals("prior"))attach(d,new File(rollback,"geller.db"),prior);
            if(importGaia!=null) {
                attach(d,new File(rollback,"odlh.db"),"prior_odlh");
                attach(d,new File(rollback,"aux.db"),"prior_aux");
            }
            d.beginTransaction();
            try {
                require(number(d,"SELECT count(*) FROM incoming.geller_file_table WHERE data_type='"+TYPE+"'")==0,"file_based_timeline_unsupported");
                require(number(d,"SELECT count(*) FROM incoming.geller_key_table k LEFT JOIN incoming.geller_data_table b ON b._id=k.data_id WHERE k.data_type='"+TYPE+"' AND b._id IS NULL")==0,"snapshot_missing_payload");
                long count=number(d,"SELECT count(*) FROM incoming.geller_data_table");
                long max=number(d,"SELECT coalesce(max(_id),0) FROM main.geller_data_table");
                require(max>=0 && count>=0 && max<Long.MAX_VALUE-count,"data_id_overflow");
                d.execSQL("CREATE TEMP TABLE old_ids AS SELECT DISTINCT data_id FROM main.geller_key_table WHERE data_type='"+TYPE+"'");
                d.execSQL("CREATE TEMP TABLE id_map(old_id INTEGER PRIMARY KEY,new_id INTEGER NOT NULL UNIQUE)");
                d.execSQL("INSERT INTO id_map SELECT _id,?+row_number() OVER (ORDER BY _id) FROM incoming.geller_data_table WHERE _id IN (SELECT data_id FROM incoming.geller_key_table WHERE data_type=?)",new Object[]{max,TYPE});
                d.execSQL("INSERT INTO main.geller_data_table SELECT m.new_id,b.data FROM incoming.geller_data_table b JOIN id_map m ON m.old_id=b._id");
                d.execSQL("DELETE FROM main.geller_key_table WHERE data_type=?",new Object[]{TYPE});
                d.execSQL("INSERT INTO main.geller_key_table SELECT k.data_type,k.key,k.timestamp_micro,k.sync_status,k.delete_status,k.num_times_used,k.deletion_sync_status,m.new_id FROM incoming.geller_key_table k JOIN id_map m ON m.old_id=k.data_id WHERE k.data_type=?",new Object[]{TYPE});
                d.execSQL("DELETE FROM main.geller_data_table WHERE _id IN (SELECT data_id FROM old_ids) AND NOT EXISTS (SELECT 1 FROM main.geller_key_table k WHERE k.data_id=main.geller_data_table._id)");
                d.execSQL("DELETE FROM main.geller_metadata_table WHERE data_type=?",new Object[]{TYPE});
                d.execSQL("INSERT INTO main.geller_metadata_table SELECT * FROM incoming.geller_metadata_table WHERE data_type=?",new Object[]{TYPE});
                if(importGaia!=null) {
                    restoreAccountRows(d,"odlh","semantic_segment_table",importGaia,0);
                    restoreAccountRows(d,"odlh","edited_segment_table",importGaia,1);
                    restoreAccountRows(d,"aux","aux_semantic_segment_table",importGaia,2);
                    // Shared sync ranges must be rebuilt after replacing a subset; keep global metadata.
                    d.execSQL("DELETE FROM odlh.geller_sync_status");
                    equalTable(d,"odlh","prior_odlh","geller_metadata");
                } else {
                    // Rollback/recovery must restore the entire captured state, including every account.
                    for(String table:ODLH) { d.execSQL("DELETE FROM odlh."+table); d.execSQL("INSERT INTO odlh."+table+" SELECT * FROM saved_odlh."+table); equalTable(d,"odlh","saved_odlh",table); }
                    for(String table:AUX) { d.execSQL("DELETE FROM aux."+table); d.execSQL("INSERT INTO aux."+table+" SELECT * FROM saved_aux."+table); equalTable(d,"aux","saved_aux",table); }
                }
                for(String table:Arrays.asList("android_metadata","geller_file_table","geller_database_info_table")) equalTable(d,"main",prior,table);
                for(String side:Arrays.asList("main",prior)) {
                    String other=side.equals("main")?prior:"main";
                    require(number(d,"SELECT count(*) FROM (SELECT *,count(*) AS copies FROM "+side+".geller_key_table WHERE data_type<>'"+TYPE+"' GROUP BY 1,2,3,4,5,6,7,8 EXCEPT SELECT *,count(*) FROM "+other+".geller_key_table WHERE data_type<>'"+TYPE+"' GROUP BY 1,2,3,4,5,6,7,8)")==0,"unrelated_keys_changed");
                    require(number(d,"SELECT count(*) FROM (SELECT *,count(*) AS copies FROM "+side+".geller_metadata_table WHERE data_type<>'"+TYPE+"' GROUP BY 1,2,3 EXCEPT SELECT *,count(*) FROM "+other+".geller_metadata_table WHERE data_type<>'"+TYPE+"' GROUP BY 1,2,3)")==0,"unrelated_metadata_changed");
                }
                require(number(d,"SELECT count(*) FROM "+prior+".geller_data_table p WHERE p._id IN (SELECT data_id FROM "+prior+".geller_key_table WHERE data_type<>'"+TYPE+"') AND NOT EXISTS (SELECT 1 FROM main.geller_data_table b WHERE b._id=p._id AND b.data=p.data)")==0,"unrelated_payload_changed");
                require(number(d,"SELECT count(*) FROM incoming.geller_data_table p JOIN id_map m ON m.old_id=p._id WHERE NOT EXISTS (SELECT 1 FROM main.geller_data_table b WHERE b._id=m.new_id AND b.data=p.data)")==0,"restored_payload_mismatch");
                require(number(d,"SELECT count(*) FROM pragma_foreign_key_check")==0,"restored_foreign_key_failed");
                guard.check(); d.setTransactionSuccessful();
            } finally { d.endTransaction(); }
        }
        guard.check();
        for(File file:live.files()) integrity(file);
        restoreModes(live,null);
        guard.check();
    }
}
