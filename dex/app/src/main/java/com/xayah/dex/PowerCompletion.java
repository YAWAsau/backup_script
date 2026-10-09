package com.xayah.dex;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.*;

/** Short-lived completion coordinator. No dependency on the backup daemon or TTY reader. */
final class PowerCompletion {
    interface Calls { String call(String command) throws Exception; }
    private final File dir;
    private final String key;
    private final Calls calls;
    private String wakeTag;

    PowerCompletion(File dir, String key, Calls calls) { this.dir=dir; this.key=key; this.calls=calls; }

    static void run(String id, String key, File store) throws Exception {
        if (!id.matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) throw new IOException("job");
        PowerNotifyUtil.secure(store, true);
        File dir = new File(store, id); PowerNotifyUtil.secure(dir, true);
        // One claim survives cancellation and repeated callers. Never restart a countdown.
        File claim = new File(dir, "coordinator");
        if (!claim.createNewFile()) return;
        android.system.Os.chmod(claim.getPath(), 0600);
        new PowerCompletion(dir, key, command -> PowerNotifyUtil.execute(new String[]{command,id},store)).run();
    }

    void run() throws Exception {
        try {
            String workers = PowerNotifyUtil.read(new File(dir,"workers"),65536);
            for (String pid : workers.split("\n")) {
                if (pid.isEmpty()) continue;
                if (!pid.matches("[1-9][0-9]*") || new File("/proc/"+pid).exists()) {
                    ui("無法確認工作程序已收尾，本次略過關機提示。\n"); return;
                }
            }
            String outcome = PowerNotifyUtil.read(new File(dir,"ready"),32).trim();
            if (!java.util.Arrays.asList("success","partial","failed","cancelled").contains(outcome)) return;
            if (!new File(key).isAbsolute() || !new File(key).canExecute()) return;
            acquire();
            if (!"AVAILABLE".equals(bounded("offer",55))) return;
            ui("success".equals(outcome) ? "\n本輪作業已完成。\n" : "\n本輪有失敗、部分完成或中斷，請先確認上述結果。\n");
            ui("已啟用備份／恢復後電腦關機。30 秒內可取消。\n音量上：取消；音量下：立即送出；30 秒未取消：自動送出關機請求。\n");
            if (!countdown(key,30)) { ui("已取消本次電腦關機。\n"); return; }
            ui("送出電腦關機請求。\n");
            long deadline = System.nanoTime()+TimeUnit.SECONDS.toNanos(120);
            boolean shown = false;
            String reply;
            while (true) {
                long remaining = TimeUnit.NANOSECONDS.toSeconds(deadline-System.nanoTime());
                if (remaining <= 0) { reply="PAIRING_REQUIRED"; break; }
                reply=bounded("complete", Math.min(55,remaining));
                if (!reply.startsWith("PAIRING_REQUIRED ")) break;
                String fingerprint=reply.substring(17);
                if (!fingerprint.matches("[0-9a-f]{64}")) { reply="NOTIFICATION_FAILED"; break; }
                if (!shown) { ui("首次配對：請在電腦 Server 核對並允許此手機。裝置指紋：\n"+fingerprint+"\n等待最長 120 秒；之後不需重複批准。\n"); shown=true; }
                Thread.sleep(Math.min(3000,Math.max(0,TimeUnit.NANOSECONDS.toMillis(deadline-System.nanoTime()))));
            }
            switch(reply) {
                case "PAIRING_REQUIRED": ui("首次使用請在電腦 Server 允許此手機配對；本次未送出關機。\n"); break;
                case "STATE waiting": case "STATE countdown": case "STATE deferred": ui("電腦已接受關機請求，可在電腦上取消或延後；尚未確認關機。\n"); break;
                case "STATE shutting_down": ui("電腦已提交關機操作；尚未確認電源關閉。\n"); break;
                case "STATE simulated": ui("Server 已完成預覽請求，不會真的關機。\n"); break;
                case "STATE cancelled": case "STATE closed": ui("此請求已取消或結束，不會重新安排關機。\n"); break;
                default: ui("電腦關機通知未成功；已完成的備份／恢復結果不受影響。\n");
            }
        } finally { release(); }
    }

