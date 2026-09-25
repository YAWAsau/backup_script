package com.xayah.dex;

import java.io.File;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.FileWriter;

/** Best-effort daemon survival hardening. All failures are non-fatal. */
final class DaemonHardening {
    private DaemonHardening() {}

    static void protectSelf(String component) {
        protectPid(currentPid(), component);
    }

    static void protectPid(int pid, String component) {
        if (pid <= 1) return;
        File modern = new File("/proc/" + pid + "/oom_score_adj");
        // Preserve stronger inherited protection, including root shells at -1000.
        // Writing legacy oom_adj after the modern interface remaps the score.
        if (modern.exists()) {
            lowerProcScore(modern, -900);
        } else {
            lowerProcScore(new File("/proc/" + pid + "/oom_adj"), -16);
        }
        // Direct syscall through Android's API: no external process or waitFor
        // on the READY path or recurring supervisor tick. Never weaken nice.
        try {
            if (android.os.Process.getThreadPriority(pid) > -5) {
                android.os.Process.setThreadPriority(pid, -5);
            }
        } catch (Throwable ignored) {}
    }

    static int currentPid() {
        try { return android.os.Process.myPid(); } catch (Throwable ignored) {}
        try { return Integer.parseInt(new File("/proc/self").getCanonicalFile().getName()); } catch (Throwable ignored) {}
        return -1;
    }

    private static void lowerProcScore(File path, int target) {
        try {
            int current;
            try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
                current = Integer.parseInt(reader.readLine().trim());
            }
            if (current > target) {
                try (FileWriter writer = new FileWriter(path, false)) {
                    writer.write(Integer.toString(target));
                    writer.write('\n');
                }
            }
        } catch (Throwable ignored) {}
    }
}
