package com.xayah.dex;

import android.content.ContentResolver;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import java.io.*;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** A root-only, commit-scoped lease. The durable setting is never left disabled. */
public final class InstallAutoRestoreGuard {
    private static Session active;
    private static final class Session {
        final int user,owner;final String identity;final long deadline;
        final Lease lease;final RandomAccessFile file;final FileLock lock;
        Session(int user,int owner,Lease lease,RandomAccessFile file,FileLock lock) {
            this.user=user;this.owner=owner;this.identity=processIdentity(owner);
            this.lease=lease;this.file=file;this.lock=lock;
            deadline=System.nanoTime()+TimeUnit.MINUTES.toNanos(10);
        }
        void close()throws Exception {try{lease.close();}finally{try{lock.release();}finally{file.close();}}}
    }
    static synchronized String daemon(String[] args) {
        int user=-1,owner=-1;
        try {
            if(android.os.Process.myUid()!=0||args.length!=3)throw new IOException("arguments");
            user=Integer.parseInt(args[1]);owner=Integer.parseInt(args[2]);
            if(user<0||owner<=1)throw new IOException("scope");
            if(args[0].equals("installAutoRestoreEnd")) {
                if(active!=null) {
                    if(active.user!=user||active.owner!=owner)throw new IOException("owner mismatch");
                    Session s=active;active=null;s.close();
                } else {
                    File dir=new File("/data/adb/speedbackup-install-guard"),journal=new File(dir,"user-"+user+".journal");
                    if(journal.exists()) {
                        if(!dir.getCanonicalFile().equals(dir)||!journal.getCanonicalFile().equals(journal))throw new IOException("path");
                        File lf=new File(dir,"user-"+user+".lock");if(!lf.getCanonicalFile().equals(lf))throw new IOException("path");
                        try(RandomAccessFile f=new RandomAccessFile(lf,"rw");FileLock l=f.getChannel().tryLock()) {
                            if(l==null)throw new IOException("busy");
                            new Lease(new AndroidBackend(user),journal).recover();
                        }
                    }
                }
                return new OperationResult("install-auto-restore",true).token(owner).appendTo("INSTALL_AUTO_RESTORE restored=true\n");
            }
            if(!args[0].equals("installAutoRestoreBegin")||active!=null||processIdentity(owner).isEmpty())throw new IOException("busy or owner");
            File dir=new File("/data/adb/speedbackup-install-guard");
            if(!dir.getCanonicalFile().equals(dir)||(!dir.isDirectory()&&!dir.mkdir()))throw new IOException("store");
            android.system.Os.chmod(dir.getPath(),0700);
            File lf=new File(dir,"user-"+user+".lock"),jf=new File(dir,"user-"+user+".journal");
            if(!lf.getCanonicalFile().equals(lf)||!jf.getCanonicalFile().equals(jf))throw new IOException("path");
            RandomAccessFile f=new RandomAccessFile(lf,"rw");FileLock lock=null;Lease lease=null;
            try {
                lock=f.getChannel().tryLock();if(lock==null)throw new IOException("busy");
                android.system.Os.chmod(lf.getPath(),0600);
                lease=new Lease(new AndroidBackend(user),jf);
                lease.begin();active=new Session(user,owner,lease,f,lock);
            }catch(Exception e){try{if(lease!=null)lease.close();}finally{try{if(lock!=null)lock.release();}finally{f.close();}}throw e;}
            final Session session=active;
            Thread watch=new Thread(()->{
                while(true) {
                    try{Thread.sleep(250);}catch(InterruptedException ignored){}
                    synchronized(InstallAutoRestoreGuard.class) {
                        if(active!=session)return;
                        if(session.identity.isEmpty()||!session.identity.equals(processIdentity(session.owner))||System.nanoTime()>session.deadline){
                            active=null;try{session.close();}catch(Exception e){System.err.println("INSTALL_AUTO_RESTORE recovery=pending");}return;
                        }
                    }
                }
            },"install-auto-restore-watch");watch.setDaemon(true);watch.start();
            return new OperationResult("install-auto-restore",true).token(owner).appendTo("INSTALL_AUTO_RESTORE begin paused="+lease.dirty+" durableOriginal=true\n");
        }catch(Exception e){return new OperationResult("install-auto-restore",false).token(owner).appendTo("INSTALL_AUTO_RESTORE unavailable="+e.getClass().getSimpleName()+"\n");}
    }
    static {
        Runtime.getRuntime().addShutdownHook(new Thread(()->{
            synchronized(InstallAutoRestoreGuard.class){if(active!=null){try{active.close();}catch(Exception ignored){}active=null;}}
        },"install-auto-restore-exit"));
    }
    interface Backend {
        String read() throws Exception;
        void live(boolean enabled) throws Exception;
        void persist(String value) throws Exception;
    }
    static final class Lease implements AutoCloseable {
        final Backend backend;
        final File journal;
        String original;
        boolean dirty;
        Lease(Backend backend,File journal) { this.backend=backend;this.journal=journal; }
        synchronized void recover() throws Exception {
            if(!journal.exists())return;
            String value=new String(Files.readAllBytes(journal.toPath()),StandardCharsets.UTF_8).trim();
            if(!Arrays.asList("null","0","1").contains(value))throw new IOException("journal");
            original=value.equals("null")?null:value;dirty=true;close();
        }
        synchronized void begin() throws Exception {
            recover();original=backend.read();
            if(original!=null&&!original.equals("0")&&!original.equals("1"))throw new IOException("setting");
            if("0".equals(original))return;
            try(FileOutputStream out=new FileOutputStream(journal)) {
                out.write((original==null?"null":original).getBytes(StandardCharsets.UTF_8));out.getFD().sync();
            }
            dirty=true;
            try {
                backend.live(false);
                if(!"0".equals(backend.read()))throw new IOException("pause not confirmed");
                // BackupManager caches its runtime switch. Restore the durable value now:
                // reboot/service restart must re-enable the user's original policy.
                backend.persist(original);
                if(!Objects.equals(original,backend.read()))throw new IOException("durable restore");
            } catch(Exception e) { close();throw e; }
        }
        public synchronized void close() throws Exception {
            if(!dirty)return;
            backend.live(!"0".equals(original));
            backend.persist(original);
            if(!Objects.equals(original,backend.read()))throw new IOException("restore not confirmed");
            Files.deleteIfExists(journal.toPath());dirty=false;
        }
    }
    static final class AndroidBackend implements Backend {
        final int user;final ContentResolver resolver;final Object service;
        AndroidBackend(int user)throws Exception {
            if(!HiddenApiBypassBridge.installExemptionsOnce())throw new IOException("hidden api");
            this.user=user;
            resolver=new FakeContext(HiddenApiHelper.getContext(),true,user,false).getContentResolver();
            IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"backup");
            if(binder==null)throw new IOException("backup service");
            service=Class.forName("android.app.backup.IBackupManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
        }
        Bundle extras(){Bundle b=new Bundle();b.putInt("_user",user);return b;}
        public String read(){Bundle b=resolver.call(Uri.parse("content://settings"),"GET_secure","backup_auto_restore",extras());if(b==null)throw new IllegalStateException("settings");return b.getString("value");}
        public void persist(String value){Bundle b=extras();b.putString("value",value);resolver.call(Uri.parse("content://settings"),"PUT_secure","backup_auto_restore",b);}
        public void live(boolean enabled)throws Exception {
            try { service.getClass().getMethod("setAutoRestoreForUser",int.class,boolean.class).invoke(service,user,enabled); }
            catch(NoSuchMethodException e) {
                if(user!=0)throw e;
                service.getClass().getMethod("setAutoRestore",boolean.class).invoke(service,enabled);
            }
        }
    }
    static String processIdentity(int pid) {
        try {
            String s=new String(Files.readAllBytes(Paths.get("/proc/"+pid+"/stat")),StandardCharsets.UTF_8);
            String[] f=s.substring(s.lastIndexOf(')')+2).split(" +");
            return f[0].equals("Z")?"":f[19];
        }catch(Exception e){return "";}
    }
}
