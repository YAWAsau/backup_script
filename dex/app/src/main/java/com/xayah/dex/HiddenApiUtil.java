package com.xayah.dex;

import android.annotation.SuppressLint;
import android.app.PendingIntent;
import android.app.AppOpsManagerHidden;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.content.pm.ActivityInfo;
import android.content.pm.ActivityInfoHidden;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.content.pm.PermissionInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.UserHandle;
import android.os.UserHandleHidden;
import android.net.Uri;
import android.view.SurfaceControlHidden;

import com.android.server.display.DisplayControlHidden;

import com.xayah.dex.compat.ActivityCompat;
import com.xayah.dex.compat.AppOpsCompat;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;
import com.xayah.dex.compat.PermissionCompat;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.text.Collator;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.zip.ZipFile;

import dev.rikka.tools.refine.Refine;

public class HiddenApiUtil {
    private static final String VERSION = "v2.4.38-notify-no-actions-zero-ui-buildfix build=v24.20.14-7.66-34-dex-notify-no-actions-zero-ui-buildfix-20260705";
    private static boolean sInstallSessionBatchMode = false;
    private static boolean sAppOpsResetUnsupportedReported = false;
    /**
     * PermissionInfo.protectionLevel 是裝置/系統層級固定資料；同一個 JVM 批量處理多個 package 時，
     * CAMERA / RECORD_AUDIO / LOCATION / READ_MEDIA_* 等常見權限會跨 package 重複查詢。
     * 這裡只快取 protection 與 protectionFlags，避免 printRuntimePermissions 逐 package 重複 binder getPermissionInfo。
     */
    private static final Map<String, int[]> sPermissionProtectionCache = new HashMap<>();
    /**
     * 單 JVM 批量還原/驗證期間的輕量快取。只快取系統層級固定資料或同一輪已讀 package metadata；
     * 不跨 JVM、不落檔，避免一致性風險。
     */
    private static final Map<Integer, String> sOpToPermissionCache = new HashMap<>();
    private static final Map<Integer, Boolean> sRuntimePermissionBackedOpCache = new HashMap<>();
    private static final Map<String, Integer> sBatteryOpCache = new HashMap<>();
    private static final Map<String, PackageInfo> sPackageInfoCache = new HashMap<>();
    private static final Map<String, Integer> sPackageUidCache = new HashMap<>();
    private static final Map<String, String> sPackageLabelCache = new HashMap<>();
    private static final Map<String, List<Object>> sNotificationChannelsCache = new HashMap<>();
    private static final Map<String, List<Object>> sNotificationGroupsCache = new HashMap<>();

    private static final class InstallSessionExit extends Error {
        final int code;
        InstallSessionExit(int code) {
            super("installSessionExit=" + code);
            this.code = code;
        }
    }

    private static void installSessionExit(int code) {
        if (sInstallSessionBatchMode) {
            throw new InstallSessionExit(code);
        }
        System.exit(code);
    }
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

    /**
     * 將 grant/revoke 例外分類, 區分「合法不可授予」(預期噪音) 與真正失敗。
     * 跨 Android 9-16, grantRuntimePermission 對下列情況丟 SecurityException 屬正常:
     *   - 套件未在 manifest 宣告該權限 ("has not requested")
     *   - 該權限非 runtime/development 類型 ("not a changeable permission type")
     * 這些情況下 stdout 的「已略過」是正確行為, 此處僅在 DEBUG 時標記類別以免淹沒真實錯誤。
     */
    private static String classifyPermFailure(String action, String pkg, String perm, Throwable t) {
        String msg = (t != null && t.getMessage() != null) ? t.getMessage().toLowerCase(Locale.ROOT) : "";
        String kind;
        if (msg.contains("has not requested") || msg.contains("not requested")) {
            kind = "預期(套件未宣告此權限)";
        } else if (msg.contains("not a changeable") || msg.contains("not a runtime")) {
            kind = "預期(非可變更權限類型)";
        } else if (msg.contains("system fixed") || msg.contains("policy fixed") || msg.contains("system-fixed")) {
            kind = "預期(權限被系統/政策鎖定)";
        } else {
            kind = "真實失敗";
        }
        return action + " " + kind + ": " + pkg + " " + perm;
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
        System.out.println();
        System.out.println("  getPackageUid USER_ID PACKAGE PACKAGE PACKAGE ...  取得套件 UID");
        System.out.println();
        System.out.println("  getPackageLabel USER_ID PACKAGE PACKAGE PACKAGE ...  取得應用名稱");
        System.out.println();
        System.out.println("  getPackageArchiveInfo APK_FILE  讀取 APK 檔案資訊");
        System.out.println();
        System.out.println("  getInstaller USER_ID PACKAGE PACKAGE PACKAGE ...  取得安裝來源/installer package");
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println("  installSessionBatch USER_ID [OPTIONS] --pkg PACKAGE APK_DIR|APK_FILE [APK_FILE ...] [--pkg PACKAGE APK_DIR|APK_FILE ...]  單次 JVM 批量執行 PackageInstaller session 安裝");
        System.out.println("  precheckInstallApks PACKAGE APK_FILE [APK_FILE ...]  只做 APK/split APK 安裝前預檢，不建立 session");
        System.out.println();
        System.out.println("  getInstallSourceInfo USER_ID PACKAGE PACKAGE PACKAGE ...  診斷安裝來源、update owner、版本、簽章、split、Play 環境");
        System.out.println();
        System.out.println("  diagnosePlayRestore USER_ID PACKAGE PACKAGE PACKAGE ...  輸出恢復後可能跳 Play 的風險與建議");
        System.out.println();
        System.out.println("  compareInstallDiagnostics USER_ID [PACKAGE VERSION_CODE SIGNING_SHA256 SPLIT_COUNT] ...  比對備份與恢復後版本/簽章/split");
        System.out.println();
        System.out.println("  getInstalledPackagesAsUser USER_ID FILTER_FLAG(user|system|xposed) FORMAT(label|pkgName|flag)  取得安裝清單");
        System.out.println();
        System.out.println("  getRuntimePermissions USER_ID PACKAGE PACKAGE PACKAGE ...  取得 Runtime 權限、權限 flags 與特殊 AppOps");
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println("  restoreAppStateBatch USER_ID --stdin  單次 JVM 批量還原權限、安裝來源、通知、電池/背景設定");
        System.out.println("  verifyAppStateBatch USER_ID --stdin  單次 JVM 批量讀回安裝完整性、權限、通知、電池/背景驗證資料");
        System.out.println();
        System.out.println("  forceStopPackage USER_ID PACKAGE PACKAGE PACKAGE ...  透過 ActivityManager hidden API 批量停止套件，用於備份前 soft freeze");
        System.out.println("  forceStopPackageBatch USER_ID --stdin  從 stdin 批量讀取套件名稱並停止");
        System.out.println();
        System.out.println("  fixRuntimeAppOpsAllow USER_ID [PACKAGE PERM_NAME PERM_NAME ...] ...  僅修正已授權 runtime 權限的 AppOps allow/default 狀態");
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println();
        System.out.println("  appOpsResetBatch USER_ID --stdin|PACKAGE...  從 stdin/參數批量 package-scoped AppOps reset");
        System.out.println();
        System.out.println("  appOpsScopeDetail USER_ID [PACKAGE OP OP ...] ...  單次 JVM 讀取 package/uid/effective AppOps scope 診斷");
        System.out.println();
        System.out.println("  setDisplayPowerMode MODE(POWER_MODE_OFF: 0, POWER_MODE_NORMAL: 2)  設定螢幕電源模式");
        System.out.println();
        System.out.println("  getNotificationSettings USER_ID PACKAGE PACKAGE PACKAGE ...  取得通知總開關、通知分類、圓點、對話相關設定");
        System.out.println();
        System.out.println();
        System.out.println("  getBatterySettings USER_ID PACKAGE PACKAGE PACKAGE ...  批量取得背景使用/AppOps 與 Doze 白名單");
        System.out.println();
    }

