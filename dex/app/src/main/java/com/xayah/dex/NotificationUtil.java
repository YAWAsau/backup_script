package com.xayah.dex;

import android.annotation.SuppressLint;
import android.app.INotificationManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.pm.ApplicationInfo;
import android.content.pm.ParceledListSlice;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Binder;
import android.os.RemoteException;
import android.os.UserHandleHidden;
import android.net.LocalSocket;

import com.xayah.dex.compat.HiddenApiServices;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Properties;

public class NotificationUtil extends BaseUtil {
    public static final String VERSION = "v1.1.5-capability-text-fix dex=" + HiddenApiUtil.VERSION;
    public static final int SHELL_UID = 2000;
    public static final String SHELL_PACKAGE = "com.android.shell";
    public static final int NOTIFICATION_ID = 2020;

    private static final String SYSTEM_NOTIFICATION_CHANNEL_ALERTS = "ALERTS";

    public static final String CHANNEL_PROGRESS_ID = "speedbackup_progress";
    public static final String CHANNEL_RESULT_ID = "speedbackup_result";
    public static final String CHANNEL_ERROR_ID = "speedbackup_error";
    public static final String CHANNEL_DEBUG_ID = "speedbackup_debug";

    private static final int DEFAULT_PROGRESS_ID = 2020;
    private static final int DEFAULT_RESULT_ID = 2020;
    private static final int DEFAULT_ERROR_ID = 2021;
    private static final int DEFAULT_DEBUG_ID = 2023;
    private static final int MAX_INBOX_LINES = 6;

    private static INotificationManager sService;

    private static void human(String msg) {
        if ("1".equals(System.getenv("DEX_HUMAN_LOG"))) {
            System.err.println("HUMAN " + msg);
        }
    }

    private static void onHelp() {
        System.out.println("NotificationUtil commands:");
        System.out.println("  help");
        System.out.println();
        System.out.println("  daemonunix SOCKET [idleSec] [ownerPid]");
        System.out.println();
        System.out.println("daemon-only command: notifyBatch");
        System.out.println("notifyBatch stdin sections:");
        System.out.println("  EVENT|BACKUP_PROGRESS|RESTORE_PROGRESS|BACKUP_DONE|RESTORE_DONE|ERROR|WARN|DEBUG");
        System.out.println("  TAG|speedbackup");
        System.out.println("  ID|1001");
        System.out.println("  CHANNEL|progress|result|error|debug");
        System.out.println("  TITLE|SpeedBackup");
        System.out.println("  TEXT|current task");
        System.out.println("  BIGTEXT|expanded text");
        System.out.println("  SUBTEXT|small status line");
        System.out.println("  PACKAGE|jp.naver.line.android        # app label / large icon");
        System.out.println("  PROGRESS|100|50|0                    # max|progress|indeterminate(0/1)");
        System.out.println("  ITEMS|50|100                         # done|total, for speed/ETA");
        System.out.println("  BYTES|1048576|10485760               # done|total, for speed/ETA");
        System.out.println("  THROTTLE_MS|500                      # skip non-urgent repeat updates inside window");
        System.out.println("  INBOX|1                              # recent event list");
        System.out.println("  ERROR_AGGREGATE|1                    # aggregate ERROR/WARN notifications");
        System.out.println("  LOG_PATH|/data/speed_debug/run_x/main.log     # metadata only, no notification action");
        System.out.println("  DIR_PATH|/data/speed_debug/run_x              # metadata only, no notification action");
        System.out.println("  ONGOING|1");
        System.out.println("  AUTO_CANCEL|0");
        System.out.println("  ONLY_ALERT_ONCE|1");
        System.out.println("  END");
        System.out.println();
        System.out.println("notes:");
        System.out.println("  no notification buttons/actions are created; this build is pure classes.dex notifyBatch without companion APK dependency.");
        System.out.println("  TAG/ID are normalized: main= speedbackup_main/2020, error= speedbackup_error/2021, debug= speedbackup_debug/2023.");
        System.out.println("  notifyBatch is daemon-only; single app_process notifyBatch CLI fallback is intentionally removed.");
    }

    private static boolean isSupportedCommand(String cmd) {
        return "help".equals(cmd) || "daemonunix".equals(cmd) || "version".equals(cmd) || "--version".equals(cmd) || "-v".equals(cmd);
    }

    private static void rejectUnknownCommand(String cmd) {
        System.out.println("UNKNOWN_COMMAND " + cmd);
        System.exit(1);
    }

    private static void onCommand() {
        switch (mCmd) {
            case "help":
                onHelp();
                break;
            case "daemonunix":
                cmdDaemonUnix();
                break;
            case "version":
            case "--version":
            case "-v":
                System.out.println(VERSION);
                break;
            default:
                rejectUnknownCommand(mCmd);
                break;
        }
    }

