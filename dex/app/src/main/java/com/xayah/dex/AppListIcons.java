package com.xayah.dex;
import android.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
/** Optional backup-only batch over the existing root native APK controller. No Activity launch. */
public final class AppListIcons {
 public static void main(String[] args){ System.exit(run(args,System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET"))); }
 static int run(String[] args,String origin){
  if((args.length!=3&&args.length!=4)||!args[0].matches("[0-9]{1,5}"))return 2;
  if(origin==null||origin.length()>90)return 0;
  ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"icon-budget");t.setDaemon(true);return t;});
  long budget=args.length==4&&args[3].equals("refresh")?30000:5000;
  long deadline=android.os.SystemClock.elapsedRealtime()+budget;
  java.util.concurrent.atomic.AtomicReference<LocalSocket> active=new java.util.concurrent.atomic.AtomicReference<>();
  timer.schedule(()->{LocalSocket socket=active.get();if(socket!=null)try{socket.close();}catch(IOException ignored){}},budget,TimeUnit.MILLISECONDS);
  try{
   LinkedHashSet<String> names=new LinkedHashSet<>();
   try(BufferedReader input=new BufferedReader(new FileReader(args[1]))){String line;while((line=input.readLine())!=null&&names.size()<5000){if(line.length()<=255&&line.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+"))names.add(line);}}
   ArrayList<String> all=new ArrayList<>(names);File directory=new File(args[2]);
   if(!directory.isDirectory()||!directory.getCanonicalPath().equals(directory.getAbsolutePath()))throw new IOException("icon directory");
   for(int offset=0;offset<all.size();offset+=20){
    if(android.os.SystemClock.elapsedRealtime()>=deadline)return 124;
    List<String> batch=all.subList(offset,Math.min(offset+20,all.size()));
    try(LocalSocket socket=new LocalSocket()){
     active.set(socket);
     if(android.os.SystemClock.elapsedRealtime()>=deadline)return 124;
     socket.connect(new LocalSocketAddress(origin+".icons",LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(1500);
     if(socket.getPeerCredentials().getUid()!=0)throw new SecurityException("icon peer");
     socket.getOutputStream().write(("ICONS\t"+args[0]+"\t"+String.join("\t",batch)+"\n").getBytes(StandardCharsets.US_ASCII));
     ByteArrayOutputStream response=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;
     while((n=socket.getInputStream().read(buffer))!=-1){response.write(buffer,0,n);if(response.size()>3*1024*1024)throw new IOException("icon limit");}
     String reply=response.toString("US-ASCII").trim();if(!reply.startsWith("ICONS\t"))throw new IOException("icon protocol");
     for(String row:reply.substring(6).split(";")){
      int pos=row.indexOf(':');if(pos<1)continue;String pkg=row.substring(0,pos),value=row.substring(pos+1);
      if(!batch.contains(pkg)||value.length()>43692||!value.startsWith("iVBORw0KGgo"))continue;
      File target=new File(directory,pkg+".b64");
      if(target.exists())continue;
      File tmp=new File(directory,pkg+".part");
      try(FileOutputStream file=new FileOutputStream(tmp)){file.write(value.getBytes(StandardCharsets.US_ASCII));}
      if(!tmp.renameTo(target))tmp.delete();
     }
    }catch(IOException e){System.err.println("BACKUP_ICON_BATCH_SKIP "+e.getClass().getSimpleName());}
   }
  }catch(Exception e){System.err.println("BACKUP_ICON_OPTIONAL "+e.getClass().getSimpleName());}
  finally{timer.shutdownNow();}
  return 0;
 }
}
