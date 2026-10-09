package com.xayah.dex;

import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Display cache. The live account DB is accessed only through ordinary file reads/stat. */
final class GoogleAccountCache {
    private static final long MAX_BYTES=16*1024*1024, TTL_MS=24*60*60_000L;
    private static final String[] SUFFIXES={"","-wal","-journal"};

    private static void need(boolean ok,String code) throws Exception { TimelineDatabase.require(ok,code); }
    private static void privateDirectory(File root) throws Exception {
        need(Os.getuid()==0,"account_cache_requires_root");
        try { Files.createDirectory(root.toPath(),PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------"))); }
        catch(java.nio.file.FileAlreadyExistsException ignored) { }
        StructStat s=Os.lstat(root.getPath());
        need(OsConstants.S_ISDIR(s.st_mode)&&s.st_uid==0&&(s.st_mode&0777)==0700,"account_cache_directory_invalid");
    }
    private static String stamp(File file,boolean required) throws Exception {
        StructStat s;
        try { s=Os.lstat(file.getPath()); }
        catch(android.system.ErrnoException e) {
            if(!required&&e.errno==OsConstants.ENOENT)return "absent";
            throw e;
        }
        need(OsConstants.S_ISREG(s.st_mode)&&s.st_size<=MAX_BYTES,"account_source_invalid");
        return s.st_dev+":"+s.st_ino+":"+s.st_size+":"+s.st_ctime+":"+
            Files.getLastModifiedTime(file.toPath(),LinkOption.NOFOLLOW_LINKS).toString();
    }
    private static String signature(File source) throws Exception {
        StringBuilder out=new StringBuilder(source.getAbsolutePath());
        for(String suffix:SUFFIXES)out.append('|').append(stamp(new File(source+suffix),suffix.isEmpty()));
        // Do not try to recover a live rollback transaction from an unlocked copy.
        need(new File(source+"-journal").length()==0,"account_source_busy");
        return out.toString();
    }
    private static void privateFile(File file) throws Exception {
        StructStat s=Os.lstat(file.getPath());
        need(OsConstants.S_ISREG(s.st_mode)&&s.st_uid==0&&(s.st_mode&0777)==0600&&s.st_size<=65536,"account_cache_file_invalid");
    }
    private static List<GoogleAccountNames.Account> cached(File file,String key,int user) {
        try {
            privateFile(file);
            JSONObject saved=new JSONObject(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));
            long age=System.currentTimeMillis()-saved.getLong("created");
            if(saved.getInt("format")!=1||saved.getInt("user")!=user||age<0||age>TTL_MS||!key.equals(saved.getString("source")))return null;
            JSONArray rows=saved.getJSONArray("accounts");need(rows.length()<=32,"account_cache_count_invalid");
            List<GoogleAccountNames.Account> result=new ArrayList<>();
            for(int i=0;i<rows.length();i++)result.add(new GoogleAccountNames.Account(rows.getJSONObject(i)));
            return result;
        } catch(Exception ignored) { return null; }
    }
    private static void save(File cache,String key,int user,List<GoogleAccountNames.Account> rows) throws Exception {
        JSONArray accounts=new JSONArray();
        for(GoogleAccountNames.Account a:rows)accounts.put(new JSONObject().put("selector",a.selector).put("gaia",a.gaia).put("label",a.label));
        JSONObject data=new JSONObject().put("format",1).put("user",user).put("created",System.currentTimeMillis()).put("source",key).put("accounts",accounts);
        File temp=Files.createTempFile(cache.getParentFile().toPath(),"cache-",".tmp",
            PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"))).toFile();
        try {
            Files.write(temp.toPath(),data.toString().getBytes(StandardCharsets.UTF_8));
            Files.move(temp.toPath(),cache.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(temp.toPath()); }
    }
    static synchronized List<GoogleAccountNames.Account> read(File source,File root,int user,boolean fresh) throws Exception {
        privateDirectory(root);
        String key=signature(source);File cache=new File(root,"u"+user+".json");
        if(!fresh) {
            List<GoogleAccountNames.Account> hit=cached(cache,key,user);
            if(hit!=null&&key.equals(signature(source)))return hit;
        }
        File work=Files.createTempDirectory(root.toPath(),"snapshot-",
            PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------"))).toFile();
        try {
            File copy=new File(work,"accounts.db");
            // Never copy SHM. SQLite rebuilds the WAL index in this private directory.
            for(String suffix:new String[]{"","-wal"}) {
                File from=new File(source+suffix),to=new File(copy+suffix);
                if(!from.exists()) { need(!suffix.isEmpty(),"account_source_missing");continue; }
                Files.createFile(to.toPath(),PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
                try(java.io.InputStream in=Files.newInputStream(from.toPath());java.io.OutputStream out=Files.newOutputStream(to.toPath())) {
                    byte[] buffer=new byte[8192];int n;long total=0;
                    try { while((n=in.read(buffer))!=-1) { total+=n;need(total<=MAX_BYTES,"account_source_too_large");out.write(buffer,0,n); } }
                    finally { java.util.Arrays.fill(buffer,(byte)0); }
                }
            }
            // An unlocked copy is not an atomic SQLite backup. Reject observed changes,
            // including equal-size WAL updates, before opening even the private copy.
            need(key.equals(signature(source)),"account_source_changed");
            for(String suffix:new String[]{"","-wal"}) {
                File from=new File(source+suffix),to=new File(copy+suffix);
                need(from.exists()==to.exists(),"account_source_changed");
                if(to.exists())need(TimelineDatabase.hash(from).equals(TimelineDatabase.hash(to)),"account_source_changed");
            }
            need(key.equals(signature(source)),"account_source_changed");
            List<GoogleAccountNames.Account> result=GoogleAccountNames.queryCopy(copy);
            need(key.equals(signature(source)),"account_source_changed");
            need(result.size()<=32,"account_cache_count_invalid");
            // Cache failure must not prevent use of a successfully validated fresh read.
            try { save(cache,key,user,result); } catch(Exception ignored) { }
            return result;
        } finally {
            // Only unlink children of our newly created, root-only snapshot directory.
            File[] files=work.listFiles();
            if(files!=null)for(File file:files)Files.deleteIfExists(file.toPath());
            Files.deleteIfExists(work.toPath());
        }
    }
}