    public static void main(String[] args) {
        mArgs = args;
        if (args == null || args.length <= 0) {
            onHelp();
            System.exit(0);
        }

        mCmd = args[0];
        mArgPos = 1;

        // Legacy single-notify entry is intentionally removed.  Reject unknown
        // commands before touching notification service so dex_check can verify
        // the public API surface without depending on framework service state.
        if (!isSupportedCommand(mCmd)) {
            rejectUnknownCommand(mCmd);
        }

        if ("help".equals(mCmd)) {
            onHelp();
            System.exit(0);
        }
        if ("version".equals(mCmd) || "--version".equals(mCmd) || "-v".equals(mCmd)) {
            System.out.println(VERSION);
            System.exit(0);
        }

        HiddenApiBypassBridge.installExemptionsOnce();

        if ("daemonunix".equals(mCmd)) {
            cmdDaemonUnix();
            System.exit(0);
        }

        getService();
        if (sService == null) {
            System.out.println("NOTIFICATION_NOTIFY_FAILED reason=no_notification_service");
            human("通知發送失敗: 無法取得 notification service");
            System.exit(1);
        }

        onCommand();
        System.exit(0);
    }

    private static final int DAEMON_PROTOCOL_VERSION = 1;

    private static void cmdDaemonUnix() {
        if (mArgs == null || mArgs.length < 2) {
            System.err.println("NOTIFICATION_DAEMON_BAD_ARGS daemonunix <socketPath> [idleTimeoutSec] [ownerPid]");
            System.exit(2);
        }
        String socketPath = mArgs[1];
        long idleTimeoutMs = 1800_000L;
        if (mArgs.length >= 3) {
            try { idleTimeoutMs = Math.max(1L, Long.parseLong(mArgs[2])) * 1000L; } catch (Throwable ignored) {}
        }
        final int ownerPid = mArgs.length >= 4 ? parsePositiveInt(mArgs[3], -1) : -1;
        getService();
        if (sService == null) {
            System.err.println("NOTIFICATION_DAEMON_FAILED reason=no_notification_service");
            System.exit(1);
        }
        DaemonBootstrap.runUnixDaemon(
                "NOTIFICATION",
                socketPath,
                idleTimeoutMs,
                ownerPid,
                "NOTIFY_DAEMON_READY_UNIX " + socketPath,
                false,
                NotificationUtil::handleDaemonClient);
    }

    private static void handleDaemonClient(LocalSocket client) {
        try (LocalSocket c = client) {
            InputStream in = c.getInputStream();
            OutputStream out = c.getOutputStream();
            String command = readUtf8Line(in);
            String protocolRaw = readUtf8Line(in);
            String bodyLengthRaw = readUtf8Line(in);
            int protocol = parsePositiveInt(protocolRaw, -1);
            long bodyLength = parseLongDaemon(bodyLengthRaw, -2L);
            int rc;
            String name;
            String body;
            if (protocol != DAEMON_PROTOCOL_VERSION || bodyLength < -1L) {
                rc = 2;
                name = "BAD_REQUEST";
                body = "NOTIFICATION_DAEMON_BAD_REQUEST\n";
            } else {
                byte[] request = bodyLength == -1L ? readAll(in) : readExactly(in, bodyLength);
                DaemonRunResult result = runDaemonCommand(command, request);
                rc = result.rc;
                name = rc == 0 ? "OK" : "FAIL";
                body = result.stdout;
            }
            byte[] response = body.getBytes(StandardCharsets.UTF_8);
            out.write(("RESULT " + rc + " " + name + "\n").getBytes(StandardCharsets.UTF_8));
            out.write((String.valueOf(response.length) + "\n").getBytes(StandardCharsets.UTF_8));
            out.write(response);
            out.flush();
        } catch (Throwable t) {
            System.err.println("[notify-daemon] " + t.getClass().getName() + ": " + t.getMessage());
        }
    }

    private static synchronized DaemonRunResult runDaemonCommand(String command, byte[] request) {
        if (command == null) command = "";
        command = command.trim();
        if ("ping".equals(command)) {
            return new DaemonRunResult(0, "PONG\n");
        }
        PrintStream oldOut = System.out;
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        int rc;
        try {
            System.setOut(new PrintStream(baos, true, "UTF-8"));
            if ("notifyBatch".equals(command)) {
                rc = notifyBatchCommand(new ByteArrayInputStream(request == null ? new byte[0] : request), Binder.getCallingUid(), false);
            } else {
                System.out.println("UNKNOWN_COMMAND " + command);
                rc = 2;
            }
        } catch (Throwable t) {
            System.out.println("NOTIFICATION_DAEMON_COMMAND_FAILED command=" + command + " exception=" + t.getClass().getName());
            t.printStackTrace(System.err);
            rc = 1;
        } finally {
            try { System.out.flush(); } catch (Throwable ignored) {}
            System.setOut(oldOut);
        }
        return new DaemonRunResult(rc, baos.toString());
    }

