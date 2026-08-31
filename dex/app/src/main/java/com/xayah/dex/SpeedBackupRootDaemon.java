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
    public static final String VERSION = "v2.6.207-r501-canary-daemon-supervisor-keep dex=" + HiddenApiUtil.VERSION;
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
            // r498: Android Canary can hang before READY while installing hidden-api exemptions
            // on the long-lived root daemon startup path. Publish the AF_UNIX daemon first and
            // initialize hidden-api exemptions lazily only for requests that actually need them.
            cmdDaemonUnix(args);
            System.exit(0);
        }
        printUsage();
        System.exit(2);
    }

    private static void printUsage() {
        System.out.println("SpeedBackupRootDaemon " + VERSION);
        System.out.println("  capability: dex.root_unified_daemon.v1");
        System.out.println("  capability: dex.root_daemon.ready_before_appstate_init.v1");
        System.out.println("  capability: dex.root_daemon.ready_before_hiddenapi_init.v1");
        System.out.println("  capability: dex.root_daemon.ready_before_hardening.v1");
        System.out.println("  capability: dex.display_power.root_daemon.v1");
        System.out.println("  capability: dex.app_inventory.snapshot.v1");
        System.out.println("  capability: dex.app_inventory.daemon_cache.v1");
        System.out.println("  capability: dex.app_inventory.pkg_uid.single.v1");
        System.out.println("  capability: dex.app_inventory.package_status.single.v1");
        System.out.println("  capability: dex.pm.facts.single.v1");
        System.out.println("  capability: dex.pm.installed_users_facts.v1");
        System.out.println("  capability: dex.pm.visible_after_install.v1");
        System.out.println("  capability: dex.storage_volume_facts.v1");
        System.out.println("  capability: dex.home_ime_launcher_facts.v1");
        System.out.println("  capability: dex.app_inventory.default_ime.v1");
        System.out.println("  capability: dex.process_observer.watch.v1");
        System.out.println("  capability: dex.process_observer.guard.v2");
        System.out.println("  capability: dex.process_observer.pre_guard.v3");
        System.out.println("  capability: dex.app_wake_block.v1");
        System.out.println("  capability: dex.process_observer.integrated_wake_block.v1");
        System.out.println("  capability: dex.app_kill.context.v1");
        System.out.println("  capability: dex.process_observer.task_stack.v1");
        System.out.println("  capability: dex.process_observer.debounce.v1");
        System.out.println("  capability: dex.process_observer.debounce.v2");
        System.out.println("  capability: dex.process_observer.lifecycle_token.v1");
        System.out.println("  capability: dex.process_observer.bootstrap_gate.v1");
        System.out.println("  capability: dex.process_observer.global_daemon.v1");
        System.out.println("  capability: dex.process_observer.target_lifecycle.v1");
        System.out.println("  capability: dex.process_observer.batch_watchset.v1");
        System.out.println("  capability: dex.process_observer.batch_stop_safe.v1");
        System.out.println("  capability: dex.process_observer.batch_persistent_safety.v1");
        System.out.println("  capability: dex.process_observer.live_respawn_guard.v1");
        System.out.println("  capability: dex.process_observer.cgroup_high_risk_only.v1");
        System.out.println("  capability: dex.process_observer.high_risk_notop_cgroup_freeze.v1");
        System.out.println("  capability: dex.process_observer.cgroup_freeze_reuse.v1");
        System.out.println("  capability: dex.process_observer.cgroup_freeze_reuse_all_alive_pids.v1");
        System.out.println("  capability: dex.process_observer.cgroup_stale_token_prune.v1");
        System.out.println("  capability: dex.process_observer.high_risk_top_fast_freeze.v1");
        System.out.println("  capability: dex.app_wake_block.persistent_state.v1");
        System.out.println("  capability: dex.app_wake_block.persistent_restore.v1");
        System.out.println("  capability: dex.app_wake_block.restore_verify.v1");
        System.out.println("  capability: dex.app_wake_block.persistent_cleanup.v1");
        System.out.println("  capability: dex.app_wake_block.state_delete_verify.v1");
        System.out.println("  capability: dex.app_wake_block.cleanup_force_zero_ttl.v1");
        System.out.println("  capability: dex.app_wake_block.exempted_restore_alias.v1");
        System.out.println("  capability: dex.app_wake_block.deviceidle_whitelist_restore.v1");
        System.out.println("  capability: dex.app_wake_block.direct_appops.v1");
        System.out.println("  capability: dex.app_wake_block.direct_standby.v1");
        System.out.println("  capability: dex.app_wake_block.direct_deviceidle.v1");
        System.out.println("  capability: dex.process_observer.raw_transaction_code.v1");
        System.out.println("  capability: dex.uid_net_block.netpolicy_direct.v1");
        System.out.println("  capability: dex.uid_net_block.netd_direct_probe.v1");
        System.out.println("  capability: dex.uid_net_block.persistent_restore.v1");
        System.out.println("  capability: dex.uid_net_block.smart_policy.v1");
        System.out.println("  capability: dex.cgroup_freezer.lifecycle.v1");
        System.out.println("  capability: dex.process_observer.cgroup_freezer_guard.v1");
        System.out.println("  capability: dex.cgroup_freezer.persistent_restore.v1");
        System.out.println("  capability: dex.process_observer.cgroup_freezer_fallback_kill.v1");
        System.out.println("  capability: dex.cgroup_freezer.native_helper_optional.v1");
        System.out.println("  capability: dex.process_observer.native_logd_events_optional.v1");
        System.out.println("  capability: dex.cgroup_freezer.native_daemon_optional.v1");
        System.out.println("  capability: dex.cgroup_freezer.batch_daemon_prewarm.v1");
        System.out.println("  capability: dex.cgroup_freezer.native_package_atomic.v1");
        System.out.println("  capability: dex.cgroup_freezer.native_thaw_uid_emergency.v1");
        System.out.println("  capability: dex.cgroup_freezer.daemon_parent_control.v1");
        System.out.println("  capability: dex.cgroup_freezer.binder_freeze_optional.v1");
        System.out.println("  capability: dex.cgroup_freezer.native_scan_package_optional.v1");
        System.out.println("  capability: dex.cgroup_freezer.v1_fallback_optional.v1");
        System.out.println("  capability: dex.process_observer.smart_policy.v1");
        System.out.println("  capability: dex.app_wake_block.token_match_guard.v1");
        System.out.println("  capability: dex.app_wake_block.token_epoch.v1");
        System.out.println("  capability: dex.process_observer.token_epoch.v1");
        System.out.println("  capability: dex.process_observer.stop_missing_restore.v1");
        System.out.println("  capability: dex.app_kill.verify.v1");
        System.out.println("  capability: dex.app_kill.top_check.v1");
        System.out.println("  capability: dex.app_wake_block.parser.v2");
        System.out.println("  capability: dex.hidden_api.bootstrap.v2");
        System.out.println("  capability: dex.hidden_api.bypass_softgate.v1");
        System.out.println("  capability: dex.hidden_api.runtime_probe.v1");
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
        // r497: Android Canary/SDK37+ may block in early Binder-backed AppState/bootstrap
        // calls before the AF_UNIX daemon publishes READY. Do not perform optional cleanup or
        // AppState runtime initialization on the startup path; hiddenapi inventory commands must
        // be able to use the daemon even when AppState services are slow or unavailable.
        // AppStateEngine still initializes lazily when appstate commands are actually handled.
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
                HiddenApiBypassBridge.installExemptionsOnce();
                handleHot(out, in, true);
                return;
            }
            if ("notify".equals(namespace) || "notification".equals(namespace)) {
                handleHot(out, in, false);
                return;
            }
            if ("appstate".equals(namespace)) {
                // AppStateEngine initializes its Binder-backed services lazily per command.
                // Keep daemon READY independent of hidden-api/AppState bootstrap on Canary.
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