    private String bounded(String command,long seconds) throws Exception {
        FutureTask<String> task = new FutureTask<>(() -> calls.call(command));
        Thread t=new Thread(task,"power-stage"); t.setDaemon(true); t.start();
        try { return task.get(seconds,TimeUnit.SECONDS); }
        catch (Exception e) { task.cancel(true); throw e; }
    }

    static boolean countdown(String key, int seconds) throws Exception {
        Process p = new ProcessBuilder(key).redirectError(new File("/dev/null")).start();
        ByteArrayOutputStream captured = new ByteArrayOutputStream();
        Thread drain = new Thread(() -> {
            try (InputStream in=p.getInputStream()) {
                byte[] b=new byte[256]; int n;
                while ((n=in.read(b))!=-1) synchronized(captured) { if(captured.size()+n<=4096) captured.write(b,0,n); }
            } catch(IOException ignored) {}
        },"power-key-output"); drain.setDaemon(true); drain.start();
        try {
            if (!p.waitFor(seconds,TimeUnit.SECONDS)) return true;
            drain.join(100);
            int rc=p.exitValue();
            if (rc==42 || rc==46 || rc==56) return false;
            if (rc==41 || rc==47 || rc==57) return true;
            if (rc!=0) return false; // Crash/early SIGKILL must cancel, never imply timeout.
            String text; synchronized(captured) { text=new String(captured.toByteArray(),StandardCharsets.UTF_8); }
            String first=text.split("\n",2)[0].replace("\r","").trim().toLowerCase(java.util.Locale.ROOT);
            // Preserve the existing volume-only parser, including long-press aliases.
            if (first.matches(".*vol.*up.*") || first.equals("vol+") || first.equals("volume+")) return false;
            return first.matches(".*vol.*down.*") || first.equals("vol-") || first.equals("volume-")
                    || first.equals("long_vol-") || first.equals("114") || first.equals("25");
        } finally { p.destroyForcibly(); }
    }

    private void acquire() {
        String tag="speedbackup-power-"+android.os.Process.myPid()+"-"+System.nanoTime();
        try {
            Files.write(new File("/sys/power/wake_lock").toPath(),(tag+" 300000000000\n").getBytes(StandardCharsets.UTF_8));
            wakeTag=tag; log("POWER_WAKE acquired tag="+tag+" maxSeconds=300\n");
        } catch(Exception e) { ui("無法取得短期 CPU 喚醒鎖；熄屏可能延後關機倒數。\n"); }
    }
    private void release() {
        if(wakeTag==null) return;
        try { Files.write(new File("/sys/power/wake_unlock").toPath(),(wakeTag+"\n").getBytes(StandardCharsets.UTF_8)); log("POWER_WAKE release tag="+wakeTag+"\n"); }
        catch(Exception e) { log("POWER_WAKE release_failed boundedByKernel=300\n"); }
        wakeTag=null;
    }
    private void log(String text) {
        try {
            File f=new File(dir,"ui.log");
            if(f.exists()) PowerNotifyUtil.secure(f,false);
            else { if(!f.createNewFile()) return; android.system.Os.chmod(f.getPath(),0600); }
            try(FileOutputStream out=new FileOutputStream(f,true)) { out.write(text.getBytes(StandardCharsets.UTF_8)); }
        } catch(Exception ignored) {}
    }
    private void ui(String text) {
        log(text);
        // A blocked terminal can only block a daemon writer for the remaining process lifetime.
        Thread t=new Thread(() -> { try { System.out.print(text); System.out.flush(); } catch(Exception ignored) {} },"power-ui");
        t.setDaemon(true); t.start();
        try { t.join(1000); } catch(InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