    private static final class DaemonRunResult {
        final int rc;
        final String stdout;
        DaemonRunResult(int rc, String stdout) { this.rc = rc; this.stdout = stdout == null ? "" : stdout; }
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
        if (length > Integer.MAX_VALUE) throw new IOException("body too large");
        byte[] out = new byte[(int) length];
        int off = 0;
        while (off < out.length) {
            int n = in.read(out, off, out.length - off);
            if (n < 0) throw new IOException("unexpected EOF");
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

    private static int parsePositiveInt(String raw, int fallback) {
        try { int v = Integer.parseInt(raw == null ? "" : raw.trim()); return v > 0 ? v : fallback; } catch (Throwable ignored) { return fallback; }
    }

    private static long parseLongDaemon(String raw, long fallback) {
        try { return Long.parseLong(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    @SuppressLint("NotificationPermission")
    private static void notifyBatch(int callingUid) {
        System.exit(notifyBatchCommand(System.in, callingUid, true));
    }

    private static int notifyBatchCommand(InputStream requestInput, int callingUid, boolean parseOptions) {
        boolean stdin = !parseOptions;
        String opt;
        while (parseOptions && (opt = getNextOption()) != null) {
            if ("--stdin".equals(opt)) {
                stdin = true;
            } else {
                System.out.println("NOTIFICATION_BATCH_FAILED reason=bad_option option=" + opt);
                return 1;
            }
        }
        if (!stdin) {
            onHelp();
            return 1;
        }
        int events = 0;
        int sent = 0;
        int skipped = 0;
        int failed = 0;
        try {
            final Context ctx = HiddenApiHelper.getContext();
            final List<NotifyEvent> parsed = parseNotifyBatch(requestInput);
            for (NotifyEvent ev : parsed) {
                events++;
                try {
                    prepareEvent(ctx, ev);
                    if (shouldThrottle(ev)) {
                        skipped++;
                        System.out.println("NOTIFICATION_EVENT_SKIPPED reason=throttle event=" + safeLog(ev.event)
                                + " tag=" + safeLog(ev.tag) + " id=" + ev.id);
                        continue;
                    }
                    sendNotifyEvent(ctx, callingUid, ev);
                    saveEventState(ev);
                    sent++;
                    System.out.println("NOTIFICATION_EVENT_OK event=" + safeLog(ev.event)
                            + " tag=" + safeLog(ev.tag) + " id=" + ev.id
                            + " channel=" + safeLog(ev.channelAlias)
                            + " actions=0");
                } catch (Throwable t) {
                    failed++;
                    System.out.println("NOTIFICATION_EVENT_FAILED event=" + safeLog(ev.event)
                            + " reason=" + t.getClass().getSimpleName());
                    t.printStackTrace(System.err);
                }
            }
            System.out.println("NOTIFICATION_BATCH_OK events=" + events + " sent=" + sent + " skipped=" + skipped + " failed=" + failed);
            return failed == 0 ? 0 : 1;
        } catch (Exception e) {
            human("批量通知工具失敗: " + e.getMessage());
            System.out.println("NOTIFICATION_BATCH_FAILED reason=" + e.getClass().getSimpleName());
            e.printStackTrace(System.err);
            return 1;
        }
    }

    private static List<NotifyEvent> parseNotifyBatch(InputStream input) throws Exception {
        final ArrayList<NotifyEvent> out = new ArrayList<>();
        final BufferedReader br = new BufferedReader(new InputStreamReader(input));
        NotifyEvent current = new NotifyEvent();
        String line;
        while ((line = br.readLine()) != null) {
            line = line.trim();
            if (line.length() == 0 || line.startsWith("#")) {
                continue;
            }
            final String[] parts = line.split("\\|", 4);
            final String key = parts[0].trim().toUpperCase(Locale.ROOT);
            if ("END".equals(key)) {
                current.normalize();
                out.add(current);
                current = new NotifyEvent();
                continue;
            }
            final String value = parts.length >= 2 ? parts[1] : "";
            current.touched = true;
            if ("EVENT".equals(key)) current.event = value;
            else if ("TAG".equals(key)) current.tag = value;
            else if ("ID".equals(key)) current.id = parseInt(value, current.id);
            else if ("CHANNEL".equals(key)) current.channelAlias = value;
            else if ("TITLE".equals(key)) current.title = value;
            else if ("TEXT".equals(key)) current.text = value;
            else if ("BIGTEXT".equals(key)) current.bigText = value;
            else if ("SUBTEXT".equals(key)) current.subText = value;
            else if ("PACKAGE".equals(key) || "PKG".equals(key)) current.packageName = value;
            else if ("LOG_PATH".equals(key) || "DIR_PATH".equals(key) || "FOLDER_PATH".equals(key)
                    || "PAUSE_FILE".equals(key) || "STOP_FILE".equals(key) || "DEFAULT_ACTIONS".equals(key)
                    || "COMPANION_APK".equals(key) || "NO_ACTIONS".equals(key) || "SINGLE_MAIN".equals(key)) {
                /* no-actions build: metadata/action keys are intentionally ignored */
            }
            else if ("INBOX".equals(key)) current.inbox = parseBool(value, current.inbox);
            else if ("ERROR_AGGREGATE".equals(key)) current.errorAggregate = parseBool(value, current.errorAggregate);
            else if ("THROTTLE_MS".equals(key)) current.throttleMs = parseLong(value, current.throttleMs);
            else if ("GROUP".equals(key)) current.group = value;
            else if ("GROUP_SUMMARY".equals(key)) current.groupSummary = parseBool(value, current.groupSummary);
            else if ("ACTION".equals(key)) {
                /* no-actions build: ignore ACTION lines so no buttons are displayed */
            } else if ("PROGRESS".equals(key)) {
                current.hasProgress = true;
                current.progressMax = parts.length >= 2 ? parseInt(parts[1], current.progressMax) : current.progressMax;
                current.progress = parts.length >= 3 ? parseInt(parts[2], current.progress) : current.progress;
                current.indeterminate = parts.length >= 4 && parseBool(parts[3], current.indeterminate);
            } else if ("ITEMS".equals(key)) {
                current.metricDone = parts.length >= 2 ? parseLong(parts[1], current.metricDone) : current.metricDone;
                current.metricTotal = parts.length >= 3 ? parseLong(parts[2], current.metricTotal) : current.metricTotal;
                current.metricKind = "items";
            } else if ("BYTES".equals(key)) {
                current.metricDone = parts.length >= 2 ? parseLong(parts[1], current.metricDone) : current.metricDone;
                current.metricTotal = parts.length >= 3 ? parseLong(parts[2], current.metricTotal) : current.metricTotal;
                current.metricKind = "bytes";
            } else if ("PROGRESS_MAX".equals(key)) current.progressMax = parseInt(value, current.progressMax);
            else if ("PROGRESS_CURRENT".equals(key) || "PROGRESS_VALUE".equals(key)) current.progress = parseInt(value, current.progress);
            else if ("INDETERMINATE".equals(key)) current.indeterminate = parseBool(value, current.indeterminate);
            else if ("ONGOING".equals(key)) current.ongoing = parseBool(value, current.ongoing);
            else if ("AUTO_CANCEL".equals(key)) current.autoCancel = parseBool(value, current.autoCancel);
            else if ("ONLY_ALERT_ONCE".equals(key)) current.onlyAlertOnce = parseBool(value, current.onlyAlertOnce);
            else if ("SHOW_WHEN".equals(key)) current.showWhen = parseBool(value, current.showWhen);
            else if ("WHEN".equals(key)) current.when = parseLong(value, current.when);
            else if ("IMPORTANCE".equals(key)) current.importanceAlias = value;
        }
        if (current.hasContent()) {
            current.normalize();
            out.add(current);
        }
        return out;
    }

    private static void prepareEvent(Context ctx, NotifyEvent ev) {
        enrichPackage(ctx, ev);
        applyMetrics(ev);
        updateRecentAndErrors(ev);
    }

    private static void enrichPackage(Context ctx, NotifyEvent ev) {
        if (ev.packageName == null || ev.packageName.length() == 0) return;
        try {
            PackageManager pm = ctx.getPackageManager();
            ApplicationInfo ai = pm.getApplicationInfo(ev.packageName, 0);
            CharSequence label = pm.getApplicationLabel(ai);
            if (label != null && label.length() > 0) {
                ev.appLabel = label.toString();
                if (ev.subText == null || ev.subText.length() == 0) ev.subText = ev.appLabel;
            }
            Drawable icon = pm.getApplicationIcon(ai);
            ev.largeIcon = drawableToBitmap(icon);
        } catch (Throwable ignored) {
        }
    }

    private static void applyMetrics(NotifyEvent ev) {
        if (ev.metricTotal <= 0 && ev.hasProgress && ev.progressMax > 0) {
            ev.metricDone = ev.progress;
            ev.metricTotal = ev.progressMax;
            ev.metricKind = "items";
        }
        if (ev.metricTotal <= 0 || ev.metricDone < 0) return;
        Properties p = loadState(ev.stateFile());
        long now = System.currentTimeMillis();
        long startMs = parseLong(p.getProperty("start.ms"), 0L);
        long startValue = parseLong(p.getProperty("start.value"), ev.metricDone);
        if (startMs <= 0 || ev.metricDone <= 0 || ev.metricDone < startValue || ev.metricDone >= ev.metricTotal) {
            startMs = now;
            startValue = Math.max(0, ev.metricDone);
        }
        long elapsed = Math.max(1L, now - startMs);
        long delta = Math.max(0L, ev.metricDone - startValue);
        String line = "";
        if (delta > 0 && ev.metricDone < ev.metricTotal) {
            double perSec = delta * 1000.0d / elapsed;
            long remain = Math.max(0L, ev.metricTotal - ev.metricDone);
            long etaSec = perSec > 0 ? Math.round(remain / perSec) : -1L;
            if ("bytes".equals(ev.metricKind)) {
                line = percent(ev.metricDone, ev.metricTotal) + " · " + formatBytesPerSec(perSec) + " · 剩餘 " + formatDuration(etaSec);
            } else {
                line = percent(ev.metricDone, ev.metricTotal) + " · " + String.format(Locale.ROOT, "%.1f項/s", perSec) + " · 剩餘 " + formatDuration(etaSec);
            }
        } else if (ev.metricTotal > 0) {
            line = percent(ev.metricDone, ev.metricTotal);
        }
        if (line.length() > 0) {
            ev.metricLine = line;
            if (ev.subText == null || ev.subText.length() == 0) ev.subText = line;
            if (ev.bigText == null || ev.bigText.length() == 0 || ev.bigText.equals(ev.text)) {
                ev.bigText = ev.text + "\n" + line;
            } else if (!ev.bigText.contains(line)) {
                ev.bigText = ev.bigText + "\n" + line;
            }
        }
        p.setProperty("start.ms", String.valueOf(startMs));
        p.setProperty("start.value", String.valueOf(startValue));
        saveState(ev.stateFile(), p);
    }

    private static void updateRecentAndErrors(NotifyEvent ev) {
        if (ev.isRootStartEvent()) {
            recentFile().delete();
            errorFile().delete();
            errorPropsFile().delete();
        }
        String line = timestamp() + " " + shortEvent(ev.event) + " " + firstNonEmpty(ev.appLabel, ev.text);
        appendBoundedLines(recentFile(), line, 16);
        ev.inboxLines.clear();
        if (ev.inbox) {
            ev.inboxLines.addAll(tailLines(recentFile(), MAX_INBOX_LINES));
        }
        if (ev.errorAggregate && ev.isErrorLike()) {
            appendBoundedLines(errorFile(), line, 20);
            int count = incrementErrorCount();
            ev.title = "SpeedBackup 錯誤/警告 (" + count + ")";
            ev.inboxLines.clear();
            ev.inboxLines.addAll(tailLines(errorFile(), MAX_INBOX_LINES));
            if (ev.bigText == null || ev.bigText.length() == 0) ev.bigText = ev.text;
        }
    }

    private static boolean shouldThrottle(NotifyEvent ev) {
        if (ev.throttleMs <= 0 || ev.isUrgent()) return false;
        Properties p = loadState(ev.stateFile());
        long now = System.currentTimeMillis();
        long last = parseLong(p.getProperty("last.ms"), 0L);
        if (last > 0 && now - last < ev.throttleMs) {
            return true;
        }
        return false;
    }

    private static void saveEventState(NotifyEvent ev) {
        Properties p = loadState(ev.stateFile());
        p.setProperty("last.ms", String.valueOf(System.currentTimeMillis()));
        p.setProperty("last.text", ev.text == null ? "" : ev.text);
        p.setProperty("last.progress", String.valueOf(ev.progress));
        saveState(ev.stateFile(), p);
    }

    @SuppressLint("NotificationPermission")
    private static void sendNotifyEvent(Context ctx, int callingUid, NotifyEvent ev) throws Exception {
        final boolean shellCaller = callingUid == SHELL_UID;
        final String channelId = shellCaller ? resolveChannelId(ev) : SYSTEM_NOTIFICATION_CHANNEL_ALERTS;
        Notification.Builder builder;
        if (shellCaller) {
            ensureSpeedBackupChannels(SHELL_PACKAGE);
            builder = new Notification.Builder(ctx, channelId);
        } else {
            final NotificationManager notificationManager = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 26 && notificationManager != null) {
                notificationManager.createNotificationChannel(makeChannel(channelId, ev.importance()));
            }
            builder = new Notification.Builder(ctx, channelId);
        }
        builder.setContentTitle(ev.title)
                .setContentText(ev.text)
                .setSmallIcon(android.R.drawable.sym_def_app_icon)
                .setOngoing(ev.ongoing)
                .setAutoCancel(ev.autoCancel)
                .setOnlyAlertOnce(ev.onlyAlertOnce)
                .setShowWhen(ev.showWhen)
                .setWhen(ev.when);
        if (ev.subText != null && ev.subText.length() > 0) {
            builder.setSubText(ev.subText);
        }
        if (ev.largeIcon != null) {
            builder.setLargeIcon(ev.largeIcon);
        }
        if (ev.group != null && ev.group.length() > 0) {
            builder.setGroup(ev.group);
            builder.setGroupSummary(ev.groupSummary);
        }
        if (ev.hasProgress) {
            int max = Math.max(0, ev.progressMax);
            int progress = Math.max(0, ev.progress);
            if (max > 0 && progress > max) progress = max;
            builder.setProgress(max, progress, ev.indeterminate);
        }
        if (ev.inboxLines.size() > 0) {
            Notification.InboxStyle style = new Notification.InboxStyle();
            if (ev.bigText != null && ev.bigText.length() > 0) style.setBigContentTitle(ev.title);
            for (String line : ev.inboxLines) style.addLine(line);
            if (ev.metricLine != null && ev.metricLine.length() > 0) style.setSummaryText(ev.metricLine);
            builder.setStyle(style);
        } else if (ev.bigText != null && ev.bigText.length() > 0) {
            builder.setStyle(new Notification.BigTextStyle().bigText(ev.bigText));
        }
        setCompatPriority(builder, ev.importance());
        final Notification n = builder.build();
        if (shellCaller) {
            sService.enqueueNotificationWithTag(SHELL_PACKAGE, SHELL_PACKAGE, ev.tag,
                    ev.id, n, UserHandleHidden.getUserId(callingUid));
        } else {
            final NotificationManager notificationManager = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            notificationManager.notify(ev.tag, ev.id, n);
        }
    }

    private static void setCompatPriority(Notification.Builder builder, int importance) {
        try {
            if (importance >= NotificationManager.IMPORTANCE_HIGH) {
                builder.setPriority(Notification.PRIORITY_HIGH);
            } else if (importance <= NotificationManager.IMPORTANCE_LOW) {
                builder.setPriority(Notification.PRIORITY_LOW);
            } else {
                builder.setPriority(Notification.PRIORITY_DEFAULT);
            }
        } catch (Throwable ignored) {
        }
    }

    private static String resolveChannelId(NotifyEvent ev) {
        String alias = ev.channelAlias == null ? "" : ev.channelAlias.trim().toLowerCase(Locale.ROOT);
        if ("progress".equals(alias) || CHANNEL_PROGRESS_ID.equals(alias)) return CHANNEL_PROGRESS_ID;
        if ("result".equals(alias) || CHANNEL_RESULT_ID.equals(alias)) return CHANNEL_RESULT_ID;
        if ("error".equals(alias) || CHANNEL_ERROR_ID.equals(alias)) return CHANNEL_ERROR_ID;
        if ("debug".equals(alias) || CHANNEL_DEBUG_ID.equals(alias)) return CHANNEL_DEBUG_ID;
        String event = ev.event == null ? "" : ev.event.toUpperCase(Locale.ROOT);
        if (event.contains("ERROR") || event.contains("FAIL") || event.contains("WARN")) return CHANNEL_ERROR_ID;
        if (event.contains("DONE") || event.contains("RESULT") || event.contains("FINISH")) return CHANNEL_RESULT_ID;
        if (event.contains("DEBUG") || event.contains("SELFTEST")) return CHANNEL_DEBUG_ID;
        return CHANNEL_PROGRESS_ID;
    }

    private static NotificationChannel makeChannel(String id, int importance) {
        String name;
        if (CHANNEL_PROGRESS_ID.equals(id)) name = "SpeedBackup 進度";
        else if (CHANNEL_RESULT_ID.equals(id)) name = "SpeedBackup 結果";
        else if (CHANNEL_ERROR_ID.equals(id)) name = "SpeedBackup 錯誤";
        else if (CHANNEL_DEBUG_ID.equals(id)) name = "SpeedBackup Debug";
        else name = "SpeedBackup";
        return new NotificationChannel(id, name, importance);
    }

    static void ensureSpeedBackupChannels(String callingPackage) throws RemoteException {
        final ArrayList<NotificationChannel> channels = new ArrayList<>();
        channels.add(makeChannel(CHANNEL_PROGRESS_ID, NotificationManager.IMPORTANCE_LOW));
        channels.add(makeChannel(CHANNEL_RESULT_ID, NotificationManager.IMPORTANCE_DEFAULT));
        channels.add(makeChannel(CHANNEL_ERROR_ID, NotificationManager.IMPORTANCE_HIGH));
        channels.add(makeChannel(CHANNEL_DEBUG_ID, NotificationManager.IMPORTANCE_LOW));
        sService.createNotificationChannels(callingPackage, new ParceledListSlice<>(channels));
    }

    private static File stateDir() {
        String env = System.getenv("SPEEDBACKUP_NOTIFY_STATE_DIR");
        File dir = new File(env != null && env.length() > 0 ? env : "/data/local/tmp/speedbackup_notify_state");
        try { dir.mkdirs(); } catch (Throwable ignored) {}
        return dir;
    }

    private static File recentFile() { return new File(stateDir(), "recent.log"); }
    private static File errorFile() { return new File(stateDir(), "errors.log"); }
    private static File errorPropsFile() { return new File(stateDir(), "errors.properties"); }

    private static Properties loadState(File file) {
        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream(file)) { p.load(in); } catch (Throwable ignored) {}
        return p;
    }

    private static void saveState(File file, Properties p) {
        try {
            File parent = file.getParentFile();
            if (parent != null) parent.mkdirs();
            try (FileOutputStream out = new FileOutputStream(file)) { p.store(out, "SpeedBackup notification state"); }
        } catch (Throwable ignored) {}
    }

    private static int incrementErrorCount() {
        File f = errorPropsFile();
        Properties p = loadState(f);
        int n = parseInt(p.getProperty("count"), 0) + 1;
        p.setProperty("count", String.valueOf(n));
        saveState(f, p);
        return n;
    }

    private static void appendBoundedLines(File file, String line, int max) {
        try {
            List<String> lines = tailLines(file, Math.max(0, max - 1));
            lines.add(line);
            File parent = file.getParentFile();
            if (parent != null) parent.mkdirs();
            try (FileWriter w = new FileWriter(file, false)) {
                for (String s : lines) {
                    w.write(s);
                    w.write('\n');
                }
            }
        } catch (Throwable ignored) {}
    }

    private static List<String> tailLines(File file, int max) {
        ArrayList<String> out = new ArrayList<>();
        if (max <= 0 || file == null || !file.exists()) return out;
        try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (line.length() == 0) continue;
                out.add(line);
                while (out.size() > max) out.remove(0);
            }
        } catch (Throwable ignored) {}
        return out;
    }

