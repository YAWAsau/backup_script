package com.xayah.dex;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.*;

/** Short-lived completion coordinator. No dependency on the backup daemon or TTY reader. */
final class PowerCompletion {
    interface Calls { String call(String command) throws Exception; }
    private final File dir;
    private final String webNative;
    private final Calls calls;
    private String wakeTag;

    PowerCompletion(File dir, String webNative, Calls calls) { this.dir=dir; this.webNative=webNative; this.calls=calls; }

    static void run(String id, String webNative, File store) throws Exception {
        if (!id.matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) throw new IOException("job");
        PowerNotifyUtil.secure(store, true);
        File dir = new File(store, id); PowerNotifyUtil.secure(dir, true);
        // One claim survives cancellation and repeated callers. Never restart a countdown.
        File claim = new File(dir, "coordinator");
        if (!claim.createNewFile()) return;
        android.system.Os.chmod(claim.getPath(), 0600);
        new PowerCompletion(dir, webNative, command -> PowerNotifyUtil.execute(new String[]{command,id},store)).run();
    }

    void run() throws Exception {
        boolean completionAttempted = false;
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
            if ("cancelled".equals(outcome)) { ui("本輪作業已取消，本次不發送電腦關機請求。\n"); return; }
            if (!new File(webNative).isAbsolute() || !new File(webNative).canExecute()) return;
            acquire();
            if (!"AVAILABLE".equals(bounded("offer",55))) return;
            ui("success".equals(outcome) ? "\n本輪作業已完成。\n" : "\n本輪有失敗、部分完成或中斷，請先確認上述結果。\n");
            ui("已啟用備份／恢復後電腦關機。30 秒內可取消。\n網頁可選取消或立即送出；顯示後倒數 30 秒，未取消則送出關機請求。\n");
            if (!countdown(webNative,dir)) { ui("已取消本次電腦關機。\n"); return; }
            ui("送出電腦關機請求。\n");
            long deadline = System.nanoTime()+TimeUnit.SECONDS.toNanos(120);
            boolean shown = false;
            String reply;
            while (true) {
                long remaining = TimeUnit.NANOSECONDS.toSeconds(deadline-System.nanoTime());
                if (remaining <= 0) { reply="PAIRING_REQUIRED"; break; }
                completionAttempted = true;
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
                case "NOTIFICATION_UNCERTAIN": ui("關機請求回覆未確認，為避免重複操作不會重送；請在電腦上確認狀態。\n"); break;
                case "STATE simulated": ui("Server 已完成預覽請求，不會真的關機。\n"); break;
                case "STATE cancelled": case "STATE closed": ui("此請求已取消或結束，不會重新安排關機。\n"); break;
                default: ui("電腦關機通知未成功；已完成的備份／恢復結果不受影響。\n");
            }
        } catch (Exception e) {
            log("POWER_COMPLETION_FAILED reason="+e.getClass().getSimpleName()+"\n");
            ui(completionAttempted ? "關機請求逾時或回覆未確認，可能已送達；請在電腦端確認，不會自動重送。\n" : "電腦關機服務檢查失敗或逾時，本次未發送關機請求；備份／恢復結果不受影響。\n");
            throw e;
        } finally { release(); }
    }

    private String bounded(String command,long seconds) throws Exception {
        FutureTask<String> task = new FutureTask<>(() -> calls.call(command));
        Thread t=new Thread(task,"power-stage"); t.setDaemon(true); t.start();
        try { return task.get(seconds,TimeUnit.SECONDS); }
        catch (Exception e) { task.cancel(true); throw e; }
    }

    static boolean countdown(String webNative, File jobDir) throws Exception {
        PowerNotifyUtil.secure(jobDir,true);
        File work=Files.createTempDirectory(jobDir.toPath(),"web-").toFile();
        android.system.Os.chmod(work.getPath(),0700);
        File input=new File(work,"input"),result=new File(work,"result");
        Process process=null;
        try {
            PowerNotifyUtil.write(input,"電腦關機倒數\nMODE\tpower-countdown\t30\nCHOICE\t1\t立即送出\nCHOICE\t0\t取消\n");
            ProcessBuilder builder=new ProcessBuilder(webNative,"menu-web",input.getPath(),result.getPath(),"--open");
            // Completion needs a bounded fresh window; no old menu handoff wait.
            builder.environment().put("SPEEDBACKUP_WEB_CANCEL_ON_PAUSE","1");
            builder.environment().remove("SPEEDBACKUP_WEB_OWNER_PID");
            builder.environment().remove("SPEEDBACKUP_WEB_ORIGIN_SOCKET");
            builder.redirectOutput(new File("/dev/null"));builder.redirectError(new File("/dev/null"));
            process=builder.start();
            if(!process.waitFor(100,TimeUnit.SECONDS) || process.exitValue()!=0)return false;
            PowerNotifyUtil.secure(result,false);
            return "1\n".equals(PowerNotifyUtil.read(result,16));
        } finally {
            if(process!=null){process.destroyForcibly();process.waitFor(3,TimeUnit.SECONDS);}
            Files.deleteIfExists(result.toPath());Files.deleteIfExists(input.toPath());Files.deleteIfExists(work.toPath());
        }
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
