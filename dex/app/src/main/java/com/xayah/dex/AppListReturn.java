package com.xayah.dex;
import android.content.*;
import android.content.pm.*;
import android.net.Uri;
import android.net.LocalSocket;
import android.net.LocalServerSocket;
import android.net.LocalSocketAddress;
import java.io.*;
import android.os.*;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;
import java.lang.reflect.Field;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Root-side one-session native APK transport. No browser tasks, polling or arbitrary commands. */
public final class AppListReturn {
    private static final String PACKAGE="io.github.yawasau.speedbackup.webview";
    private static final long APK_VERSION=138;
    private static final String APK_SHA="84b01978e6226e8d402662f981ff6d31eb7b15c2ca4e03b85aeb1b1a639c65bd";
    private static final String PROTOCOL="speedbackup.webview.v1";
    private static final String CERT="73d49c551002cb071ac89ac6bad572ec999dc0b9f2fbb381130f84fbd0ea251e";
    private static int number(Object value,String name,int fallback){try{return ((Number)field(value,name)).intValue();}catch(Exception e){return fallback;}}
    private static Object field(Object value, String name) throws Exception {
        for (Class<?> c = value.getClass(); c != null; c = c.getSuperclass()) {
            try { Field f = c.getDeclaredField(name); f.setAccessible(true); return f.get(value); }
            catch (NoSuchFieldException ignored) { }
        }
        throw new NoSuchFieldException(name);
    }
    private static Object call(Object target, String method, Object... args) throws Exception {
        return HiddenApiReflection.invokeFlexible(target, method, args);
    }
    private static List<?> tasks(Object service) throws Exception {
        Object[][] variants = {{128, false, true, -1}, {128, false, true}, {128, false}, {128}};
        for (Object[] args : variants) {
            try { Object value = call(service, "getTasks", args); if (value instanceof List<?>) return (List<?>) value; }
            catch (NoSuchMethodException ignored) { }
        }
        throw new IllegalStateException("unsupported task API");
    }
    private static final class Task {
        final int id, user, display, windowing;
        final ComponentName base, top;
        final IBinder token;
        final Intent intent;
        final int activities;
        Task(Object info) throws Exception {
            intent = null; activities = number(info,"numActivities",-1);
            id = number(info,"taskId",number(info,"id",-1)); user = number(info,"userId",number(call(HiddenApiServices.activity(),"getCurrentUser"),"id",-1));
            display = number(info,"displayId",0);
            int mode=1;try{mode=(Integer)call(field(field(info,"configuration"),"windowConfiguration"),"getWindowingMode");}catch(NoSuchFieldException legacy){if(Build.VERSION.SDK_INT>=29)throw legacy;}windowing=mode;
            base = (ComponentName) field(info, "baseActivity"); top = (ComponentName) field(info, "topActivity");
            IBinder t=null;try{t=(IBinder)call(field(info,"token"),"asBinder");}catch(Exception ignored){} token=t;
            if (base == null || top == null || id < 0) throw new IllegalStateException("incomplete task");
        }
        boolean same(Task other) {
            return id == other.id && user == other.user && display == other.display
                    && base.equals(other.base) && java.util.Objects.equals(token,other.token);
        }
    }
    private static boolean unlocked() throws Exception {
        Object window = HiddenApiServices.interfaceService("window", "android.view.IWindowManager$Stub");
        Object power = HiddenApiServices.interfaceService("power", "android.os.IPowerManager$Stub");
        return Boolean.FALSE.equals(call(window, "isKeyguardLocked")) && Boolean.TRUE.equals(call(power, "isInteractive"));
    }
    private static String restoreAfterExternalClose(Object atm, Task origin, String browser) throws Exception {
        if(!unlocked())return "SKIP_LOCKED";
        List<?> list=tasks(atm);if(list.isEmpty())return "SKIP_NO_TASK";
        Task front=new Task(list.get(0));
        if(origin.same(front)||browser.equals(front.top.getPackageName())){return restore(atm,origin,browser);}
        // Android may resume Home after a previously-backgrounded native APK
        // finishes. Never redirect an unrelated foreground app.
        Intent home=new Intent(Intent.ACTION_MAIN);home.addCategory(Intent.CATEGORY_HOME);
        Object pm=HiddenApiServices.interfaceService("package","android.content.pm.IPackageManager$Stub");
        ResolveInfo resolved;
        try{resolved=(ResolveInfo)call(pm,"resolveIntent",home,null,0x00010000L,origin.user);}
        catch(NoSuchMethodException older){resolved=(ResolveInfo)call(pm,"resolveIntent",home,null,0x00010000,origin.user);}
        if(resolved!=null&&resolved.activityInfo!=null&&front.top.equals(new ComponentName(resolved.activityInfo.packageName,resolved.activityInfo.name)))
            return restore(atm,origin,resolved.activityInfo.packageName);
        return "SKIP_FOREGROUND_CHANGED";
    }
    private static String restore(Object atm, Task origin, String browser) throws Exception {
        if (!unlocked()) return "SKIP_LOCKED";
        List<?> list = tasks(atm);
        if (list.isEmpty()) return "SKIP_NO_TASK";
        Task foreground = new Task(list.get(0));
        if (origin.same(foreground)) return origin.top.equals(foreground.top)&&foreground.windowing==1 ? "ALREADY_ORIGIN" : "SKIP_ORIGIN_CHANGED";
        if (!supportedHostWindow(foreground) || foreground.user != origin.user || foreground.display != origin.display
                || !browser.equals(foreground.top.getPackageName())) return "SKIP_FOREGROUND_CHANGED";
        Task existing = null;
        for (Object item : list) {
            try { Task task = new Task(item); if (origin.same(task)) { existing = task; break; } }
            catch (Exception ignored) { }
        }
        if (existing == null || !origin.top.equals(existing.top)) return "SKIP_ORIGIN_CHANGED";
        // Recheck immediately before focus. No task removal, launch, Back, or force-stop.
        list = tasks(atm);
        if (!unlocked() || list.isEmpty()) return "SKIP_FOREGROUND_CHANGED";
        Task latest = new Task(list.get(0));
        if (!supportedHostWindow(latest) || !foreground.same(latest) || !foreground.top.equals(latest.top) || !browser.equals(latest.top.getPackageName())) return "SKIP_FOREGROUND_CHANGED";
        boolean originPresent = false;
        for (Object item : list) {
            try { Task task = new Task(item); if (origin.same(task) && origin.top.equals(task.top) && task.windowing == 1) { originPresent = true; break; } }
            catch (Exception ignored) { }
        }
        if (!originPresent) return "SKIP_ORIGIN_CHANGED";
        call(atm, "setFocusedTask", origin.id);
        // Android resumes asynchronously. Confirm briefly, never issue focus twice.
        try {
            for (int attempt = 0; attempt < 12; attempt++) {
                list = tasks(atm);
                if (!list.isEmpty()) {
                    Task confirmed=new Task(list.get(0));
                    if (unlocked()&&origin.same(confirmed)&&origin.top.equals(confirmed.top)&&confirmed.windowing==1) return "RETURNED";
                }
                Thread.sleep(40);
            }
        } catch (Exception ignored) { }
        return "RETURN_UNCONFIRMED";
    }