    private static Bitmap drawableToBitmap(Drawable drawable) {
        if (drawable == null) return null;
        try {
            if (drawable instanceof BitmapDrawable) {
                Bitmap b = ((BitmapDrawable) drawable).getBitmap();
                if (b != null) return b;
            }
            int w = Math.max(1, drawable.getIntrinsicWidth());
            int h = Math.max(1, drawable.getIntrinsicHeight());
            if (w <= 1) w = 96;
            if (h <= 1) h = 96;
            Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);
            drawable.setBounds(0, 0, canvas.getWidth(), canvas.getHeight());
            drawable.draw(canvas);
            return bitmap;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static int parseInt(String s, int def) {
        try { return Integer.parseInt(s.trim()); } catch (Throwable ignored) { return def; }
    }

    private static long parseLong(String s, long def) {
        try { return Long.parseLong(s.trim()); } catch (Throwable ignored) { return def; }
    }

    private static boolean parseBool(String s, boolean def) {
        if (s == null) return def;
        s = s.trim().toLowerCase(Locale.ROOT);
        if ("1".equals(s) || "true".equals(s) || "yes".equals(s) || "y".equals(s) || "on".equals(s)) return true;
        if ("0".equals(s) || "false".equals(s) || "no".equals(s) || "n".equals(s) || "off".equals(s)) return false;
        return def;
    }

    private static String safeLog(String s) {
        if (s == null) return "";
        return s.replace(' ', '_').replace('\t', '_').replace('\n', '_');
    }

    private static String safeFileName(String s) {
        if (s == null || s.length() == 0) return "default";
        return s.replaceAll("[^A-Za-z0-9_.-]", "_");
    }

    private static String timestamp() {
        try { return new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date()); } catch (Throwable ignored) { return "--:--:--"; }
    }

