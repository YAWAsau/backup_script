package com.xayah.dex;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.locks.ReentrantLock;

/** Request-local utilities; no cached battery state or process-wide exit. */
final class BackupUtilities {
    private static final ReentrantLock ICONS = new ReentrantLock();
    private static final ReentrantLock BATTERY = new ReentrantLock();
    private static final java.util.concurrent.ExecutorService DUMPS = new java.util.concurrent.ThreadPoolExecutor(2,2,0,
            java.util.concurrent.TimeUnit.SECONDS,new java.util.concurrent.ArrayBlockingQueue<>(2),r->{Thread t=new Thread(r,"battery-binder");t.setDaemon(true);return t;});
    // Root app_process is not an AMS application; newer Android rejects its sticky
    // receiver query. Use the same service operations as the legacy commands,
    // directly over Binder, with bounded output/time and no child processes.
    private static String dump(String service,String... args) throws Exception {
        android.os.IBinder binder=(android.os.IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,service);
        if(binder==null)throw new java.io.IOException("service unavailable");
        android.os.ParcelFileDescriptor[] pipe=android.os.ParcelFileDescriptor.createPipe();
        java.util.concurrent.Future<?> writer=null;
        java.util.concurrent.Future<String> reader=null;
        try {
            reader=DUMPS.submit(()->{try(java.io.InputStream in=new android.os.ParcelFileDescriptor.AutoCloseInputStream(pipe[0])){
                java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] buf=new byte[2048];int n;
                while((n=in.read(buf))!=-1){if(out.size()+n>65536)throw new java.io.IOException("battery output limit");out.write(buf,0,n);}
                return out.toString("UTF-8");
            }});
            writer=DUMPS.submit(()->{try{binder.dump(pipe[1].getFileDescriptor(),args);}finally{pipe[1].close();}return null;});
            writer.get(2,java.util.concurrent.TimeUnit.SECONDS);
            return reader.get(2,java.util.concurrent.TimeUnit.SECONDS);
        } finally {
            try{pipe[0].close();}catch(Exception ignored){}try{pipe[1].close();}catch(Exception ignored){}
            if(writer!=null)writer.cancel(true);if(reader!=null)reader.cancel(true);
        }
    }
    static boolean accepts(String command) {
        return "backupBatteryState".equals(command) || "backupIcons".equals(command);
    }
    private static DisplayTimeoutSettings.Result result(int rc,String body) {
        return new DisplayTimeoutSettings.Result(rc,rc==0?"OK":"FAIL",body);
    }
    static DisplayTimeoutSettings.Result run(String command,byte[] body) {
        if(body.length>4096)return result(2,"UTILITY_BAD_REQUEST\n");
        try {
            if("backupBatteryState".equals(command)) {
                if(body.length!=0)return result(2,"BATTERY_BAD_REQUEST\n");
                HiddenApiBypassBridge.installExemptionsOnce();
                if(!BATTERY.tryLock())return result(75,"BATTERY_BUSY\n");
                try {
                    String charging=dump("deviceidle","get","charging").trim();
                    String battery=dump("battery");
                    java.util.regex.Matcher level=java.util.regex.Pattern.compile("(?m)^\\s*level:\\s*([0-9]+)\\s*$").matcher(battery);
                    if(!level.find()||!(charging.equals("true")||charging.equals("false")))return result(69,"BATTERY_UNAVAILABLE\n");
                    return result(0,Integer.parseInt(level.group(1))+"\t"+charging+"\n");
                } finally { BATTERY.unlock(); }
            }
            String[] args=new String(body,StandardCharsets.UTF_8).split("\n",-1);
            if(!"backupIcons".equals(command)||args.length!=6||!args[5].isEmpty()
                    ||!args[0].matches("[0-9]{1,5}")||!args[1].startsWith("/")||!args[2].startsWith("/")
                    ||!(args[3].equals("normal")||args[3].equals("refresh"))
                    ||args[4].isEmpty()||args[4].length()>90||args[4].indexOf('\0')>=0)
                return result(2,"ICONS_BAD_REQUEST\n");
            if(!ICONS.tryLock())return result(75,"ICONS_BUSY\n");
            try {
                int rc=AppListIcons.run(new String[]{args[0],args[1],args[2],args[3]},args[4]);
                return result(rc,"ICONS_DONE rc="+rc+"\n");
            } finally { ICONS.unlock(); }
        } catch(Exception e) {
            return result(69,"UTILITY_UNAVAILABLE "+e.getClass().getSimpleName()+"\n");
        }
    }
}
