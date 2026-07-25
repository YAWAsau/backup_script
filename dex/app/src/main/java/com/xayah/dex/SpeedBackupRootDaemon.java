package com.xayah.dex;

import android.net.LocalSocket;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Unified root-side AF_UNIX daemon for SpeedBackup hot paths.
 *
 * Request namespaces:
 *   ping\n
 *   hiddenapi\n<HiddenApi hot protocol: command, protocol, bodyLength, body>
 *   notify\n<Notification hot protocol: command, protocol, bodyLength, body>
 *   appstate\n<AppState protocol: command, userId, format, extra, protocol, bodyLength, body>
 *
 * This daemon intentionally keeps WebDAV and Play-UID install daemons separate: WebDAV is a
 * streaming/network daemon, and install must run under Play UID.
 */
public final class SpeedBackupRootDaemon {
    public static final String VERSION = "v2.6.95-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify dex=" + HiddenApiUtil.VERSION;
    private static final int HOT_PROTOCOL_VERSION = 1;

    private SpeedBackupRootDaemon() {}

    public static void main(String[] args) {
        if (args == null || args.length == 0) {
            printUsage();
            System.exit(2);
        }
        String cmd = args[0];
        if ("version".equals(cmd) || "--version".equals(cmd) || "-v".equals(cmd)) {
            System.out.println(VERSION);
            System.exit(0);
        }
        if ("daemonunix".equals(cmd)) {
            HiddenApiBypassBridge.installExemptionsOnce();
            cmdDaemonUnix(args);
            System.exit(0);
        }
        printUsage();
        System.exit(2);
    }

    private static void printUsage() {
        System.out.println("SpeedBackupRootDaemon " + VERSION);
        System.out.println("  capability: dex.root_unified_daemon.v1");
        System.out.println("  daemonunix <socketPath> [idleTimeoutSec] [ownerPid]");
    }

    private static void cmdDaemonUnix(String[] args) {
        if (args.length < 2) throw new IllegalArgumentException("daemonunix <socketPath> [idleTimeoutSec] [ownerPid]");
        String socketPath = args[1];
        long idleTimeoutMs = 1800_000L;
        if (args.length >= 3) {
            try { idleTimeoutMs = Math.max(1L, Long.parseLong(args[2])) * 1000L; } catch (Throwable ignored) {}
        }
        int ownerPid = args.length >= 4 ? parsePositiveInt(args[3], -1) : -1;
        try {
            AppStateEngine.initializeRuntime();
        } catch (Throwable t) {
            System.err.println("ROOT_DAEMON_APPSTATE_INIT_WARN reason=" + t.getClass().getSimpleName());
        }
        DaemonBootstrap.runUnixDaemon(
                "SPEEDBACKUP_ROOT",
                socketPath,
                idleTimeoutMs,
                ownerPid,
                "SPEEDBACKUP_ROOT_DAEMON_READY_UNIX " + socketPath,
                true,
                SpeedBackupRootDaemon::handleClient);
    }

    private static int parsePositiveInt(String raw, int fallback) {
        try {
            int value = Integer.parseInt(raw == null ? "" : raw.trim());
            return value > 0 ? value : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static void handleClient(LocalSocket client) throws Exception {
        try (LocalSocket c = client) {
            InputStream in = c.getInputStream();
            OutputStream out = c.getOutputStream();
            String namespace = readUtf8Line(in).trim();
            if ("ping".equals(namespace)) {
                writeResult(out, 0, "OK", "PONG\n");
                return;
            }
            if ("hiddenapi".equals(namespace)) {
                handleHot(out, in, true);
                return;
            }
            if ("notify".equals(namespace) || "notification".equals(namespace)) {
                handleHot(out, in, false);
                return;
            }
            if ("appstate".equals(namespace)) {
                AppStateUtil.handleRootDaemonConnection(in, out);
                return;
            }
            writeResult(out, 2, "BAD_REQUEST", "ROOT_DAEMON_UNKNOWN_NAMESPACE " + sanitize(namespace) + "\n");
        }
    }

    private static void handleHot(OutputStream out, InputStream in, boolean hiddenApi) throws IOException {
        String command = readUtf8Line(in);
        String protocolRaw = readUtf8Line(in);
        String bodyLengthRaw = readUtf8Line(in);
        int protocol = parsePositiveInt(protocolRaw, -1);
        long bodyLength = parseLong(bodyLengthRaw, -2L);
        if (protocol != HOT_PROTOCOL_VERSION || bodyLength < -1L) {
            writeResult(out, 2, "BAD_REQUEST", "ROOT_DAEMON_BAD_HOT_REQUEST\n");
            return;
        }
        byte[] bodyBytes = bodyLength == -1L ? readAll(in) : readExactly(in, bodyLength);
        if (hiddenApi) {
            HiddenApiUtil.DaemonRunResult result = HiddenApiUtil.runDaemonCommand(command, bodyBytes);
            writeResult(out, result.rc, result.rc == 0 ? "OK" : "FAIL", result.stdout);
        } else {
            NotificationUtil.DaemonRunResult result = NotificationUtil.runDaemonCommand(command, bodyBytes);
            writeResult(out, result.rc, result.rc == 0 ? "OK" : "FAIL", result.stdout);
        }
    }

    private static void writeResult(OutputStream out, int rc, String name, String body) throws IOException {
        byte[] payload = (body == null ? "" : body).getBytes(StandardCharsets.UTF_8);
        out.write(("RESULT " + rc + " " + name + "\n").getBytes(StandardCharsets.UTF_8));
        out.write((String.valueOf(payload.length) + "\n").getBytes(StandardCharsets.UTF_8));
        out.write(payload);
        out.flush();
    }

    private static String readUtf8Line(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(128);
        while (true) {
            int b = in.read();
            if (b < 0 || b == '\n') break;
            if (b != '\r') out.write(b);
        }
        return out.toString("UTF-8");
    }

    private static byte[] readExactly(InputStream in, long length) throws IOException {
        if (length > Integer.MAX_VALUE) throw new IOException("request body too large");
        byte[] out = new byte[(int) length];
        int off = 0;
        while (off < out.length) {
            int n = in.read(out, off, out.length - off);
            if (n < 0) throw new IOException("unexpected EOF: expected=" + out.length + " actual=" + off);
            off += n;
        }
        return out;
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
        return out.toByteArray();
    }

    private static long parseLong(String raw, long fallback) {
        try { return Long.parseLong(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        String value = raw.replace('\n', ' ').replace('\r', ' ').replace('\0', ' ');
        return value.length() > 180 ? value.substring(0, 180) : value;
    }
}
