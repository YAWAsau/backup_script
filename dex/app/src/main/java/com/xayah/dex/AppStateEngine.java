package com.xayah.dex;

import android.annotation.SuppressLint;
import android.app.ActivityManager;
import android.app.AppOpsManagerHidden;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.content.pm.ActivityInfoHidden;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.content.pm.PermissionInfo;
import android.os.Build;
import android.os.UserHandle;
import android.os.UserHandleHidden;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonNull;
import com.google.gson.JsonParser;
import com.xayah.dex.compat.AppOpsCompat;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;
import com.xayah.dex.compat.PermissionCompat;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.concurrent.TimeUnit;

import dev.rikka.tools.refine.Refine;

/**
 * Structured App state engine shared by the one-shot CLI and the persistent AF_UNIX daemon.
 *
 * Output is UTF-8 NDJSON. Every package record carries an explicit result object, so callers
 * never need to infer success/failure from translated text. The final record is always a
 * summary record. Snapshot, restore and verify share this single canonical schema; the former
 * HiddenApiUtil token-section AppState protocol has been removed.
 */
public final class AppStateEngine {
    public static final int SCHEMA_VERSION = 2;
    public static final int DAEMON_PROTOCOL_VERSION = 1;
    public static final String ENGINE_VERSION = "v1.3.30-device-list-sharded-clean";

    static final Gson GSON = new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
    static final Gson PRETTY_GSON = new GsonBuilder().serializeNulls().disableHtmlEscaping().setPrettyPrinting().create();

    public enum ResultCode {
        OK(0, false),
        PARTIAL(10, true),
        BAD_REQUEST(20, false),
        PACKAGE_NOT_FOUND(30, false),
        UNSUPPORTED(40, false),
        PERMISSION_DENIED(50, false),
        VERIFY_MISMATCH(60, false),
        INTERNAL_ERROR(70, true);

        public final int code;
        public final boolean retryable;

        ResultCode(int code, boolean retryable) {
            this.code = code;
            this.retryable = retryable;
        }
    }

    public static final class EngineResponse {
        public final ResultCode resultCode;
        public final String body;

        public EngineResponse(ResultCode resultCode, String body) {
            this.resultCode = resultCode;
            this.body = body == null ? "" : body;
        }

        public int processExitCode() {
            if (resultCode == ResultCode.OK || resultCode == ResultCode.PARTIAL || resultCode == ResultCode.VERIFY_MISMATCH) {
                return 0;
            }
            return resultCode == ResultCode.BAD_REQUEST ? 2 : 1;
        }
    }

    private static final class SpecialAccessDescriptor {
        final String key;
        final String publicName;
        final String manifestPermission;
        final boolean requirePictureInPictureActivity;

        SpecialAccessDescriptor(String key, String publicName, String manifestPermission,
                                boolean requirePictureInPictureActivity) {
            this.key = key;
            this.publicName = publicName;
            this.manifestPermission = manifestPermission;
            this.requirePictureInPictureActivity = requirePictureInPictureActivity;
        }
    }

    private static final List<SpecialAccessDescriptor> SPECIAL_ACCESS = Collections.unmodifiableList(Arrays.asList(
            new SpecialAccessDescriptor("SYSTEM_ALERT_WINDOW", "android:system_alert_window", "android.permission.SYSTEM_ALERT_WINDOW", false),
            new SpecialAccessDescriptor("PICTURE_IN_PICTURE", "android:picture_in_picture", null, true),
            new SpecialAccessDescriptor("MANAGE_EXTERNAL_STORAGE", "android:manage_external_storage", "android.permission.MANAGE_EXTERNAL_STORAGE", false),
            new SpecialAccessDescriptor("WRITE_SETTINGS", "android:write_settings", "android.permission.WRITE_SETTINGS", false),
            new SpecialAccessDescriptor("REQUEST_INSTALL_PACKAGES", "android:request_install_packages", "android.permission.REQUEST_INSTALL_PACKAGES", false),
            new SpecialAccessDescriptor("GET_USAGE_STATS", "android:get_usage_stats", "android.permission.PACKAGE_USAGE_STATS", false),
            new SpecialAccessDescriptor("USE_FULL_SCREEN_INTENT", "android:use_full_screen_intent", "android.permission.USE_FULL_SCREEN_INTENT", false),
            new SpecialAccessDescriptor("SCHEDULE_EXACT_ALARM", "android:schedule_exact_alarm", "android.permission.SCHEDULE_EXACT_ALARM", false),
            new SpecialAccessDescriptor("ACCESS_NOTIFICATION_POLICY", "android:access_notification_policy", "android.permission.ACCESS_NOTIFICATION_POLICY", false)
    ));

    private static final Map<String, SpecialAccessDescriptor> SPECIAL_ACCESS_BY_KEY = buildSpecialAccessMap();
    private static final Map<String, Integer> OP_CACHE = new HashMap<>();
    private static final Map<String, int[]> PERMISSION_PROTECTION_CACHE = new HashMap<>();
    private static final Object RUNTIME_LOCK = new Object();
    private static volatile RuntimeServices RUNTIME_SERVICES;

    private static final class RuntimeServices {
        final Context context;
        final PackageManager packageManager;
        final PackageManagerHidden packageManagerHidden;
        final AppOpsManagerHidden appOpsManager;

        RuntimeServices(Context context, PackageManager packageManager,
                        PackageManagerHidden packageManagerHidden,
                        AppOpsManagerHidden appOpsManager) {
            this.context = context;
            this.packageManager = packageManager;
            this.packageManagerHidden = packageManagerHidden;
            this.appOpsManager = appOpsManager;
        }
    }

    private static final class ForegroundProcess {
        final String packageName;
        final String processName;
        final int pid;
        final int uid;
        final int userId;
        final int importance;
        final int processState;
        final int importanceReasonCode;
        final String source;

        ForegroundProcess(String packageName, String processName, int pid, int uid, int userId,
                          int importance, int processState, int importanceReasonCode, String source) {
            this.packageName = packageName == null ? "" : packageName;
            this.processName = processName == null ? "" : processName;
            this.pid = pid;
            this.uid = uid;
            this.userId = userId;
            this.importance = importance;
            this.processState = processState;
            this.importanceReasonCode = importanceReasonCode;
            this.source = source == null ? "unknown" : source;
        }
    }

    private static final class RunningProcessSnapshot {
        final List<ForegroundProcess> processes;
        final String source;
        final boolean dumpsysFallbackUsed;
        final String note;

        RunningProcessSnapshot(List<ForegroundProcess> processes, String source, boolean dumpsysFallbackUsed, String note) {
            this.processes = processes == null ? Collections.<ForegroundProcess>emptyList() : processes;
            this.source = source == null || source.isEmpty() ? "none" : source;
            this.dumpsysFallbackUsed = dumpsysFallbackUsed;
            this.note = note == null ? "" : note;
        }
    }

    private static final class TopApp {
        final String packageName;
        final String activityName;
        final int userId;
        final String source;
        final String raw;

        TopApp(String packageName, String activityName, int userId, String source, String raw) {
            this.packageName = packageName == null ? "" : packageName;
            this.activityName = activityName == null ? "" : activityName;
            this.userId = userId;
            this.source = source == null ? "unknown" : source;
            this.raw = raw == null ? "" : raw;
        }
    }

    private AppStateEngine() {
    }

    /** Initializes Context and Binder-backed services once before daemon READY. */
    @SuppressLint("ServiceCast")
    public static void initializeRuntime() throws Exception {
        runtimeServices();
    }

    @SuppressLint("ServiceCast")
    private static RuntimeServices runtimeServices() throws Exception {
        RuntimeServices cached = RUNTIME_SERVICES;
        if (cached != null) return cached;
        synchronized (RUNTIME_LOCK) {
            cached = RUNTIME_SERVICES;
            if (cached != null) return cached;
            Context context = HiddenApiHelper.initializeContext();
            PackageManager packageManager = PackageManagerUtil.getPackageManager(context).packageManager();
            PackageManagerHidden packageManagerHidden = Refine.unsafeCast(packageManager);
            AppOpsManagerHidden appOpsManager =
                    (AppOpsManagerHidden) context.getSystemService(Context.APP_OPS_SERVICE);
            if (appOpsManager == null) {
                throw new IllegalStateException("APP_OPS_SERVICE unavailable");
            }
            cached = new RuntimeServices(context, packageManager, packageManagerHidden, appOpsManager);
            RUNTIME_SERVICES = cached;
            return cached;
        }
    }

