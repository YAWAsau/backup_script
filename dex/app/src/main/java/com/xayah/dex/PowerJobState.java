package com.xayah.dex;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

/** Completion preparation is deliberately separate from the later countdown. */
final class PowerJobState {
    static String collectExtras(File run,String extras,String pidFiles)throws Exception {
        StringBuilder result=new StringBuilder(extras.equals("-")?"":extras);
        if(!pidFiles.equals("-"))for(String raw:pidFiles.split(",")){
            File f=GuardLifecycle.child(run,raw);
            if(!f.exists())continue;
            // Run pid files are not credentials; legacy writers can use 0644.
            // Their private parent and root ownership still prevent substitution.
            PowerNotifyUtil.secure(run,true);
            android.system.StructStat st=android.system.Os.lstat(f.getPath());
            if(st.st_uid!=0 || !android.system.OsConstants.S_ISREG(st.st_mode)
                    || (st.st_mode&0022)!=0 || st.st_size>64)throw new IOException("pid file");
            String pid=new String(Files.readAllBytes(f.toPath()),StandardCharsets.UTF_8).trim();
            if(!pid.matches("[1-9][0-9]*"))throw new IOException("pid file");
            if(result.length()>0)result.append(',');result.append(pid);
        }
        return result.length()==0?"-":result.toString();
    }
    static String snapshot(File dir,String ownerRaw,String extras)throws Exception {
        int owner=Integer.parseInt(ownerRaw);if(owner<=1||!new File("/proc/"+owner).isDirectory())throw new IOException("owner");
        Map<Integer,Integer> parents=new HashMap<>();File[] entries=new File("/proc").listFiles();if(entries==null)throw new IOException("proc");
        for(File f:entries)if(f.getName().matches("[1-9][0-9]*"))try{
            String stat=new String(Files.readAllBytes(new File(f,"stat").toPath()),StandardCharsets.UTF_8);
            String[] fields=stat.substring(stat.lastIndexOf(')')+2).split(" +");parents.put(Integer.parseInt(f.getName()),Integer.parseInt(fields[1]));
        }catch(IOException|NumberFormatException ignored){}
        Set<Integer> workers=new TreeSet<>();int self=android.os.Process.myPid();
        for(int pid:parents.keySet()){
            int q=pid;boolean child=false,own=false;
            for(int i=0;i<100&&parents.containsKey(q);i++){
                if(q==self){own=true;break;}
                int parent=parents.get(q);if(parent==owner){child=true;break;}if(parent==q)break;q=parent;
            }
            if(child&&!own&&pid!=self)workers.add(pid);
        }
        if(!extras.equals("-"))for(String p:extras.split(",")){int pid=Integer.parseInt(p);if(pid<=1||pid==owner)throw new IOException("extra pid");workers.add(pid);}
        StringBuilder out=new StringBuilder();for(int pid:workers)out.append(pid).append('\n');
        PowerNotifyUtil.write(new File(dir,"workers"),out.toString());return "WORKERS_READY";
    }
    static String ready(File dir,String base,String requestedOrigin,String rcRaw)throws Exception {
        if(!base.equals(PowerNotifyUtil.origin(requestedOrigin)))throw new IOException("origin");
        int rc=Integer.parseInt(rcRaw);String outcome=rc==0?"success":rc==130||rc==137||rc==143?"cancelled":"failed";
        if(outcome.equals("success")&&new File(dir,"issues").exists())outcome="partial";
        PowerNotifyUtil.write(new File(dir,"ready"),outcome+"\n");return "READY";
    }
}
