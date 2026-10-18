package com.xayah.dex;

import java.io.*;
import java.nio.channels.*;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.*;

/** Serializes network-policy snapshots/mutations across root daemon processes. */
final class UidPolicyLock implements AutoCloseable {
    private final FileChannel channel;
    private final FileLock lock;
    private UidPolicyLock(FileChannel channel, FileLock lock) { this.channel=channel; this.lock=lock; }
    static UidPolicyLock acquire(int uid) throws Exception {
        if (uid < 0 || android.os.Process.myUid()!=0) throw new IOException("uid policy lock requires root/valid uid");
        File base=privateDirectory(new File("/data/.speedbackup_tmp"));
        File dir=privateDirectory(new File(base,".uid_policy_locks"));
        Set<OpenOption> options=new HashSet<>(Arrays.asList(StandardOpenOption.CREATE,StandardOpenOption.READ,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS));
        File file=new File(dir,"uid-"+uid+".lock");
        FileChannel ch=FileChannel.open(file.toPath(),options,PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
        try {
            android.system.StructStat stat=android.system.Os.lstat(file.getPath());
            if(!android.system.OsConstants.S_ISREG(stat.st_mode)||stat.st_uid!=0||(stat.st_mode&0077)!=0)throw new IOException("unsafe uid policy lock");
            FileLock lock=ch.tryLock();
            if(lock==null)throw new IOException("uid policy transaction busy");
            return new UidPolicyLock(ch,lock);
        } catch(Exception e) { ch.close();throw e; }
    }
    private static File privateDirectory(File dir)throws Exception {
        try {Files.createDirectory(dir.toPath(),PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")));}
        catch(FileAlreadyExistsException ignored){}
        android.system.StructStat stat=android.system.Os.lstat(dir.getPath());
        if(!dir.getCanonicalFile().equals(dir)||!android.system.OsConstants.S_ISDIR(stat.st_mode)||stat.st_uid!=0||(stat.st_mode&0077)!=0)
            throw new IOException("unsafe uid policy directory");
        return dir;
    }
    static List<File> pendingStateFiles(File current)throws Exception {
        Set<File> dirs=new HashSet<>();dirs.add(current.getCanonicalFile());
        for(String base:new String[]{"/data/.speedbackup_tmp","/data/local/tmp"}) {
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
        try{lock.release();}finally{channel.close();}
        // Never unlink the lock inode: another process may already have it open.
    }
}