    private static String shortEvent(String event) {
        if (event == null) return "INFO";
        String e = event.toUpperCase(Locale.ROOT);
        if (e.contains("ERROR") || e.contains("FAIL")) return "❌";
        if (e.contains("WARN")) return "⚠️";
        if (e.contains("DONE") || e.contains("FINISH")) return "✅";
        return "•";
    }

    private static String firstNonEmpty(String a, String b) {
        if (a != null && a.length() > 0) return a;
        return b == null ? "" : b;
    }

    private static String percent(long done, long total) {
        if (total <= 0) return "0%";
        long pct = Math.max(0, Math.min(100, Math.round(done * 100.0d / total)));
        return pct + "%";
    }

    private static String formatDuration(long sec) {
        if (sec < 0) return "--:--";
        long h = sec / 3600;
        long m = (sec % 3600) / 60;
        long s = sec % 60;
        if (h > 0) return String.format(Locale.ROOT, "%d:%02d:%02d", h, m, s);
        return String.format(Locale.ROOT, "%02d:%02d", m, s);
    }

    private static String formatBytesPerSec(double bytesPerSec) {
        if (bytesPerSec >= 1024d * 1024d * 1024d) return String.format(Locale.ROOT, "%.1f GB/s", bytesPerSec / 1024d / 1024d / 1024d);
        if (bytesPerSec >= 1024d * 1024d) return String.format(Locale.ROOT, "%.1f MB/s", bytesPerSec / 1024d / 1024d);
        if (bytesPerSec >= 1024d) return String.format(Locale.ROOT, "%.1f KB/s", bytesPerSec / 1024d);
        return String.format(Locale.ROOT, "%.0f B/s", bytesPerSec);
    }

