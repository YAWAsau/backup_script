package com.xayah.dex;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Small app_process watchdog used by tools.sh to supervise root-side Dex daemons.
 * It cannot resurrect a killed tools.sh, but it can restart a killed child daemon while the
 * owner process is alive. Usage:
 *   supervise COMPONENT PID_FILE SOCKET_OR_DASH OWNER_PID INTERVAL_MS -- command ...
 */
public final class DaemonSupervisorUtil {
    private DaemonSupervisorUtil() {}

    public static void main(String[] args) throws Exception {
        if (args.length == 0 || "help".equals(args[0])) { usage(); return; }
        if ("version".equals(args[0]) || "--version".equals(args[0]) || "-v".equals(args[0])) {
            System.out.println("DaemonSupervisorUtil v1.0 dex=" + HiddenApiUtil.VERSION);
            return;
        }
        if (!"supervise".equals(args[0])) { usage(); System.exit(2); }
        if (args.length < 8) { usage(); System.exit(2); }
        String component = safe(args[1]);
        File pidFile = new File(args[2]);
        String socketPath = args[3];
        int ownerPid = parseInt(args[4], -1);
        long intervalMs = Math.max(500L, parseLong(args[5], 1500L));
        int sep = -1;
        for (int i = 6; i < args.length; i++) if ("--".equals(args[i])) { sep = i; break; }
        if (sep < 0 || sep == args.length - 1) { usage(); System.exit(2); }
        List<String> command = new ArrayList<>(Arrays.asList(args).subList(sep + 1, args.length));
        if (ownerPid <= 1 || DaemonBootstrap.readProcStarttime(ownerPid) == null) System.exit(0);
        Long ownerStart = DaemonBootstrap.readProcStarttime(ownerPid);
        DaemonHardening.protectSelf("supervisor-" + component);
        int restartCount = 0;
        long lastRestart = 0L;
        while (true) {
            Thread.sleep(intervalMs);
            Long curOwnerStart = DaemonBootstrap.readProcStarttime(ownerPid);
            if (ownerStart == null || curOwnerStart == null || !ownerStart.equals(curOwnerStart)) System.exit(0);
            int daemonPid = readPid(pidFile);
            boolean alive = daemonPid > 1 && DaemonBootstrap.readProcStarttime(daemonPid) != null;
            boolean socketOk = socketPath == null || "-".equals(socketPath) || new File(socketPath).exists();
            if (alive && socketOk) {
                DaemonHardening.protectPid(daemonPid, component);
                continue;
            }
            long now = System.currentTimeMillis();
            if (now - lastRestart < Math.max(1000L, intervalMs)) continue;
            lastRestart = now;
            restartCount++;
            startDaemon(command, pidFile, component, restartCount);
        }
    }

    private static void startDaemon(List<String> command, File pidFile, String component, int restartCount) {
        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            pb.redirectOutput(ProcessBuilder.Redirect.appendTo(new File("/dev/null")));
            Process p = pb.start();
            int pid = bestEffortPid(p);
            if (pid > 1) {
                writePid(pidFile, pid);
                DaemonHardening.protectPid(pid, component);
            }
        } catch (Throwable ignored) {}
    }

    private static int bestEffortPid(Process p) {
        try { return (int) p.getClass().getMethod("pid").invoke(p); } catch (Throwable ignored) {}
        try {
            java.lang.reflect.Field f = p.getClass().getDeclaredField("pid");
            f.setAccessible(true);
            Object v = f.get(p);
            if (v instanceof Number) return ((Number) v).intValue();
        } catch (Throwable ignored) {}
        return -1;
    }

    private static void writePid(File f, int pid) {
        try {
            File parent = f.getParentFile();
            if (parent != null && !parent.isDirectory()) parent.mkdirs();
            try (FileOutputStream out = new FileOutputStream(f, false)) {
                out.write((String.valueOf(pid) + "\n").getBytes(StandardCharsets.UTF_8));
            }
        } catch (Throwable ignored) {}
    }

    private static int readPid(File f) {
        try {
            if (!f.isFile()) return -1;
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            try (java.io.FileInputStream input = new java.io.FileInputStream(f)) {
                byte[] buf = new byte[64];
                int n;
                while ((n = input.read(buf)) >= 0) out.write(buf, 0, n);
            }
            String s = out.toString("UTF-8").trim();
            return parseInt(s, -1);
        } catch (Throwable ignored) { return -1; }
    }

    private static int parseInt(String s, int d) { try { return Integer.parseInt(s); } catch (Throwable ignored) { return d; } }
    private static long parseLong(String s, long d) { try { return Long.parseLong(s); } catch (Throwable ignored) { return d; } }
    private static String safe(String s) { return s == null ? "daemon" : s.replace('\n','_').replace('\r','_').replace('\0','_'); }
    private static void usage() {
        System.out.println("DaemonSupervisorUtil commands:");
        System.out.println("  version");
        System.out.println("  supervise COMPONENT PID_FILE SOCKET_OR_DASH OWNER_PID INTERVAL_MS -- command ...");
    }
}
