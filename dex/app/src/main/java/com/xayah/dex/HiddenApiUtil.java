package com.xayah.dex;

import android.annotation.SuppressLint;
import android.app.PendingIntent;
import android.app.AppOpsManagerHidden;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.Build;
import android.os.IBinder;
import android.os.UserHandleHidden;
import android.net.Uri;
import android.net.LocalSocket;
import android.view.SurfaceControlHidden;

import com.android.server.display.DisplayControlHidden;

import com.xayah.dex.compat.ActivityCompat;
import com.xayah.dex.compat.AppOpsCompat;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;

import java.io.ByteArrayOutputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.text.Collator;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipFile;
import java.nio.charset.StandardCharsets;

import dev.rikka.tools.refine.Refine;

public class HiddenApiUtil {
    static final String VERSION = "v2.6.81-ssaid-metadata-restore build=v24.20.14-7.66-439-ssaid-metadata-restore-20260723";
    /**
     * 單 JVM 批量命令期間的輕量快取。只快取系統層級固定資料或同一輪已讀 package metadata；
     * 不跨 JVM、不落檔，避免一致性風險。
     */
    private static final Map<String, PackageInfo> sPackageInfoCache = new HashMap<>();
    private static final Map<String, Integer> sPackageUidCache = new HashMap<>();
    private static final Map<String, String> sPackageLabelCache = new HashMap<>();

    private static boolean sHumanLog = false;
    private static final String XPOSED_METADATA = "xposedminversion";
    private static final String FLAG_USER = "user";
    private static final String FLAG_SYSTEM = "system";
    private static final String FLAG_XPOSED = "xposed";
    private static final String FORMAT_LABEL = "label";
    private static final String FORMAT_PKG_NAME = "pkgName";
    private static final String FORMAT_FLAG = "flag";
    /**
     * 診斷開關: 環境變數 HIDDENAPI_DEBUG 設為 1/true/yes 時, 將被靜默吞掉的反射例外印到 stderr。
     * 預設關閉, stdout 備份資料格式不受影響。
     */
    private static final boolean DEBUG = parseDebugFlag();

    private static boolean parseDebugFlag() {
        try {
            String v = System.getenv("HIDDENAPI_DEBUG");
            if (v == null) {
                return false;
            }
            v = v.trim().toLowerCase(Locale.ROOT);
            return v.equals("1") || v.equals("true") || v.equals("yes");
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static void debugThrowable(String context, Throwable t) {
        if (DEBUG && t != null) {
            System.err.println("[HiddenApiUtil][DEBUG] " + context + ": " + t.getClass().getName()
                    + (t.getMessage() != null ? ": " + t.getMessage() : ""));
        }
    }

    private static String describeSpecs(CallSpec... specs) {
        if (specs == null || specs.length == 0) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < specs.length; i++) {
            if (i > 0) {
                sb.append(" | ");
            }
            sb.append(specs[i].methodName).append('/')
                    .append(specs[i].args == null ? 0 : specs[i].args.length);
        }
        return sb.toString();
    }

    private static void onHelp() {
        System.out.println("HiddenApiUtil 指令說明:");
        System.out.println("  help  顯示此說明");
        System.out.println("  version / --version / -v  顯示版本資訊");
        System.out.println("  AppState daemon: app_process /system/bin com.xayah.dex.AppStateUtil daemonunix SOCKET [idleSec] [ownerPid]");
        System.out.println("  HiddenApi daemon: app_process /system/bin com.xayah.dex.HiddenApiUtil daemonunix SOCKET [idleSec] [ownerPid]");
        System.out.println();
        System.out.println("  getPackageLabel USER_ID PACKAGE PACKAGE PACKAGE ...  取得應用名稱");
        System.out.println();
        System.out.println("  getPackageArchiveInfo APK_FILE  讀取 APK 檔案資訊");
        System.out.println();
        System.out.println("  hiddenApiBypassStatus  初始化並顯示 AndroidHiddenApiBypass 狀態");
        System.out.println("  daemon-only commands: getPackageUid / getInstallSourceInfo / installSessionCreate / installSessionCommit / forceStopPackageBatch");
        System.out.println("    上述熱路徑只能透過 HiddenApi daemon socket 呼叫，不再提供單次 app_process CLI fallback");
        System.out.println();
        System.out.println("  getInstalledPackagesAsUser USER_ID FILTER_FLAG(user|system|xposed) FORMAT(label|pkgName|flag)  取得安裝清單");
        System.out.println();
        System.out.println("  forceStopPackage USER_ID PACKAGE PACKAGE PACKAGE ...  透過 ActivityManager hidden API 批量停止套件，用於備份前 soft freeze");
        System.out.println("  forceStopPackageBatch USER_ID --stdin  從 stdin 批量讀取套件名稱並停止");
        System.out.println();
        System.out.println("  appOpsScopeDetail USER_ID [PACKAGE OP OP ...] ...  單次 JVM 讀取 package/uid/effective AppOps scope 診斷");
        System.out.println();
        System.out.println("  setDisplayPowerMode MODE(POWER_MODE_OFF: 0, POWER_MODE_NORMAL: 2)  設定螢幕電源模式");
        System.out.println();
    }

    private static void printVersion() {
        System.out.println(VERSION);
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "getPackageLabel":
                getPackageLabel(args);
                break;
            case "getPackageArchiveInfo":
                getPackageArchiveInfo(args);
                break;
            case "getInstalledPackagesAsUser":
                getInstalledPackagesAsUser(args);
                break;
            case "forceStopPackage":
                forceStopPackage(args);
                break;
            case "forceStopPackageBatch":
                forceStopPackageBatch(args);
                break;
            case "appOpsScopeDetail":
                appOpsScopeDetail(args);
                break;
            case "setDisplayPowerMode":
                setDisplayPowerMode(args);
                break;
            case "hiddenApiBypassStatus":
                HiddenApiBypassBridge.printStatus();
                break;
            case "daemonunix":
                cmdDaemonUnix(args);
                break;
            case "version":
            case "--version":
            case "--Version":
            case "-v":
                printVersion();
                break;
            case "help":
                onHelp();
                break;
            default:
                System.out.println("UNKNOWN_COMMAND " + sanitizeDiagValue(cmd));
                System.exit(1);
        }
    }

    public static void main(String[] args) {
        String cmd;
        if (args != null && args.length > 0) {
            cmd = args[0];
            if (!isColdInfoCommand(cmd)) {
                HiddenApiBypassBridge.installExemptionsOnce();
            }
            onCommand(cmd, args);
        } else {
            onHelp();
        }
        System.exit(0);
    }

    private static boolean isColdInfoCommand(String cmd) {
        return "version".equals(cmd) || "--version".equals(cmd) || "--Version".equals(cmd)
                || "-v".equals(cmd) || "help".equals(cmd);
    }

    private static final int DAEMON_PROTOCOL_VERSION = 1;

    private static void cmdDaemonUnix(String[] args) {
        if (args == null || args.length < 2) {
            System.err.println("HIDDENAPI_DAEMON_BAD_ARGS daemonunix <socketPath> [idleTimeoutSec] [ownerPid]");
            System.exit(2);
        }
        String socketPath = args[1];
        long idleTimeoutMs = 1800_000L;
        if (args.length >= 3) {
            try { idleTimeoutMs = Math.max(1L, Long.parseLong(args[2])) * 1000L; } catch (Throwable ignored) {}
        }
        final int ownerPid = args.length >= 4 ? parsePositiveInt(args[3], -1) : -1;
        DaemonBootstrap.runUnixDaemon(
                "HIDDENAPI",
                socketPath,
                idleTimeoutMs,
                ownerPid,
                "HIDDENAPI_DAEMON_READY_UNIX " + socketPath,
                false,
                HiddenApiUtil::handleDaemonClient);
    }

