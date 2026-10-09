package com.xayah.dex;

import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import org.json.JSONObject;
import org.json.JSONArray;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.HashSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/** Maps-attached Timeline operations. Personal snapshots never enter diagnostic output. */
public final class TimelineUtil {
    private static final File ROOT=new File("/data/.speedbackup_timeline");
    private static final String PKG="com.google.android.gms";
    private static final long DEADLINE_MS=30000;
    private static void need(boolean value,String reason) throws IOException { TimelineDatabase.require(value,reason); }
    private static String read(File file) throws IOException { return new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8).trim(); }
    private static void privateDir(File directory) throws Exception {
        if(!directory.exists()) need(directory.mkdir(),"private_directory_create_failed");
        android.system.StructStat s=Os.lstat(directory.getPath());
        need(OsConstants.S_ISDIR(s.st_mode) && s.st_uid==0,"private_directory_owner_invalid");
        Os.chmod(directory.getPath(),0700);
    }
    private static void durable(File path,String data) throws Exception {
        File temp=new File(path.getParentFile(),path.getName()+".new");
        try(FileOutputStream out=new FileOutputStream(temp,false)) {
            Os.chmod(temp.getPath(),0600); out.write(data.getBytes(StandardCharsets.UTF_8)); out.getFD().sync();
        }
        Os.rename(temp.getPath(),path.getPath());
        java.io.FileDescriptor dir=Os.open(path.getParent(),OsConstants.O_RDONLY,0);
        try { need(OsConstants.S_ISDIR(Os.fstat(dir).st_mode),"journal_parent_invalid"); Os.fsync(dir); } finally { Os.close(dir); }
    }
    private static String identity(int pid) {
        try {
            String value=read(new File("/proc/"+pid+"/stat"));
            String[] fields=value.substring(value.lastIndexOf(')')+2).split(" +");
            if(fields[0].equals("Z") || fields[0].equals("X")) return "";
            return fields[19];
        } catch(Exception e) { return ""; }
    }
    private static void lease() throws Exception {
        String token=System.getenv("SPEEDBACKUP_TIMELINE_LEASE");
        need(token!=null && token.equals(read(new File("/data/.backup_lock/owner"))),"backup_lease_required");
        String[] fields=token.split(":",-1);
        need(fields.length==3 && fields[1].equals(identity(Integer.parseInt(fields[0])))
                && fields[2].equals(read(new File("/proc/sys/kernel/random/boot_id"))),"backup_lease_stale");
    }
    private static ProcessBuilder self(File work,String... arguments) {
        List<String> command=new ArrayList<>(Arrays.asList("/system/bin/app_process","/system/bin",TimelineUtil.class.getName()));
        command.addAll(Arrays.asList(arguments));
        ProcessBuilder builder=new ProcessBuilder(command);
        builder.environment().put("SPEEDBACKUP_RUN_TMPDIR",work.getPath());
        builder.environment().put("SPEEDBACKUP_CGROUP_FREEZER_STATE_FILE",new File(work,"freeze.state").getPath());
        builder.environment().put("SPEEDBACKUP_CGROUP_FREEZER_SOCKET",new File(work,"cg.sock").getPath());
        return builder;
    }
    private static String binding() throws Exception {
        Process p=new ProcessBuilder("/system/bin/getprop","ro.serialno").start();
        need(p.waitFor(3,TimeUnit.SECONDS) && p.exitValue()==0,"device_identity_unavailable");
        byte[] bytes=new byte[1024]; int size=p.getInputStream().read(bytes);
        String serial=size>0?new String(bytes,0,size,StandardCharsets.UTF_8).trim():"";
        need(!serial.isEmpty() && !serial.equals("unknown"),"device_identity_unavailable");
        return TimelineDatabase.digest((serial+"\n"+android.os.Build.FINGERPRINT).getBytes(StandardCharsets.UTF_8));
    }
    private static File pending(int user) { return new File(ROOT,"pending-"+user+".json"); }
    private static void removePending(File marker) throws Exception {
        Files.deleteIfExists(marker.toPath());
        java.io.FileDescriptor directory=Os.open(ROOT.getPath(),OsConstants.O_RDONLY,0);
        try { Os.fsync(directory); } finally { Os.close(directory); }
    }
    private static File ownedWork(String path) throws Exception {
        File work=new File(path);
        need(work.getCanonicalFile().getParentFile().equals(ROOT.getCanonicalFile()) && work.getName().startsWith("run-"),"invalid_work_directory");
        privateDir(work); return work;
    }
    private static File stageInput(File source,File work) throws Exception {
        File target=new File(work,"input"); privateDir(target);
        for(String name:Arrays.asList("odlh.db","aux.db","geller.db","manifest.json")) {
            File file=new File(source,name); TimelineDatabase.regular(file);
            Files.copy(file.toPath(),new File(target,name).toPath()); Os.chmod(new File(target,name).getPath(),0600);
        }
        return target;
    }
    private static final List<String> ARCHIVE_FILES=Arrays.asList("manifest.json","odlh.db","aux.db","geller.db");
    private static long publishArchive(File source,File destination) throws Exception {
        need(!destination.exists(),"backup_destination_exists");
        File parent=destination.getAbsoluteFile().getParentFile();
        need(parent!=null && parent.isDirectory(),"backup_parent_missing");
        File temp=Files.createTempFile(parent.toPath(),".timeline-",".partial").toFile();
        long inputBytes=0;
        try {
            Os.chmod(temp.getPath(),0600);
            try(FileOutputStream output=new FileOutputStream(temp); ZipOutputStream zip=new ZipOutputStream(output)) {
                zip.setLevel(1);
                for(String name:ARCHIVE_FILES) {
                    zip.putNextEntry(new ZipEntry(name)); inputBytes=Math.addExact(inputBytes,Files.copy(new File(source,name).toPath(),zip)); zip.closeEntry();
                }
                zip.finish(); zip.flush(); output.getFD().sync();
            }
            need(temp.renameTo(destination),"backup_publish_failed");
            return inputBytes;
        } finally { Files.deleteIfExists(temp.toPath()); }
    }
    private static File stageArchive(File source,File work) throws Exception {
        TimelineDatabase.regular(source);
        File target=new File(work,"input"); privateDir(target);
        HashSet<String> seen=new HashSet<>(); JSONObject inventory=null;
        try(ZipInputStream zip=new ZipInputStream(Files.newInputStream(source.toPath()))) {
            ZipEntry entry; byte[] buffer=new byte[65536];
            while((entry=zip.getNextEntry())!=null) {
                String name=entry.getName();
                need(!entry.isDirectory() && ARCHIVE_FILES.contains(name) && seen.add(name),"timeline_archive_entry_invalid");
                need(inventory!=null || name.equals("manifest.json"),"timeline_archive_manifest_first");
                long limit=name.equals("manifest.json")?32768:inventory.getJSONObject(name).getLong("bytes");
                need(limit>0 && limit<target.getUsableSpace(),"timeline_archive_space_insufficient");
                File file=new File(target,name); long written=0;
                try(FileOutputStream output=new FileOutputStream(file)) {
                    Os.chmod(file.getPath(),0600); int n;
                    while((n=zip.read(buffer))!=-1) { written+=n; need(written<=limit,"timeline_archive_size_exceeded"); output.write(buffer,0,n); }
                    output.getFD().sync();
                }
                zip.closeEntry();
                if(name.equals("manifest.json")) {
                    inventory=new JSONObject(read(file)).getJSONObject("files");
                    long required=67108864;
                    for(String db:TimelineDatabase.FILES) {
                        long bytes=inventory.getJSONObject(db).getLong("bytes");
                        need(bytes>0 && bytes<target.getUsableSpace() && required<Long.MAX_VALUE-bytes,"timeline_archive_space_insufficient"); required+=bytes;
                    }
                    need(required<target.getUsableSpace(),"timeline_archive_space_insufficient");
                } else need(written==limit,"timeline_archive_size_mismatch");
            }
            need(seen.size()==4,"timeline_archive_incomplete"); return target;
        } catch(Exception failure) { discardTransient(work,"input"); throw failure; }
    }
    private static void discardTransient(File work,String name) throws Exception {
        need(name.equals("input")||name.equals("capture")||name.equals("rollback")||name.equals("auxiliary"),"transient_name_invalid");
        File directory=new File(work,name);
        if(!directory.exists()) return;
        need(directory.getCanonicalFile().getParentFile().equals(work.getCanonicalFile())
                && !Files.isSymbolicLink(directory.toPath()),"transient_directory_invalid");
        File[] entries=directory.listFiles(); need(entries!=null,"transient_list_failed");
        for(File file:entries) {
            need(file.getName().matches("(odlh|aux|geller)\\.db(-wal|-shm|-journal)?|manifest\\.json"),"transient_unknown_file");
            need(!file.isDirectory(),"transient_nested_directory");
        }
        for(File file:entries) Files.deleteIfExists(file.toPath());
        Files.deleteIfExists(directory.toPath());
    }
    private static void publish(File source,File destination) throws Exception {
        need(!destination.exists(),"backup_destination_exists");
        File parent=destination.getAbsoluteFile().getParentFile();
        need(parent!=null && parent.isDirectory(),"backup_parent_missing");
        File temp=Files.createTempDirectory(parent.toPath(),".timeline-").toFile();
        for(String name:Arrays.asList("odlh.db","aux.db","geller.db","manifest.json")) {
            File src=new File(source,name), dst=new File(temp,name);
            Files.copy(src.toPath(),dst.toPath());
            need(TimelineDatabase.hash(src).equals(TimelineDatabase.hash(dst)),"backup_publish_hash_failed");
            try(FileOutputStream out=new FileOutputStream(dst,true)) { out.getFD().sync(); }
        }
        need(temp.renameTo(destination),"backup_publish_failed");
    }
    private static void restart(int user) throws Exception {
        for(String pkg:Arrays.asList("com.google.android.apps.maps",PKG)) {
            Process p=new ProcessBuilder("/system/bin/am","force-stop","--user",Integer.toString(user),pkg)
                    .redirectOutput(new File("/dev/null")).redirectError(new File("/dev/null")).start();
            if(!p.waitFor(5,TimeUnit.SECONDS)) { p.destroyForcibly(); throw new IOException("service_restart_timeout"); }
            need(p.exitValue()==0,"service_restart_failed");
        }
    }
    private static void saveBaseline(File work,int uid) throws Exception {
        File root=new File("/sys/fs/cgroup/apps/uid_"+uid);
        need(read(new File(root,"cgroup.freeze")).equals("0"),"uid_scope_already_frozen");
        JSONArray list=new JSONArray(); File[] dirs=root.listFiles(); need(dirs!=null,"uid_scope_unavailable");
        for(File dir:dirs) {
            if(!dir.getName().matches("pid_[0-9]+")) continue;
            int pid=Integer.parseInt(dir.getName().substring(4)); String start=identity(pid);
            if(start.isEmpty()) continue;
            File path=new File(dir,"cgroup.freeze"); String value=read(path);
            need(value.equals("0")||value.equals("1"),"pid_freeze_state_invalid");
            list.put(new JSONObject().put("pid",pid).put("start",start).put("path",path.getPath()).put("before",value));
        }
        durable(new File(work,"baseline.json"),new JSONObject().put("uid",uid).put("pids",list).toString());
    }
    private static void restoreBaseline(File work) throws Exception {
        JSONObject saved=new JSONObject(read(new File(work,"baseline.json")));
        int uid=saved.getInt("uid"); String prefix="/sys/fs/cgroup/apps/uid_"+uid+"/";
        File root=new File(prefix+"cgroup.freeze");
        if(root.exists()) Files.write(root.toPath(),"0\n".getBytes(StandardCharsets.US_ASCII));
        String helper=CgroupFreezeUtil.nativeHelperPath(); need(helper!=null,"native_freezer_missing");
        JSONArray list=saved.getJSONArray("pids");
        for(int i=0;i<list.length();i++) {
            JSONObject item=list.getJSONObject(i); int pid=item.getInt("pid");
            if(!item.getString("start").equals(identity(pid))) continue;
            String path=item.getString("path");
            need(path.equals(prefix+"pid_"+pid+"/cgroup.freeze"),"baseline_path_invalid");
            Process p=new ProcessBuilder(helper,"thaw-pid",Integer.toString(pid),path,item.getString("before"),"1000")
                    .redirectOutput(new File("/dev/null")).redirectError(new File("/dev/null")).start();
            if(!p.waitFor(3,TimeUnit.SECONDS)) { p.destroyForcibly(); throw new IOException("baseline_restore_timeout"); }
            need(p.exitValue()==0,"baseline_restore_failed");
        }
    }
    private static boolean recoverAfterRelease(File work,int user) throws Exception {
        // An old frozen GMS connection can retain a read lock required by hot
        // journal recovery. Release/restart it, then use a fresh guarded session.
        restart(user);
        String token=System.getenv("SPEEDBACKUP_TIMELINE_LEASE"); boolean owned=false;
        String helper=CgroupFreezeUtil.nativeHelperPath();
        need(helper!=null,"native_freezer_missing");
        File scanner=new File(new File(helper).getParentFile(),"speedscan");
        try { lease(); }
        catch(Exception staleLease) {
            Process acquire=new ProcessBuilder(scanner.getPath(),"lock-acquire","/data/.backup_lock",Integer.toString(android.os.Process.myPid()))
                    .redirectError(new File(work,"recovery-lock.log")).start();
            if(!acquire.waitFor(3,TimeUnit.SECONDS) || acquire.exitValue()!=0) return false;
            byte[] bytes=new byte[512]; int length=acquire.getInputStream().read(bytes);
            need(length>0,"recovery_lease_missing");
            token=new String(bytes,0,length,StandardCharsets.UTF_8).trim(); owned=true;
        }
        try {
            ProcessBuilder command=self(work,"recover",Integer.toString(user));
            command.environment().put("SPEEDBACKUP_TIMELINE_LEASE",token);
            Process recovery=command.redirectOutput(new File(work,"recovery.log")).redirectErrorStream(true).start();
            if(!recovery.waitFor(45,TimeUnit.SECONDS)) { recovery.destroyForcibly(); return false; }
            return recovery.exitValue()==0 && !pending(user).exists();
        } finally {
            if(owned) {
                Process release=new ProcessBuilder(scanner.getPath(),"lock-release","/data/.backup_lock",token)
                        .redirectOutput(new File("/dev/null")).redirectError(new File("/dev/null")).start();
                release.waitFor(3,TimeUnit.SECONDS);
            }
        }
    }
    private static final class Scope implements AutoCloseable,TimelineDatabase.Barrier {
        final File work; final int user,uid; int token=-1,watcherPid=-1; String watcherIdentity="";
        Scope(File work,int user,int uid) throws Exception {
            this.work=work; this.user=user; this.uid=uid;
            saveBaseline(work,uid);
            Files.deleteIfExists(new File(work,"released").toPath());
            Files.deleteIfExists(new File(work,"ready").toPath());
            int pid=android.os.Process.myPid();
            durable(new File(work,"armed"),"1");
            // Double-fork through a short-lived shell. The bounded watcher must survive
            // the existing lock-stop command terminating the controller's process tree.
            ProcessBuilder launch=self(work);
            launch.command("/system/bin/sh","-c","/system/bin/app_process /system/bin com.xayah.dex.TimelineUtil watchdog \"$SB_TL_WORK\" \"$SB_TL_PID\" \"$SB_TL_START\" \"$SB_TL_USER\" \"$SB_TL_UID\" </dev/null >\"$SB_TL_WORK/watchdog.log\" 2>&1 &");
            launch.environment().put("SB_TL_WORK",work.getPath());
            launch.environment().put("SB_TL_PID",Integer.toString(pid));
            launch.environment().put("SB_TL_START",identity(pid));
            launch.environment().put("SB_TL_USER",Integer.toString(user));
            launch.environment().put("SB_TL_UID",Integer.toString(uid));
            Process starter=launch.start();
            need(starter.waitFor(3,TimeUnit.SECONDS) && starter.exitValue()==0,"watchdog_launch_failed");
            long until=SystemClock.elapsedRealtime()+5000;
            while(!new File(work,"ready").exists() && SystemClock.elapsedRealtime()<until) Thread.sleep(20);
            if(!new File(work,"ready").exists()) { Files.deleteIfExists(new File(work,"armed").toPath()); throw new IOException("watchdog_not_ready"); }
            JSONObject ready=new JSONObject(read(new File(work,"ready")));
            watcherPid=ready.getInt("pid"); watcherIdentity=ready.getString("identity");
            try { token=CgroupFreezeUtil.startTimelineScope(user,uid); check(); }
            catch(Exception e) { close(); throw e; }
        }
        public void check() throws Exception {
            need(!watcherIdentity.isEmpty() && watcherIdentity.equals(identity(watcherPid)) && new File(work,"armed").exists(),"timeline_guard_expired");
            CgroupFreezeUtil.checkTimelineScope(token,user,uid);
        }
        public void close() throws Exception {
            if(token>=0) {
                need(OperationResult.isOk(CgroupFreezeUtil.stop(token,user,PKG),"cgroup-stop"),"timeline_thaw_failed");
                token=-1;
            }
            Files.deleteIfExists(new File(work,"armed").toPath());
            long until=SystemClock.elapsedRealtime()+5000;
            while(!watcherIdentity.isEmpty() && watcherIdentity.equals(identity(watcherPid)) && SystemClock.elapsedRealtime()<until) Thread.sleep(20);
            need(watcherIdentity.isEmpty() || !watcherIdentity.equals(identity(watcherPid)),"watchdog_cleanup_pending");
        }
    }
    private static void watchdog(String[] args) throws Exception {
        File work=ownedWork(args[1]);
        int pid=Integer.parseInt(args[2]), user=Integer.parseInt(args[4]); String owner=args[3];
        need(!owner.isEmpty() && owner.equals(identity(pid)),"watchdog_owner_invalid");
        int watcherPid=android.os.Process.myPid();
        durable(new File(work,"ready"),new JSONObject().put("pid",watcherPid).put("identity",identity(watcherPid)).toString());
        long until=SystemClock.elapsedRealtime()+DEADLINE_MS;
        while(new File(work,"armed").exists() && owner.equals(identity(pid)) && SystemClock.elapsedRealtime()<until) Thread.sleep(100);
        if(!new File(work,"armed").exists()) return;
        if(owner.equals(identity(pid))) Os.kill(pid,OsConstants.SIGKILL);
        long reap=SystemClock.elapsedRealtime()+3000;
        while(owner.equals(identity(pid)) && SystemClock.elapsedRealtime()<reap) Thread.sleep(20);
        // Stop this scope's native workers before replaying release state, so no
        // in-flight helper can freeze another PID after cleanup has finished.
        try { CgroupFreezeUtil.runNativeDaemonCommand("STOP",2500); } catch(Exception ignored) {}
        boolean rolledBack=false,needsRecovery=false;
        File marker=pending(user);
        try {
            if(marker.isFile() && work.getPath().equals(new JSONObject(read(marker)).getString("work"))) {
                needsRecovery=true;
                File rollback=new File(work,"rollback");
                TimelineDatabase.Live live=new TimelineDatabase.Live(user,true,snapshotManifest(rollback).getString("account"),work);
                TimelineDatabase.Barrier stillFrozen=()->need(read(new File("/sys/fs/cgroup/apps/uid_"+live.uid+"/cgroup.events")).contains("frozen 1"),"watchdog_scope_missing");
                TimelineDatabase.restore(live,rollback,rollback,binding(),stillFrozen);
                TimelineDatabase.restoreModes(live,rollback);
                rolledBack=true;
                System.err.println("TIMELINE_WATCHDOG_ROLLBACK_OK");
            }
        } catch(Exception failure) { System.err.println("TIMELINE_WATCHDOG_RECOVERY_PENDING reason="+failure.getClass().getSimpleName()); }
        // Persistent scope replay also covers a worker dying before its token is returned.
        String result="";
        try { result=CgroupFreezeUtil.restorePersistedPackage(user,PKG,"timeline-watchdog"); }
        finally { restoreBaseline(work); }
        System.err.println("TIMELINE_WATCHDOG_THAW="+OperationResult.isOk(result,"cgroup-restore-package"));
        if(rolledBack && OperationResult.isOk(result,"cgroup-restore-package")) {
            restart(user); removePending(marker);
        } else if(needsRecovery && OperationResult.isOk(result,"cgroup-restore-package")) {
            if(recoverAfterRelease(work,user)) {
                rolledBack=true;
                System.err.println("TIMELINE_WATCHDOG_ROLLBACK_OK method=fresh_scope");
            }
        }
        // Failed recovery retains the prepared journal for the next controller invocation.
        durable(new File(work,"released"),"watchdog");
        Files.deleteIfExists(new File(work,"armed").toPath());
        discardTransient(work,"capture"); discardTransient(work,"input");
    }
    private static JSONObject snapshotManifest(File input) throws Exception {
        File manifest=new File(input,"manifest.json");
        TimelineDatabase.regular(manifest);
        need(manifest.length()<=32768,"manifest_too_large");
        JSONObject result=new JSONObject(read(manifest));
        need(result.getString("account").matches("[a-f0-9]{64}"),"account_selector_invalid");
        return result;
    }
    private static void worker(String[] args) throws Exception {
        String operation=args[1]; int user=Integer.parseInt(args[2]);
        File work=ownedWork(args[4]); lease();
        File marker=pending(user);
        if(marker.isFile()) {
            File previous=ownedWork(new JSONObject(read(marker)).getString("work"));
            if(new File(previous,"completed").isFile()) removePending(marker);
        }
        need(!operation.equals("recover") || marker.isFile(),"timeline_no_pending_recovery");
        need(!marker.exists() || operation.equals("recover"),"timeline_pending_recovery_required");
        boolean archiveBackup=operation.equals("backup-archive"), archiveRestore=operation.equals("restore-archive")||operation.equals("check-archive");
        if(archiveBackup) {
            File odlh=new File("/data/user/"+user+"/com.google.android.gms/databases/odlh-storage.db");
            if(!odlh.exists()) { System.err.println("TIMELINE_BACKUP_ABSENT"); return; }
            boolean empty;
            try(android.database.sqlite.SQLiteDatabase db=TimelineDatabase.open(odlh,TimelineDatabase.RO)) {
                empty=TimelineDatabase.number(db,"SELECT count(*) FROM semantic_segment_table")==0;
            } finally { TimelineDatabase.fixSidecars(odlh); }
            if(empty) { System.err.println("TIMELINE_BACKUP_ABSENT"); return; }
        }
        if(archiveBackup) {
            List<GoogleAccountNames.Account> accounts=GoogleAccountNames.histories(user);
            if(accounts.size()>1) {
                try {
                    long inputBytes=0;
                    for(GoogleAccountNames.Account account:accounts) {
                        TimelineDatabase.Live source=new TimelineDatabase.Live(user,false,account.selector,work);
                        File capture=new File(work,"capture");privateDir(capture);
                        try(Scope guard=new Scope(work,user,source.uid)){TimelineDatabase.capture(source,capture,guard);}
                        TimelineDatabase.filterAccount(capture,account.gaia);
                        TimelineDatabase.finishBackup(source,capture,binding(),true);
                        inputBytes=Math.addExact(inputBytes,publishArchive(capture,TimelineCollection.part(work,account.selector)));
                        discardTransient(work,"capture");
                    }
                    inputBytes=Math.addExact(inputBytes,TimelineCollection.publish(work,new File(args[3]),accounts));
                    System.out.println("SBRESULT\t1\ttimeline-backup-bytes\t"+inputBytes+"\t"+new File(args[3]).length());
                    DiagnosticInfo.write("TIMELINE_BACKUP_OK accounts="+accounts.size());return;
                }finally{TimelineCollection.cleanup(work);}
            }
        }
        boolean captureOperation=archiveBackup || operation.equals("backup") || operation.equals("probe");
        TimelineDatabase.Live live=null;
        if(captureOperation) {
            GoogleAccountNames.Account source=GoogleAccountNames.history(user);
            String selected=System.getenv("SPEEDBACKUP_TIMELINE_ACCOUNT_SHA256");
            need(selected==null||selected.isEmpty()||selected.equals(source.selector),"timeline_source_account_mismatch");
            live=new TimelineDatabase.Live(user,false,source.selector,work);
        }
        String device=binding();
        boolean cross=operation.equals("restore-cross");
        if(operation.equals("probe")) {
            System.err.println("TIMELINE_SUPPORTED user="+user+" crossDeviceSameAccount=true"); return;
        }
        if(operation.equals("backup") || archiveBackup) {
            File capture=new File(work,"capture"); privateDir(capture);
            try(Scope guard=new Scope(work,user,live.uid)) { TimelineDatabase.capture(live,capture,guard); }
            TimelineDatabase.finishBackup(live,capture,device,true);
            if(archiveBackup) {
                long inputBytes=publishArchive(capture,new File(args[3]));
                System.out.println("SBRESULT\t1\ttimeline-backup-bytes\t"+inputBytes+"\t"+new File(args[3]).length());
            } else publish(capture,new File(args[3]));
            discardTransient(work,"capture"); DiagnosticInfo.write("TIMELINE_BACKUP_OK"); return;
        }
        File input;
        if(operation.equals("recover")) {
            need(marker.isFile(),"timeline_no_pending_recovery");
            JSONObject journal=new JSONObject(read(marker));
            input=new File(ownedWork(journal.getString("work")),"rollback");
        } else {
            need(operation.equals("restore") || cross || archiveRestore,"timeline_command_invalid");
            input=archiveRestore?stageArchive(TimelineCollection.select(new File(args[3]),work,System.getenv("SPEEDBACKUP_TIMELINE_SOURCE_SHA256")),work):stageInput(new File(args[3]),work);
        }
        String importGaia=null;
        try {
            JSONObject manifest=snapshotManifest(input);
            if(archiveRestore) {
                String selectedSource=System.getenv("SPEEDBACKUP_TIMELINE_SOURCE_SHA256");
                need(selectedSource==null||selectedSource.isEmpty()||selectedSource.equals(manifest.getString("account")),"timeline_source_account_mismatch");
                GoogleAccountNames.Account target=GoogleAccountNames.select(user,System.getenv("SPEEDBACKUP_TIMELINE_ACCOUNT_SHA256"));
                live=new TimelineDatabase.Live(user,false,target.selector,work);
                TimelineDatabase.validateSnapshot(input);
                System.out.println("此時間軸來自「"+GoogleAccountNames.sourceLabel(user,input,manifest)+"」，將匯入至「"+GoogleAccountNames.label(target)+"」的時間軸。");
                TimelineDatabase.prepareAccountImport(live,input,device,target);
                cross=true; importGaia=target.gaia;
            } else {
                live=new TimelineDatabase.Live(user,operation.equals("recover"),manifest.getString("account"),work);
            }
            TimelineDatabase.validate(live,input,device,cross,importGaia);
        }
        catch(Exception invalid) { if(!operation.equals("recover")) discardTransient(work,"input"); throw invalid; }
        if(operation.equals("check-archive")) {
            discardTransient(work,"input");
            System.err.println("TIMELINE_RESTORE_PREFLIGHT_OK");return;
        }
        File rollback=new File(work,"rollback"); privateDir(rollback);
        boolean succeeded=false,rolledBack=false;
        try(Scope guard=new Scope(work,user,live.uid)) {
            TimelineDatabase.capture(live,rollback,guard);
            TimelineDatabase.finishBackup(live,rollback,device,false);
            if(!operation.equals("recover")) durable(marker,new JSONObject().put("work",work.getPath()).put("user",user).put("phase","prepared").toString());
            try {
                TimelineDatabase.restore(live,input,rollback,device,guard,cross,importGaia);
                if(operation.equals("recover")) TimelineDatabase.restoreModes(live,input);
                succeeded=true;
            } catch(Exception failure) {
                String detail=failure instanceof IOException && failure.getMessage()!=null && failure.getMessage().matches("[a-z_]+")?failure.getMessage():failure.getClass().getSimpleName();
                System.err.println("TIMELINE_WRITE_FAILED reason="+detail);
                for(StackTraceElement frame:failure.getStackTrace())System.err.println("TIMELINE_FRAME "+frame);
                // Rollback to the immediate pre-write state while the same UID scope is held.
                TimelineDatabase.restore(live,rollback,rollback,device,guard);
                rolledBack=true;
            }
        }
        if(succeeded || rolledBack) {
            restart(user);
            durable(new File(work,"completed"),"1");
            durable(marker,new JSONObject().put("work",work.getPath()).put("user",user).put("phase","completed").toString());
            removePending(marker);
            if(!operation.equals("recover")) discardTransient(work,"input");
            // The durable completion marker supersedes rollback only after recovery
            // has finished and the pending journal has been removed.
            discardTransient(work,"rollback");
            need(!rolledBack,"timeline_restore_failed_rolled_back");
            System.err.println(operation.equals("recover")?"TIMELINE_RECOVERY_OK":"TIMELINE_RESTORE_OK");
        }
    }
    private static void pruneCompletedRuns() {
        try {
            File[] entries=ROOT.listFiles(); if(entries==null)return;
            java.util.Set<String> protectedRuns=new java.util.HashSet<>();
            for(File file:entries) if(file.getName().matches("pending-[0-9]+\\.json")) protectedRuns.add(new File(new JSONObject(read(file)).getString("work")).getCanonicalPath());
            long cutoff=System.currentTimeMillis()-86400000L;
            for(File directory:entries) {
                if(!directory.getName().startsWith("run-") || Files.isSymbolicLink(directory.toPath()))continue;
                if(protectedRuns.contains(directory.getCanonicalPath()) || new File(directory,"armed").exists())continue;
                File finished=new File(directory,"finished");
                if(!finished.isFile() || finished.lastModified()>=cutoff)continue;
                privateDir(directory);
                Files.walkFileTree(directory.toPath(),new java.nio.file.SimpleFileVisitor<java.nio.file.Path>() {
                    @Override public java.nio.file.FileVisitResult visitFile(java.nio.file.Path file,java.nio.file.attribute.BasicFileAttributes attrs) throws IOException { Files.delete(file); return java.nio.file.FileVisitResult.CONTINUE; }
                    @Override public java.nio.file.FileVisitResult postVisitDirectory(java.nio.file.Path dir,IOException failure) throws IOException { if(failure!=null)throw failure; Files.delete(dir); return java.nio.file.FileVisitResult.CONTINUE; }
                });
            }
        } catch(Exception ignored) { /* Never remove unverified recovery state. */ }
    }
    public static void main(String[] args) {
        int rc=1;
        try {
            need(android.os.Process.myUid()==0,"root_required");
            HiddenApiBypassBridge.installExemptionsOnce();
            if(args.length==3&&args[0].equals("sources")) {
                System.out.print(TimelineCollection.sources(new File(args[2])));System.exit(0);return;
            }
            if(args.length==2&&args[0].equals("accounts")) {
                System.out.print(GoogleAccountNames.fields(Integer.parseInt(args[1])));System.exit(0);return;
            }
            privateDir(ROOT);
            if(args.length==6 && args[0].equals("watchdog")) { watchdog(args); rc=0; }
            else if(args.length==5 && args[0].equals("worker")) { worker(args); rc=0; }
            else {
                need(args.length==2 || args.length==3,"timeline_arguments_invalid");
                String operation=args[0]; int user=Integer.parseInt(args[1]);
                need(Arrays.asList("probe","backup","backup-archive","restore","restore-cross","restore-archive","check-archive","recover").contains(operation),"timeline_command_invalid");
                need((operation.equals("backup")||operation.equals("backup-archive")||operation.equals("restore")||operation.equals("restore-cross")||operation.equals("restore-archive")||operation.equals("check-archive"))== (args.length==3),"timeline_arguments_invalid");
                lease();
                File lock=new File(ROOT,"controller.lock");
                File retryRecovery=null;
                try(FileChannel channel=FileChannel.open(lock.toPath(),StandardOpenOption.CREATE,StandardOpenOption.WRITE); FileLock held=channel.tryLock()) {
                    need(held!=null,"timeline_controller_busy");
                    pruneCompletedRuns();
                    File work=Files.createTempDirectory(ROOT.toPath(),"run-").toFile(); privateDir(work);
                    Process child=self(work,"worker",operation,Integer.toString(user),args.length==3?args[2]:"-",work.getPath()).inheritIO().start();
                    rc=child.waitFor();
                    if(rc!=0 && !operation.equals("recover") && pending(user).isFile() && !new File(work,"armed").exists()) {
                        JSONObject journal=new JSONObject(read(pending(user)));
                        if(work.getPath().equals(journal.getString("work")) && "prepared".equals(journal.optString("phase")))retryRecovery=work;
                    }
                    if(!pending(user).exists() && !new File(work,"armed").exists()) {
                        // A rejected/preparation-failed operation has no live transaction
                        // to recover. Do not retain private database copies indefinitely.
                        discardTransient(work,"capture");
                        discardTransient(work,"input");
                        discardTransient(work,"rollback");
                        discardTransient(work,"auxiliary");
                        TimelineCollection.cleanup(work);
                        durable(new File(work,"finished"),Integer.toString(rc));
                    }
                }
                // A live GMS connection can retain SQLite locks even while frozen.
                // Retry rollback once after releasing the controller lock and restarting GMS.
                if(retryRecovery!=null) {
                    boolean recovered=recoverAfterRelease(retryRecovery,user);
                    System.err.println(recovered?"TIMELINE_ROLLBACK_OK method=fresh_scope":"TIMELINE_RECOVERY_PENDING");
                }
            }
        } catch(Throwable e) {
            String reason=e instanceof IOException && e.getMessage()!=null && e.getMessage().matches("[a-z_]+")?e.getMessage():e.getClass().getSimpleName();
            System.err.println("TIMELINE_FAILED reason="+reason);
            for(StackTraceElement frame:e.getStackTrace())
                if(frame.getClassName().startsWith("com.xayah.dex.Timeline"))
                    System.err.println("TIMELINE_FRAME "+frame);
        }
        System.exit(rc);
    }
}