    private static void printVersion() {
        System.out.println(VERSION);
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "getPackageUid":
                getPackageUid(args);
                break;
            case "getPackageLabel":
                getPackageLabel(args);
                break;
            case "getPackageArchiveInfo":
                getPackageArchiveInfo(args);
                break;
            case "getInstaller":
                getInstaller(args);
                break;
            case "installSessionBatch":
                installSessionBatch(args);
                break;
            case "precheckInstallApks":
                precheckInstallApks(args);
                break;
            case "getInstallSourceInfo":
                getInstallSourceInfo(args, false);
                break;
            case "diagnosePlayRestore":
                getInstallSourceInfo(args, true);
                break;
            case "compareInstallDiagnostics":
                compareInstallDiagnostics(args);
                break;
            case "getInstalledPackagesAsUser":
                getInstalledPackagesAsUser(args);
                break;
            case "getRuntimePermissions":
                getRuntimePermissions(args);
                break;
            case "getNotificationSettings":
                getNotificationSettings(args);
                break;
            case "getBatterySettings":
                getBatterySettings(args);
                break;
            case "forceStopPackage":
                forceStopPackage(args);
                break;
            case "forceStopPackageBatch":
                forceStopPackageBatch(args);
                break;
            case "restoreAppStateBatch":
                restoreAppStateBatch(args);
                break;
            case "verifyAppStateBatch":
                verifyAppStateBatch(args);
                break;
            case "fixRuntimeAppOpsAllow":
                fixRuntimeAppOpsAllow(args);
                break;
            case "appOpsResetBatch":
                appOpsResetBatch(args);
                break;
            case "appOpsScopeDetail":
                appOpsScopeDetail(args);
                break;
            case "setDisplayPowerMode":
                setDisplayPowerMode(args);
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
            onCommand(cmd, args);
        } else {
            onHelp();
        }
        System.exit(0);
    }

    private static void getPackageUid(String[] args) {
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
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
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
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            String file = args[1];
            PackageInfo packageInfo = pm.getPackageArchiveInfo(file, 0);
            if (packageInfo != null && packageInfo.applicationInfo != null) {
                packageInfo.applicationInfo.sourceDir = file;
                packageInfo.applicationInfo.publicSourceDir = file;
                System.out.println(removeSpaces(packageInfo.applicationInfo.loadLabel(pm).toString()) + " " + packageInfo.packageName);
            } else {
                throw new PackageManager.NameNotFoundException("無法解析 APK 套件資訊!");
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void installSessionInternal(String[] args) {
        PackageInstaller.Session session = null;
        int sessionId = -1;
        String packageName = null;
        InstallSessionOptions options = null;
        try {
            if (args == null || args.length < 4) {
                throw new IllegalArgumentException("installSessionBatch 內部安裝參數錯誤: USER_ID PACKAGE APK_FILE [APK_FILE ...]");
            }
            Context ctx = HiddenApiHelper.getContext();
            int userId = Integer.parseInt(args[1]);
            // HiddenApiHelper 取到的通常是 system context，packageName 會是 android。
            // PackageInstaller.createSession 會檢查 installerPackageName 是否屬於 callingUid；
            // 在 uidexec 切到 Play UID 後，如果仍用 system context，就會變成
            // "Package android does not belong to 10278"。
            // 所以內部 session 安裝必須改用 com.android.vending package context 取得 PackageInstaller，
            // 讓 createSession 的 installerPackageName 跟 callingUid 對上。
            Context installerCtx = createPackageContextForUser(ctx, "com.android.vending", userId);
            PackageManager realPm = installerCtx.getPackageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            packageName = args[2];
            options = parseInstallSessionOptions(args, 3);
            sHumanLog = options.humanLog;
            List<String> apkPaths = options.apkPaths;
            if (apkPaths.isEmpty()) {
                throw new IllegalArgumentException("installSessionBatch 內部安裝缺少 APK_FILE");
            }
            apkPaths = dedupeFilePaths(apkPaths);
            System.out.println(packageName + " INSTALL_SESSION options " + options.toSummaryString());
            human(packageName, "安裝方式: Play UID PackageInstaller session；安裝來源目標=" + options.installerPackageName + "；來源類型=" + options.packageSource);

            long totalBytes = 0L;
            // 先檢查 APK 檔案對目前 UID 可讀。若 Play UID 讀不到，這裡會直接拋錯，
            // 避免 PackageInstaller session 建到一半才失敗。
            for (String path : apkPaths) {
                File f = new File(path);
                if (!f.isFile()) {
                    throw new IllegalArgumentException("APK 不存在或不是檔案: " + path);
                }
                if (!f.getName().toLowerCase(Locale.ROOT).endsWith(".apk")) {
                    System.out.println(packageName + " INSTALL_SESSION warnNonApkFile " + sanitizeDiagValue(f.getName()));
                }
                totalBytes += Math.max(0L, f.length());
                try (InputStream ignored = new FileInputStream(f)) {
                    // readable
                }
            }
            System.out.println(packageName + " INSTALL_SESSION apkCount " + apkPaths.size());
            System.out.println(packageName + " INSTALL_SESSION totalBytes " + totalBytes);
            human(packageName, "APK 檢查完成: 共 " + apkPaths.size() + " 個檔案，總大小 " + totalBytes + " bytes");
            printArchivePrecheck(realPm, packageName, apkPaths);
            PackageInstaller packageInstaller = realPm.getPackageInstaller();
            System.out.println(packageName + " INSTALL_SESSION installerContext " + installerCtx.getPackageName());
            PackageInstaller.SessionParams params =
                    new PackageInstaller.SessionParams(options.mode);
            params.setAppPackageName(packageName);
            applyInstallSessionOptions(params, packageName, totalBytes, options);

            sessionId = packageInstaller.createSession(params);
            System.out.println(packageName + " INSTALL_SESSION sessionId " + sessionId);
            human(packageName, "已建立安裝 session: " + sessionId);
            session = packageInstaller.openSession(sessionId);

            byte[] buffer = new byte[4 * 1024 * 1024];
            Set<String> sessionNames = new HashSet<>();
            for (String path : apkPaths) {
                File file = new File(path);
                String name = uniqueSessionFileName(file.getName(), sessionNames);
                long size = file.length();
                try (InputStream in = new FileInputStream(file);
                     OutputStream out = session.openWrite(name, 0, size > 0 ? size : -1)) {
                    int read;
                    while ((read = in.read(buffer)) != -1) {
                        out.write(buffer, 0, read);
                    }
                    session.fsync(out);
                }
                System.out.println(packageName + " INSTALL_SESSION wrote " + name + " " + size);
            }

            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            // PackageInstaller.Session.commit() 在新版 Android 需要 mutable status receiver，
            // 但 Android 14/U+ 又禁止 targetSdk 34+ 建立「mutable + implicit Intent」的 PendingIntent。
            // 這裡保留 Play package 限定，並在可用時加 FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT，
            // 目的只是拿到 commit status receiver；真正安裝結果仍以 getInstallSourceInfo 驗證。
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
            System.out.println(packageName + " INSTALL_SESSION statusReceiver flags " + flags);
            session.commit(pendingIntent.getIntentSender());
            session.close();
            session = null;

            System.out.println(packageName + " INSTALL_SESSION committed " + sessionId);
            human(packageName, "已提交安裝 session，等待系統完成安裝");

            // commit 是非同步。這裡只做短輪詢，方便終端測試；真正結果仍建議用
            // getInstallSourceInfo / dumpsys package / 設定頁驗證。
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
                        human(packageName, "安裝完成: 已找到套件，versionCode=" + getLongVersionCodeCompat(info));
                        try {
                            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
                            Set<String> idleWhitelist = getDeviceIdleWhitelist();
                            GooglePackageSnapshot playStoreSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.android.vending");
                            GooglePackageSnapshot playServicesSnapshot = getGooglePackageSnapshot(realPm, pmHidden, appOpsManager, idleWhitelist, userId, "com.google.android.gms");
                            printInstallSourceDiagnostics(realPm, pmHidden, userId, packageName, false, playStoreSnapshot, playServicesSnapshot);
                        } catch (Throwable diagError) {
                            debugThrowable("installSessionBatch post-verify getInstallSourceInfo " + packageName, diagError);
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
                human(packageName, "安裝提交後逾時仍找不到套件，請查看失敗原因與 PackageInstaller/logcat");
                try {
                    printSessionInfoDiagnostics(packageInstaller, sessionId, packageName);
                } catch (Throwable sessionInfoError) {
                    debugThrowable("installSessionBatch sessionInfo after wait " + packageName, sessionInfoError);
                }
                printInstallFailureTranslation(packageName, null, "packageNotFoundAfterWait");
            }
            installSessionExit(0);
        } catch (Exception e) {
            if (session != null) {
                try {
                    session.abandon();
                } catch (Throwable ignored) {
                }
                try {
                    session.close();
                } catch (Throwable ignored) {
                }
            }
            if (packageName == null) {
                packageName = "unknown";
            }
            System.out.println(packageName + " INSTALL_SESSION failed " + e.getClass().getName()
                    + " " + sanitizeDiagValue(e.getMessage()));
            human(packageName, "安裝流程失敗: " + e.getClass().getSimpleName() + " " + sanitizeDiagValue(e.getMessage()));
            printInstallFailureTranslation(packageName, e, e.getMessage());
            e.printStackTrace(System.err);
            installSessionExit(1);
        }
    }

    private static void precheckInstallApks(String[] args) {
        try {
            if (args == null || args.length < 3) {
                throw new IllegalArgumentException("precheckInstallApks 用法: precheckInstallApks PACKAGE APK_FILE [APK_FILE ...]");
            }
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            String packageName = args[1];
            List<String> apkPaths = new ArrayList<>();
            for (int i = 2; i < args.length; i++) apkPaths.add(args[i]);
            apkPaths = expandApkInputs(apkPaths);
            InstallPrecheckResult result = printArchivePrecheck(pm, packageName, apkPaths);
            System.out.println(packageName + " INSTALL_PRECHECK result " + (result.ok ? "ok" : "failed")
                    + " reason=" + sanitizeDiagValue(result.reason)
                    + " apkCount=" + result.apkCount
                    + " totalBytes=" + result.totalBytes);
            System.exit(result.ok ? 0 : 1);
        } catch (Exception e) {
            String pkg = args != null && args.length > 1 ? args[1] : "unknown";
            System.out.println(pkg + " INSTALL_PRECHECK failed exception=" + e.getClass().getName() + " message=" + sanitizeDiagValue(e.getMessage()));
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void installSessionBatch(String[] args) {
        int ok = 0;
        int failed = 0;
        boolean oldBatchMode = sInstallSessionBatchMode;
        try {
            if (args == null || args.length < 5) {
                throw new IllegalArgumentException("installSessionBatch 用法: installSessionBatch USER_ID [OPTIONS] --pkg PACKAGE APK_DIR|APK_FILE [APK_FILE ...] [--pkg PACKAGE APK_DIR|APK_FILE ...]");
            }
            String userId = args[1];
            List<String> sharedOptions = new ArrayList<>();
            List<BatchInstallItem> items = new ArrayList<>();
            BatchInstallItem current = null;
            for (int i = 2; i < args.length; i++) {
                String a = args[i];
                if ("--pkg".equals(a) || "--package".equals(a)) {
                    if (i + 1 >= args.length) throw new IllegalArgumentException("--pkg 後缺少 PACKAGE");
                    current = new BatchInstallItem();
                    current.packageName = args[++i];
                    items.add(current);
                    continue;
                }
                if (current == null) {
                    sharedOptions.add(a);
                } else {
                    current.inputs.add(a);
                }
            }
            if (items.isEmpty()) throw new IllegalArgumentException("installSessionBatch 缺少 --pkg 分組");
            System.out.println("INSTALL_BATCH_BEGIN count=" + items.size() + " userId=" + sanitizeDiagValue(userId));
            human("batch", "開始批量 Play UID PackageInstaller session，共 " + items.size() + " 個套件");
            sInstallSessionBatchMode = true;
            for (BatchInstallItem item : items) {
                long itemStart = System.currentTimeMillis();
                try {
                    List<String> apkPaths = expandApkInputs(item.inputs);
                    if (apkPaths.isEmpty()) throw new IllegalArgumentException("APK input empty for " + item.packageName);
                    System.out.println("INSTALL_BATCH_ITEM_BEGIN pkg=" + sanitizeDiagValue(item.packageName) + " apkCount=" + apkPaths.size());
                    List<String> one = new ArrayList<>();
                    one.add("installSessionInternal");
                    one.add(userId);
                    one.add(item.packageName);
                    one.addAll(sharedOptions);
                    one.addAll(apkPaths);
                    try {
                        installSessionInternal(one.toArray(new String[0]));
                    } catch (InstallSessionExit exit) {
                        if (exit.code != 0) throw exit;
                    }
                    ok++;
                    System.out.println("INSTALL_BATCH_ITEM_END pkg=" + sanitizeDiagValue(item.packageName)
                            + " result=ok elapsedMs=" + (System.currentTimeMillis() - itemStart));
                } catch (Throwable t) {
                    failed++;
                    String raw = t instanceof InstallSessionExit ? ("exitCode=" + ((InstallSessionExit) t).code) : String.valueOf(t.getMessage());
                    System.out.println("INSTALL_BATCH_ITEM_END pkg=" + sanitizeDiagValue(item.packageName)
                            + " result=failed elapsedMs=" + (System.currentTimeMillis() - itemStart)
                            + " error=" + sanitizeDiagValue(raw));
                    printInstallFailureTranslation(item.packageName, t, raw);
                }
            }
            System.out.println("INSTALL_BATCH_END ok=" + ok + " failed=" + failed + " total=" + items.size());
            sInstallSessionBatchMode = oldBatchMode;
            System.exit(failed == 0 ? 0 : 1);
        } catch (Exception e) {
            System.out.println("INSTALL_BATCH_FAILED exception=" + e.getClass().getName() + " message=" + sanitizeDiagValue(e.getMessage())
                    + " ok=" + ok + " failed=" + failed);
            e.printStackTrace(System.err);
            sInstallSessionBatchMode = oldBatchMode;
            System.exit(1);
        }
    }

    private static final class BatchInstallItem {
        String packageName;
        List<String> inputs = new ArrayList<>();
    }

    private static List<String> expandApkInputs(List<String> inputs) {
        List<String> out = new ArrayList<>();
        if (inputs == null) return out;
        for (String input : inputs) {
            if (input == null || input.trim().isEmpty()) continue;
            File f = new File(input);
            if (f.isDirectory()) {
                File[] files = f.listFiles();
                if (files != null) {
                    Arrays.sort(files, new Comparator<File>() {
                        @Override public int compare(File a, File b) {
                            String an = a.getName();
                            String bn = b.getName();
                            boolean ab = an.equals("base.apk");
                            boolean bb = bn.equals("base.apk");
                            if (ab != bb) return ab ? -1 : 1;
                            return an.compareTo(bn);
                        }
                    });
                    for (File child : files) {
                        if (child.isFile() && child.getName().toLowerCase(Locale.ROOT).endsWith(".apk")) {
                            out.add(child.getAbsolutePath());
                        }
                    }
                }
            } else {
                out.add(input);
            }
        }
        return dedupeFilePaths(out);
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

    private static String humanizePermissionFailure(String action, Throwable e) {
        String base = humanizeException(e);
        String msg = e == null ? "" : String.valueOf(e.getMessage());
        if (msg.contains("requested permission") || msg.contains("not a changeable permission")) {
            return "此權限不是可直接變更的 runtime permission；" + base;
        }
        if (msg.contains("does not request") || msg.contains("has not requested")) {
            return "目標 app manifest 沒有申請此權限；" + base;
        }
        if (msg.contains("fixed") || msg.contains("policy")) {
            return "權限被 policy/fixed flag 固定，需先清除 flags；" + base;
        }
        return base;
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

    private static final class InstallPrecheckResult {
        boolean ok = true;
        String reason = "ok";
        int apkCount = 0;
        int readableArchives = 0;
        long totalBytes = 0L;
        boolean hasBase = false;
        void fail(String r) {
            if (ok) reason = r;
            ok = false;
        }
    }

    private static InstallPrecheckResult printArchivePrecheck(PackageManager pm, String expectedPackageName, List<String> apkPaths) {
        InstallPrecheckResult result = new InstallPrecheckResult();
        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            flags |= PackageManager.GET_SIGNING_CERTIFICATES;
        } else {
            flags |= PackageManager.GET_SIGNATURES;
        }
        Set<String> packages = new HashSet<>();
        Set<String> versions = new HashSet<>();
        Set<String> signatures = new HashSet<>();
        Set<String> splitNames = new HashSet<>();
        Set<String> duplicateSplits = new HashSet<>();
        if (apkPaths == null || apkPaths.isEmpty()) {
            result.fail("no_apk");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=no_apk");
            return result;
        }
        for (String path : apkPaths) {
            File file = new File(path);
            result.apkCount++;
            result.totalBytes += Math.max(0L, file.length());
            try {
                if (!file.isFile()) {
                    result.fail("not_file");
                    System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED file=" + sanitizeDiagValue(file.getName()) + " reason=not_file");
                    continue;
                }
                try (InputStream ignored = new FileInputStream(file)) {
                    // readable by current UID
                }
                PackageInfo info = pm.getPackageArchiveInfo(path, flags);
                boolean looksLikeSplit = isLikelySplitApk(file);
                if (info == null) {
                    if (looksLikeSplit && apkZipBasicReadable(file)) {
                        // Some ROMs/Android releases return null for standalone config splits even though
                        // PackageInstaller can stream/install them successfully. Treat these as a soft
                        // precheck pass and leave final validation to INSTALL_COMPARE after commit.
                        result.readableArchives++;
                        String splitName = guessSplitNameFromFile(file);
                        if (splitName == null || splitName.isEmpty()) splitName = sanitizeDiagValue(file.getName());
                        if (!splitNames.add(splitName)) {
                            duplicateSplits.add(splitName);
                        }
                        System.out.println(expectedPackageName + " INSTALL_PRECHECK_SPLIT_BASIC_OK file="
                                + sanitizeDiagValue(file.getName())
                                + " split=" + sanitizeDiagValue(splitName)
                                + " bytes=" + file.length());
                        continue;
                    }
                    result.fail("archive_unreadable");
                    System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED file=" + sanitizeDiagValue(file.getName()) + " reason=archive_unreadable");
                    continue;
                }
                result.readableArchives++;
                String archivePackage = sanitizeDiagValue(info.packageName);
                String versionCode = String.valueOf(getLongVersionCodeCompat(info));
                String signing = sanitizeDiagValue(getSigningSha256(info));
                String splitName = getArchiveSplitName(info);
                if (splitName == null || splitName.isEmpty() || file.getName().equals("base.apk")) {
                    result.hasBase = true;
                    splitName = "base";
                } else if (!splitNames.add(splitName)) {
                    duplicateSplits.add(splitName);
                }
                packages.add(archivePackage);
                versions.add(versionCode);
                signatures.add(signing);
                System.out.println(expectedPackageName + " INSTALL_SESSION archive "
                        + sanitizeDiagValue(file.getName())
                        + " package=" + archivePackage
                        + " versionCode=" + versionCode
                        + " signingSha256=" + signing
                        + " split=" + sanitizeDiagValue(splitName)
                        + " bytes=" + file.length());
                if (info.packageName != null && !expectedPackageName.equals(info.packageName)) {
                    result.fail("package_mismatch");
                    System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED file="
                            + sanitizeDiagValue(file.getName()) + " reason=package_mismatch actual=" + archivePackage);
                }
            } catch (Throwable e) {
                result.fail("read_failed");
                debugThrowable("printArchivePrecheck " + path, e);
                System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED file="
                        + sanitizeDiagValue(file.getName()) + " reason=read_failed message=" + sanitizeDiagValue(e.getMessage()));
            }
        }
        if (result.readableArchives <= 0) {
            result.fail("no_readable_archive");
        }
        if (packages.size() > 1) {
            result.fail("mixed_packages");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=mixed_packages count=" + packages.size());
        }
        if (versions.size() > 1) {
            result.fail("mixed_version_codes");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=mixed_version_codes count=" + versions.size());
        }
        if (signatures.size() > 1) {
            result.fail("mixed_signatures");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=mixed_signatures count=" + signatures.size());
        }
        if (!duplicateSplits.isEmpty()) {
            result.fail("duplicate_split");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=duplicate_split names=" + sanitizeDiagValue(String.valueOf(duplicateSplits)));
        }
        if (!result.hasBase) {
            result.fail("missing_base");
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_FAILED reason=missing_base");
        }
        if (result.ok) {
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_OK apkCount=" + result.apkCount
                    + " readable=" + result.readableArchives
                    + " totalBytes=" + result.totalBytes
                    + " packages=" + packages.size()
                    + " versions=" + versions.size()
                    + " signatures=" + signatures.size());
        } else {
            System.out.println(expectedPackageName + " INSTALL_PRECHECK_SUMMARY result=failed reason=" + sanitizeDiagValue(result.reason)
                    + " apkCount=" + result.apkCount
                    + " readable=" + result.readableArchives
                    + " totalBytes=" + result.totalBytes);
        }
        return result;
    }

    private static boolean isLikelySplitApk(File file) {
        if (file == null) return false;
        String name = file.getName();
        if (name == null) return false;
        return name.startsWith("split_") || name.startsWith("config.") || name.contains("split_config") || (!"base.apk".equals(name) && name.endsWith(".apk"));
    }

    private static String guessSplitNameFromFile(File file) {
        if (file == null) return "";
        String name = file.getName();
        if (name == null) return "";
        if (name.endsWith(".apk")) name = name.substring(0, name.length() - 4);
        if (name.startsWith("split_")) name = name.substring("split_".length());
        return name;
    }

    private static boolean apkZipBasicReadable(File file) {
        if (file == null || !file.isFile() || file.length() <= 0L) return false;
        try (ZipFile zip = new ZipFile(file)) {
            return zip.getEntry("AndroidManifest.xml") != null;
        } catch (Throwable e) {
            debugThrowable("apkZipBasicReadable " + file, e);
            return false;
        }
    }

    private static String getArchiveSplitName(PackageInfo info) {
        if (info == null || info.applicationInfo == null) return "";
        try {
            java.lang.reflect.Field f = ApplicationInfo.class.getField("splitName");
            Object v = f.get(info.applicationInfo);
            return v == null ? "" : String.valueOf(v);
        } catch (Throwable ignored) {
            return "";
        }
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

    private static void getInstaller(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            int userId = Integer.parseInt(args[1]);
            for (String packageName : collectPackageNames(args, 2)) {
                try {
                    // 先確認指定 user 下確實有這個 package，避免輸出跨 user 的殘留/不存在狀態。
                    getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                    String installer = realPm.getInstallerPackageName(packageName);
                    System.out.println(packageName + " INSTALLER " + formatNullableToken(installer));
                } catch (Exception e) {
                    System.out.println("INSTALLER_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static String formatNullableToken(String value) {
        return value == null || value.isEmpty() ? "null" : value;
    }

    private static String parseNullableToken(String value) {
        if (value == null) {
            return null;
        }
        String v = value.trim();
        if (v.isEmpty()
                || "null".equalsIgnoreCase(v)
                || "none".equalsIgnoreCase(v)
                || "-".equals(v)) {
            return null;
        }
        return v;
    }

    private static void getInstallSourceInfo(String[] args, boolean diagnose) {
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
                    printInstallSourceDiagnostics(realPm, pmHidden, userId, packageName, diagnose, playStoreSnapshot, playServicesSnapshot);
                } catch (Exception e) {
                    System.out.println("INSTALL_SOURCE_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                    human(packageName, "讀取安裝來源失敗: " + humanizeException(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void compareInstallDiagnostics(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            int userId = Integer.parseInt(args[1]);
            for (List<String> tokens : parseBracketGroups(args, 2)) {
                try {
                    if (tokens.size() < 4) {
                        throw new IllegalArgumentException("compareInstallDiagnostics 需要 PACKAGE VERSION_CODE SIGNING_SHA256 SPLIT_COUNT");
                    }
                    String packageName = tokens.get(0);
                    String backupVersionCode = tokens.get(1);
                    String backupSigningSha256 = tokens.get(2);
                    String backupSplitCount = tokens.get(3);
                    printInstallDiagnosticCompare(realPm, pmHidden, userId, packageName,
                            backupVersionCode, backupSigningSha256, backupSplitCount);
                } catch (Exception e) {
                    System.out.println("INSTALL_COMPARE_FAILED_SKIP package=" + sanitizeDiagValue(tokens.isEmpty() ? "unknown" : tokens.get(0)) + " reason=" + failureReason(e));
                    human((tokens.isEmpty() ? "unknown" : tokens.get(0)), "安裝診斷比對失敗: " + humanizeException(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void printInstallDiagnosticCompare(
            PackageManager realPm,
            PackageManagerHidden pmHidden,
            int userId,
            String packageName,
            String backupVersionCode,
            String backupSigningSha256,
            String backupSplitCount
    ) throws Exception {
        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            flags |= PackageManager.GET_SIGNING_CERTIFICATES;
        } else {
            flags |= PackageManager.GET_SIGNATURES;
        }
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, flags, userId);
        String currentVersionCode = String.valueOf(getLongVersionCodeCompat(packageInfo));
        String currentSigningSha256 = getSigningSha256(packageInfo);
        String currentSplitCount = String.valueOf(packageInfo.splitNames == null ? 0 : packageInfo.splitNames.length);

        printInstallCompare(packageName, "versionCode", backupVersionCode, currentVersionCode);
        printInstallCompare(packageName, "signingSha256", backupSigningSha256, currentSigningSha256);
        printInstallCompare(packageName, "splitCount", backupSplitCount, currentSplitCount);

        if (!safeEquals(backupVersionCode, currentVersionCode)) {
            printInstallRisk(packageName, "VERSION_CHANGED", "CHECK_RESTORED_APK_OR_UPDATE_FROM_PLAY");
        }
        if (!safeEquals(normalizeDiagCompareValue(backupSigningSha256), normalizeDiagCompareValue(currentSigningSha256))) {
            printInstallRisk(packageName, "SIGNATURE_CHANGED", "REINSTALL_CORRECT_SIGNED_APK");
        }
        if (!safeEquals(backupSplitCount, currentSplitCount)) {
            printInstallRisk(packageName, "SPLIT_COUNT_CHANGED", "RESTORE_COMPLETE_BASE_AND_SPLIT_APKS");
        }
    }

    private static void printInstallSourceDiagnostics(
            PackageManager realPm,
            PackageManagerHidden pmHidden,
            int userId,
            String packageName,
            boolean diagnose,
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

        if (diagnose) {
            printPlayRestoreRisks(packageName, installer, source.updateOwnerPackageName, versionCode, signingSha256,
                    splitCount, playStore.state, playServices.state);
        }
    }

    private static void printPlayRestoreRisks(
            String packageName,
            String installer,
            String updateOwner,
            long versionCode,
            String signingSha256,
            int splitCount,
            String playStoreState,
            String playServicesState
    ) {
        if (installer == null || installer.isEmpty()) {
            printInstallRisk(packageName, "INSTALLER_NULL", "SET_INSTALLER_IF_PLAY_APP");
        } else if (!"com.android.vending".equals(installer)) {
            printInstallRisk(packageName, "INSTALLER_NOT_PLAY", "SET_INSTALLER_COM_ANDROID_VENDING_IF_NEEDED");
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                && "com.android.vending".equals(updateOwner)) {
            printInstallRisk(packageName, "UPDATE_OWNER_PLAY_API34_PLUS", "USE_PLAY_UPDATE_OR_REINSTALL_WITH_CORRECT_SESSION");
        }
        if (versionCode <= 0) {
            printInstallRisk(packageName, "VERSION_UNKNOWN", "REINSTALL_CORRECT_APK");
        }
        if (signingSha256 == null || signingSha256.isEmpty() || "null".equals(signingSha256)) {
            printInstallRisk(packageName, "SIGNATURE_UNREADABLE", "REINSTALL_CORRECT_SIGNED_APK");
        }
        if (splitCount > 0) {
            printInstallRisk(packageName, "HAS_SPLITS", "BACKUP_AND_RESTORE_ALL_SPLIT_APKS");
        }
        if (!"installed_enabled".equals(playStoreState)) {
            printInstallRisk(packageName, "PLAY_STORE_NOT_READY", "ENABLE_OR_RESTORE_COM_ANDROID_VENDING");
        }
        if (!"installed_enabled".equals(playServicesState)) {
            printInstallRisk(packageName, "PLAY_SERVICES_NOT_READY", "ENABLE_OR_RESTORE_COM_GOOGLE_ANDROID_GMS");
        }
    }

    private static void printInstallCompare(String packageName, String key, String backupValue, String currentValue) {
        String b = sanitizeDiagValue(backupValue);
        String c = sanitizeDiagValue(currentValue);
        String status = safeEquals(normalizeDiagCompareValue(b), normalizeDiagCompareValue(c)) ? "MATCH" : "MISMATCH";
        System.out.println(packageName + " INSTALL_COMPARE " + key + " " + b + " " + c + " " + status);
    }

    private static boolean safeEquals(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }

    private static String normalizeDiagCompareValue(String v) {
        if (v == null) {
            return "null";
        }
        String normalized = v.trim();
        if (normalized.isEmpty() || "null".equalsIgnoreCase(normalized)) {
            return "null";
        }
        return normalized.toLowerCase(Locale.ROOT);
    }

    private static void printInstallDiag(String packageName, String key, String value) {
        System.out.println(packageName + " INSTALL_DIAG " + key + " " + sanitizeDiagValue(value));
    }

    private static void printInstallRisk(String packageName, String risk, String action) {
        System.out.println(packageName + " INSTALL_RISK " + risk + " " + action);
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
        GooglePackageSnapshot out = new GooglePackageSnapshot();
        out.state = "missing";
        out.enabledState = "missing";
        out.uid = "null";
        out.versionCode = "null";
        out.runInBackgroundMode = "null";
        out.runAnyInBackgroundMode = "null";
        out.deviceIdleWhitelist = "false";
        try {
            PackageInfo info = getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
            if (info == null || info.applicationInfo == null) {
                return out;
            }
            out.state = info.applicationInfo.enabled ? "installed_enabled" : "installed_disabled";
            out.uid = String.valueOf(info.applicationInfo.uid);
            out.versionCode = String.valueOf(getLongVersionCodeCompat(info));
            try {
                out.enabledState = String.valueOf(realPm.getApplicationEnabledSetting(packageName));
            } catch (Throwable ignored) {
                out.enabledState = info.applicationInfo.enabled ? "0" : "unknown";
            }
            int runInBackground = resolveBatteryOp("RUN_IN_BACKGROUND");
            int runAnyInBackground = resolveBatteryOp("RUN_ANY_IN_BACKGROUND");
            if (runInBackground != AppOpsManagerHidden.OP_NONE) {
                out.runInBackgroundMode = String.valueOf(getOpMode(appOpsManager, runInBackground, info.applicationInfo.uid, packageName));
            }
            if (runAnyInBackground != AppOpsManagerHidden.OP_NONE) {
                out.runAnyInBackgroundMode = String.valueOf(getOpMode(appOpsManager, runAnyInBackground, info.applicationInfo.uid, packageName));
            }
            out.deviceIdleWhitelist = String.valueOf(idleWhitelist != null && idleWhitelist.contains(packageName));
        } catch (Throwable ignored) {
            // missing / inaccessible
        }
        return out;
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
            // 走 invokeFlexible 復用 METHOD_CACHE: getInstallSourceInfo(String) 對同一 PackageManager 類
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

    private static final class GooglePackageSnapshot {
        String state;
        String enabledState;
        String uid;
        String versionCode;
        String runInBackgroundMode;
        String runAnyInBackgroundMode;
        String deviceIdleWhitelist;
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

    @SuppressLint("ServiceCast")
    private static void getRuntimePermissions(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager packageManager = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden packageManagerHidden = Refine.unsafeCast(packageManager);
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            List<String> packageNames = collectPackageNames(args, 2);
            for (String packageName : packageNames) {
                try {
                    printRuntimePermissions(packageManager, packageManagerHidden, appOpsManager, userId, packageName);
                } catch (Exception e) {
                    System.out.println("PERMISSION_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void printRuntimePermissions(
            PackageManager packageManager,
            PackageManagerHidden packageManagerHidden,
            AppOpsManagerHidden appOpsManager,
            int userId,
            String packageName
    ) {
        PackageInfo packageInfo = packageManagerHidden.getPackageInfoAsUser(packageName, PackageManager.GET_PERMISSIONS | PackageManager.GET_ACTIVITIES, userId);
        String[] requestedPermissions = packageInfo.requestedPermissions;
        int[] requestedPermissionsFlags = packageInfo.requestedPermissionsFlags;
        AppOpsManagerHidden.PackageOps ops = null;
        try {
            List<AppOpsManagerHidden.PackageOps> packageOps = appOpsManager.getOpsForPackage(packageInfo.applicationInfo.uid, packageName, null);
            if (packageOps != null && !packageOps.isEmpty()) {
                ops = packageOps.get(0);
            }
        } catch (Exception ignored) {
        }
        Map<Integer, Integer> opsMap = null;
        if (ops != null) {
            opsMap = ops.getOps().stream().collect(Collectors.toMap(
                    AppOpsManagerHidden.OpEntry::getOp,
                    AppOpsManagerHidden.OpEntry::getMode,
                    (oldMode, newMode) -> newMode
            ));
        }
        Set<Integer> handledOps = new HashSet<>();
        if (requestedPermissions != null && requestedPermissionsFlags != null) {
            for (int i = 0; i < requestedPermissions.length; i++) {
                try {
                    int[] protectionInfo = getPermissionProtectionCached(packageManager, requestedPermissions[i]);
                    int protection = protectionInfo[0];
                    int protectionFlags = protectionInfo[1];
                    boolean isGranted = (requestedPermissionsFlags[i] & PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0;
                    int permissionFlags = getPermissionFlagsCompat(packageManagerHidden, packageName, requestedPermissions[i], userId);
                    int op = AppOpsManagerHidden.permissionToOpCode(requestedPermissions[i]);
                    int mode = AppOpsManagerHidden.MODE_IGNORED;
                    if (opsMap != null && opsMap.containsKey(op)) {
                        mode = getOpMode(appOpsManager, op, packageInfo.applicationInfo.uid, packageName);
                        opsMap.remove(op);
                    }
                    if ((op != AppOpsManagerHidden.OP_NONE)
                            || (protection == PermissionInfo.PROTECTION_DANGEROUS || (protectionFlags & PermissionInfo.PROTECTION_FLAG_DEVELOPMENT) != 0)) {
                        System.out.println(formatRuntimePermissionLine(packageName, requestedPermissions[i], isGranted, op, mode, permissionFlags));
                        if (op != AppOpsManagerHidden.OP_NONE) {
                            handledOps.add(op);
                        }
                    }
                } catch (PackageManager.NameNotFoundException ignored) {
                } catch (Exception e) {
                    e.printStackTrace(System.err);
                }
            }
        }
        for (SpecialAppOp specialAppOp : KNOWN_SPECIAL_APP_OPS) {
            try {
                if (specialAppOp.requirePictureInPictureActivity && !hasPictureInPictureActivity(packageInfo)) {
                    continue;
                }
                int op = AppOpsManagerHidden.strOpToOp(specialAppOp.fieldName);
                if (op == AppOpsManagerHidden.OP_NONE || handledOps.contains(op)) {
                    continue;
                }
                int mode = getOpMode(appOpsManager, op, packageInfo.applicationInfo.uid, packageName);
                handledOps.add(op);
                if (opsMap != null) {
                    opsMap.remove(op);
                }
                System.out.println(formatRuntimePermissionLine(packageName, specialAppOp.publicName, isModeAllowed(mode), op, mode));
            } catch (Throwable ignored) {
            }
        }
        if (opsMap != null) {
            for (Map.Entry<Integer, Integer> entry : opsMap.entrySet()) {
                int op = entry.getKey();
                int mode = entry.getValue();
                String publicName = getPublicName(op);
                System.out.println(formatRuntimePermissionLine(packageName, publicName, isModeAllowed(mode), op, mode));
            }
        }
    }

    /**
     * 已知特殊 AppOps 清單 (主動查詢, 不依賴 getOpsForPackage 是否曾記錄過該 op)
     * requirePictureInPictureActivity=true 的項目只對 manifest 確實宣告支援子母畫面的 app 查詢
     * static 常數, 避免每個 package 重建物件
     */
    private static final List<SpecialAppOp> KNOWN_SPECIAL_APP_OPS = Arrays.asList(
            new SpecialAppOp("android:system_alert_window", "android:system_alert_window", null, false),
            new SpecialAppOp("android:picture_in_picture", "android:picture_in_picture", null, true),
            new SpecialAppOp("android:manage_external_storage", "android:manage_external_storage", null, false),
            new SpecialAppOp("android:write_settings", "android:write_settings", null, false),
            new SpecialAppOp("android:request_install_packages", "android:request_install_packages", null, false),
            new SpecialAppOp("android:get_usage_stats", "android:get_usage_stats", null, false),
            new SpecialAppOp("android:use_full_screen_intent", "android:use_full_screen_intent", null, false),
            new SpecialAppOp("android:schedule_exact_alarm", "android:schedule_exact_alarm", null, false),
            new SpecialAppOp("android:access_notification_policy", "android:access_notification_policy", null, false)
    );

    /**
     * 檢查 app 是否有任何 Activity 宣告支援子母畫面
     * 用 ActivityInfoHidden.FLAG_SUPPORTS_PICTURE_IN_PICTURE (正式 Hidden API 常數, 取代手寫魔術數字)
     */
    private static boolean hasPictureInPictureActivity(PackageInfo packageInfo) {
        if (packageInfo.activities == null) {
            return false;
        }
        for (ActivityInfo activityInfo : packageInfo.activities) {
            if (activityInfo != null && (activityInfo.flags & ActivityInfoHidden.FLAG_SUPPORTS_PICTURE_IN_PICTURE) != 0) {
                return true;
            }
        }
        return false;
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

    private static void restoreAppStateBatch(String[] args) {
        try {
            args = expandAppStateArgsFromStdin(args);
            int userId = Integer.parseInt(args[1]);
            AppStateSections sections = parseAppStateSections(args, 2);

            PermissionStateResult permissionResult = null;
            if (!sections.permission.isEmpty()) {
                String[] permissionArgs = makeSectionArgs(userId, sections.permission);
                permissionResult = restorePermissionSectionsInternal(permissionArgs, 2);
                System.out.println(permissionResult.toLine());
            }

            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            PackageManagerHidden packageManager = pmHidden;
            Object notificationManager = null;
            AppOpsManagerHidden appOpsManager = null;

            int installerPackages = 0;
            int installerClearPackages = 0;
            int notifyPackages = 0;
            int batteryPackages = 0;

            if (!sections.installer.isEmpty()) {
                for (List<String> tokens : parseBracketGroups(makeSectionArgs(userId, sections.installer), 2)) {
                    if (tokens.size() < 2) {
                        throw new IllegalArgumentException("restoreAppStateBatch __INSTALLER__ 分組格式錯誤，需為 [PACKAGE INSTALLER]");
                    }
                    String packageName = tokens.get(0);
                    String installer = parseNullableToken(tokens.get(1));
                    installerPackages++;
                    try {
                        getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                        realPm.setInstallerPackageName(packageName, installer);
                        if (installer != null) {
                            human(packageName, "設定安裝來源完成: installer=" + installer);
                        } else {
                            human(packageName, "清除安裝來源完成");
                        }
                    } catch (Exception e) {
                        System.out.println("INSTALLER_SET_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " installer=" + valueOrDash(installer) + " reason=" + failureReason(e));
                        human(packageName, "設定安裝來源失敗: " + humanizeException(e) + "；若要偽裝成 Play 商店，通常需要用 Play UID 執行或改用 Play session 安裝");
                    }
                }
            }

            if (!sections.installerClear.isEmpty()) {
                for (String packageName : collectPackageNames(makeSectionArgs(userId, sections.installerClear), 2)) {
                    installerClearPackages++;
                    try {
                        getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                        realPm.setInstallerPackageName(packageName, null);
                        human(packageName, "清除安裝來源完成");
                    } catch (Exception e) {
                        System.out.println("INSTALLER_CLEAR_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                        human(packageName, "清除安裝來源失敗: " + humanizeException(e));
                    }
                }
            }

            if (!sections.notification.isEmpty()) {
                notificationManager = getNotificationService();
                for (PackageNotificationSettingSet set : parsePackageNotificationSettingSets(makeSectionArgs(userId, sections.notification), 2)) {
                    notifyPackages++;
                    try {
                        PackageInfo packageInfo = getPackageInfoAsUserCached(packageManager, set.packageName, 0, userId);
                        int uid = packageInfo.applicationInfo.uid;
                        for (NotificationSettingValue item : set.items) {
                            try {
                                applyNotificationSetting(notificationManager, set.packageName, uid, item.key, item.value);
                                human(set.packageName, "通知設定完成: " + item.key + "=" + item.value);
                            } catch (Exception e) {
                                System.out.println("NOTIFICATION_SET_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " key=" + sanitizeDiagValue(item.key) + " value=" + sanitizeDiagValue(item.value) + " reason=" + failureReason(e));
                                human(set.packageName, "通知設定失敗: " + item.key + "=" + item.value + "；" + humanizeException(e));
                            }
                        }
                    } catch (Exception e) {
                        System.out.println("NOTIFICATION_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " reason=" + failureReason(e));
                    }
                }
            }

            if (!sections.battery.isEmpty()) {
                appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
                for (PackageNotificationSettingSet set : parsePackageNotificationSettingSets(makeSectionArgs(userId, sections.battery), 2)) {
                    batteryPackages++;
                    try {
                        PackageInfo packageInfo = getPackageInfoAsUserCached(packageManager, set.packageName, 0, userId);
                        int uid = packageInfo.applicationInfo.uid;
                        for (NotificationSettingValue item : set.items) {
                            try {
                                applyBatterySetting(appOpsManager, set.packageName, uid, item.key, item.value);
                                human(set.packageName, "電池/背景設定完成: " + item.key + "=" + item.value);
                            } catch (Exception e) {
                                System.out.println("BATTERY_SET_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " key=" + sanitizeDiagValue(item.key) + " value=" + sanitizeDiagValue(item.value) + " reason=" + failureReason(e));
                                human(set.packageName, "電池/背景設定失敗: " + item.key + "=" + item.value + "；" + humanizeException(e));
                            }
                        }
                    } catch (Exception e) {
                        System.out.println("BATTERY_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " reason=" + failureReason(e));
                    }
                }
            }

            System.out.println("APP_STATE_BATCH_OK permission=" + (permissionResult == null ? 0 : 1)
                    + " installerPackages=" + installerPackages
                    + " installerClearPackages=" + installerClearPackages
                    + " notifyPackages=" + notifyPackages
                    + " batteryPackages=" + batteryPackages);
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void verifyAppStateBatch(String[] args) {
        try {
            args = expandPermissionStateArgsFromStdin(args);
            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(realPm);
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            VerifyAppStateSections sections = parseVerifyAppStateSections(args, 2);

            if (!sections.installCompare.isEmpty()) {
                for (List<String> tokens : parseBracketGroups(makeSectionArgs(userId, sections.installCompare), 2)) {
                    try {
                        if (tokens.size() < 4) {
                            throw new IllegalArgumentException("verifyAppStateBatch __INSTALL_COMPARE__ 需要 PACKAGE VERSION_CODE SIGNING_SHA256 SPLIT_COUNT");
                        }
                        printInstallDiagnosticCompare(realPm, pmHidden, userId, tokens.get(0), tokens.get(1), tokens.get(2), tokens.get(3));
                    } catch (Exception e) {
                        String pkg = tokens.isEmpty() ? "unknown" : tokens.get(0);
                        System.out.println("INSTALL_COMPARE_FAILED_SKIP package=" + sanitizeDiagValue(pkg) + " reason=" + failureReason(e));
                        human(pkg, "安裝診斷比對失敗: " + humanizeException(e));
                    }
                }
            }

            for (String packageName : collectUniquePackageNames(sections.runtimePackages)) {
                try {
                    printRuntimePermissions(realPm, pmHidden, appOpsManager, userId, packageName);
                } catch (Exception e) {
                    System.out.println("PERMISSION_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }

            if (!sections.notificationPackages.isEmpty()) {
                Object notificationManager = getNotificationService();
                for (String packageName : collectUniquePackageNames(sections.notificationPackages)) {
                    try {
                        PackageInfo packageInfo = getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                        int uid = packageInfo.applicationInfo.uid;
                        printNotificationSettings(notificationManager, packageName, uid);
                    } catch (Exception e) {
                        System.out.println("NOTIFICATION_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                    }
                }
            }

            if (!sections.batteryPackages.isEmpty()) {
                Set<String> idleWhitelist = getDeviceIdleWhitelist();
                for (String packageName : collectUniquePackageNames(sections.batteryPackages)) {
                    try {
                        PackageInfo packageInfo = getPackageInfoAsUserCached(pmHidden, packageName, 0, userId);
                        int uid = packageInfo.applicationInfo.uid;
                        printBatteryOp(appOpsManager, packageName, uid, "RUN_IN_BACKGROUND");
                        printBatteryOp(appOpsManager, packageName, uid, "RUN_ANY_IN_BACKGROUND");
                        System.out.println(packageName + " BATTERY:deviceidle_whitelist " + idleWhitelist.contains(packageName));
                    } catch (Exception e) {
                        System.out.println("BATTERY_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                    }
                }
            }

            System.out.println("VERIFY_APP_STATE_BATCH_OK installCompareGroups=" + parseBracketGroups(makeSectionArgs(userId, sections.installCompare), 2).size()
                    + " runtimePackages=" + collectUniquePackageNames(sections.runtimePackages).size()
                    + " notifyPackages=" + collectUniquePackageNames(sections.notificationPackages).size()
                    + " batteryPackages=" + collectUniquePackageNames(sections.batteryPackages).size());
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static final class VerifyAppStateSections {
        final List<String> installCompare = new ArrayList<>();
        final List<String> runtimePackages = new ArrayList<>();
        final List<String> notificationPackages = new ArrayList<>();
        final List<String> batteryPackages = new ArrayList<>();
    }

    private static VerifyAppStateSections parseVerifyAppStateSections(String[] args, int startIndex) {
        VerifyAppStateSections sections = new VerifyAppStateSections();
        List<String> current = null;
        for (int i = startIndex; i < args.length; i++) {
            String token = args[i];
            switch (token) {
                case "__INSTALL_COMPARE__":
                    current = sections.installCompare;
                    continue;
                case "__RUNTIME__":
                case "__OPS__":
                    current = sections.runtimePackages;
                    continue;
                case "__NOTIFY__":
                    current = sections.notificationPackages;
                    continue;
                case "__BATTERY__":
                    current = sections.batteryPackages;
                    continue;
                default:
                    if (current != null) current.add(token);
            }
        }
        return sections;
    }

    private static List<String> collectUniquePackageNames(List<String> tokens) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        for (String token : tokens) {
            if (token == null) continue;
            String v = token.trim();
            if (v.isEmpty() || "[".equals(v) || "]".equals(v)) continue;
            v = v.replace("[", "").replace("]", "").trim();
            if (v.isEmpty()) continue;
            if (v.contains(".")) out.add(v);
        }
        return new ArrayList<>(out);
    }

    private static PermissionStateResult restorePermissionSectionsInternal(String[] args, int startIndex) throws Exception {
        Context ctx = HiddenApiHelper.getContext();
        PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
        PackageManagerHidden pm = Refine.unsafeCast(realPm);
        AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
        int userId = Integer.parseInt(args[1]);
        UserHandle user = UserHandleHidden.of(userId);

        PermissionStateSections sections = parsePermissionStateSections(args, startIndex);
        List<String> resetPackages = parseResetPackageGroups(sections.reset);
        List<PackagePermissionSet> grants = parsePermissionSection(sections.grant);
        List<PackagePermissionSet> revokes = parsePermissionSection(sections.revoke);
        List<PackageOpModeSet> ops = parseOpModeSection(sections.ops);
        List<PackageModeSet> mediaModes = parseModeSection(sections.media);
        List<PackageModeSet> locationModes = parseModeSection(sections.location);
        List<PackagePermissionFlagSet> permissionFlags = parsePermissionFlagSection(sections.pflags);
        List<PackagePermissionSet> askModes = parsePermissionSection(sections.ask);

        Set<String> resetSet = new HashSet<>();
        resetSet.addAll(resetPackages);
        for (PackagePermissionSet set : grants) resetSet.add(set.packageName);
        for (PackagePermissionSet set : revokes) resetSet.add(set.packageName);
        for (PackageOpModeSet set : ops) resetSet.add(set.packageName);
        for (PackageModeSet set : mediaModes) resetSet.add(set.packageName);
        for (PackageModeSet set : locationModes) resetSet.add(set.packageName);
        for (PackagePermissionFlagSet set : permissionFlags) resetSet.add(set.packageName);
        for (PackagePermissionSet set : askModes) resetSet.add(set.packageName);

        Map<String, Set<Integer>> resetFallbackOps = buildPackageScopedResetFallbackOps(grants, revokes, ops, mediaModes, locationModes, askModes);

        for (String packageName : resetSet) {
            Set<Integer> fallbackOps = resetFallbackOps.get(packageName);
            resetPackageAppOpsInternal(appOpsManager, pm, userId, packageName, fallbackOps);
        }

        for (PackagePermissionSet permissionSet : grants) {
            PackageInfo packageInfo = getPackageInfoForPermissionState(pm, permissionSet.packageName, userId);
            if (packageInfo == null) continue;
            for (String permName : permissionSet.permissionNames) {
                try {
                    pm.grantRuntimePermission(permissionSet.packageName, permName, user);
                    human(permissionSet.packageName, "授予權限完成: " + permName);
                    fixRuntimePermissionAppOpAllow(realPm, appOpsManager, permissionSet.packageName, packageInfo.applicationInfo.uid, permName, "RUNTIME_APPOP_ALLOW");
                } catch (Exception e) {
                    System.out.println("PERMISSION_GRANT_FAILED_SKIP package=" + sanitizeDiagValue(permissionSet.packageName)
                            + " permission=" + sanitizeDiagValue(permName) + " reason=" + failureReason(e));
                    human(permissionSet.packageName, "授予權限失敗: " + permName + "；" + humanizePermissionFailure("grant", e));
                    debugThrowable(classifyPermFailure("grant", permissionSet.packageName, permName, e), e);
                }
            }
        }

        for (PackagePermissionSet permissionSet : revokes) {
            for (String permName : permissionSet.permissionNames) {
                try {
                    pm.revokeRuntimePermission(permissionSet.packageName, permName, user);
                    human(permissionSet.packageName, "撤銷權限完成: " + permName);
                } catch (Exception e) {
                    System.out.println("PERMISSION_REVOKE_FAILED_SKIP package=" + sanitizeDiagValue(permissionSet.packageName)
                            + " permission=" + sanitizeDiagValue(permName) + " reason=" + failureReason(e));
                    human(permissionSet.packageName, "撤銷權限失敗: " + permName + "；" + humanizePermissionFailure("revoke", e));
                    debugThrowable(classifyPermFailure("revoke", permissionSet.packageName, permName, e), e);
                }
            }
        }

        for (PackageOpModeSet opModeSet : ops) {
            PackageInfo packageInfo = getPackageInfoForPermissionState(pm, opModeSet.packageName, userId);
            if (packageInfo == null) continue;
            int uid = packageInfo.applicationInfo.uid;
            for (OpMode opMode : opModeSet.opModes) {
                try {
                    if (isRuntimePermissionBackedOp(realPm, opMode.op)) {
                        System.out.println("APP_OP_RUNTIME_BACKED_SKIP package=" + sanitizeDiagValue(opModeSet.packageName)
                                + " op=" + opMode.op + " mode=" + opMode.mode);
                        human(opModeSet.packageName, "略過 runtime 權限背書 AppOps: op=" + opMode.op + " mode=" + opMode.mode);
                        continue;
                    }
                    AppOpsCompat.setPackageModeIfNeeded(appOpsManager, opMode.op, uid, opModeSet.packageName, opMode.mode);
                    // Android 16/部分 ROM 對若干 AppOps 會同時存在 package mode 與 uid mode；
                    // 7.66 reset fallback 會安全清掉已知 uid mode，因此恢復時同步寫回 uid mode，避免 verify 讀到 default。
                    try {
                        AppOpsCompat.setUidModeIfNeeded(appOpsManager, opMode.op, uid, opMode.mode, HiddenApiUtil::getPublicName);
                    } catch (Throwable t) {
                        debugThrowable("set uid mode after appops restore package=" + opModeSet.packageName + " op=" + opMode.op, t);
                    }
                    human(opModeSet.packageName, "AppOps 設定完成: op=" + opMode.op + " mode=" + opMode.mode);
                } catch (Exception e) {
                    System.out.println("APP_OP_FAILED_SKIP package=" + sanitizeDiagValue(opModeSet.packageName)
                            + " op=" + opMode.op + " mode=" + opMode.mode + " reason=" + failureReason(e));
                    human(opModeSet.packageName, "AppOps 設定失敗: op=" + opMode.op + " mode=" + opMode.mode + "；" + humanizeException(e));
                }
            }
        }

        restoreMediaAccessModeInternal(realPm, pm, appOpsManager, userId, user, mediaModes);
        restoreLocationAccessModeInternal(realPm, pm, appOpsManager, userId, user, locationModes);
        restorePermissionFlagsInternal(pm, userId, user, permissionFlags);
        restoreAskEveryTimeInternal(pm, appOpsManager, userId, user, askModes);

        return new PermissionStateResult(resetSet.size(), grants.size(), revokes.size(), ops.size(), mediaModes.size(), locationModes.size(), permissionFlags.size(), askModes.size());
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

    private static String[] expandAppStateArgsFromStdin(String[] args) throws IOException {
        if (args == null || args.length < 3 || !"--stdin".equals(args[2])) {
            return args;
        }
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = System.in.read(buf)) != -1) {
            baos.write(buf, 0, n);
        }
        String raw = baos.toString();
        raw = raw == null ? "" : raw.trim();
        String[] tokens = raw.isEmpty() ? new String[0] : raw.split("\\s+");
        String[] out = new String[2 + tokens.length];
        out[0] = args[0];
        out[1] = args[1];
        System.arraycopy(tokens, 0, out, 2, tokens.length);
        return out;
    }

    private static String[] makeSectionArgs(int userId, List<String> tokens) {
        String[] out = new String[2 + tokens.size()];
        out[0] = "restoreAppStateBatch";
        out[1] = String.valueOf(userId);
        for (int i = 0; i < tokens.size(); i++) {
            out[i + 2] = tokens.get(i);
        }
        return out;
    }

    private static final class PermissionStateResult {
        final int resetPackages, grantPackages, revokePackages, opPackages, mediaPackages, locationPackages, pflagPackages, askPackages;
        PermissionStateResult(int resetPackages, int grantPackages, int revokePackages, int opPackages, int mediaPackages, int locationPackages, int pflagPackages, int askPackages) {
            this.resetPackages = resetPackages;
            this.grantPackages = grantPackages;
            this.revokePackages = revokePackages;
            this.opPackages = opPackages;
            this.mediaPackages = mediaPackages;
            this.locationPackages = locationPackages;
            this.pflagPackages = pflagPackages;
            this.askPackages = askPackages;
        }
        String toLine() {
            return "PERMISSION_STATE_BATCH_OK reset=" + resetPackages
                    + " grantPackages=" + grantPackages
                    + " revokePackages=" + revokePackages
                    + " opPackages=" + opPackages
                    + " mediaPackages=" + mediaPackages
                    + " locationPackages=" + locationPackages
                    + " pflagPackages=" + pflagPackages
                    + " askPackages=" + askPackages;
        }
    }

    private static final class AppStateSections {
        final List<String> permission = new ArrayList<>();
        final List<String> installer = new ArrayList<>();
        final List<String> installerClear = new ArrayList<>();
        final List<String> notification = new ArrayList<>();
        final List<String> battery = new ArrayList<>();
    }

    private static AppStateSections parseAppStateSections(String[] args, int startIndex) {
        AppStateSections sections = new AppStateSections();
        List<String> current = null;
        for (int i = startIndex; i < args.length; i++) {
            String token = args[i];
            switch (token) {
                case "__PERMISSION__":
                    current = sections.permission;
                    continue;
                case "__INSTALLER__":
                    current = sections.installer;
                    continue;
                case "__CLEAR_INSTALLER__":
                    current = sections.installerClear;
                    continue;
                case "__NOTIFY__":
                    current = sections.notification;
                    continue;
                case "__BATTERY__":
                    current = sections.battery;
                    continue;
                default:
                    if (current != null) {
                        current.add(token);
                    }
            }
        }
        return sections;
    }

    private static String[] expandPermissionStateArgsFromStdin(String[] args) throws IOException {
        if (args == null || args.length < 3 || !"--stdin".equals(args[2])) {
            return args;
        }
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = System.in.read(buf)) != -1) {
            baos.write(buf, 0, n);
        }
        String raw = baos.toString();
        raw = raw == null ? "" : raw.trim();
        String[] tokens = raw.isEmpty() ? new String[0] : raw.split("\\s+");
        String[] out = new String[2 + tokens.length];
        out[0] = args[0];
        out[1] = args[1];
        System.arraycopy(tokens, 0, out, 2, tokens.length);
        return out;
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

    private static PackageInfo getPackageInfoForPermissionState(PackageManagerHidden pm, String packageName, int userId) {
        try {
            return getPackageInfoAsUserCached(pm, packageName, PackageManager.GET_PERMISSIONS, userId);
        } catch (Exception e) {
            System.out.println("PERMISSION_STATE_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
            human(packageName, "權限狀態套件讀取失敗: " + humanizeException(e));
            return null;
        }
    }

    private static boolean resetPackageAppOpsInternal(AppOpsManagerHidden appOpsManager, PackageManagerHidden pm, int userId, String packageName, Set<Integer> fallbackOps) {
        AppOpsCompat.ResetResult reset = AppOpsCompat.resetPackageModesSafe(appOpsManager, userId, packageName);
        if (reset.ok) {
            System.out.println("APP_OPS_RESET_OK package=" + sanitizeDiagValue(packageName)
                    + " method=" + reset.method
                    + " signature=" + reset.signature
                    + " cached=" + reset.cached
                    + " safePackageScoped=" + reset.safePackageScoped);
            human(packageName, "AppOps 重置完成");
            return true;
        }

        if (resetKnownAppOpsForPackage(appOpsManager, pm, userId, packageName, fallbackOps)) {
            System.out.println("APP_OPS_RESET_FALLBACK_OK package=" + sanitizeDiagValue(packageName)
                    + " method=known_ops_default"
                    + " reason=" + failureReason(reset.error)
                    + " safePackageScopedOnly=true cachedUnsupported=" + reset.cachedUnsupported);
            human(packageName, "AppOps package-scoped reset 不支援，已改用本次 payload 內已知 op reset");
            return true;
        }

        String marker = sAppOpsResetUnsupportedReported
                ? "APP_OPS_RESET_CACHED_UNSUPPORTED_SKIP"
                : "APP_OPS_RESET_UNSUPPORTED_SKIP";
        sAppOpsResetUnsupportedReported = true;
        System.out.println(marker + " package=" + sanitizeDiagValue(packageName)
                + " reason=" + failureReason(reset.error)
                + " safePackageScopedOnly=true cachedUnsupported=" + reset.cachedUnsupported
                + " fallbackKnownOps=false");
        human(packageName, "AppOps package-scoped reset 不支援，且本次無可安全 fallback 的已知 op");
        return false;
    }

    private static Map<String, Set<Integer>> buildPackageScopedResetFallbackOps(List<PackagePermissionSet> grants,
                                                                                List<PackagePermissionSet> revokes,
                                                                                List<PackageOpModeSet> ops,
                                                                                List<PackageModeSet> mediaModes,
                                                                                List<PackageModeSet> locationModes,
                                                                                List<PackagePermissionSet> askModes) {
        Map<String, Set<Integer>> out = new HashMap<>();
        for (PackagePermissionSet set : grants) addPermissionOps(out, set.packageName, set.permissionNames);
        for (PackagePermissionSet set : revokes) addPermissionOps(out, set.packageName, set.permissionNames);
        for (PackagePermissionSet set : askModes) addPermissionOps(out, set.packageName, set.permissionNames);
        for (PackageOpModeSet set : ops) {
            for (OpMode opMode : set.opModes) addResetFallbackOp(out, set.packageName, opMode.op);
        }
        for (PackageModeSet set : mediaModes) addMediaResetOps(out, set.packageName);
        for (PackageModeSet set : locationModes) addLocationResetOps(out, set.packageName);
        return out;
    }

    private static void addPermissionOps(Map<String, Set<Integer>> out, String packageName, List<String> permissionNames) {
        for (String permissionName : permissionNames) {
            try {
                int op = AppOpsManagerHidden.permissionToOpCode(permissionName);
                addResetFallbackOp(out, packageName, op);
            } catch (Throwable ignored) {
            }
        }
    }

    private static void addMediaResetOps(Map<String, Set<Integer>> out, String packageName) {
        addPermissionOps(out, packageName, Arrays.asList(
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.READ_MEDIA_VIDEO",
                "android.permission.READ_MEDIA_AUDIO",
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"));
    }

    private static void addLocationResetOps(Map<String, Set<Integer>> out, String packageName) {
        addPermissionOps(out, packageName, Arrays.asList(
                "android.permission.ACCESS_COARSE_LOCATION",
                "android.permission.ACCESS_FINE_LOCATION",
                "android.permission.ACCESS_BACKGROUND_LOCATION"));
    }

    private static void addResetFallbackOp(Map<String, Set<Integer>> out, String packageName, int op) {
        if (packageName == null || packageName.isEmpty() || op < 0 || op == AppOpsManagerHidden.OP_NONE) return;
        Set<Integer> set = out.get(packageName);
        if (set == null) {
            set = new LinkedHashSet<>();
            out.put(packageName, set);
        }
        set.add(op);
    }

    private static boolean resetKnownAppOpsForPackage(AppOpsManagerHidden appOpsManager, PackageManagerHidden pm, int userId, String packageName, Set<Integer> fallbackOps) {
        if (fallbackOps == null || fallbackOps.isEmpty()) return false;
        PackageInfo packageInfo;
        try {
            packageInfo = getPackageInfoAsUserCached(pm, packageName, 0, userId);
        } catch (Exception e) {
            System.out.println("APP_OPS_RESET_FALLBACK_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
            return false;
        }
        int changed = AppOpsCompat.resetKnownOpsToDefault(appOpsManager, packageInfo.applicationInfo.uid, packageName, fallbackOps, HiddenApiUtil::getPublicName);
        int fail = Math.max(0, fallbackOps.size() - changed);
        System.out.println("APP_OPS_RESET_FALLBACK_SUMMARY package=" + sanitizeDiagValue(packageName)
                + " ok=" + changed + " fail=" + fail + " total=" + fallbackOps.size());
        return changed > 0;
    }

    private static void restoreMediaAccessModeInternal(PackageManager realPm, PackageManagerHidden pm,
                                                       AppOpsManagerHidden appOpsManager, int userId, UserHandle user,
                                                       List<PackageModeSet> sets) {
        for (PackageModeSet set : sets) {
            PackageInfo packageInfo;
            try {
                packageInfo = getPackageInfoAsUserCached(pm, set.packageName, PackageManager.GET_PERMISSIONS, userId);
            } catch (Exception e) {
                System.out.println("MEDIA_MODE_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " reason=" + failureReason(e));
                continue;
            }
            String mode = normalizeMode(set.mode);
            if ("full".equals(mode)) {
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_IMAGES");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_VIDEO");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_AUDIO");
            } else if ("selected".equals(mode)) {
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_IMAGES");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_VIDEO");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_VISUAL_USER_SELECTED");
            } else if ("denied".equals(mode)) {
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_IMAGES");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_VIDEO");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_AUDIO");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.READ_MEDIA_VISUAL_USER_SELECTED");
            } else {
                System.out.println("MEDIA_MODE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " mode=" + sanitizeDiagValue(set.mode) + " reason=unsupported_mode");
                continue;
            }
            System.out.println("MEDIA_MODE_RESTORE_OK package=" + sanitizeDiagValue(set.packageName) + " mode=" + mode);
            human(set.packageName, "媒體權限語意模式完成: " + mode);
        }
    }

    private static void restoreLocationAccessModeInternal(PackageManager realPm, PackageManagerHidden pm,
                                                          AppOpsManagerHidden appOpsManager, int userId, UserHandle user,
                                                          List<PackageModeSet> sets) {
        for (PackageModeSet set : sets) {
            PackageInfo packageInfo;
            try {
                packageInfo = getPackageInfoAsUserCached(pm, set.packageName, PackageManager.GET_PERMISSIONS, userId);
            } catch (Exception e) {
                System.out.println("LOCATION_MODE_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " reason=" + failureReason(e));
                continue;
            }
            String mode = normalizeMode(set.mode);
            if ("precise".equals(mode) || "while_in_use".equals(mode)) {
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_COARSE_LOCATION");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_FINE_LOCATION");
            } else if ("approximate".equals(mode)) {
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_COARSE_LOCATION");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.ACCESS_FINE_LOCATION");
            } else if ("background".equals(mode)) {
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_COARSE_LOCATION");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_FINE_LOCATION");
                grantIfRequestedAndFix(realPm, pm, appOpsManager, packageInfo, user, set.packageName, "android.permission.ACCESS_BACKGROUND_LOCATION");
            } else if ("ask_every_time".equals(mode) || "ask".equals(mode)) {
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.ACCESS_BACKGROUND_LOCATION");
                restoreAskEveryTimeForPermission(pm, appOpsManager, set.packageName, packageInfo.applicationInfo.uid, "android.permission.ACCESS_FINE_LOCATION", userId, user);
                restoreAskEveryTimeForPermission(pm, appOpsManager, set.packageName, packageInfo.applicationInfo.uid, "android.permission.ACCESS_COARSE_LOCATION", userId, user);
            } else if ("denied".equals(mode)) {
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.ACCESS_BACKGROUND_LOCATION");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.ACCESS_FINE_LOCATION");
                revokeIfRequested(pm, packageInfo, user, set.packageName, "android.permission.ACCESS_COARSE_LOCATION");
            } else {
                System.out.println("LOCATION_MODE_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName) + " mode=" + sanitizeDiagValue(set.mode) + " reason=unsupported_mode");
                continue;
            }
            System.out.println("LOCATION_MODE_RESTORE_OK package=" + sanitizeDiagValue(set.packageName) + " mode=" + mode);
            human(set.packageName, "定位權限語意模式完成: " + mode);
        }
    }

    private static int getPermissionFlagsCompat(PackageManagerHidden pm, String packageName, String permissionName, int userId) {
        return PermissionCompat.getPermissionFlags(pm, packageName, permissionName, userId);
    }

    private static int getPackageManagerFlag(String name, int fallback) {
        return PermissionCompat.packageManagerFlag(name, fallback);
    }

    private static int permissionFlagRestoreMask() {
        int mask = 0;
        mask |= getPackageManagerFlag("FLAG_PERMISSION_USER_SET", 1 << 0);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_USER_FIXED", 1 << 1);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_REVOKED_COMPAT", 1 << 3);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_REVIEW_REQUIRED", 1 << 6);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_REVOKE_WHEN_REQUESTED", 1 << 14);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_AUTO_REVOKED", 1 << 15);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_ONE_TIME", 1 << 16);
        mask |= getPackageManagerFlag("FLAG_PERMISSION_SELECTED_LOCATION_ACCURACY", 1 << 19);
        return mask;
    }

    private static void updatePermissionFlagsCompat(PackageManagerHidden pm, String packageName, String permissionName,
                                                    int mask, int values, int userId, UserHandle user) throws Exception {
        PermissionCompat.updatePermissionFlags(pm, packageName, permissionName, mask, values, userId, user);
    }

    private static void restorePermissionFlagsInternal(PackageManagerHidden pm, int userId, UserHandle user,
                                                       List<PackagePermissionFlagSet> sets) {
        int mask = permissionFlagRestoreMask();
        for (PackagePermissionFlagSet set : sets) {
            for (PermissionFlagValue flag : set.flags) {
                try {
                    int values = flag.flags & mask;
                    updatePermissionFlagsCompat(pm, set.packageName, flag.permissionName, mask, values, userId, user);
                    System.out.println("PERMISSION_FLAGS_RESTORE_OK package=" + sanitizeDiagValue(set.packageName)
                            + " permission=" + sanitizeDiagValue(flag.permissionName) + " flags=" + flag.flags + " mask=" + mask);
                    human(set.packageName, "權限 flags 還原完成: " + flag.permissionName + " flags=" + flag.flags);
                } catch (Exception e) {
                    System.out.println("PERMISSION_FLAGS_FAILED_SKIP package=" + sanitizeDiagValue(set.packageName)
                            + " permission=" + sanitizeDiagValue(flag.permissionName) + " flags=" + flag.flags
                            + " reason=" + failureReason(e));
                    human(set.packageName, "權限 flags 還原失敗: " + flag.permissionName + "；" + humanizeException(e));
                    debugThrowable("restorePermissionFlags package=" + set.packageName + " permission=" + flag.permissionName, e);
                }
            }
        }
    }

    private static int flagUserSet() { return getPackageManagerFlag("FLAG_PERMISSION_USER_SET", 1 << 0); }
    private static int flagUserFixed() { return getPackageManagerFlag("FLAG_PERMISSION_USER_FIXED", 1 << 1); }
    private static int flagRevokeWhenRequested() { return getPackageManagerFlag("FLAG_PERMISSION_REVOKE_WHEN_REQUESTED", 1 << 14); }
    private static int flagOneTime() { return getPackageManagerFlag("FLAG_PERMISSION_ONE_TIME", 1 << 16); }

    private static boolean isAskEveryTimePermission(String permissionName) {
        return "android.permission.CAMERA".equals(permissionName)
                || "android.permission.RECORD_AUDIO".equals(permissionName)
                || "android.permission.ACCESS_FINE_LOCATION".equals(permissionName)
                || "android.permission.ACCESS_COARSE_LOCATION".equals(permissionName);
    }

    private static int askEveryTimeFlagsValue() {
        return flagUserSet() | flagOneTime() | flagRevokeWhenRequested();
    }

    private static int askEveryTimeFlagsMask() {
        return flagUserSet() | flagUserFixed() | flagOneTime() | flagRevokeWhenRequested();
    }

    private static void restoreAskEveryTimeForPermission(PackageManagerHidden pm, AppOpsManagerHidden appOpsManager,
                                                         String packageName, int uid, String permissionName,
                                                         int userId, UserHandle user) {
        if (!isAskEveryTimePermission(permissionName)) {
            System.out.println("ASK_MODE_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " reason=unsupported_permission");
            return;
        }
        try {
            PackageInfo packageInfo = getPackageInfoForPermissionState(pm, packageName, userId);
            if (packageInfo != null && !packageRequests(packageInfo, permissionName)) {
                System.out.println("ASK_MODE_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                        + " permission=" + sanitizeDiagValue(permissionName) + " reason=permission_not_requested");
                return;
            }
            try {
                pm.revokeRuntimePermission(packageName, permissionName, user);
            } catch (Exception ignored) {
                debugThrowable("askMode revoke package=" + packageName + " permission=" + permissionName, ignored);
            }
            int op = AppOpsManagerHidden.permissionToOpCode(permissionName);
            int packageMode = -999;
            int uidMode = -999;
            int effectiveMode = -999;
            String scope = "NO_OP";
            if (op >= 0) {
                // ask-every-time 語意：PM runtime 狀態由 revoke + one-time flags 表示；
                // AppOps 只允許 uid scope 為權威。先清 package mode，再寫 uid ignored，
                // 避免 AOSP/Android 16 的 package+uid 雙重狀態污染。
                try {
                    AppOpsCompat.setRuntimePermissionUidMode(appOpsManager, op, uid,
                            AppOpsManagerHidden.MODE_IGNORED, packageName, HiddenApiUtil::getPublicName);
                } catch (Throwable t) {
                    debugThrowable("askMode runtime uid mode package=" + packageName + " permission=" + permissionName + " op=" + op, t);
                }
                packageMode = AppOpsCompat.getPackageModeRaw(appOpsManager, op, uid, packageName, getOpMode(appOpsManager, op, uid, packageName));
                uidMode = AppOpsCompat.getUidModeRaw(appOpsManager, op, uid, HiddenApiUtil::getPublicName);
                effectiveMode = getOpMode(appOpsManager, op, uid, packageName);
                scope = classifyScopeNote(op, packageMode, uidMode, effectiveMode);
            }
            updatePermissionFlagsCompat(pm, packageName, permissionName, askEveryTimeFlagsMask(), askEveryTimeFlagsValue(), userId, user);
            System.out.println("ASK_MODE_RESTORE_OK package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName)
                    + " flags=" + askEveryTimeFlagsValue()
                    + " op=" + op
                    + " package_mode=" + packageMode
                    + " uid_mode=" + uidMode
                    + " effective_mode=" + effectiveMode
                    + " scope=" + scope);
            human(packageName, "每次詢問模式還原完成: " + permissionName);
        } catch (Exception e) {
            System.out.println("ASK_MODE_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " reason=" + failureReason(e));
            human(packageName, "每次詢問模式還原失敗: " + permissionName + "；" + humanizeException(e));
            debugThrowable("restoreAskEveryTime package=" + packageName + " permission=" + permissionName, e);
        }
    }

    private static void restoreAskEveryTimeInternal(PackageManagerHidden pm, AppOpsManagerHidden appOpsManager,
                                                    int userId, UserHandle user,
                                                    List<PackagePermissionSet> sets) {
        for (PackagePermissionSet set : sets) {
            PackageInfo packageInfo = getPackageInfoForPermissionState(pm, set.packageName, userId);
            if (packageInfo == null) continue;
            for (String permissionName : set.permissionNames) {
                restoreAskEveryTimeForPermission(pm, appOpsManager, set.packageName,
                        packageInfo.applicationInfo.uid, permissionName, userId, user);
            }
        }
    }

    @SuppressLint("ServiceCast")
    private static void fixRuntimeAppOpsAllow(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            PackageManagerHidden pm = Refine.unsafeCast(realPm);
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            for (PackagePermissionSet permissionSet : parsePackagePermissionSets(args, 2)) {
                PackageInfo packageInfo;
                try {
                    packageInfo = getPackageInfoAsUserCached(pm, permissionSet.packageName, PackageManager.GET_PERMISSIONS, userId);
                } catch (Exception e) {
                    System.out.println("RUNTIME_APPOP_PACKAGE_FAILED_SKIP package=" + sanitizeDiagValue(permissionSet.packageName) + " reason=" + failureReason(e));
                    continue;
                }
                int uid = packageInfo.applicationInfo.uid;
                for (String permName : permissionSet.permissionNames) {
                    fixRuntimePermissionAppOpAllow(realPm, appOpsManager, permissionSet.packageName, uid, permName, "RUNTIME_APPOP_FIX");
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    /**
     * 判斷 op 是否為 runtime(dangerous)權限背書。透過 AppOpsManager.opToPermission(int) 反查權限名,
     * 再用 PackageManager 確認其 protectionLevel 是否為 DANGEROUS。
     * opToPermission 為長期存在的 @hide 靜態方法 (Android 9-16 穩定)。
     * 任何反射或查詢失敗一律回 false (不略過), 確保 fail-open 不弄丟還原。
     */
    private static String opToPermissionCached(int op) {
        if (sOpToPermissionCache.containsKey(op)) {
            return sOpToPermissionCache.get(op);
        }
        String out = null;
        try {
            Object perm = invokeFlexible(classForNameCached("android.app.AppOpsManager"), "opToPermission", op);
            if (perm instanceof String && !((String) perm).isEmpty()) {
                out = (String) perm;
            }
        } catch (Throwable ignored) {
        }
        sOpToPermissionCache.put(op, out);
        return out;
    }

    private static boolean isRuntimePermissionBackedOp(PackageManager pm, int op) {
        Boolean cached = sRuntimePermissionBackedOpCache.get(op);
        if (cached != null) {
            return cached;
        }
        boolean result = false;
        try {
            String perm = opToPermissionCached(op);
            if (perm != null && !perm.isEmpty()) {
                int[] protectionInfo = getPermissionProtectionCached(pm, perm);
                result = protectionInfo[0] == PermissionInfo.PROTECTION_DANGEROUS;
            }
        } catch (Throwable ignored) {
            result = false;
        }
        sRuntimePermissionBackedOpCache.put(op, result);
        return result;
    }

    private static void fixRuntimePermissionAppOpAllow(PackageManager pm, AppOpsManagerHidden appOpsManager,
                                                        String packageName, int uid, String permissionName, String prefix) {
        int op = AppOpsManagerHidden.OP_NONE;
        try {
            op = AppOpsManagerHidden.permissionToOpCode(permissionName);
        } catch (Throwable ignored) {
        }
        if (op == AppOpsManagerHidden.OP_NONE) {
            System.out.println(prefix + "_NO_OP package=" + sanitizeDiagValue(packageName) + " permission=" + sanitizeDiagValue(permissionName));
            return;
        }
        try {
            // runtime-backed op 必須以 per-uid 為唯一權威: 先用 setMode(MODE_DEFAULT) 清掉
            // 舊版工具可能留下的 package 級 override，再用 setUidMode 設 ALLOWED。
            // 若 setMode(DEFAULT) 在某些 ROM 上不支援，仍繼續嘗試 uid mode；不可改用 setMode(ALLOWED)。
            try {
                AppOpsCompat.setPackageModeIfNeeded(appOpsManager, op, uid, packageName, AppOpsManagerHidden.MODE_DEFAULT);
            } catch (Throwable t) {
                debugThrowable(prefix + " setMode(MODE_DEFAULT) clear failed package=" + packageName + " permission=" + permissionName, t);
            }
            AppOpsCompat.setUidModeIfNeeded(appOpsManager, op, uid, AppOpsManagerHidden.MODE_ALLOWED, HiddenApiUtil::getPublicName);
            int mode = getOpMode(appOpsManager, op, uid, packageName);
            System.out.println(prefix + "_OK package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " op=" + op + " mode=" + mode);
            human(packageName, "runtime 權限 AppOps 修正完成: " + permissionName + " op=" + op + " mode=" + mode);
        } catch (Exception e) {
            System.out.println(prefix + "_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " op=" + op + " reason=" + failureReason(e));
            human(packageName, "runtime 權限 AppOps 修正失敗: " + permissionName + "；" + humanizeException(e));
        }
    }

    private static boolean packageRequests(PackageInfo packageInfo, String permissionName) {
        String[] requested = packageInfo.requestedPermissions;
        if (requested == null) return false;
        for (String perm : requested) {
            if (permissionName.equals(perm)) return true;
        }
        return false;
    }

    private static void grantIfRequestedAndFix(PackageManager realPm, PackageManagerHidden pm, AppOpsManagerHidden appOpsManager,
                                                PackageInfo packageInfo, UserHandle user, String packageName, String permissionName) {
        if (!packageRequests(packageInfo, permissionName)) return;
        try {
            pm.grantRuntimePermission(packageName, permissionName, user);
            fixRuntimePermissionAppOpAllow(realPm, appOpsManager, packageName, packageInfo.applicationInfo.uid, permissionName, "SEMANTIC_APPOP_ALLOW");
        } catch (Exception e) {
            System.out.println("SEMANTIC_GRANT_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " reason=" + failureReason(e));
            debugThrowable(classifyPermFailure("semantic grant", packageName, permissionName, e), e);
        }
    }

    private static void revokeIfRequested(PackageManagerHidden pm, PackageInfo packageInfo, UserHandle user, String packageName, String permissionName) {
        if (!packageRequests(packageInfo, permissionName)) return;
        try {
            pm.revokeRuntimePermission(packageName, permissionName, user);
        } catch (Exception e) {
            System.out.println("SEMANTIC_REVOKE_FAILED_SKIP package=" + sanitizeDiagValue(packageName)
                    + " permission=" + sanitizeDiagValue(permissionName) + " reason=" + failureReason(e));
            debugThrowable(classifyPermFailure("semantic revoke", packageName, permissionName, e), e);
        }
    }

    private static String normalizeMode(String raw) {
        if (raw == null) return "";
        return raw.trim().toLowerCase(Locale.ROOT).replace('-', '_');
    }

    @SuppressLint("ServiceCast")
    private static void appOpsResetBatch(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManagerHidden packageManager = Refine.unsafeCast(PackageManagerUtil.getPackageManager(ctx).packageManager());
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            int packages = 0;
            int ok = 0;
            int skip = 0;
            for (String packageName : readPackagesFromArgsOrStdin(args, 2)) {
                if (packageName == null || packageName.trim().isEmpty()) continue;
                packages++;
                if (resetPackageAppOpsInternal(appOpsManager, packageManager, userId, packageName.trim(), new LinkedHashSet<Integer>())) {
                    ok++;
                } else {
                    skip++;
                }
            }
            System.out.println("APP_OPS_RESET_BATCH_OK packages=" + packages + " ok=" + ok + " skip=" + skip + " source=" + ((args.length > 2 && "--stdin".equals(args[2])) ? "stdin" : "args"));
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static List<String> readPackagesFromArgsOrStdin(String[] args, int start) throws IOException {
        List<String> packages = new ArrayList<>();
        if (args.length > start && "--stdin".equals(args[start])) {
            byte[] data = readAllStdinBytes();
            String text = new String(data, java.nio.charset.StandardCharsets.UTF_8);
            for (String line : text.split("\\r?\\n")) {
                String pkg = line.trim();
                if (!pkg.isEmpty() && !pkg.startsWith("#")) {
                    packages.add(pkg);
                }
            }
            return packages;
        }
        return collectPackageNames(args, start);
    }

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
                    throw new IllegalArgumentException("appOpsScopeDetail 分組格式錯誤，需為 [PACKAGE OP OP ...]");
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

    private static void forceStopPackageBatch(String[] args) {
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
            for (String packageName : packages) {
                if (ActivityCompat.forceStopPackageNoThrow(packageName, userId)) {
                    System.out.println("FORCE_STOP_OK package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                } else {
                    System.out.println("FORCE_STOP_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " user=" + userId);
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
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

    private static String formatRuntimePermissionLine(String packageName, String permissionName, boolean isGranted, int op, int mode) {
        return formatRuntimePermissionLine(packageName, permissionName, isGranted, op, mode, 0);
    }

    private static String formatRuntimePermissionLine(String packageName, String permissionName, boolean isGranted, int op, int mode, int permissionFlags) {
        if (permissionName != null && permissionName.startsWith("android.permission.")) {
            return packageName + " " + permissionName + " " + isGranted + " " + op + " " + mode + " pflags=" + permissionFlags;
        }
        return packageName + " " + permissionName + " " + isGranted + " " + op + " " + mode;
    }

    private static int[] getPermissionProtectionCached(PackageManager packageManager, String permissionName)
            throws PackageManager.NameNotFoundException {
        int[] cached = sPermissionProtectionCache.get(permissionName);
        if (cached != null) {
            return cached;
        }
        PermissionInfo permissionInfo = packageManager.getPermissionInfo(permissionName, 0);
        int[] protectionInfo = new int[] {
                getPermissionProtection(permissionInfo),
                getPermissionProtectionFlags(permissionInfo)
        };
        sPermissionProtectionCache.put(permissionName, protectionInfo);
        return protectionInfo;
    }

    private static int getPermissionProtection(PermissionInfo permissionInfo) {
        return permissionInfo.protectionLevel & 0x0000000f;
    }

    private static int getPermissionProtectionFlags(PermissionInfo permissionInfo) {
        return permissionInfo.protectionLevel & 0xfffffff0;
    }

    private static boolean isModeAllowed(int mode) {
        return mode == AppOpsManagerHidden.MODE_ALLOWED || mode == AppOpsManagerHidden.MODE_FOREGROUND;
    }

    @SuppressLint("ServiceCast")
    private static void getBatterySettings(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManagerHidden packageManager = Refine.unsafeCast(PackageManagerUtil.getPackageManager(ctx).packageManager());
            AppOpsManagerHidden appOpsManager = (AppOpsManagerHidden) ctx.getSystemService(Context.APP_OPS_SERVICE);
            int userId = Integer.parseInt(args[1]);
            Set<String> idleWhitelist = getDeviceIdleWhitelist();
            List<String> packageNames = collectPackageNames(args, 2);
            for (String packageName : packageNames) {
                try {
                    PackageInfo packageInfo = getPackageInfoAsUserCached(packageManager, packageName, 0, userId);
                    int uid = packageInfo.applicationInfo.uid;
                    printBatteryOp(appOpsManager, packageName, uid, "RUN_IN_BACKGROUND");
                    printBatteryOp(appOpsManager, packageName, uid, "RUN_ANY_IN_BACKGROUND");
                    System.out.println(packageName + " BATTERY:deviceidle_whitelist " + idleWhitelist.contains(packageName));
                } catch (Exception e) {
                    System.out.println("BATTERY_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void printBatteryOp(AppOpsManagerHidden appOpsManager, String packageName, int uid, String opName) {
        int op = resolveBatteryOp(opName);
        if (op == AppOpsManagerHidden.OP_NONE) {
            System.out.println(packageName + " BATTERY:" + opName + " -1 " + AppOpsManagerHidden.MODE_IGNORED + " ignored");
            return;
        }
        int mode = getOpMode(appOpsManager, op, uid, packageName);
        System.out.println(packageName + " BATTERY:" + opName + " " + op + " " + mode + " " + appOpsModeToName(mode));
    }

    private static int getOpMode(AppOpsManagerHidden appOpsManager, int op, int uid, String packageName) {
        if (op == AppOpsManagerHidden.OP_NONE) {
            return AppOpsManagerHidden.MODE_IGNORED;
        }
        try {
            return appOpsManager.unsafeCheckOpRawNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        try {
            return appOpsManager.checkOpNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        return AppOpsManagerHidden.MODE_IGNORED;
    }

    private static void applyBatterySetting(AppOpsManagerHidden appOpsManager, String packageName, int uid, String key, String value) throws Exception {
        if ("battery_opt".equals(key) || "BATTERY:RUN_ANY_IN_BACKGROUND".equals(key)) {
            int op = resolveBatteryOp("RUN_ANY_IN_BACKGROUND");
            if (op == AppOpsManagerHidden.OP_NONE)
                throw new IllegalArgumentException("找不到 RUN_ANY_IN_BACKGROUND AppOp");
            int mode = parseBatteryMode(value);
            AppOpsCompat.setPackageModeIfNeeded(appOpsManager, op, uid, packageName, mode);
            // Android 16/部分 ROM 會優先以 uid mode 回報 RUN_ANY_IN_BACKGROUND；同步寫入避免 package=ignore 但 uid=default 導致 verify mismatch。
            try {
                AppOpsCompat.setUidModeIfNeeded(appOpsManager, op, uid, mode, HiddenApiUtil::getPublicName);
            } catch (Throwable t) {
                debugThrowable("set uid mode after battery run_any package=" + packageName + " op=" + op, t);
            }
            // 不再強制連帶寫入 deviceidle 白名單。
            // 備份時 RUN_ANY 與白名單是各自獨立讀取的, 還原也必須各自獨立,
            // 否則 RUN_ANY=allow 會覆蓋備份中 whitelist=false 的真實狀態 (且結果取決於 key 順序)。
            // 白名單一律由 BATTERY:deviceidle_whitelist key 自行還原。
            return;
        }
        if ("BATTERY:RUN_IN_BACKGROUND".equals(key)) {
            int op = resolveBatteryOp("RUN_IN_BACKGROUND");
            if (op == AppOpsManagerHidden.OP_NONE)
                throw new IllegalArgumentException("找不到 RUN_IN_BACKGROUND AppOp");
            int mode = parseBatteryMode(value);
            AppOpsCompat.setPackageModeIfNeeded(appOpsManager, op, uid, packageName, mode);
            try {
                AppOpsCompat.setUidModeIfNeeded(appOpsManager, op, uid, mode, HiddenApiUtil::getPublicName);
            } catch (Throwable t) {
                debugThrowable("set uid mode after battery run_in package=" + packageName + " op=" + op, t);
            }
            return;
        }
        if ("BATTERY:deviceidle_whitelist".equals(key) || "BATTERY:idle_whitelist".equals(key) || "BATTERY:doze_whitelist".equals(key)) {
            setDeviceIdleWhitelist(packageName, Boolean.parseBoolean(value));
            return;
        }
        throw new IllegalArgumentException("未知電池設定 key: " + key);
    }

    private static int parseBatteryMode(String raw) {
        if (raw == null) return AppOpsManagerHidden.MODE_DEFAULT;
        String v = raw.trim().toLowerCase(Locale.ROOT);
        if (v.contains(" ")) {
            String[] parts = v.split("\\s+");
            if (parts.length >= 2) v = parts[1];
        }
        switch (v) {
            case "allow":
            case "allowed":
            case "true":
                return AppOpsManagerHidden.MODE_ALLOWED;
            case "ignore":
            case "ignored":
            case "false":
                return AppOpsManagerHidden.MODE_IGNORED;
            case "deny":
            case "denied":
            case "errored":
                return AppOpsManagerHidden.MODE_ERRORED;
            case "default":
                return AppOpsManagerHidden.MODE_DEFAULT;
            case "foreground":
                return AppOpsManagerHidden.MODE_FOREGROUND;
            default:
                return Integer.parseInt(v);
        }
    }

    private static String appOpsModeToName(int mode) {
        switch (mode) {
            case AppOpsManagerHidden.MODE_ALLOWED:
                return "allow";
            case AppOpsManagerHidden.MODE_IGNORED:
                return "ignore";
            case AppOpsManagerHidden.MODE_ERRORED:
                return "deny";
            case AppOpsManagerHidden.MODE_DEFAULT:
                return "default";
            case AppOpsManagerHidden.MODE_FOREGROUND:
                return "foreground";
            default:
                return String.valueOf(mode);
        }
    }

    private static int resolveBatteryOp(String opName) {
        Integer cached = sBatteryOpCache.get(opName);
        if (cached != null) {
            return cached;
        }
        int resolved = AppOpsManagerHidden.OP_NONE;
        String publicName = "android:" + opName.toLowerCase(Locale.ROOT);
        try {
            int op = AppOpsManagerHidden.strOpToOp(publicName);
            if (op != AppOpsManagerHidden.OP_NONE) resolved = op;
        } catch (Throwable ignored) {
        }
        if (resolved == AppOpsManagerHidden.OP_NONE) {
            try {
                Class<?> clazz = classForNameCached("android.app.AppOpsManager");
                java.lang.reflect.Field field = clazz.getDeclaredField("OP_" + opName);
                field.setAccessible(true);
                resolved = field.getInt(null);
            } catch (Throwable ignored) {
            }
        }
        sBatteryOpCache.put(opName, resolved);
        return resolved;
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

    private static void setDeviceIdleWhitelist(String packageName, boolean enabled) {
        try {
            Set<String> current = getDeviceIdleWhitelist();
            if (current.contains(packageName) == enabled) {
                return;
            }
        } catch (Throwable ignored) {
        }
        try {
            Object service = getDeviceIdleService();
            if (enabled) {
                callRequired(service, new CallSpec("addPowerSaveWhitelistApp", packageName));
            } else {
                callRequired(service, new CallSpec("removePowerSaveWhitelistApp", packageName));
            }
            return;
        } catch (Throwable ignored) {
            // Compatibility / fallback handling.
        }
        setDeviceIdleWhitelistViaShell(packageName, enabled);
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

    private static void setDeviceIdleWhitelistViaShell(String packageName, boolean enabled) {
        String safePkg = packageName.replaceAll("[^A-Za-z0-9._-]", "");
        if (safePkg.isEmpty()) return;
        String prefix = enabled ? "+" : "-";

        // Compatibility / fallback handling.
        if (execShellSuccess("cmd deviceidle whitelist " + prefix + safePkg)) {
            return;
        }
        execShellCapture("dumpsys deviceidle whitelist " + prefix + safePkg);
    }

    private static boolean execShellSuccess(String command) {
        try {
            Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", command});
            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))) {
                while (reader.readLine() != null) {
                }
            }
            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))) {
                while (reader.readLine() != null) {
                }
            }
            return process.waitFor() == 0;
        } catch (Throwable ignored) {
            return false;
        }
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

    private static void getNotificationSettings(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManagerHidden packageManager = Refine.unsafeCast(PackageManagerUtil.getPackageManager(ctx).packageManager());
            int userId = Integer.parseInt(args[1]);
            Object notificationManager = getNotificationService();
            List<String> packageNames = collectPackageNames(args, 2);
            for (String packageName : packageNames) {
                try {
                    PackageInfo packageInfo = getPackageInfoAsUserCached(packageManager, packageName, 0, userId);
                    int uid = packageInfo.applicationInfo.uid;
                    printNotificationSettings(notificationManager, packageName, uid);
                } catch (Exception e) {
                    System.out.println("NOTIFICATION_QUERY_FAILED_SKIP package=" + sanitizeDiagValue(packageName) + " reason=" + failureReason(e));
                }
            }
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static Object getNotificationService() throws Exception {
        return HiddenApiServices.notification();
    }

    private static void printNotificationSettings(Object notificationManager, String packageName, int uid) {
        printNotificationValue(packageName, "NOTIFY_APP:enabled", safeBoolean(callFirst(notificationManager,
                new CallSpec("areNotificationsEnabledForPackage", packageName, uid),
                new CallSpec("areNotificationsEnabled", packageName)
        ), true));
        Object importance = callFirst(notificationManager,
                new CallSpec("getPackageImportance", packageName),
                new CallSpec("getImportance", packageName),
                new CallSpec("getPackageImportance", packageName, uid)
        );
        if (importance instanceof Number) {
            printNotificationValue(packageName, "NOTIFY_APP:importance", String.valueOf(((Number) importance).intValue()));
        }

        Object appShowBadge = callFirst(notificationManager,
                new CallSpec("canShowBadge", packageName, uid),
                new CallSpec("getShowBadge", packageName, uid)
        );
        if (appShowBadge instanceof Boolean) {
            printNotificationValue(packageName, "NOTIFY_APP:showBadge", String.valueOf(appShowBadge));
        }

        Object appBubblePreference = callFirst(notificationManager,
                new CallSpec("getBubblePreferenceForPackage", packageName, uid),
                new CallSpec("getBubblesAllowed", packageName, uid),
                new CallSpec("getBubblePreference", packageName, uid)
        );
        if (appBubblePreference instanceof Number) {
            printNotificationValue(packageName, "NOTIFY_APP:bubblePreference", String.valueOf(((Number) appBubblePreference).intValue()));
        } else if (appBubblePreference instanceof Boolean) {
            printNotificationValue(packageName, "NOTIFY_APP:allowBubbles", String.valueOf(appBubblePreference));
        }

        for (Object group : getNotificationGroups(notificationManager, packageName, uid)) {
            String groupId = safeString(invokeNoArg(group, "getId"));
            if (groupId == null || groupId.isEmpty()) {
                continue;
            }
            String keyPrefix = "NOTIFY_GROUP:" + encodeToken(groupId) + ":";
            Object blocked = invokeNoArg(group, "isBlocked");
            if (blocked instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "blocked", String.valueOf(blocked));
            }
        }

        for (Object channel : getNotificationChannels(notificationManager, packageName, uid)) {
            String channelId = safeString(invokeNoArg(channel, "getId"));
            if (channelId == null || channelId.isEmpty()) {
                continue;
            }
            String keyPrefix = "NOTIFY_CHANNEL:" + encodeToken(channelId) + ":";
            Object importanceValue = invokeNoArg(channel, "getImportance");
            if (importanceValue instanceof Number) {
                printNotificationValue(packageName, keyPrefix + "importance", String.valueOf(((Number) importanceValue).intValue()));
            }
            Object showBadge = invokeNoArg(channel, "canShowBadge");
            if (showBadge instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "showBadge", String.valueOf(showBadge));
            }
            Object allowBubbles = callFirst(channel,
                    new CallSpec("getAllowBubbles"),
                    new CallSpec("canBubble")
            );
            if (allowBubbles instanceof Number) {
                printNotificationValue(packageName, keyPrefix + "allowBubbles", String.valueOf(((Number) allowBubbles).intValue()));
            } else if (allowBubbles instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "canBubble", String.valueOf(allowBubbles));
            }
            Object importantConversation = invokeNoArg(channel, "isImportantConversation");
            if (importantConversation instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "importantConversation", String.valueOf(importantConversation));
            }
            Object demoted = invokeNoArg(channel, "isDemoted");
            if (demoted instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "demoted", String.valueOf(demoted));
            }
            Object shouldVibrate = invokeNoArg(channel, "shouldVibrate");
            if (shouldVibrate instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "vibration", String.valueOf(shouldVibrate));
            }
            Object shouldShowLights = invokeNoArg(channel, "shouldShowLights");
            if (shouldShowLights instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "lights", String.valueOf(shouldShowLights));
            }
            Object deleted = invokeNoArg(channel, "isDeleted");
            if (deleted instanceof Boolean) {
                printNotificationValue(packageName, keyPrefix + "deleted", String.valueOf(deleted));
            }
        }
    }

    private static void printNotificationValue(String packageName, String key, String value) {
        if (value != null) {
            System.out.println(packageName + " " + key + " " + value);
        }
    }

    private static String notificationCacheKey(String packageName, int uid) {
        return uid + "|" + packageName;
    }

    private static List<Object> getNotificationChannels(Object notificationManager, String packageName, int uid) {
        String key = notificationCacheKey(packageName, uid);
        List<Object> cached = sNotificationChannelsCache.get(key);
        if (cached != null) {
            return new ArrayList<>(cached);
        }
        Object slice = callFirst(notificationManager,
                new CallSpec("getNotificationChannelsForPackage", packageName, uid, true),
                new CallSpec("getNotificationChannelsForPackage", packageName, uid, true, false),
                new CallSpec("getNotificationChannels", packageName, uid, true)
        );
        List<Object> result = listFromSliceOrList(slice);
        sNotificationChannelsCache.put(key, result);
        return new ArrayList<>(result);
    }

    private static List<Object> getNotificationGroups(Object notificationManager, String packageName, int uid) {
        String key = notificationCacheKey(packageName, uid);
        List<Object> cached = sNotificationGroupsCache.get(key);
        if (cached != null) {
            return new ArrayList<>(cached);
        }
        Object slice = callFirst(notificationManager,
                new CallSpec("getNotificationChannelGroupsForPackage", packageName, uid, true),
                new CallSpec("getNotificationChannelGroupsForPackage", packageName, uid, true, false),
                new CallSpec("getNotificationChannelGroups", packageName, uid, true)
        );
        List<Object> result = listFromSliceOrList(slice);
        sNotificationGroupsCache.put(key, result);
        return new ArrayList<>(result);
    }

    private static void clearNotificationResultCache(String packageName, int uid) {
        String key = notificationCacheKey(packageName, uid);
        sNotificationChannelsCache.remove(key);
        sNotificationGroupsCache.remove(key);
    }

    private static List<Object> listFromSliceOrList(Object obj) {
        List<Object> result = new ArrayList<>();
        if (obj == null) {
            return result;
        }
        try {
            Object list = obj;
            if (!(list instanceof List)) {
                list = invokeNoArg(obj, "getList");
            }
            if (list instanceof List<?>) {
                result.addAll((List<?>) list);
            }
        } catch (Throwable ignored) {
        }
        return result;
    }

    private static void applyNotificationSetting(Object notificationManager, String packageName, int uid, String key, String value) throws Exception {
        if (key == null || value == null) {
            return;
        }
        if ("NOTIFY_APP:enabled".equals(key)) {
            boolean enabled = Boolean.parseBoolean(value);
            callRequired(notificationManager,
                    new CallSpec("setNotificationsEnabledWithImportanceLockForPackage", packageName, uid, enabled),
                    new CallSpec("setNotificationsEnabledForPackage", packageName, uid, enabled),
                    new CallSpec("setNotificationsEnabled", packageName, enabled)
            );
            return;
        }
        if ("NOTIFY_APP:showBadge".equals(key)) {
            boolean showBadge = Boolean.parseBoolean(value);
            callRequired(notificationManager,
                    new CallSpec("setShowBadge", packageName, uid, showBadge)
            );
            return;
        }
        if ("NOTIFY_APP:bubblePreference".equals(key)) {
            int bubblePreference = Integer.parseInt(value);
            callRequired(notificationManager,
                    new CallSpec("setBubblesAllowed", packageName, uid, bubblePreference),
                    new CallSpec("setBubblePreferenceForPackage", packageName, uid, bubblePreference)
            );
            return;
        }
        if ("NOTIFY_APP:allowBubbles".equals(key)) {
            int bubblePreference = Boolean.parseBoolean(value) ? 1 : 0;
            callRequired(notificationManager,
                    new CallSpec("setBubblesAllowed", packageName, uid, bubblePreference),
                    new CallSpec("setBubblePreferenceForPackage", packageName, uid, bubblePreference)
            );
            return;
        }
        if (key.startsWith("NOTIFY_CHANNEL:")) {
            String[] parts = key.split(":", 3);
            if (parts.length != 3) {
                throw new IllegalArgumentException("通知分類 key 格式錯誤: " + key);
            }
            String channelId = decodeToken(parts[1]);
            String field = parts[2];
            Object channel = findNotificationChannel(notificationManager, packageName, uid, channelId);
            if (channel == null) {
                throw new IllegalArgumentException("找不到通知分類: " + channelId);
            }
            applyChannelField(channel, field, value);
            callRequired(notificationManager,
                    new CallSpec("updateNotificationChannelForPackage", packageName, uid, channel)
            );
            clearNotificationResultCache(packageName, uid);
            return;
        }
        if (key.startsWith("NOTIFY_GROUP:")) {
            String[] parts = key.split(":", 3);
            if (parts.length != 3) {
                throw new IllegalArgumentException("通知群組 key 格式錯誤: " + key);
            }
            String groupId = decodeToken(parts[1]);
            String field = parts[2];
            Object group = findNotificationGroup(notificationManager, packageName, uid, groupId);
            if (group == null) {
                throw new IllegalArgumentException("找不到通知群組: " + groupId);
            }
            applyGroupField(group, field, value);
            callRequired(notificationManager,
                    new CallSpec("updateNotificationChannelGroupForPackage", packageName, uid, group)
            );
            clearNotificationResultCache(packageName, uid);
            return;
        }
        throw new IllegalArgumentException("未知通知設定 key: " + key);
    }

    private static Object findNotificationChannel(Object notificationManager, String packageName, int uid, String channelId) {
        for (Object channel : getNotificationChannels(notificationManager, packageName, uid)) {
            if (channelId.equals(safeString(invokeNoArg(channel, "getId")))) {
                return channel;
            }
        }
        return null;
    }

    private static Object findNotificationGroup(Object notificationManager, String packageName, int uid, String groupId) {
        for (Object group : getNotificationGroups(notificationManager, packageName, uid)) {
            if (groupId.equals(safeString(invokeNoArg(group, "getId")))) {
                return group;
            }
        }
        return null;
    }

    private static void applyChannelField(Object channel, String field, String value) throws Exception {
        switch (field) {
            case "importance":
                invokeRequired(channel, "setImportance", Integer.parseInt(value));
                break;
            case "showBadge":
                invokeRequired(channel, "setShowBadge", Boolean.parseBoolean(value));
                break;
            case "allowBubbles":
                invokeRequired(channel, "setAllowBubbles", Integer.parseInt(value));
                break;
            case "canBubble":
                invokeRequired(channel, "setAllowBubbles", Boolean.parseBoolean(value) ? 1 : 0);
                break;
            case "importantConversation":
                invokeRequired(channel, "setImportantConversation", Boolean.parseBoolean(value));
                break;
            case "demoted":
                invokeRequired(channel, "setDemoted", Boolean.parseBoolean(value));
                break;
            case "vibration":
                invokeRequired(channel, "enableVibration", Boolean.parseBoolean(value));
                break;
            case "lights":
                invokeRequired(channel, "enableLights", Boolean.parseBoolean(value));
                break;
            default:
                throw new IllegalArgumentException("不支援的通知分類欄位: " + field);
        }
    }

    private static void applyGroupField(Object group, String field, String value) throws Exception {
        if ("blocked".equals(field)) {
            invokeRequired(group, "setBlocked", Boolean.parseBoolean(value));
        } else {
            throw new IllegalArgumentException("不支援的通知群組欄位: " + field);
        }
    }

    private static Class<?> classForNameCached(String name) throws ClassNotFoundException {
        return HiddenApiReflection.classForNameCached(name);
    }

    private static Object callFirst(Object target, CallSpec... specs) {
        Throwable last = null;
        for (CallSpec spec : specs) {
            try {
                return invokeFlexible(target, spec.methodName, spec.args);
            } catch (Throwable e) {
                last = e;
            }
        }
        if (last != null) {
            debugThrowable("callFirst 全部簽章失敗 (" + describeSpecs(specs) + ")", last);
        }
        return null;
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
            debugThrowable("callRequired 全部簽章失敗 (" + describeSpecs(specs) + ")", last);
        }
        throw new IllegalStateException(last != null ? last.getMessage() : "找不到匹配的方法");
    }

    private static Object invokeNoArg(Object target, String methodName) {
        try {
            return invokeFlexible(target, methodName);
        } catch (Throwable e) {
            debugThrowable("invokeNoArg " + methodName, e);
            return null;
        }
    }

    private static Object invokeRequired(Object target, String methodName, Object... args) throws Exception {
        return invokeFlexible(target, methodName, args);
    }

    private static final Map<String, java.lang.reflect.Method> METHOD_CACHE = new java.util.HashMap<>();
    private static final Set<String> METHOD_MISS_CACHE = new HashSet<>();

    private static String buildMethodKey(Class<?> clazz, String methodName, Object[] args) {
        StringBuilder sb = new StringBuilder(clazz.getName());
        sb.append('#').append(methodName).append('#').append(args.length);
        for (Object arg : args) {
            sb.append('#').append(arg == null ? "null" : arg.getClass().getName());
        }
        return sb.toString();
    }

    private static Object invokeFlexible(Object target, String methodName, Object... args) throws Exception {
        return HiddenApiReflection.invokeFlexible(target, methodName, args);
    }

    private static java.lang.reflect.Method resolveMethod(Class<?> clazz, String methodName, Object[] args) {
        for (java.lang.reflect.Method method : clazz.getMethods()) {
            if (!method.getName().equals(methodName)) {
                continue;
            }
            Class<?>[] paramTypes = method.getParameterTypes();
            if (paramTypes.length != args.length) {
                continue;
            }
            if (!areArgsCompatible(paramTypes, args)) {
                continue;
            }
            method.setAccessible(true);
            return method;
        }
        for (java.lang.reflect.Method method : clazz.getDeclaredMethods()) {
            if (!method.getName().equals(methodName)) {
                continue;
            }
            Class<?>[] paramTypes = method.getParameterTypes();
            if (paramTypes.length != args.length) {
                continue;
            }
            if (!areArgsCompatible(paramTypes, args)) {
                continue;
            }
            method.setAccessible(true);
            return method;
        }
        return null;
    }

    private static boolean areArgsCompatible(Class<?>[] paramTypes, Object[] args) {
        for (int i = 0; i < paramTypes.length; i++) {
            if (args[i] == null) {
                if (paramTypes[i].isPrimitive()) {
                    return false;
                }
                continue;
            }
            Class<?> wrapper = primitiveToWrapper(paramTypes[i]);
            if (!wrapper.isInstance(args[i])) {
                return false;
            }
        }
        return true;
    }

    private static Class<?> primitiveToWrapper(Class<?> type) {
        if (!type.isPrimitive()) {
            return type;
        }
        if (type == int.class) return Integer.class;
        if (type == boolean.class) return Boolean.class;
        if (type == long.class) return Long.class;
        if (type == float.class) return Float.class;
        if (type == double.class) return Double.class;
        if (type == byte.class) return Byte.class;
        if (type == short.class) return Short.class;
        if (type == char.class) return Character.class;
        return Void.class;
    }

    private static String safeBoolean(Object value, boolean fallback) {
        if (value instanceof Boolean) {
            return String.valueOf(value);
        }
        return String.valueOf(fallback);
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String encodeToken(String raw) {
        try {
            return android.util.Base64.encodeToString(raw.getBytes("UTF-8"), android.util.Base64.URL_SAFE | android.util.Base64.NO_WRAP | android.util.Base64.NO_PADDING);
        } catch (Throwable ignored) {
            return raw.replace("%", "%25").replace(":", "%3A").replace(" ", "%20");
        }
    }

    private static String decodeToken(String token) {
        try {
            return new String(android.util.Base64.decode(token, android.util.Base64.URL_SAFE | android.util.Base64.NO_WRAP | android.util.Base64.NO_PADDING), "UTF-8");
        } catch (Throwable ignored) {
            return token.replace("%20", " ").replace("%3A", ":").replace("%25", "%");
        }
    }

    private static List<PackageNotificationSettingSet> parsePackageNotificationSettingSets(String[] args, int start) {
        List<PackageNotificationSettingSet> sets = new ArrayList<>();
        for (List<String> tokens : parseBracketGroups(args, start)) {
            PackageNotificationSettingSet set = new PackageNotificationSettingSet(tokens.get(0));
            for (int j = 1; j < tokens.size(); j += 2) {
                if (j + 1 >= tokens.size()) {
                    throw new IllegalArgumentException("缺少通知設定值，key: " + tokens.get(j));
                }
                set.items.add(new NotificationSettingValue(tokens.get(j), tokens.get(j + 1)));
            }
            sets.add(set);
        }
        return sets;
    }

    private static final class CallSpec {
        final String methodName;
        final Object[] args;

        CallSpec(String methodName, Object... args) {
            this.methodName = methodName;
            this.args = args;
        }
    }

    private static final class PackageNotificationSettingSet {
        final String packageName;
        final List<NotificationSettingValue> items = new ArrayList<>();

        PackageNotificationSettingSet(String packageName) {
            this.packageName = packageName;
        }
    }

    private static final class NotificationSettingValue {
        final String key;
        final String value;

        NotificationSettingValue(String key, String value) {
            this.key = key;
            this.value = value;
        }
    }

    private static final class PermissionStateSections {
        final List<String> reset = new ArrayList<>();
        final List<String> grant = new ArrayList<>();
        final List<String> revoke = new ArrayList<>();
        final List<String> ops = new ArrayList<>();
        final List<String> media = new ArrayList<>();
        final List<String> location = new ArrayList<>();
        final List<String> pflags = new ArrayList<>();
        final List<String> ask = new ArrayList<>();
    }

    private static PermissionStateSections parsePermissionStateSections(String[] args, int start) {
        PermissionStateSections sections = new PermissionStateSections();
        List<String> current = null;
        for (int i = start; i < args.length; i++) {
            String token = args[i];
            if ("__RESET__".equals(token)) {
                current = sections.reset;
                continue;
            } else if ("__GRANT__".equals(token)) {
                current = sections.grant;
                continue;
            } else if ("__REVOKE__".equals(token)) {
                current = sections.revoke;
                continue;
            } else if ("__OPS__".equals(token)) {
                current = sections.ops;
                continue;
            } else if ("__MEDIA__".equals(token)) {
                current = sections.media;
                continue;
            } else if ("__LOCATION__".equals(token)) {
                current = sections.location;
                continue;
            } else if ("__PFLAGS__".equals(token)) {
                current = sections.pflags;
                continue;
            } else if ("__ASK__".equals(token)) {
                current = sections.ask;
                continue;
            }
            if (current != null) {
                current.add(token);
            }
        }
        return sections;
    }

    private static String[] sectionArgs(List<String> tokens) {
        String[] out = new String[tokens.size() + 2];
        out[0] = "section";
        out[1] = "0";
        for (int i = 0; i < tokens.size(); i++) {
            out[i + 2] = tokens.get(i);
        }
        return out;
    }

    private static List<PackagePermissionSet> parsePermissionSection(List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) return new ArrayList<>();
        return parsePackagePermissionSets(sectionArgs(tokens), 2);
    }

    private static List<PackageOpModeSet> parseOpModeSection(List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) return new ArrayList<>();
        return parsePackageOpModeSets(sectionArgs(tokens), 2);
    }

    private static List<PackageModeSet> parseModeSection(List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) return new ArrayList<>();
        return parsePackageModeSets(sectionArgs(tokens), 2);
    }

    private static List<String> parseResetPackageGroups(List<String> tokens) {
        List<String> out = new ArrayList<>();
        if (tokens == null || tokens.isEmpty()) return out;
        for (List<String> group : parseBracketGroups(sectionArgs(tokens), 2)) {
            if (!group.isEmpty()) {
                out.add(group.get(0));
            }
        }
        return out;
    }

    private static List<PackagePermissionSet> parsePackagePermissionSets(String[] args, int start) {
        List<PackagePermissionSet> sets = new ArrayList<>();
        for (List<String> tokens : parseBracketGroups(args, start)) {
            PackagePermissionSet set = new PackagePermissionSet(tokens.get(0));
            set.permissionNames.addAll(tokens.subList(1, tokens.size()));
            sets.add(set);
        }
        return sets;
    }

    private static List<PackageOpModeSet> parsePackageOpModeSets(String[] args, int start) {
        List<PackageOpModeSet> sets = new ArrayList<>();
        for (List<String> tokens : parseBracketGroups(args, start)) {
            PackageOpModeSet set = new PackageOpModeSet(tokens.get(0));
            for (int j = 1; j < tokens.size(); j += 2) {
                if (j + 1 >= tokens.size()) {
                    throw new IllegalArgumentException("缺少 AppOps mode: " + tokens.get(j));
                }
                set.opModes.add(new OpMode(Integer.parseInt(tokens.get(j)), Integer.parseInt(tokens.get(j + 1))));
            }
            sets.add(set);
        }
        return sets;
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
                        throw new IllegalArgumentException("不支援巢狀分組: " + rawToken);
                    }
                    current = new ArrayList<>();
                    rawToken = rawToken.substring(1);
                }
                if (current == null) {
                    throw new IllegalArgumentException("缺少分組起始標記 [: " + rawToken);
                }
                if (endsGroup) {
                    rawToken = rawToken.substring(0, rawToken.length() - 1);
                }
                if (!rawToken.isEmpty()) {
                    current.add(rawToken);
                }
                if (endsGroup) {
                    if (current.isEmpty()) {
                        throw new IllegalArgumentException("空分組");
                    }
                    groups.add(current);
                    current = null;
                }
            }
        }
        if (current != null) {
            throw new IllegalArgumentException("缺少分組結束標記 ]");
        }
        return groups;
    }

    private static final class SpecialAppOp {
        final String publicName;
        final String fieldName;
        final String permissionName;
        final boolean requirePictureInPictureActivity;

        SpecialAppOp(String publicName, String fieldName, String permissionName, boolean requirePictureInPictureActivity) {
            this.publicName = publicName;
            this.fieldName = fieldName;
            this.permissionName = permissionName;
            this.requirePictureInPictureActivity = requirePictureInPictureActivity;
        }
    }

    private static List<PackageModeSet> parsePackageModeSets(String[] args, int start) {
        List<PackageModeSet> sets = new ArrayList<>();
        for (List<String> tokens : parseBracketGroups(args, start)) {
            if (tokens.size() < 2) {
                throw new IllegalArgumentException("缺少 mode: " + tokens.get(0));
            }
            sets.add(new PackageModeSet(tokens.get(0), tokens.get(1)));
        }
        return sets;
    }

    private static List<PackagePermissionFlagSet> parsePermissionFlagSection(List<String> tokens) {
        return parsePermissionFlagSets(sectionArgs(tokens), 2);
    }

    private static List<PackagePermissionFlagSet> parsePermissionFlagSets(String[] args, int start) {
        List<PackagePermissionFlagSet> sets = new ArrayList<>();
        for (List<String> tokens : parseBracketGroups(args, start)) {
            if (tokens.isEmpty()) {
                continue;
            }
            PackagePermissionFlagSet set = new PackagePermissionFlagSet(tokens.get(0));
            for (int i = 1; i + 1 < tokens.size(); i += 2) {
                try {
                    set.flags.add(new PermissionFlagValue(tokens.get(i), Integer.parseInt(tokens.get(i + 1))));
                } catch (NumberFormatException ignored) {
                }
            }
            sets.add(set);
        }
        return sets;
    }

    private static final class PackageModeSet {
        final String packageName;
        final String mode;

        PackageModeSet(String packageName, String mode) {
            this.packageName = packageName;
            this.mode = mode;
        }
    }

    private static final class PackagePermissionSet {
        final String packageName;
        final List<String> permissionNames = new ArrayList<>();

        PackagePermissionSet(String packageName) {
            this.packageName = packageName;
        }
    }

    private static final class PackagePermissionFlagSet {
        final String packageName;
        final List<PermissionFlagValue> flags = new ArrayList<>();

        PackagePermissionFlagSet(String packageName) {
            this.packageName = packageName;
        }
    }

    private static final class PermissionFlagValue {
        final String permissionName;
        final int flags;

        PermissionFlagValue(String permissionName, int flags) {
            this.permissionName = permissionName;
            this.flags = flags;
        }
    }

    private static final class PackageOpModeSet {
        final String packageName;
        final List<OpMode> opModes = new ArrayList<>();

        PackageOpModeSet(String packageName) {
            this.packageName = packageName;
        }
    }

    private static final class OpMode {
        final int op;
        final int mode;

        OpMode(int op, int mode) {
            this.op = op;
            this.mode = mode;
        }
    }
}
