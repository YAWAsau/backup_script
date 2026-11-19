package com.xayah.dex;

import java.io.*;
import java.nio.channels.*;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.*;

/** Serializes network-policy snapshots/mutations across root daemon processes. */
final class UidPolicyLock implements AutoCloseable {
    private final List<FileChannel> channels;
    private UidPolicyLock(List<FileChannel> channels) { this.channels=channels; }
    static UidPolicyLock acquire(int uid) throws Exception {
        if (uid < 0 || android.os.Process.myUid()!=0) throw new IOException("uid policy lock requires root/valid uid");
        List<FileChannel> channels=new ArrayList<>();
        try {
            File root=directory(new File("/data/.speedbackup"),0711,true);
            File base=directory(new File(root,"tmp"),0700,true);
            File dir=directory(new File(base,".uid_policy_locks"),0700,true);
            acquireFile(dir,uid,channels);
            // Compatibility for live jobs only; never create either legacy directory.
            // Arbitrary old binaries started after offline retirement are unsupported.
            File oldRoot=new File("/data/.speedbackup_tmp");
            if (exists(oldRoot)) {
                directory(oldRoot,0700,false);
                File oldDir=new File(oldRoot,".uid_policy_locks");
                if (exists(oldDir)) acquireFile(directory(oldDir,0700,false),uid,channels);
            }
            return new UidPolicyLock(channels);
        } catch(Exception e) {
            for(FileChannel ch:channels)try{ch.close();}catch(Exception close){e.addSuppressed(close);}
            throw e;
        }
    }
    private static boolean exists(File file)throws Exception {
        try {android.system.Os.lstat(file.getPath());return true;}
        catch(android.system.ErrnoException e) {
            if(e.errno==android.system.OsConstants.ENOENT)return false;
            throw e;
        }
    }
    private static void acquireFile(File dir,int uid,List<FileChannel> channels)throws Exception {
        Set<OpenOption> options=new HashSet<>(Arrays.asList(StandardOpenOption.CREATE,StandardOpenOption.READ,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS));
        File file=new File(dir,"uid-"+uid+".lock");
        FileChannel ch=FileChannel.open(file.toPath(),options,PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
        channels.add(ch);
        android.system.StructStat stat=android.system.Os.lstat(file.getPath());
        if(!android.system.OsConstants.S_ISREG(stat.st_mode)||stat.st_uid!=0||stat.st_nlink!=1||(stat.st_mode&07777)!=0600)
            throw new IOException("unsafe uid policy lock");
        if(ch.tryLock()==null)throw new IOException("uid policy transaction busy");
    }
    private static File directory(File dir,int mode,boolean create)throws Exception {
        if(create) {
            String permissions=mode==0711?"rwx--x--x":"rwx------";
            try {Files.createDirectory(dir.toPath(),PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString(permissions)));}
            catch(FileAlreadyExistsException ignored){}
        }
        android.system.StructStat stat=android.system.Os.lstat(dir.getPath());
        if(!dir.getCanonicalFile().equals(dir)||!android.system.OsConstants.S_ISDIR(stat.st_mode)||stat.st_uid!=0||(stat.st_mode&07777)!=mode)
            throw new IOException("unsafe uid policy directory");
        return dir;
    }
    static List<File> pendingStateFiles(File current)throws Exception {
        Set<File> dirs=new HashSet<>();dirs.add(current.getCanonicalFile());
        for(String base:new String[]{"/data/.speedbackup/tmp","/data/.speedbackup_tmp","/data/local/tmp"}) {
            File parent=new File(base);if(!parent.exists())continue;
            File[] runs=parent.listFiles((d,n)->n.startsWith(".speedbackup_run_"));
            if(runs==null)throw new IOException("uid ownership directory unavailable");
            for(File run:runs){
                android.system.StructStat stat=android.system.Os.lstat(run.getPath());
                if(!android.system.OsConstants.S_ISDIR(stat.st_mode)||stat.st_uid!=0||(stat.st_mode&0077)!=0)continue;
                File states=new File(run,".speedbackup_uid_netblock_state");
                if(Files.exists(states.toPath(),LinkOption.NOFOLLOW_LINKS)) {
                    if(!states.getCanonicalFile().equals(states)||!states.isDirectory())throw new IOException("unsafe uid state directory");
                    dirs.add(states);
                }
            }
        }
        List<File> files=new ArrayList<>();
        for(File dir:dirs){File[] rows=dir.listFiles();if(rows==null)throw new IOException("uid state unavailable");Collections.addAll(files,rows);}
        return files;
    }
    public void close()throws IOException {
        IOException failure=null;
        for(FileChannel ch:channels)try{ch.close();}catch(IOException e){
            if(failure==null)failure=e;else failure.addSuppressed(e);
        }
        if(failure!=null)throw failure;
        // Never unlink the lock inode: another process may already have it open.
    }
}
