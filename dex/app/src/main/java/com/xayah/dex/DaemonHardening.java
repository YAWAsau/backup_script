package com.xayah.dex;

import java.io.File;
import java.io.FileWriter;

/** Best-effort daemon survival hardening. All failures are non-fatal. */
final class DaemonHardening {
    private DaemonHardening() {}

    static void protectSelf(String component) {
        protectPid(currentPid(), component);
        try { Thread.currentThread().setPriority(Thread.MAX_PRIORITY); } catch (Throwable ignored) {}
    }

    static void protectPid(int pid, String component) {
        if (pid <= 1) return;
        writeProc("/proc/" + pid + "/oom_score_adj", "-900\n");
        writeProc("/proc/" + pid + "/oom_adj", "-16\n");
        // Android app_process usually lacks CAP_SYS_NICE; this is intentionally best-effort.
        try { Runtime.getRuntime().exec(new String[]{"/system/bin/renice", "-n", "-5", "-p", String.valueOf(pid)}).waitFor(); } catch (Throwable ignored) {}
        try { Runtime.getRuntime().exec(new String[]{"renice", "-n", "-5", "-p", String.valueOf(pid)}).waitFor(); } catch (Throwable ignored) {}
    }

    static int currentPid() {
        try { return android.os.Process.myPid(); } catch (Throwable ignored) {}
        try { return Integer.parseInt(new File("/proc/self").getCanonicalFile().getName()); } catch (Throwable ignored) {}
        return -1;
    }

    private static void writeProc(String path, String value) {
        try (FileWriter fw = new FileWriter(path, false)) { fw.write(value); } catch (Throwable ignored) {}
    }
}