    private static class NotifyEvent {
        String event = "INFO";
        String tag = "speedbackup";
        int id = DEFAULT_RESULT_ID;
        String channelAlias = "result";
        String importanceAlias = "";
        String title = "SpeedBackup";
        String text = "";
        String bigText = "";
        String subText = "";
        String packageName = "";
        String appLabel = "";
        String metricKind = "";
        String metricLine = "";
        String group = "speedbackup";
        boolean groupSummary = false;
        boolean touched = false;
        boolean hasProgress = false;
        int progressMax = 0;
        int progress = 0;
        long metricDone = -1L;
        long metricTotal = -1L;
        long throttleMs = 0L;
        boolean indeterminate = false;
        boolean ongoing = false;
        boolean autoCancel = true;
        boolean onlyAlertOnce = true;
        boolean showWhen = true;
        boolean inbox = false;
        boolean errorAggregate = true;
        long when = System.currentTimeMillis();
        Bitmap largeIcon = null;
        final ArrayList<String> inboxLines = new ArrayList<>();

        boolean hasContent() {
            return touched;
        }

        void normalize() {
            if (event == null || event.length() == 0) event = "INFO";
            if (title == null || title.length() == 0) title = "SpeedBackup";
            if (text == null) text = "";
            if (bigText == null || bigText.length() == 0) bigText = text;
            final String up = event.toUpperCase(Locale.ROOT);
            if (channelAlias == null || channelAlias.length() == 0) {
                if (up.contains("ERROR") || up.contains("WARN") || up.contains("FAIL")) channelAlias = "error";
                else if (up.contains("DEBUG") || up.contains("SELFTEST")) channelAlias = "debug";
                else channelAlias = "progress";
            }
            final String ch = channelAlias.toLowerCase(Locale.ROOT);
            if ("error".equals(ch) || up.contains("ERROR") || up.contains("WARN") || up.contains("FAIL")) {
                tag = "speedbackup_error";
                id = 2021;
                channelAlias = "error";
                ongoing = false;
                autoCancel = true;
                onlyAlertOnce = false;
                inbox = true;
            } else if ("debug".equals(ch)) {
                tag = "speedbackup_debug";
                id = 2023;
                onlyAlertOnce = true;
            } else {
                tag = "speedbackup_main";
                id = 2020;
                channelAlias = "progress";
                onlyAlertOnce = true;
                if (throttleMs <= 0) throttleMs = 500L;
                inbox = true;
                if (hasProgress || "progress".equals(channelAlias)) {
                    ongoing = true;
                    autoCancel = false;
                }
                if (up.contains("DONE") || up.contains("RESULT") || up.contains("FINISH")) {
                    ongoing = false;
                    autoCancel = true;
                }
            }
        }