    // OEMs can launch our verified host as freeform. Keep origin identity,
    // selected user/display, unlocked and foreground checks unchanged.
    private static boolean supportedHostWindow(Task task) {
        return task.windowing==1 || (task.windowing==5 && PACKAGE.equals(task.top.getPackageName()));
    }

    private static Object activity() throws Exception {
        return Build.VERSION.SDK_INT>=29?HiddenApiServices.interfaceService("activity_task","android.app.IActivityTaskManager$Stub"):HiddenApiServices.activity();
    }
    private static PackageInfo installed(int user) throws Exception {
        Object pm=HiddenApiServices.interfaceService("package","android.content.pm.IPackageManager$Stub");
        try{return (PackageInfo)call(pm,"getPackageInfo",PACKAGE,0x08000000L,user);}
        catch(NoSuchMethodException e){return (PackageInfo)call(pm,"getPackageInfo",PACKAGE,0x08000000,user);}
    }
    // Called only after signature, version and APK identity validation. Normal
    // manifest permissions are install-time grants; POST_NOTIFICATIONS is the
    // host's only runtime permission. No backup target application's grants change.
    private static void prepareShortcutAccess(PackageInfo info) {
        // OEM shortcut gates are not Android runtime permissions. Resolve the
        // ROM's named operation; never apply another vendor's numeric AppOp.
        try {
            Integer op=null;
            for(String owner:new String[]{"android.app.AppOpsManager","android.app.AppOpsManagerInjector"}) {
                try {
                    java.lang.reflect.Field field=Class.forName(owner).getDeclaredField("OP_INSTALL_SHORTCUT");
                    field.setAccessible(true);
                    if(field.getType()==int.class && java.lang.reflect.Modifier.isStatic(field.getModifiers())) {
                        op=field.getInt(null);break;
                    }
                } catch(ReflectiveOperationException ignored) {}
            }
            if(op==null) {
                System.err.println("SHORTCUT_ACCESS status=unsupported_named_operation manual_oem_permission_may_be_required");
                return;
            }
            Object service=HiddenApiServices.interfaceService("appops","com.android.internal.app.IAppOpsService$Stub");
            int uid=info.applicationInfo.uid;
            Object before=call(service,"checkOperation",op,uid,PACKAGE);
            if(!(before instanceof Integer))throw new IllegalStateException("unexpected AppOp result");
            if(((Integer)before)!=android.app.AppOpsManager.MODE_ALLOWED)
                call(service,"setMode",op,uid,PACKAGE,android.app.AppOpsManager.MODE_ALLOWED);
            Object after=call(service,"checkOperation",op,uid,PACKAGE);
            System.err.println("SHORTCUT_ACCESS op="+op+" uid="+uid+" before="+before+" after="+after+
                " verified="+Integer.valueOf(android.app.AppOpsManager.MODE_ALLOWED).equals(after));
        } catch(Exception e) {
            // Failure to configure an optional launcher permission must not stop
            // backup/restore or imply that a shortcut was successfully pinned.
            System.err.println("SHORTCUT_ACCESS status=unavailable reason="+e.getClass().getSimpleName());
        }
    }
    private static void prepareHostAccess(int user) throws IOException {
        if(user<0)throw new IOException("host user");
        // Identity was verified above. Native owns the bounded permission policy.
        System.out.println("HOST_ACCESS\t"+user+"\t"+Build.VERSION.SDK_INT);
        System.out.flush();
        String reply=new BufferedReader(new InputStreamReader(System.in,java.nio.charset.StandardCharsets.UTF_8)).readLine();
        if(!"HOST_ACCESS_DONE".equals(reply))throw new IOException("host access handshake");
    }
    private static boolean trustedLauncherPackage(PackageInfo info) throws Exception {
        if(info==null)return false;
        if(info.signingInfo==null||info.signingInfo.getApkContentsSigners().length!=1)throw new SecurityException("signer");
        byte[] digest=java.security.MessageDigest.getInstance("SHA-256").digest(info.signingInfo.getApkContentsSigners()[0].toByteArray());
        StringBuilder hex=new StringBuilder();for(byte b:digest)hex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        if(!CERT.equals(hex.toString()))throw new SecurityException("installed native APK certificate mismatch");
        return info.applicationInfo!=null&&info.applicationInfo.enabled;
    }
    private static boolean verify(PackageInfo info) throws Exception {
        if(!trustedLauncherPackage(info)||info.getLongVersionCode()<APK_VERSION)return false;
        // Never downgrade a newer compatible host; repair same-version prototype/stale APKs.
        if(info.getLongVersionCode()>APK_VERSION)return true;
        java.security.MessageDigest apkDigest=java.security.MessageDigest.getInstance("SHA-256");
        try(InputStream input=new FileInputStream(info.applicationInfo.sourceDir)){
            byte[] buffer=new byte[65536];int n;while((n=input.read(buffer))!=-1)apkDigest.update(buffer,0,n);
        }
        StringBuilder apkHex=new StringBuilder();for(byte b:apkDigest.digest())apkHex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        return APK_SHA.equals(apkHex.toString());
    }
    private static String ownerIdentity(String pid){
        try{
            if(pid==null||!pid.matches("[1-9][0-9]{1,9}"))return null;
            String stat=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/"+pid+"/stat")),java.nio.charset.StandardCharsets.UTF_8);
            String[] fields=stat.substring(stat.lastIndexOf(')')+2).split(" ");
            if(fields[0].equals("Z"))return null;
            return pid+":"+fields[19];
        }catch(Exception e){return null;}
    }
    private static String boundedLine(InputStream input) throws IOException {return boundedLine(input,160);}
    private static String boundedLine(InputStream input,int limit) throws IOException {
        StringBuilder line=new StringBuilder();int c;
        while((c=input.read())!=-1&&c!='\n'){
            if(c<32||c>126||line.length()>=limit)throw new IOException("origin protocol");
            line.append((char)c);
        }
        if(c!='\n')throw new IOException("origin EOF");return line.toString();
    }
    private static String originCommand(String name,String identity,String action) throws Exception {
        if(name==null||!name.matches("sb-web-origin-[0-9]+-[0-9]+-[0-9]+")||name.length()>96||identity==null)throw new IOException("origin identity");
        try(LocalSocket socket=new LocalSocket()){
            socket.connect(new LocalSocketAddress(name,LocalSocketAddress.Namespace.ABSTRACT));
            socket.setSoTimeout(5000);
            if(socket.getPeerCredentials().getUid()!=0)throw new SecurityException("origin peer");
            socket.getOutputStream().write((identity+" "+action+"\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            return boundedLine(socket.getInputStream());
        }
    }
    private static boolean ownLauncher(Task task) throws Exception {
        return PACKAGE.equals(task.top.getPackageName())&&(PACKAGE+".LauncherActivity").equals(task.top.getClassName())&&trustedLauncherPackage(installed(task.user));
    }
    private static void checkAncestor(String owner,Task original) throws Exception {checkAncestor(owner,original,false);}
    private static void checkAncestor(String owner,Task original,boolean required) throws Exception {
        // Our signed launcher invokes su without a PTY; managers may detach its ancestry.
        // Keep all existing ancestry/PTY checks for every other foreground application.
        if(ownLauncher(original))return;
        String pid=owner;
        for(int i=0;i<32&&!pid.equals("1");i++){
            int uid;
            String stat;
            try{uid=android.system.Os.stat("/proc/"+pid).st_uid;stat=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/"+pid+"/stat")),java.nio.charset.StandardCharsets.UTF_8);}catch(IOException|android.system.ErrnoException unavailable){if(required)throw new SecurityException("invoker ancestry unavailable");return;}
            if(uid>=10000){
                Object pm=HiddenApiServices.interfaceService("package","android.content.pm.IPackageManager$Stub");Object info;
                try{info=call(pm,"getPackageInfo",original.top.getPackageName(),0L,original.user);}catch(NoSuchMethodException older){info=call(pm,"getPackageInfo",original.top.getPackageName(),0,original.user);}
                if(!(info instanceof PackageInfo)||((PackageInfo)info).applicationInfo==null||((PackageInfo)info).applicationInfo.uid!=uid)throw new SecurityException("terminal ancestor differs from foreground");
                return;
            }
            String[] fields=stat.substring(stat.lastIndexOf(')')+2).split(" ");pid=fields[1];if(pid.equals("0"))break;
        }
        if(required&&!terminalPeer(owner,original))throw new SecurityException("no verified terminal ancestor or PTY owner");
    }
    // Root managers may daemonize su, removing the app from the parent chain.
    // In that case require the invoker's live PTY slave to be owned by the
    // foreground app's PTY master. An adb pipe or unrelated foreground fails.
    private static String componentKey(ComponentName component){return android.util.Base64.encodeToString(component.flattenToString().getBytes(java.nio.charset.StandardCharsets.UTF_8),android.util.Base64.NO_WRAP);}
    private static boolean terminalPeer(String invoker,Task foreground) throws Exception {
        // su may daemonize, and wrappers may redirect stdin. Only accept a live
        // root ancestor's stdio PTY paired with the foreground app's master.
        java.util.LinkedHashMap<String,String> chain=new java.util.LinkedHashMap<>();
        String pid=invoker;
        for(int depth=0;depth<32&&!pid.equals("0")&&!pid.equals("1");depth++){
            String stat;
            try{
                if(android.system.Os.stat("/proc/"+pid).st_uid!=0)return false;
                stat=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/"+pid+"/stat")),java.nio.charset.StandardCharsets.UTF_8);
            }catch(Exception gone){return false;}
            String[] f=stat.substring(stat.lastIndexOf(')')+2).split(" ");
            if(f[0].equals("Z")||chain.containsKey(pid))return false;
            chain.put(pid,f[1]+":"+f[19]);
            if(terminalPeerAt(pid,foreground)){
                try{for(java.util.Map.Entry<String,String> item:chain.entrySet()){
                    String now=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/"+item.getKey()+"/stat")),java.nio.charset.StandardCharsets.UTF_8);
                    String[] a=now.substring(now.lastIndexOf(')')+2).split(" ");
                    if(a[0].equals("Z")||!item.getValue().equals(a[1]+":"+a[19])||android.system.Os.stat("/proc/"+item.getKey()).st_uid!=0)return false;
                }}catch(Exception gone){return false;}
                return true;
            }
            pid=f[1];
        }
        return false;
    }
    private static boolean terminalPeerAt(String invoker,Task foreground) throws Exception {
        for(int fd=0;fd<3;fd++)if(terminalPeerFd(invoker,foreground,fd))return true;
        return false;
    }
    private static boolean terminalPeerFd(String invoker,Task foreground,int stdFd) throws Exception {
        String identity=ownerIdentity(invoker);if(identity==null)return false;
        String slave;
        try{slave=android.system.Os.readlink("/proc/"+invoker+"/fd/"+stdFd);}catch(Exception absent){return false;}
        if(!slave.matches("/dev/pts/[0-9]+"))return false;
        String index=slave.substring(slave.lastIndexOf('/')+1);
        Object pm=HiddenApiServices.interfaceService("package","android.content.pm.IPackageManager$Stub");Object raw;
        try{raw=call(pm,"getPackageInfo",foreground.top.getPackageName(),0L,foreground.user);}catch(NoSuchMethodException older){raw=call(pm,"getPackageInfo",foreground.top.getPackageName(),0,foreground.user);}
        if(!(raw instanceof PackageInfo)||((PackageInfo)raw).applicationInfo==null)return false;
        int uid=((PackageInfo)raw).applicationInfo.uid;
        File[] processes=new File("/proc").listFiles();if(processes==null)return false;
        for(File process:processes){
            if(!process.getName().matches("[0-9]+"))continue;
            try{
                if(android.system.Os.stat(process.getPath()).st_uid!=uid)continue;
                String appIdentity=ownerIdentity(process.getName());if(appIdentity==null)continue;
                File[] descriptors=new File(process,"fd").listFiles();if(descriptors==null)continue;
                for(File fd:descriptors){
                    String master=android.system.Os.readlink(fd.getPath());
                    if(!master.equals("/dev/ptmx")&&!master.equals("/dev/pts/ptmx"))continue;
                    String infoPath=process.getPath()+"/fdinfo/"+fd.getName();
                    String info=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(infoPath)),java.nio.charset.StandardCharsets.US_ASCII);
                    if(!java.util.regex.Pattern.compile("(?m)^tty-index:[ \t]*"+index+"[ \t]*$").matcher(info).find())continue;
                    if(identity.equals(ownerIdentity(invoker))&&appIdentity.equals(ownerIdentity(process.getName()))&&
                        android.system.Os.stat(process.getPath()).st_uid==uid&&slave.equals(android.system.Os.readlink("/proc/"+invoker+"/fd/"+stdFd))&&
                        master.equals(android.system.Os.readlink(fd.getPath()))&&info.equals(new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(infoPath)),java.nio.charset.StandardCharsets.US_ASCII)))return true;
                }
            }catch(Exception raced){ /* Process/descriptor changed: try another verified owner. */ }
        }
        return false;
    }
    // Scope host protection to this root-owned worker, not the installed app's lifetime.
    private static final class HostProtection implements AutoCloseable {
        final int user;final File marker;int uid=-1;
        boolean seenHost=false, fallbackPosted=false;int missingTicks=0;long fallbackAt=0;
        final java.util.Map<Integer,String> identities=new java.util.HashMap<>();
        final java.util.Map<Integer,Integer> originals=new java.util.HashMap<>();
        HostProtection(int user){
            this.user=user;String dir=System.getenv("SPEEDBACKUP_CONSOLE_DIR");
            marker=dir!=null&&dir.startsWith("/data/.speedbackup/console/")?new File(dir,"guard-active"):null;
        }
        void tick(boolean deathEvent){
            if(marker==null||!marker.isFile()){close();return;}
            try{
                if(uid<0){PackageInfo info=installed(user);if(!verify(info))return;uid=info.applicationInfo.uid;}
                File[] all=new File("/proc").listFiles();if(all==null)return;
                boolean hostAlive=false;
                for(File f:all)try{
                    if(!f.getName().matches("[1-9][0-9]+")||android.system.Os.stat(f.getPath()).st_uid!=uid)continue;
                    String name=new String(java.nio.file.Files.readAllBytes(new File(f,"cmdline").toPath()),java.nio.charset.StandardCharsets.UTF_8).split("\\x00",2)[0];
                    if(!name.equals(PACKAGE)&&!name.equals(PACKAGE+":guardian"))continue;
                    hostAlive=true;
                    int pid=Integer.parseInt(f.getName());String identity=ownerIdentity(f.getName());if(identity==null)continue;
                    File score=new File(f,"oom_score_adj");int current=Integer.parseInt(new String(java.nio.file.Files.readAllBytes(score.toPath())).trim());
                    if(!identity.equals(identities.get(pid))){identities.put(pid,identity);originals.put(pid,current);}
                    if(current > -900&&identity.equals(ownerIdentity(f.getName()))&&android.system.Os.stat(f.getPath()).st_uid==uid)
                        java.nio.file.Files.write(score.toPath(),"-900\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                }catch(Exception ignored){}
                if(hostAlive){seenHost=true;missingTicks=0;clearFallback();}
                else if(seenHost && (deathEvent || ++missingTicks>=2) && (!fallbackPosted||SystemClock.elapsedRealtime()-fallbackAt>=15000) && verify(installed(user))){
                    NotificationUtil.hostFallback(HiddenApiHelper.getContext(),marker.getParentFile().getName(),user,true);
                    fallbackPosted=true;fallbackAt=SystemClock.elapsedRealtime();
                }
            }catch(Exception e){System.err.println("HOST_OOM_PROTECT "+e.getClass().getSimpleName());}
        }
        void clearFallback(){
            if(fallbackPosted)try{
                NotificationUtil.hostFallback(HiddenApiHelper.getContext(),marker.getParentFile().getName(),user,false);
                fallbackPosted=false;
            }catch(Exception e){System.err.println("HOST_FALLBACK_CANCEL "+e.getClass().getSimpleName());}
        }
        public void close(){
            clearFallback();
            for(java.util.Map.Entry<Integer,String> item:identities.entrySet())try{
                int pid=item.getKey();File score=new File("/proc/"+pid+"/oom_score_adj");
                if(item.getValue().equals(ownerIdentity(Integer.toString(pid)))&&android.system.Os.stat("/proc/"+pid).st_uid==uid&&
                    Integer.parseInt(new String(java.nio.file.Files.readAllBytes(score.toPath())).trim())==-900)
                    java.nio.file.Files.write(score.toPath(),(originals.get(pid)+"\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            }catch(Exception ignored){}
            identities.clear();originals.clear();
        }
    }
    private static void originServer(String[] args,Object atm) throws Exception {
        if(args.length!=8)throw new IllegalArgumentException("origin arguments");
        final String name=args[1],owner=args[2],identity=ownerIdentity(owner);
        if(identity==null||!name.matches("sb-web-origin-[0-9]+-[0-9]+-[0-9]+")||name.length()>96)throw new IllegalArgumentException("origin owner");
        List<?> list=tasks(atm);if(list.isEmpty()||!unlocked())throw new IllegalStateException("origin absent");
        Task original=new Task(list.get(0));
        if((Build.VERSION.SDK_INT>=30&&original.token==null)||(PACKAGE.equals(original.top.getPackageName())&&!ownLauncher(original))||original.windowing!=1||
            !args[3].equals(String.valueOf(original.id))||!args[4].equals(String.valueOf(original.user))||!args[5].equals(String.valueOf(original.display))||
            !args[6].equals(original.base.flattenToString())||!args[7].equals(original.top.flattenToString()))throw new IllegalStateException("origin changed before capture");
        checkAncestor(owner,original);
        try(LocalServerSocket server=new LocalServerSocket(name)){
            HiddenApiHelper.initializeContext();
            final int guardUser=original.user;
            final AtomicInteger trustedHostUid=new AtomicInteger(-1);
            final java.util.concurrent.Semaphore hostEvents=new java.util.concurrent.Semaphore(0);
            final java.util.Set<Integer> watched=java.util.concurrent.ConcurrentHashMap.newKeySet();
            Thread watch=new Thread(()->{
                try(HostProtection guard=new HostProtection(guardUser)){
                    int tick=0;
                    while(identity.equals(ownerIdentity(owner))){boolean changed=hostEvents.tryAcquire(250,TimeUnit.MILLISECONDS);if(changed||tick++%20==0){guard.tick(changed);trustedHostUid.set(guard.uid);}}
                }catch(Exception ignored){}
                System.exit(0);
            },"origin-owner");watch.setDaemon(true);watch.start();
            System.out.println("ORIGIN_READY");System.out.flush();
            while(true){
                try(LocalSocket client=server.accept()){
                    if(client.getPeerCredentials().getUid()!=0){
                        if(client.getPeerCredentials().getUid()!=trustedHostUid.get())continue;
                        try {
                        int peer=client.getPeerCredentials().getPid();
                        String process=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/"+peer+"/cmdline")),java.nio.charset.StandardCharsets.UTF_8).split("\\x00",2)[0];
                        if((!process.equals(PACKAGE)&&!process.equals(PACKAGE+":guardian"))||!watched.add(peer))continue;
                        // Transfer the duplicated descriptor only after the watcher starts.
                        android.os.ParcelFileDescriptor retained=null;boolean transferred=false;
                        try {
                            retained=android.os.ParcelFileDescriptor.dup(client.getFileDescriptor());
                            client.getOutputStream().write(1);
                            final android.os.ParcelFileDescriptor link=retained;
                            Thread life=new Thread(()->{
                                try(java.io.InputStream in=new android.os.ParcelFileDescriptor.AutoCloseInputStream(link)){in.read();}
                                catch(Exception ignored){}
                                finally{watched.remove(peer);hostEvents.release();}
                            },"host-death-"+peer);life.setDaemon(true);life.start();transferred=true;hostEvents.release();
                        }finally{
                            if(!transferred){watched.remove(peer);if(retained!=null)retained.close();}
                        }
                        }catch(Exception rejected){ /* Peer exit must never close the origin server. */ }
                        continue;
                    }
                    client.setSoTimeout(5000);String request=boundedLine(client.getInputStream(),4096),answer="DENIED";
                    try { if(identity.equals(ownerIdentity(owner))&&request.startsWith(identity+" ")){
                        String action=request.substring(identity.length()+1);
                        if(action.equals("PROBE"))answer="OK";
                        else if(action.equals("FOCUS"))answer=restore(atm,original,PACKAGE);
                        else if(action.equals("AFTER_CLOSE"))answer=restoreAfterExternalClose(atm,original,PACKAGE);
                        else if(action.startsWith("REBIND ")){
                            String[] f=action.split(" ",8);List<?> current=tasks(atm);
                            if(f.length==8&&f[2].equals(ownerIdentity(f[1]))&&unlocked()&&!current.isEmpty()){
                                Task candidate=new Task(current.get(0));
                                if(candidate.user==original.user&&candidate.display==original.display&&candidate.windowing==1&&
                                    (!PACKAGE.equals(candidate.top.getPackageName())||ownLauncher(candidate))&&(Build.VERSION.SDK_INT<30||candidate.token!=null)&&
                                    f[3].equals(String.valueOf(candidate.id))&&f[4].equals(String.valueOf(candidate.user))&&f[5].equals(String.valueOf(candidate.display))&&
                                    f[6].equals(componentKey(candidate.base))&&f[7].equals(componentKey(candidate.top))){
                                    checkAncestor(f[1],candidate,true);if(!f[2].equals(ownerIdentity(f[1])))throw new SecurityException("invoker ended");original=candidate;answer="OK";
                                }
                            }
                        }
                        else if(action.equals("HOST_OPEN")){
                            List<?> current=tasks(atm);
                            if(unlocked()&&!current.isEmpty()){
                                Task front=new Task(current.get(0));
                                if(front.user==original.user&&front.display==original.display&&supportedHostWindow(front)&&
                                    PACKAGE.equals(front.top.getPackageName())&&(PACKAGE+".ResumeActivity").equals(front.top.getClassName())&&verify(installed(front.user)))answer="OK";
                            }
                        }
                        else if(action.equals("OPEN")){
                            PackageInfo currentHost=installed(original.user);if(verify(currentHost))trustedHostUid.set(currentHost.applicationInfo.uid);
                            List<?> current=tasks(atm);
                            if(unlocked()&&!current.isEmpty()){
                                Task front=new Task(current.get(0));
                                if(front.user==original.user&&front.display==original.display&&supportedHostWindow(front)&&
                                    ((original.same(front)&&original.top.equals(front.top))||PACKAGE.equals(front.top.getPackageName())))answer="OK";
                            }
                        }
                    }
                    } catch(Exception failure){answer="ERROR";}
                    client.getOutputStream().write((answer+"\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                }catch(IOException ignored){} // a malformed/abandoned client cannot end the owner session
            }
        }
    }
    private static void ensureOrigin(String name,String owner,String identity,Task expected) throws Exception {
        try {if(!originCommand(name,identity,"PROBE").equals("OK"))throw new SecurityException("origin owner mismatch");return;}
        catch(IOException absent){if(PACKAGE.equals(expected.top.getPackageName())&&!ownLauncher(expected))throw new IllegalStateException("original terminal unavailable");}
        java.lang.Process process=new ProcessBuilder("/system/bin/app_process","/system/bin","com.xayah.dex.AppListReturn","--origin",name,owner,
            String.valueOf(expected.id),String.valueOf(expected.user),String.valueOf(expected.display),expected.base.flattenToString(),expected.top.flattenToString())
            .redirectInput(new File("/dev/null")).redirectError(new File("/dev/null")).start();
        FutureTask<String> ready=new FutureTask<>(()->boundedLine(process.getInputStream()));Thread reader=new Thread(ready,"origin-ready");reader.setDaemon(true);reader.start();
        try{if(!"ORIGIN_READY".equals(ready.get(4,TimeUnit.SECONDS))||!"OK".equals(originCommand(name,identity,"PROBE")))throw new IOException("origin startup");}
        catch(Exception failure){process.destroyForcibly();throw failure;}
        finally{process.getInputStream().close();}
    }
    private static boolean returned(String value){return "RETURNED".equals(value)||"ALREADY_ORIGIN".equals(value);}
    private static String icons(String request,IBinder endpoint) throws Exception {
        String[] fields=request.split("\\t",-1);
        if(fields.length<3||fields.length>102||!fields[1].matches("[0-9]{1,5}"))throw new IllegalArgumentException("icon request");
        int user=Integer.parseInt(fields[1]);
        for(int i=2;i<fields.length;i++)if(fields[i].length()>265||!fields[i].matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+"))throw new IllegalArgumentException("icon package");
        Object pm=HiddenApiServices.interfaceService("package","android.content.pm.IPackageManager$Stub");
        StringBuilder out=new StringBuilder("ICONS\t");
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(6);
        for(int i=2;i<fields.length;i++){
            String value="";
            if(System.nanoTime()<deadline)try{
                ApplicationInfo app;
                try{app=(ApplicationInfo)call(pm,"getApplicationInfo",fields[i],0L,user);}
                catch(NoSuchMethodException old){app=(ApplicationInfo)call(pm,"getApplicationInfo",fields[i],0,user);}
                if(app!=null&&app.uid/100000==user&&fields[i].equals(app.packageName)){
                    Parcel data=Parcel.obtain(),reply=Parcel.obtain();
                    try{
                        data.writeInterfaceToken(PROTOCOL);data.writeInt(1);app.writeToParcel(data,0);
                        if(endpoint.transact(4,data,reply,0)){
                            reply.readException();byte[] png=reply.createByteArray();
                            if(png!=null&&png.length<=32768)value=android.util.Base64.encodeToString(png,android.util.Base64.NO_WRAP);
                        }
                    }finally{data.recycle();reply.recycle();}
                }
            }catch(RemoteException e){throw e;}catch(Exception e){System.err.println("WEBVIEW_ICON_UNAVAILABLE user="+user+" package="+fields[i]+" error="+e.getClass().getSimpleName());}
            if(i>2)out.append(';');out.append(fields[i]).append(':').append(value);
        }
        return out.toString();
    }
    private static void iconSocket(String originName,AtomicReference<IBinder> endpoint){
        if(originName==null||originName.length()>90)return;
        try{
            LocalServerSocket bound=null;
            // A replaced HELD controller may need a moment to release the scoped name.
            for(int attempt=0;attempt<11;attempt++){
                try{bound=new LocalServerSocket(originName+".icons");break;}
                catch(IOException e){if(attempt==10)throw e;Thread.sleep(50);}
            }
            final LocalServerSocket server=bound;
            Thread worker=new Thread(()->{
                while(true){
                    final LocalSocket client;
                    try{client=server.accept();}catch(Exception e){break;}
                    try(LocalSocket socket=client){
                        if(socket.getPeerCredentials().getUid()!=0)continue;
                        socket.setSoTimeout(2000);
                        BufferedInputStream in=new BufferedInputStream(socket.getInputStream());
                        StringBuilder request=new StringBuilder();int c;
                        while((c=in.read())!=-1&&c!='\n'&&request.length()<26000)request.append((char)c);
                        if(c!='\n'||!request.toString().startsWith("ICONS\t"))continue;
                        String response=icons(request.toString(),endpoint.get())+"\n";
                        socket.getOutputStream().write(response.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                    }catch(Exception e){
                        if(endpoint.get()==null||!endpoint.get().isBinderAlive())break;
                        // One expired/slow client must not disable subsequent batches.
                    }
                }
                try{server.close();}catch(Exception ignored){}
            },"backup-icon-socket");worker.setDaemon(true);worker.start();
        }catch(Exception e){System.err.println("BACKUP_ICON_SOCKET_UNAVAILABLE "+e.getClass().getSimpleName());}
    }
    public static void main(String[] args){
        try {
            DaemonHardening.protectSelf("webview-controller");
            HiddenApiBypassBridge.installExemptionsOnce();Object atm=activity();
            if(args.length>0&&args[0].equals("--origin")){originServer(args,atm);return;}
            if(args.length==1&&args[0].equals("--notification-check")){
                String result=originCommand(System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET"),ownerIdentity(System.getenv("SPEEDBACKUP_WEB_OWNER_PID")),"HOST_OPEN");
                System.out.println(result);System.out.flush();System.exit("OK".equals(result)?0:130);return;
            }
            if(args.length==2&&args[0].equals("--prepare-origin")){
                String owner=System.getenv("SPEEDBACKUP_WEB_OWNER_PID"),identity=ownerIdentity(owner),name=System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET");
                if(identity==null||name==null)throw new IllegalStateException("origin scope missing");
                if(args[1].equals("1")){
                    List<?> current=tasks(atm);if(current.isEmpty())throw new IllegalStateException("terminal absent");
                    ensureOrigin(name,owner,identity,new Task(current.get(0)));
                }else if(!args[1].equals("0")||!"OK".equals(originCommand(name,identity,"PROBE")))throw new IllegalStateException("original terminal session lost");
                System.out.println("ORIGIN_OK");System.out.flush();System.exit(0);return;
            }
            if(args.length==3&&args[0].equals("--rebind-origin")){
                if(!args[2].equals(ownerIdentity(args[1]))||!unlocked())throw new SecurityException("invoker changed or locked");
                List<?> current=tasks(atm);if(current.isEmpty())throw new SecurityException("reopen foreground absent");
                Task candidate=new Task(current.get(0));
                if(candidate.windowing!=1||(PACKAGE.equals(candidate.top.getPackageName())&&!ownLauncher(candidate))||(Build.VERSION.SDK_INT>=30&&candidate.token==null))throw new SecurityException("reopen foreground unsupported: component="+candidate.top.flattenToShortString()+" mode="+candidate.windowing+" token="+(candidate.token!=null));
                checkAncestor(args[1],candidate,true);
                String owner=System.getenv("SPEEDBACKUP_WEB_OWNER_PID"),identity=ownerIdentity(owner),name=System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET");
                String action="REBIND "+args[1]+" "+args[2]+" "+candidate.id+" "+candidate.user+" "+candidate.display+" "+componentKey(candidate.base)+" "+componentKey(candidate.top);
                String result;
                try{result=originCommand(name,identity,action);}catch(IOException absent){
                    if(!args[2].equals(ownerIdentity(args[1])))throw new SecurityException("invoker ended");
                    ensureOrigin(name,owner,identity,candidate);result=originCommand(name,identity,action);
                }
                System.out.println(result);System.out.flush();System.exit("OK".equals(result)?0:130);return;
            }
            if(args.length==1&&args[0].equals("--focus-origin")){
                String result=originCommand(System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET"),ownerIdentity(System.getenv("SPEEDBACKUP_WEB_OWNER_PID")),"FOCUS");
                System.out.println(result);System.out.flush();System.exit(returned(result)?0:130);return;
            }
            if(args.length==1&&args[0].equals("--check")){
                int user=number(call(HiddenApiServices.activity(),"getCurrentUser"),"id",-1);
                if(user<0)throw new IllegalStateException("current user unavailable");
                if(verify(installed(user))){System.out.println("OK");System.exit(0);return;}
                System.out.println("INSTALL\t"+user);System.exit(10);return;
            }
            List<?> list=tasks(atm);if(list.isEmpty())throw new IllegalStateException("origin absent");
            Task origin=new Task(list.get(0));
            if(origin.user<0)throw new IllegalStateException("origin unsupported");
            if(args.length!=1)throw new IllegalStateException("native APK unavailable");
            String url=args[0];Uri uri=Uri.parse(url);
            if(!"http".equals(uri.getScheme())||!"127.0.0.1".equals(uri.getHost())||uri.getPort()<1||uri.getUserInfo()!=null||!"/".equals(uri.getPath())||uri.getQuery()!=null||uri.getFragment()==null||!uri.getFragment().matches("[0-9a-f]{64}"))throw new IllegalArgumentException("URL");
            String owner=System.getenv("SPEEDBACKUP_WEB_OWNER_PID");
            final String identity=ownerIdentity(owner);
            final String originName=System.getenv("SPEEDBACKUP_WEB_ORIGIN_SOCKET");
            final boolean scoped=identity!=null&&originName!=null;
            if(identity!=null&&!scoped)throw new IllegalStateException("origin scope missing");
            if(scoped){
                if(!"OK".equals(originCommand(originName,identity,"PROBE")))throw new IllegalStateException("original terminal session lost");
                if(!"OK".equals(originCommand(originName,identity,"OPEN"))){
                    System.out.println("WAIT_FOREGROUND");System.out.flush();long deadline=System.nanoTime()+TimeUnit.MINUTES.toNanos(15);
                    while(true){
                        if(!identity.equals(ownerIdentity(owner))||System.nanoTime()>=deadline)throw new IllegalStateException("foreground wait ended");
                        if("OK".equals(originCommand(originName,identity,"OPEN")))break;
                        Thread.sleep(250);
                    }
                }
            }else if(!unlocked())throw new IllegalStateException("screen locked");
            list=tasks(atm);if(list.isEmpty())throw new IllegalStateException("foreground absent");
            origin=new Task(list.get(0));
            if(origin.user<0||(origin.windowing!=1&&(!scoped||!supportedHostWindow(origin))))throw new IllegalStateException("foreground unsupported");
            PackageInfo info=installed(origin.user);
            if(!verify(info)){System.out.println("INSTALL\t"+origin.user);System.out.flush();System.exit(10);return;}
            prepareHostAccess(origin.user);
            Thread shortcutAccess=new Thread(()->prepareShortcutAccess(info),"shortcut-access");
            shortcutAccess.setDaemon(true);shortcutAccess.start();
            shortcutAccess.join(500);
            if(shortcutAccess.isAlive())System.err.println("SHORTCUT_ACCESS status=pending_background");
            final int uid=info.applicationInfo.uid;
            CountDownLatch ready=new CountDownLatch(1),event=new CountDownLatch(1),closed=new CountDownLatch(1),held=new CountDownLatch(1);
            AtomicReference<IBinder> endpoint=new AtomicReference<>();AtomicInteger command=new AtomicInteger();
            final AtomicReference<CountDownLatch> navigation=new AtomicReference<>();
            final AtomicInteger navigationAccepted=new AtomicInteger();
            final AtomicReference<String> navigationId=new AtomicReference<>();
            Binder session=new Binder(){@Override protected boolean onTransact(int code,Parcel data,Parcel reply,int flags)throws RemoteException{
                if(Binder.getCallingUid()!=uid)return false;
                data.enforceInterface(PROTOCOL);
                if(code==1){IBinder b=data.readStrongBinder();if(b==null||!endpoint.compareAndSet(null,b))return false;
                    b.linkToDeath(()->{command.compareAndSet(0,3);closed.countDown();event.countDown();},0);ready.countDown();return true;}
                if(code==2||code==4){if(code==4)command.set(4);else command.compareAndSet(0,3);closed.countDown();event.countDown();return true;}
                if(code==5){held.countDown();return true;}
                if(code==6){String id=data.readString();int accepted=data.readInt();CountDownLatch pending=navigation.get();if(pending!=null&&id!=null&&id.equals(navigationId.get())){navigationAccepted.set(accepted);pending.countDown();}return true;}return false;
            }};
            Intent intent=new Intent(Intent.ACTION_VIEW,uri).setComponent(new ComponentName(PACKAGE,PACKAGE+".MainActivity"));
            // Package-update auto-relaunch may carry a dead Binder from the previous task.
            // Only after a verified container installation replace that UI task; the root work stays alive.
            boolean freshTask="1".equals(System.getenv("SPEEDBACKUP_WEBVIEW_FRESH_TASK"));
            intent.addFlags(freshTask ? Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK : Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);
            if(freshTask)System.err.println("WEBVIEW_LAUNCH fresh_task=package_updated");Bundle extras=new Bundle();extras.putBinder("session",session);extras.putBoolean("debug","1".equals(System.getenv("SPEEDBACKUP_WEBVIEW_DEBUG")));extras.putBoolean("cancelOnPause","1".equals(System.getenv("SPEEDBACKUP_WEB_CANCEL_ON_PAUSE")));String consoleUrl=System.getenv("SPEEDBACKUP_CONSOLE_URL");
            if(consoleUrl!=null){extras.putString("consoleUrl",consoleUrl);extras.putString("guardSocket",originName);}
            extras.putString("uiLanguage",System.getenv("SPEEDBACKUP_UI_LANGUAGE"));
            extras.putString("shortcutEntry",System.getenv("SPEEDBACKUP_SHORTCUT_ENTRY"));
            extras.putString("shortcutMode",System.getenv("SPEEDBACKUP_SHORTCUT_MODE"));
            extras.putString("shortcutBackend",System.getenv("SPEEDBACKUP_SHORTCUT_BACKEND"));
            intent.putExtras(extras);
            boolean permissionSetup=consoleUrl!=null&&Build.VERSION.SDK_INT>=33;
            if(permissionSetup){System.out.println("WAIT_HOST_SETUP");System.out.flush();}
            Object result;
            try{result=call(atm,"startActivityAsUser",null,"com.android.shell",null,intent,null,null,null,0,0,null,null,origin.user);}
            catch(NoSuchMethodException older){result=call(atm,"startActivityAsUser",null,"com.android.shell",intent,null,null,null,0,0,null,null,origin.user);}
            // Positive Android start results can also mean an aborted/background-blocked
            // launch. Results 0..4 can deliver an Activity; do not hide those failures
            // behind a two-minute Binder timeout.
            if(!(result instanceof Integer)||((Integer)result)<0||((Integer)result)>4)
                throw new IllegalStateException("native APK start rejected: result="+result+" user="+origin.user);
            if(!ready.await(permissionSetup?120:8,TimeUnit.SECONDS)) {
                int currentUid=-1;try{PackageInfo latest=installed(origin.user);if(latest!=null)currentUid=latest.applicationInfo.uid;}catch(Exception ignored){}
                throw new IllegalStateException("native APK Binder READY timeout: startResult="+result+" user="+origin.user+" hostUid="+uid+" currentUid="+currentUid);
            }
            // READY is authenticated by the host UID and a live endpoint Binder.
            // Losing foreground while opening is not a process/session failure.
            if(closed.getCount()==0||endpoint.get()==null||!endpoint.get().isBinderAlive())
                throw new IllegalStateException("native APK closed during bind");
            iconSocket(originName,endpoint);
            System.out.println("READY");System.out.flush();
            final ExecutorService iconWorker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"webview-icons");t.setDaemon(true);return t;});
            final AtomicBoolean iconsDown=new AtomicBoolean(),iconsBusy=new AtomicBoolean();
            Thread input=new Thread(()->{try{
                BufferedInputStream commands=new BufferedInputStream(System.in);
                StringBuilder line;int c;
                while(true){
                    line=new StringBuilder();
                    while((c=commands.read())!=-1&&c!='\n'&&line.length()<26000)line.append((char)c);
                    if(c=='\n'&&line.toString().startsWith("NAV\t")){
                        String[] nav=line.toString().split("\t",3);if(nav.length!=3||!nav[1].matches("[0-9a-f]{64}"))throw new SecurityException("navigation id");
                        boolean ok=false,detached=false;CountDownLatch done=new CountDownLatch(1);
                        try{
                            String target=nav[2];Uri targetUri=Uri.parse(target);
                            if(!"http".equals(targetUri.getScheme())||!"127.0.0.1".equals(targetUri.getHost())||targetUri.getPort()<1||targetUri.getUserInfo()!=null||!"/".equals(targetUri.getPath())||targetUri.getQuery()!=null||targetUri.getFragment()==null||!targetUri.getFragment().matches("[0-9a-f]{64}"))throw new SecurityException("navigation URL");
                            // An existing authenticated Binder can update its page in the background.
                            // This does not launch/focus an Activity or change the current app.
                            if(!scoped||!identity.equals(ownerIdentity(owner))||!"OK".equals(originCommand(originName,identity,"PROBE"))||closed.getCount()==0||endpoint.get()==null||!endpoint.get().isBinderAlive()){
                                detached=true;throw new SecurityException("navigation session closed");
                            }
                            navigationAccepted.set(0);navigationId.set(nav[1]);navigation.set(done);Parcel data=Parcel.obtain();
                            try{data.writeInterfaceToken(PROTOCOL);data.writeString(nav[1]);data.writeString(target);if(!endpoint.get().transact(5,data,null,IBinder.FLAG_ONEWAY))throw new IOException("navigation unsupported");}finally{data.recycle();}
                            boolean answered=done.await(10,TimeUnit.SECONDS);int accepted=navigationAccepted.get();
                            ok=answered&&accepted==1;detached=accepted==2||closed.getCount()==0;
                            if(!ok)System.err.println("WEBVIEW_NAVIGATION_RESULT answered="+answered+" accepted="+accepted+" windowClosed="+(closed.getCount()==0));
                        }catch(Exception e){System.err.println("WEBVIEW_NAVIGATION_FALLBACK "+e.getClass().getSimpleName()+": "+e.getMessage());}
                        finally{navigation.compareAndSet(done,null);navigationId.compareAndSet(nav[1],null);}
                        System.out.println((detached?"NAV_CLOSED":ok?"NAV_OK":"NAV_FALLBACK")+"\t"+nav[1]);System.out.flush();continue;
                    }
                    if(c=='\n'&&line.toString().startsWith("ICONS\t")){
                        final String request=line.toString();
                        if(!iconsDown.get()&&iconsBusy.compareAndSet(false,true)){
                            iconWorker.submit(()->{try{System.out.println(icons(request,endpoint.get()));}catch(Exception e){iconsDown.set(true);System.out.println("ICONS\t");}finally{System.out.flush();iconsBusy.set(false);}});
                        }else{System.out.println("ICONS\t");System.out.flush();}
                        continue;
                    }
                    break;
                }
                int mode=c=='\n'&&line.toString().equals("RETURN")?1:
                    identity!=null&&c=='\n'&&line.toString().equals("HOLD")?5:
                    identity!=null&&c=='\n'&&line.toString().equals("BACKGROUND")?6:2;
                command.compareAndSet(0,mode);
            }catch(Exception e){command.compareAndSet(0,2);}finally{event.countDown();}},"webview-command");input.setDaemon(true);input.start();
            event.await();
            if(command.get()==5||command.get()==6){
                int mode=command.get();
                Parcel data=Parcel.obtain();try{data.writeInterfaceToken(PROTOCOL);endpoint.get().transact(2,data,null,IBinder.FLAG_ONEWAY);}finally{data.recycle();}
                if(!held.await(3,TimeUnit.SECONDS))throw new IllegalStateException("handoff not acknowledged");
                if(mode==6&&!returned(scoped?originCommand(originName,identity,"FOCUS"):restore(atm,origin,PACKAGE))){
                    System.out.println("FOCUS_FAILED");System.out.flush();System.exit(65);return;
                }
                System.out.println("HELD");System.out.flush();
                // Keep the Binder alive across the short-lived Rust servers. An owner
                // identity check also closes the card if the script dies in the gap.
                long foregroundDeadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(60);
                boolean foregroundHold=mode==5;
                while(!closed.await(250,TimeUnit.MILLISECONDS)){
                    // A failed successor must not hide a terminal fallback forever.
                    // Keep the card, but reveal the terminal after a bounded HOLD.
                    if(foregroundHold&&System.nanoTime()>=foregroundDeadline){
                        String focused=scoped?originCommand(originName,identity,"FOCUS"):restore(atm,origin,PACKAGE);
                        if(!returned(focused)){Parcel back=Parcel.obtain();try{back.writeInterfaceToken(PROTOCOL);endpoint.get().transact(1,back,null,IBinder.FLAG_ONEWAY);}finally{back.recycle();}}
                        foregroundHold=false;
                    }
                    if(!identity.equals(ownerIdentity(owner))){
                        Parcel close=Parcel.obtain();try{close.writeInterfaceToken(PROTOCOL);endpoint.get().transact(1,close,null,IBinder.FLAG_ONEWAY);}finally{close.recycle();}
                        closed.await(3,TimeUnit.SECONDS);break;
                    }
                }
            }else if(command.get()==1){
                boolean focused=scoped&&returned(originCommand(originName,identity,"FOCUS"));
                Parcel data=Parcel.obtain();try{data.writeInterfaceToken(PROTOCOL);endpoint.get().transact(1,data,null,IBinder.FLAG_ONEWAY);}finally{data.recycle();}
                if(closed.await(3,TimeUnit.SECONDS)){String returned=scoped?originCommand(originName,identity,"AFTER_CLOSE"):restoreAfterExternalClose(atm,origin,PACKAGE);System.out.println(focused||returned(returned)?"CLOSED_RETURNED":"CLOSED_RETURN_UNCONFIRMED");}
                else System.out.println("SKIP_CLOSE_FAILED");
            }else if(command.get()==3){if(scoped)originCommand(originName,identity,"AFTER_CLOSE");else restoreAfterExternalClose(atm,origin,PACKAGE);System.out.println("WINDOW_CLOSED");}
            System.out.flush();System.exit(0);
        }catch(Throwable e){System.err.println("WEBVIEW_RETURN_UNAVAILABLE "+e.getClass().getSimpleName()+": "+e.getMessage());System.out.println("SKIP_UNAVAILABLE");System.out.flush();System.exit(65);}
    }
}