    private static void handleDaemonClient(LocalSocket client) {
        try (LocalSocket c = client) {
            InputStream in = c.getInputStream();
            OutputStream out = c.getOutputStream();
            String command = readUtf8Line(in);
            String protocolRaw = readUtf8Line(in);
            String bodyLengthRaw = readUtf8Line(in);
            int protocol = parsePositiveInt(protocolRaw, -1);
            long bodyLength = parseLong(bodyLengthRaw, -2L);
            byte[] bodyBytes;
            int rc;
            String name;
            String body;
            if (protocol != DAEMON_PROTOCOL_VERSION || bodyLength < -1L) {
                rc = 2;
                name = "BAD_REQUEST";
                body = "HIDDENAPI_DAEMON_BAD_REQUEST\n";
            } else {
                bodyBytes = bodyLength == -1L ? readAll(in) : readExactly(in, bodyLength);
                DaemonRunResult result = runDaemonCommand(command, bodyBytes);
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
            System.err.println("[hiddenapi-daemon] " + t.getClass().getName() + ": " + sanitizeMachineValue(t.getMessage()));
        }
    }

    private static DaemonRunResult runDaemonCommand(String command, byte[] bodyBytes) {
        if (command == null) command = "";
        command = command.trim();
        String body = new String(bodyBytes == null ? new byte[0] : bodyBytes, StandardCharsets.UTF_8);
        List<String> argsList = new ArrayList<>();
        argsList.add(command);
        if (!body.isEmpty()) {
            String[] lines = body.split("\\n", -1);
            for (String line : lines) {
                if (line.endsWith("\r")) line = line.substring(0, line.length() - 1);
                if (line.length() > 0) argsList.add(line);
            }
        }
        String[] cmdArgs = argsList.toArray(new String[0]);
        if ("ping".equals(command)) {
            return new DaemonRunResult(0, "PONG\n");
        }
        if ("forceStopPackageBatch".equals(command)) {
            return forceStopPackageBatchDaemonCommand(cmdArgs);
        }

        PrintStream oldOut = System.out;
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        int rc = 1;
        try {
            System.setOut(new PrintStream(baos, true, "UTF-8"));
            if ("getPackageUid".equals(command)) {
                rc = getPackageUidCommand(cmdArgs);
            } else if ("installSessionCreate".equals(command)) {
                rc = installSessionCreateCommand(cmdArgs);
            } else if ("installSessionCommit".equals(command)) {
                rc = installSessionCommitCommand(cmdArgs);
            } else if ("getInstallSourceInfo".equals(command)) {
                rc = getInstallSourceInfoCommand(cmdArgs);
            } else {
                System.out.println("UNKNOWN_COMMAND " + sanitizeDiagValue(command));
                rc = 2;
            }
        } catch (Throwable t) {
            System.out.println("HIDDENAPI_DAEMON_COMMAND_FAILED command=" + sanitizeDiagValue(command)
                    + " exception=" + t.getClass().getName() + " message=" + sanitizeDiagValue(t.getMessage()));
            t.printStackTrace(System.err);
            rc = 1;
        } finally {
            System.out.flush();
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
        try {
            int v = Integer.parseInt(raw == null ? "" : raw.trim());
            return v > 0 ? v : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static long parseLong(String raw, long fallback) {
        try { return Long.parseLong(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static int getPackageUidCommand(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
            int userId = Integer.parseInt(args[1]);
            for (String packageName : collectPackageNames(args, 2)) {
                try {
                    System.out.println(getPackageUidCached(pmHidden, packageName, userId));
                } catch (Exception e) {
                    System.out.println("PACKAGE_UID_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            return 0;
        } catch (Exception e) {
            e.printStackTrace(System.err);
            return 1;
        }
    }

    private static void getPackageLabel(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
            int userId = Integer.parseInt(args[1]);
            for (String packageName : collectPackageNames(args, 2)) {
                try {
                    System.out.println(getPackageLabelCached(pm, pmHidden, packageName, userId));
                } catch (Exception e) {
                    System.out.println("PACKAGE_LABEL_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void getPackageArchiveInfo(String[] args) {
        String file = args != null && args.length > 1 ? args[1] : "";
        try {
            if (file.isEmpty()) throw new IllegalArgumentException("APK_FILE is required");
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageInfo packageInfo = pm.getPackageArchiveInfo(file, 0);
            if (packageInfo != null && packageInfo.applicationInfo != null) {
                packageInfo.applicationInfo.sourceDir = file;
                packageInfo.applicationInfo.publicSourceDir = file;
                System.out.println(removeSpaces(packageInfo.applicationInfo.loadLabel(pm).toString()) + " " + packageInfo.packageName);
            } else {
                throw new PackageManager.NameNotFoundException("unable to parse APK package info");
            }
            System.exit(0);
        } catch (Exception e) {
            System.err.println("PACKAGE_ARCHIVE_INFO_FAILED path=" + sanitizeMachineValue(file)
                    + " reason=" + sanitizeMachineValue(e.getClass().getSimpleName()));
            if (sHumanLog) e.printStackTrace(System.err);
            System.exit(1);
        }
    }



    private static int installSessionCreateCommand(String[] args) {
        try {
            if (args == null || args.length < 4) {
                throw new IllegalArgumentException("usage: installSessionCreate USER_ID PACKAGE TOTAL_BYTES [OPTIONS]");
            }
            Context ctx = HiddenApiHelper.getContext();
            int userId = Integer.parseInt(args[1]);
            String packageName = args[2];
            long totalBytes = parseLong(args[3], 0L);
            if (totalBytes < 0L) totalBytes = 0L;
            InstallSessionOptions options = parseInstallSessionOptions(args, 4);
            sHumanLog = options.humanLog;
            Context installerCtx = createPackageContextForUser(ctx, "com.android.vending", userId);
            PackageManager realPm = installerCtx.getPackageManager();
            PackageInstaller packageInstaller = realPm.getPackageInstaller();
            System.out.println(packageName + " INSTALL_SESSION_CREATE options " + options.toSummaryString());
            System.out.println(packageName + " INSTALL_SESSION_CREATE totalBytes " + totalBytes);
            System.out.println(packageName + " INSTALL_SESSION_CREATE installerContext " + installerCtx.getPackageName());
            PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(options.mode);
            params.setAppPackageName(packageName);
            applyInstallSessionOptions(params, packageName, totalBytes, options);
            int sessionId = packageInstaller.createSession(params);
            System.out.println(packageName + " INSTALL_SESSION_CREATE sessionId " + sessionId);
            human(packageName, "已由 Play UID 建立安裝 session: " + sessionId);
            return 0;
        } catch (Exception e) {
            String pkg = args != null && args.length > 2 ? args[2] : "unknown";
            System.out.println(pkg + " INSTALL_SESSION_CREATE failed " + e.getClass().getName()
                    + " " + sanitizeDiagValue(e.getMessage()));
            human(pkg, "建立安裝 session 失敗: " + e.getClass().getSimpleName() + " " + sanitizeDiagValue(e.getMessage()));
            printInstallFailureTranslation(pkg, e, e.getMessage());
            e.printStackTrace(System.err);
            return 1;
        }
    }

    private static int installSessionCommitCommand(String[] args) {
        PackageInstaller.Session session = null;
        try {
            if (args == null || args.length < 4) {
                throw new IllegalArgumentException("usage: installSessionCommit USER_ID PACKAGE SESSION_ID [OPTIONS]");
            }
            Context ctx = HiddenApiHelper.getContext();
            int userId = Integer.parseInt(args[1]);
            String packageName = args[2];
            int sessionId = Integer.parseInt(args[3]);
            InstallSessionOptions options = parseInstallSessionOptions(args, 4);
            sHumanLog = options.humanLog;
            Context installerCtx = createPackageContextForUser(ctx, "com.android.vending", userId);
            PackageManager realPm = installerCtx.getPackageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            PackageInstaller packageInstaller = realPm.getPackageInstaller();
            System.out.println(packageName + " INSTALL_SESSION_COMMIT options " + options.toSummaryString());
            System.out.println(packageName + " INSTALL_SESSION_COMMIT installerContext " + installerCtx.getPackageName());
            session = packageInstaller.openSession(sessionId);

            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_MUTABLE;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                try {
                    flags |= PendingIntent.class.getField("FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT").getInt(null);
                } catch (Throwable ignored) {
                }
            }
            Intent statusIntent = new Intent("com.xayah.dex.INSTALL_SESSION_STATUS." + sessionId);
            statusIntent.setPackage("com.android.vending");
            PendingIntent pendingIntent = PendingIntent.getBroadcast(installerCtx, sessionId, statusIntent, flags);
            System.out.println(packageName + " INSTALL_SESSION_COMMIT statusReceiver flags " + flags);
            session.commit(pendingIntent.getIntentSender());
            session.close();
            session = null;
            System.out.println(packageName + " INSTALL_SESSION_COMMIT committed " + sessionId);
            human(packageName, "已由 Play UID 提交安裝 session，等待系統完成安裝");

            long waitStart = System.currentTimeMillis();
            long deadline = waitStart + 60000L;
            boolean found = false;
            while (System.currentTimeMillis() < deadline) {
                try {
                    PackageInfo info = getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                    if (info != null) {
                        found = true;
                        System.out.println(packageName + " INSTALL_SESSION packageFound versionCode "
                                + getLongVersionCodeCompat(info));
                        System.out.println(packageName + " INSTALL_SESSION_COMMIT packageFound versionCode "
                                + getLongVersionCodeCompat(info));
                        human(packageName, "安裝完成: 已找到套件，versionCode=" + getLongVersionCodeCompat(info));
                        try {
                            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
                            Set<String> idleWhitelist = getDeviceIdleWhitelist();
                            GooglePackageSnapshot playStoreSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.android.vending");
                            GooglePackageSnapshot playServicesSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.google.android.gms");
                            printInstallSourceDiagnostics(realPm, pmHidden, userId, packageName, playStoreSnapshot, playServicesSnapshot);
                        } catch (Throwable diagError) {
                            debugThrowable("installSessionCommit post-verify getInstallSourceInfo " + packageName, diagError);
                            System.out.println(packageName + " INSTALL_SESSION sourceVerifyFailed "
                                    + diagError.getClass().getName() + " " + sanitizeDiagValue(diagError.getMessage()));
                        }
                        break;
                    }
                } catch (Throwable ignored) {
                }
                try {
                    long elapsed = System.currentTimeMillis() - waitStart;
                    Thread.sleep(elapsed < 5000L ? 200L : 500L);
                } catch (InterruptedException ignored) {
                    break;
                }
            }
            if (!found) {
                System.out.println(packageName + " INSTALL_SESSION packageNotFoundAfterWait");
                System.out.println(packageName + " INSTALL_SESSION_COMMIT packageNotFoundAfterWait");
                human(packageName, "安裝提交後逾時仍找不到套件，請查看失敗原因與 PackageInstaller/logcat");
                try {
                    printSessionInfoDiagnostics(packageInstaller, sessionId, packageName);
                } catch (Throwable sessionInfoError) {
                    debugThrowable("installSessionCommit sessionInfo after wait " + packageName, sessionInfoError);
                }
                printInstallFailureTranslation(packageName, null, "packageNotFoundAfterWait");
                return 1;
            }
            return 0;
        } catch (Exception e) {
            if (session != null) {
                try { session.abandon(); } catch (Throwable ignored) {}
                try { session.close(); } catch (Throwable ignored) {}
            }
            String pkg = args != null && args.length > 2 ? args[2] : "unknown";
            System.out.println(pkg + " INSTALL_SESSION_COMMIT failed " + e.getClass().getName()
                    + " " + sanitizeDiagValue(e.getMessage()));
            human(pkg, "提交安裝 session 失敗: " + e.getClass().getSimpleName() + " " + sanitizeDiagValue(e.getMessage()));
            printInstallFailureTranslation(pkg, e, e.getMessage());
            e.printStackTrace(System.err);
            return 1;
        }
    }





    private static class InstallSessionOptions {
        int mode = PackageInstaller.SessionParams.MODE_FULL_INSTALL;
        String installerPackageName = "com.android.vending";
        String packageSource = "store";
        String installReason = "user";
        String requireUserAction = "not_required";
        String installLocation = "auto";
        String installScenario = "";
        String volumeUuid = "";
        String abiOverride = "";
        String originatingUri = "";
        String referrerUri = "";
        boolean instantApp = false;
        boolean dontKillApp = false;
        boolean staged = false;
        boolean enableRollback = false;
        boolean humanLog = false;
        List<String> installFlagTokens = new ArrayList<>();
        List<String> clearInstallFlagTokens = new ArrayList<>();
        List<String> permissionStateTokens = new ArrayList<>();
        List<String> apkPaths = new ArrayList<>();

        String toSummaryString() {
            return "mode=" + mode
                    + " installer=" + sanitizeDiagValue(installerPackageName)
                    + " packageSource=" + sanitizeDiagValue(packageSource)
                    + " installReason=" + sanitizeDiagValue(installReason)
                    + " requireUserAction=" + sanitizeDiagValue(requireUserAction)
                    + " installLocation=" + sanitizeDiagValue(installLocation)
                    + " flags=" + sanitizeDiagValue(String.valueOf(installFlagTokens))
                    + " clearFlags=" + sanitizeDiagValue(String.valueOf(clearInstallFlagTokens))
                    + " dontKill=" + dontKillApp
                    + " instant=" + instantApp
                    + " staged=" + staged
                    + " rollback=" + enableRollback
                    + " humanLog=" + humanLog
                    + " apkCount=" + apkPaths.size();
        }
    }

    private static InstallSessionOptions parseInstallSessionOptions(String[] args, int start) {
        InstallSessionOptions options = new InstallSessionOptions();
        for (int i = start; i < args.length; i++) {
            String arg = args[i];
            if (arg == null || arg.trim().isEmpty()) {
                continue;
            }
            if (!arg.startsWith("--")) {
                options.apkPaths.add(arg);
                continue;
            }
            String key;
            String value;
            int eq = arg.indexOf('=');
            if (eq >= 0) {
                key = arg.substring(2, eq).trim().toLowerCase(Locale.ROOT).replace('_', '-');
                value = arg.substring(eq + 1).trim();
            } else {
                key = arg.substring(2).trim().toLowerCase(Locale.ROOT).replace('_', '-');
                value = "1";
            }
            if (key.equals("install-flags") || key.equals("flags")) {
                addCsvTokens(options.installFlagTokens, value);
            } else if (key.equals("clear-install-flags") || key.equals("clear-flags")) {
                addCsvTokens(options.clearInstallFlagTokens, value);
            } else if (key.equals("allow-downgrade")) {
                if (parseBoolean(value)) {
                    options.installFlagTokens.add("INSTALL_ALLOW_DOWNGRADE");
                    options.installFlagTokens.add("INSTALL_REQUEST_DOWNGRADE");
                }
            } else if (key.equals("allow-test")) {
                if (parseBoolean(value)) options.installFlagTokens.add("INSTALL_ALLOW_TEST");
            } else if (key.equals("grant-runtime-permissions")) {
                if (parseBoolean(value)) options.installFlagTokens.add("INSTALL_GRANT_RUNTIME_PERMISSIONS");
            } else if (key.equals("bypass-low-target-sdk-block")) {
                if (parseBoolean(value)) options.installFlagTokens.add("INSTALL_BYPASS_LOW_TARGET_SDK_BLOCK");
            } else if (key.equals("replace-existing")) {
                if (parseBoolean(value)) options.installFlagTokens.add("INSTALL_REPLACE_EXISTING");
            } else if (key.equals("installer")) {
                options.installerPackageName = value;
            } else if (key.equals("package-source") || key.equals("source")) {
                options.packageSource = value;
            } else if (key.equals("install-reason") || key.equals("reason")) {
                options.installReason = value;
            } else if (key.equals("require-user-action") || key.equals("user-action")) {
                options.requireUserAction = value;
            } else if (key.equals("install-location") || key.equals("location")) {
                options.installLocation = value;
            } else if (key.equals("install-scenario") || key.equals("scenario")) {
                options.installScenario = value;
            } else if (key.equals("volume-uuid")) {
                options.volumeUuid = value;
            } else if (key.equals("abi") || key.equals("abi-override")) {
                options.abiOverride = value;
            } else if (key.equals("originating-uri")) {
                options.originatingUri = value;
            } else if (key.equals("referrer-uri")) {
                options.referrerUri = value;
            } else if (key.equals("instant") || key.equals("instant-app")) {
                options.instantApp = parseBoolean(value);
            } else if (key.equals("dont-kill") || key.equals("dont-kill-app")) {
                options.dontKillApp = parseBoolean(value);
            } else if (key.equals("staged")) {
                options.staged = parseBoolean(value);
            } else if (key.equals("enable-rollback") || key.equals("rollback")) {
                options.enableRollback = parseBoolean(value);
            } else if (key.equals("mode")) {
                options.mode = parseInstallMode(value);
            } else if (key.equals("permission-state") || key.equals("perm-state")) {
                addCsvTokens(options.permissionStateTokens, value);
            } else if (key.equals("human-log") || key.equals("human") || key.equals("zh-log")) {
                options.humanLog = parseBoolean(value);
            } else {
                System.out.println("unknown INSTALL_SESSION warnUnknownOption " + sanitizeDiagValue(arg));
            }
        }
        return options;
    }

    private static void human(String packageName, String message) {
        // 保守策略：HUMAN 中文提示不進 stdout，避免污染腳本用英文 key 解析的資料流。
        // 預設 sHumanLog=false；即使手動開啟，也只寫 stderr，stdout 只保留 INSTALL_*/APP_OP/PERMISSION 等機器 key。
        if (!sHumanLog) return;
        if (packageName == null || packageName.isEmpty()) packageName = "unknown";
        System.err.println(packageName + " HUMAN " + sanitizeDiagValue(message));
    }

    private static String valueOrDash(String value) {
        return value == null || value.isEmpty() ? "-" : sanitizeDiagValue(value);
    }

    private static String humanizeException(Throwable e) {
        if (e == null) return "未知錯誤";
        String name = e.getClass().getSimpleName();
        String msg = sanitizeDiagValue(e.getMessage());
        if (msg == null || msg.isEmpty() || msg.equals("null")) msg = "無詳細訊息";
        if (name.contains("Security")) return "權限不足 / 系統拒絕: " + msg;
        if (name.contains("NameNotFound")) return "找不到套件或使用者下未安裝: " + msg;
        if (name.contains("IllegalArgument")) return "參數格式或值不正確: " + msg;
        if (name.contains("InvocationTarget")) return "隱藏 API 呼叫失敗: " + msg;
        if (name.contains("NoSuchMethod") || name.contains("NoSuchField")) return "此 Android 版本或 ROM 不支援對應隱藏 API: " + msg;
        return name + ": " + msg;
    }

    private static void addCsvTokens(List<String> out, String csv) {
        if (csv == null) return;
        for (String token : csv.split(",")) {
            String t = token.trim();
            if (!t.isEmpty()) out.add(t);
        }
    }

    private static boolean parseBoolean(String value) {
        if (value == null) return false;
        String v = value.trim().toLowerCase(Locale.ROOT);
        return v.equals("1") || v.equals("true") || v.equals("yes") || v.equals("on") || v.equals("y");
    }

    private static int parseInstallMode(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        if (v.equals("inherit") || v.equals("inherit_existing") || v.equals("inherit-existing")) {
            return getSessionParamsConstant("MODE_INHERIT_EXISTING", PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        }
        if (v.matches("^-?\\d+$")) {
            try { return Integer.parseInt(v); } catch (Throwable ignored) {}
        }
        return PackageInstaller.SessionParams.MODE_FULL_INSTALL;
    }

    private static void applyInstallSessionOptions(PackageInstaller.SessionParams params, String packageName, long totalBytes, InstallSessionOptions options) {
        tryCall(params, "setSize", totalBytes, packageName);
        if (options.installerPackageName != null && !options.installerPackageName.isEmpty()) {
            tryCall(params, "setInstallerPackageName", options.installerPackageName, packageName);
        }
        tryCall(params, "setPackageSource", parsePackageSource(options.packageSource), packageName);
        tryCall(params, "setInstallReason", parseInstallReason(options.installReason), packageName);
        tryCall(params, "setRequireUserAction", parseRequireUserAction(options.requireUserAction), packageName);
        tryCall(params, "setInstallAsInstantApp", options.instantApp, packageName);
        tryCall(params, "setDontKillApp", options.dontKillApp, packageName);
        if (options.staged) tryCall(params, "setStaged", true, packageName);
        if (options.enableRollback) tryCall(params, "setEnableRollback", true, packageName);
        int installLocation = parseInstallLocation(options.installLocation);
        if (installLocation != Integer.MIN_VALUE) {
            tryCall(params, "setInstallLocation", installLocation, packageName);
        }
        int scenario = parseInstallScenario(options.installScenario);
        if (scenario != Integer.MIN_VALUE) {
            tryCall(params, "setInstallScenario", scenario, packageName);
        }
        if (options.volumeUuid != null && !options.volumeUuid.isEmpty()) {
            tryCall(params, "setVolumeUuid", options.volumeUuid, packageName);
        }
        if (options.abiOverride != null && !options.abiOverride.isEmpty()) {
            tryCall(params, "setAbiOverride", options.abiOverride, packageName);
        }
        if (options.originatingUri != null && !options.originatingUri.isEmpty()) {
            tryCall(params, "setOriginatingUri", Uri.parse(options.originatingUri), packageName);
        }
        if (options.referrerUri != null && !options.referrerUri.isEmpty()) {
            tryCall(params, "setReferrerUri", Uri.parse(options.referrerUri), packageName);
        }
        applyInstallFlags(params, packageName, options);
        applyPermissionStates(params, packageName, options.permissionStateTokens);
        printSessionParamsDiagnostics(params, packageName);
    }

    private static void tryCall(Object target, String methodName, Object value, String packageName) {
        try {
            invokeFlexible(target, methodName, value);
            System.out.println(packageName + " INSTALL_SESSION param " + methodName + "=" + sanitizeDiagValue(String.valueOf(value)));
        } catch (Throwable e) {
            System.out.println(packageName + " INSTALL_SESSION warnParamUnsupported " + methodName + " " + sanitizeDiagValue(e.getClass().getSimpleName()));
            debugThrowable("SessionParams." + methodName, e);
        }
    }

    private static void applyInstallFlags(PackageInstaller.SessionParams params, String packageName, InstallSessionOptions options) {
        try {
            java.lang.reflect.Field field = PackageInstaller.SessionParams.class.getDeclaredField("installFlags");
            field.setAccessible(true);
            int flags = field.getInt(params);
            int original = flags;
            for (String token : options.installFlagTokens) {
                Integer bit = resolveInstallFlag(token);
                if (bit == null) {
                    System.out.println(packageName + " INSTALL_SESSION warnUnknownInstallFlag " + sanitizeDiagValue(token));
                    continue;
                }
                flags |= bit;
                System.out.println(packageName + " INSTALL_SESSION installFlagAdd " + sanitizeDiagValue(token) + "=" + bit);
            }
            for (String token : options.clearInstallFlagTokens) {
                Integer bit = resolveInstallFlag(token);
                if (bit == null) {
                    System.out.println(packageName + " INSTALL_SESSION warnUnknownClearInstallFlag " + sanitizeDiagValue(token));
                    continue;
                }
                flags &= ~bit;
                System.out.println(packageName + " INSTALL_SESSION installFlagClear " + sanitizeDiagValue(token) + "=" + bit);
            }
            field.setInt(params, flags);
            System.out.println(packageName + " INSTALL_SESSION installFlags original=" + original + " final=" + flags);
        } catch (Throwable e) {
            System.out.println(packageName + " INSTALL_SESSION warnInstallFlagsUnsupported " + sanitizeDiagValue(e.getClass().getName()));
            debugThrowable("SessionParams.installFlags", e);
        }
    }

    private static Integer resolveInstallFlag(String token) {
        if (token == null || token.trim().isEmpty()) return null;
        String raw = token.trim();
        if (raw.matches("^-?\\d+$")) {
            try { return Integer.parseInt(raw); } catch (Throwable ignored) { return null; }
        }
        String name = raw.toUpperCase(Locale.ROOT).replace('-', '_');
        if (!name.startsWith("INSTALL_")) name = "INSTALL_" + name;
        Integer v = reflectIntField(PackageManager.class, name);
        if (v != null) return v;
        // 某些 ROM/API 使用不同命名；只在常見別名上做映射，不硬塞不確定數值。
        if (name.equals("INSTALL_DOWNGRADE")) return reflectIntField(PackageManager.class, "INSTALL_ALLOW_DOWNGRADE");
        if (name.equals("INSTALL_BYPASS_LOW_TARGET") || name.equals("INSTALL_BYPASS_LOW_TARGET_SDK")) return reflectIntField(PackageManager.class, "INSTALL_BYPASS_LOW_TARGET_SDK_BLOCK");
        return null;
    }

    private static Integer reflectIntField(Class<?> clazz, String fieldName) {
        try {
            java.lang.reflect.Field f;
            try {
                f = clazz.getField(fieldName);
            } catch (NoSuchFieldException e) {
                f = clazz.getDeclaredField(fieldName);
            }
            f.setAccessible(true);
            return f.getInt(null);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static int parsePackageSource(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
        if (v.matches("^-?\\d+$")) return Integer.parseInt(v);
        if (v.equals("store") || v.equals("play")) return getPackageInstallerConstant("PACKAGE_SOURCE_STORE", 2);
        if (v.equals("local") || v.equals("local_file")) return getPackageInstallerConstant("PACKAGE_SOURCE_LOCAL_FILE", 3);
        if (v.equals("download") || v.equals("downloaded") || v.equals("downloaded_file")) return getPackageInstallerConstant("PACKAGE_SOURCE_DOWNLOADED_FILE", 4);
        if (v.equals("other")) return getPackageInstallerConstant("PACKAGE_SOURCE_OTHER", 1);
        return getPackageInstallerConstant("PACKAGE_SOURCE_UNSPECIFIED", 0);
    }

    private static int parseInstallReason(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
        if (v.matches("^-?\\d+$")) return Integer.parseInt(v);
        if (v.equals("user")) return getPackageManagerConstant("INSTALL_REASON_USER", 4);
        if (v.equals("policy")) return getPackageManagerConstant("INSTALL_REASON_POLICY", 1);
        if (v.equals("device_restore") || v.equals("restore")) return getPackageManagerConstant("INSTALL_REASON_DEVICE_RESTORE", 2);
        if (v.equals("device_setup") || v.equals("setup")) return getPackageManagerConstant("INSTALL_REASON_DEVICE_SETUP", 3);
        if (v.equals("package_manager") || v.equals("pm")) return getPackageManagerConstant("INSTALL_REASON_PACKAGE_MANAGER", 5);
        return getPackageManagerConstant("INSTALL_REASON_UNKNOWN", 0);
    }

    private static int parseRequireUserAction(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
        if (v.matches("^-?\\d+$")) return Integer.parseInt(v);
        if (v.equals("required") || v.equals("require")) return getSessionParamsConstant("USER_ACTION_REQUIRED", 1);
        if (v.equals("not_required") || v.equals("none") || v.equals("silent")) return getSessionParamsConstant("USER_ACTION_NOT_REQUIRED", 2);
        return getSessionParamsConstant("USER_ACTION_UNSPECIFIED", 0);
    }

    private static int parseInstallLocation(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
        if (v.isEmpty() || v.equals("auto") || v.equals("default")) return Integer.MIN_VALUE;
        if (v.matches("^-?\\d+$")) return Integer.parseInt(v);
        if (v.equals("internal") || v.equals("internal_only")) return PackageInfo.INSTALL_LOCATION_INTERNAL_ONLY;
        if (v.equals("prefer_external") || v.equals("external")) return PackageInfo.INSTALL_LOCATION_PREFER_EXTERNAL;
        return Integer.MIN_VALUE;
    }

    private static int parseInstallScenario(String value) {
        String v = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('-', '_');
        if (v.isEmpty() || v.equals("default")) return Integer.MIN_VALUE;
        if (v.matches("^-?\\d+$")) return Integer.parseInt(v);
        if (v.equals("fast")) return getSessionParamsConstant("INSTALL_SCENARIO_FAST", Integer.MIN_VALUE);
        if (v.equals("bulk")) return getSessionParamsConstant("INSTALL_SCENARIO_BULK", Integer.MIN_VALUE);
        if (v.equals("bulk_secondary")) return getSessionParamsConstant("INSTALL_SCENARIO_BULK_SECONDARY", Integer.MIN_VALUE);
        return Integer.MIN_VALUE;
    }

    private static void applyPermissionStates(PackageInstaller.SessionParams params, String packageName, List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) return;
        for (String token : tokens) {
            try {
                String[] parts = token.split(":", 2);
                String perm = parts[0].trim();
                String stateName = parts.length > 1 ? parts[1].trim().toLowerCase(Locale.ROOT) : "granted";
                int state;
                if (stateName.equals("granted") || stateName.equals("grant") || stateName.equals("1")) {
                    state = getPackageInstallerConstant("PERMISSION_STATE_GRANTED", 1);
                } else if (stateName.equals("denied") || stateName.equals("deny") || stateName.equals("2")) {
                    state = getPackageInstallerConstant("PERMISSION_STATE_DENIED", 2);
                } else {
                    state = getPackageInstallerConstant("PERMISSION_STATE_DEFAULT", 0);
                }
                invokeFlexible(params, "setPermissionState", perm, state);
                System.out.println(packageName + " INSTALL_SESSION permissionState " + sanitizeDiagValue(perm) + "=" + state);
            } catch (Throwable e) {
                System.out.println(packageName + " INSTALL_SESSION warnPermissionStateUnsupported " + sanitizeDiagValue(token));
                debugThrowable("SessionParams.setPermissionState", e);
            }
        }
    }

    private static void printSessionParamsDiagnostics(PackageInstaller.SessionParams params, String packageName) {
        printObjectIntField(params, packageName, "SessionParams", "installFlags");
        printObjectIntField(params, packageName, "SessionParams", "installLocation");
        printObjectIntField(params, packageName, "SessionParams", "installReason");
        printObjectStringField(params, packageName, "SessionParams", "installerPackageName");
        printObjectStringField(params, packageName, "SessionParams", "volumeUuid");
    }

    private static void printObjectIntField(Object object, String packageName, String prefix, String fieldName) {
        try {
            java.lang.reflect.Field f = object.getClass().getDeclaredField(fieldName);
            f.setAccessible(true);
            System.out.println(packageName + " INSTALL_SESSION " + prefix + "." + fieldName + "=" + f.getInt(object));
        } catch (Throwable ignored) {
        }
    }

    private static void printObjectStringField(Object object, String packageName, String prefix, String fieldName) {
        try {
            java.lang.reflect.Field f = object.getClass().getDeclaredField(fieldName);
            f.setAccessible(true);
            Object v = f.get(object);
            System.out.println(packageName + " INSTALL_SESSION " + prefix + "." + fieldName + "=" + sanitizeDiagValue(String.valueOf(v)));
        } catch (Throwable ignored) {
        }
    }

    private static void printSessionInfoDiagnostics(PackageInstaller packageInstaller, int sessionId, String packageName) {
        if (sessionId < 0) return;
        try {
            Object info = invokeFlexible(packageInstaller, "getSessionInfo", sessionId);
            if (info == null) {
                System.out.println(packageName + " INSTALL_SESSION sessionInfo null");
                return;
            }
            String[] getters = new String[] {
                    "getSessionId", "getAppPackageName", "getInstallerPackageName", "getProgress",
                    "isCommitted", "isStaged", "isSessionReady", "isSessionApplied", "isSessionFailed",
                    "getInstallReason", "getPackageSource", "getInstallScenario", "getRequireUserAction"
            };
            for (String getter : getters) {
                try {
                    Object v = invokeFlexible(info, getter);
                    System.out.println(packageName + " INSTALL_SESSION sessionInfo." + getter + "=" + sanitizeDiagValue(String.valueOf(v)));
                } catch (Throwable ignored) {
                }
            }
        } catch (Throwable e) {
            debugThrowable("PackageInstaller.getSessionInfo", e);
        }
    }

    private static void printInstallFailureTranslation(String packageName, Throwable throwable, String rawMessage) {
        String text = ((throwable == null ? "" : throwable.getClass().getName()) + " " + String.valueOf(rawMessage)).toLowerCase(Locale.ROOT);
        String code = "UNKNOWN";
        String hint = "UNKNOWN_ERROR_CHECK_INSTALL_SESSION_FAILED_LOGCAT_PACKAGEINSTALLER_PM_INSTALL";
        if (text.contains("version downgrade") || text.contains("downgrade")) {
            code = "VERSION_DOWNGRADE";
            hint = "VERSION_CODE_LOWER_THAN_INSTALLED_ENABLE_ALLOW_DOWNGRADE_IF_ROM_ALLOWS";
        } else if (text.contains("signatures do not match") || text.contains("inconsistent certificates") || text.contains("update incompatible")) {
            code = "UPDATE_INCOMPATIBLE";
            hint = "INSTALLED_APP_SIGNATURE_DIFFERS_UNINSTALL_OR_USE_SAME_SIGNATURE_APK";
        } else if (text.contains("missing split") || text.contains("split") && text.contains("missing")) {
            code = "MISSING_SPLIT";
            hint = "MISSING_REQUIRED_SPLIT_INSTALL_BASE_AND_REQUIRED_CONFIG_SPLITS_TOGETHER";
        } else if (text.contains("no matching abis") || text.contains("abi")) {
            code = "NO_MATCHING_ABIS";
            hint = "ABI_SPLIT_NOT_MATCH_DEVICE_OR_REQUIRED_ABI_SPLIT_MISSING";
        } else if (text.contains("insufficient storage") || text.contains("no space")) {
            code = "INSUFFICIENT_STORAGE";
            hint = "INSUFFICIENT_STORAGE";
        } else if (text.contains("parse") || text.contains("invalid apk") || text.contains("failed to parse")) {
            code = "INVALID_APK";
            hint = "INVALID_OR_CORRUPT_APK_CHECK_ARCHIVE_AND_SPLITS";
        } else if (text.contains("test-only") || text.contains("test only")) {
            code = "TEST_ONLY_BLOCKED";
            hint = "TEST_ONLY_APK_BLOCKED_ENABLE_ALLOW_TEST";
        } else if (text.contains("blocked") && text.contains("target")) {
            code = "LOW_TARGET_SDK_BLOCKED";
            hint = "LOW_TARGET_SDK_BLOCKED_ENABLE_BYPASS_LOW_TARGET_IF_ROM_SUPPORTS";
        } else if (text.contains("verification") || text.contains("verifier")) {
            code = "VERIFICATION_FAILED";
            hint = "SYSTEM_VERIFIER_REJECTED_CHECK_LOGCAT_VERIFIER_PACKAGEINSTALLER";
        }
        System.out.println(packageName + " INSTALL_SESSION failureCode " + code);
        System.out.println(packageName + " INSTALL_ERROR_CLASS pkg=" + sanitizeDiagValue(packageName) + " class=" + code + " hint=" + sanitizeDiagValue(hint));
        System.out.println(packageName + " INSTALL_SESSION failureHint " + sanitizeDiagValue(hint));
        human(packageName, "安裝失敗原因: " + hint + " (" + code + ")");
    }

    private static Context createPackageContextForUser(Context base, String packageName, int userId) throws Exception {
        try {
            Object userHandle = UserHandleHidden.of(userId);
            Object result = invokeFlexible(base, "createPackageContextAsUser",
                    packageName, Context.CONTEXT_IGNORE_SECURITY, userHandle);
            if (result instanceof Context) {
                return (Context) result;
            }
        } catch (Throwable e) {
            debugThrowable("createPackageContextAsUser " + packageName + " user=" + userId, e);
        }
        return base.createPackageContext(packageName, Context.CONTEXT_IGNORE_SECURITY);
    }







    private static List<String> dedupeFilePaths(List<String> paths) {
        List<String> out = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String path : paths) {
            if (path == null || path.trim().isEmpty()) {
                continue;
            }
            String key;
            try {
                key = new File(path).getCanonicalPath();
            } catch (Throwable ignored) {
                key = new File(path).getAbsolutePath();
            }
            if (seen.add(key)) {
                out.add(path);
            }
        }
        return out;
    }

    private static String uniqueSessionFileName(String originalName, Set<String> usedNames) {
        String base = sanitizeSessionFileName(originalName);
        String name = base;
        int index = 1;
        while (usedNames.contains(name)) {
            String stem = base;
            String ext = "";
            int dot = base.lastIndexOf('.');
            if (dot > 0) {
                stem = base.substring(0, dot);
                ext = base.substring(dot);
            }
            name = stem + "_" + index + ext;
            index++;
        }
        usedNames.add(name);
        return name;
    }

    private static String sanitizeSessionFileName(String name) {
        if (name == null || name.isEmpty()) {
            return "base.apk";
        }
        String n = name.replaceAll("[^A-Za-z0-9._-]", "_");
        if (!n.endsWith(".apk")) {
            n = n + ".apk";
        }
        return n;
    }

    private static int getSessionParamsConstant(String fieldName, int fallback) {
        try {
            java.lang.reflect.Field field = PackageInstaller.SessionParams.class.getField(fieldName);
            field.setAccessible(true);
            return field.getInt(null);
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static int getPackageInstallerConstant(String fieldName, int fallback) {
        try {
            java.lang.reflect.Field field = PackageInstaller.class.getField(fieldName);
            return field.getInt(null);
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static int getPackageManagerConstant(String fieldName, int fallback) {
        try {
            java.lang.reflect.Field field = PackageManager.class.getField(fieldName);
            return field.getInt(null);
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static int getInstallSourceInfoCommand(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            Set<String> idleWhitelist = getDeviceIdleWhitelist();
            // Play Store / Play services 的快照與當前 target package 無關, 對整批只需算一次,
            // 提到迴圈外避免每個 app 重複 getPackageInfoAsUser + getOpMode + getApplicationEnabledSetting。
            GooglePackageSnapshot playStoreSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.android.vending");
            GooglePackageSnapshot playServicesSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.google.android.gms");
            for (String packageName : collectPackageNames(args, 2)) {
                try {
                    printInstallSourceDiagnostics(realPm, pmHidden, userId, packageName, playStoreSnapshot, playServicesSnapshot);
                } catch (Exception e) {
                    System.out.println("INSTALL_SOURCE_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                    human(packageName, "讀取安裝來源失敗: " + humanizeException(e));
                }
            }
            return 0;
        } catch (Exception e) {
            e.printStackTrace(System.err);
            return 1;
        }
    }

    private static void printInstallSourceDiagnostics(
            PackageManager realPm,
            PackageManagerHidden pmHidden,
            int userId,
            String packageName,
            GooglePackageSnapshot playStore,
            GooglePackageSnapshot playServices
    ) throws Exception {
        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            flags |= PackageManager.GET_SIGNING_CERTIFICATES;
        } else {
            flags |= PackageManager.GET_SIGNATURES;
        }
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, flags, userId);
        String installer = null;
        try {
            installer = realPm.getInstallerPackageName(packageName);
        } catch (Throwable e) {
            debugThrowable("getInstallerPackageName " + packageName, e);
        }
        InstallSourceSnapshot source = readInstallSourceInfo(realPm, packageName, installer);
        String installing = firstNonEmpty(source.installingPackageName, installer);
        long versionCode = getLongVersionCodeCompat(packageInfo);
        int splitCount = packageInfo.splitNames == null ? 0 : packageInfo.splitNames.length;
        String signingSha256 = getSigningSha256(packageInfo);

        printInstallDiag(packageName, "installer", installer);
        printInstallDiag(packageName, "installing", installing);
        printInstallDiag(packageName, "initiating", source.initiatingPackageName);
        printInstallDiag(packageName, "originating", source.originatingPackageName);
        printInstallDiag(packageName, "updateOwner", source.updateOwnerPackageName);
        printInstallDiag(packageName, "updateOwnerApi", source.updateOwnerApi);
        printInstallDiag(packageName, "packageSource", source.packageSource);
        printInstallDiag(packageName, "packageSourceName", source.packageSourceName);
        printInstallDiag(packageName, "versionCode", String.valueOf(versionCode));
        printInstallDiag(packageName, "versionName", packageInfo.versionName);
        printInstallDiag(packageName, "signingSha256", signingSha256);
        printInstallDiag(packageName, "splitCount", String.valueOf(splitCount));
        printInstallDiag(packageName, "sourceDir", packageInfo.applicationInfo != null ? packageInfo.applicationInfo.sourceDir : null);
        printGooglePackageDiag(packageName, "playStore", playStore);
        printGooglePackageDiag(packageName, "playServices", playServices);
        human(packageName, "安裝來源: installer=" + valueOrDash(installer)
                + ", installing=" + valueOrDash(installing)
                + ", initiating=" + valueOrDash(source.initiatingPackageName)
                + ", source=" + valueOrDash(source.packageSourceName));

    }

    private static void printInstallDiag(String packageName, String key, String value) {
        System.out.println(packageName + " INSTALL_DIAG " + key + " " + sanitizeDiagValue(value));
    }

    private static String sanitizeDiagValue(String value) {
        if (value == null || value.isEmpty()) {
            return "null";
        }
        return value.replace('\n', '_').replace('\r', '_').replace(' ', '_').replace('\t', '_');
    }

    private static String failureReason(Throwable e) {
        if (e == null) {
            return "unknown";
        }
        String cls = e.getClass().getSimpleName();
        String msg = e.getMessage();
        if (msg == null || msg.isEmpty()) {
            return sanitizeMachineValue(cls);
        }
        return sanitizeMachineValue(cls + ":" + msg);
    }

    private static String sanitizeMachineValue(String value) {
        String v = sanitizeDiagValue(value);
        StringBuilder out = new StringBuilder(v.length());
        for (int i = 0; i < v.length(); i++) {
            char c = v.charAt(i);
            if (c >= 0x21 && c <= 0x7e) {
                out.append(c);
            } else {
                out.append('_');
            }
        }
        return out.toString();
    }

    private static String firstNonEmpty(String a, String b) {
        if (a != null && !a.isEmpty()) {
            return a;
        }
        return b;
    }

    private static long getLongVersionCodeCompat(PackageInfo packageInfo) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return packageInfo.getLongVersionCode();
            }
        } catch (Throwable ignored) {
        }
        return packageInfo.versionCode;
    }

    private static GooglePackageSnapshot getGooglePackageSnapshot(
            PackageManager realPm,
            PackageManagerHidden pmHidden,
            AppOpsManagerHidden appOpsManager,
            Set<String> idleWhitelist,
            int userId,
            String packageName
    ) {
        return GooglePackageSnapshot.collect(
                realPm,
                pmHidden,
                appOpsManager,
                idleWhitelist,
                userId,
                packageName,
                new GooglePackageSnapshot.PackageInfoReader() {
                    @Override
                    public PackageInfo get(PackageManagerHidden hidden, String pkg, int flags, int user)
                            throws Throwable {
                        return getPackageInfoAsUserCached(hidden, pkg, flags, user);
                    }
                });
    }

    private static void printGooglePackageDiag(String targetPackageName, String prefix, GooglePackageSnapshot snapshot) {
        if (snapshot == null) {
            printInstallDiag(targetPackageName, prefix, "missing");
            return;
        }
        printInstallDiag(targetPackageName, prefix, snapshot.state);
        printInstallDiag(targetPackageName, prefix + "EnabledState", snapshot.enabledState);
        printInstallDiag(targetPackageName, prefix + "Uid", snapshot.uid);
        printInstallDiag(targetPackageName, prefix + "VersionCode", snapshot.versionCode);
        printInstallDiag(targetPackageName, prefix + "RunInBackgroundMode", snapshot.runInBackgroundMode);
        printInstallDiag(targetPackageName, prefix + "RunAnyInBackgroundMode", snapshot.runAnyInBackgroundMode);
        printInstallDiag(targetPackageName, prefix + "DeviceIdleWhitelist", snapshot.deviceIdleWhitelist);
    }

    private static InstallSourceSnapshot readInstallSourceInfo(PackageManager pm, String packageName, String installerFallback) {
        InstallSourceSnapshot out = new InstallSourceSnapshot();
        out.packageSource = "null";
        out.packageSourceName = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ? "UNKNOWN" : "UNAVAILABLE_API_LT_30";
        out.updateOwnerApi = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ? "api34_plus" : "unsupported_pre34";
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // Android 9/10 沒有 getInstallSourceInfo(String)，明確 fallback 到 getInstallerPackageName。
            out.installingPackageName = installerFallback;
            return out;
        }
        try {
            // 透過共用 HiddenApiReflection 快取反射方法。
            // 只解析一次, 跨 package 命中快取; API<30 無此方法時負結果亦被快取為 MISS, 不重複全掃。
            Object info = invokeFlexible(pm, "getInstallSourceInfo", packageName);
            out.installingPackageName = firstNonEmpty(safeString(invokeNoArg(info, "getInstallingPackageName")), installerFallback);
            out.initiatingPackageName = safeString(invokeNoArg(info, "getInitiatingPackageName"));
            out.originatingPackageName = safeString(invokeNoArg(info, "getOriginatingPackageName"));
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                out.updateOwnerPackageName = safeString(invokeNoArg(info, "getUpdateOwnerPackageName"));
            }
            Object source = invokeNoArg(info, "getPackageSource");
            if (source instanceof Number) {
                int sourceValue = ((Number) source).intValue();
                out.packageSource = String.valueOf(sourceValue);
                out.packageSourceName = packageSourceToName(sourceValue);
            }
        } catch (Throwable e) {
            out.installingPackageName = installerFallback;
            debugThrowable("getInstallSourceInfo " + packageName, e);
        }
        return out;
    }

    private static volatile Map<Integer, String> PACKAGE_SOURCE_NAMES;

    private static String packageSourceToName(int source) {
        Map<Integer, String> map = PACKAGE_SOURCE_NAMES;
        if (map == null) {
            map = new java.util.HashMap<>();
            try {
                Class<?> clazz = classForNameCached("android.content.pm.PackageInstaller");
                for (java.lang.reflect.Field field : clazz.getFields()) {
                    if (!field.getName().startsWith("PACKAGE_SOURCE_")) {
                        continue;
                    }
                    if (field.getType() == int.class) {
                        map.put(field.getInt(null), field.getName());
                    }
                }
            } catch (Throwable ignored) {
            }
            PACKAGE_SOURCE_NAMES = map;
        }
        String name = map.get(source);
        return name != null ? name : "UNKNOWN_" + source;
    }

    private static String getSigningSha256(PackageInfo packageInfo) {
        try {
            android.content.pm.Signature[] signatures = null;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && packageInfo.signingInfo != null) {
                if (packageInfo.signingInfo.hasMultipleSigners()) {
                    signatures = packageInfo.signingInfo.getApkContentsSigners();
                } else {
                    signatures = packageInfo.signingInfo.getSigningCertificateHistory();
                }
            }
            if ((signatures == null || signatures.length == 0) && packageInfo.signatures != null) {
                signatures = packageInfo.signatures;
            }
            if (signatures == null || signatures.length == 0) {
                return "null";
            }
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            List<String> result = new ArrayList<>();
            for (android.content.pm.Signature signature : signatures) {
                if (signature == null) {
                    continue;
                }
                result.add(bytesToHex(digest.digest(signature.toByteArray())));
            }
            return result.isEmpty() ? "null" : String.join(",", result);
        } catch (Throwable e) {
            debugThrowable("getSigningSha256", e);
            return "null";
        }
    }

    private static String bytesToHex(byte[] bytes) {
        char[] hexArray = "0123456789abcdef".toCharArray();
        char[] hexChars = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int v = bytes[i] & 0xff;
            hexChars[i * 2] = hexArray[v >>> 4];
            hexChars[i * 2 + 1] = hexArray[v & 0x0f];
        }
        return new String(hexChars);
    }

    private static final class InstallSourceSnapshot {
        String installingPackageName;
        String initiatingPackageName;
        String originatingPackageName;
        String updateOwnerPackageName;
        String updateOwnerApi;
        String packageSource;
        String packageSourceName;
    }

    private static void getInstalledPackagesAsUser(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManagerUtil.PackageManagerWithLocale packageManagerWithLocale = PackageManagerUtil.getPackageManager(ctx);
            Locale locale = packageManagerWithLocale.locale();
            PackageManager pm = packageManagerWithLocale.packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
            int userId = Integer.parseInt(args[1]);
            List<String> filterFlags = new ArrayList<>();
            List<String> formatList = new ArrayList<>();
            try {
                filterFlags = Arrays.asList(args[2].split("\\|"));
            } catch (Exception ignored) {
            }
            if (filterFlags.isEmpty()) {
                filterFlags.add(FLAG_USER);
                filterFlags.add(FLAG_SYSTEM);
            }
            try {
                formatList = Arrays.asList(args[3].split("\\|"));
            } catch (Exception ignored) {
            }
            if (formatList.isEmpty()) {
                formatList.add(FORMAT_LABEL);
                formatList.add(FORMAT_PKG_NAME);
                formatList.add(FORMAT_FLAG);
            }
            boolean userFlag = filterFlags.contains(FLAG_USER);
            boolean systemFlag = filterFlags.contains(FLAG_SYSTEM);
            boolean xposedFlag = filterFlags.contains(FLAG_XPOSED);
            List<PackageInfo> packages = pmHidden.getInstalledPackagesAsUser(PackageManager.GET_META_DATA, userId);
            Collator collator = Collator.getInstance(locale != null ? locale : ctx.getResources().getConfiguration().getLocales().get(0));
            packages.sort((p1, p2) -> {
                if (p1 != null && p2 != null) {
                    return collator.getCollationKey(p1.applicationInfo.loadLabel(pm).toString())
                            .compareTo(collator.getCollationKey(p2.applicationInfo.loadLabel(pm).toString()));
                }
                return 0;
            });
            for (PackageInfo pkg : packages) {
                boolean isSystemApp = (pkg.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
                boolean isUserApp = !isSystemApp;
                boolean isXposedApp = ((pkg.applicationInfo.metaData != null && pkg.applicationInfo.metaData.containsKey(XPOSED_METADATA))
                        || isModernModules(pkg.applicationInfo));
                if ((userFlag && isUserApp) || (systemFlag && isSystemApp) || (xposedFlag && isXposedApp)) {
                    StringBuilder out = new StringBuilder();
                    for (String format : formatList) {
                        switch (format) {
                            case FORMAT_LABEL ->
                                    out.append(" ").append(removeSpaces(pkg.applicationInfo.loadLabel(pm).toString().replaceAll("\n", "")));
                            case FORMAT_PKG_NAME -> out.append(" ").append(pkg.packageName);
                            case FORMAT_FLAG -> {
                                List<String> flags = new ArrayList<>();
                                if (isUserApp) {
                                    flags.add(FLAG_USER);
                                }
                                if (isSystemApp) {
                                    flags.add(FLAG_SYSTEM);
                                }
                                if (isXposedApp) {
                                    flags.add(FLAG_XPOSED);
                                }
                                out.append(" ").append(String.join("|", flags));
                            }
                        }
                    }
                    String item = out.toString().trim();
                    if (!item.isEmpty()) {
                        System.out.println(item);
                    }
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static String getPublicName(int op) {
        try {
            String publicName = AppOpsManagerHidden.opToPublicName(op);
            if (publicName != null && !publicName.isEmpty()) {
                return publicName;
            }
        } catch (Throwable ignored) {
        }
        try {
            String name = AppOpsManagerHidden.opToName(op);
            if (name != null && !name.isEmpty()) {
                return "android:" + name.toLowerCase(Locale.ROOT);
            }
        } catch (Throwable ignored) {
        }
        return "android:op_" + op;
    }

    private static byte[] readAllStdinBytes() throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] chunk = new byte[8192];
        int n;
        while ((n = System.in.read(chunk)) != -1) {
            buffer.write(chunk, 0, n);
        }
        return buffer.toByteArray();
    }

    private static String packageInfoCacheKey(String packageName, int flags, int userId) {
        return userId + "|" + flags + "|" + packageName;
    }

    private static PackageInfo getPackageInfoAsUserCached(PackageManagerHidden pm, String packageName, int flags, int userId) throws Exception {
        String key = packageInfoCacheKey(packageName, flags, userId);
        PackageInfo cached = sPackageInfoCache.get(key);
        if (cached != null) {
            return cached;
        }
        PackageInfo info = pm.getPackageInfoAsUser(packageName, flags, userId);
        if (info != null) {
            sPackageInfoCache.put(key, info);
            if ((flags & PackageManager.GET_PERMISSIONS) == 0) {
                // 不主動覆蓋 GET_PERMISSIONS 版本；但 uid/label/installed 快取可共用 PackageInfo 的 applicationInfo。
            }
        }
        return info;
    }

    private static String packageBasicCacheKey(String packageName, int userId) {
        return userId + "|" + packageName;
    }

    private static int getPackageUidCached(PackageManagerHidden pm, String packageName, int userId) throws Exception {
        String key = packageBasicCacheKey(packageName, userId);
        Integer cached = sPackageUidCache.get(key);
        if (cached != null) {
            return cached;
        }
        PackageInfo info = getPackageInfoAsUserCached(pm, packageName, 0, userId);
        int uid = info.applicationInfo.uid;
        sPackageUidCache.put(key, uid);
        return uid;
    }

    private static String getPackageLabelCached(PackageManager pm, PackageManagerHidden pmHidden, String packageName, int userId) throws Exception {
        String key = packageBasicCacheKey(packageName, userId);
        String cached = sPackageLabelCache.get(key);
        if (cached != null) {
            return cached;
        }
        PackageInfo info = getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
        String label = removeSpaces(info.applicationInfo.loadLabel(pm).toString());
        sPackageLabelCache.put(key, label);
        if (info.applicationInfo != null) {
            sPackageUidCache.put(key, info.applicationInfo.uid);
        }
        return label;
    }

    /**
     * 判斷 op 是否為 runtime(dangerous)權限背書。透過 AppOpsManager.opToPermission(int) 反查權限名,
     * 再用 PackageManager 確認其 protectionLevel 是否為 DANGEROUS。
     * opToPermission 為長期存在的 @hide 靜態方法 (Android 9-16 穩定)。
     * 任何反射或查詢失敗一律回 false (不略過), 確保 fail-open 不弄丟還原。
     */
    @SuppressLint("ServiceCast")
    private static void appOpsScopeDetail(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManagerHidden packageManager = Refine.unsafeCast(PackageManagerUtil.getPackageManager(ctx).packageManager());
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            int packages = 0;
            int ops = 0;
            for (List<String> tokens : parseBracketGroups(args, 2)) {
                if (tokens.size() < 2) {
                    throw new IllegalArgumentException("invalid appOpsScopeDetail group; expected [PACKAGE OP OP ...]");
                }
                String packageName = tokens.get(0);
                packages++;
                try {
                    PackageInfo packageInfo = getPackageInfoAsUserCached(packageManager, packageName, 0, userId);
                    int uid = packageInfo.applicationInfo.uid;
                    for (int i = 1; i < tokens.size(); i++) {
                        int op = Integer.parseInt(tokens.get(i));
                        int packageMode = AppOpsCompat.getPackageModeRaw(appOpsManager, op, uid, packageName, getOpMode(appOpsManager, op, uid, packageName));
                        int uidMode = AppOpsCompat.getUidModeRaw(appOpsManager, op, uid, HiddenApiUtil::getPublicName);
                        int effectiveMode = getOpMode(appOpsManager, op, uid, packageName);
                        String note = classifyScopeNote(op, packageMode, uidMode, effectiveMode);
                        System.out.println("APPOPS_SCOPE package=" + sanitizeDiagValue(packageName)
                                + " op=" + op
                                + " name=" + sanitizeDiagValue(getPublicName(op))
                                + " package_mode=" + packageMode
                                + " uid_mode=" + uidMode
                                + " effective_mode=" + effectiveMode
                                + " note=" + note);
                        ops++;
                    }
                } catch (Exception e) {
                    System.out.println("APPOPS_SCOPE_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.out.println("APPOPS_SCOPE_DETAIL_OK packages=" + packages + " ops=" + ops);
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static String classifyScopeNote(int op, int packageMode, int uidMode, int effectiveMode) {
        if (uidMode == -999) return "UID_MODE_UNAVAILABLE";
        if (packageMode == uidMode) return "OK";
        if (uidMode == AppOpsManagerHidden.MODE_FOREGROUND || effectiveMode == AppOpsManagerHidden.MODE_FOREGROUND) return "FOREGROUND_OK";
        if (packageMode == AppOpsManagerHidden.MODE_ALLOWED && uidMode == AppOpsManagerHidden.MODE_IGNORED) return "ASK_EVERY_TIME_OK";
        return "SCOPE_MISMATCH_WARN";
    }

    private static void forceStopPackage(String[] args) {
        try {
            int userId = Integer.parseInt(args[1]);
            List<String> packages = collectPackageNames(args, 2);
            for (String packageName : packages) {
                if (packageName == null || packageName.isEmpty()) {
                    continue;
                }
                if (ActivityCompat.forceStopPackageNoThrow(packageName, userId)) {
                    System.out.println("FORCE_STOP_OK package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                    human(packageName, "備份前停止完成");
                } else {
                    System.out.println("FORCE_STOP_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                    human(packageName, "備份前停止失敗，已略過");
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }


    private static DaemonRunResult forceStopPackageBatchDaemonCommand(String[] args) {
        StringBuilder out = new StringBuilder();
        try {
            int userId = Integer.parseInt(args[1]);
            List<String> packages;
            if (args.length > 2 && "--stdin".equals(args[2])) {
                packages = new ArrayList<>();
                for (int i = 3; i < args.length; i++) {
                    String pkg = args[i] == null ? "" : args[i].trim();
                    if (!pkg.isEmpty() && !pkg.startsWith("#")) {
                        packages.add(pkg);
                    }
                }
            } else {
                packages = collectPackageNames(args, 2);
            }
            int failed = 0;
            for (String packageName : packages) {
                if (ActivityCompat.forceStopPackageNoThrow(packageName, userId)) {
                    out.append("FORCE_STOP_OK package=").append(sanitizeDiagValue(packageName)).append(" user=").append(userId).append('\n');
                } else {
                    out.append("FORCE_STOP_FAILED_SKIP package=").append(sanitizeDiagValue(packageName)).append(" user=").append(userId).append('\n');
                    failed++;
                }
            }
            if (packages.isEmpty()) {
                out.append("FORCE_STOP_EMPTY user=").append(userId).append('\n');
                return new DaemonRunResult(2, out.toString());
            }
            return new DaemonRunResult(failed == 0 ? 0 : 1, out.toString());
        } catch (Throwable e) {
            out.append("FORCE_STOP_DAEMON_FAILED exception=").append(e.getClass().getName())
                    .append(" message=").append(sanitizeDiagValue(e.getMessage())).append('\n');
            return new DaemonRunResult(1, out.toString());
        }
    }

    private static int forceStopPackageBatchCommand(String[] args) {
        try {
            int userId = Integer.parseInt(args[1]);
            List<String> packages;
            if (args.length > 2 && "--stdin".equals(args[2])) {
                packages = new ArrayList<>();
                byte[] data = readAllStdinBytes();
                String text = new String(data, java.nio.charset.StandardCharsets.UTF_8);
                for (String line : text.split("\\r?\\n")) {
                    String pkg = line.trim();
                    if (!pkg.isEmpty() && !pkg.startsWith("#")) {
                        packages.add(pkg);
                    }
                }
            } else {
                packages = collectPackageNames(args, 2);
            }
            int failed = 0;
            for (String packageName : packages) {
                if (ActivityCompat.forceStopPackageNoThrow(packageName, userId)) {
                    System.out.println("FORCE_STOP_OK package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                } else {
                    System.out.println("FORCE_STOP_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                    failed++;
                }
            }
            return failed == 0 ? 0 : 1;
        } catch (Exception e) {
            e.printStackTrace(System.err);
            return 1;
        }
    }

    private static void forceStopPackageBatch(String[] args) {
        System.exit(forceStopPackageBatchCommand(args));
    }

    public static void setDisplayPowerMode(String[] args) {
        try {
            int mode = Integer.parseInt(args[1]);
            long[] physicalDisplayIds;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                physicalDisplayIds = DisplayControlHidden.getPhysicalDisplayIds();
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                physicalDisplayIds = SurfaceControlHidden.getPhysicalDisplayIds();
            } else {
                physicalDisplayIds = new long[]{0L};
            }
            for (long id : physicalDisplayIds) {
                IBinder token;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    token = DisplayControlHidden.getPhysicalDisplayToken(id);
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    token = SurfaceControlHidden.getPhysicalDisplayToken(id);
                } else {
                    token = SurfaceControlHidden.getBuiltInDisplay((int) id);
                }
                SurfaceControlHidden.setDisplayPowerMode(token, mode);
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static String removeSpaces(String string) {
        return string.replaceAll("\\s", "");
    }

    /**
     * @see <a href="https://github.com/LSPosed/LSPosed/blob/df74d83eb03a44cc6ad268841ac2ada28d077c77/daemon/src/main/java/org/lsposed/lspd/service/LSPosedService.java#L69">LSPosedService.java#L69</a>
     */
    private static boolean isModernModules(ApplicationInfo info) {
        String[] apks;
        if (info.splitSourceDirs != null) {
            apks = Arrays.copyOf(info.splitSourceDirs, info.splitSourceDirs.length + 1);
            apks[info.splitSourceDirs.length] = info.sourceDir;
        } else apks = new String[]{info.sourceDir};
        for (var apk : apks) {
            try (var zip = new ZipFile(apk)) {
                if (zip.getEntry("META-INF/xposed/java_init.list") != null) {
                    return true;
                }
            } catch (IOException ignored) {
            }
        }
        return false;
    }

    private static List<String> collectPackageNames(String[] args, int start) {
        return flattenArgs(args, start);
    }

    private static int getOpMode(AppOpsManagerHidden appOpsManager, int op, int uid, String packageName) {
        if (op == AppOpsManagerHidden.OP_NONE) {
            return AppOpsManagerHidden.MODE_DEFAULT;
        }
        try {
            return appOpsManager.unsafeCheckOpRawNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        try {
            return appOpsManager.checkOpNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        return AppOpsManagerHidden.MODE_DEFAULT;
    }

    private static Object getDeviceIdleService() throws Exception {
        return HiddenApiServices.deviceIdle();
    }

    private static Set<String> getDeviceIdleWhitelist() {
        Set<String> result = new HashSet<>();
        try {
            Object service = getDeviceIdleService();
            // Compatibility / fallback handling.
            Object names = callRequired(service,
                    new CallSpec("getFullPowerWhitelist"),
                    new CallSpec("getFullPowerWhitelistExceptIdle")
            );
            if (names instanceof String[]) {
                for (String name : (String[]) names) {
                    if (name != null && !name.isEmpty()) result.add(name);
                }
                return result;
            }
        } catch (Throwable ignored) {
            // Compatibility / fallback handling.
        }
        return getDeviceIdleWhitelistViaShell();
    }

    // Compatibility / fallback handling.
    private static Set<String> getDeviceIdleWhitelistViaShell() {
        Set<String> result = new HashSet<>();
        String output = execShellCapture("dumpsys deviceidle whitelist");
        for (String line : output.split("\\r?\\n")) {
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.startsWith("Added:") || line.startsWith("Removed:")) {
                int colon = line.indexOf(':');
                if (colon >= 0 && colon + 1 < line.length()) {
                    String pkg = line.substring(colon + 1).trim();
                    if (pkg.contains(".")) result.add(pkg);
                }
                continue;
            }
            if (line.contains(",")) {
                String[] commaParts = line.split(",");
                for (String part : commaParts) {
                    String pkg = part.trim();
                    if (pkg.contains(".") && !pkg.matches("^[0-9]+$")) {
                        result.add(pkg);
                    }
                }
                continue;
            }
            String[] parts = line.split("\\s+");
            for (String part : parts) {
                String pkg = part.trim();
                if (pkg.contains(".")) result.add(pkg);
            }
        }
        return result;
    }

    private static String execShellCapture(String command) {
        StringBuilder output = new StringBuilder();
        try {
            Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", command});
            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append('\n');
                }
            }
            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))) {
                while (reader.readLine() != null) {
                }
            }
            process.waitFor();
        } catch (Throwable ignored) {
        }
        return output.toString();
    }

    private static Class<?> classForNameCached(String name) throws ClassNotFoundException {
        return HiddenApiReflection.classForNameCached(name);
    }

    private static Object callRequired(Object target, CallSpec... specs) throws Exception {
        Throwable last = null;
        for (CallSpec spec : specs) {
            try {
                return invokeFlexible(target, spec.methodName, spec.args);
            } catch (Throwable e) {
                last = e;
            }
        }
        if (last != null) {
            debugThrowable("callRequired signatures failed (" + describeSpecs(specs) + ")", last);
        }
        throw new IllegalStateException(last != null ? last.getMessage() : "no matching method");
    }

    private static Object invokeNoArg(Object target, String methodName) {
        try {
            return invokeFlexible(target, methodName);
        } catch (Throwable e) {
            debugThrowable("invokeNoArg " + methodName, e);
            return null;
        }
    }

    private static Object invokeFlexible(Object target, String methodName, Object... args) throws Exception {
        return HiddenApiReflection.invokeFlexible(target, methodName, args);
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static final class CallSpec {
        final String methodName;
        final Object[] args;

        CallSpec(String methodName, Object... args) {
            this.methodName = methodName;
            this.args = args;
        }
    }

    private static List<String> flattenArgs(String[] args, int start) {
        List<String> tokens = new ArrayList<>();
        for (int i = start; i < args.length; i++) {
            for (String token : args[i].trim().split("\\s+")) {
                if (!token.isEmpty()) {
                    tokens.add(token);
                }
            }
        }
        return tokens;
    }

    private static List<List<String>> parseBracketGroups(String[] args, int start) {
        List<List<String>> groups = new ArrayList<>();
        List<String> current = null;
        for (int i = start; i < args.length; i++) {
            for (String rawToken : args[i].trim().split("\\s+")) {
                if (rawToken.isEmpty()) {
                    continue;
                }
                boolean startsGroup = rawToken.startsWith("[");
                boolean endsGroup = rawToken.endsWith("]");
                if (startsGroup) {
                    if (current != null) {
                        throw new IllegalArgumentException("nested groups are not supported: " + rawToken);
                    }
                    current = new ArrayList<>();
                    rawToken = rawToken.substring(1);
                }
                if (current == null) {
                    throw new IllegalArgumentException("missing group start marker [: " + rawToken);
                }
                if (endsGroup) {
                    rawToken = rawToken.substring(0, rawToken.length() - 1);
                }
                if (!rawToken.isEmpty()) {
                    current.add(rawToken);
                }
                if (endsGroup) {
                    if (current.isEmpty()) {
                        throw new IllegalArgumentException("empty group");
                    }
                    groups.add(current);
                    current = null;
                }
            }
        }
        if (current != null) {
            throw new IllegalArgumentException("missing group end marker ]");
        }
        return groups;
    }
}