        boolean isRootStartEvent() {
            String t = text == null ? "" : text.trim();
            String up = event == null ? "" : event.toUpperCase(Locale.ROOT);
            return up.contains("BACKUP_START") || up.contains("RESTORE_START") || "開始備份".equals(t) || t.startsWith("開始恢復");
        }

        boolean isUrgent() {
            String up = event == null ? "" : event.toUpperCase(Locale.ROOT);
            return up.contains("ERROR") || up.contains("WARN") || up.contains("FAIL") || up.contains("DONE") || up.contains("FINISH") || up.contains("RESULT");
        }

        boolean isErrorLike() {
            String up = event == null ? "" : event.toUpperCase(Locale.ROOT);
            String ch = channelAlias == null ? "" : channelAlias.toLowerCase(Locale.ROOT);
            return "error".equals(ch) || up.contains("ERROR") || up.contains("WARN") || up.contains("FAIL");
        }

        File stateFile() {
            return new File(stateDir(), safeFileName(tag + "_" + id) + ".properties");
        }

        int importance() {
            String imp = importanceAlias == null ? "" : importanceAlias.trim().toUpperCase(Locale.ROOT);
            if ("HIGH".equals(imp) || "MAX".equals(imp)) return NotificationManager.IMPORTANCE_HIGH;
            if ("LOW".equals(imp)) return NotificationManager.IMPORTANCE_LOW;
            if ("MIN".equals(imp)) return NotificationManager.IMPORTANCE_MIN;
            if ("NONE".equals(imp)) return NotificationManager.IMPORTANCE_NONE;
            final String ch = channelAlias == null ? "" : channelAlias.toLowerCase(Locale.ROOT);
            if ("error".equals(ch)) return NotificationManager.IMPORTANCE_HIGH;
            if ("progress".equals(ch) || "debug".equals(ch)) return NotificationManager.IMPORTANCE_LOW;
            return NotificationManager.IMPORTANCE_DEFAULT;
        }
    }

    private static INotificationManager getService() {
        if (sService != null) {
            return sService;
        }
        try {
            sService = (INotificationManager) HiddenApiServices.notification();
        } catch (Throwable ignored) {
            sService = null;
        }
        return sService;
    }
}
