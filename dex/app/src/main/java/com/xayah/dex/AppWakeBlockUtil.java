package com.xayah.dex;

import com.xayah.dex.compat.ActivityCompat;
import com.xayah.dex.compat.AppOpsCompat;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;

import android.app.AppOpsManagerHidden;
import android.content.Context;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Short-window wake block for backup payloads.
 *
 * Design intent:
 * - normal: force-stop only; relies on Android stopped state and observer guard.
 * - appops: temporarily deny/ignore background AppOps, then restore.
 * - restricted: appops + standby bucket restricted, then restore.
 *
 * This deliberately avoids pm disable/hide/suspend by default. Those are hard-freeze
 * tools with launcher/cache side effects and should not be the normal backup path.
 */
final class AppWakeBlockUtil {
    static final String VERSION = "v2.2-r487-run-tmpdir-state-scope";
    private static final SimpleDateFormat TS = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);
    private static final long PROCESS_START_MS = System.currentTimeMillis();
    private static final String PROCESS_SESSION_ID = android.os.Process.myPid() + "-" + PROCESS_START_MS;
    private static final AtomicInteger NEXT_TOKEN = new AtomicInteger(tokenSeed());
    private static final Map<Integer, WakeBlockSession> SESSIONS = new HashMap<>();
    private static final String OP_RUN_IN_BACKGROUND = "RUN_IN_BACKGROUND";
    private static final String OP_RUN_ANY_IN_BACKGROUND = "RUN_ANY_IN_BACKGROUND";
    private static final String STATE_DIR = scopedPath("SPEEDBACKUP_WAKEBLOCK_STATE_DIR", ".speedbackup_wakeblock_state");
    private static final long STATE_TTL_MS = 24L * 60L * 60L * 1000L;


    private static String scopedTmpDir() {
        String run = System.getenv("SPEEDBACKUP_RUN_TMPDIR");
        if (run != null && run.length() > 0) return run;
        String tmp = System.getenv("TMPDIR");
        if (tmp != null && tmp.contains(".speedbackup_run_") && tmp.length() > 0) return tmp;
        return "/data/local/tmp/.speedbackup_run_dex_" + android.os.Process.myPid();
    }

    private static String scopedPath(String envName, String name) {
        String env = System.getenv(envName);
        if (env != null && env.length() > 0) return env;
        File dir = new File(scopedTmpDir());
        try { dir.mkdirs(); } catch (Throwable ignored) {}
        return new File(dir, name).getAbsolutePath();
    }

    private AppWakeBlockUtil() {}

    static synchronized String start(int userId, String packageName, String mode, String logPath) {
        return start(userId, packageName, mode, logPath, -1, "direct");
    }

    static synchronized String start(int userId, String packageName, String mode, String logPath, int ownerToken, String ownerKind) {
        int token = NEXT_TOKEN.incrementAndGet();
        WakeBlockSession session = new WakeBlockSession(token, userId, safePackage(packageName), normalizeMode(mode), logPath);
        session.ownerToken = ownerToken;
        session.ownerKind = ownerKind == null ? "" : ownerKind.trim();
        try {
            session.apply();
            SESSIONS.put(token, session);
            return "APP_WAKE_BLOCK_START_OK token=" + token
                    + " user=" + userId
                    + " package=" + session.packageName
                    + " mode=" + session.mode
                    + " ownerToken=" + ownerToken
                    + " ownerKind=" + sanitize(session.ownerKind)
                    + " log=" + sanitize(logPath) + "\n";
        } catch (Throwable t) {
            try { session.restore("start-failed"); } catch (Throwable ignored) {}
            return "APP_WAKE_BLOCK_START_FAILED token=" + token
                    + " user=" + userId
                    + " package=" + session.packageName
                    + " mode=" + session.mode
                    + " ownerToken=" + ownerToken
                    + " ownerKind=" + sanitize(session.ownerKind)
                    + " exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage()) + "\n";
        }
    }

    static synchronized String stop(int token) {
        return stop(token, -1, "");
    }

    static synchronized String stop(int token, int expectedUserId, String expectedPackageName) {
        WakeBlockSession session = SESSIONS.remove(token);
        if (session == null) {
            return "APP_WAKE_BLOCK_STOP_MISSING token=" + token
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName) + "\n"
                    + restorePersistedWakeBlockToken(token, "stop-missing-" + token, expectedUserId, expectedPackageName);
        }
        return session.restore("stop-token-" + token);
    }

    static synchronized String restorePersistedWakeBlockToken(int token, String reason) {
        return restorePersistedWakeBlockToken(token, reason, -1, "");
    }

    static synchronized String restorePersistedWakeBlockToken(int token, String reason, int expectedUserId, String expectedPackageName) {
        File file = findStateByWakeToken(token, expectedUserId, expectedPackageName);
        if (file == null) {
            return "APP_WAKE_BLOCK_PERSISTENT_RESTORE_MISSING token=" + token
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName)
                    + " reason=" + sanitize(reason) + "\n";
        }
        return restorePersistedFile(file, reason, "wake-token", token, -1, expectedUserId, safePackage(expectedPackageName));
    }

    static synchronized String restorePersistedObserverToken(int observerToken, String reason) {
        return restorePersistedObserverToken(observerToken, reason, -1, "");
    }

    static synchronized String restorePersistedObserverToken(int observerToken, String reason, int expectedUserId, String expectedPackageName) {
        File file = findStateByOwnerToken(observerToken, "processObserver", expectedUserId, expectedPackageName);
        if (file == null) {
            return "APP_WAKE_BLOCK_PERSISTENT_RESTORE_MISSING ownerToken=" + observerToken
                    + " ownerKind=processObserver"
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName)
                    + " reason=" + sanitize(reason) + "\n";
        }
        return restorePersistedFile(file, reason, "process-observer-token", -1, observerToken, expectedUserId, safePackage(expectedPackageName));
    }

    static synchronized String restorePersistedPackage(int userId, String packageName, String reason) {
        String pkg = safePackage(packageName);
        File file = findStateByPackage(userId, pkg);
        if (file == null) {
            return "APP_WAKE_BLOCK_PERSISTENT_RESTORE_MISSING user=" + userId
                    + " package=" + pkg
                    + " reason=" + sanitize(reason) + "\n";
        }
        return restorePersistedFile(file, reason, "package", -1, -1, userId, pkg);
    }

    static synchronized String restorePersistedAll(String reason) {
        StringBuilder out = new StringBuilder();
        File dir = stateDir();
        File[] files = dir.listFiles();
        int total = 0;
        int restored = 0;
        if (files != null) {
            for (File f : files) {
                if (f == null || !f.isFile() || !f.getName().endsWith(".properties")) continue;
                total++;
                String r = restorePersistedFile(f, reason, "all", -1, -1, -1, "");
                out.append(r);
                if (restoreDoneAndStateDeleted(r)) restored++;
            }
        }
        out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_ALL_DONE total=").append(total)
                .append(" restored=").append(restored)
                .append(" reason=").append(sanitize(reason)).append('\n');
        return out.toString();
    }



    static synchronized String cleanupStalePersistentStates(String reason) {
        return cleanupStalePersistentStates(reason, STATE_TTL_MS);
    }

    static synchronized String cleanupStalePersistentStates(String reason, long ttlMs) {
        long ttl = ttlMs < 0L ? STATE_TTL_MS : ttlMs;
        long now = System.currentTimeMillis();
        StringBuilder out = new StringBuilder();
        File[] files = stateDir().listFiles();
        int total = 0;
        int stale = 0;
        int restored = 0;
        int deleted = 0;
        out.append("APP_WAKE_BLOCK_PERSISTENT_CLEANUP_BEGIN reason=").append(sanitize(reason))
                .append(" ttlMs=").append(ttl).append('\n');
        if (files != null) {
            for (File f : files) {
                if (!isStateFile(f)) continue;
                total++;
                Properties p = readProperties(f);
                long updatedAt = parseLong(p.getProperty("updatedAt"), f.lastModified());
                long ageMs = Math.max(0L, now - updatedAt);
                if (ageMs < ttl) continue;
                stale++;
                out.append("APP_WAKE_BLOCK_PERSISTENT_CLEANUP_STALE path=").append(sanitize(f.getAbsolutePath()))
                        .append(" ageMs=").append(ageMs)
                        .append(" token=").append(sanitize(p.getProperty("token", "")))
                        .append(" ownerToken=").append(sanitize(p.getProperty("ownerToken", "")))
                        .append(" user=").append(sanitize(p.getProperty("user", "")))
                        .append(" package=").append(sanitize(p.getProperty("package", ""))).append('\n');
                String r = restorePersistedFile(f, "stale-cleanup-" + sanitize(reason), "stale-cleanup", -1, -1, -1, "");
                out.append(r);
                if (restoreDoneAndStateDeleted(r)) restored++;
                boolean del = !f.exists() || f.delete();
                if (del) deleted++;
                out.append("APP_WAKE_BLOCK_PERSISTENT_CLEANUP_DELETE path=").append(sanitize(f.getAbsolutePath()))
                        .append(" deleted=").append(del)
                        .append(" restoreDone=").append(restoreDoneAndStateDeleted(r))
                        .append(" reason=").append(sanitize(reason)).append('\n');
            }
        }
        out.append("APP_WAKE_BLOCK_PERSISTENT_CLEANUP_DONE total=").append(total)
                .append(" stale=").append(stale)
                .append(" restored=").append(restored)
                .append(" deleted=").append(deleted)
                .append(" reason=").append(sanitize(reason)).append('\n');
        return out.toString();
    }

    static synchronized String status() {
        StringBuilder out = new StringBuilder();
        out.append("APP_WAKE_BLOCK_STATUS total=").append(SESSIONS.size())
                .append(" persistent=").append(countPersistentStates()).append('\n');
        for (Map.Entry<Integer, WakeBlockSession> e : SESSIONS.entrySet()) {
            WakeBlockSession s = e.getValue();
            out.append("APP_WAKE_BLOCK_SESSION token=").append(e.getKey())
                    .append(" user=").append(s.userId)
                    .append(" package=").append(s.packageName)
                    .append(" mode=").append(s.mode)
                    .append(" applied=").append(s.applied)
                    .append(" restored=").append(s.restored)
                    .append('\n');
        }
        return out.toString();
    }

    static String hold(int userId, String packageName, long durationMs, String mode, String logPath) {
        int token = NEXT_TOKEN.incrementAndGet();
        WakeBlockSession session = new WakeBlockSession(token, userId, safePackage(packageName), normalizeMode(mode), logPath);
        StringBuilder out = new StringBuilder();
        try {
            session.apply();
            out.append("APP_WAKE_BLOCK_HOLD_OK token=").append(token)
                    .append(" user=").append(userId)
                    .append(" package=").append(session.packageName)
                    .append(" mode=").append(session.mode)
                    .append(" durationMs=").append(Math.max(1000L, durationMs)).append('\n');
            try { new CountDownLatch(1).await(Math.max(1000L, durationMs), TimeUnit.MILLISECONDS); }
            catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
            out.append(session.restore("hold-timeout"));
        } catch (Throwable t) {
            out.append("APP_WAKE_BLOCK_HOLD_FAILED token=").append(token)
                    .append(" exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
            try { out.append(session.restore("hold-failed")); } catch (Throwable ignored) {}
        }
        return out.toString();
    }

    private static final class WakeBlockSession {
        final int token;
        final int userId;
        final String packageName;
        final String mode;
        final String logPath;
        int targetUid = -1;
        boolean applied;
        boolean restored;
        PrintWriter log;
        String originalRunInBackground = "unknown";
        String originalRunAnyInBackground = "unknown";
        String originalStandbyBucket = "unknown";
        boolean originalDeviceIdleWhitelist;
        boolean deviceIdleWhitelistSnapshotKnown;
        boolean runInBackgroundTouched;
        boolean runAnyInBackgroundTouched;
        boolean standbyTouched;
        boolean deviceIdleWhitelistTouched;
        int ownerToken = -1;
        String ownerKind = "";
        int restoreAttempts = 0;

        WakeBlockSession(int token, int userId, String packageName, String mode, String logPath) {
            this.token = token;
            this.userId = userId;
            this.packageName = packageName;
            this.mode = mode;
            this.logPath = logPath == null ? "" : logPath.trim();
        }

        void apply() throws Exception {
            if (packageName.isEmpty()) throw new IllegalArgumentException("packageName is empty");
            log = openLog(logPath);
            targetUid = resolveTargetUid(userId, packageName);
            CURRENT_USER.set(userId);
            CURRENT_PACKAGE.set(packageName);
            CURRENT_UID.set(targetUid);
            logLine("APP_WAKE_BLOCK_START schema=speedbackup.app_wake_block.v1 version=" + VERSION
                    + " user=" + userId + " package=" + packageName + " uid=" + targetUid
                    + " mode=" + mode + " token=" + token
                    + " ownerToken=" + ownerToken
                    + " ownerKind=" + sanitize(ownerKind));
            snapshot();
            persistState("snapshot");
            boolean forceStopApplied = false;
            boolean forceStopSkipped = true;
            logLine("APP_WAKE_BLOCK_APPLY stage=force-stop skipped=true ok=true reason=cgroup-first-no-force-stop detail=forceStop=skipped");
            if (usesAppOps(mode)) {
                applyAppOp(OP_RUN_IN_BACKGROUND, "ignore");
                applyAppOp(OP_RUN_ANY_IN_BACKGROUND, "deny");
            } else {
                logLine("APP_WAKE_BLOCK_APPLY stage=appops skipped=true reason=mode-" + mode);
            }
            if (usesRestrictedBucket(mode)) {
                applyStandbyBucket("restricted");
            } else {
                logLine("APP_WAKE_BLOCK_APPLY stage=standby skipped=true reason=mode-" + mode);
            }
            applied = true;
            persistState("apply-done");
            logLine("APP_WAKE_BLOCK_APPLY_DONE user=" + userId + " package=" + packageName + " mode=" + mode
                    + " forceStopApplied=" + forceStopApplied
                    + " forceStopSkipped=" + forceStopSkipped
                    + " runBgTouched=" + runInBackgroundTouched
                    + " runAnyTouched=" + runAnyInBackgroundTouched
                    + " standbyTouched=" + standbyTouched);
        }

        private void snapshot() {
            originalRunInBackground = snapshotAppOp(OP_RUN_IN_BACKGROUND);
            originalRunAnyInBackground = snapshotAppOp(OP_RUN_ANY_IN_BACKGROUND);
            originalStandbyBucket = snapshotStandbyBucket();
            originalDeviceIdleWhitelist = snapshotDeviceIdleWhitelist();
            logLine("APP_WAKE_BLOCK_SNAPSHOT user=" + userId
                    + " package=" + packageName
                    + " runBg=" + originalRunInBackground
                    + " runAny=" + originalRunAnyInBackground
                    + " standbyBucket=" + originalStandbyBucket
                    + " deviceIdleWhitelist=" + originalDeviceIdleWhitelist
                    + " deviceIdleSnapshotKnown=" + deviceIdleWhitelistSnapshotKnown
                    + " snapshotSafe=" + snapshotSafe());
        }

        private boolean snapshotSafe() {
            if (usesAppOps(mode) && ("unknown".equals(originalRunInBackground) || "unknown".equals(originalRunAnyInBackground))) return false;
            if (usesRestrictedBucket(mode) && "unknown".equals(originalStandbyBucket)) return false;
            return true;
        }

        private String snapshotAppOp(String op) {
            DirectAppOpSnapshot direct = snapshotAppOpDirect(op);
            if (direct.ok) {
                logLine("APP_WAKE_BLOCK_SNAPSHOT_OP op=" + op
                        + " mode=" + direct.snapshot.restoreMode
                        + " packageMode=" + direct.snapshot.packageMode
                        + " uidMode=" + direct.snapshot.uidMode
                        + " effectiveMode=" + direct.snapshot.effectiveMode
                        + " source=" + direct.snapshot.source
                        + " provider=direct rc=0 raw=" + sanitize(direct.raw));
                return direct.snapshot.restoreMode;
            }
            ShellResult r = runShell("cmd appops get --user " + userId + " " + shellQuote(packageName) + " " + op,
                    "cmd appops get " + shellQuote(packageName) + " " + op);
            AppOpSnapshot snapshot = parseAppOpsSnapshot(op, r.out);
            logLine("APP_WAKE_BLOCK_SNAPSHOT_OP op=" + op
                    + " mode=" + snapshot.restoreMode
                    + " packageMode=" + snapshot.packageMode
                    + " uidMode=" + snapshot.uidMode
                    + " effectiveMode=" + snapshot.effectiveMode
                    + " source=" + snapshot.source
                    + " provider=shell directError=" + sanitize(direct.error)
                    + " rc=" + r.rc
                    + " raw=" + sanitize(r.out));
            return snapshot.restoreMode;
        }

        private String snapshotStandbyBucket() {
            DirectStandbySnapshot direct = snapshotStandbyBucketDirect();
            if (direct.ok) {
                logLine("APP_WAKE_BLOCK_SNAPSHOT_BUCKET bucket=" + direct.snapshot.bucket
                        + " rawBucket=" + direct.snapshot.rawBucket
                        + " numeric=" + direct.snapshot.numeric
                        + " provider=direct rc=0 raw=" + sanitize(direct.raw));
                return direct.snapshot.bucket;
            }
            ShellResult r = runShell("am get-standby-bucket --user " + userId + " " + shellQuote(packageName),
                    "am get-standby-bucket " + shellQuote(packageName));
            StandbySnapshot snapshot = parseStandbyBucketSnapshot(r.out);
            logLine("APP_WAKE_BLOCK_SNAPSHOT_BUCKET bucket=" + snapshot.bucket
                    + " rawBucket=" + snapshot.rawBucket
                    + " numeric=" + snapshot.numeric
                    + " provider=shell directError=" + sanitize(direct.error)
                    + " rc=" + r.rc
                    + " raw=" + sanitize(r.out));
            return snapshot.bucket;
        }


        private boolean snapshotDeviceIdleWhitelist() {
            DirectBooleanResult direct = snapshotDeviceIdleWhitelistDirect();
            if (direct.ok) {
                deviceIdleWhitelistSnapshotKnown = true;
                logLine("APP_WAKE_BLOCK_SNAPSHOT_DEVICEIDLE package=" + packageName
                        + " whitelisted=" + direct.value
                        + " known=true provider=direct rc=0 raw=" + sanitize(direct.raw));
                return direct.value;
            }
            ShellResult r = runShell("dumpsys deviceidle whitelist", "cmd deviceidle whitelist");
            boolean listed = deviceIdleWhitelistContains(r.out, packageName);
            deviceIdleWhitelistSnapshotKnown = r.rc == 0 || (r.out != null && !r.out.trim().isEmpty());
            logLine("APP_WAKE_BLOCK_SNAPSHOT_DEVICEIDLE package=" + packageName
                    + " whitelisted=" + listed
                    + " known=" + deviceIdleWhitelistSnapshotKnown
                    + " provider=shell directError=" + sanitize(direct.error)
                    + " rc=" + r.rc
                    + " raw=" + sanitize(r.out));
            return listed;
        }

        private void applyAppOp(String op, String targetMode) {
            String original = OP_RUN_IN_BACKGROUND.equals(op) ? originalRunInBackground : originalRunAnyInBackground;
            if ("unknown".equals(original)) {
                logLine("APP_WAKE_BLOCK_APPLY stage=appops op=" + op + " skipped=true reason=snapshot-unknown target=" + targetMode);
                return;
            }
            DirectResult direct = setAppOpDirect(op, targetMode);
            ShellResult r;
            String provider;
            if (direct.ok) {
                r = new ShellResult(0, direct.raw);
                provider = "direct";
            } else {
                r = runShell("cmd appops set --user " + userId + " " + shellQuote(packageName) + " " + op + " " + targetMode,
                        "cmd appops set " + shellQuote(packageName) + " " + op + " " + targetMode);
                provider = "shell directError=" + sanitize(direct.error);
            }
            boolean ok = r.rc == 0;
            if (OP_RUN_IN_BACKGROUND.equals(op)) runInBackgroundTouched = ok;
            if (OP_RUN_ANY_IN_BACKGROUND.equals(op)) runAnyInBackgroundTouched = ok;
            if (ok) persistState("apply-appops-" + op);
            logLine("APP_WAKE_BLOCK_APPLY stage=appops op=" + op + " target=" + targetMode
                    + " original=" + original + " ok=" + ok + " provider=" + provider + " rc=" + r.rc + " raw=" + sanitize(r.out));
        }

        private void applyStandbyBucket(String bucket) {
            if ("unknown".equals(originalStandbyBucket)) {
                logLine("APP_WAKE_BLOCK_APPLY stage=standby skipped=true reason=snapshot-unknown target=" + bucket);
                return;
            }
            if ((originalDeviceIdleWhitelist || "exempted".equals(originalStandbyBucket)) && "restricted".equals(bucket)) {
                boolean removed = setDeviceIdleWhitelist(false, "apply-restricted");
                deviceIdleWhitelistTouched = removed;
                if (removed) persistState("apply-deviceidle-remove");
            }
            DirectResult direct = setStandbyBucketDirect(bucket);
            ShellResult r;
            String provider;
            if (direct.ok) {
                r = new ShellResult(0, direct.raw);
                provider = "direct";
            } else {
                r = runShell("am set-standby-bucket --user " + userId + " " + shellQuote(packageName) + " " + bucket,
                        "am set-standby-bucket " + shellQuote(packageName) + " " + bucket);
                provider = "shell directError=" + sanitize(direct.error);
            }
            standbyTouched = r.rc == 0;
            if (standbyTouched) persistState("apply-standby");
            logLine("APP_WAKE_BLOCK_APPLY stage=standby target=" + bucket + " original=" + originalStandbyBucket
                    + " originalDeviceIdleWhitelist=" + originalDeviceIdleWhitelist
                    + " deviceIdleTouched=" + deviceIdleWhitelistTouched
                    + " ok=" + standbyTouched + " provider=" + provider + " rc=" + r.rc + " raw=" + sanitize(r.out));
        }

        String restore(String reason) {
            if (restored) {
                return "APP_WAKE_BLOCK_RESTORE_DUP token=" + token + " reason=" + sanitize(reason) + "\n";
            }
            StringBuilder out = new StringBuilder();
            boolean standbyRestored = !standbyTouched;
            boolean deviceIdleRestored = !deviceIdleWhitelistTouched && !"exempted".equals(originalStandbyBucket);
            boolean runAnyRestored = !runAnyInBackgroundTouched;
            boolean runBgRestored = !runInBackgroundTouched;
            boolean restoreOk = false;
            try {
                CURRENT_USER.set(userId);
                CURRENT_PACKAGE.set(packageName);
                CURRENT_UID.set(targetUid);
                restoreAttempts++;
                persistState("restore-attempt-" + restoreAttempts);
                logLine("APP_WAKE_BLOCK_RESTORE_BEGIN token=" + token + " reason=" + sanitize(reason)
                        + " user=" + userId + " package=" + packageName + " mode=" + mode
                        + " restoreAttempts=" + restoreAttempts);
                if (standbyTouched) {
                    standbyRestored = restoreStandbyBucket();
                } else {
                    logLine("APP_WAKE_BLOCK_RESTORE stage=standby skipped=true reason=not-touched original=" + originalStandbyBucket);
                }
                if (runAnyInBackgroundTouched) {
                    runAnyRestored = restoreAppOp(OP_RUN_ANY_IN_BACKGROUND, originalRunAnyInBackground);
                } else {
                    logLine("APP_WAKE_BLOCK_RESTORE stage=appops op=" + OP_RUN_ANY_IN_BACKGROUND + " skipped=true reason=not-touched original=" + originalRunAnyInBackground);
                }
                if (runInBackgroundTouched) {
                    runBgRestored = restoreAppOp(OP_RUN_IN_BACKGROUND, originalRunInBackground);
                } else {
                    logLine("APP_WAKE_BLOCK_RESTORE stage=appops op=" + OP_RUN_IN_BACKGROUND + " skipped=true reason=not-touched original=" + originalRunInBackground);
                }
                deviceIdleRestored = restoreDeviceIdleWhitelistIfNeeded();
                restoreOk = standbyRestored && deviceIdleRestored && runAnyRestored && runBgRestored;
                if (restoreOk) {
                    persistState("restore-ok-before-delete");
                    boolean stateDeleted = deletePersistedState("restore-done");
                    if (stateDeleted) {
                        restored = true;
                        logLine("APP_WAKE_BLOCK_RESTORE_DONE token=" + token + " user=" + userId + " package=" + packageName
                                + " restoreOk=true"
                                + " stateDeleted=true"
                                + " runBgRestored=" + runBgRestored
                                + " runAnyRestored=" + runAnyRestored
                                + " standbyRestored=" + standbyRestored
                                + " deviceIdleRestored=" + deviceIdleRestored);
                        out.append("APP_WAKE_BLOCK_STOP_OK token=").append(token)
                                .append(" user=").append(userId)
                                .append(" package=").append(packageName)
                                .append(" mode=").append(mode)
                                .append(" restoreOk=true")
                                .append(" stateDeleted=true").append('\n');
                    } else {
                        restored = false;
                        persistState("restore-ok-delete-failed-retain-state");
                        logLine("APP_WAKE_BLOCK_RESTORE_FAILED token=" + token + " user=" + userId + " package=" + packageName
                                + " restoreOk=true"
                                + " stateDeleted=false"
                                + " runBgRestored=" + runBgRestored
                                + " runAnyRestored=" + runAnyRestored
                                + " standbyRestored=" + standbyRestored
                                + " reason=state-delete-failed stateRetained=true");
                        out.append("APP_WAKE_BLOCK_STOP_FAILED token=").append(token)
                                .append(" user=").append(userId)
                                .append(" package=").append(packageName)
                                .append(" mode=").append(mode)
                                .append(" reason=state-delete-failed")
                                .append(" restoreOk=true")
                                .append(" stateDeleted=false")
                                .append(" runBgRestored=").append(runBgRestored)
                                .append(" runAnyRestored=").append(runAnyRestored)
                                .append(" standbyRestored=").append(standbyRestored)
                                .append(" stateRetained=true").append('\n');
                    }
                } else {
                    restored = false;
                    persistState("restore-failed-retain-state");
                    logLine("APP_WAKE_BLOCK_RESTORE_FAILED token=" + token + " user=" + userId + " package=" + packageName
                            + " restoreOk=false"
                            + " runBgRestored=" + runBgRestored
                            + " runAnyRestored=" + runAnyRestored
                            + " standbyRestored=" + standbyRestored
                            + " deviceIdleRestored=" + deviceIdleRestored
                            + " stateRetained=true");
                    out.append("APP_WAKE_BLOCK_STOP_FAILED token=").append(token)
                            .append(" user=").append(userId)
                            .append(" package=").append(packageName)
                            .append(" mode=").append(mode)
                            .append(" reason=restore-step-failed")
                            .append(" runBgRestored=").append(runBgRestored)
                            .append(" runAnyRestored=").append(runAnyRestored)
                            .append(" standbyRestored=").append(standbyRestored)
                            .append(" stateRetained=true").append('\n');
                }
            } catch (Throwable t) {
                restored = false;
                try { persistState("restore-exception-retain-state"); } catch (Throwable ignored) {}
                logLine("APP_WAKE_BLOCK_RESTORE_FAILED token=" + token + " user=" + userId + " package=" + packageName
                        + " restoreOk=false exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage())
                        + " stateRetained=true");
                out.append("APP_WAKE_BLOCK_STOP_FAILED token=").append(token)
                        .append(" user=").append(userId)
                        .append(" package=").append(packageName)
                        .append(" mode=").append(mode)
                        .append(" exception=").append(sanitize(t.getClass().getName()))
                        .append(" message=").append(sanitize(t.getMessage()))
                        .append(" stateRetained=true").append('\n');
            } finally {
                if (log != null) {
                    try { log.flush(); log.close(); } catch (Throwable ignored) {}
                }
            }
            return out.toString();
        }

        private boolean restoreAppOp(String op, String original) {
            if (original == null || original.isEmpty() || "unknown".equals(original)) {
                logLine("APP_WAKE_BLOCK_RESTORE stage=appops op=" + op + " skipped=true reason=original-unknown ok=false");
                return false;
            }
            DirectResult direct = setAppOpDirect(op, original);
            ShellResult r;
            String provider;
            if (direct.ok) {
                r = new ShellResult(0, direct.raw);
                provider = "direct";
            } else {
                r = runShell("cmd appops set --user " + userId + " " + shellQuote(packageName) + " " + op + " " + original,
                        "cmd appops set " + shellQuote(packageName) + " " + op + " " + original);
                provider = "shell directError=" + sanitize(direct.error);
            }
            boolean ok = r.rc == 0;
            logLine("APP_WAKE_BLOCK_RESTORE stage=appops op=" + op + " target=" + original
                    + " ok=" + ok + " provider=" + provider + " rc=" + r.rc + " raw=" + sanitize(r.out));
            return ok;
        }

        private boolean restoreStandbyBucket() {
            if (originalStandbyBucket == null || originalStandbyBucket.isEmpty() || "unknown".equals(originalStandbyBucket)) {
                logLine("APP_WAKE_BLOCK_RESTORE stage=standby skipped=true reason=original-unknown ok=false");
                return false;
            }
            String targetBucket = standbyBucketRestoreTarget(originalStandbyBucket);
            if ("deviceidle-whitelist".equals(targetBucket)) {
                logLine("APP_WAKE_BLOCK_RESTORE stage=standby target=exempted original=" + originalStandbyBucket
                        + " skipped=true reason=restore-via-deviceidle-whitelist ok=true");
                return true;
            }
            if (targetBucket == null || targetBucket.isEmpty() || "unknown".equals(targetBucket)) {
                logLine("APP_WAKE_BLOCK_RESTORE stage=standby original=" + originalStandbyBucket
                        + " skipped=true reason=restore-target-unknown ok=false");
                return false;
            }
            DirectResult direct = setStandbyBucketDirect(targetBucket);
            ShellResult r;
            String provider;
            if (direct.ok) {
                r = new ShellResult(0, direct.raw);
                provider = "direct";
            } else {
                r = runShell("am set-standby-bucket --user " + userId + " " + shellQuote(packageName) + " " + targetBucket,
                        "am set-standby-bucket " + shellQuote(packageName) + " " + targetBucket);
                provider = "shell directError=" + sanitize(direct.error);
            }
            boolean ok = r.rc == 0;
            logLine("APP_WAKE_BLOCK_RESTORE stage=standby target=" + targetBucket
                    + " original=" + originalStandbyBucket
                    + " ok=" + ok + " provider=" + provider + " rc=" + r.rc + " raw=" + sanitize(r.out));
            return ok;
        }

        private boolean restoreDeviceIdleWhitelistIfNeeded() {
            if ("exempted".equals(originalStandbyBucket) || originalDeviceIdleWhitelist) {
                boolean ok = setDeviceIdleWhitelist(true, "restore-original-exempted");
                logLine("APP_WAKE_BLOCK_RESTORE stage=deviceidle-whitelist target=true original=" + originalDeviceIdleWhitelist
                        + " originalBucket=" + originalStandbyBucket
                        + " ok=" + ok);
                return ok;
            }
            if (deviceIdleWhitelistTouched) {
                boolean ok = setDeviceIdleWhitelist(false, "restore-original-not-whitelisted");
                logLine("APP_WAKE_BLOCK_RESTORE stage=deviceidle-whitelist target=false original=" + originalDeviceIdleWhitelist
                        + " originalBucket=" + originalStandbyBucket
                        + " ok=" + ok);
                return ok;
            }
            logLine("APP_WAKE_BLOCK_RESTORE stage=deviceidle-whitelist skipped=true reason=not-touched original=" + originalDeviceIdleWhitelist
                    + " originalBucket=" + originalStandbyBucket);
            return true;
        }

        private String standbyBucketRestoreTarget(String original) {
            if (original == null) return "unknown";
            String b = original.trim().toLowerCase(Locale.ROOT);
            if ("exempted".equals(b)) return "deviceidle-whitelist";
            return b;
        }

        private boolean setDeviceIdleWhitelist(boolean enable, String phase) {
            DirectResult direct = setDeviceIdleWhitelistDirect(enable);
            ShellResult r;
            String provider;
            if (direct.ok) {
                r = new ShellResult(0, direct.raw);
                provider = "direct";
            } else {
                String prefix = enable ? "+" : "-";
                r = runShell("cmd deviceidle whitelist " + prefix + shellQuote(packageName),
                        "dumpsys deviceidle whitelist " + prefix + shellQuote(packageName));
                provider = "shell directError=" + sanitize(direct.error);
            }
            boolean ok = r.rc == 0;
            logLine("APP_WAKE_BLOCK_DEVICEIDLE phase=" + sanitize(phase)
                    + " target=" + enable
                    + " ok=" + ok + " provider=" + provider + " rc=" + r.rc + " raw=" + sanitize(r.out));
            return ok;
        }

        private void persistState(String phase) {
            try {
                File file = stateFileFor(this);
                Properties p = new Properties();
                p.setProperty("schema", "speedbackup.app_wake_block.persistent.v4");
                p.setProperty("version", VERSION);
                p.setProperty("createdAt", p.getProperty("createdAt", String.valueOf(PROCESS_START_MS)));
                p.setProperty("processPid", String.valueOf(android.os.Process.myPid()));
                p.setProperty("processSessionId", PROCESS_SESSION_ID);
                p.setProperty("token", String.valueOf(token));
                p.setProperty("ownerToken", String.valueOf(ownerToken));
                p.setProperty("ownerKind", ownerKind == null ? "" : ownerKind);
                p.setProperty("user", String.valueOf(userId));
                p.setProperty("package", packageName);
                p.setProperty("mode", mode);
                p.setProperty("logPath", logPath == null ? "" : logPath);
                p.setProperty("targetUid", String.valueOf(targetUid));
                p.setProperty("runBg", originalRunInBackground);
                p.setProperty("runAny", originalRunAnyInBackground);
                p.setProperty("standbyBucket", originalStandbyBucket);
                p.setProperty("deviceIdleWhitelist", String.valueOf(originalDeviceIdleWhitelist));
                p.setProperty("deviceIdleWhitelistSnapshotKnown", String.valueOf(deviceIdleWhitelistSnapshotKnown));
                p.setProperty("runBgTouched", String.valueOf(runInBackgroundTouched));
                p.setProperty("runAnyTouched", String.valueOf(runAnyInBackgroundTouched));
                p.setProperty("standbyTouched", String.valueOf(standbyTouched));
                p.setProperty("deviceIdleWhitelistTouched", String.valueOf(deviceIdleWhitelistTouched));
                p.setProperty("applied", String.valueOf(applied));
                p.setProperty("restored", String.valueOf(restored));
                p.setProperty("restoreAttempts", String.valueOf(restoreAttempts));
                p.setProperty("phase", phase == null ? "" : phase);
                p.setProperty("updatedAt", String.valueOf(System.currentTimeMillis()));
                writePropertiesAtomic(file, p);
                logLine("APP_WAKE_BLOCK_PERSIST_STATE token=" + token
                        + " ownerToken=" + ownerToken
                        + " ownerKind=" + sanitize(ownerKind)
                        + " phase=" + sanitize(phase)
                        + " path=" + sanitize(file.getAbsolutePath()));
            } catch (Throwable t) {
                logLine("APP_WAKE_BLOCK_PERSIST_STATE_FAILED token=" + token
                        + " phase=" + sanitize(phase)
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage()));
            }
        }

        private boolean deletePersistedState(String reason) {
            try {
                File file = stateFileFor(this);
                boolean existedBefore = file.exists();
                boolean deleted = !existedBefore || file.delete();
                logLine("APP_WAKE_BLOCK_PERSIST_DELETE token=" + token
                        + " ownerToken=" + ownerToken
                        + " reason=" + sanitize(reason)
                        + " existedBefore=" + existedBefore
                        + " deleted=" + deleted
                        + " path=" + sanitize(file.getAbsolutePath()));
                return deleted;
            } catch (Throwable t) {
                logLine("APP_WAKE_BLOCK_PERSIST_DELETE_FAILED token=" + token
                        + " reason=" + sanitize(reason)
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage())
                        + " deleted=false");
                return false;
            }
        }

        void logLine(String line) {
            String out = now() + " " + line;
            if (log != null) {
                log.println(out);
                log.flush();
            } else {
                System.out.println(out);
            }
        }
    }

    private static String restorePersistedFile(File file, String reason, String source, int wakeToken, int ownerToken, int userId, String packageName) {
        StringBuilder out = new StringBuilder();
        Properties p = readProperties(file);
        if (p.isEmpty()) {
            return "APP_WAKE_BLOCK_PERSISTENT_RESTORE_FAILED source=" + sanitize(source)
                    + " reason=" + sanitize(reason)
                    + " path=" + sanitize(file == null ? "" : file.getAbsolutePath())
                    + " message=empty-state\n";
        }
        WakeBlockSession s = sessionFromProperties(p);
        String mismatch = expectedMismatch(s, userId, packageName);
        if (!mismatch.isEmpty()) {
            out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_REJECTED source=").append(sanitize(source))
                    .append(" reason=").append(sanitize(reason))
                    .append(" token=").append(s.token)
                    .append(" ownerToken=").append(s.ownerToken)
                    .append(" stateUser=").append(s.userId)
                    .append(" statePackage=").append(s.packageName)
                    .append(" expectedUser=").append(userId)
                    .append(" expectedPackage=").append(sanitize(packageName))
                    .append(" mismatch=").append(sanitize(mismatch))
                    .append(" stateRetained=true")
                    .append(" path=").append(sanitize(file.getAbsolutePath())).append('\n');
            return out.toString();
        }
        out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_BEGIN source=").append(sanitize(source))
                .append(" reason=").append(sanitize(reason))
                .append(" token=").append(s.token)
                .append(" ownerToken=").append(s.ownerToken)
                .append(" ownerKind=").append(sanitize(s.ownerKind))
                .append(" user=").append(s.userId)
                .append(" package=").append(s.packageName)
                .append(" mode=").append(s.mode)
                .append(" path=").append(sanitize(file.getAbsolutePath())).append('\n');
        try {
            String restoreOut = s.restore("persistent-" + reason);
            out.append(restoreOut);
            if (restoreOut.contains("APP_WAKE_BLOCK_STOP_OK") && restoreOut.contains("stateDeleted=true")) {
                out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_DONE source=").append(sanitize(source))
                        .append(" token=").append(s.token)
                        .append(" ownerToken=").append(s.ownerToken)
                        .append(" user=").append(s.userId)
                        .append(" package=").append(s.packageName)
                        .append(" stateDeleted=true")
                        .append(" reason=").append(sanitize(reason)).append('\n');
            } else {
                out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_FAILED source=").append(sanitize(source))
                        .append(" token=").append(s.token)
                        .append(" ownerToken=").append(s.ownerToken)
                        .append(" user=").append(s.userId)
                        .append(" package=").append(s.packageName)
                        .append(" reason=").append(sanitize(reason))
                        .append(" message=restore-step-failed stateRetained=true").append('\n');
            }
        } catch (Throwable t) {
            out.append("APP_WAKE_BLOCK_PERSISTENT_RESTORE_FAILED source=").append(sanitize(source))
                    .append(" token=").append(s.token)
                    .append(" ownerToken=").append(s.ownerToken)
                    .append(" exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage()))
                    .append(" stateRetained=true").append('\n');
        }
        return out.toString();
    }


    private static boolean restoreDoneAndStateDeleted(String raw) {
        return raw != null
                && raw.contains("APP_WAKE_BLOCK_PERSISTENT_RESTORE_DONE")
                && raw.contains("stateDeleted=true");
    }

    private static WakeBlockSession sessionFromProperties(Properties p) {
        int token = parseInt(p.getProperty("token"), -1);
        int userId = parseInt(p.getProperty("user"), 0);
        String pkg = safePackage(p.getProperty("package", ""));
        String mode = normalizeMode(p.getProperty("mode", "normal"));
        String logPath = p.getProperty("logPath", "-");
        WakeBlockSession s = new WakeBlockSession(token, userId, pkg, mode, logPath);
        s.ownerToken = parseInt(p.getProperty("ownerToken"), -1);
        s.ownerKind = p.getProperty("ownerKind", "");
        s.targetUid = parseInt(p.getProperty("targetUid"), -1);
        s.originalRunInBackground = p.getProperty("runBg", "unknown");
        s.originalRunAnyInBackground = p.getProperty("runAny", "unknown");
        s.originalStandbyBucket = p.getProperty("standbyBucket", "unknown");
        s.originalDeviceIdleWhitelist = Boolean.parseBoolean(p.getProperty("deviceIdleWhitelist", "false"));
        s.deviceIdleWhitelistSnapshotKnown = Boolean.parseBoolean(p.getProperty("deviceIdleWhitelistSnapshotKnown", "false"));
        s.runInBackgroundTouched = Boolean.parseBoolean(p.getProperty("runBgTouched", "false"));
        s.runAnyInBackgroundTouched = Boolean.parseBoolean(p.getProperty("runAnyTouched", "false"));
        s.standbyTouched = Boolean.parseBoolean(p.getProperty("standbyTouched", "false"));
        s.deviceIdleWhitelistTouched = Boolean.parseBoolean(p.getProperty("deviceIdleWhitelistTouched", "false"));
        s.applied = Boolean.parseBoolean(p.getProperty("applied", "true"));
        s.restoreAttempts = parseInt(p.getProperty("restoreAttempts"), 0);
        return s;
    }

    private static File stateDir() {
        File dir = new File(STATE_DIR);
        try { if (!dir.isDirectory()) dir.mkdirs(); } catch (Throwable ignored) {}
        return dir;
    }

    private static File stateFileFor(WakeBlockSession s) {
        String owner = s.ownerToken > 0 ? "po" + s.ownerToken + "_" : "direct_";
        return new File(stateDir(), owner + "wb" + s.token + "_u" + s.userId + "_" + safeFilePart(s.packageName) + ".properties");
    }

    private static File findStateByWakeToken(int token) {
        return findStateByWakeToken(token, -1, "");
    }

    private static File findStateByWakeToken(int token, int expectedUserId, String expectedPackageName) {
        File[] files = stateDir().listFiles();
        if (files == null) return null;
        File best = null;
        long bestTime = Long.MIN_VALUE;
        for (File f : files) {
            if (!isStateFile(f)) continue;
            Properties p = readProperties(f);
            if (parseInt(p.getProperty("token"), -1) != token) continue;
            if (!stateMatchesExpected(p, expectedUserId, expectedPackageName)) continue;
            long t = stateUpdatedAt(p, f);
            if (best == null || t > bestTime) { best = f; bestTime = t; }
        }
        return best;
    }

    private static File findStateByOwnerToken(int ownerToken, String ownerKind) {
        return findStateByOwnerToken(ownerToken, ownerKind, -1, "");
    }

    private static File findStateByOwnerToken(int ownerToken, String ownerKind, int expectedUserId, String expectedPackageName) {
        File[] files = stateDir().listFiles();
        if (files == null) return null;
        File best = null;
        long bestTime = Long.MIN_VALUE;
        String kind = ownerKind == null ? "" : ownerKind.trim();
        for (File f : files) {
            if (!isStateFile(f)) continue;
            Properties p = readProperties(f);
            if (parseInt(p.getProperty("ownerToken"), -1) != ownerToken) continue;
            if (!kind.isEmpty() && !kind.equals(p.getProperty("ownerKind", ""))) continue;
            if (!stateMatchesExpected(p, expectedUserId, expectedPackageName)) continue;
            long t = stateUpdatedAt(p, f);
            if (best == null || t > bestTime) { best = f; bestTime = t; }
        }
        return best;
    }

    private static File findStateByPackage(int userId, String packageName) {
        File[] files = stateDir().listFiles();
        if (files == null) return null;
        File best = null;
        long bestTime = Long.MIN_VALUE;
        for (File f : files) {
            if (!isStateFile(f)) continue;
            Properties p = readProperties(f);
            if (!stateMatchesExpected(p, userId, packageName)) continue;
            long t = stateUpdatedAt(p, f);
            if (best == null || t > bestTime) {
                best = f;
                bestTime = t;
            }
        }
        return best;
    }

    private static boolean stateMatchesExpected(Properties p, int expectedUserId, String expectedPackageName) {
        if (p == null || p.isEmpty()) return false;
        if (expectedUserId >= 0 && parseInt(p.getProperty("user"), -1) != expectedUserId) return false;
        String expectedPkg = safePackage(expectedPackageName);
        if (!expectedPkg.isEmpty() && !expectedPkg.equals(safePackage(p.getProperty("package", "")))) return false;
        return true;
    }

    private static String expectedMismatch(WakeBlockSession s, int expectedUserId, String expectedPackageName) {
        if (s == null) return "empty-session";
        if (expectedUserId >= 0 && s.userId != expectedUserId) return "user";
        String expectedPkg = safePackage(expectedPackageName);
        if (!expectedPkg.isEmpty() && !expectedPkg.equals(s.packageName)) return "package";
        return "";
    }

    private static boolean isStateFile(File f) {
        return f != null && f.isFile() && f.getName().endsWith(".properties");
    }

    private static long stateUpdatedAt(Properties p, File f) {
        return parseLong(p == null ? null : p.getProperty("updatedAt"), f == null ? 0L : f.lastModified());
    }

    private static int countPersistentStates() {
        File[] files = stateDir().listFiles();
        if (files == null) return 0;
        int n = 0;
        for (File f : files) {
            if (f != null && f.isFile() && f.getName().endsWith(".properties")) n++;
        }
        return n;
    }

    private static Properties readProperties(File file) {
        Properties p = new Properties();
        if (file == null || !file.isFile()) return p;
        try (FileInputStream in = new FileInputStream(file)) {
            p.load(in);
        } catch (Throwable ignored) {}
        return p;
    }

    private static void writePropertiesAtomic(File file, Properties p) throws Exception {
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory()) parent.mkdirs();
        File tmp = new File(file.getAbsolutePath() + ".tmp." + android.os.Process.myPid() + "." + System.nanoTime());
        try (FileOutputStream out = new FileOutputStream(tmp)) {
            p.store(out, "SpeedBackup wake-block persistent state");
            out.flush();
            try { out.getFD().sync(); } catch (Throwable ignored) {}
        }
        if (!tmp.renameTo(file)) {
            try { copyFile(tmp, file); } finally { try { tmp.delete(); } catch (Throwable ignored) {} }
        }
    }

    private static void copyFile(File src, File dst) throws Exception {
        byte[] buf = new byte[8192];
        try (FileInputStream in = new FileInputStream(src); FileOutputStream out = new FileOutputStream(dst)) {
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            out.flush();
            try { out.getFD().sync(); } catch (Throwable ignored) {}
        }
    }

    private static int tokenSeed() {
        long seed = (System.currentTimeMillis() % 100000L) * 1000L;
        seed += Math.abs(android.os.Process.myPid() % 1000);
        if (seed < 2000L) seed += 2000L;
        if (seed > Integer.MAX_VALUE - 10000L) seed = 2000L + Math.abs(android.os.Process.myPid() % 1000);
        return (int) seed;
    }

    private static String safeFilePart(String raw) {
        if (raw == null || raw.isEmpty()) return "unknown";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < raw.length() && out.length() < 160; i++) {
            char c = raw.charAt(i);
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-') out.append(c);
            else out.append('_');
        }
        return out.length() == 0 ? "unknown" : out.toString();
    }

    private static int parseInt(String raw, int fallback) {
        try { return raw == null ? fallback : Integer.parseInt(raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static long parseLong(String raw, long fallback) {
        try { return raw == null ? fallback : Long.parseLong(raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static boolean usesAppOps(String mode) {
        return "appops".equals(mode) || "restricted".equals(mode) || "hard".equals(mode);
    }

    private static boolean usesRestrictedBucket(String mode) {
        return "restricted".equals(mode) || "hard".equals(mode);
    }

    private static String normalizeMode(String raw) {
        String m = raw == null ? "normal" : raw.trim().toLowerCase(Locale.ROOT);
        if (m.equals("normal") || m.equals("force-stop") || m.equals("stop")) return "normal";
        if (m.equals("appops") || m.equals("ops") || m.equals("bg")) return "appops";
        if (m.equals("restricted") || m.equals("restrict") || m.equals("bucket")) return "restricted";
        if (m.equals("hard") || m.equals("disable") || m.equals("suspend")) return "hard";
        return "normal";
    }

    private static int resolveTargetUid(int userId, String packageName) {
        try {
            String status = AppInventoryUtil.packageStatusSingle(userId, packageName, true);
            JsonObjectCompat o = JsonObjectCompat.parse(status);
            return o.getInt("uid", -1);
        } catch (Throwable ignored) {}
        return -1;
    }

    private static final class JsonObjectCompat {
        final com.google.gson.JsonObject object;
        JsonObjectCompat(com.google.gson.JsonObject object) { this.object = object; }
        static JsonObjectCompat parse(String raw) {
            return new JsonObjectCompat(com.google.gson.JsonParser.parseString(raw.trim()).getAsJsonObject());
        }
        int getInt(String key, int fallback) {
            try { return object.has(key) ? object.get(key).getAsInt() : fallback; } catch (Throwable ignored) { return fallback; }
        }
    }

    private static final class AppOpSnapshot {
        final String packageMode;
        final String uidMode;
        final String effectiveMode;
        final String restoreMode;
        final String source;

        AppOpSnapshot(String packageMode, String uidMode, String effectiveMode, String restoreMode, String source) {
            this.packageMode = packageMode;
            this.uidMode = uidMode;
            this.effectiveMode = effectiveMode;
            this.restoreMode = restoreMode;
            this.source = source;
        }
    }

    private static AppOpSnapshot parseAppOpsSnapshot(String op, String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            return new AppOpSnapshot("unknown", "unknown", "unknown", "unknown", "empty");
        }
        String normalized = raw.replace('\n', '|').replace('\r', '|');
        String[] segments = normalized.split("\\|");
        String packageMode = "unknown";
        String uidMode = "unknown";
        for (String segment : segments) {
            String s = segment == null ? "" : segment.trim();
            if (s.isEmpty()) continue;
            String lower = s.toLowerCase(Locale.ROOT);
            if (lower.contains("no operations")) {
                packageMode = "default";
                continue;
            }
            if (!lower.contains(op.toLowerCase(Locale.ROOT))) continue;
            String mode = parseModeToken(lower);
            if ("unknown".equals(mode)) continue;
            if (lower.contains("uid mode")) {
                uidMode = mode;
            } else {
                packageMode = mode;
            }
        }
        // cmd appops set <package> writes package mode. If the dump only exposes a UID mode,
        // restore package mode to default after our temporary override instead of copying UID mode
        // into a package-scoped entry. This prevents package/uid scope pollution on Android 16/vendor ROMs.
        String restoreMode;
        String source;
        if (!"unknown".equals(packageMode)) {
            restoreMode = packageMode;
            source = "package";
        } else if (!"unknown".equals(uidMode)) {
            restoreMode = "default";
            source = "uid-only-package-default";
        } else {
            restoreMode = "unknown";
            source = "unknown";
        }
        String effectiveMode = !"unknown".equals(packageMode) ? packageMode : uidMode;
        return new AppOpSnapshot(packageMode, uidMode, effectiveMode, restoreMode, source);
    }

    private static String parseModeToken(String lower) {
        if (lower == null) return "unknown";
        if (lower.contains("foreground")) return "foreground";
        if (lower.contains("ignore")) return "ignore";
        if (lower.contains("deny") || lower.contains("errored")) return "deny";
        if (lower.contains("allow")) return "allow";
        if (lower.contains("default")) return "default";
        return "unknown";
    }

    private static final class StandbySnapshot {
        final String bucket;
        final String rawBucket;
        final boolean numeric;

        StandbySnapshot(String bucket, String rawBucket, boolean numeric) {
            this.bucket = bucket;
            this.rawBucket = rawBucket;
            this.numeric = numeric;
        }
    }

    private static StandbySnapshot parseStandbyBucketSnapshot(String raw) {
        if (raw == null) return new StandbySnapshot("unknown", "", false);
        String lower = raw.trim().toLowerCase(Locale.ROOT);
        if (lower.isEmpty()) return new StandbySnapshot("unknown", "", false);
        String[] known = new String[]{"exempted", "active", "working_set", "frequent", "rare", "restricted", "never"};
        for (String k : known) {
            if (lower.equals(k) || lower.contains(k)) return new StandbySnapshot(k, lower, false);
        }
        String first = firstIntegerToken(lower);
        if (!first.isEmpty()) {
            String mapped = standbyBucketNameFromNumber(first);
            return new StandbySnapshot(mapped, first, true);
        }
        return new StandbySnapshot("unknown", lower, false);
    }

    private static String firstIntegerToken(String text) {
        if (text == null) return "";
        int start = -1;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c >= '0' && c <= '9') {
                if (start < 0) start = i;
            } else if (start >= 0) {
                return text.substring(start, i);
            }
        }
        return start >= 0 ? text.substring(start) : "";
    }

    private static String standbyBucketNameFromNumber(String rawNumber) {
        try {
            int value = Integer.parseInt(rawNumber);
            if (value <= 5) return "exempted";
            if (value == 10) return "active";
            if (value == 20) return "working_set";
            if (value == 30) return "frequent";
            if (value == 40) return "rare";
            if (value == 45) return "restricted";
            if (value >= 50) return "never";
        } catch (Throwable ignored) {}
        return "unknown";
    }

    private static boolean deviceIdleWhitelistContains(String raw, String packageName) {
        String pkg = safePackage(packageName);
        if (pkg.isEmpty() || raw == null) return false;
        String normalized = raw.replace('\r', '\n');
        String[] lines = normalized.split("\n");
        for (String line : lines) {
            String l = line == null ? "" : line.trim();
            if (l.equals(pkg) || l.endsWith(" " + pkg) || l.contains("," + pkg) || l.contains("=" + pkg)) return true;
            if (l.contains(pkg)) {
                String[] parts = l.split("[^A-Za-z0-9._-]+");
                for (String part : parts) if (pkg.equals(part)) return true;
            }
        }
        return false;
    }

    private static final class DirectResult {
        final boolean ok;
        final String raw;
        final String error;
        DirectResult(boolean ok, String raw, String error) {
            this.ok = ok;
            this.raw = raw == null ? "" : raw;
            this.error = error == null ? "" : error;
        }
        static DirectResult ok(String raw) { return new DirectResult(true, raw, ""); }
        static DirectResult fail(Throwable t) { return new DirectResult(false, "", t == null ? "unknown" : t.getClass().getName() + ":" + t.getMessage()); }
        static DirectResult fail(String msg) { return new DirectResult(false, "", msg); }
    }

    private static final class DirectBooleanResult {
        final boolean ok;
        final boolean value;
        final String raw;
        final String error;
        DirectBooleanResult(boolean ok, boolean value, String raw, String error) {
            this.ok = ok;
            this.value = value;
            this.raw = raw == null ? "" : raw;
            this.error = error == null ? "" : error;
        }
        static DirectBooleanResult ok(boolean value, String raw) { return new DirectBooleanResult(true, value, raw, ""); }
        static DirectBooleanResult fail(Throwable t) { return new DirectBooleanResult(false, false, "", t == null ? "unknown" : t.getClass().getName() + ":" + t.getMessage()); }
        static DirectBooleanResult fail(String msg) { return new DirectBooleanResult(false, false, "", msg); }
    }

    private static final class DirectAppOpSnapshot {
        final boolean ok;
        final AppOpSnapshot snapshot;
        final String raw;
        final String error;
        DirectAppOpSnapshot(boolean ok, AppOpSnapshot snapshot, String raw, String error) {
            this.ok = ok;
            this.snapshot = snapshot;
            this.raw = raw == null ? "" : raw;
            this.error = error == null ? "" : error;
        }
        static DirectAppOpSnapshot ok(AppOpSnapshot snapshot, String raw) { return new DirectAppOpSnapshot(true, snapshot, raw, ""); }
        static DirectAppOpSnapshot fail(Throwable t) { return new DirectAppOpSnapshot(false, null, "", t == null ? "unknown" : t.getClass().getName() + ":" + t.getMessage()); }
        static DirectAppOpSnapshot fail(String msg) { return new DirectAppOpSnapshot(false, null, "", msg); }
    }

    private static final class DirectStandbySnapshot {
        final boolean ok;
        final StandbySnapshot snapshot;
        final String raw;
        final String error;
        DirectStandbySnapshot(boolean ok, StandbySnapshot snapshot, String raw, String error) {
            this.ok = ok;
            this.snapshot = snapshot;
            this.raw = raw == null ? "" : raw;
            this.error = error == null ? "" : error;
        }
        static DirectStandbySnapshot ok(StandbySnapshot snapshot, String raw) { return new DirectStandbySnapshot(true, snapshot, raw, ""); }
        static DirectStandbySnapshot fail(Throwable t) { return new DirectStandbySnapshot(false, null, "", t == null ? "unknown" : t.getClass().getName() + ":" + t.getMessage()); }
        static DirectStandbySnapshot fail(String msg) { return new DirectStandbySnapshot(false, null, "", msg); }
    }

    private static DirectAppOpSnapshot snapshotAppOpDirect(String op) {
        try {
            AppOpsManagerHidden appOps = appOpsManager();
            int code = appOpCode(op);
            if (code == AppOpsManagerHidden.OP_NONE || targetUidInvalidForDirect(op)) return DirectAppOpSnapshot.fail("op-or-uid-unavailable");
            Integer packageModeValue = AppOpsCompat.tryGetPackageModeRaw(appOps, code, cachedUidForCurrentThread(), cachedPackageForCurrentThread());
            Integer uidModeValue = AppOpsCompat.tryGetUidModeRaw(appOps, code, cachedUidForCurrentThread(), AppWakeBlockUtil::appOpPublicName);
            int effectiveValue = AppOpsManagerHidden.MODE_DEFAULT;
            try { effectiveValue = appOps.unsafeCheckOpRawNoThrow(code, cachedUidForCurrentThread(), cachedPackageForCurrentThread()); } catch (Throwable ignored) {}
            String packageMode = packageModeValue == null ? "unknown" : modeValueToName(packageModeValue);
            String uidMode = uidModeValue == null ? "unknown" : modeValueToName(uidModeValue);
            String effectiveMode = modeValueToName(effectiveValue);
            String restoreMode = (packageModeValue != null && packageModeValue != AppOpsManagerHidden.MODE_DEFAULT) ? packageMode : "default";
            return DirectAppOpSnapshot.ok(new AppOpSnapshot(packageMode, uidMode, effectiveMode, restoreMode, "direct-package"),
                    "packageMode=" + packageMode + " uidMode=" + uidMode + " effectiveMode=" + effectiveMode);
        } catch (Throwable t) {
            return DirectAppOpSnapshot.fail(t);
        }
    }

    private static DirectResult setAppOpDirect(String op, String modeName) {
        try {
            AppOpsManagerHidden appOps = appOpsManager();
            int code = appOpCode(op);
            int mode = modeNameToValue(modeName);
            if (code == AppOpsManagerHidden.OP_NONE || mode < 0 || targetUidInvalidForDirect(op)) return DirectResult.fail("op-mode-or-uid-unavailable");
            AppOpsCompat.setPackageModeIfNeeded(appOps, code, cachedUidForCurrentThread(), cachedPackageForCurrentThread(), mode);
            return DirectResult.ok("setMode packageMode=" + modeNameToValueName(mode));
        } catch (Throwable t) {
            return DirectResult.fail(t);
        }
    }

    private static DirectStandbySnapshot snapshotStandbyBucketDirect() {
        try {
            int bucket = getStandbyBucketDirectInt();
            return DirectStandbySnapshot.ok(new StandbySnapshot(bucketToName(bucket), String.valueOf(bucket), true), "bucket=" + bucket);
        } catch (Throwable t) {
            return DirectStandbySnapshot.fail(t);
        }
    }

    private static DirectResult setStandbyBucketDirect(String bucketName) {
        try {
            int bucket = bucketNameToValue(bucketName);
            if (bucket < 0) return DirectResult.fail("bucket-unavailable:" + bucketName);
            try {
                Object service = HiddenApiServices.interfaceService("usagestats", "android.app.usage.IUsageStatsManager$Stub");
                HiddenApiReflection.invokeFlexible(service, "setAppStandbyBucket", cachedPackageForCurrentThread(), bucket, cachedUserForCurrentThread());
                return DirectResult.ok("IUsageStatsManager.setAppStandbyBucket bucket=" + bucket);
            } catch (Throwable serviceError) {
                if (cachedUserForCurrentThread() != 0) throw serviceError;
                Object usm = HiddenApiHelper.getContext().getSystemService(Context.USAGE_STATS_SERVICE);
                HiddenApiReflection.invokeFlexible(usm, "setAppStandbyBucket", cachedPackageForCurrentThread(), bucket);
                return DirectResult.ok("UsageStatsManager.setAppStandbyBucket bucket=" + bucket + " serviceFallback=" + serviceError.getClass().getSimpleName());
            }
        } catch (Throwable t) {
            return DirectResult.fail(t);
        }
    }

    private static DirectBooleanResult snapshotDeviceIdleWhitelistDirect() {
        try {
            Object service = HiddenApiServices.deviceIdle();
            Object names = null;
            try { names = HiddenApiReflection.invokeFlexible(service, "getFullPowerWhitelist"); } catch (Throwable ignored) {}
            if (!(names instanceof String[])) {
                try { names = HiddenApiReflection.invokeFlexible(service, "getFullPowerWhitelistExceptIdle"); } catch (Throwable ignored) {}
            }
            if (names instanceof String[]) {
                for (String name : (String[]) names) {
                    if (cachedPackageForCurrentThread().equals(name)) return DirectBooleanResult.ok(true, "IDeviceIdleController.whitelist contains=true");
                }
                return DirectBooleanResult.ok(false, "IDeviceIdleController.whitelist contains=false");
            }
            return DirectBooleanResult.fail("whitelist-method-return-unsupported");
        } catch (Throwable t) {
            return DirectBooleanResult.fail(t);
        }
    }

    private static DirectResult setDeviceIdleWhitelistDirect(boolean enable) {
        try {
            Object service = HiddenApiServices.deviceIdle();
            String pkg = cachedPackageForCurrentThread();
            Throwable last = null;
            String[] methods = enable
                    ? new String[]{"addPowerSaveWhitelistApp", "addPowerSaveWhitelistAppInternal"}
                    : new String[]{"removePowerSaveWhitelistApp", "removePowerSaveWhitelistAppInternal"};
            for (String method : methods) {
                try {
                    HiddenApiReflection.invokeFlexible(service, method, pkg);
                    return DirectResult.ok("IDeviceIdleController." + method);
                } catch (Throwable t) {
                    last = t;
                }
            }
            return DirectResult.fail(last);
        } catch (Throwable t) {
            return DirectResult.fail(t);
        }
    }

    private static int getStandbyBucketDirectInt() throws Exception {
        try {
            Object service = HiddenApiServices.interfaceService("usagestats", "android.app.usage.IUsageStatsManager$Stub");
            Object v = HiddenApiReflection.invokeFlexible(service, "getAppStandbyBucket", cachedPackageForCurrentThread(), "com.android.shell", cachedUserForCurrentThread());
            if (v instanceof Integer) return (Integer) v;
        } catch (Throwable serviceError) {
            if (cachedUserForCurrentThread() != 0) throw new Exception(serviceError);
        }
        Object usm = HiddenApiHelper.getContext().getSystemService(Context.USAGE_STATS_SERVICE);
        Object v = HiddenApiReflection.invokeFlexible(usm, "getAppStandbyBucket", cachedPackageForCurrentThread());
        if (v instanceof Integer) return (Integer) v;
        throw new IllegalStateException("standby-bucket-not-integer");
    }

    private static AppOpsManagerHidden appOpsManager() throws Exception {
        Object o = HiddenApiHelper.getContext().getSystemService(Context.APP_OPS_SERVICE);
        if (o == null) throw new IllegalStateException("APP_OPS_SERVICE unavailable");
        return (AppOpsManagerHidden) o;
    }

    private static int appOpCode(String op) {
        String publicName = appOpPublicNameForKey(op);
        try { return AppOpsManagerHidden.strOpToOp(publicName); } catch (Throwable ignored) {}
        try { return (Integer) HiddenApiReflection.invokeFlexible(AppOpsManagerHidden.class, "strOpToOp", publicName); } catch (Throwable ignored) {}
        // Some Android builds do not accept shell-style names such as RUN_IN_BACKGROUND
        // in strOpToOp().  Keep numeric fallbacks for the two wake-block ops so direct
        // AppOps does not unnecessarily fall back to `cmd appops`.
        if (OP_RUN_IN_BACKGROUND.equals(op)) return 63;
        if (OP_RUN_ANY_IN_BACKGROUND.equals(op)) return 70;
        try { return AppOpsManagerHidden.strOpToOp(op); } catch (Throwable ignored) {}
        try { return (Integer) HiddenApiReflection.invokeFlexible(AppOpsManagerHidden.class, "strOpToOp", op); } catch (Throwable ignored) {}
        return AppOpsManagerHidden.OP_NONE;
    }

    private static String appOpPublicNameForKey(String op) {
        if (OP_RUN_IN_BACKGROUND.equals(op)) return "android:run_in_background";
        if (OP_RUN_ANY_IN_BACKGROUND.equals(op)) return "android:run_any_in_background";
        return op;
    }

    private static String appOpPublicName(int op) {
        try { return AppOpsManagerHidden.opToPublicName(op); } catch (Throwable ignored) {}
        try { return AppOpsManagerHidden.opToName(op); } catch (Throwable ignored) {}
        return String.valueOf(op);
    }

    private static int modeNameToValue(String mode) {
        String m = mode == null ? "" : mode.trim().toLowerCase(Locale.ROOT);
        if (m.equals("allow") || m.equals("allowed")) return AppOpsManagerHidden.MODE_ALLOWED;
        if (m.equals("ignore") || m.equals("ignored")) return AppOpsManagerHidden.MODE_IGNORED;
        if (m.equals("deny") || m.equals("denied") || m.equals("errored")) return AppOpsManagerHidden.MODE_ERRORED;
        if (m.equals("default")) return AppOpsManagerHidden.MODE_DEFAULT;
        if (m.equals("foreground")) return AppOpsManagerHidden.MODE_FOREGROUND;
        return -1;
    }

    private static String modeValueToName(int mode) {
        switch (mode) {
            case AppOpsManagerHidden.MODE_ALLOWED: return "allow";
            case AppOpsManagerHidden.MODE_IGNORED: return "ignore";
            case AppOpsManagerHidden.MODE_ERRORED: return "deny";
            case AppOpsManagerHidden.MODE_DEFAULT: return "default";
            case AppOpsManagerHidden.MODE_FOREGROUND: return "foreground";
            default: return "unknown";
        }
    }

    private static String modeNameToValueName(int mode) {
        return modeValueToName(mode);
    }

    private static int bucketNameToValue(String bucket) {
        String b = bucket == null ? "" : bucket.trim().toLowerCase(Locale.ROOT);
        if (b.equals("active")) return 10;
        if (b.equals("working_set") || b.equals("working-set") || b.equals("working")) return 20;
        if (b.equals("frequent")) return 30;
        if (b.equals("rare")) return 40;
        if (b.equals("restricted")) return 45;
        if (b.equals("never")) return 50;
        try { return Integer.parseInt(b); } catch (Throwable ignored) {}
        return -1;
    }

    private static String bucketToName(int bucket) {
        if (bucket == 5) return "exempted";
        if (bucket == 10) return "active";
        if (bucket == 20) return "working_set";
        if (bucket == 30) return "frequent";
        if (bucket == 40) return "rare";
        if (bucket == 45) return "restricted";
        if (bucket >= 50) return "never";
        return String.valueOf(bucket);
    }

    private static final ThreadLocal<Integer> CURRENT_USER = new ThreadLocal<>();
    private static final ThreadLocal<String> CURRENT_PACKAGE = new ThreadLocal<>();
    private static final ThreadLocal<Integer> CURRENT_UID = new ThreadLocal<>();

    private static int cachedUserForCurrentThread() {
        Integer v = CURRENT_USER.get();
        return v == null ? 0 : v;
    }

    private static String cachedPackageForCurrentThread() {
        String v = CURRENT_PACKAGE.get();
        return v == null ? "" : v;
    }

    private static int cachedUidForCurrentThread() {
        Integer v = CURRENT_UID.get();
        return v == null ? -1 : v;
    }

    private static boolean targetUidInvalidForDirect(String op) {
        return cachedUidForCurrentThread() < 0 || cachedPackageForCurrentThread().isEmpty();
    }

    private static final class ShellResult {
        final int rc;
        final String out;
        ShellResult(int rc, String out) { this.rc = rc; this.out = out == null ? "" : out; }
    }

    private static ShellResult runShell(String primary, String fallback) {
        ShellResult first = runOneShell(primary);
        if (first.rc == 0) return first;
        if (fallback == null || fallback.trim().isEmpty() || fallback.equals(primary)) return first;
        ShellResult second = runOneShell(fallback);
        if (second.rc == 0) return second;
        return new ShellResult(second.rc, "primary={" + first.out + "} fallback={" + second.out + "}");
    }

    private static ShellResult runOneShell(String command) {
        Process process = null;
        try {
            process = new ProcessBuilder("sh", "-c", command).redirectErrorStream(true).start();
            StringBuilder out = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                int lines = 0;
                while ((line = reader.readLine()) != null && lines < 80) {
                    if (out.length() > 0) out.append(" | ");
                    out.append(line);
                    lines++;
                }
            }
            boolean finished = process.waitFor(2500L, TimeUnit.MILLISECONDS);
            if (!finished) {
                try { process.destroy(); } catch (Throwable ignored) {}
                return new ShellResult(124, out.toString());
            }
            return new ShellResult(process.exitValue(), out.toString());
        } catch (Throwable t) {
            return new ShellResult(125, t.getClass().getName() + ":" + t.getMessage());
        } finally {
            if (process != null) {
                try { process.destroy(); } catch (Throwable ignored) {}
            }
        }
    }

    private static String shellQuote(String raw) {
        if (raw == null) return "''";
        return "'" + raw.replace("'", "'\\''") + "'";
    }

    private static PrintWriter openLog(String logPath) throws Exception {
        if (logPath == null || logPath.trim().isEmpty() || "-".equals(logPath.trim())) {
            return new PrintWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8), true);
        }
        File file = new File(logPath.trim());
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory()) parent.mkdirs();
        return new PrintWriter(new OutputStreamWriter(new FileOutputStream(file, true), StandardCharsets.UTF_8), true);
    }

    private static String safePackage(String packageName) {
        if (packageName == null) return "";
        String p = packageName.trim();
        if (p.indexOf('\n') >= 0 || p.indexOf('\r') >= 0 || p.indexOf('\0') >= 0) return "";
        return p;
    }

    private static String now() {
        try { return TS.format(new Date()); } catch (Throwable ignored) { return String.valueOf(System.currentTimeMillis()); }
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        String v = raw.replace('\n', ' ').replace('\r', ' ').replace('\0', ' ');
        return v.length() > 260 ? v.substring(0, 260) : v;
    }
}
