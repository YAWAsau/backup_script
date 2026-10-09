package com.xayah.dex;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;
import org.json.*;

/** A bounded, indexed collection of independently validated format-1 snapshots. */
final class TimelineCollection {
    static final String INDEX="accounts.json";
    static void require(boolean ok,String why)throws IOException { TimelineDatabase.require(ok,why); }
    static JSONObject index(ZipFile zip)throws Exception {
        ZipEntry entry=zip.getEntry(INDEX);
        if(entry==null)return null;
        require(entry.getSize()>0&&entry.getSize()<=32768,"timeline_collection_index_invalid");
        byte[] bytes=new byte[(int)entry.getSize()];
        try(DataInputStream in=new DataInputStream(zip.getInputStream(entry))){in.readFully(bytes);require(in.read()==-1,"timeline_collection_index_invalid");}
        JSONObject root=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
        require(root.getInt("format")==2,"timeline_collection_format_invalid");
        JSONArray accounts=root.getJSONArray("accounts");
        require(accounts.length()>0&&accounts.length()<=32,"timeline_collection_count_invalid");
        Set<String> expected=new HashSet<>();expected.add(INDEX);
        for(int i=0;i<accounts.length();i++){
            JSONObject a=accounts.getJSONObject(i);String id=a.getString("selector");
            require(id.matches("[a-f0-9]{64}")&&expected.add(id+".sbtimeline"),"timeline_collection_account_invalid");
            require(a.getLong("bytes")>0&&a.getString("sha256").matches("[a-f0-9]{64}"),"timeline_collection_item_invalid");
            ZipEntry item=zip.getEntry(id+".sbtimeline");
            require(item!=null&&item.getSize()==a.getLong("bytes"),"timeline_collection_size_mismatch");
        }
        Set<String> actual=new HashSet<>();Enumeration<? extends ZipEntry> entries=zip.entries();
        while(entries.hasMoreElements()){ZipEntry e=entries.nextElement();require(!e.isDirectory()&&actual.add(e.getName())&&expected.contains(e.getName()),"timeline_collection_entry_invalid");}
        require(actual.equals(expected),"timeline_collection_incomplete");return root;
    }
    static String sources(File file)throws Exception {
        try(ZipFile zip=new ZipFile(file)){
            JSONObject root=index(zip);if(root==null)return "";
            StringBuilder out=new StringBuilder();JSONArray accounts=root.getJSONArray("accounts");
            for(int i=0;i<accounts.length();i++){JSONObject a=accounts.getJSONObject(i);out.append(a.getString("selector")).append('\t').append(GoogleAccountNames.clean(a.optString("display_name","來源帳號名稱未知"))).append('\n');}
            return out.toString();
        }
    }
    static File select(File source,File work,String selected)throws Exception {
        try(ZipFile zip=new ZipFile(source)){
            JSONObject root=index(zip);if(root==null)return source;
            JSONArray accounts=root.getJSONArray("accounts");JSONObject chosen=null;
            for(int i=0;i<accounts.length();i++){JSONObject a=accounts.getJSONObject(i);if(a.getString("selector").equals(selected)||((selected==null||selected.isEmpty())&&accounts.length()==1))chosen=a;}
            require(chosen!=null,"timeline_source_selection_required");
            long expected=chosen.getLong("bytes");require(expected<work.getUsableSpace(),"timeline_archive_space_insufficient");
            File target=new File(work,"selected.sbtimeline");require(!target.exists(),"snapshot_exists");
            try(InputStream in=zip.getInputStream(zip.getEntry(chosen.getString("selector")+".sbtimeline"));FileOutputStream out=new FileOutputStream(target)){
                android.system.Os.chmod(target.getPath(),0600);byte[] b=new byte[65536];long total=0;int n;
                while((n=in.read(b))!=-1){total+=n;require(total<=expected,"timeline_archive_size_exceeded");out.write(b,0,n);}require(total==expected,"timeline_archive_size_mismatch");
            }
            require(TimelineDatabase.hash(target).equals(chosen.getString("sha256")),"snapshot_hash_mismatch");return target;
        }
    }
    static long publish(File work,File destination,List<GoogleAccountNames.Account> accounts)throws Exception {
        require(!destination.exists(),"backup_destination_exists");JSONArray list=new JSONArray();
        for(GoogleAccountNames.Account a:accounts){File p=part(work,a.selector);list.put(new JSONObject().put("selector",a.selector).put("display_name",GoogleAccountNames.label(a)).put("bytes",p.length()).put("sha256",TimelineDatabase.hash(p)));}
        byte[] indexBytes=new JSONObject().put("format",2).put("accounts",list).toString().getBytes(StandardCharsets.UTF_8);
        File tmp=Files.createTempFile(destination.getAbsoluteFile().getParentFile().toPath(),".timeline-",".partial").toFile();
        try{
            android.system.Os.chmod(tmp.getPath(),0600);
            try(FileOutputStream output=new FileOutputStream(tmp);ZipOutputStream zip=new ZipOutputStream(output)){
                zip.setLevel(0);zip.putNextEntry(new ZipEntry(INDEX));zip.write(indexBytes);zip.closeEntry();
                for(GoogleAccountNames.Account a:accounts){zip.putNextEntry(new ZipEntry(a.selector+".sbtimeline"));Files.copy(part(work,a.selector).toPath(),zip);zip.closeEntry();}
                zip.finish();zip.flush();output.getFD().sync();
            }
            require(tmp.renameTo(destination),"backup_publish_failed");
            // Inner archives already report their source bytes; count only the
            // collection's new index, not a second copy of the compressed parts.
            return indexBytes.length;
        }finally{Files.deleteIfExists(tmp.toPath());}
    }
    static File part(File work,String selector){return new File(work,"part-"+selector+".sbtimeline");}
    static void cleanup(File work)throws Exception {
        File[] files=work.listFiles();if(files==null)return;
        for(File f:files)if(f.getName().equals("selected.sbtimeline")||f.getName().matches("part-[a-f0-9]{64}\\.sbtimeline")){
            require(!Files.isSymbolicLink(f.toPath())&&f.isFile(),"timeline_collection_cleanup_invalid");Files.deleteIfExists(f.toPath());
        }
    }
}
