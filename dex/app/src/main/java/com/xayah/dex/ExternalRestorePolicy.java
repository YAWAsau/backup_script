// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Android-DataBackup RestoreExternalDataHelper.kt,
// fa0a0f74a1fcafa29018afa88a293880599cbce7 (2026-10-12).
package com.xayah.dex;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.Build;
import android.os.IBinder;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import android.system.ErrnoException;
import dev.rikka.tools.refine.Refine;
import java.io.File;
import java.nio.file.Files;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;

/** External storage metadata belongs to vold or the derived-permission mount. */
final class ExternalRestorePolicy {
    private final ApplicationInfo app;
    private final File target, backing;
    private final String storage, kind, partitioned;
    private final Object vold;
    private final Method setup;

    private static void require(boolean ok, String message) {
        if (!ok) throw new IllegalStateException(message);
    }
    private static StructStat stat(File f) throws Exception {
        try { return Os.lstat(f.getPath()); }
        catch (ErrnoException e) { if (e.errno == OsConstants.ENOENT) return null; throw e; }
    }
    private static File[] children(File f) {
        File[] items=f.listFiles(); require(items!=null,"Cannot list " + f); return items;
    }
    private static void ancestors(File f) throws Exception {
        if (f.getParentFile()!=null) ancestors(f.getParentFile());
        require(OsConstants.S_ISDIR(Os.lstat(f.getPath()).st_mode),"Invalid ancestor " + f);
    }
    private interface DirectoryAction { void run(File f) throws Exception; }
    private static void walk(File root, long device, DirectoryAction action) throws Exception {
        ArrayDeque<File> pending=new ArrayDeque<>(); pending.push(root);
        while (!pending.isEmpty()) {
            File f=pending.pop(); StructStat s=Os.lstat(f.getPath());
            require(s.st_dev==device,"Cross-device external entry " + f);
            boolean dir=OsConstants.S_ISDIR(s.st_mode);
            require(dir || OsConstants.S_ISREG(s.st_mode),"Unsupported external entry " + f);
            require(dir || s.st_nlink==1,"Hard-linked external entry " + f);
            if (dir) {
                action.run(f);
                File[] entries=children(f);
                for(int i=entries.length-1;i>=0;i--) pending.push(entries[i]);
            }
        }
    }
    private static void clear(File root, long device) throws Exception {
        for (File f:children(root)) {
            StructStat s=Os.lstat(f.getPath());
            require(s.st_dev==device,"Cross-device delete " + f);
            if(OsConstants.S_ISDIR(s.st_mode)) clear(f,device);
            require(f.delete(),"Cannot remove " + f);
        }
    }
    private ExternalRestorePolicy(int user,String pkg,String kind) throws Exception {
        require(user>=0 && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+"),"Invalid package/user");
        require(kind.equals("data") || kind.equals("obb"),"Invalid external category");
        this.kind=kind;this.partitioned="/data/media/"+user+"/Android/"+kind+"/"+pkg;
        PackageManager pm=PackageManagerUtil.getPackageManager(HiddenApiHelper.getContext()).packageManager();
        PackageInfo info=Refine.<PackageManagerHidden>unsafeCast(pm).getPackageInfoAsUser(pkg,0,user);
        require(info!=null && info.applicationInfo!=null,"Package unavailable");app=info.applicationInfo;
        require(app.uid>=0 && app.uid/100000==user,"Package user mismatch");
        String volume="/mnt/runtime/default/emulated/"+user;
        String[] mount=null;
        for(String line:Files.readAllLines(new File("/proc/mounts").toPath())) {
            String[] fields=line.split(" ");
            if(fields.length>3 && (volume.equals(fields[1]) || volume.startsWith(fields[1].replaceAll("/+$","")+"/"))
                    && (mount==null || fields[1].length()>mount[1].length())) mount=fields;
        }
        boolean derived=mount!=null && (mount[2].equals("sdcardfs") || mount[2].equals("esdfs"));
        boolean property=(Boolean)Class.forName("android.os.SystemProperties").getMethod("getBoolean",String.class,boolean.class)
                .invoke(null,"external_storage.sdcardfs.enabled",true);
        boolean sdcardfs=property && Files.readAllLines(new File("/proc/filesystems").toPath()).stream()
                .anyMatch(x -> x.trim().equals("sdcardfs") || x.trim().endsWith("\tsdcardfs"));
        boolean useVold=Build.VERSION.SDK_INT>=30 && !derived && !sdcardfs;
        boolean sharedObb=!useVold && mount!=null && (mount[2].equals("fuse") || !Arrays.asList(mount[3].split(",")).contains("unshared_obb"));
        File volumeDir=new File(useVold?"/data/media/"+user:volume); ancestors(volumeDir);
        if(!useVold) {
            require(mount!=null && (derived || mount[2].equals("fuse")),"External storage not mounted");
            require(!derived || mount[0].equals("/data/media"),"Unexpected storage backing");
        }
        String relative="Android/"+kind+"/"+pkg;
        backing=new File(sharedObb && kind.equals("obb")?"/data/media/obb/"+pkg:"/data/media/"+user+"/"+relative);
        target=useVold?backing:new File(volumeDir,relative);
        storage="/storage/emulated/"+user+"/"+relative+"/";
        for(File f=target;f!=null;f=f.getParentFile()) {
            StructStat s=stat(f);require(s==null || OsConstants.S_ISDIR(s.st_mode),"Invalid destination " + f);
        }
        require(backing.getCanonicalPath().equals(backing.getAbsolutePath()),"Invalid backing path");
        if(useVold) {
            // Some ROMs bridge restorecon through a mutable system property.
            // A rejected (>=92 byte) value can leave vold holding its global lock.
            require((backing.getPath()+"/").getBytes(StandardCharsets.UTF_8).length < 92
                            && storage.getBytes(StandardCharsets.UTF_8).length < 92,
                    "EXTERNAL_POLICY_PATH_TOO_LONG");
            IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"vold");
            require(binder!=null,"vold unavailable");
            Class<?> api=Class.forName("android.os.IVold");
            vold=Class.forName("android.os.IVold$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
            setup=api.getMethod("setupAppDir",String.class,int.class);
        } else {vold=null;setup=null;}
    }
    private void prepare(String source, boolean nativeClear) throws Exception {
        require(!nativeClear || vold!=null,"Native clear requires vold");
        long t0=android.os.SystemClock.elapsedRealtime();
        // Reject local backup inside every target alias before clearing contents.
        String repository=new File(source).getCanonicalPath();
        for(File alias:new File[]{target,backing,new File(storage),new File("/mnt/user/"+(app.uid/100000)+"/emulated/"+(app.uid/100000)+"/Android/"+target.getParentFile().getName()+"/"+app.packageName)}) {
            String p=alias.getCanonicalPath();require(!repository.equals(p) && !repository.startsWith(p+"/"),"Source inside destination");
        }
        long t1=android.os.SystemClock.elapsedRealtime();
        System.err.println("EXTERNAL_PREPARE_PHASE_BEGIN stage=precheck");
        StructStat old=stat(target);if(old!=null && !nativeClear) walk(target,old.st_dev,f -> {});
        long t2=android.os.SystemClock.elapsedRealtime();
        System.err.println("EXTERNAL_PREPARE_PHASE_BEGIN stage=vold precheckMs="+(t2-t1));
        if(vold!=null) setup.invoke(vold,storage,app.uid);
        else require(target.mkdirs() || target.isDirectory(),"Cannot prepare external directory");
        long t3=android.os.SystemClock.elapsedRealtime();
        System.err.println("EXTERNAL_PREPARE_PHASE_BEGIN stage=postcheck voldMs="+(t3-t2));
        StructStat s=Os.lstat(target.getPath());
        require(OsConstants.S_ISDIR(s.st_mode) && (vold==null || s.st_uid==app.uid),"Unexpected prepared owner");
        if(!nativeClear) walk(target,s.st_dev,f -> {});
        long t4=android.os.SystemClock.elapsedRealtime();
        System.err.println("EXTERNAL_PREPARE_PHASE_BEGIN stage=clear postcheckMs="+(t4-t3));
        if(!nativeClear) clear(target,s.st_dev);
        long t5=android.os.SystemClock.elapsedRealtime();
        System.err.println("EXTERNAL_PREPARE_PHASES native="+nativeClear+" aliasMs="+(t1-t0)+" precheckMs="+(t2-t1)+" voldMs="+(t3-t2)+" postcheckMs="+(t4-t3)+" clearMs="+(t5-t4));
    }
    private void repair() throws Exception {
        ancestors(target);long dev=Os.lstat(target.getPath()).st_dev;
        walk(target,dev,f -> {});
        // Shell performs fd-based metadata repair in a standalone native child.
        // Never send restored descendant paths to vold: a long path can wedge
        // the service's restorecon property bridge and trigger system watchdog.
        if(!backing.equals(target)) {ancestors(backing);walk(backing,Os.lstat(backing.getPath()).st_dev,f -> {});}
    }
    private void requireExpected(String[] args) {
        require(args.length==9,"external RPC expected target/backing/UID missing");
        require(target.getPath().equals(args[6]) && backing.getPath().equals(args[7])
                && Integer.toString(app.uid).equals(args[8]),"external policy changed");
    }
    private boolean partitionedRoot() {
        return vold!=null && backing.getPath().equals(partitioned)
                && backing.equals(target);
    }
    private void prepareRpc(String source) throws Exception {
        if (partitionedRoot()) {
            NativeFileClient.run("external-tree-check",backing.getPath(),Integer.toString(app.uid),kind);
            prepare(source,true);
            NativeFileClient.run("external-tree-clear",backing.getPath(),Integer.toString(app.uid),kind);
        } else prepare(source,false);
    }
    private void repairRpc() throws Exception {
        repair();
        if (partitionedRoot()) {
            NativeFileClient.run("external-policy-fused",backing.getPath(),Integer.toString(app.uid),kind);
        } else {
            if (vold!=null) NativeFileClient.run("external-policy-repair",backing.getPath(),Integer.toString(app.uid),kind);
            NativeFileClient.run("selinux-restore",backing.getPath(),"12");
        }
    }
    static void command(String[] args) {
        try {
            boolean rpc=args.length>1 && ("prepare-rpc".equals(args[1]) || "repair-rpc".equals(args[1]));
            require(args.length==(rpc?9:6),"externalRestorePolicy MODE USER PACKAGE KIND SOURCE [TARGET BACKING UID]");
            ExternalRestorePolicy p=new ExternalRestorePolicy(Integer.parseInt(args[2]),args[3],args[4]);
            switch(args[1]) {
                case "prepare-rpc":p.requireExpected(args);p.prepareRpc(args[5]);break;
                case "repair-rpc":p.requireExpected(args);p.repairRpc();break;
                case "plan": break;
                case "prepare":p.prepare(args[5],false);break;
                case "prepare-native":p.prepare(args[5],true);break;
                case "repair":p.repair();break;
                default:throw new IllegalArgumentException("Invalid external policy mode");
            }
            DaemonOutput.current().println(p.target.getPath()+"\t"+p.backing.getPath()+"\t"+(p.vold==null?"derived":"vold")+"\t"+p.app.uid);
        } catch(Exception e) {
            if ("EXTERNAL_POLICY_PATH_TOO_LONG".equals(e.getMessage()))
                DaemonOutput.current().println("EXTERNAL_POLICY_PATH_TOO_LONG");
            throw new IllegalStateException("External restore policy failed",e);
        }
    }
}