    public static synchronized EngineResponse dispatch(String command, int userId, String extra, String body) {
        try {
            switch (normalizeCommand(command)) {
                case "ping":
                    return new EngineResponse(ResultCode.OK, "PONG\n");
                case "capabilities":
                    return capabilities("pretty".equalsIgnoreCase(extra));
                case "localize":
                case "localizebatch":
                    return new EngineResponse(ResultCode.OK, AppStateLocalization.localizeRequest(body));
                case "snapshot":
                    return snapshot(userId, parsePackageLines(body));
                case "foregroundstate":
                    return foregroundState(userId, parsePackageLines(body));
                case "foregroundrunning":
                    return foregroundRunning(userId);
                case "foregroundlist":
                    return foregroundList(userId);
                case "foregroundtop":
                    return foregroundTop(userId);
                case "restore":
                    return restoreAppState(userId, body);
                case "verify":
                    return verifyAppState(userId, body);
                default:
                    return errorResponse(ResultCode.BAD_REQUEST, "dispatch", null,
                            "unknown command: " + safe(command));
            }
        } catch (IllegalArgumentException e) {
            return errorResponse(ResultCode.BAD_REQUEST, normalizeCommand(command), null, failureMessage(e));
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, normalizeCommand(command), null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, normalizeCommand(command), null, failureMessage(e));
        }
    }

    public static EngineResponse capabilities(boolean pretty) {
        JsonObject root = new JsonObject();
        root.addProperty("schemaVersion", SCHEMA_VERSION);
        root.addProperty("daemonProtocolVersion", DAEMON_PROTOCOL_VERSION);
        root.addProperty("engineVersion", ENGINE_VERSION);
        root.addProperty("dexVersion", HiddenApiUtil.VERSION);
        root.addProperty("mainClass", "com.xayah.dex.AppStateUtil");

        JsonArray resultCodes = new JsonArray();
        for (ResultCode code : ResultCode.values()) {
            JsonObject item = new JsonObject();
            item.addProperty("name", code.name());
            item.addProperty("code", code.code);
            item.addProperty("retryable", code.retryable);
            resultCodes.add(item);
        }
        root.add("resultCodes", resultCodes);

        JsonArray capabilities = new JsonArray();
        addCapability(capabilities, "dex.capabilities.v1", true, true, "json");
        addCapability(capabilities, "dex.machine_stdout.v1", true, true, "stdout=data-only;stderr=diagnostic");
        addCapability(capabilities, "appstate.snapshot.batch.v2", true, true, "canonical-ndjson");
        addCapability(capabilities, "appstate.snapshot.compact_persist.v1", true, true, "drop-non-restorable-display-fields");
        addCapability(capabilities, "appstate.foreground_state.batch.v1", true, false, "canonical-ndjson;simple-label+packageName+active");
        addCapability(capabilities, "appstate.foreground_state.simple_batch.v1", true, false, "app-items-only-label+packageName+active-boolean;no-uid-no-process-no-importance");
        addCapability(capabilities, "appstate.foreground_state.robust.v1", true, false, "hidden-iam-first+public-api-second+dumpsys-fallback;android9-17-target");
        addCapability(capabilities, "appstate.foreground_running.v1", true, false, "list-running-packages+importance+source");
        addCapability(capabilities, "appstate.foreground_list.json.v1", true, false, "single-json;top+foreground+foreground_service+active+background+cached;packageName+label");
        addCapability(capabilities, "appstate.foreground_list.simple_json.v1", true, false, "app-items-only-label+packageName;no-uid-no-process-no-importance");
        addCapability(capabilities, "appstate.foreground_top.v1", true, false, "focused-top-package+dumpsys-activity-window-fallback");
        addCapability(capabilities, "appstate.foreground_state.dumpsys_fallback.v1", true, false, "activity-processes+oom+activities+window");
        addCapability(capabilities, "appstate.shared_payload.v1", true, true, "snapshot=restore=verify");
        addCapability(capabilities, "appstate.special_access.integrated.v1", true, true, "snapshot+restore+verify");
        addCapability(capabilities, "appstate.restore.batch.v3", true, true, "canonical-ndjson+structured-items");
        addCapability(capabilities, "appstate.verify.batch.v3", true, true, "canonical-ndjson+structured-mismatch");
        addCapability(capabilities, "appstate.restore.batch.v4", true, true, "runtime-permission-uid-op+explicit-package-op");
        addCapability(capabilities, "appstate.verify.batch.v4", true, true, "effective-runtime-op+stable-flags");
        addCapability(capabilities, "appstate.appops_reset.integrated.v1", true, true, "package-scoped");
        addCapability(capabilities, "appstate.ssaid.integrated.v1", true, true, "snapshot+restore+verify");
        addCapability(capabilities, "appstate.daemon.af_unix.v1", true, true, "stream-framed");
        addCapability(capabilities, "appstate.daemon.runtime_preinit.v1", true, true, "context+pm+appops-before-ready");
        addCapability(capabilities, "dex.daemon_bootstrap.shared.v1", true, true, "appstate+notify+hiddenapi");
        addCapability(capabilities, "dex.daemon_bootstrap.sequential_guard.v1", true, true, "request-exception-does-not-kill-sequential-daemon");
        addCapability(capabilities, "dex.daemon_hardening.oom_protect.v1", true, true, "daemon best-effort oom_score_adj/renice self-protection");
        addCapability(capabilities, "dex.daemon_supervisor.watchdog.v1", true, true, "external Dex watchdog can restart killed root-side daemons while owner process is alive");
        addCapability(capabilities, "dex.http_util.get.v1", true, true, "short-lived HttpUtil get; used by tools Device_List sharded downloader");
        addCapability(capabilities, "dex.device_list.download.v1", false, false, "removed: batch device-list downloader aborted on some Android 16 app_process builds; tools use HttpUtil sharded downloader");
        addCapability(capabilities, "dex.google_package_snapshot.shared.v1", true, true, "install-diagnostics+appstate-verify");
        addCapability(capabilities, "appstate.structured_result_codes.v2", true, true, "result-header+package+item-ndjson");
        addCapability(capabilities, "appstate.scoped_appops_fields.v1", true, true, "packageMode+uidMode+effectiveMode");
        addCapability(capabilities, "appstate.explicit_package_mode_snapshot.v1", true, true, "getOpsForPackage-not-effective-check");
        addCapability(capabilities, "appstate.default_appop_missing_equivalent.v1", true, true, "missing-row-equals-mode-default");
        addCapability(capabilities, "appstate.permission_denied_item_partial.v1", true, true, "item-level-securityexception-does-not-poison-batch");
        addCapability(capabilities, "appstate.legacy_permission_normalize.v1", true, true, "skip-nonchangeable-grants+special-appop-permission-bridge");
        addCapability(capabilities, "appstate.non_ok_structured_body.v1", true, true, "daemon-body-kept-for-non-ok-package-results");
        addCapability(capabilities, "appstate.runtime_permission_uid_restore.v1", true, true, "clear-package+set-uid-effective-mode");
        addCapability(capabilities, "appstate.permission_flags.stable_mask.v1", true, true, "exclude-os-managed-revoked-compat");
        addCapability(capabilities, "appstate.special_access.deduplicated.v1", true, true, "special-op-owned-by-specialAccess");
        addCapability(capabilities, "appstate.localization.dex.v1", true, true, "permission+appops+mode+special-cn;raw-fields-preserved");
        addCapability(capabilities, "appstate.localization.raw_plus_cn.v1", true, true, "raw-machine-fields-plus-best-effort-cn-display-fields");
        addCapability(capabilities, "appstate.batch_preflight_validation.v1", true, true, "reject-before-mutation");
        addCapability(capabilities, "appstate.token_sections", false, false, "removed");
        addCapability(capabilities, "appops.reset.package_batch", false, false, "removed-from-public-surface");
        addCapability(capabilities, "webdav.rel_only.v1", true, true, "only *rel WebDAV operations are exposed for stream/atomic/data paths");
        addCapability(capabilities, "webdav.legacy_url_surface", false, false, "non-rel URL aliases removed: mkdirs/putstdin/putstdinchunked/getstdout/move/copy");
        addCapability(capabilities, "webdav.daemon.af_unix", true, true, "stream-framed");
        addCapability(capabilities, "webdav.daemon.mkcol_cache.v1", true, true, "per-daemon-url-cache");
        addCapability(capabilities, "webdav.daemon.list_cache.v1", true, true, "per-daemon-propfind-cache-invalidated-on-write");
        addCapability(capabilities, "webdav.putbatchrel.v1", true, true, "manifest-rel-to-localfile-batch-put");
        addCapability(capabilities, "webdav.managed_put.v1", true, true, "Dex-managed direct/atomic rel upload policy");
        addCapability(capabilities, "webdav.managed_probe.v1", true, true, "Dex-managed WebDAV stream capability probe");
        addCapability(capabilities, "webdav.rclone_json_direct_put.dex.v1", true, true, "rclone app_details.json direct PUT handled inside WebDavUtil");
        addCapability(capabilities, "webdav.rclone_direct_all.dex.v1", true, true, "rclone managed WebDAV uploads use direct PUT to avoid MOVE stat noise");
        addCapability(capabilities, "webdav.pan123_managed_direct.dex.v1", true, true, "123pan official WebDAV managed uploads use direct PUT to avoid .part MOVE HTTP 500");
        addCapability(capabilities, "webdav.compat_probe.v1", true, true, "Dex-side WebDAV OPTIONS/PUT/MOVE/STAT/GET/COPY/DELETE feature probe");
        addCapability(capabilities, "webdav.atomic_probe.v2", true, true, "PUT part + MOVE publish + GET byte compare + COPY + overwrite regression");
        addCapability(capabilities, "webdav.vendor_quirks.v1", true, true, "auto/rclone/nextcloud/jianguoyun/123pan/generic WebDAV quirk profile");
        addCapability(capabilities, "webdav.vendor_auto_detect.v1", true, true, "detect server profile from OPTIONS headers and observed probe behavior");
        addCapability(capabilities, "webdav.pacer_retry_backoff.v1", true, true, "bounded retry/backoff for replay-safe WebDAV control operations");
        addCapability(capabilities, "webdav.directory_cache.v1", true, true, "daemon directory exists/missing/failed state cache");
        addCapability(capabilities, "webdav.propfind_xml_tolerant.v2", true, true, "namespace/local-name PROPFIND parser with regex fallback");
        addCapability(capabilities, "webdav.error_policy_table.v1", true, true, "central MKCOL/MOVE/COPY/DELETE/OPTIONS/PROPFIND/HEAD policy table");
        addCapability(capabilities, "webdav.regression_suite.v1", true, true, "rclone serve WebDAV compat regression script contract");
        addCapability(capabilities, "webdav.buffer.autotune.v1", true, true, "legacy-compat");
        addCapability(capabilities, "webdav.buffer.autotune.v2", false, false, "rolled-back-after-ab-test");
        addCapability(capabilities, "webdav.buffer.autotune.v3", true, true, "256k-512k-1m-stable-cap");
        addCapability(capabilities, "webdav.socket.read_idle_timeout.v1", true, true, "socket-so-timeout-45s-no-infinite-read");
        addCapability(capabilities, "webdav.socket.write_idle_watchdog.v1", true, true, "close-origin-socket-when-request-write-stalls-45s");
        addCapability(capabilities, "webdav.empty_body_retry_before_payload", true, true, "internal");
        addCapability(capabilities, "notification.speedbackup_status", true, false, "notifyBatch");
        addCapability(capabilities, "hiddenapi.daemon.af_unix.v1", true, true, "getPackageUid+getInstallSourceInfo+installSessionCreate+installSessionCommit+forceStopPackageBatch");
        addCapability(capabilities, "hiddenapi.force_stop_package_batch.daemon.v1", true, true, "single-package-or-batch-force-stop-via-hiddenapi-daemon");
        addCapability(capabilities, "hiddenapi.daemon.response_body.capture.fix.v1", true, true, "ping+forceStopPackageBatch-body-returned-on-socket");
        addCapability(capabilities, "hiddenapi.install_session.hybrid_write.v1", true, true, "createSession=PlayUID;write=root;commit=PlayUID");
        addCapability(capabilities, "hiddenapi.install_session.batch", false, false, "removed in v2.6.4; use installSessionCreate/installSessionCommit");
        addCapability(capabilities, "hiddenapi.install_precheck_apks", false, false, "removed in v2.6.4; root pm install-write path does not need Play-readable APK precheck");
        addCapability(capabilities, "hiddenapi.hot_cli_removed.v1", true, true, "hot commands are daemon-only");
        addCapability(capabilities, "notification.daemon.af_unix.v1", true, true, "notifyBatch");
        addCapability(capabilities, "notification.hot_cli_removed.v1", true, true, "notifyBatch is daemon-only");
        addCapability(capabilities, "notification.app_settings_backup_restore", false, false, "removed");
        root.add("capabilities", capabilities);

        JsonArray specialKeys = new JsonArray();
        for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) {
            specialKeys.add(descriptor.key);
        }
        root.add("specialAccessKeys", specialKeys);

        return new EngineResponse(ResultCode.OK, (pretty ? PRETTY_GSON : GSON).toJson(root) + "\n");
    }

    @SuppressLint("ServiceCast")
    static EngineResponse snapshot(int userId, List<String> packageNames) {
        List<String> packages = dedupePackages(packageNames);
        if (packages.isEmpty()) {
            return batchSummaryOnly("snapshotAppStateBatch", ResultCode.BAD_REQUEST, 0, 0, 0, 0,
                    "no packages");
        }

        StringBuilder out = new StringBuilder();
        int ok = 0;
        int partial = 0;
        int failed = 0;
        try {
            RuntimeServices runtime = runtimeServices();
            PackageManager realPm = runtime.packageManager;
            PackageManagerHidden pmHidden = runtime.packageManagerHidden;
            AppOpsManagerHidden appOps = runtime.appOpsManager;
            Set<String> idleWhitelist = getDeviceIdleWhitelist();
            UserHandle user = UserHandleHidden.of(userId);
            GooglePackageSnapshot playStore = googlePackageSnapshot(
                    realPm, pmHidden, appOps, idleWhitelist, userId, "com.android.vending");
            GooglePackageSnapshot playServices = googlePackageSnapshot(
                    realPm, pmHidden, appOps, idleWhitelist, userId, "com.google.android.gms");

            for (String packageName : packages) {
                JsonObject record;
                try {
                    record = snapshotPackage(realPm, pmHidden, appOps, idleWhitelist, user, userId, packageName,
                            playStore, playServices);
                } catch (PackageManager.NameNotFoundException e) {
                    record = packageErrorRecord("snapshot", userId, packageName, ResultCode.PACKAGE_NOT_FOUND, failureMessage(e));
                } catch (SecurityException e) {
                    record = packageErrorRecord("snapshot", userId, packageName, ResultCode.PERMISSION_DENIED, failureMessage(e));
                } catch (Throwable e) {
                    record = packageErrorRecord("snapshot", userId, packageName, ResultCode.INTERNAL_ERROR, failureMessage(e));
                }
                ResultCode code = resultCodeFromRecord(record);
                if (code == ResultCode.OK) ok++;
                else if (code == ResultCode.PARTIAL) partial++;
                else failed++;
                out.append(GSON.toJson(record)).append('\n');
            }
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, "snapshotAppStateBatch", null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, "snapshotAppStateBatch", null, failureMessage(e));
        }

        ResultCode overall = failed > 0 || partial > 0 ? ResultCode.PARTIAL : ResultCode.OK;
        out.append(GSON.toJson(summaryRecord("snapshotAppStateBatch", overall, packages.size(), ok, partial, failed, null))).append('\n');

        return new EngineResponse(overall, out.toString());
    }

    @SuppressLint("ServiceCast")
    static EngineResponse foregroundState(int userId, List<String> packageNames) {
        List<String> packages = dedupePackages(packageNames);
        if (packages.isEmpty()) {
            return batchSummaryOnly("foregroundStateBatch", ResultCode.BAD_REQUEST, 0, 0, 0, 0,
                    "no packages");
        }

        StringBuilder out = new StringBuilder();
        int ok = 0;
        int partial = 0;
        int failed = 0;
        try {
            RuntimeServices runtime = runtimeServices();
            PackageManager realPm = runtime.packageManager;
            PackageManagerHidden pmHidden = runtime.packageManagerHidden;
            Set<String> requested = new LinkedHashSet<>(packages);
            RunningProcessSnapshot running = getForegroundProcessSnapshot(runtime.context, userId, requested, true);
            Map<String, List<ForegroundProcess>> byPackage = indexForegroundProcesses(running.processes, userId);

            for (String packageName : packages) {
                JsonObject record;
                try {
                    PackageInfo packageInfo = null;
                    try { packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId); } catch (Throwable ignored) {}
                    record = foregroundStatePackageSimple(realPm, packageInfo, packageName, byPackage.get(packageName));
                    ok++;
                } catch (Throwable e) {
                    record = foregroundStatePackageSimple(realPm, null, packageName, null);
                    ok++;
                }
                out.append(GSON.toJson(record)).append('\n');
            }
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, "foregroundStateBatch", null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, "foregroundStateBatch", null, failureMessage(e));
        }

        ResultCode overall = failed > 0 || partial > 0 ? ResultCode.PARTIAL : ResultCode.OK;
        out.append(GSON.toJson(summaryRecord("foregroundStateBatch", overall, packages.size(), ok, partial, failed, null))).append('\n');
        return new EngineResponse(overall, out.toString());
    }

    static EngineResponse foregroundRunning(int userId) {
        StringBuilder out = new StringBuilder();
        int ok = 0;
        int failed = 0;
        try {
            RuntimeServices runtime = runtimeServices();
            RunningProcessSnapshot snapshot = getForegroundProcessSnapshot(runtime.context, userId, Collections.<String>emptySet(), true);
            Map<String, List<ForegroundProcess>> byPackage = indexForegroundProcesses(snapshot.processes, userId);
            PackageManagerHidden pmHidden = runtime.packageManagerHidden;
            List<String> packages = new ArrayList<>(byPackage.keySet());
            Collections.sort(packages);
            for (String packageName : packages) {
                JsonObject record;
                try {
                    PackageInfo packageInfo = null;
                    try { packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId); } catch (Throwable ignored) {}
                    record = foregroundStatePackage(packageInfo, packageName, userId, byPackage.get(packageName), snapshot);
                } catch (Throwable e) {
                    record = packageErrorRecord("foregroundState", userId, packageName, ResultCode.INTERNAL_ERROR, failureMessage(e));
                }
                ResultCode code = resultCodeFromRecord(record);
                if (code == ResultCode.OK) ok++; else failed++;
                out.append(GSON.toJson(record)).append('\n');
            }
            ResultCode overall = failed > 0 ? ResultCode.PARTIAL : ResultCode.OK;
            out.append(GSON.toJson(summaryRecord("foregroundStateRunning", overall, packages.size(), ok, 0, failed,
                    "source=" + snapshot.source + ";dumpsysFallback=" + snapshot.dumpsysFallbackUsed))).append('\n');
            return new EngineResponse(overall, out.toString());
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, "foregroundStateRunning", null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, "foregroundStateRunning", null, failureMessage(e));
        }
    }

    static EngineResponse foregroundList(int userId) {
        try {
            RuntimeServices runtime = runtimeServices();
            RunningProcessSnapshot snapshot = getForegroundProcessSnapshot(runtime.context, userId, Collections.<String>emptySet(), true);
            Map<String, List<ForegroundProcess>> byPackage = indexForegroundProcessesForList(snapshot.processes, userId);
            PackageManagerHidden pmHidden = runtime.packageManagerHidden;
            PackageManager pm = runtime.packageManager;

            JsonObject root = new JsonObject();
            root.addProperty("schemaVersion", SCHEMA_VERSION);
            root.addProperty("engineVersion", ENGINE_VERSION);
            root.addProperty("dexVersion", HiddenApiUtil.VERSION);
            root.addProperty("recordType", "foregroundList");
            root.addProperty("userId", userId);
            root.addProperty("stateSource", snapshot.source);
            root.addProperty("dumpsysFallbackUsed", snapshot.dumpsysFallbackUsed);
            if (!snapshot.note.isEmpty()) root.addProperty("stateNote", snapshot.note);

            JsonArray topArray = new JsonArray();
            JsonArray foregroundArray = new JsonArray();
            JsonArray foregroundServiceArray = new JsonArray();
            JsonArray activeArray = new JsonArray();
            JsonArray backgroundArray = new JsonArray();
            JsonArray cachedArray = new JsonArray();

            TopApp top = findTopApp(userId);
            if (top != null && !top.packageName.isEmpty()) {
                JsonObject topItem = foregroundTopListItem(pm, pmHidden, userId, top);
                if (topItem != null) topArray.add(topItem);
            }

            List<String> packages = new ArrayList<>(byPackage.keySet());
            Collections.sort(packages);
            int skipped = 0;
            for (String packageName : packages) {
                List<ForegroundProcess> processes = byPackage.get(packageName);
                if (processes == null || processes.isEmpty()) continue;
                PackageInfo packageInfo = null;
                try { packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId); } catch (Throwable ignored) {}
                if (!isForegroundListPackage(packageInfo)) {
                    skipped++;
                    continue;
                }
                String category = foregroundListBestCategory(processes);
                if (category.isEmpty()) {
                    skipped++;
                    continue;
                }
                JsonObject item = foregroundListItem(pm, packageInfo, packageName, userId, processes);
                if (item == null) {
                    skipped++;
                    continue;
                }
                if ("foreground".equals(category)) foregroundArray.add(item);
                else if ("foreground_service".equals(category)) foregroundServiceArray.add(item);
                else if ("active".equals(category)) activeArray.add(item);
                else if ("background".equals(category)) backgroundArray.add(item);
                else if ("cached".equals(category)) cachedArray.add(item);
                else skipped++;
            }

            root.add("top", topArray);
            root.add("foreground", foregroundArray);
            root.add("foreground_service", foregroundServiceArray);
            root.add("active", activeArray);
            root.add("background", backgroundArray);
            root.add("cached", cachedArray);
            JsonObject counts = new JsonObject();
            counts.addProperty("top", topArray.size());
            counts.addProperty("foreground", foregroundArray.size());
            counts.addProperty("foreground_service", foregroundServiceArray.size());
            counts.addProperty("active", activeArray.size());
            counts.addProperty("background", backgroundArray.size());
            counts.addProperty("cached", cachedArray.size());
            counts.addProperty("shown", topArray.size() + foregroundArray.size() + foregroundServiceArray.size()
                    + activeArray.size() + backgroundArray.size() + cachedArray.size());
            counts.addProperty("skipped", skipped);
            root.add("counts", counts);
            setResult(root, ResultCode.OK, null);
            return new EngineResponse(ResultCode.OK, GSON.toJson(root) + "\n");
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, "foregroundListJson", null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, "foregroundListJson", null, failureMessage(e));
        }
    }

    static EngineResponse foregroundTop(int userId) {
        StringBuilder out = new StringBuilder();
        try {
            TopApp top = findTopApp(userId);
            JsonObject root = baseRecord("foregroundTop", userId, top == null ? "" : top.packageName);
            if (top == null || top.packageName.isEmpty()) {
                root.addProperty("running", false);
                root.addProperty("foreground", false);
                root.addProperty("background", false);
                root.addProperty("top", false);
                root.addProperty("source", "none");
                addJsonNull(root, "topActivity");
                setResult(root, ResultCode.PARTIAL, "top app not found");
                out.append(GSON.toJson(root)).append('\n');
                out.append(GSON.toJson(summaryRecord("foregroundTop", ResultCode.PARTIAL, 1, 0, 1, 0, "top app not found"))).append('\n');
                return new EngineResponse(ResultCode.PARTIAL, out.toString());
            }
            root.addProperty("top", true);
            root.addProperty("running", true);
            root.addProperty("foreground", true);
            root.addProperty("background", false);
            root.addProperty("topActivity", top.activityName);
            root.addProperty("source", top.source);
            root.addProperty("raw", safe(top.raw));
            setResult(root, ResultCode.OK, null);
            out.append(GSON.toJson(root)).append('\n');
            out.append(GSON.toJson(summaryRecord("foregroundTop", ResultCode.OK, 1, 1, 0, 0, null))).append('\n');
            return new EngineResponse(ResultCode.OK, out.toString());
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, "foregroundTop", null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, "foregroundTop", null, failureMessage(e));
        }
    }

    @SuppressWarnings("unchecked")
    private static List<ActivityManager.RunningAppProcessInfo> getRunningAppProcessesHidden() throws Exception {
        Object raw = HiddenApiReflection.invokeFlexible(HiddenApiServices.activity(), "getRunningAppProcesses");
        if (raw instanceof List) return (List<ActivityManager.RunningAppProcessInfo>) raw;
        if (raw != null) {
            try {
                Object inner = HiddenApiReflection.invokeFlexible(raw, "getList");
                if (inner instanceof List) return (List<ActivityManager.RunningAppProcessInfo>) inner;
            } catch (Throwable ignored) {
                // Keep original unsupported error below.
            }
        }
        throw new UnsupportedOperationException("IActivityManager.getRunningAppProcesses unavailable");
    }

    private static List<ActivityManager.RunningAppProcessInfo> getRunningAppProcessesPublic(Context context) throws Exception {
        ActivityManager activityManager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        if (activityManager == null) throw new UnsupportedOperationException("ACTIVITY_SERVICE unavailable");
        List<ActivityManager.RunningAppProcessInfo> list = activityManager.getRunningAppProcesses();
        if (list == null) throw new UnsupportedOperationException("ActivityManager returned null");
        return list;
    }

    private static RunningProcessSnapshot getForegroundProcessSnapshot(Context context, int userId,
                                                                       Set<String> requestedPackages,
                                                                       boolean allowDumpsys) {
        List<ForegroundProcess> out = new ArrayList<>();
        StringBuilder sources = new StringBuilder();
        StringBuilder notes = new StringBuilder();
        boolean dumpsysUsed = false;
        try {
            List<ActivityManager.RunningAppProcessInfo> hidden = getRunningAppProcessesHidden();
            List<ForegroundProcess> converted = convertRunningAppProcesses(hidden, userId, "hidden_iam");
            if (!converted.isEmpty()) {
                mergeProcesses(out, converted);
                sources.append("hidden_iam");
            }
        } catch (Throwable e) {
            notes.append("hidden_iam=").append(e.getClass().getSimpleName()).append(';');
        }
        if (out.isEmpty()) {
            try {
                List<ActivityManager.RunningAppProcessInfo> pub = getRunningAppProcessesPublic(context);
                List<ForegroundProcess> converted = convertRunningAppProcesses(pub, userId, "public_activity_manager");
                if (!converted.isEmpty()) {
                    mergeProcesses(out, converted);
                    sources.append(sources.length() > 0 ? "+public_activity_manager" : "public_activity_manager");
                }
            } catch (Throwable e) {
                notes.append("public_activity_manager=").append(e.getClass().getSimpleName()).append(';');
            }
        }
        if (allowDumpsys && shouldUseDumpsysFallback(out, requestedPackages)) {
            List<ForegroundProcess> dump = getDumpsysRunningProcesses(userId);
            if (!dump.isEmpty()) {
                mergeProcesses(out, dump);
                sources.append(sources.length() > 0 ? "+dumpsys_activity" : "dumpsys_activity");
                dumpsysUsed = true;
            } else {
                notes.append("dumpsys_activity=empty;");
            }
        }
        return new RunningProcessSnapshot(out, sources.toString(), dumpsysUsed, notes.toString());
    }

    private static boolean shouldUseDumpsysFallback(List<ForegroundProcess> current, Set<String> requestedPackages) {
        if (current == null || current.isEmpty()) return true;
        if (requestedPackages == null || requestedPackages.isEmpty()) return false;
        // For small direct probes, a non-empty but filtered public list is a common cross-ROM failure mode.
        // Re-check with dumpsys only when none of the requested packages appeared.
        if (requestedPackages.size() <= 10) {
            for (ForegroundProcess process : current) {
                if (requestedPackages.contains(process.packageName)) return false;
            }
            return true;
        }
        return false;
    }

    private static List<ForegroundProcess> convertRunningAppProcesses(
            List<ActivityManager.RunningAppProcessInfo> running, int userId, String source) {
        List<ForegroundProcess> out = new ArrayList<>();
        if (running == null) return out;
        for (ActivityManager.RunningAppProcessInfo info : running) {
            if (info == null) continue;
            int procUserId = getUserIdFromUid(info.uid);
            if (userId >= 0 && procUserId != userId) continue;
            String[] pkgList = info.pkgList;
            if (pkgList == null || pkgList.length == 0) {
                String procName = info.processName == null ? "" : info.processName.trim();
                String pkg = packageFromProcessName(procName);
                if (!pkg.isEmpty()) pkgList = new String[]{pkg};
            }
            if (pkgList == null) continue;
            for (String pkg : pkgList) {
                if (pkg == null || pkg.trim().isEmpty()) continue;
                out.add(new ForegroundProcess(pkg.trim(), safe(info.processName), info.pid, info.uid, procUserId,
                        info.importance, safeProcessState(info), info.importanceReasonCode, source));
            }
        }
        return out;
    }

    private static int safeProcessState(ActivityManager.RunningAppProcessInfo info) {
        if (info == null) return -1;
        try {
            java.lang.reflect.Field field = ActivityManager.RunningAppProcessInfo.class.getDeclaredField("processState");
            field.setAccessible(true);
            Object value = field.get(info);
            if (value instanceof Number) return ((Number) value).intValue();
        } catch (Throwable ignored) {
        }
        return -1;
    }

    private static Map<String, List<ForegroundProcess>> indexForegroundProcesses(List<ForegroundProcess> running, int userId) {
        Map<String, List<ForegroundProcess>> out = new LinkedHashMap<>();
        if (running == null) return out;
        for (ForegroundProcess info : running) {
            if (info == null) continue;
            if (userId >= 0 && info.userId != userId) continue;
            if (info.packageName == null || info.packageName.trim().isEmpty()) continue;
            List<ForegroundProcess> bucket = out.get(info.packageName);
            if (bucket == null) {
                bucket = new ArrayList<>();
                out.put(info.packageName, bucket);
            }
            bucket.add(info);
        }
        return out;
    }


    private static JsonObject foregroundStatePackageSimple(PackageManager pm, PackageInfo packageInfo,
                                                           String packageName,
                                                           List<ForegroundProcess> processes) {
        JsonObject root = new JsonObject();
        String pkg = safe(packageName);
        root.addProperty("recordType", "foregroundState");
        root.addProperty("label", appLabelOrPackage(pm, packageInfo, pkg));
        root.addProperty("packageName", pkg);
        root.addProperty("active", processes != null && !processes.isEmpty());
        return root;
    }

    private static JsonObject foregroundStatePackage(PackageInfo packageInfo, String packageName, int userId,
                                                     List<ForegroundProcess> processes,
                                                     RunningProcessSnapshot snapshot) {
        JsonObject root = baseRecord("foregroundState", userId, packageName);
        int bestImportance = 1000;
        int bestProcessState = Integer.MAX_VALUE;
        int bestUid = -1;
        boolean running = processes != null && !processes.isEmpty();
        JsonArray processArray = new JsonArray();
        Set<String> sources = new LinkedHashSet<>();
        if (processes != null) {
            for (ForegroundProcess info : processes) {
                if (info == null) continue;
                sources.add(info.source);
                JsonObject item = new JsonObject();
                item.addProperty("pid", info.pid);
                item.addProperty("uid", info.uid);
                item.addProperty("userId", info.userId);
                item.addProperty("processName", safe(info.processName));
                item.addProperty("importance", info.importance);
                item.addProperty("importanceBucket", importanceBucket(info.importance));
                item.addProperty("foreground", isForegroundImportance(info.importance));
                item.addProperty("background", isBackgroundImportance(info.importance));
                item.addProperty("processState", info.processState);
                item.addProperty("importanceReasonCode", info.importanceReasonCode);
                item.addProperty("source", info.source);
                processArray.add(item);
                if (info.importance > 0 && info.importance < bestImportance) bestImportance = info.importance;
                if (info.processState >= 0 && info.processState < bestProcessState) bestProcessState = info.processState;
                if (bestUid < 0 && info.uid >= 0) bestUid = info.uid;
            }
        }
        if (!running) {
            bestImportance = 1000;
            bestProcessState = -1;
        } else if (bestProcessState == Integer.MAX_VALUE) {
            bestProcessState = -1;
        }
        boolean foreground = running && isForegroundImportance(bestImportance);
        boolean background = running && !foreground;
        int packageUid = -1;
        try {
            if (packageInfo != null && packageInfo.applicationInfo != null) packageUid = packageInfo.applicationInfo.uid;
        } catch (Throwable ignored) {}
        if (packageUid < 0) packageUid = bestUid;
        root.addProperty("packageUid", packageUid);
        root.addProperty("running", running);
        root.addProperty("foreground", foreground);
        root.addProperty("background", background);
        root.addProperty("importance", bestImportance);
        root.addProperty("importanceBucket", importanceBucket(bestImportance));
        root.addProperty("processState", bestProcessState);
        root.addProperty("stateSource", snapshot == null ? "unknown" : snapshot.source);
        root.addProperty("dumpsysFallbackUsed", snapshot != null && snapshot.dumpsysFallbackUsed);
        if (snapshot != null && !snapshot.note.isEmpty()) root.addProperty("stateNote", snapshot.note);
        JsonArray sourceArray = new JsonArray();
        for (String source : sources) sourceArray.add(source);
        root.add("sources", sourceArray);
        root.add("processes", processArray);
        setResult(root, ResultCode.OK, null);
        return root;
    }

    private static Map<String, List<ForegroundProcess>> indexForegroundProcessesForList(List<ForegroundProcess> running, int userId) {
        Map<String, List<ForegroundProcess>> out = new LinkedHashMap<>();
        if (running == null) return out;
        for (ForegroundProcess info : running) {
            if (info == null) continue;
            if (userId >= 0 && info.userId != userId) continue;
            String category = foregroundListCategory(info.importance);
            if (category.isEmpty()) continue;
            if (!isPrimaryProcessPackage(info)) continue;
            String packageName = safe(info.packageName);
            if (packageName.isEmpty()) continue;
            List<ForegroundProcess> bucket = out.get(packageName);
            if (bucket == null) {
                bucket = new ArrayList<>();
                out.put(packageName, bucket);
            }
            bucket.add(info);
        }
        return out;
    }

    private static boolean isPrimaryProcessPackage(ForegroundProcess info) {
        if (info == null) return false;
        String pkg = safe(info.packageName);
        String proc = safe(info.processName);
        if (pkg.isEmpty()) return false;
        if (proc.isEmpty()) return true;
        if (proc.equals(pkg) || proc.startsWith(pkg + ":")) return true;
        String fromProcess = packageFromProcessName(proc);
        return pkg.equals(fromProcess);
    }

    private static boolean isForegroundListPackage(PackageInfo packageInfo) {
        if (packageInfo == null || packageInfo.applicationInfo == null) return false;
        String pkg = safe(packageInfo.packageName);
        if (pkg.isEmpty() || "android".equals(pkg)) return false;
        int uid = packageInfo.applicationInfo.uid;
        // Drop core/shared system UIDs. User-visible system apps normally still have app UIDs >= 10000.
        return uid >= 10000;
    }

    private static JsonObject foregroundTopListItem(PackageManager pm, PackageManagerHidden pmHidden, int userId, TopApp top) {
        if (top == null || top.packageName.isEmpty()) return null;
        PackageInfo packageInfo = null;
        try { packageInfo = pmHidden.getPackageInfoAsUser(top.packageName, 0, userId); } catch (Throwable ignored) {}
        if (!isForegroundListPackage(packageInfo)) return null;
        JsonObject item = new JsonObject();
        item.addProperty("label", appLabelOrPackage(pm, packageInfo, top.packageName));
        item.addProperty("packageName", top.packageName);
        return item;
    }

    private static JsonObject foregroundListItem(PackageManager pm, PackageInfo packageInfo, String packageName,
                                                 int userId, List<ForegroundProcess> processes) {
        if (processes == null || processes.isEmpty()) return null;
        if (foregroundListBestCategory(processes).isEmpty()) return null;
        JsonObject item = new JsonObject();
        item.addProperty("label", appLabelOrPackage(pm, packageInfo, packageName));
        item.addProperty("packageName", packageName);
        return item;
    }

    private static String foregroundListBestCategory(List<ForegroundProcess> processes) {
        if (processes == null || processes.isEmpty()) return "";
        int bestImportance = 1000;
        for (ForegroundProcess info : processes) {
            if (info == null) continue;
            if (info.importance > 0 && info.importance < bestImportance) {
                bestImportance = info.importance;
            }
        }
        return foregroundListCategory(bestImportance);
    }

    private static String appLabelOrPackage(PackageManager pm, PackageInfo packageInfo, String packageName) {
        String label = "";
        try {
            if (packageInfo != null && packageInfo.applicationInfo != null) {
                label = safeLabel(pm, packageInfo.applicationInfo);
            }
        } catch (Throwable ignored) {}
        return label == null || label.isEmpty() ? safe(packageName) : label;
    }

    private static String foregroundListCategory(int importance) {
        if (importance <= 0) return "";
        if (importance <= 100) return "foreground";
        if (importance <= 125) return "foreground_service";
        if (importance <= 230) return "active";
        if (importance <= 350) return "background";
        if (importance < 1000) return "cached";
        return "";
    }

    private static void mergeProcesses(List<ForegroundProcess> out, List<ForegroundProcess> input) {
        if (out == null || input == null) return;
        Set<String> existing = new HashSet<>();
        for (ForegroundProcess p : out) existing.add(processKey(p));
        for (ForegroundProcess p : input) {
            String key = processKey(p);
            if (existing.add(key)) out.add(p);
        }
    }

    private static String processKey(ForegroundProcess p) {
        if (p == null) return "null";
        return p.packageName + "#" + p.processName + "#" + p.pid + "#" + p.uid;
    }

    private static final Pattern DUMPSYS_PROC_TOKEN = Pattern.compile("\\b([0-9]{2,7}):([A-Za-z0-9_.$:-]+)/(u\\d+a\\d+|u\\d+s\\d+|u\\d+i\\d+|u\\d+|system|root|[0-9]+)\\b");
    private static final Pattern TOP_USER_PACKAGE_ACTIVITY = Pattern.compile("\\bu(\\d+)\\s+([A-Za-z0-9_.]+)/(\\S+)");
    private static final Pattern TOP_PACKAGE_ACTIVITY = Pattern.compile("\\b([A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+)/(\\S+)");

    private static List<ForegroundProcess> getDumpsysRunningProcesses(int userId) {
        List<ForegroundProcess> out = new ArrayList<>();
        String dump = runShellOutput("dumpsys activity processes; dumpsys activity oom");
        if (dump == null || dump.isEmpty()) return out;
        BufferedReader reader = new BufferedReader(new java.io.StringReader(dump));
        try {
            String line;
            while ((line = reader.readLine()) != null) {
                Matcher matcher = DUMPSYS_PROC_TOKEN.matcher(line);
                while (matcher.find()) {
                    int pid = parseInt(matcher.group(1), -1);
                    String processName = matcher.group(2);
                    String pkg = packageFromProcessName(processName);
                    UidParts uidParts = decodeDumpsysUid(matcher.group(3));
                    int procUserId = uidParts.userId >= 0 ? uidParts.userId : 0;
                    if (userId >= 0 && procUserId != userId) continue;
                    int importance = inferImportanceFromDumpsysLine(line);
                    out.add(new ForegroundProcess(pkg, processName, pid, uidParts.uid, procUserId,
                            importance, -1, 0, "dumpsys_activity"));
                }
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    private static TopApp findTopApp(int userId) {
        TopApp top = findTopAppInDump(userId, "dumpsys activity activities", "dumpsys_activity");
        if (top != null) return top;
        top = findTopAppInDump(userId, "dumpsys window windows", "dumpsys_window");
        if (top != null) return top;
        top = findTopAppInDump(userId, "dumpsys activity top", "dumpsys_activity_top");
        return top;
    }

    private static TopApp findTopAppInDump(int userId, String command, String source) {
        String dump = runShellOutput(command);
        if (dump == null || dump.isEmpty()) return null;
        String[] lines = dump.split("\\r?\\n");
        String[] preferred = new String[]{"topresumedactivity", "mresumedactivity", "resumedactivity", "mcurrentfocus", "mfocusedapp"};
        for (String key : preferred) {
            for (String line : lines) {
                if (line == null) continue;
                String lower = line.toLowerCase(Locale.ROOT);
                if (!lower.contains(key)) continue;
                TopApp parsed = parseTopAppLine(line, userId, source);
                if (parsed != null) return parsed;
            }
        }
        for (String line : lines) {
            TopApp parsed = parseTopAppLine(line, userId, source);
            if (parsed != null) return parsed;
        }
        return null;
    }

    private static TopApp parseTopAppLine(String line, int userId, String source) {
        if (line == null) return null;
        Matcher userMatcher = TOP_USER_PACKAGE_ACTIVITY.matcher(line);
        while (userMatcher.find()) {
            int lineUser = parseInt(userMatcher.group(1), -1);
            if (userId >= 0 && lineUser != userId) continue;
            String pkg = userMatcher.group(2);
            String activity = normalizeActivityName(pkg, userMatcher.group(3));
            return new TopApp(pkg, activity, lineUser, source, line);
        }
        Matcher plainMatcher = TOP_PACKAGE_ACTIVITY.matcher(line);
        while (plainMatcher.find()) {
            String pkg = plainMatcher.group(1);
            if (pkg.startsWith("android.")) continue;
            String activity = normalizeActivityName(pkg, plainMatcher.group(2));
            return new TopApp(pkg, activity, userId, source, line);
        }
        return null;
    }

    private static String normalizeActivityName(String pkg, String rawActivity) {
        String value = rawActivity == null ? "" : rawActivity;
        int end = value.length();
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (Character.isWhitespace(c) || c == '}' || c == ']') { end = i; break; }
        }
        value = value.substring(0, end);
        if (value.startsWith(".")) return pkg + value;
        return value;
    }

    private static String packageFromProcessName(String processName) {
        if (processName == null) return "";
        String value = processName.trim();
        int colon = value.indexOf(':');
        if (colon > 0) value = value.substring(0, colon);
        return value.matches("[A-Za-z0-9_.-]+") ? value : "";
    }

    private static int inferImportanceFromDumpsysLine(String line) {
        String lower = line == null ? "" : line.toLowerCase(Locale.ROOT);
        if (lower.contains("top") || lower.contains("top-activity") || lower.contains("mresumedactivity")) return 100;
        if (lower.contains("fg-service") || lower.contains("fgs") || lower.contains("foreground service")) return 125;
        if (lower.contains("vis") || lower.contains("visible")) return 200;
        if (lower.contains("perceptible") || lower.contains("prcp")) return 230;
        if (lower.contains("cached") || lower.contains("cch")) return 400;
        if (lower.contains("service") || lower.contains("svc")) return 300;
        return 400;
    }

    private static String runShellOutput(String command) {
        Process process = null;
        try {
            ProcessBuilder builder = new ProcessBuilder("sh", "-c", command);
            builder.redirectErrorStream(true);
            process = builder.start();
            StringBuilder out = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) out.append(line).append('\n');
            }
            try {
                if (!process.waitFor(8, TimeUnit.SECONDS)) process.destroy();
            } catch (Throwable ignored) {
                try { process.waitFor(); } catch (Throwable ignored2) {}
            }
            return out.toString();
        } catch (Throwable ignored) {
            if (process != null) try { process.destroy(); } catch (Throwable ignored2) {}
            return "";
        }
    }

    private static final class UidParts {
        final int uid;
        final int userId;
        UidParts(int uid, int userId) { this.uid = uid; this.userId = userId; }
    }

    private static UidParts decodeDumpsysUid(String raw) {
        if (raw == null) return new UidParts(-1, -1);
        String value = raw.trim();
        try {
            if (value.startsWith("u") && value.contains("a")) {
                int a = value.indexOf('a');
                int user = parseInt(value.substring(1, a), 0);
                int app = parseInt(value.substring(a + 1), -1);
                return new UidParts(app >= 0 ? user * 100000 + 10000 + app : -1, user);
            }
            if (value.startsWith("u") && value.contains("s")) {
                int s = value.indexOf('s');
                int user = parseInt(value.substring(1, s), 0);
                int sys = parseInt(value.substring(s + 1), -1);
                return new UidParts(sys >= 0 ? user * 100000 + sys : -1, user);
            }
            if (value.startsWith("u") && value.length() > 1) {
                int user = parseInt(value.substring(1).replaceAll("[^0-9].*", ""), 0);
                return new UidParts(-1, user);
            }
            if ("system".equals(value)) return new UidParts(1000, 0);
            if ("root".equals(value)) return new UidParts(0, 0);
            int uid = parseInt(value, -1);
            return new UidParts(uid, uid >= 100000 ? uid / 100000 : 0);
        } catch (Throwable ignored) {
            return new UidParts(-1, -1);
        }
    }

    private static int parseInt(String value, int fallback) {
        try { return Integer.parseInt(value); } catch (Throwable ignored) { return fallback; }
    }

    private static int getUserIdFromUid(int uid) {
        try { return UserHandleHidden.getUserId(uid); } catch (Throwable ignored) {}
        if (uid >= 100000) return uid / 100000;
        return 0;
    }

    private static boolean isForegroundImportance(int importance) {
        return importance > 0 && importance <= 200;
    }

    private static boolean isBackgroundImportance(int importance) {
        return importance > 200 && importance < 1000;
    }

    private static String importanceBucket(int importance) {
        if (importance <= 0) return "unknown";
        if (importance <= 100) return "foreground";
        if (importance <= 125) return "foreground_service";
        if (importance <= 200) return "visible";
        if (importance <= 230) return "perceptible";
        if (importance <= 350) return "background";
        if (importance < 1000) return "cached";
        return "not_running";
    }

    static EngineResponse restoreAppState(int userId, String body) {
        return processCanonicalBatch("restoreAppStateBatch", userId, body, false);
    }

    static EngineResponse verifyAppState(int userId, String body) {
        return processCanonicalBatch("verifyAppStateBatch", userId, body, true);
    }

    @SuppressLint("ServiceCast")
    private static EngineResponse processCanonicalBatch(String command, int userId, String body, boolean verifyOnly) {
        final List<JsonObject> records;
        try {
            records = parseJsonRecords(body);
        } catch (IllegalArgumentException e) {
            return errorResponse(ResultCode.BAD_REQUEST, command, null, failureMessage(e));
        }
        if (records.isEmpty()) {
            return batchSummaryOnly(command, ResultCode.BAD_REQUEST, 0, 0, 0, 0,
                    "no canonical AppState records");
        }

        // Validate the complete batch before obtaining mutable services or touching any package.
        // A malformed/schema-incompatible record rejects the whole request with BAD_REQUEST.
        for (int i = 0; i < records.size(); i++) {
            JsonObject desired = records.get(i);
            String packageName = stringMember(desired, "packageName");
            try {
                validateCanonicalRecord(desired, packageName);
            } catch (IllegalArgumentException e) {
                return batchSummaryOnly(command, ResultCode.BAD_REQUEST, records.size(), 0, 0,
                        records.size(), "record=" + (i + 1) + " " + failureMessage(e));
            }
        }

        StringBuilder out = new StringBuilder();
        int ok = 0;
        int partial = 0;
        int failed = 0;
        ResultCode uniformFailure = null;
        boolean mixedFailures = false;
        try {
            RuntimeServices runtime = runtimeServices();
            PackageManager realPm = runtime.packageManager;
            PackageManagerHidden pmHidden = runtime.packageManagerHidden;
            AppOpsManagerHidden appOps = runtime.appOpsManager;
            UserHandle user = UserHandleHidden.of(userId);
            Set<String> idleWhitelist = getDeviceIdleWhitelist();
            GooglePackageSnapshot playStore = verifyOnly
                    ? googlePackageSnapshot(realPm, pmHidden, appOps, idleWhitelist, userId, "com.android.vending")
                    : null;
            GooglePackageSnapshot playServices = verifyOnly
                    ? googlePackageSnapshot(realPm, pmHidden, appOps, idleWhitelist, userId, "com.google.android.gms")
                    : null;

            for (JsonObject desired : records) {
                String packageName = stringMember(desired, "packageName");
                JsonObject result;
                try {
                    result = verifyOnly
                            ? verifyPackageState(realPm, pmHidden, appOps, user, userId, packageName,
                            desired, playStore, playServices)
                            : restorePackageState(realPm, pmHidden, appOps, user, userId, packageName, desired);
                } catch (PackageManager.NameNotFoundException e) {
                    result = packageErrorRecord(verifyOnly ? "verify" : "restore", userId, packageName,
                            ResultCode.PACKAGE_NOT_FOUND, failureMessage(e));
                } catch (IllegalArgumentException e) {
                    result = packageErrorRecord(verifyOnly ? "verify" : "restore", userId, packageName,
                            ResultCode.BAD_REQUEST, failureMessage(e));
                } catch (SecurityException e) {
                    result = packageErrorRecord(verifyOnly ? "verify" : "restore", userId, packageName,
                            ResultCode.PERMISSION_DENIED, failureMessage(e));
                } catch (Throwable e) {
                    result = packageErrorRecord(verifyOnly ? "verify" : "restore", userId, packageName,
                            ResultCode.INTERNAL_ERROR, failureMessage(e));
                }
                ResultCode code = resultCodeFromRecord(result);
                if (code == ResultCode.OK) {
                    ok++;
                } else if (code == ResultCode.PARTIAL || code == ResultCode.VERIFY_MISMATCH) {
                    partial++;
                } else {
                    failed++;
                    if (uniformFailure == null) uniformFailure = code;
                    else if (uniformFailure != code) mixedFailures = true;
                }
                out.append(GSON.toJson(result)).append('\n');
            }
        } catch (SecurityException e) {
            return errorResponse(ResultCode.PERMISSION_DENIED, command, null, failureMessage(e));
        } catch (Throwable e) {
            return errorResponse(ResultCode.INTERNAL_ERROR, command, null, failureMessage(e));
        }

        ResultCode overall;
        if (failed == records.size() && partial == 0 && ok == 0
                && uniformFailure != null && !mixedFailures) {
            // Preserve a homogeneous terminal error in the daemon RESULT header and one-shot exit code.
            overall = uniformFailure;
        } else if (failed > 0) {
            overall = ResultCode.PARTIAL;
        } else if (partial > 0) {
            overall = verifyOnly ? ResultCode.VERIFY_MISMATCH : ResultCode.PARTIAL;
        } else {
            overall = ResultCode.OK;
        }
        out.append(GSON.toJson(summaryRecord(command, overall, records.size(), ok, partial, failed, null))).append('\n');
        return new EngineResponse(overall, out.toString());
    }

    private static void validateCanonicalRecord(JsonObject record, String packageName) {
        if (record == null) throw new IllegalArgumentException("record is null");
        if (packageName == null || packageName.trim().isEmpty()) {
            throw new IllegalArgumentException("packageName is empty");
        }
        int schema = intMember(record, "schemaVersion", -1);
        if (schema != SCHEMA_VERSION) {
            throw new IllegalArgumentException("unsupported schemaVersion=" + schema);
        }
        if (!"snapshot".equals(stringMember(record, "recordType"))) {
            throw new IllegalArgumentException("recordType must be snapshot");
        }
        if (!record.has("permissions") || !record.get("permissions").isJsonArray()) {
            throw new IllegalArgumentException("permissions must be an array");
        }
        if (!record.has("specialAccess") || !record.get("specialAccess").isJsonObject()) {
            throw new IllegalArgumentException("specialAccess must be an object");
        }
        if (!record.has("otherAppOps") || !record.get("otherAppOps").isJsonArray()) {
            throw new IllegalArgumentException("otherAppOps must be an array");
        }
        if (!record.has("batterySettings") || !record.get("batterySettings").isJsonObject()) {
            throw new IllegalArgumentException("batterySettings must be an object");
        }
        validateScopedOpContract(record);
    }

    private static final class OperationReport {
        final JsonArray items = new JsonArray();
        final JsonArray errors = new JsonArray();
        ResultCode result = ResultCode.OK;

        void success(String category, String key, String message) {
            JsonObject item = operationItem(category, key, ResultCode.OK, message);
            items.add(item);
        }

        void note(String category, String key, ResultCode code, String message) {
            JsonObject item = operationItem(category, key, code, message);
            items.add(item);
            if (code != ResultCode.OK) result = mergeResult(result, code);
        }

        void failure(String category, String key, Throwable throwable) {
            ResultCode code = classifyThrowable(throwable);
            JsonObject item = operationItem(category, key, code, failureMessage(throwable));
            items.add(item);
            errors.add(errorObject(category + (key == null || key.isEmpty() ? "" : "." + key),
                    code, failureMessage(throwable)));
            // Item-level SecurityException is expected on some Android 16 / vendor AppOps
            // and settings rows. Keep the per-item PERMISSION_DENIED detail, but do not
            // let a single denied item turn the whole package/daemon header into a
            // transport-like terminal failure. Callers must still receive the structured
            // body and continue to verify the rest of the restored state.
            ResultCode aggregate = (code == ResultCode.UNSUPPORTED || code == ResultCode.PERMISSION_DENIED)
                    ? ResultCode.PARTIAL : code;
            result = mergeResult(result, aggregate);
        }

        void mismatch(String category, String key, String message) {
            JsonObject item = operationItem(category, key, ResultCode.VERIFY_MISMATCH, message);
            items.add(item);
            result = mergeResult(result, ResultCode.VERIFY_MISMATCH);
        }
    }

    private static JsonObject operationItem(String category, String key, ResultCode code, String message) {
        JsonObject item = new JsonObject();
        item.addProperty("category", category == null ? "" : category);
        item.addProperty("key", key == null ? "" : key);
        setResult(item, code, message);
        return item;
    }

    private static JsonObject restorePackageState(PackageManager realPm, PackageManagerHidden pmHidden,
                                                  AppOpsManagerHidden appOps, UserHandle user, int userId,
                                                  String packageName, JsonObject desired) throws Exception {
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, snapshotPackageFlags(), userId);
        if (packageInfo == null || packageInfo.applicationInfo == null) {
            throw new PackageManager.NameNotFoundException(packageName);
        }
        int uid = packageInfo.applicationInfo.uid;
        OperationReport report = new OperationReport();
        JsonObject root = baseRecord("restore", userId, packageName);
        Set<Integer> expectedOps = collectExpectedOps(desired);

        AppOpsCompat.ResetResult reset = AppOpsCompat.resetPackageModesSafe(appOps, userId, packageName);
        if (reset.ok) {
            report.success("appOpsReset", packageName,
                    "package-scoped resetAllModes signature=" + reset.signature + " cached=" + reset.cached);
        } else {
            int resetCount = AppOpsCompat.resetKnownOpsToDefault(appOps, uid, packageName,
                    expectedOps, AppStateEngine::publicOpName);
            if (expectedOps.isEmpty() || resetCount == expectedOps.size()) {
                report.success("appOpsReset", packageName,
                        "package-scoped reset unavailable; package-only known-op fallback="
                                + resetCount + "/" + expectedOps.size());
            } else if (resetCount > 0) {
                report.note("appOpsReset", packageName, ResultCode.PARTIAL,
                        "package-only known-op fallback incomplete=" + resetCount
                                + "/" + expectedOps.size());
            } else {
                report.failure("appOpsReset", packageName,
                        new UnsupportedOperationException("package-scoped AppOps reset unavailable"));
            }
        }

        Set<String> requestedPermissions = new HashSet<>();
        if (packageInfo.requestedPermissions != null) {
            requestedPermissions.addAll(Arrays.asList(packageInfo.requestedPermissions));
        }
        int permissionMask = permissionFlagRestoreMask();
        JsonArray permissions = desired.getAsJsonArray("permissions");
        for (JsonElement element : permissions) {
            if (!element.isJsonObject()) continue;
            JsonObject permission = element.getAsJsonObject();
            String name = stringMember(permission, "name");
            if (name.isEmpty()) continue;
            boolean runtime = booleanMember(permission, "runtime", false);
            boolean development = booleanMember(permission, "development", false);
            int op = intMember(permission, "appOp", AppOpsManagerHidden.OP_NONE);
            boolean specialAccessOp = isSpecialAccessOp(op);
            boolean changeableGrant = isChangeablePermissionGrant(realPm, name, runtime, development);
            if (!requestedPermissions.contains(name)) {
                report.note("permission", name, ResultCode.UNSUPPORTED, "permission not requested by installed package");
                continue;
            }
            // Legacy app_details sometimes marked install-time or special-access permissions
            // (FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE, SYSTEM_ALERT_WINDOW,
            // PACKAGE_USAGE_STATS, DUMP, etc.) as runtime=true. Android correctly rejects
            // grant/revoke for those with "not a changeable permission type". The AppOp and
            // flags remain restorable; the permission grant itself is not a failure.
            if ((runtime || development) && changeableGrant && !specialAccessOp) {
                try {
                    boolean granted = booleanMember(permission, "granted", false);
                    if (granted) pmHidden.grantRuntimePermission(packageName, name, user);
                    else pmHidden.revokeRuntimePermission(packageName, name, user);
                    report.success("permissionGrant", name, granted ? "granted" : "revoked");
                } catch (Throwable e) {
                    report.failure("permissionGrant", name, e);
                }
            } else if (runtime || development || specialAccessOp) {
                report.success("permissionGrant", name, "skipped non-changeable or special-access permission");
            }
            if (permission.has("flags") && !permission.get("flags").isJsonNull() && !specialAccessOp) {
                try {
                    int flags = intMember(permission, "flags", 0);
                    PermissionCompat.updatePermissionFlags(pmHidden, packageName, name,
                            permissionMask, flags & permissionMask, userId, user);
                    report.success("permissionFlags", name, "flags=" + flags + " mask=" + permissionMask);
                } catch (Throwable e) {
                    report.failure("permissionFlags", name, e);
                }
            }
            if (op != AppOpsManagerHidden.OP_NONE) {
                if (changeableGrant && runtime && !specialAccessOp) {
                    restoreRuntimePermissionAppOp(appOps, uid, packageName, permission, op,
                            "permissionAppOp", name, report);
                } else {
                    // For legacy-migrated permission rows that are not emitted by the new
                    // snapshot schema, bridge their AppOp into the scoped writer so old
                    // backups still restore the meaningful state without creating verify noise.
                    restoreScopedAppOp(appOps, uid, packageName, permission, op, "appOpMode",
                            "permissionAppOp", name, false, report);
                }
            }
        }

        JsonObject special = desired.getAsJsonObject("specialAccess");
        for (Map.Entry<String, JsonElement> entry : special.entrySet()) {
            if (!entry.getValue().isJsonObject()) continue;
            JsonObject state = entry.getValue().getAsJsonObject();
            if (!booleanMember(state, "supported", true)
                    || !booleanMember(state, "requested", false)) continue;
            int op = intMember(state, "op", AppOpsManagerHidden.OP_NONE);
            if (op == AppOpsManagerHidden.OP_NONE) {
                report.note("specialAccess", entry.getKey(), ResultCode.UNSUPPORTED, "AppOp unavailable");
                continue;
            }
            restoreScopedAppOp(appOps, uid, packageName, state, op, "mode",
                    "specialAccess", entry.getKey(), false, report);
        }

        JsonArray otherOps = desired.getAsJsonArray("otherAppOps");
        for (JsonElement element : otherOps) {
            if (!element.isJsonObject()) continue;
            JsonObject state = element.getAsJsonObject();
            int op = intMember(state, "op", AppOpsManagerHidden.OP_NONE);
            if (op == AppOpsManagerHidden.OP_NONE) continue;
            restoreScopedAppOp(appOps, uid, packageName, state, op, "mode",
                    "otherAppOp", publicOpName(op), false, report);
        }

        JsonObject battery = desired.getAsJsonObject("batterySettings");
        restoreBatteryOp(appOps, uid, packageName, battery, "RUN_IN_BACKGROUND", report);
        restoreBatteryOp(appOps, uid, packageName, battery, "RUN_ANY_IN_BACKGROUND", report);
        if (battery.has("deviceidleWhitelist") && !battery.get("deviceidleWhitelist").isJsonNull()) {
            try {
                boolean enabled = battery.get("deviceidleWhitelist").getAsBoolean();
                setDeviceIdleWhitelist(packageName, enabled);
                report.success("battery", "deviceidleWhitelist", String.valueOf(enabled));
            } catch (Throwable e) {
                report.failure("battery", "deviceidleWhitelist", e);
            }
        }

        if (desired.has("ssaid") && !desired.get("ssaid").isJsonNull()) {
            String ssaid = stringMember(desired, "ssaid");
            if (!ssaid.isEmpty()) {
                try {
                    SsaidUtil.writeSsaidValue(userId, packageName, ssaid, pmHidden);
                    String readBack = SsaidUtil.readSsaidValue(userId, packageName, pmHidden);
                    if (ssaid.equals(readBack)) report.success("ssaid", packageName, "write/readback matched");
                    else report.mismatch("ssaid", packageName, "expected=" + ssaid + " actual=" + safe(readBack));
                } catch (Throwable e) {
                    report.failure("ssaid", packageName, e);
                }
            }
        }

        root.add("items", report.items);
        if (report.errors.size() > 0) root.add("errors", report.errors);
        setResult(root, report.result, report.result == ResultCode.OK ? null : "one or more AppState items did not fully restore");
        return root;
    }

    private static void restoreBatteryOp(AppOpsManagerHidden appOps, int uid, String packageName,
                                         JsonObject battery, String key, OperationReport report) {
        JsonObject state = objectMember(battery, key);
        if (state == null || !booleanMember(state, "supported", true)) return;
        int op = intMember(state, "op", AppOpsManagerHidden.OP_NONE);
        if (op == AppOpsManagerHidden.OP_NONE) return;
        restoreScopedAppOp(appOps, uid, packageName, state, op, "mode", "battery", key, true, report);
    }

    private static void restoreRuntimePermissionAppOp(AppOpsManagerHidden appOps, int uid,
                                                      String packageName, JsonObject state, int op,
                                                      String category, String key,
                                                      OperationReport report) {
        try {
            int expectedEffective = intMember(state, "appOpMode", AppOpsManagerHidden.MODE_DEFAULT);
            AppOpsCompat.setRuntimePermissionUidMode(appOps, op, uid, expectedEffective,
                    packageName, AppStateEngine::publicOpName);
            int actualEffective = readEffectiveModeWithRetry(appOps, op, uid, packageName, expectedEffective);
            if (modeEquivalent(expectedEffective, actualEffective)) {
                report.success(category, key, "op=" + op + " uidMode=" + expectedEffective
                        + " effective=" + actualEffective);
            } else {
                report.mismatch(category, key, "op=" + op
                        + " expectedEffective=" + expectedEffective
                        + " actualEffective=" + actualEffective
                        + " strategy=runtime_permission_uid");
            }
        } catch (Throwable e) {
            report.failure(category, key, e);
        }
    }

    private static void restoreScopedAppOp(AppOpsManagerHidden appOps, int uid, String packageName,
                                           JsonObject state, int op, String effectiveField,
                                           String category, String key, boolean mirrorUidWhenUnknown,
                                           OperationReport report) {
        try {
            Integer packageMode = nullableIntMember(state, "packageMode");
            Integer uidMode = nullableIntMember(state, "uidMode");
            int expectedEffective = intMember(state, effectiveField, AppOpsManagerHidden.MODE_DEFAULT);

            // JSON null means that scope could not be observed, not MODE_DEFAULT. Do not erase an
            // unknown scope. Package mode is restored only when it carries an actual integer.
            if (packageMode != null) {
                AppOpsCompat.setPackageModeIfNeeded(appOps, op, uid, packageName, packageMode);
            }
            if (uidMode != null) {
                AppOpsCompat.setUidModeIfNeeded(appOps, op, uid, uidMode,
                        AppStateEngine::publicOpName);
            } else if (mirrorUidWhenUnknown) {
                // Android 16/vendor battery AppOps may be uid-authoritative even when getUidMode
                // is hidden. Mirror the desired effective mode, matching the proven legacy path.
                AppOpsCompat.setUidModeIfNeeded(appOps, op, uid, expectedEffective,
                        AppStateEngine::publicOpName);
            }

            Integer actualPackage = AppOpsCompat.tryGetPackageModeRaw(appOps, op, uid, packageName);
            Integer actualUid = AppOpsCompat.tryGetUidModeRaw(appOps, op, uid, AppStateEngine::publicOpName);
            int actualEffective = readEffectiveModeWithRetry(appOps, op, uid, packageName, expectedEffective);
            boolean packageOk = packageMode == null || nullableModeEquivalent(packageMode, actualPackage);
            boolean uidOk = uidMode == null || nullableModeEquivalent(uidMode, actualUid);
            boolean explicitScopeOk = (packageMode != null || uidMode != null) && packageOk && uidOk;
            boolean effectiveOk = modeEquivalent(expectedEffective, actualEffective)
                    || (explicitScopeOk && isEffectiveModeAdvisory(op));
            if (packageOk && uidOk && effectiveOk) {
                String suffix = isEffectiveModeAdvisory(op) && !modeEquivalent(expectedEffective, actualEffective)
                        ? " advisoryEffective=" + actualEffective
                        : " mode=" + actualEffective;
                report.success(category, key, "op=" + op + suffix
                        + " packageMode=" + String.valueOf(actualPackage)
                        + " uidMode=" + String.valueOf(actualUid));
            } else {
                report.mismatch(category, key, "op=" + op
                        + " expectedEffective=" + expectedEffective + " actualEffective=" + actualEffective
                        + " expectedPackage=" + String.valueOf(packageMode) + " actualPackage=" + String.valueOf(actualPackage)
                        + " expectedUid=" + String.valueOf(uidMode) + " actualUid=" + String.valueOf(actualUid));
            }
        } catch (Throwable e) {
            report.failure(category, key, e);
        }
    }

    private static boolean isEffectiveModeAdvisory(int op) {
        // OP_START_FOREGROUND / android:start_foreground. Package mode is restorable,
        // but effective mode may stay MODE_DEFAULT on Android 16 vendor builds.
        return op == 76;
    }

    private static int readEffectiveModeWithRetry(AppOpsManagerHidden appOps, int op, int uid,
                                                   String packageName, int expected) {
        int actual = getEffectiveOpMode(appOps, op, uid, packageName);
        for (int attempt = 0; attempt < 3 && !modeEquivalent(expected, actual); attempt++) {
            try {
                Thread.sleep(20L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
            actual = getEffectiveOpMode(appOps, op, uid, packageName);
        }
        return actual;
    }

    private static JsonObject verifyPackageState(PackageManager realPm, PackageManagerHidden pmHidden,
                                                 AppOpsManagerHidden appOps, UserHandle user, int userId,
                                                 String packageName, JsonObject desired,
                                                 GooglePackageSnapshot playStore,
                                                 GooglePackageSnapshot playServices) throws Exception {
        Set<String> idleWhitelist = getDeviceIdleWhitelist();
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, snapshotPackageFlags(), userId);
        JsonObject current = snapshotPackage(realPm, pmHidden, appOps, idleWhitelist, user, userId,
                packageName, playStore, playServices);
        JsonObject root = baseRecord("verify", userId, packageName);
        JsonArray mismatches = new JsonArray();

        compareInstallState(desired, current, mismatches);
        comparePermissionState(desired, current, mismatches);
        compareSpecialAccessState(desired, current, mismatches);
        compareOtherAppOpsState(desired, current, mismatches);
        compareBatteryState(desired, current, mismatches);
        compareSsaidState(desired, current, mismatches);

        root.addProperty("uid", packageInfo.applicationInfo.uid);
        root.add("mismatches", mismatches);
        JsonObject currentResult = objectMember(current, "result");
        if (currentResult != null) root.add("currentSnapshotResult", currentResult.deepCopy());
        ResultCode currentCode = resultCodeFromRecord(current);
        ResultCode code;
        String message = null;
        if (mismatches.size() > 0) {
            code = ResultCode.VERIFY_MISMATCH;
            message = mismatches.size() + " AppState mismatch(es)";
        } else if (currentCode != ResultCode.OK) {
            code = ResultCode.PARTIAL;
            message = "current snapshot was partial";
        } else {
            code = ResultCode.OK;
        }
        setResult(root, code, message);
        return root;
    }

    private static void compareInstallState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        JsonObject expected = objectMember(desired, "installDiagnostics");
        JsonObject actual = objectMember(current, "installDiagnostics");
        if (expected == null || actual == null) return;
        compareScalar(mismatches, "installDiagnostics.versionCode", expected, actual, "versionCode", false);
        compareScalar(mismatches, "installDiagnostics.signingSha256", expected, actual, "signingSha256", false);
        compareScalar(mismatches, "installDiagnostics.splitCount", expected, actual, "splitCount", false);
    }

    private static void comparePermissionState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        Map<String, JsonObject> expected = indexArrayByString(desired.getAsJsonArray("permissions"), "name");
        Map<String, JsonObject> actual = indexArrayByString(current.getAsJsonArray("permissions"), "name");
        int mask = permissionFlagRestoreMask();
        for (Map.Entry<String, JsonObject> entry : expected.entrySet()) {
            String name = entry.getKey();
            JsonObject e = entry.getValue();
            int op = intMember(e, "appOp", AppOpsManagerHidden.OP_NONE);
            boolean runtime = booleanMember(e, "runtime", false);
            boolean legacySpecialOrNonSnapshot = isSpecialAccessOp(op)
                    || (runtime && !isSnapshotPermissionName(name));
            JsonObject a = actual.get(name);
            if (a == null) {
                if (legacySpecialOrNonSnapshot) {
                    // Old app_details can carry special-access/install-time permissions in
                    // the permissions array. New schema intentionally emits those through
                    // specialAccess/other AppOps or omits non-restorable grant rows.
                    continue;
                }
                addMismatch(mismatches, "permissions." + name, e, null, "missing permission record");
                continue;
            }
            if (!legacySpecialOrNonSnapshot) {
                compareScalar(mismatches, "permissions." + name + ".granted", e, a, "granted", false);
                if (e.has("flags")) {
                    int ef = intMember(e, "flags", 0) & mask;
                    int af = intMember(a, "flags", 0) & mask;
                    if (ef != af) addMismatch(mismatches, "permissions." + name + ".flags", ef, af, "restorable flag mask mismatch");
                }
            }
            if (op != AppOpsManagerHidden.OP_NONE && !isSpecialAccessOp(op)) {
                if (runtime && !legacySpecialOrNonSnapshot) {
                    compareEffectiveOpState(mismatches, "permissions." + name + ".appOp",
                            e, a, "appOpMode");
                } else {
                    compareOpState(mismatches, "permissions." + name + ".appOp", e, a, "appOpMode");
                }
            }
        }
    }

    private static void compareSpecialAccessState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        JsonObject expected = desired.getAsJsonObject("specialAccess");
        JsonObject actual = current.getAsJsonObject("specialAccess");
        for (Map.Entry<String, JsonElement> entry : expected.entrySet()) {
            if (!entry.getValue().isJsonObject()) continue;
            JsonObject e = entry.getValue().getAsJsonObject();
            if (!booleanMember(e, "supported", true)
                    || !booleanMember(e, "requested", false)) continue;
            JsonObject a = objectMember(actual, entry.getKey());
            if (a == null) {
                addMismatch(mismatches, "specialAccess." + entry.getKey(), e, null, "missing special access record");
                continue;
            }
            compareOpState(mismatches, "specialAccess." + entry.getKey(), e, a, "mode");
        }
    }

    private static void compareOtherAppOpsState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        Map<Integer, JsonObject> expected = indexArrayByInt(desired.getAsJsonArray("otherAppOps"), "op");
        Map<Integer, JsonObject> actual = indexArrayByInt(current.getAsJsonArray("otherAppOps"), "op");
        for (Map.Entry<Integer, JsonObject> entry : expected.entrySet()) {
            JsonObject e = entry.getValue();
            JsonObject a = actual.get(entry.getKey());
            if (a == null) {
                // getOpsForPackage() only returns AppOps that have an explicit non-default
                // package record on many Android builds.  If the canonical backup expected
                // a pure default state (packageMode/default, uidMode/null or default,
                // effective mode/default), the missing row is semantically identical to
                // MODE_DEFAULT and must not fail verify.  This hit op=119
                // android:access_restricted_settings after restore: setting it to default
                // removed the row, which is the correct platform representation.
                if (isDefaultAppOpRecord(e, "mode")) continue;
                addMismatch(mismatches, "otherAppOps." + entry.getKey(), e, null, "missing AppOp record");
                continue;
            }
            compareOpState(mismatches, "otherAppOps." + entry.getKey(), e, a, "mode");
        }
    }

    private static void compareBatteryState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        JsonObject expected = desired.getAsJsonObject("batterySettings");
        JsonObject actual = current.getAsJsonObject("batterySettings");
        for (String key : Arrays.asList("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND")) {
            JsonObject e = objectMember(expected, key);
            if (e == null || !booleanMember(e, "supported", true)) continue;
            JsonObject a = objectMember(actual, key);
            if (a == null) {
                addMismatch(mismatches, "batterySettings." + key, e, null, "missing battery AppOp record");
                continue;
            }
            compareOpState(mismatches, "batterySettings." + key, e, a, "mode");
        }
        compareScalar(mismatches, "batterySettings.deviceidleWhitelist", expected, actual,
                "deviceidleWhitelist", false);
    }

    private static void compareSsaidState(JsonObject desired, JsonObject current, JsonArray mismatches) {
        if (!desired.has("ssaid") || desired.get("ssaid").isJsonNull()) return;
        JsonElement expected = desired.get("ssaid");
        JsonElement actual = current.has("ssaid") ? current.get("ssaid") : null;
        if (!jsonElementEquals(expected, actual)) {
            addMismatch(mismatches, "ssaid", expected, actual, "SSAID mismatch");
        }
    }

    private static void compareEffectiveOpState(JsonArray mismatches, String path,
                                                JsonObject expected, JsonObject actual,
                                                String effectiveField) {
        int expectedMode = intMember(expected, effectiveField, AppOpsManagerHidden.MODE_DEFAULT);
        int actualMode = intMember(actual, effectiveField, AppOpsManagerHidden.MODE_DEFAULT);
        if (!modeEquivalent(expectedMode, actualMode)) {
            addMismatch(mismatches, path + "." + effectiveField, expectedMode, actualMode,
                    "effective mode mismatch");
        }
    }

    private static void compareOpState(JsonArray mismatches, String path, JsonObject expected,
                                       JsonObject actual, String effectiveField) {
        int op = intMember(expected, "op", intMember(expected, "appOp", AppOpsManagerHidden.OP_NONE));
        boolean packageCompared = false;
        boolean packageOk = true;
        boolean uidCompared = false;
        boolean uidOk = true;
        if (expected.has("packageMode") && !expected.get("packageMode").isJsonNull()) {
            packageCompared = true;
            Integer e = nullableIntMember(expected, "packageMode");
            Integer a = nullableIntMember(actual, "packageMode");
            packageOk = nullableModeEquivalent(e, a);
            if (!packageOk) {
                addMismatch(mismatches, path + ".packageMode", e, a, "package mode mismatch");
            }
        }
        if (expected.has("uidMode") && !expected.get("uidMode").isJsonNull()) {
            uidCompared = true;
            Integer e = nullableIntMember(expected, "uidMode");
            Integer a = nullableIntMember(actual, "uidMode");
            uidOk = nullableModeEquivalent(e, a);
            if (!uidOk) {
                addMismatch(mismatches, path + ".uidMode", e, a, "uid mode mismatch");
            }
        }
        // Some Android 15/16 vendor builds report OP_START_FOREGROUND's effective
        // unsafeCheckOpNoThrow() result as MODE_DEFAULT even after the package-scoped
        // override was correctly written and can be read back from getOpsForPackage().
        // For such ops, the restorable state is the explicit package/uid scope; the
        // effective value is diagnostic only and must not fail restore/verify.
        if (isEffectiveModeAdvisory(op) && (packageCompared || uidCompared) && packageOk && uidOk) {
            return;
        }
        compareEffectiveOpState(mismatches, path, expected, actual, effectiveField);
    }

    private static void compareScalar(JsonArray mismatches, String path, JsonObject expected,
                                      JsonObject actual, String key, boolean mode) {
        if (expected == null || !expected.has(key)) return;
        JsonElement e = expected.get(key);
        JsonElement a = actual != null && actual.has(key) ? actual.get(key) : null;
        boolean equal;
        if (mode && e != null && !e.isJsonNull() && a != null && !a.isJsonNull()) {
            equal = modeEquivalent(e.getAsInt(), a.getAsInt());
        } else {
            equal = jsonElementEquals(e, a);
        }
        if (!equal) addMismatch(mismatches, path, e, a, "value mismatch");
    }

    private static void addMismatch(JsonArray mismatches, String path, Object expected,
                                    Object actual, String message) {
        JsonObject item = new JsonObject();
        item.addProperty("path", path);
        addJsonValue(item, "expected", expected);
        addJsonValue(item, "actual", actual);
        item.addProperty("message", message);
        setResult(item, ResultCode.VERIFY_MISMATCH, message);
        mismatches.add(item);
    }

    private static void addJsonValue(JsonObject object, String key, Object value) {
        if (value == null) {
            addJsonNull(object, key);
        } else if (value instanceof JsonElement) {
            object.add(key, ((JsonElement) value).deepCopy());
        } else if (value instanceof Number) {
            object.addProperty(key, (Number) value);
        } else if (value instanceof Boolean) {
            object.addProperty(key, (Boolean) value);
        } else {
            object.addProperty(key, String.valueOf(value));
        }
    }

    private static boolean jsonElementEquals(JsonElement first, JsonElement second) {
        if (first == null || first.isJsonNull()) return second == null || second.isJsonNull();
        if (second == null || second.isJsonNull()) return false;
        if (first.equals(second) || first.toString().equals(second.toString())) return true;
        if (first.isJsonPrimitive() && second.isJsonPrimitive()) {
            try {
                java.math.BigDecimal a = first.getAsBigDecimal();
                java.math.BigDecimal b = second.getAsBigDecimal();
                return a.compareTo(b) == 0;
            } catch (Throwable ignored) {
            }
        }
        return false;
    }

    private static Map<String, JsonObject> indexArrayByString(JsonArray array, String key) {
        Map<String, JsonObject> out = new LinkedHashMap<>();
        if (array == null) return out;
        for (JsonElement element : array) {
            if (!element.isJsonObject()) continue;
            JsonObject object = element.getAsJsonObject();
            String value = stringMember(object, key);
            if (!value.isEmpty()) out.put(value, object);
        }
        return out;
    }

    private static Map<Integer, JsonObject> indexArrayByInt(JsonArray array, String key) {
        Map<Integer, JsonObject> out = new LinkedHashMap<>();
        if (array == null) return out;
        for (JsonElement element : array) {
            if (!element.isJsonObject()) continue;
            JsonObject object = element.getAsJsonObject();
            int value = intMember(object, key, AppOpsManagerHidden.OP_NONE);
            if (value != AppOpsManagerHidden.OP_NONE) out.put(value, object);
        }
        return out;
    }

    private static Set<Integer> collectExpectedOps(JsonObject desired) {
        Set<Integer> out = new LinkedHashSet<>();
        JsonArray permissions = desired.getAsJsonArray("permissions");
        if (permissions != null) {
            for (JsonElement element : permissions) {
                if (!element.isJsonObject()) continue;
                addExpectedOp(out, intMember(element.getAsJsonObject(), "appOp", AppOpsManagerHidden.OP_NONE));
            }
        }
        JsonObject special = desired.getAsJsonObject("specialAccess");
        if (special != null) {
            for (Map.Entry<String, JsonElement> entry : special.entrySet()) {
                if (entry.getValue().isJsonObject()) {
                    JsonObject state = entry.getValue().getAsJsonObject();
                    if (booleanMember(state, "supported", true)
                            && booleanMember(state, "requested", false)) {
                        addExpectedOp(out, intMember(state, "op", AppOpsManagerHidden.OP_NONE));
                    }
                }
            }
        }
        JsonArray other = desired.getAsJsonArray("otherAppOps");
        if (other != null) {
            for (JsonElement element : other) {
                if (element.isJsonObject()) addExpectedOp(out, intMember(element.getAsJsonObject(), "op", AppOpsManagerHidden.OP_NONE));
            }
        }
        JsonObject battery = desired.getAsJsonObject("batterySettings");
        if (battery != null) {
            for (String key : Arrays.asList("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND")) {
                JsonObject state = objectMember(battery, key);
                if (state != null) addExpectedOp(out, intMember(state, "op", AppOpsManagerHidden.OP_NONE));
            }
        }
        return out;
    }

    private static void addExpectedOp(Set<Integer> out, int op) {
        if (op != AppOpsManagerHidden.OP_NONE && op >= 0) out.add(op);
    }

    private static boolean modeEquivalent(int expected, int actual) {
        return expected == actual || equivalentAllowedMode(actual, expected);
    }

    private static boolean nullableModeEquivalent(Integer expected, Integer actual) {
        if (expected == null || expected == AppOpsManagerHidden.MODE_DEFAULT) {
            return actual == null || actual == AppOpsManagerHidden.MODE_DEFAULT;
        }
        if (actual == null) return false;
        return modeEquivalent(expected, actual);
    }

    private static boolean isDefaultAppOpRecord(JsonObject object, String effectiveField) {
        if (object == null) return true;
        Integer packageMode = nullableIntMember(object, "packageMode");
        Integer uidMode = nullableIntMember(object, "uidMode");
        int effective = intMember(object, effectiveField, AppOpsManagerHidden.MODE_DEFAULT);
        return nullableModeEquivalent(AppOpsManagerHidden.MODE_DEFAULT, packageMode)
                && nullableModeEquivalent(AppOpsManagerHidden.MODE_DEFAULT, uidMode)
                && modeEquivalent(AppOpsManagerHidden.MODE_DEFAULT, effective);
    }

    private static Integer nullableIntMember(JsonObject object, String name) {
        try {
            if (object == null || !object.has(name) || object.get(name).isJsonNull()) return null;
            return object.get(name).getAsInt();
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static boolean booleanMember(JsonObject object, String name, boolean fallback) {
        try {
            if (object == null || !object.has(name) || object.get(name).isJsonNull()) return fallback;
            return object.get(name).getAsBoolean();
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static int permissionFlagRestoreMask() {
        int mask = 0;
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_USER_SET", 1 << 0);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_USER_FIXED", 1 << 1);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_REVIEW_REQUIRED", 1 << 6);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_REVOKE_WHEN_REQUESTED", 1 << 14);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_AUTO_REVOKED", 1 << 15);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_ONE_TIME", 1 << 16);
        mask |= PermissionCompat.packageManagerFlag("FLAG_PERMISSION_SELECTED_LOCATION_ACCURACY", 1 << 19);
        return mask;
    }

    private static void setDeviceIdleWhitelist(String packageName, boolean enabled) throws Exception {
        Set<String> current = getDeviceIdleWhitelist();
        if (current.contains(packageName) == enabled) return;
        Throwable serviceFailure = null;
        try {
            Object service = HiddenApiServices.deviceIdle();
            if (enabled) {
                HiddenApiReflection.callRequired(service,
                        new HiddenApiReflection.Call("addPowerSaveWhitelistApp", packageName));
            } else {
                HiddenApiReflection.callRequired(service,
                        new HiddenApiReflection.Call("removePowerSaveWhitelistApp", packageName));
            }
            return;
        } catch (Throwable e) {
            serviceFailure = e;
        }
        String safePackage = packageName == null ? "" : packageName.replaceAll("[^A-Za-z0-9._-]", "");
        if (safePackage.isEmpty()) throw new IllegalArgumentException("invalid package for deviceidle whitelist");
        String prefix = enabled ? "+" : "-";
        int rc = runShellCommand("cmd deviceidle whitelist " + prefix + safePackage);
        if (rc != 0) {
            int fallbackRc = runShellCommand("dumpsys deviceidle whitelist " + prefix + safePackage);
            if (fallbackRc != 0) {
                if (serviceFailure instanceof Exception) throw (Exception) serviceFailure;
                throw new IllegalStateException("deviceidle whitelist update failed rc=" + rc + "/" + fallbackRc,
                        serviceFailure);
            }
        }
    }

    private static int runShellCommand(String command) throws Exception {
        ProcessBuilder builder = new ProcessBuilder("sh", "-c", command);
        builder.redirectErrorStream(true);
        Process process = builder.start();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            while (reader.readLine() != null) {
                // Drain output so a full pipe cannot deadlock waitFor().
            }
        }
        return process.waitFor();
    }

    static List<String> parsePackageLines(String text) {
        List<String> out = new ArrayList<>();
        if (text == null) return out;
        for (String line : text.split("\\r?\\n")) {
            String value = line.trim();
            if (value.isEmpty() || value.startsWith("#")) continue;
            for (String token : value.split("\\s+")) {
                if (!token.isEmpty()) out.add(token);
            }
        }
        return dedupePackages(out);
    }

    private static JsonObject snapshotPackage(PackageManager realPm, PackageManagerHidden pmHidden,
                                              AppOpsManagerHidden appOps, Set<String> idleWhitelist,
                                              UserHandle user, int userId, String packageName,
                                              GooglePackageSnapshot playStore,
                                              GooglePackageSnapshot playServices) throws Exception {
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(
                packageName, snapshotPackageFlags(), userId);
        JsonObject root = baseRecord("snapshot", userId, packageName);
        JsonArray errors = new JsonArray();
        ResultCode code = ResultCode.OK;

        JsonObject packageObject = new JsonObject();
        packageObject.addProperty("uid", packageInfo.applicationInfo.uid);
        packageObject.addProperty("label", safeLabel(realPm, packageInfo.applicationInfo));
        packageObject.addProperty("versionCode", longVersionCode(packageInfo));
        packageObject.addProperty("versionName", packageInfo.versionName == null ? "" : packageInfo.versionName);
        packageObject.addProperty("systemApp", (packageInfo.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0);
        String installer = null;
        try {
            installer = realPm.getInstallerPackageName(packageName);
        } catch (Throwable e) {
            errors.add(errorObject("installer", ResultCode.PARTIAL, failureMessage(e)));
            code = ResultCode.PARTIAL;
        }
        if (installer == null) addJsonNull(packageObject, "installer");
        else packageObject.addProperty("installer", installer);
        root.add("package", packageObject);
        try {
            root.add("installDiagnostics", collectInstallDiagnostics(
                    realPm, packageInfo, installer, playStore, playServices));
        } catch (Throwable e) {
            root.add("installDiagnostics", new JsonObject());
            errors.add(errorObject("installDiagnostics", classifyThrowable(e), failureMessage(e)));
            code = ResultCode.PARTIAL;
        }

        Map<Integer, Integer> rawOps = readPackageOps(appOps, packageInfo.applicationInfo.uid, packageName);
        Set<Integer> handledOps = new HashSet<>();
        Set<Integer> specialManagedOps = collectRequestedSpecialAccessOps(packageInfo);
        handledOps.addAll(specialManagedOps);
        try {
            root.add("permissions", collectPermissions(realPm, pmHidden, appOps, user, packageInfo,
                    rawOps, handledOps, specialManagedOps));
        } catch (Throwable e) {
            root.add("permissions", new JsonArray());
            errors.add(errorObject("permissions", classifyThrowable(e), failureMessage(e)));
            code = ResultCode.PARTIAL;
        }

        JsonObject specialAccess;
        try {
            specialAccess = collectSpecialAccess(appOps, packageInfo);
            root.add("specialAccess", specialAccess);
            for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) {
                int op = resolveOp(descriptor.publicName);
                if (op != AppOpsManagerHidden.OP_NONE) handledOps.add(op);
            }
        } catch (Throwable e) {
            root.add("specialAccess", new JsonObject());
            errors.add(errorObject("specialAccess", classifyThrowable(e), failureMessage(e)));
            code = ResultCode.PARTIAL;
        }

        try {
            root.add("batterySettings", collectBatterySettings(appOps, packageInfo, idleWhitelist));
            int runInBackground = resolveOp("android:run_in_background");
            int runAnyInBackground = resolveOp("android:run_any_in_background");
            if (runInBackground != AppOpsManagerHidden.OP_NONE) {
                handledOps.add(runInBackground);
                rawOps.remove(runInBackground);
            }
            if (runAnyInBackground != AppOpsManagerHidden.OP_NONE) {
                handledOps.add(runAnyInBackground);
                rawOps.remove(runAnyInBackground);
            }
        } catch (Throwable e) {
            root.add("batterySettings", new JsonObject());
            errors.add(errorObject("batterySettings", classifyThrowable(e), failureMessage(e)));
            code = ResultCode.PARTIAL;
        }

        root.add("otherAppOps", collectOtherAppOps(appOps, packageInfo, rawOps, handledOps));

        try {
            String ssaid = SsaidUtil.readSsaidValue(userId, packageName, pmHidden);
            if (ssaid == null) addJsonNull(root, "ssaid");
            else root.addProperty("ssaid", ssaid);
        } catch (Throwable e) {
            addJsonNull(root, "ssaid");
            errors.add(errorObject("ssaid", classifyThrowable(e), failureMessage(e)));
            code = ResultCode.PARTIAL;
        }

        // Canonical schema v2 contract: every AppOp-bearing record always exposes both
        // packageMode and uidMode, even when one scope is unavailable (explicit JSON null).
        enforceScopedOpContract(root);
        // Drop non-restorable display/debug fields before persistence.
        compactSnapshotRecord(root);

        // Fail the package snapshot before serialization if the declared scoped-AppOps
        // contract is incomplete. This prevents capability/output drift in release builds.
        validateScopedOpContract(root);
        if (errors.size() > 0) root.add("errors", errors);
        setResult(root, code, code == ResultCode.PARTIAL ? "one or more optional fields failed" : null);
        return root;
    }

    private static JsonArray collectPermissions(PackageManager realPm, PackageManagerHidden pmHidden,
                                                AppOpsManagerHidden appOps, UserHandle user,
                                                PackageInfo packageInfo, Map<Integer, Integer> rawOps,
                                                Set<Integer> handledOps, Set<Integer> specialManagedOps) {
        JsonArray out = new JsonArray();
        String[] requested = packageInfo.requestedPermissions;
        int[] requestedFlags = packageInfo.requestedPermissionsFlags;
        if (requested == null) return out;
        for (int i = 0; i < requested.length; i++) {
            String permissionName = requested[i];
            JsonObject item = new JsonObject();
            item.addProperty("name", permissionName);
            item.addProperty("nameCn", AppStateLocalization.permissionCn(permissionName));
            boolean granted = requestedFlags != null && i < requestedFlags.length
                    && (requestedFlags[i] & PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0;
            item.addProperty("granted", granted);
            try {
                item.addProperty("flags", pmHidden.getPermissionFlags(permissionName, packageInfo.packageName, user));
            } catch (Throwable e) {
                item.addProperty("flags", 0);
                item.addProperty("flagsError", failureMessage(e));
            }
            int protection = -1;
            int protectionFlags = 0;
            try {
                int[] info = permissionProtection(realPm, permissionName);
                protection = info[0];
                protectionFlags = info[1];
            } catch (Throwable ignored) {
            }
            item.addProperty("protection", protection);
            item.addProperty("protectionFlags", protectionFlags);
            item.addProperty("runtime", protection == PermissionInfo.PROTECTION_DANGEROUS);
            item.addProperty("development", (protectionFlags & PermissionInfo.PROTECTION_FLAG_DEVELOPMENT) != 0);
            int op = AppOpsManagerHidden.OP_NONE;
            try {
                op = AppOpsManagerHidden.permissionToOpCode(permissionName);
            } catch (Throwable ignored) {
            }
            boolean managedBySpecialAccess = op != AppOpsManagerHidden.OP_NONE
                    && specialManagedOps.contains(op);
            item.addProperty("appOp", managedBySpecialAccess ? AppOpsManagerHidden.OP_NONE : op);
            if (!managedBySpecialAccess && op != AppOpsManagerHidden.OP_NONE) {
                String appOpPublicName = publicOpName(op);
                item.addProperty("appOpName", appOpPublicName);
                item.addProperty("appOpNameCn", AppStateLocalization.permissionCn(appOpPublicName));
            }
            if (managedBySpecialAccess) {
                item.addProperty("appOpManagedBy", "specialAccess");
            } else if (op != AppOpsManagerHidden.OP_NONE) {
                addScopedOpState(item, appOps, op, packageInfo.applicationInfo.uid,
                        packageInfo.packageName, "appOpMode");
                handledOps.add(op);
                rawOps.remove(op);
            }
            if ((!managedBySpecialAccess && op != AppOpsManagerHidden.OP_NONE)
                    || protection == PermissionInfo.PROTECTION_DANGEROUS
                    || (!managedBySpecialAccess
                    && (protectionFlags & PermissionInfo.PROTECTION_FLAG_DEVELOPMENT) != 0)) {
                out.add(item);
            }
        }
        return out;
    }

    private static Set<Integer> collectRequestedSpecialAccessOps(PackageInfo packageInfo) {
        Set<Integer> out = new HashSet<>();
        for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) {
            if (!isSpecialAccessRequested(descriptor, packageInfo)) continue;
            int op = resolveOp(descriptor.publicName);
            if (op != AppOpsManagerHidden.OP_NONE) out.add(op);
        }
        return out;
    }

    private static boolean isSpecialAccessOp(int op) {
        if (op == AppOpsManagerHidden.OP_NONE) return false;
        for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) {
            if (resolveOp(descriptor.publicName) == op) return true;
        }
        return false;
    }

    private static boolean isSnapshotPermissionName(String permissionName) {
        if (permissionName == null) return false;
        try {
            int[] protection = permissionProtection(runtimeServices().packageManager, permissionName);
            int base = protection[0];
            int flags = protection[1];
            return base == PermissionInfo.PROTECTION_DANGEROUS
                    || (flags & PermissionInfo.PROTECTION_FLAG_DEVELOPMENT) != 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static boolean isChangeablePermissionGrant(PackageManager pm, String permissionName,
                                                       boolean declaredRuntime, boolean declaredDevelopment) {
        try {
            int[] protection = permissionProtection(pm, permissionName);
            int base = protection[0];
            int flags = protection[1];
            return base == PermissionInfo.PROTECTION_DANGEROUS
                    || (flags & PermissionInfo.PROTECTION_FLAG_DEVELOPMENT) != 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static JsonObject collectSpecialAccess(AppOpsManagerHidden appOps, PackageInfo packageInfo) {
        JsonObject out = new JsonObject();
        for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) {
            JsonObject item = new JsonObject();
            int op = resolveOp(descriptor.publicName);
            boolean supported = op != AppOpsManagerHidden.OP_NONE;
            boolean requested = isSpecialAccessRequested(descriptor, packageInfo);
            item.addProperty("keyCn", AppStateLocalization.specialCn(descriptor.key));
            item.addProperty("publicName", descriptor.publicName);
            item.addProperty("publicNameCn", AppStateLocalization.permissionCn(descriptor.publicName));
            if (descriptor.manifestPermission == null) addJsonNull(item, "manifestPermission");
            else {
                item.addProperty("manifestPermission", descriptor.manifestPermission);
                item.addProperty("manifestPermissionCn", AppStateLocalization.permissionCn(descriptor.manifestPermission));
            }
            item.addProperty("requested", requested);
            item.addProperty("supported", supported);
            item.addProperty("op", op);
            item.addProperty("source", "appop");
            if (supported) {
                int uid = packageInfo.applicationInfo.uid;
                Integer packageMode = AppOpsCompat.tryGetPackageModeRaw(appOps, op, uid, packageInfo.packageName);
                Integer uidMode = AppOpsCompat.tryGetUidModeRaw(appOps, op, uid, AppStateEngine::publicOpName);
                int mode = getEffectiveOpMode(appOps, op, uid, packageInfo.packageName);
                if (packageMode == null) addJsonNull(item, "packageMode");
                else item.addProperty("packageMode", packageMode);
                if (uidMode == null) addJsonNull(item, "uidMode");
                else item.addProperty("uidMode", uidMode);
                String scope = "default";
                if (packageMode != null && packageMode != AppOpsManagerHidden.MODE_DEFAULT) scope = "package";
                else if (uidMode != null && uidMode != AppOpsManagerHidden.MODE_DEFAULT) scope = "uid";
                item.addProperty("scope", scope);
                item.addProperty("mode", mode);
                item.addProperty("modeName", modeName(mode));
                item.addProperty("modeCn", AppStateLocalization.modeCn(mode));
                item.addProperty("allowed", allowedMode(mode));
            } else {
                addJsonNull(item, "packageMode");
                addJsonNull(item, "uidMode");
                item.addProperty("scope", "unsupported");
                item.addProperty("mode", AppOpsManagerHidden.MODE_DEFAULT);
                item.addProperty("modeName", "unsupported");
                item.addProperty("modeCn", "不支援");
                item.addProperty("allowed", false);
            }
            out.add(descriptor.key, item);
        }
        return out;
    }

    private static JsonArray collectOtherAppOps(AppOpsManagerHidden appOps, PackageInfo packageInfo,
                                                Map<Integer, Integer> rawOps, Set<Integer> handledOps) {
        JsonArray out = new JsonArray();
        List<Map.Entry<Integer, Integer>> entries = new ArrayList<>(rawOps.entrySet());
        entries.sort(Comparator.comparingInt(e -> e.getKey()));
        for (Map.Entry<Integer, Integer> entry : entries) {
            if (handledOps.contains(entry.getKey())) continue;
            JsonObject item = new JsonObject();
            item.addProperty("op", entry.getKey());
            String opPublicName = publicOpName(entry.getKey());
            item.addProperty("publicName", opPublicName);
            item.addProperty("publicNameCn", AppStateLocalization.permissionCn(opPublicName));
            addScopedOpState(item, appOps, entry.getKey(), packageInfo.applicationInfo.uid,
                    packageInfo.packageName, "mode");
            out.add(item);
        }
        return out;
    }


    private static void compactSnapshotRecord(JsonObject root) {
        if (root == null) return;

        JsonObject install = objectMember(root, "installDiagnostics");
        if (install != null) {
            JsonObject compact = new JsonObject();
            copyJsonMember(install, compact, "installer");
            copyJsonMember(install, compact, "installing");
            copyJsonMember(install, compact, "initiating");
            copyJsonMember(install, compact, "packageSourceName");
            copyJsonMember(install, compact, "versionCode");
            copyJsonMember(install, compact, "versionName");
            copyJsonMember(install, compact, "signingSha256");
            copyJsonMember(install, compact, "splitCount");
            root.add("installDiagnostics", compact);
        }

        JsonArray permissions = root.getAsJsonArray("permissions");
        if (permissions != null) {
            for (JsonElement element : permissions) {
                if (!element.isJsonObject()) continue;
                pruneJsonObject(element.getAsJsonObject(),
                        "name", "nameCn", "granted", "flags", "flagsError",
                        "runtime", "development", "appOp", "appOpName", "appOpNameCn", "appOpManagedBy",
                        "packageMode", "uidMode", "scope", "appOpMode", "appOpModeName", "appOpModeCn");
            }
        }

        JsonObject specialAccess = objectMember(root, "specialAccess");
        if (specialAccess != null) {
            for (Map.Entry<String, JsonElement> entry : specialAccess.entrySet()) {
                if (!entry.getValue().isJsonObject()) continue;
                pruneJsonObject(entry.getValue().getAsJsonObject(),
                        "keyCn", "requested", "supported", "op", "publicName", "publicNameCn", "manifestPermission", "manifestPermissionCn",
                        "packageMode", "uidMode", "scope", "mode", "modeName", "modeCn");
            }
        }

        JsonArray otherAppOps = root.getAsJsonArray("otherAppOps");
        if (otherAppOps != null) {
            for (JsonElement element : otherAppOps) {
                if (!element.isJsonObject()) continue;
                pruneJsonObject(element.getAsJsonObject(),
                        "op", "publicName", "publicNameCn", "packageMode", "uidMode", "scope", "mode", "modeName", "modeCn");
            }
        }

        JsonObject battery = objectMember(root, "batterySettings");
        if (battery != null) {
            for (String key : Arrays.asList("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND")) {
                JsonObject item = objectMember(battery, key);
                if (item != null) {
                    pruneJsonObject(item,
                            "op", "publicName", "publicNameCn", "supported", "packageMode", "uidMode", "scope", "mode", "modeName", "modeCn");
                }
            }
        }
    }

    private static void copyJsonMember(JsonObject from, JsonObject to, String name) {
        if (from == null || to == null || !from.has(name)) return;
        JsonElement value = from.get(name);
        to.add(name, value == null ? JsonNull.INSTANCE : value.deepCopy());
    }

    private static void pruneJsonObject(JsonObject object, String... keepNames) {
        if (object == null) return;
        Set<String> keep = new HashSet<>(Arrays.asList(keepNames));
        List<String> remove = new ArrayList<>();
        for (Map.Entry<String, JsonElement> entry : object.entrySet()) {
            if (!keep.contains(entry.getKey())) remove.add(entry.getKey());
        }
        for (String key : remove) object.remove(key);
    }

    private static JsonObject collectBatterySettings(AppOpsManagerHidden appOps, PackageInfo packageInfo,
                                                     Set<String> idleWhitelist) {
        JsonObject out = new JsonObject();
        out.add("RUN_IN_BACKGROUND", appOpState(appOps, packageInfo, resolveOp("android:run_in_background")));
        out.add("RUN_ANY_IN_BACKGROUND", appOpState(appOps, packageInfo, resolveOp("android:run_any_in_background")));
        out.addProperty("deviceidleWhitelist", idleWhitelist.contains(packageInfo.packageName));
        return out;
    }

    private static JsonObject appOpState(AppOpsManagerHidden appOps, PackageInfo packageInfo, int op) {
        JsonObject item = new JsonObject();
        item.addProperty("op", op);
        if (op != AppOpsManagerHidden.OP_NONE) {
            String opPublicName = publicOpName(op);
            item.addProperty("publicName", opPublicName);
            item.addProperty("publicNameCn", AppStateLocalization.permissionCn(opPublicName));
        }
        item.addProperty("supported", op != AppOpsManagerHidden.OP_NONE);
        if (op == AppOpsManagerHidden.OP_NONE) {
            addJsonNull(item, "packageMode");
            addJsonNull(item, "uidMode");
            item.addProperty("scope", "unsupported");
            item.addProperty("mode", AppOpsManagerHidden.MODE_DEFAULT);
            item.addProperty("modeName", "unsupported");
            item.addProperty("modeCn", "不支援");
            item.addProperty("allowed", false);
        } else {
            addScopedOpState(item, appOps, op, packageInfo.applicationInfo.uid,
                    packageInfo.packageName, "mode");
        }
        return item;
    }

    private static void addScopedOpState(JsonObject item, AppOpsManagerHidden appOps, int op,
                                         int uid, String packageName, String modeField) {
        Integer packageMode = AppOpsCompat.tryGetPackageModeRaw(appOps, op, uid, packageName);
        Integer uidMode = AppOpsCompat.tryGetUidModeRaw(appOps, op, uid, AppStateEngine::publicOpName);
        int mode = getEffectiveOpMode(appOps, op, uid, packageName);
        if (packageMode == null) addJsonNull(item, "packageMode");
        else item.addProperty("packageMode", packageMode);
        if (uidMode == null) addJsonNull(item, "uidMode");
        else item.addProperty("uidMode", uidMode);
        String scope = "default";
        if (packageMode != null && packageMode != AppOpsManagerHidden.MODE_DEFAULT) scope = "package";
        else if (uidMode != null && uidMode != AppOpsManagerHidden.MODE_DEFAULT) scope = "uid";
        item.addProperty("scope", scope);
        item.addProperty(modeField, mode);
        item.addProperty(modeField + "Name", modeName(mode));
        item.addProperty(modeField + "Cn", AppStateLocalization.modeCn(mode));
        item.addProperty("allowed", allowedMode(mode));
    }

    private static void addJsonNull(JsonObject object, String name) {
        object.add(name, JsonNull.INSTANCE);
    }

    private static void ensureNullableMember(JsonObject object, String name) {
        if (object != null && !object.has(name)) addJsonNull(object, name);
    }

    private static void ensureScopedOpFields(JsonObject object) {
        if (object == null) return;
        ensureNullableMember(object, "packageMode");
        ensureNullableMember(object, "uidMode");
    }

    private static void enforceScopedOpContract(JsonObject root) {
        JsonArray permissions = root.getAsJsonArray("permissions");
        if (permissions != null) {
            for (JsonElement element : permissions) {
                if (!element.isJsonObject()) continue;
                JsonObject item = element.getAsJsonObject();
                if (intMember(item, "appOp", AppOpsManagerHidden.OP_NONE) != AppOpsManagerHidden.OP_NONE) {
                    ensureScopedOpFields(item);
                }
            }
        }
        JsonObject specialAccess = objectMember(root, "specialAccess");
        if (specialAccess != null) {
            for (Map.Entry<String, JsonElement> entry : specialAccess.entrySet()) {
                if (entry.getValue().isJsonObject()) ensureScopedOpFields(entry.getValue().getAsJsonObject());
            }
        }
        JsonArray otherAppOps = root.getAsJsonArray("otherAppOps");
        if (otherAppOps != null) {
            for (JsonElement element : otherAppOps) {
                if (element.isJsonObject()) ensureScopedOpFields(element.getAsJsonObject());
            }
        }
        JsonObject battery = objectMember(root, "batterySettings");
        if (battery != null) {
            for (String key : Arrays.asList("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND")) {
                JsonObject item = objectMember(battery, key);
                if (item != null) ensureScopedOpFields(item);
            }
        }
    }

    private static void validateScopedOpObject(JsonObject object, String path) {
        if (object == null) throw new IllegalArgumentException(path + " must be an object");
        if (!object.has("packageMode")) throw new IllegalArgumentException(path + ".packageMode is missing");
        if (!object.has("uidMode")) throw new IllegalArgumentException(path + ".uidMode is missing");
        if (!object.has("scope")) throw new IllegalArgumentException(path + ".scope is missing");
        if (!object.has("mode") && !object.has("appOpMode")) {
            throw new IllegalArgumentException(path + ".effective mode is missing");
        }
    }

    private static void validateScopedOpContract(JsonObject root) {
        JsonArray permissions = root.getAsJsonArray("permissions");
        if (permissions != null) {
            int permissionIndex = 0;
            for (JsonElement element : permissions) {
                if (!element.isJsonObject()) {
                    throw new IllegalArgumentException("permissions[" + permissionIndex + "] must be an object");
                }
                JsonObject item = element.getAsJsonObject();
                if (intMember(item, "appOp", AppOpsManagerHidden.OP_NONE) != AppOpsManagerHidden.OP_NONE) {
                    validateScopedOpObject(item, "permissions[" + permissionIndex + "]");
                }
                permissionIndex++;
            }
        }
        JsonObject specialAccess = root.getAsJsonObject("specialAccess");
        for (Map.Entry<String, JsonElement> entry : specialAccess.entrySet()) {
            if (!entry.getValue().isJsonObject()) {
                throw new IllegalArgumentException("specialAccess." + entry.getKey() + " must be an object");
            }
            validateScopedOpObject(entry.getValue().getAsJsonObject(), "specialAccess." + entry.getKey());
        }
        JsonArray otherAppOps = root.getAsJsonArray("otherAppOps");
        int appOpIndex = 0;
        for (JsonElement element : otherAppOps) {
            if (!element.isJsonObject()) {
                throw new IllegalArgumentException("otherAppOps[" + appOpIndex + "] must be an object");
            }
            validateScopedOpObject(element.getAsJsonObject(), "otherAppOps[" + appOpIndex + "]");
            appOpIndex++;
        }
        JsonObject battery = root.getAsJsonObject("batterySettings");
        for (String key : Arrays.asList("RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND")) {
            if (battery.has(key)) validateScopedOpObject(objectMember(battery, key), "batterySettings." + key);
        }
    }

    private static Map<Integer, Integer> readPackageOps(AppOpsManagerHidden appOps, int uid, String packageName) {
        Map<Integer, Integer> out = new LinkedHashMap<>();
        try {
            List<AppOpsManagerHidden.PackageOps> list = appOps.getOpsForPackage(uid, packageName, null);
            if (list != null && !list.isEmpty() && list.get(0).getOps() != null) {
                for (AppOpsManagerHidden.OpEntry entry : list.get(0).getOps()) {
                    out.put(entry.getOp(), entry.getMode());
                }
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    private static int getOpMode(AppOpsManagerHidden appOps, int op, int uid, String packageName) {
        if (op == AppOpsManagerHidden.OP_NONE) return AppOpsManagerHidden.MODE_DEFAULT;
        try {
            return appOps.unsafeCheckOpRawNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        try {
            return appOps.checkOpNoThrow(op, uid, packageName);
        } catch (Throwable ignored) {
        }
        return AppOpsManagerHidden.MODE_DEFAULT;
    }

    private static int getEffectiveOpMode(AppOpsManagerHidden appOps, int op, int uid, String packageName) {
        // unsafeCheckOpRawNoThrow/checkOpNoThrow are suitable for the effective result only.
        // Stored package and uid scopes are captured separately by AppOpsCompat.
        return getOpMode(appOps, op, uid, packageName);
    }

    private static int resolveOp(String publicName) {
        Integer cached = OP_CACHE.get(publicName);
        if (cached != null) return cached;
        int op = AppOpsManagerHidden.OP_NONE;
        try {
            op = AppOpsManagerHidden.strOpToOp(publicName);
        } catch (Throwable ignored) {
        }
        if (op == AppOpsManagerHidden.OP_NONE) {
            try {
                String fieldName = "OP_" + publicName.substring(publicName.indexOf(':') + 1)
                        .toUpperCase(Locale.ROOT);
                Class<?> clazz = HiddenApiReflection.classForNameCached("android.app.AppOpsManager");
                java.lang.reflect.Field field = clazz.getDeclaredField(fieldName);
                field.setAccessible(true);
                op = field.getInt(null);
            } catch (Throwable ignored) {
            }
        }
        OP_CACHE.put(publicName, op);
        return op;
    }

    private static String publicOpName(int op) {
        try {
            String name = AppOpsManagerHidden.opToPublicName(op);
            if (name != null && !name.isEmpty()) return name;
        } catch (Throwable ignored) {
        }
        try {
            String name = AppOpsManagerHidden.opToName(op);
            if (name != null && !name.isEmpty()) return "android:" + name.toLowerCase(Locale.ROOT);
        } catch (Throwable ignored) {
        }
        return "android:op_" + op;
    }

    private static String modeName(int mode) {
        switch (mode) {
            case AppOpsManagerHidden.MODE_ALLOWED: return "allow";
            case AppOpsManagerHidden.MODE_IGNORED: return "ignore";
            case AppOpsManagerHidden.MODE_ERRORED: return "deny";
            case AppOpsManagerHidden.MODE_DEFAULT: return "default";
            case AppOpsManagerHidden.MODE_FOREGROUND: return "foreground";
            default: return String.valueOf(mode);
        }
    }

    private static boolean allowedMode(int mode) {
        return mode == AppOpsManagerHidden.MODE_ALLOWED || mode == AppOpsManagerHidden.MODE_FOREGROUND;
    }

    private static boolean equivalentAllowedMode(int actual, int expected) {
        return allowedMode(actual) && allowedMode(expected);
    }

    private static boolean isSpecialAccessRequested(SpecialAccessDescriptor descriptor, PackageInfo packageInfo) {
        if (descriptor.requirePictureInPictureActivity) {
            if (packageInfo.activities == null) return false;
            for (ActivityInfo activityInfo : packageInfo.activities) {
                if (activityInfo != null
                        && (activityInfo.flags & ActivityInfoHidden.FLAG_SUPPORTS_PICTURE_IN_PICTURE) != 0) {
                    return true;
                }
            }
            return false;
        }
        if (descriptor.manifestPermission == null) return true;
        if (packageInfo.requestedPermissions == null) return false;
        for (String permission : packageInfo.requestedPermissions) {
            if (descriptor.manifestPermission.equals(permission)) return true;
        }
        return false;
    }

    private static int[] permissionProtection(PackageManager pm, String permissionName)
            throws PackageManager.NameNotFoundException {
        int[] cached = PERMISSION_PROTECTION_CACHE.get(permissionName);
        if (cached != null) return cached;
        PermissionInfo info = pm.getPermissionInfo(permissionName, 0);
        int[] value = new int[] {
                info.protectionLevel & 0x0000000f,
                info.protectionLevel & 0xfffffff0
        };
        PERMISSION_PROTECTION_CACHE.put(permissionName, value);
        return value;
    }

    private static Set<String> getDeviceIdleWhitelist() {
        Set<String> result = new HashSet<>();
        try {
            Object service = HiddenApiServices.deviceIdle();
            Object names = HiddenApiReflection.callFirst(service,
                    new HiddenApiReflection.Call("getFullPowerWhitelist"),
                    new HiddenApiReflection.Call("getFullPowerWhitelistExceptIdle"));
            if (names instanceof String[]) {
                result.addAll(Arrays.asList((String[]) names));
                result.remove(null);
                result.remove("");
                return result;
            }
        } catch (Throwable ignored) {
        }
        try {
            Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", "dumpsys deviceidle whitelist"});
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    for (String token : line.split("[,\\s]+")) {
                        String value = token.trim();
                        if (value.contains(".") && value.matches("[A-Za-z0-9._-]+")) result.add(value);
                    }
                }
            }
            process.waitFor();
        } catch (Throwable ignored) {
        }
        return result;
    }

    private static int snapshotPackageFlags() {
        int flags = PackageManager.GET_PERMISSIONS | PackageManager.GET_ACTIVITIES;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            flags |= PackageManager.GET_SIGNING_CERTIFICATES;
        } else {
            //noinspection deprecation
            flags |= PackageManager.GET_SIGNATURES;
        }
        return flags;
    }

    private static JsonObject collectInstallDiagnostics(PackageManager pm, PackageInfo packageInfo,
                                                        String installerFallback,
                                                        GooglePackageSnapshot playStore,
                                                        GooglePackageSnapshot playServices) {
        JsonObject out = new JsonObject();
        String installing = installerFallback;
        String initiating = null;
        String originating = null;
        String updateOwner = null;
        String packageSource = "null";
        String packageSourceName = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ? "UNKNOWN" : "UNAVAILABLE_API_LT_30";
        String updateOwnerApi = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                ? "api34_plus" : "unsupported_pre34";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                Object info = HiddenApiReflection.invokeFlexible(pm, "getInstallSourceInfo", packageInfo.packageName);
                installing = firstNonEmpty(safeString(invokeNoArg(info, "getInstallingPackageName")), installerFallback);
                initiating = safeString(invokeNoArg(info, "getInitiatingPackageName"));
                originating = safeString(invokeNoArg(info, "getOriginatingPackageName"));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    updateOwner = safeString(invokeNoArg(info, "getUpdateOwnerPackageName"));
                }
                Object source = invokeNoArg(info, "getPackageSource");
                if (source instanceof Number) {
                    int value = ((Number) source).intValue();
                    packageSource = String.valueOf(value);
                    packageSourceName = packageSourceToName(value);
                }
            } catch (Throwable ignored) {
            }
        }
        addNullable(out, "installer", installerFallback);
        addNullable(out, "installing", installing);
        addNullable(out, "initiating", initiating);
        addNullable(out, "originating", originating);
        addNullable(out, "updateOwner", updateOwner);
        out.addProperty("updateOwnerApi", updateOwnerApi);
        out.addProperty("packageSource", packageSource);
        out.addProperty("packageSourceName", packageSourceName);
        long versionCode = longVersionCode(packageInfo);
        String signingSha256 = signingSha256(packageInfo);
        int splitCount = packageInfo.splitNames == null ? 0 : packageInfo.splitNames.length;
        out.addProperty("versionCode", versionCode);
        out.addProperty("versionName", packageInfo.versionName == null ? "" : packageInfo.versionName);
        out.addProperty("signingSha256", signingSha256);
        out.addProperty("splitCount", splitCount);
        addNullable(out, "sourceDir", packageInfo.applicationInfo == null ? null : packageInfo.applicationInfo.sourceDir);
        addGooglePackageDiagnostics(out, "playStore", playStore);
        addGooglePackageDiagnostics(out, "playServices", playServices);
        addPlayRestoreRisks(out, installerFallback, updateOwner, versionCode, signingSha256, splitCount,
                playStore == null ? "missing" : playStore.state,
                playServices == null ? "missing" : playServices.state);
        return out;
    }

    private static GooglePackageSnapshot googlePackageSnapshot(
            PackageManager realPm, PackageManagerHidden pmHidden, AppOpsManagerHidden appOps,
            Set<String> idleWhitelist, int userId, String packageName) {
        return GooglePackageSnapshot.collect(realPm, pmHidden, appOps, idleWhitelist, userId, packageName);
    }

    private static void addGooglePackageDiagnostics(JsonObject out, String prefix,
                                                    GooglePackageSnapshot snapshot) {
        GooglePackageSnapshot value = snapshot == null ? new GooglePackageSnapshot() : snapshot;
        out.addProperty(prefix, value.state);
        out.addProperty(prefix + "EnabledState", value.enabledState);
        out.addProperty(prefix + "Uid", value.uid);
        out.addProperty(prefix + "VersionCode", value.versionCode);
        out.addProperty(prefix + "RunInBackgroundMode", value.runInBackgroundMode);
        out.addProperty(prefix + "RunAnyInBackgroundMode", value.runAnyInBackgroundMode);
        out.addProperty(prefix + "DeviceIdleWhitelist", value.deviceIdleWhitelist);
    }

    private static void addPlayRestoreRisks(JsonObject out, String installer, String updateOwner,
                                            long versionCode, String signingSha256, int splitCount,
                                            String playStoreState, String playServicesState) {
        if (installer == null || installer.isEmpty()) {
            out.addProperty("risk_INSTALLER_NULL", "SET_INSTALLER_IF_PLAY_APP");
        } else if (!"com.android.vending".equals(installer)) {
            out.addProperty("risk_INSTALLER_NOT_PLAY", "SET_INSTALLER_COM_ANDROID_VENDING_IF_NEEDED");
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                && "com.android.vending".equals(updateOwner)) {
            out.addProperty("risk_UPDATE_OWNER_PLAY_API34_PLUS",
                    "USE_PLAY_UPDATE_OR_REINSTALL_WITH_CORRECT_SESSION");
        }
        if (versionCode <= 0) out.addProperty("risk_VERSION_UNKNOWN", "REINSTALL_CORRECT_APK");
        if (signingSha256 == null || signingSha256.isEmpty() || "null".equals(signingSha256)) {
            out.addProperty("risk_SIGNATURE_UNREADABLE", "REINSTALL_CORRECT_SIGNED_APK");
        }
        if (splitCount > 0) out.addProperty("risk_HAS_SPLITS", "BACKUP_AND_RESTORE_ALL_SPLIT_APKS");
        if (!"installed_enabled".equals(playStoreState)) {
            out.addProperty("risk_PLAY_STORE_NOT_READY", "ENABLE_OR_RESTORE_COM_ANDROID_VENDING");
        }
        if (!"installed_enabled".equals(playServicesState)) {
            out.addProperty("risk_PLAY_SERVICES_NOT_READY", "ENABLE_OR_RESTORE_COM_GOOGLE_ANDROID_GMS");
        }
    }

    private static Object invokeNoArg(Object target, String methodName) {
        if (target == null) return null;
        try {
            return HiddenApiReflection.invokeFlexible(target, methodName);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonEmpty(String first, String second) {
        return first != null && !first.isEmpty() ? first : second;
    }

    private static void addNullable(JsonObject object, String key, String value) {
        if (value == null || value.isEmpty()) addJsonNull(object, key);
        else object.addProperty(key, value);
    }

    private static volatile Map<Integer, String> PACKAGE_SOURCE_NAMES;

    private static String packageSourceToName(int source) {
        Map<Integer, String> map = PACKAGE_SOURCE_NAMES;
        if (map == null) {
            map = new HashMap<>();
            try {
                Class<?> clazz = HiddenApiReflection.classForNameCached("android.content.pm.PackageInstaller");
                for (java.lang.reflect.Field field : clazz.getFields()) {
                    if (field.getName().startsWith("PACKAGE_SOURCE_") && field.getType() == int.class) {
                        map.put(field.getInt(null), field.getName());
                    }
                }
            } catch (Throwable ignored) {
            }
            PACKAGE_SOURCE_NAMES = map;
        }
        String name = map.get(source);
        return name == null ? "UNKNOWN_" + source : name;
    }

    private static String signingSha256(PackageInfo packageInfo) {
        try {
            android.content.pm.Signature[] signatures = null;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && packageInfo.signingInfo != null) {
                signatures = packageInfo.signingInfo.hasMultipleSigners()
                        ? packageInfo.signingInfo.getApkContentsSigners()
                        : packageInfo.signingInfo.getSigningCertificateHistory();
            }
            //noinspection deprecation
            if ((signatures == null || signatures.length == 0) && packageInfo.signatures != null) {
                //noinspection deprecation
                signatures = packageInfo.signatures;
            }
            if (signatures == null || signatures.length == 0) return "null";
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            List<String> hashes = new ArrayList<>();
            for (android.content.pm.Signature signature : signatures) {
                if (signature != null) hashes.add(bytesToHex(digest.digest(signature.toByteArray())));
            }
            return hashes.isEmpty() ? "null" : String.join(",", hashes);
        } catch (Throwable ignored) {
            return "null";
        }
    }

    private static String bytesToHex(byte[] bytes) {
        char[] hex = "0123456789abcdef".toCharArray();
        char[] out = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int value = bytes[i] & 0xff;
            out[i * 2] = hex[value >>> 4];
            out[i * 2 + 1] = hex[value & 0x0f];
        }
        return new String(out);
    }

    private static long longVersionCode(PackageInfo info) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return info.getLongVersionCode();
        //noinspection deprecation
        return info.versionCode;
    }

    private static String safeLabel(PackageManager pm, ApplicationInfo info) {
        try {
            CharSequence value = info.loadLabel(pm);
            return value == null ? "" : value.toString().replace('\n', ' ').trim();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static Map<String, SpecialAccessDescriptor> buildSpecialAccessMap() {
        Map<String, SpecialAccessDescriptor> out = new LinkedHashMap<>();
        for (SpecialAccessDescriptor descriptor : SPECIAL_ACCESS) out.put(descriptor.key, descriptor);
        return Collections.unmodifiableMap(out);
    }

    private static void addCapability(JsonArray array, String name, boolean enabled, boolean critical, String protocol) {
        JsonObject item = new JsonObject();
        item.addProperty("name", name);
        item.addProperty("enabled", enabled);
        item.addProperty("critical", critical);
        item.addProperty("protocol", protocol);
        array.add(item);
    }

    private static JsonObject baseRecord(String recordType, int userId, String packageName) {
        JsonObject root = new JsonObject();
        root.addProperty("schemaVersion", SCHEMA_VERSION);
        root.addProperty("engineVersion", ENGINE_VERSION);
        root.addProperty("dexVersion", HiddenApiUtil.VERSION);
        root.addProperty("recordType", recordType);
        root.addProperty("userId", userId);
        root.addProperty("packageName", packageName == null ? "" : packageName);
        return root;
    }

    private static JsonObject packageErrorRecord(String recordType, int userId, String packageName,
                                                 ResultCode code, String message) {
        JsonObject root = baseRecord(recordType, userId, packageName);
        setResult(root, code, message);
        return root;
    }

    private static JsonObject summaryRecord(String command, ResultCode code, int total, int ok,
                                            int partial, int failed, String message) {
        JsonObject root = new JsonObject();
        root.addProperty("schemaVersion", SCHEMA_VERSION);
        root.addProperty("engineVersion", ENGINE_VERSION);
        root.addProperty("recordType", "summary");
        root.addProperty("command", command);
        root.addProperty("total", total);
        root.addProperty("ok", ok);
        root.addProperty("partial", partial);
        root.addProperty("failed", failed);
        setResult(root, code, message);
        return root;
    }

    private static void setResult(JsonObject root, ResultCode code, String message) {
        JsonObject result = new JsonObject();
        result.addProperty("code", code.code);
        result.addProperty("name", code.name());
        result.addProperty("retryable", code.retryable);
        if (message == null || message.isEmpty()) addJsonNull(result, "message");
        else result.addProperty("message", message);
        root.add("result", result);
    }

    private static JsonObject errorObject(String field, ResultCode code, String message) {
        JsonObject item = new JsonObject();
        item.addProperty("field", field);
        item.addProperty("code", code.code);
        item.addProperty("name", code.name());
        item.addProperty("message", message);
        return item;
    }

    /** Structured daemon framing/protocol error; package-private for AppStateUtil. */
    static EngineResponse protocolError(ResultCode code, String message) {
        ResultCode safeCode = code == null ? ResultCode.INTERNAL_ERROR : code;
        return errorResponse(safeCode, "daemon", null, safe(message));
    }

    private static EngineResponse errorResponse(ResultCode code, String command, String packageName, String message) {
        JsonObject root = new JsonObject();
        root.addProperty("schemaVersion", SCHEMA_VERSION);
        root.addProperty("engineVersion", ENGINE_VERSION);
        root.addProperty("recordType", "error");
        root.addProperty("command", command == null ? "" : command);
        if (packageName == null) addJsonNull(root, "packageName");
        else root.addProperty("packageName", packageName);
        setResult(root, code, message);
        return new EngineResponse(code, GSON.toJson(root) + "\n");
    }

    private static EngineResponse batchSummaryOnly(String command, ResultCode code, int total, int ok,
                                                   int partial, int failed, String message) {
        return new EngineResponse(code,
                GSON.toJson(summaryRecord(command, code, total, ok, partial, failed, message)) + "\n");
    }

    private static ResultCode resultCodeFromRecord(JsonObject record) {
        try {
            String name = record.getAsJsonObject("result").get("name").getAsString();
            return ResultCode.valueOf(name);
        } catch (Throwable ignored) {
            return ResultCode.INTERNAL_ERROR;
        }
    }

    private static ResultCode mergeResult(ResultCode current, ResultCode next) {
        if (current == ResultCode.INTERNAL_ERROR || current == ResultCode.PERMISSION_DENIED
                || current == ResultCode.BAD_REQUEST || current == ResultCode.PACKAGE_NOT_FOUND) return current;
        if (next == ResultCode.INTERNAL_ERROR || next == ResultCode.PERMISSION_DENIED
                || next == ResultCode.BAD_REQUEST || next == ResultCode.PACKAGE_NOT_FOUND) return next;
        if (current == ResultCode.VERIFY_MISMATCH || next == ResultCode.VERIFY_MISMATCH) return ResultCode.VERIFY_MISMATCH;
        if (current == ResultCode.PARTIAL || next == ResultCode.PARTIAL || next == ResultCode.UNSUPPORTED) return ResultCode.PARTIAL;
        return ResultCode.OK;
    }

    private static ResultCode classifyThrowable(Throwable e) {
        Throwable cur = e;
        while (cur != null) {
            if (cur instanceof PackageManager.NameNotFoundException) return ResultCode.PACKAGE_NOT_FOUND;
            cur = cur.getCause();
        }
        if (e instanceof SecurityException) return ResultCode.PERMISSION_DENIED;
        if (e instanceof UnsupportedOperationException) return ResultCode.UNSUPPORTED;
        if (e instanceof IllegalArgumentException) return ResultCode.BAD_REQUEST;
        return ResultCode.INTERNAL_ERROR;
    }

    private static List<String> dedupePackages(List<String> packageNames) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if (packageNames != null) {
            for (String packageName : packageNames) {
                if (packageName == null) continue;
                String value = packageName.trim();
                if (value.isEmpty() || value.startsWith("#")) continue;
                out.add(value);
            }
        }
        return new ArrayList<>(out);
    }

    private static List<JsonObject> parseJsonRecords(String ndjson) {
        List<JsonObject> out = new ArrayList<>();
        if (ndjson == null) return out;
        int lineNo = 0;
        for (String line : ndjson.split("\\r?\\n")) {
            lineNo++;
            String value = line.trim();
            if (value.isEmpty() || value.startsWith("#")) continue;
            try {
                JsonElement element = JsonParser.parseString(value);
                if (!element.isJsonObject()) throw new IllegalArgumentException("line " + lineNo + " is not a JSON object");
                JsonObject object = element.getAsJsonObject();
                if ("summary".equals(stringMember(object, "recordType"))) continue;
                out.add(object);
            } catch (RuntimeException e) {
                throw new IllegalArgumentException("invalid NDJSON at line " + lineNo + ": " + failureMessage(e), e);
            }
        }
        return out;
    }

    private static JsonObject objectMember(JsonObject object, String name) {
        if (object == null || !object.has(name) || !object.get(name).isJsonObject()) return null;
        return object.getAsJsonObject(name);
    }

    private static String stringMember(JsonObject object, String name) {
        try {
            if (object == null || !object.has(name) || object.get(name).isJsonNull()) return "";
            return object.get(name).getAsString();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static int intMember(JsonObject object, String name, int fallback) {
        try {
            if (object == null || !object.has(name) || object.get(name).isJsonNull()) return fallback;
            return object.get(name).getAsInt();
        } catch (Throwable ignored) {
            return fallback;
        }
    }


    private static String normalizeCommand(String command) {
        if (command == null) return "";
        String value = command.trim().toLowerCase(Locale.ROOT);
        switch (value) {
            case "snapshotappstatebatch": return "snapshot";
            case "foreground":
            case "foregroundstate":
            case "foregroundstatebatch":
            case "processstatebatch": return "foregroundstate";
            case "foregroundrunning":
            case "foregroundrunningbatch":
            case "foregroundstaterunning":
            case "foregroundstaterunningbatch": return "foregroundrunning";
            case "foregroundlist":
            case "foregroundlistjson":
            case "foregroundstatelist":
            case "foregroundstatejson":
            case "foregroundjson": return "foregroundlist";
            case "foregroundtop":
            case "foregroundtopapp": return "foregroundtop";
            case "restoreappstatebatch": return "restore";
            case "verifyappstatebatch": return "verify";
            default: return value;
        }
    }

    private static String failureMessage(Throwable e) {
        if (e == null) return "unknown";
        Throwable cause = e.getCause() != null ? e.getCause() : e;
        String message = cause.getMessage();
        if (message == null || message.trim().isEmpty()) message = cause.getClass().getSimpleName();
        return safe(message);
    }

    private static String safe(String value) {
        if (value == null) return "";
        return value.replace('\n', ' ').replace('\r', ' ').replace('\t', ' ').trim();
    }
}
