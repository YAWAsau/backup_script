package com.xayah.dex;

import android.os.Build;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * cgroup freezer tar-scope lifecycle guard with cgroup v2 primary, cgroup v1 native fallback, and persistent fail-safe restore.
 *
 * Official runtime surface is start/stop.  Start performs per-pid capability detection by resolving
 * /proc/<pid>/cgroup.  Primary backup/restore app scopes always select package-scope freeze,
 * even when the shell provides a first alive pid for logging/barrier facts, so all currently alive
 * package pids are frozen in one native package request.  ProcessObserver may open additional
 * pid-specific sessions for newly awakened pids during the same scope.  ProcessObserver cgroup and
 * wake-block cleanup defer to the primary app-scope token while it is active, so the final release
 * order is: primary package-scoped release, then deferred wake-block package restore.  Stop restores the original
 * frozen state and verifies cgroup.events.
 */
final class CgroupFreezeUtil {
    static final String VERSION = DexBuildInfo.VERSION;
    private static final String CGROUP_ROOT = "/sys/fs/cgroup";
    private static final String STATE_FILE = scopedPath("SPEEDBACKUP_CGROUP_FREEZER_STATE_FILE", ".speedbackup_cgroup_freezer_state");
    private static final int MAX_PIDS = 16;
    private static final long ROOT_CACHE_TTL_MS = 60000L;
    private static final long HELPER_CACHE_TTL_MS = 60000L;
    private static final String DAEMON_SOCKET = scopedPath("SPEEDBACKUP_CGROUP_FREEZER_SOCKET", "speedbackup_cgfreezerd.sock");
    private static final String NATIVE_KILL_PACKAGE_CAP = "kill-package-live-rescan-v1";
    private static final long DAEMON_CACHE_TTL_MS = 60000L;
    private static long helperCacheAt = 0L;
    private static String helperCachePath = null;
    private static long daemonCacheAt = 0L;
    private static Boolean daemonCacheOk = null;
    private static long daemonCacheGeneration = 0L;
    private static volatile boolean daemonMayHaveWorkers;
    private static Process daemonStartingProcess;
    private static final long DAEMON_RETRY_MS = 1000L;
    private static volatile boolean batchDaemonPinned = false;
    private static volatile long batchDaemonPinnedAt = 0L;
    private static final String[] HELPER_CANDIDATES = new String[] {
            "/data/backup_tools/cgfreezer",
            "/data/adb/modules/SpeedBackup/tools/cgfreezer",
            "/data/local/tmp/cgfreezer"
    };
    private static long rootCacheAt = 0L;
    private static CgroupRootInfo rootCache;
    private static final AtomicInteger NEXT_TOKEN = new AtomicInteger(DaemonBootstrap.tokenSeed(1000));
    private static final Map<Integer, FreezeSession> SESSIONS = new HashMap<>();


    private static String scopedTmpDir() {
        String run = System.getenv("SPEEDBACKUP_RUN_TMPDIR");
        if (run != null && run.length() > 0) return run;
        String tmp = System.getenv("TMPDIR");
        if (tmp != null && tmp.contains(".speedbackup_run_") && tmp.length() > 0) return tmp;
        return GuardLifecycle.fallbackRunDirectory();
    }

    private static String scopedPath(String envName, String name) {
        String env = System.getenv(envName);
        if (env != null && env.length() > 0) return env;
        File dir = new File(scopedTmpDir());
        try { dir.mkdirs(); } catch (Throwable ignored) {}
        return new File(dir, name).getAbsolutePath();
    }

    private CgroupFreezeUtil() {}

    /** Timeline-only whole-UID extension; general app freezer policy is unchanged. */
    static synchronized int startTimelineScope(int userId, int uid) throws Exception {
        final String pkg = "com.google.android.gms";
        if (findNativeHelper() == null) throw new java.io.IOException("timeline_native_freezer_required");
        if (uid / 100000 != userId || uid % 100000 < 10000 || uid % 100000 >= 99000)
            throw new java.io.IOException("timeline_uid_invalid");
        String parentPath = CGROUP_ROOT + "/apps/uid_" + uid + "/cgroup.freeze";
        File parent = new File(parentPath);
        if (!"0".equals(readFileTrim(parent, 64)))
            throw new java.io.IOException("timeline_uid_already_frozen_or_unavailable");
        for (FreezeSession prior : SESSIONS.values()) {
            if (prior.userId == userId && pkg.equals(prior.packageName))
                throw new java.io.IOException("timeline_other_freeze_session_active");
        }
        for (FreezeSession prior : readAllPersistentSessions()) {
            if (prior.userId == userId && pkg.equals(prior.packageName))
                throw new java.io.IOException("timeline_persisted_freeze_requires_cleanup");
        }
        String result = startLocked(userId, pkg, -1, 1000, "timeline");
        int token = OperationResult.token(result, "cgroup-start");
        try {
            String[] receipt = OperationResult.read(result, "cgroup-start");
            if (receipt == null || !"ok".equals(receipt[3]) || !receipt[6].equals(receipt[7])
                    || !result.contains("stateWritten=true"))
                throw new java.io.IOException("timeline_complete_freeze_required");
            FreezeSession session = SESSIONS.get(token);
            if (session == null || session.entries.isEmpty())
                throw new java.io.IOException("timeline_freeze_session_missing");
            for (FreezeEntry e : session.entries) {
                if (e.uid != uid || !e.path.startsWith(parent.getParent() + "/"))
                    throw new java.io.IOException("timeline_process_outside_uid_scope");
            }
            FreezeEntry scope = new FreezeEntry();
            scope.token = token; scope.userId = userId; scope.packageName = pkg;
            scope.pid = -1; scope.uid = uid; scope.processName = pkg;
            scope.path = parentPath; scope.originalFreeze = "0"; scope.originalFrozen = "0";
            scope.startedAt = session.startedAt; scope.owner = "timeline";
            session.entries.add(0, scope);
            FreezeSession delta = new FreezeSession(); delta.entries.add(scope);
            if (!writePersistentSession(delta, new StringBuilder()))
                throw new java.io.IOException("timeline_scope_state_write_failed");
            // Persist release instructions before changing the UID parent.
            try (FileOutputStream state = new FileOutputStream(STATE_FILE, true)) { state.getFD().sync(); }
            writeFileText(parent, "1\n");
            if (!waitFrozenValue(parentPath, "1", 1000, new StringBuilder(), "TIMELINE_UID"))
                throw new java.io.IOException("timeline_uid_freeze_timeout");
            return token;
        } catch (Exception failure) {
            if (token >= 0) stopLocked(token, userId, pkg);
            throw failure;
        }
    }

    static synchronized void checkTimelineScope(int token, int userId, int uid) throws Exception {
        FreezeSession session = SESSIONS.get(token);
        if (session == null || session.userId != userId || !"timeline".equals(session.owner))
            throw new java.io.IOException("timeline_guard_expired");
        String root = CGROUP_ROOT + "/apps/uid_" + uid;
        if (!"1".equals(readFileTrim(new File(root, "cgroup.freeze"), 64))
                || !"1".equals(parseEventsValue(readFileTrim(new File(root, "cgroup.events"), 1024), "frozen")))
            throw new java.io.IOException("timeline_uid_not_frozen");
    }


    static String start(int userId, String packageName, int explicitPid, int timeoutMs, String owner) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "start",
                () -> startLocked(userId, packageName, explicitPid, timeoutMs, owner));
    }

    private static String startLocked(int userId, String packageName, int explicitPid, int timeoutMs, String owner) {
        long startMs = System.currentTimeMillis();
        String pkg = safePackage(packageName);
        int safeTimeoutMs = clamp(timeoutMs, 100, 5000, 1500);
        String safeOwner = safeWord(owner == null || owner.trim().isEmpty() ? "manual" : owner.trim());
        StringBuilder out = new StringBuilder(4096);
        out.append("CGROUP_FREEZE_START_BEGIN")
                .append(" user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" pid=").append(explicitPid)
                .append(" timeoutMs=").append(safeTimeoutMs)
                .append(" owner=").append(sanitize(safeOwner))
                .append(" sdk=").append(Build.VERSION.SDK_INT)
                .append('\n');

        if (pkg.isEmpty()) {
            out.append("CGROUP_FREEZE_START_UNAVAILABLE reason=bad_args available=false\n");
            out.append(doneLine("START", false, -1, 0, 0, 0, "bad_args", startMs));
            return out.toString();
        }

        if (AudioPlaybackGuard.blocks(userId, pkg)) {
            out.append("CGROUP_FREEZE_START_UNAVAILABLE reason=audio_playback_guard available=false\n");
            out.append(doneLine("START", false, -1, 0, 0, 0, "audio_playback_guard", startMs));
            return out.toString();
        }
        CgroupRootInfo rootInfo = inspectCgroupRoot();
        out.append("CGROUP_FREEZE_CHECK exists=").append(rootInfo.rootExists)
                .append(" controllersFile=").append(rootInfo.controllersFileExists)
                .append(" controllersReadable=").append(rootInfo.controllersReadable)
                .append(" hasFreezerController=").append(rootInfo.hasFreezer)
                .append(" controllers=").append(sanitize(rootInfo.controllers))
                .append('\n');
        String nativeBackendProbe = tryNativeBackendProbe(out, safeTimeoutMs);
        boolean nativeV1Available = nativeBackendProbe != null && nativeBackendProbe.contains("v1Freezer=true");
        if (!rootInfo.rootExists && !nativeV1Available) {
            out.append("CGROUP_FREEZE_START_UNAVAILABLE reason=no_cgroup_root available=false\n");
            out.append(doneLine("START", false, -1, 0, 0, 0, "no_cgroup_root", startMs));
            return out.toString();
        }

        int packageUid = resolvePackageUid(userId, pkg, out, "CGROUP_FREEZE_START_UID");
        int selectedPid = selectedPidForStartOwner(explicitPid, safeOwner);
        if (selectedPid != explicitPid) {
            out.append("CGROUP_FREEZE_START_SCOPE_POLICY package=").append(sanitize(pkg))
                    .append(" owner=").append(sanitize(safeOwner))
                    .append(" explicitPid=").append(explicitPid)
                    .append(" selectedPid=").append(selectedPid)
                    .append(" reason=primary_app_scope_package_freeze_all_alive_pids")
                    .append('\n');
        }
        List<PidInfo> pids;
        if (selectedPid > 0) {
            PidInfo direct = explicitPidInfo(pkg, userId, selectedPid, out);
            pids = new ArrayList<>();
            if (direct != null) pids.add(direct);
            if (pids.isEmpty()) {
                List<PidInfo> scanned = findPackagePids(pkg, userId, out);
                for (PidInfo p : scanned) if (p != null && p.pid == selectedPid) pids.add(p);
            }
        } else {
            pids = findPackagePids(pkg, userId, out);
        }
        out.append("CGROUP_FREEZE_START_PIDS package=").append(sanitize(pkg))
                .append(" count=").append(pids.size())
                .append(" packageUid=").append(packageUid)
                .append(" selectedPid=").append(selectedPid)
                .append(" explicitPid=").append(explicitPid)
                .append(" pids=").append(sanitize(renderPids(pids)))
                .append('\n');
        if (pids.isEmpty()) {
            out.append("CGROUP_FREEZE_START_UNAVAILABLE reason=no_alive_pid available=false\n");
            out.append(doneLine("START", false, -1, 0, 0, 0, "no_alive_pid", startMs));
            return out.toString();
        }

        FreezeSession session = new FreezeSession();
        session.token = NEXT_TOKEN.incrementAndGet();
        session.userId = userId;
        session.packageName = pkg;
        session.owner = safeOwner;
        session.startedAt = System.currentTimeMillis();
        int checked = 0;
        int skipped = 0;
        int frozen = 0;
        int alreadyFrozen = 0;
        String reason = "no_usable_pid";

        NativePackageFreezeResult packageFreeze = selectedPid > 0 ? null
                : tryNativeFreezePackage(session, pids, packageUid, safeTimeoutMs, out);
        if (packageFreeze != null && packageFreeze.noRetry) {
            out.append(doneLine("START", false, -1, 0, 0, pids.size(), "native_freeze_uncertain", startMs));
            return out.toString();
        }
        if (packageFreeze != null && packageFreeze.accepted) {
            checked = packageFreeze.checked;
            frozen = packageFreeze.frozen;
            skipped = packageFreeze.failed;
            alreadyFrozen = packageFreeze.alreadyFrozen;
            reason = packageFreeze.failed > 0 ? "ok_native_package_partial" : "ok_native_package";
        } else {
            for (PidInfo p : pids) {
                if (checked >= MAX_PIDS) {
                    out.append("CGROUP_FREEZE_START_PID_SKIP reason=max_pids limit=").append(MAX_PIDS)
                            .append(" remaining=").append(pids.size() - checked).append('\n');
                    break;
                }
                checked++;
                StartPidResult r = freezePid(session, p, packageUid, safeTimeoutMs, out);
                if (r.ok) {
                    frozen++;
                    if (r.originallyFrozen) alreadyFrozen++;
                    reason = "ok";
                } else {
                    skipped++;
                    if ("no_usable_pid".equals(reason) && r.reason != null && !r.reason.isEmpty()) reason = r.reason;
                }
            }
        }

        if (frozen <= 0) {
            out.append("CGROUP_FREEZE_START_UNAVAILABLE reason=").append(sanitize(reason)).append(" available=false checked=").append(checked).append(" skipped=").append(skipped).append('\n');
            out.append(doneLine("START", false, -1, checked, 0, skipped, reason, startMs));
            return out.toString();
        }

        SESSIONS.put(session.token, session);
        boolean stateWritten = writePersistentSession(session, out);
        if (!stateWritten) {
            StopStats rollback = restoreSession(session, safeTimeoutMs, out, "CGROUP_FREEZE_START_ROLLBACK");
            if (rollback.failed == 0 && removePersistentToken(session.token)) SESSIONS.remove(session.token);
            out.append(doneLine("START", false, SESSIONS.containsKey(session.token) ? session.token : -1, checked, frozen, skipped, "state_write_failed", startMs));
            return out.toString();
        }
        session.activePrimary = isPrimaryAppScopeOwner(session.owner);
        out.append("CGROUP_FREEZE_START_OK token=").append(session.token)
                .append(" user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" owner=").append(sanitize(safeOwner))
                .append(" mode=auto")
                .append(" checked=").append(checked)
                .append(" frozenCount=").append(frozen)
                .append(" alreadyFrozen=").append(alreadyFrozen)
                .append(" skipped=").append(skipped)
                .append(" stateWritten=").append(stateWritten)
                .append('\n');
        out.append(summaryLine("start", session, checked, frozen, alreadyFrozen, skipped, stateWritten, 0, 0, 0, true, startMs));
        out.append(doneLine("START", true, session.token, checked, frozen, skipped, "ok", startMs));
        return out.toString();
    }

    static void stopOwnedSessions() {
        synchronized (CgroupFreezeUtil.class) {
            for (Integer token : new java.util.ArrayList<>(SESSIONS.keySet())) {
                try { stop(token, -1, ""); } catch (Throwable ignored) { }
            }
        }
    }

    static String stop(int token, int expectedUserId, String expectedPackageName) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "stop",
                () -> stopLocked(token, expectedUserId, expectedPackageName));
    }

    private static String stopLocked(int token, int expectedUserId, String expectedPackageName) {
        long startMs = System.currentTimeMillis();
        String expectedPkg = safePackage(expectedPackageName);
        StringBuilder out = new StringBuilder(4096);
        out.append("CGROUP_FREEZE_STOP_BEGIN")
                .append(" token=").append(token)
                .append(" expectedUser=").append(expectedUserId)
                .append(" expectedPackage=").append(sanitize(expectedPkg))
                .append('\n');
        FreezeSession session = SESSIONS.get(token);
        if (session == null) {
            session = readPersistentSession(token);
        }
        if (session == null) {
            boolean deleted = removePersistentToken(token);
            out.append("CGROUP_FREEZE_STOP_MISSING token=").append(token).append(" stateDeleted=").append(deleted).append("\n");
            out.append("CGROUP_FREEZE_STOP_DONE ok=").append(deleted).append(" token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=").append(deleted).append(" reason=missing elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-stop", deleted).token(token).restoration(true, deleted).appendTo(out.toString());
        }
        if (expectedUserId >= 0 && session.userId != expectedUserId) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_REJECTED token=").append(token)
                    .append(" reason=user_mismatch actualUser=").append(session.userId).append('\n');
            out.append("CGROUP_FREEZE_STOP_DONE ok=false token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=false reason=user_mismatch elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-stop", false).token(token).restoration(false, false).appendTo(out.toString());
        }
        if (!expectedPkg.isEmpty() && !expectedPkg.equals(session.packageName)) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_REJECTED token=").append(token)
                    .append(" reason=package_mismatch actualPackage=").append(sanitize(session.packageName)).append('\n');
            out.append("CGROUP_FREEZE_STOP_DONE ok=false token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=false reason=package_mismatch elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-stop", false).token(token).restoration(false, false).appendTo(out.toString());
        }
        session.activePrimary = false;
        boolean restoreDeferredToPrimaryScope = (isProcessObserverOwner(session.owner) || isPrimaryAppScopeOwner(session.owner))
                && hasActivePrimaryAppScopeSession(session.userId, session.packageName, session.token);
        StopStats stats;
        if (restoreDeferredToPrimaryScope) {
            stats = new StopStats();
            if (!transferToPrimaryScope(session, out)) stats.failed++;
            out.append("CGROUP_FREEZE_STOP_RESTORE_DEFER_TO_PRIMARY_SCOPE token=").append(token)
                    .append(" user=").append(session.userId)
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" owner=").append(sanitize(session.owner))
                    .append(" entries=").append(session.entries.size())
                    .append(" reason=primary_app_scope_still_active")
                    .append('\n');
        } else {
            stats = restoreSession(session, 1500, out, "CGROUP_FREEZE_STOP");
        }
        if (!restoreDeferredToPrimaryScope && stats.failed == 0
                && !tryRestoreDeferredWakeBlockAfterPrimaryRelease(session, out, "CGROUP_FREEZE_STOP")) stats.failed++;
        boolean stateDeleted = stats.failed == 0 && removePersistentToken(token);
        boolean ok = stats.failed == 0 && stateDeleted;
        if (!ok) SESSIONS.put(token, session); else SESSIONS.remove(token);
        out.append(ok ? "CGROUP_FREEZE_STOP_OK" : "CGROUP_FREEZE_STOP_FAILED")
                .append(" token=").append(token)
                .append(" user=").append(session.userId)
                .append(" package=").append(sanitize(session.packageName))
                .append(" restored=").append(stats.restored)
                .append(" missingPath=").append(stats.missingPath)
                .append(" failed=").append(stats.failed)
                .append(" stateDeleted=").append(stateDeleted)
                .append('\n');
        out.append(summaryLine("stop", session, session.entries.size(), 0, 0, 0, stateDeleted, stats.restored, stats.missingPath, stats.failed, ok, startMs));
        out.append("CGROUP_FREEZE_STOP_DONE ok=").append(ok)
                .append(" token=").append(token)
                .append(" restored=").append(stats.restored)
                .append(" missingPath=").append(stats.missingPath)
                .append(" failed=").append(stats.failed)
                .append(" stateDeleted=").append(stateDeleted)
                .append(" reason=").append(ok ? "ok" : "restore_or_delete_failed")
                .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                .append('\n');
        return new OperationResult("cgroup-stop", ok).token(token).counts(session.entries.size(), stats.restored, 0, stats.failed, stats.missingPath).restoration(stats.failed == 0, stateDeleted).appendTo(out.toString());
    }


    static String refreshPrimaryAppScopePackageFreeze(int userId, String packageName, String reason, int timeoutMs) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "refreshPrimaryAppScopePackageFreeze",
                () -> refreshPrimaryAppScopePackageFreezeLocked(userId, packageName, reason, timeoutMs));
    }

    private static String refreshPrimaryAppScopePackageFreezeLocked(int userId, String packageName, String reason, int timeoutMs) {
        if (AudioPlaybackGuard.blocks(userId, packageName)) return new OperationResult("cgroup-refresh", false).appendTo("CGROUP_FREEZE_PRIMARY_REFRESH_DONE ok=false reason=audio_playback_guard\n");
        long startMs = System.currentTimeMillis();
        String pkg = safePackage(packageName);
        String safeReason = safeWord(reason == null || reason.trim().isEmpty() ? "manual-refresh" : reason.trim());
        int safeTimeoutMs = clamp(timeoutMs, 100, 5000, 1000);
        StringBuilder out = new StringBuilder(4096);
        out.append("CGROUP_FREEZE_PRIMARY_REFRESH_BEGIN")
                .append(" user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" reason=").append(sanitize(safeReason))
                .append(" timeoutMs=").append(safeTimeoutMs)
                .append('\n');
        if (pkg.isEmpty()) {
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_DONE ok=false reason=bad_args elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-refresh", false).appendTo(out.toString());
        }
        List<FreezeSession> sessions = activePrimaryAppScopeSessions(userId, pkg, -1);
        if (sessions.isEmpty()) {
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_DONE ok=true reason=no_primary_session refreshed=0 added=0 elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-refresh", true).appendTo(out.toString());
        }
        int packageUid = resolvePackageUid(userId, pkg, out, "CGROUP_FREEZE_PRIMARY_REFRESH_UID");
        List<PidInfo> pids = findPackagePids(pkg, userId, out);
        if (pids.isEmpty()) {
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_DONE ok=true reason=no_alive_pid refreshed=0 added=0 sessions=")
                    .append(sessions.size())
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs).append('\n');
            return new OperationResult("cgroup-refresh", true).appendTo(out.toString());
        }
        int refreshed = 0;
        int added = 0;
        int failed = 0;
        for (FreezeSession session : sessions) {
            if (session == null) continue;
            Set<Integer> existing = sessionEntryPidSet(session);
            FreezeSession probe = new FreezeSession();
            probe.token = session.token;
            probe.userId = session.userId;
            probe.packageName = session.packageName;
            probe.owner = session.owner;
            probe.startedAt = session.startedAt;
            List<FreezeEntry> frozenEntries = nativeFreezePackageNoThaw(probe, pids, packageUid, safeTimeoutMs, out,
                    "primary-refresh-" + sanitize(safeReason));
            if (frozenEntries == null) { failed++; continue; }
            if (frozenEntries.isEmpty()) {
                for (PidInfo pidInfo : pids) {
                    if (pidInfo == null || pidInfo.pid <= 0) continue;
                    FreezeSession one = new FreezeSession();
                    one.token = session.token;
                    one.userId = session.userId;
                    one.packageName = session.packageName;
                    one.owner = session.owner;
                    one.startedAt = session.startedAt;
                    StartPidResult r = freezePid(one, pidInfo, packageUid, safeTimeoutMs, out);
                    if (!r.ok || one.entries.isEmpty()) { failed++; continue; }
                    frozenEntries.addAll(one.entries);
                }
            }
            FreezeSession delta = new FreezeSession();
            delta.token = session.token;
            delta.userId = session.userId;
            delta.packageName = session.packageName;
            delta.owner = session.owner;
            delta.startedAt = session.startedAt;
            for (FreezeEntry e : frozenEntries) {
                if (e == null || e.pid <= 0) continue;
                refreshed++;
                e.token = session.token;
                e.userId = session.userId;
                e.packageName = session.packageName;
                e.owner = session.owner;
                e.startedAt = session.startedAt;
                // Preserve the identity captured by native before freezing.
                if (!existing.contains(e.pid)) {
                    session.entries.add(e);
                    delta.entries.add(e);
                    existing.add(e.pid);
                    added++;
                }
            }
            if (!delta.entries.isEmpty()) {
                boolean durable = writePersistentSession(delta, out);
                SESSIONS.put(session.token, session);
                if (!durable) {
                    failed++;
                    StopStats rollback = restoreSession(delta, safeTimeoutMs, out, "CGROUP_FREEZE_REFRESH_ROLLBACK");
                    if (rollback.failed == 0) session.entries.removeAll(delta.entries);
                }
            }
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_SESSION token=").append(session.token)
                    .append(" user=").append(session.userId)
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" owner=").append(sanitize(session.owner))
                    .append(" alive=").append(pids.size())
                    .append(" entries=").append(session.entries.size())
                    .append(" delta=").append(delta.entries.size())
                    .append('\n');
        }
        boolean ok = refreshed > 0 && failed == 0;
        out.append("CGROUP_FREEZE_PRIMARY_REFRESH_DONE ok=").append(ok)
                .append(" reason=").append(ok ? "ok" : "partial_or_no_refresh")
                .append(" sessions=").append(sessions.size())
                .append(" alive=").append(pids.size())
                .append(" refreshed=").append(refreshed)
                .append(" added=").append(added)
                .append(" failed=").append(failed)
                .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                .append('\n');
        return new OperationResult("cgroup-refresh", ok).counts(-1, refreshed, 0, failed, -1).appendTo(out.toString());
    }

    private static List<FreezeSession> activePrimaryAppScopeSessions(int userId, String packageName, int skipToken) {
        List<FreezeSession> result = new ArrayList<>();
        if (packageName == null || packageName.length() == 0) return result;
        // Journals are recovery evidence, not proof that their owner is active
        // in this daemon. Never defer a release to an abandoned on-disk scope.
        for (FreezeSession s : SESSIONS.values()) {
            if (s == null || s.token == skipToken) continue;
            if (s.activePrimary && s.userId == userId && packageName.equals(s.packageName) && isPrimaryAppScopeOwner(s.owner)) {
                result.add(s);
            }
        }
        return result;
    }

    private static Set<Integer> sessionEntryPidSet(FreezeSession session) {
        Set<Integer> set = new LinkedHashSet<>();
        if (session == null) return set;
        for (FreezeEntry e : session.entries) {
            if (e != null && e.pid > 0 && e.procStartTime > 0 && e.procStartTime == procStartTime(e.pid)) set.add(e.pid);
        }
        return set;
    }

    private static List<FreezeEntry> nativeFreezePackageNoThaw(FreezeSession session, List<PidInfo> pids,
                                                                int packageUid, int timeoutMs,
                                                                StringBuilder out, String tag) {
        List<FreezeEntry> entries = new ArrayList<>();
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty() || session == null || pids == null || pids.isEmpty()) return entries;
        long startMs = System.currentTimeMillis();
        int commandTimeoutMs = Math.min(30000, Math.max(3000, pids.size() * (timeoutMs + 500) + 1500));
        try {
            NativeRun run = runNativeCommand(helper,
                    new String[] {"freeze-package", session.packageName, String.valueOf(session.userId), String.valueOf(timeoutMs)},
                    "FREEZE_PKG_REFRESH " + session.packageName + " " + session.userId + " " + timeoutMs,
                    commandTimeoutMs);
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_NATIVE_PACKAGE tag=").append(sanitize(tag))
                    .append(" helper=").append(sanitize(helper))
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" user=").append(session.userId)
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" commandTimeoutMs=").append(commandTimeoutMs)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            if (containsToken(run.output, "noRetry=true")) return null;
            String doneLine = "";
            String raw = run.output == null ? "" : run.output;
            for (String line : raw.split("\\n")) {
                if (line == null) continue;
                String trimmed = line.trim();
                if (trimmed.startsWith("CGFREEZER_FREEZE_PKG_DONE ")) doneLine = trimmed;
                if (!trimmed.startsWith("CGFREEZER_FREEZE_PKG_ENTRY ") || !containsToken(trimmed, "ok=true")) continue;
                int pid = parseInt(valueOfKey(trimmed, "pid"), -1);
                int uid = parseInt(valueOfKey(trimmed, "uid"), -1);
                String path = valueOfKey(trimmed, "path");
                String process = valueOfKey(trimmed, "process");
                String beforeFreeze = normalizeFreezeValue(valueOfKey(trimmed, "beforeFreeze"));
                String beforeFrozen = normalizeFreezeValue(valueOfKey(trimmed, "beforeFrozen"));
                if (pid <= 0 || path.isEmpty() || "-".equals(path)) continue;
                if (uid < 0) {
                    for (PidInfo info : pids) if (info != null && info.pid == pid) { uid = info.uid; break; }
                }
                if (process.isEmpty() || "-".equals(process)) {
                    for (PidInfo info : pids) if (info != null && info.pid == pid) { process = info.cmdline; break; }
                }
                boolean originallyFrozen = "1".equals(beforeFreeze) || "1".equals(beforeFrozen);
                FreezeEntry e = new FreezeEntry();
                e.token = session.token;
                e.userId = session.userId;
                e.packageName = session.packageName;
                e.pid = pid;
                e.uid = uid >= 0 ? uid : packageUid;
                e.processName = process;
                e.path = path;
                e.originalFreeze = "1".equals(beforeFreeze) ? "1" : "0";
                e.originalFrozen = originallyFrozen ? "1" : "0";
                e.startedAt = session.startedAt;
                e.procStartTime = nativeStartTime(trimmed);
                e.owner = session.owner;
                entries.add(e);
            }
            boolean accepted = !run.timedOut && run.exitCode == 0 && containsToken(doneLine, "ok=true") && !entries.isEmpty();
            if (!accepted) entries.clear();
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_PRIMARY_REFRESH_NATIVE_PACKAGE_ERROR tag=").append(sanitize(tag))
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
        }
        return entries;
    }

    static String status() {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "status",
                () -> statusLocked()) + CgroupLockMetrics.summary();
    }

    private static String statusLocked() {
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_STATUS")
                .append(" active=").append(SESSIONS.size())
                .append(" stateFile=").append(STATE_FILE)
                .append('\n');
        for (Map.Entry<Integer, FreezeSession> e : SESSIONS.entrySet()) {
            FreezeSession s = e.getValue();
            out.append("CGROUP_FREEZE_SESSION token=").append(e.getKey())
                    .append(" user=").append(s.userId)
                    .append(" package=").append(sanitize(s.packageName))
                    .append(" owner=").append(sanitize(s.owner))
                    .append(" entries=").append(s.entries.size())
                    .append(" ageMs=").append(System.currentTimeMillis() - s.startedAt)
                    .append('\n');
        }
        return out.toString();
    }

    static String restorePersistedPackage(int userId, String packageName, String reason) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "restorePersistedPackage",
                () -> restorePersistedPackageLocked(userId, packageName, reason));
    }

    private static String restorePersistedPackageLocked(int userId, String packageName, String reason) {
        String pkg = safePackage(packageName);
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_PACKAGE_BEGIN user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" reason=").append(sanitize(reason)).append('\n');
        List<Integer> tokens = readPersistentTokensForPackage(userId, pkg);
        int ok = 0;
        int fail = 0;
        for (Integer token : tokens) {
            String r = stop(token, userId, pkg);
            out.append(sanitizeMultiLine(r)).append('\n');
            if (OperationResult.isOk(r, "cgroup-stop")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_PACKAGE_DONE user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" tokens=").append(tokens.size())
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append(" stateDeleted=").append(fail == 0)
                .append('\n');
        return new OperationResult("cgroup-restore-package", fail == 0).counts(tokens.size(), ok, 0, fail, 0).restoration(fail == 0, fail == 0).identity(userId, pkg).appendTo(out.toString());
    }

    static String restorePersistedAll(String reason) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "restorePersistedAll",
                () -> restorePersistedAllLocked(reason));
    }

    private static String restorePersistedAllLocked(String reason) {
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_ALL_BEGIN reason=").append(sanitize(reason)).append('\n');
        List<FreezeSession> recoverable = readAllPersistentSessions(out);
        List<Integer> tokens = new ArrayList<>();
        for (FreezeSession saved : recoverable) tokens.add(saved.token);
        boolean corrupt = out.indexOf("CGROUP_FREEZE_STATE_INVALID") >= 0;
        int ok = 0;
        int fail = 0;
        for (Integer token : tokens) {
            String r = stop(token, -1, "");
            out.append(sanitizeMultiLine(r)).append('\n');
            if (OperationResult.isOk(r, "cgroup-stop")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_ALL_DONE tokens=").append(tokens.size())
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append(" stateDeleted=").append(fail == 0)
                .append('\n');
        return new OperationResult("cgroup-restore-all", fail == 0 && !corrupt).counts(tokens.size(), ok, 0, fail, 0).appendTo(out);
    }

    static String cleanupStalePersistentStates(String reason, long ttlMs) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "cleanupStalePersistentStates",
                () -> cleanupStalePersistentStatesLocked(reason, ttlMs)) + CgroupLockMetrics.summary();
    }

    private static String cleanupStalePersistentStatesLocked(String reason, long ttlMs) {
        long now = System.currentTimeMillis();
        long ttl = ttlMs < 0 ? 0 : ttlMs;
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_CLEANUP_STALE_BEGIN reason=").append(sanitize(reason))
                .append(" ttlMs=").append(ttl).append('\n');
        List<FreezeSession> sessions = readAllPersistentSessions(out);
        boolean corrupt = out.indexOf("CGROUP_FREEZE_STATE_INVALID") >= 0;
        int stale = 0;
        int ok = 0;
        int fail = 0;
        for (FreezeSession s : sessions) {
            if (ttl > 0 && now - s.startedAt < ttl) continue;
            stale++;
            String r = stop(s.token, -1, "");
            out.append(sanitizeMultiLine(r)).append('\n');
            if (OperationResult.isOk(r, "cgroup-stop")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_CLEANUP_STALE_DONE scanned=").append(sessions.size())
                .append(" stale=").append(stale)
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append('\n');
        return new OperationResult("cgroup-cleanup", fail == 0 && !corrupt).counts(stale, ok, 0, fail, 0).appendTo(out);
    }

    static boolean isStartOk(String result) {
        return OperationResult.isOk(result, "cgroup-start");
    }

    static int parseToken(String result) {
        return OperationResult.token(result, "cgroup-start");
    }

    private static StartPidResult freezePid(FreezeSession session, PidInfo p, int packageUid, int timeoutMs, StringBuilder out) {
        StartPidResult result = tryNativeFreezePid(session, p, timeoutMs, out);
        if (result != null) return result;
        result = new StartPidResult();
        result.reason = "native_helper_required";
        return result;
    }

    private static String tryNativeBackendProbe(StringBuilder out, int timeoutMs) {
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return null;
        try {
            NativeRun run = runNativeCommand(helper, new String[] {"backend-probe"}, "BACKEND_PROBE", Math.max(800, timeoutMs + 500));
            out.append("CGROUP_FREEZE_NATIVE_BACKEND_PROBE helper=").append(sanitize(helper))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            if (!run.timedOut && run.output != null) return run.output;
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_NATIVE_BACKEND_PROBE_ERROR error=")
                    .append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
        }
        return null;
    }

    private static NativePackageFreezeResult tryNativeFreezePackage(FreezeSession session, List<PidInfo> pids,
                                                                                int packageUid, int timeoutMs,
                                                                                StringBuilder out) {
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty() || session == null || pids == null || pids.isEmpty()) return null;
        long startMs = System.currentTimeMillis();
        int commandTimeoutMs = Math.min(30000, Math.max(3000, pids.size() * (timeoutMs + 500) + 1500));
        try {
            NativeRun run = runNativeCommand(helper,
                    new String[] {"freeze-package", session.packageName, String.valueOf(session.userId), String.valueOf(timeoutMs)},
                    "FREEZE_PKG " + session.packageName + " " + session.userId + " " + timeoutMs,
                    commandTimeoutMs);
            out.append("CGROUP_FREEZE_NATIVE_PACKAGE helper=").append(sanitize(helper))
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" user=").append(session.userId)
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" commandTimeoutMs=").append(commandTimeoutMs)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');

            List<FreezeEntry> parsed = new ArrayList<>();
            int already = 0;
            String doneLine = "";
            String raw = run.output == null ? "" : run.output;
            for (String line : raw.split("\\n")) {
                if (line == null) continue;
                String trimmed = line.trim();
                if (trimmed.startsWith("CGFREEZER_FREEZE_PKG_DONE ")) doneLine = trimmed;
                if (!trimmed.startsWith("CGFREEZER_FREEZE_PKG_ENTRY ") || !containsToken(trimmed, "ok=true")) continue;
                int pid = parseInt(valueOfKey(trimmed, "pid"), -1);
                int uid = parseInt(valueOfKey(trimmed, "uid"), -1);
                String path = valueOfKey(trimmed, "path");
                String process = valueOfKey(trimmed, "process");
                String beforeFreeze = normalizeFreezeValue(valueOfKey(trimmed, "beforeFreeze"));
                String beforeFrozen = normalizeFreezeValue(valueOfKey(trimmed, "beforeFrozen"));
                if (pid <= 0 || path.isEmpty() || "-".equals(path)) continue;
                if (uid < 0) {
                    for (PidInfo info : pids) if (info != null && info.pid == pid) { uid = info.uid; break; }
                }
                if (process.isEmpty() || "-".equals(process)) {
                    for (PidInfo info : pids) if (info != null && info.pid == pid) { process = info.cmdline; break; }
                }
                boolean originallyFrozen = "1".equals(beforeFreeze) || "1".equals(beforeFrozen);
                FreezeEntry e = new FreezeEntry();
                e.token = session.token;
                e.userId = session.userId;
                e.packageName = session.packageName;
                e.pid = pid;
                e.uid = uid;
                e.processName = process;
                e.path = path;
                e.originalFreeze = "1".equals(beforeFreeze) ? "1" : "0";
                e.originalFrozen = originallyFrozen ? "1" : "0";
                e.startedAt = session.startedAt;
                e.procStartTime = nativeStartTime(trimmed);
                e.owner = session.owner;
                parsed.add(e);
                if (originallyFrozen) already++;
            }

            boolean accepted = !run.timedOut && run.exitCode == 0
                    && containsToken(doneLine, "ok=true") && !parsed.isEmpty();
            if (containsToken(raw, "noRetry=true")) {
                NativePackageFreezeResult uncertain = new NativePackageFreezeResult();
                uncertain.noRetry = true;
                return uncertain;
            }
            if (!accepted) {
                if (!parsed.isEmpty() || (run.timedOut && containsToken(raw, "CGFREEZER_FREEZE_PKG_BEGIN"))) {
                    tryNativeEmergencyThawUid(packageUid, timeoutMs, out, "native-package-uncertain");
                }
                return null;
            }
            session.entries.addAll(parsed);
            NativePackageFreezeResult result = new NativePackageFreezeResult();
            result.accepted = true;
            result.checked = parseInt(valueOfKey(doneLine, "checked"), pids.size());
            result.frozen = parseInt(valueOfKey(doneLine, "frozen"), parsed.size());
            result.failed = parseInt(valueOfKey(doneLine, "failed"), Math.max(0, result.checked - result.frozen));
            result.alreadyFrozen = parseInt(valueOfKey(doneLine, "alreadyFrozen"), already);
            out.append("CGROUP_FREEZE_NATIVE_PACKAGE_ACCEPTED package=").append(sanitize(session.packageName))
                    .append(" user=").append(session.userId)
                    .append(" checked=").append(result.checked)
                    .append(" frozen=").append(result.frozen)
                    .append(" failed=").append(result.failed)
                    .append(" alreadyFrozen=").append(result.alreadyFrozen)
                    .append(" entries=").append(parsed.size())
                    .append(" uidPidByC=true requestAtomic=true transactionalRollback=false")
                    .append('\n');
            return result;
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_NATIVE_PACKAGE_ERROR package=").append(sanitize(session.packageName))
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
            return null;
        }
    }

    private static boolean tryNativeEmergencyThawUid(int uid, int timeoutMs, StringBuilder out, String reason) {
        if (uid < 10000) return false;
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return false;
        try {
            NativeRun run = runNativeCommand(helper,
                    new String[] {"thaw-uid", String.valueOf(uid), String.valueOf(timeoutMs)},
                    "THAW_UID " + uid + " " + timeoutMs,
                    Math.max(2000, timeoutMs + 1200));
            out.append("CGROUP_FREEZE_NATIVE_EMERGENCY_THAW_UID uid=").append(uid)
                    .append(" reason=").append(sanitize(reason))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            return !run.timedOut && run.exitCode == 0 && containsToken(run.output, "CGFREEZER_THAW_UID_DONE ok=true");
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_NATIVE_EMERGENCY_THAW_UID_ERROR uid=").append(uid)
                    .append(" reason=").append(sanitize(reason))
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
            return false;
        }
    }



    private static boolean tryRestoreDeferredWakeBlockAfterPrimaryRelease(FreezeSession session, StringBuilder out, String tagPrefix) {
        if (session == null || !isPrimaryAppScopeOwner(session.owner)) return true;
        if (!AppWakeBlockUtil.hasPersistedPackage(session.userId, session.packageName)) {
            out.append(tagPrefix).append("_PRIMARY_WAKE_BLOCK_RESTORE_SKIP user=")
                    .append(session.userId)
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" owner=").append(sanitize(session.owner))
                    .append(" reason=no_deferred_wakeblock")
                    .append('\n');
            return true;
        }
        try {
            String result = AppWakeBlockUtil.restorePersistedPackage(session.userId, session.packageName,
                    "cgroup-primary-final-release-" + safeWord(session.owner));
            out.append(tagPrefix).append("_PRIMARY_WAKE_BLOCK_RESTORE user=")
                    .append(session.userId)
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" owner=").append(sanitize(session.owner))
                    .append(" result=").append(sanitize(result))
                    .append('\n');
            return OperationResult.isOk(result, "wake-restore-package");
        } catch (Throwable t) {
            out.append(tagPrefix).append("_PRIMARY_WAKE_BLOCK_RESTORE_ERROR user=")
                    .append(session.userId)
                    .append(" package=").append(sanitize(session.packageName))
                    .append(" owner=").append(sanitize(session.owner))
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
            return false;
        }
    }





    static String deferProcessObserverTokenToPrimaryScope(int token, int expectedUserId, String expectedPackageName, String reason) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "deferProcessObserverTokenToPrimaryScope",
                () -> deferProcessObserverTokenToPrimaryScopeLocked(token, expectedUserId, expectedPackageName, reason));
    }

    private static String deferProcessObserverTokenToPrimaryScopeLocked(int token, int expectedUserId, String expectedPackageName, String reason) {
        long startMs = System.currentTimeMillis();
        String expectedPkg = safePackage(expectedPackageName);
        String safeReason = safeWord(reason);
        StringBuilder out = new StringBuilder(1024);
        out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_BEGIN")
                .append(" token=").append(token)
                .append(" expectedUser=").append(expectedUserId)
                .append(" expectedPackage=").append(sanitize(expectedPkg))
                .append(" reason=").append(sanitize(safeReason))
                .append('\n');
        FreezeSession session = SESSIONS.get(token);
        if (session == null) {
            session = readPersistentSession(token);
        }
        if (session == null) {
            removePersistentToken(token);
            out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_OK token=").append(token)
                    .append(" reason=missing stateDeleted=true elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (expectedUserId >= 0 && session.userId != expectedUserId) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_REJECTED token=").append(token)
                    .append(" reason=user_mismatch actualUser=").append(session.userId)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (!expectedPkg.isEmpty() && !expectedPkg.equals(session.packageName)) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_REJECTED token=").append(token)
                    .append(" reason=package_mismatch actualPackage=").append(sanitize(session.packageName))
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (!isProcessObserverOwner(session.owner)) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_REJECTED token=").append(token)
                    .append(" reason=owner_not_process_observer owner=").append(sanitize(session.owner))
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (!hasActivePrimaryAppScopeSession(session.userId, session.packageName, session.token)) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_REJECTED token=").append(token)
                    .append(" reason=primary_app_scope_not_active owner=").append(sanitize(session.owner))
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        boolean stateDeleted = transferToPrimaryScope(session, out) && removePersistentToken(token);
        if (!stateDeleted) SESSIONS.put(token, session); else SESSIONS.remove(token);
        out.append("CGROUP_FREEZE_STOP_RESTORE_DEFER_TO_PRIMARY_SCOPE token=").append(token)
                .append(" user=").append(session.userId)
                .append(" package=").append(sanitize(session.packageName))
                .append(" owner=").append(sanitize(session.owner))
                .append(" entries=").append(session.entries.size())
                .append(" reason=primary_app_scope_still_active")
                .append(" mode=durable_ownership_transfer")
                .append('\n');
        out.append(stateDeleted ? "CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_OK" : "CGROUP_FREEZE_STOP_PROCESS_OBSERVER_DEFER_FAILED")
                .append(" token=").append(token)
                .append(" user=").append(session.userId)
                .append(" package=").append(sanitize(session.packageName))
                .append(" stateDeleted=").append(stateDeleted)
                .append(" restored=0 missingPath=0 failed=0")
                .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                .append('\n');
        return out.toString();
    }

    static synchronized boolean hasActivePrimaryAppScopeSession(int userId, String packageName, int skipToken) {
        return !activePrimaryAppScopeSessions(userId, packageName, skipToken).isEmpty();
    }

    // Persist the recipient before deleting the donor: a crash can duplicate ownership,
    // but must never lose the original state of a process frozen by the observer.
    private static boolean transferToPrimaryScope(FreezeSession donor, StringBuilder out) {
        List<FreezeSession> recipients = activePrimaryAppScopeSessions(donor.userId, donor.packageName, donor.token);
        if (recipients.isEmpty()) return false;
        FreezeSession recipient = recipients.get(0);
        FreezeSession merged = new FreezeSession();
        merged.token = recipient.token;
        merged.userId = recipient.userId;
        merged.packageName = recipient.packageName;
        merged.owner = recipient.owner;
        merged.startedAt = recipient.startedAt;
        merged.activePrimary = recipient.activePrimary;
        List<FreezeEntry> candidates = new ArrayList<>(recipient.entries);
        candidates.addAll(donor.entries);
        for (FreezeEntry entry : candidates) {
            int duplicate = -1;
            for (int i = 0; i < merged.entries.size(); i++) {
                FreezeEntry previous = merged.entries.get(i);
                if (previous.pid == entry.pid && previous.uid == entry.uid
                        && previous.procStartTime == entry.procStartTime
                        && java.util.Objects.equals(previous.path, entry.path)) { duplicate = i; break; }
            }
            if (duplicate >= 0) {
                FreezeEntry previous = merged.entries.get(duplicate);
                if (previous.startedAt < entry.startedAt
                        || (previous.startedAt == entry.startedAt && "0".equals(previous.originalFreeze))) continue;
            }
            FreezeEntry copy = decodeEntry(encodeEntry(entry));
            if (copy == null) return false;
            copy.token = merged.token;
            copy.owner = merged.owner;
            if (duplicate < 0) merged.entries.add(copy); else merged.entries.set(duplicate, copy);
        }
        if (!replacePersistentSession(merged, out)) return false;
        SESSIONS.put(merged.token, merged);
        out.append("CGROUP_FREEZE_OWNERSHIP_TRANSFER donor=").append(donor.token)
                .append(" recipient=").append(merged.token).append(" entries=").append(merged.entries.size()).append('\n');
        return true;
    }

    private static boolean replacePersistentSession(FreezeSession replacement, StringBuilder out) {
        File state = new File(STATE_FILE);
        File temporary = new File(STATE_FILE + ".transfer." + android.os.Process.myPid());
        try {
            String raw = state.exists() ? new String(java.nio.file.Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8) : "";
            try (FileOutputStream stream = new FileOutputStream(temporary, false)) {
                for (String line : raw.split("\\n")) {
                    if (line.trim().isEmpty()) continue;
                    FreezeEntry entry = decodeEntry(line);
                    if (entry != null && entry.token == replacement.token) continue;
                    stream.write((line + "\n").getBytes(StandardCharsets.UTF_8));
                }
                for (FreezeEntry entry : replacement.entries)
                    stream.write((encodeEntry(entry) + "\n").getBytes(StandardCharsets.UTF_8));
                stream.getFD().sync();
            }
            if (!temporary.renameTo(state)) throw new java.io.IOException("ownership transfer rename failed");
            TimelineUtil.syncDirectory(state.getAbsoluteFile().getParentFile());
            return true;
        } catch (Throwable failure) {
            temporary.delete();
            out.append("CGROUP_FREEZE_OWNERSHIP_TRANSFER_FAILED stateRetained=true error=")
                    .append(sanitize(failure.toString())).append('\n');
            return false;
        }
    }

    private static boolean isPrimaryAppScopeOwner(String owner) {
        String safeOwner = owner == null ? "" : owner.trim();
        return "backup_app_scope".equals(safeOwner) || "restore_app_scope".equals(safeOwner);
    }

    private static boolean isProcessObserverOwner(String owner) {
        String safeOwner = owner == null ? "" : owner.trim();
        return safeOwner.startsWith("processObserver");
    }

    private static int selectedPidForStartOwner(int explicitPid, String owner) {
        return explicitPid > 0 && isPrimaryAppScopeOwner(owner) ? -1 : explicitPid;
    }


    private static StartPidResult tryNativeFreezePid(FreezeSession session, PidInfo p, int timeoutMs, StringBuilder out) {
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return null;
        long startMs = System.currentTimeMillis();
        StartPidResult result = new StartPidResult();
        try {
            NativeRun run = runNativeCommand(helper, new String[] {"freeze-pid", String.valueOf(p.pid), String.valueOf(timeoutMs), session.packageName, String.valueOf(session.userId)}, "FREEZE " + p.pid + " " + timeoutMs + " " + session.packageName + " " + session.userId, timeoutMs + 1200);
            out.append("CGROUP_FREEZE_NATIVE_HELPER_FREEZE pid=").append(p.pid)
                    .append(" helper=").append(sanitize(helper))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            if (run.timedOut || run.exitCode != 0 || !containsToken(run.output, "ok=true")) {
                result.reason = containsToken(run.output, "noRetry=true") ? "native_freeze_uncertain" : "native_helper_failed";
                return result;
            }
            String freezePath = valueOfKey(run.output, "path");
            String beforeFreeze = normalizeFreezeValue(valueOfKey(run.output, "beforeFreeze"));
            String beforeFrozen = normalizeFreezeValue(valueOfKey(run.output, "beforeFrozen"));
            String uidRaw = valueOfKey(run.output, "uid");
            int nativeUid = parseInt(uidRaw, p.uid);
            if (freezePath.isEmpty()) {
                result.reason = "native_helper_missing_path";
                return result;
            }
            boolean originallyFrozen = "1".equals(beforeFreeze) || "1".equals(beforeFrozen);
            FreezeEntry e = new FreezeEntry();
            e.token = session.token;
            e.userId = session.userId;
            e.packageName = session.packageName;
            e.pid = p.pid;
            e.uid = nativeUid;
            e.processName = p.cmdline;
            e.path = freezePath;
            e.originalFreeze = "1".equals(beforeFreeze) ? "1" : "0";
            e.originalFrozen = originallyFrozen ? "1" : "0";
            e.startedAt = session.startedAt;
            e.procStartTime = nativeStartTime(run.output);
            e.owner = session.owner;
            session.entries.add(e);
            result.ok = true;
            result.originallyFrozen = originallyFrozen;
            result.reason = "ok_native";
            return result;
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_NATIVE_HELPER_ERROR pid=").append(p.pid)
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
            result.reason = "native_helper_exception";
            return result;
        }
    }

    private static Boolean tryNativeRestorePath(FreezeEntry e, String target, int timeoutMs, StringBuilder out, String tagPrefix) {
        // UID parent records have no Binder endpoint; restore them directly first.
        if (e.pid < 0 && "timeline".equals(e.owner)) return null;
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return null;
        long startMs = System.currentTimeMillis();
        try {
            NativeRun run = runNativeCommand(helper, new String[] {"thaw-pid", String.valueOf(e.pid), e.path, target, String.valueOf(timeoutMs)}, "THAW_PID " + e.pid + " " + e.path + " " + target + " " + timeoutMs, timeoutMs + 1200);
            boolean ok = !run.timedOut && run.exitCode == 0 && containsToken(run.output, "ok=true");
            out.append(tagPrefix).append("_NATIVE_HELPER_RESTORE pid=").append(e.pid)
                    .append(" helper=").append(sanitize(helper))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" target=").append(sanitize(target))
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" ok=").append(ok)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            return ok;
        } catch (Throwable t) {
            out.append(tagPrefix).append("_NATIVE_HELPER_RESTORE_ERROR pid=").append(e.pid)
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
            return Boolean.FALSE;
        }
    }



    static String ensureNativeDaemonForBatch(String reason) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "ensureNativeDaemonForBatch",
                () -> ensureNativeDaemonForBatchLocked(reason));
    }

    private static String ensureNativeDaemonForBatchLocked(String reason) {
        long startMs = System.currentTimeMillis();
        batchDaemonPinned = true;
        batchDaemonPinnedAt = startMs;
        String safeReason = reason == null || reason.trim().isEmpty() ? "batch" : reason.trim();
        String helper = findNativeHelper();
        boolean helloBefore = false;
        String helloBeforeOutput = "";
        try {
            NativeRun h = runNativeDaemonCommand("HELLO", 600);
            helloBeforeOutput = h.output == null ? "" : h.output;
            if (!h.timedOut && h.exitCode == 0 && helloBeforeOutput.contains("CGFREEZER_DAEMON_HELLO ok=true")) {
                helloBefore = true;
                publishDaemonCache(Boolean.TRUE, System.currentTimeMillis());
            }
        } catch (Throwable t) {
            helloBeforeOutput = t.getClass().getSimpleName() + ":" + t.getMessage();
        }
        boolean ok = helloBefore;
        boolean started = false;
        String caps = "";
        if (!ok) {
            publishDaemonCache(null, 0L);
            ok = ensureNativeDaemon();
            started = ok;
        }
        if (ok) {
            try {
                NativeRun c = runNativeDaemonCommand("CAPS", 800);
                caps = c.output == null ? "" : c.output;
            } catch (Throwable t) {
                caps = t.getClass().getSimpleName() + ":" + t.getMessage();
            }
        }
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_DAEMON_ENSURE ok=").append(ok)
                
                .append(" reason=").append(sanitize(safeReason))
                .append(" helper=").append(sanitize(helper == null ? "" : helper))
                .append(" socket=").append(sanitize(DAEMON_SOCKET))
                .append(" helloBefore=").append(helloBefore)
                .append(" started=").append(started)
                .append(" viaDaemon=").append(ok)
                .append(" persistent=true closeOnAppStop=false daemonNoExit=true perAppFastCommand=true uidPidByC=true pinned=").append(batchDaemonPinned)
                .append(" pinnedAt=").append(batchDaemonPinnedAt)
                .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                .append(" hello=").append(sanitize(helloBeforeOutput))
                .append(" caps=").append(sanitize(caps))
                .append('\n');
        return new OperationResult("cgroup-daemon-ensure", ok).appendTo(out.toString());
    }

    static synchronized List<Integer> ownedPids(int token) {
        List<Integer> pids = new ArrayList<>();
        FreezeSession session = SESSIONS.get(token);
        if (session != null) for (FreezeEntry entry : session.entries) if (entry.pid > 0) pids.add(entry.pid);
        return pids;
    }

    private static long nativeStartTime(String output) {
        try { return Long.parseLong(valueOfKey(output, "startTime")); }
        catch (NumberFormatException invalid) { return -1; }
    }

    private static long procStartTime(int pid) {
        try {
            String stat = new String(java.nio.file.Files.readAllBytes(new File("/proc/" + pid + "/stat").toPath()), java.nio.charset.StandardCharsets.UTF_8);
            return Long.parseLong(stat.substring(stat.lastIndexOf(')') + 2).split("\\s+")[19]);
        } catch (Exception e) { return -1; }
    }

    static synchronized boolean isOwnedPidFrozen(int user, String pkg, int pid) {
        for (FreezeSession session : SESSIONS.values()) {
            if (session.userId != user || !pkg.equals(session.packageName)) continue;
            for (FreezeEntry entry : session.entries) {
                if (entry.pid != pid || entry.procStartTime <= 0 || entry.procStartTime != procStartTime(pid)) continue;
                if (readStatusUid(pid) != entry.uid || !isPackageProcess(readProcCmdline(pid), pkg)) continue;
                if (isV1FreezerPath(entry.path)) return false; // Let native revalidate v1 membership.
                try { return "1".equals(normalizeFreezeValue(readFileTrim(new File(entry.path), 64)))
                        && "1".equals(parseEventsValue(readFileTrim(eventsFileForFreezePath(entry.path), 4096), "frozen")); }
                catch (Exception ignored) { return false; }
            }
        }
        return false;
    }

    static boolean resumePackagePids(int user, String pkg, String csv) {
        if (!csv.matches("[0-9]+(?:,[0-9]+)*")) return false;
        String helper = findNativeHelper();
        if (helper == null) return false;
        try {
            NativeRun result = runNativeCommand(helper, new String[]{"resume-pids", pkg, String.valueOf(user), csv},
                    "RESUME_PIDS " + pkg + " " + user + " " + csv, 1500);
            return result.exitCode == 0 && containsToken(result.output, "ok=true");
        } catch (Exception e) { return false; }
    }

    static String killPackage(int userId, String packageName, int eventPid,
                                           int timeoutMs, String owner) {
        return CgroupLockMetrics.measure(CgroupFreezeUtil.class, "killPackage",
                () -> killPackageLocked(userId, packageName, eventPid, timeoutMs, owner));
    }

    private static String killPackageLocked(int userId, String packageName, int eventPid,
                                           int timeoutMs, String owner) {
        if (AudioPlaybackGuard.blocks(userId, packageName)) return "CGROUP_NATIVE_KILL_DONE ok=false reason=audio_playback_guard remain=-1\n";
        long startMs = System.currentTimeMillis();
        String pkg = safePackage(packageName);
        int safeEventPid = eventPid > 0 ? eventPid : -1;
        int safeTimeoutMs = clamp(timeoutMs, 100, 3000, 700);
        String safeOwner = safeWord(owner == null || owner.trim().isEmpty() ? "native-kill" : owner.trim());
        StringBuilder out = new StringBuilder(8192);
        out.append("CGROUP_NATIVE_KILL_BEGIN")
                .append(" user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" eventPid=").append(safeEventPid)
                .append(" timeoutMs=").append(safeTimeoutMs)
                .append(" owner=").append(sanitize(safeOwner))
                .append(" requiredCap=").append(NATIVE_KILL_PACKAGE_CAP)
                .append('\n');
        if (pkg.isEmpty() || userId < 0) {
            out.append("CGROUP_NATIVE_KILL_DONE ok=false reason=bad_args remain=-1 elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) {
            out.append("CGROUP_NATIVE_KILL_DONE ok=false reason=no_native_helper remain=-1 elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        int commandTimeoutMs = Math.min(5000, Math.max(1200, safeTimeoutMs + 900));
        try {
            NativeRun run = runNativeCommand(helper,
                    new String[] {"kill-package", pkg, String.valueOf(userId), String.valueOf(safeEventPid), String.valueOf(safeTimeoutMs)},
                    "KILL_PKG " + pkg + " " + userId + " " + safeEventPid + " " + safeTimeoutMs,
                    commandTimeoutMs);
            String raw = run.output == null ? "" : run.output.trim();
            String doneLine = "";
            if (!raw.isEmpty()) {
                for (String line : raw.split("\n")) {
                    if (line == null) continue;
                    String trimmed = line.trim();
                    if (trimmed.startsWith("CGFREEZER_KILL_PKG_DONE ")) doneLine = trimmed;
                    if (!trimmed.isEmpty()) out.append(trimmed).append('\n');
                }
            }
            boolean doneOk = containsToken(doneLine, "ok=true");
            boolean commandOk = !run.timedOut && doneOk && (run.viaDaemon || run.exitCode == 0);
            int remain = parseInt(valueOfKey(doneLine, "remain"), -1);
            int signaled = parseInt(valueOfKey(doneLine, "signaled"), 0);
            int passes = parseInt(valueOfKey(doneLine, "passes"), 0);
            String reason = valueOfKey(doneLine, "reason");
            if (reason.isEmpty()) reason = commandOk ? "ok" : "native_command_failed";
            out.append("CGROUP_NATIVE_KILL_DONE ok=").append(commandOk)
                    .append(" package=").append(sanitize(pkg))
                    .append(" user=").append(userId)
                    .append(" eventPid=").append(safeEventPid)
                    .append(" owner=").append(sanitize(safeOwner))
                    .append(" helper=").append(sanitize(helper))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" remain=").append(remain)
                    .append(" signaled=").append(signaled)
                    .append(" passes=").append(passes)
                    .append(" reason=").append(sanitize(reason))
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append('\n');
        } catch (Throwable t) {
            out.append("CGROUP_NATIVE_KILL_DONE ok=false package=").append(sanitize(pkg))
                    .append(" user=").append(userId)
                    .append(" eventPid=").append(safeEventPid)
                    .append(" owner=").append(sanitize(safeOwner))
                    .append(" reason=exception error=")
                    .append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append(" remain=-1 elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append('\n');
        }
        return out.toString();
    }

    static boolean isNativePackageKillOk(String output) {
        if (output == null || output.isEmpty()) return false;
        for (String line : output.split("\n")) {
            String trimmed = line == null ? "" : line.trim();
            if (trimmed.startsWith("CGROUP_NATIVE_KILL_DONE ") && containsToken(trimmed, "ok=true")) return true;
        }
        return false;
    }

    static int nativePackageKillRemain(String output) {
        if (output == null || output.isEmpty()) return -1;
        int remain = -1;
        for (String line : output.split("\n")) {
            String trimmed = line == null ? "" : line.trim();
            if (trimmed.startsWith("CGROUP_NATIVE_KILL_DONE ")) {
                remain = parseInt(valueOfKey(trimmed, "remain"), remain);
            }
        }
        return remain;
    }

    static String nativeHelperPath() {
        return findNativeHelper();
    }

    static String nativeDaemonSocketPath() {
        return ensureNativeDaemon() ? DAEMON_SOCKET : null;
    }

    private static synchronized String findNativeHelper() {
        long now = System.currentTimeMillis();
        if (helperCacheAt > 0 && now - helperCacheAt >= 0 && now - helperCacheAt < HELPER_CACHE_TTL_MS) {
            return helperCachePath;
        }
        for (String path : HELPER_CANDIDATES) {
            try {
                File f = new File(path);
                if (f.exists() && f.isFile() && f.canExecute()) {
                    helperCachePath = path;
                    helperCacheAt = now;
                    return helperCachePath;
                }
            } catch (Throwable ignored) {}
        }
        helperCachePath = null;
        helperCacheAt = now;
        return null;
    }


    private static synchronized void publishDaemonCache(Boolean ok, long at) {
        daemonCacheOk = ok;
        daemonCacheAt = at;
        daemonCacheGeneration++;
    }

    private static synchronized void invalidateDaemonCache(long generation) {
        // An older failed request must not discard a newer successful startup.
        if (generation == daemonCacheGeneration) publishDaemonCache(Boolean.FALSE, System.currentTimeMillis());
    }

    private static NativeRun runNativeCommand(String helper, String[] helperArgs, String daemonCommand, int timeoutMs) throws Exception {
        final boolean ready;
        final long generation;
        synchronized (CgroupFreezeUtil.class) {
            ready = ensureNativeDaemon();
            generation = daemonCacheGeneration;
        }
        // Only lifecycle/cache work is newly serialized; do not hold its monitor
        // around an otherwise independent socket request or native fallback.
        if (ready) {
            try {
                NativeRun daemonRun = runNativeDaemonCommand(daemonCommand, timeoutMs);
                if (!daemonRun.timedOut && daemonRun.exitCode == 0 && daemonRun.output != null && daemonRun.output.trim().length() > 0) {
                    daemonRun.viaDaemon = true;
                    return daemonRun;
                }
            } catch (Throwable ignored) {}
            // Empty/nonzero/timeout replies are transport failures too. Do not
            // leave the batch-pinned hot path pointing at a dead daemon.
            invalidateDaemonCache(generation);
            return uncertainDaemonResult(daemonCommand);
        }
        // A failed HELLO/transport does not prove its native worker exited.
        // Never overlap it with a CLI mutation; recover through the daemon.
        synchronized (CgroupFreezeUtil.class) {
            if (daemonMayHaveWorkers) return uncertainDaemonResult(daemonCommand);
            return runNativeHelper(helper, helperArgs, timeoutMs);
        }
    }

    private static NativeRun uncertainDaemonResult(String command) {
        NativeRun r = new NativeRun();
        r.exitCode = 75;
        r.timedOut = true;
        r.viaDaemon = true;
        r.output = "CGFREEZER_COMMAND_UNCERTAIN noRetry=true command=" + command.split(" ", 2)[0];
        return r;
    }

    static synchronized boolean ensureNativeDaemon() {
        long now = System.currentTimeMillis();
        if (daemonCacheOk != null && Boolean.TRUE.equals(daemonCacheOk) && batchDaemonPinned) {
            return true;
        }
        if (daemonCacheOk != null && now - daemonCacheAt >= 0 && now - daemonCacheAt < (Boolean.TRUE.equals(daemonCacheOk) ? DAEMON_CACHE_TTL_MS : DAEMON_RETRY_MS)) {
            return Boolean.TRUE.equals(daemonCacheOk);
        }
        try {
            NativeRun hello = runNativeDaemonCommand("HELLO", 600);
            if (!hello.timedOut && hello.output.contains("CGFREEZER_DAEMON_HELLO ok=true")) {
                daemonMayHaveWorkers = true;
                publishDaemonCache(Boolean.TRUE, now);
                return true;
            }
        } catch (Throwable ignored) {}
        if (daemonStartingProcess != null && daemonStartingProcess.isAlive()) {
            publishDaemonCache(Boolean.FALSE, now);
            return false;
        }
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) {
            publishDaemonCache(Boolean.FALSE, now);
            return false;
        }
        try {
            ProcessBuilder pb = new ProcessBuilder(helper, "daemon", DAEMON_SOCKET);
            pb.redirectErrorStream(true);
            final Process started = pb.start();
            daemonStartingProcess = started;
            daemonMayHaveWorkers = true;
            // Drain daemon stdout/stderr so its pipe does not block.
            Thread drainer = new Thread(() -> {
                try (InputStream in = started.getInputStream()) {
                    byte[] buf = new byte[512];
                    while (in.read(buf) >= 0) {}
                } catch (Throwable ignored) {}
            }, "speedbackup-cgfreezerd-drainer");
            drainer.setDaemon(true);
            drainer.start();
            for (int i = 0; i < 10; i++) {
                sleepQuiet(80);
                try {
                    NativeRun hello = runNativeDaemonCommand("HELLO", 600);
                    if (!hello.timedOut && hello.output.contains("CGFREEZER_DAEMON_HELLO ok=true")) {
                        publishDaemonCache(Boolean.TRUE, System.currentTimeMillis());
                        return true;
                    }
                } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {}
        publishDaemonCache(Boolean.FALSE, System.currentTimeMillis());
        return false;
    }

    // Read-only query against the current run's existing daemon. Do not start
    // a daemon here: the shell retains the established fallback path.
    static String wchanPidList(int userId, String pids, String expect) throws Exception {
        return runNativeDaemonCommand("WCHAN_PID_LIST " + userId + " " + pids + " " + expect, 1500).output;
    }

    static String correctiveThawPackage(int userId, String pkg) throws Exception {
        return correctiveThawPackage(userId,pkg,700);
    }

    static String correctiveThawPackage(int userId, String pkg,int timeoutMs) throws Exception {
        int uid = resolvePackageUid(userId, pkg, new StringBuilder(), "GUARD_CORRECTIVE_UID");
        if (uid < 10000) throw new IllegalArgumentException("non-app uid");
        String out = runNativeDaemonCommand("THAW_UID " + uid + " " + timeoutMs, Math.max(1500,timeoutMs+500)).output;
        return out + "\n" + restorePersistedPackage(userId, pkg, "local-read-corrective");
    }

    static NativeRun runNativeDaemonCommand(String command, int timeoutMs) throws Exception {
        LocalSocket socket = new LocalSocket();
        ByteArrayOutputStream out = new ByteArrayOutputStream(4096);
        long start = System.currentTimeMillis();
        try {
            socket.connect(new LocalSocketAddress(DAEMON_SOCKET, LocalSocketAddress.Namespace.FILESYSTEM));
            try { socket.setSoTimeout(Math.max(100, timeoutMs)); } catch (Throwable ignored) {}
            OutputStream os = socket.getOutputStream();
            os.write((command + "\n").getBytes(StandardCharsets.UTF_8));
            os.flush();
            try { socket.shutdownOutput(); } catch (Throwable ignored) {}
            InputStream in = socket.getInputStream();
            byte[] buf = new byte[1024];
            int total = 0;
            int n;
            while ((n = in.read(buf)) >= 0 && total < 262144) {
                out.write(buf, 0, n);
                total += n;
            }
            NativeRun r = new NativeRun();
            r.exitCode = 0;
            r.timedOut = false;
            r.output = new String(out.toByteArray(), StandardCharsets.UTF_8).trim();
            r.viaDaemon = true;
            return r;
        } catch (Throwable t) {
            if (t instanceof Exception) throw (Exception) t;
            throw new Exception(t);
        } finally {
            try { socket.close(); } catch (Throwable ignored) {}
        }
    }

    private static NativeRun runNativeHelper(String helper, String[] args, int timeoutMs) throws Exception {
        List<String> cmd = new ArrayList<>();
        cmd.add(helper);
        for (String arg : args) cmd.add(arg == null ? "" : arg);
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.redirectErrorStream(true);
        Process proc = pb.start();
        ByteArrayOutputStream out = new ByteArrayOutputStream(4096);
        Thread reader = new Thread(() -> {
            try (InputStream in = proc.getInputStream()) {
                byte[] buf = new byte[1024];
                int total = 0;
                int n;
                while ((n = in.read(buf)) >= 0 && total < 262144) {
                    out.write(buf, 0, n);
                    total += n;
                }
            } catch (Throwable ignored) {}
        }, "cgfreezer-reader");
        reader.setDaemon(true);
        reader.start();
        boolean done = proc.waitFor(Math.max(100, timeoutMs), TimeUnit.MILLISECONDS);
        if (!done) {
            try { proc.destroy(); } catch (Throwable ignored) {}
            try { proc.destroyForcibly(); } catch (Throwable ignored) {}
        }
        try { reader.join(200); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        NativeRun r = new NativeRun();
        r.timedOut = !done;
        r.exitCode = done ? proc.exitValue() : -999;
        r.output = new String(out.toByteArray()).trim();
        return r;
    }

    private static boolean containsToken(String output, String token) {
        return output != null && token != null && output.contains(token);
    }

    private static String valueOfKey(String output, String key) {
        if (output == null || key == null || key.isEmpty()) return "";
        String prefix = key + "=";
        String normalized = output.replace('\n', ' ').replace('\r', ' ');
        String[] parts = normalized.split("\\s+");
        for (String part : parts) {
            if (part != null && part.startsWith(prefix)) return part.substring(prefix.length());
        }
        return "";
    }

    private static int parseInt(String raw, int fallback) {
        try { return Integer.parseInt(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }
    private static boolean isV1FreezerPath(String path) {
        return path != null && path.contains("cgroup.procs") && !path.endsWith("cgroup.freeze");
    }


    private static boolean definitelyAbsent(File path) {
        if (path == null) return false;
        try {
            java.nio.file.Files.readAttributes(path.toPath(), java.nio.file.attribute.BasicFileAttributes.class,
                    java.nio.file.LinkOption.NOFOLLOW_LINKS);
            return false;
        } catch (java.nio.file.NoSuchFileException missing) { return true; }
        catch (Exception unavailable) { return false; }
    }

    private static StopStats restoreSession(FreezeSession session, int timeoutMs, StringBuilder out, String tagPrefix) {
        StopStats stats = new StopStats();
        List<FreezeEntry> ordered = new ArrayList<>(session.entries);
        if ("timeline".equals(session.owner)) ordered.sort((a, b) -> Boolean.compare(b.pid < 0, a.pid < 0));
        for (FreezeEntry e : ordered) {
            boolean v1Entry = isV1FreezerPath(e.path);
            File f = new File(e.path == null ? "" : e.path);
            try {
                String target = "1".equals(e.originalFreeze) ? "1" : "0";
                if (e.pid > 0 && new File("/proc/" + e.pid).exists()) {
                    long currentStart = procStartTime(e.pid);
                    int currentUid = readStatusUid(e.pid);
                    if (e.procStartTime <= 0 || currentStart <= 0 || currentUid < 0) {
                        stats.failed++;
                        out.append(tagPrefix).append("_RESTORE_FAILED reason=identity_unavailable stateRetained=true\n");
                        continue;
                    }
                    if (e.procStartTime != currentStart || e.uid != currentUid) {
                        stats.missingPath++;
                        out.append(tagPrefix).append("_RESTORE_ORIGINAL_PROCESS_GONE reason=identity_changed mutation=false\n");
                        continue;
                    }
                }
                if (!v1Entry && !f.exists()) {
                    boolean gone = e.pid > 0 ? definitelyAbsent(new File("/proc/" + e.pid))
                            : definitelyAbsent(f.getParentFile());
                    if (gone && definitelyAbsent(f)) {
                        stats.missingPath++;
                        out.append(tagPrefix).append("_RESTORE_PATH_MISSING ok=true reason=original_scope_gone\n");
                    } else {
                        stats.failed++;
                        out.append(tagPrefix).append("_RESTORE_PATH_UNAVAILABLE ok=false stateRetained=true\n");
                    }
                    continue;
                }
                Boolean nativeOk = tryNativeRestorePath(e, target, timeoutMs, out, tagPrefix);
                if (Boolean.TRUE.equals(nativeOk)) {
                    stats.restored++;
                    continue;
                }
                if (!(e.pid < 0 && "timeline".equals(e.owner))) {
                    stats.failed++;
                    out.append(tagPrefix).append("_RESTORE_FAIL_V1_NATIVE_REQUIRED pid=").append(e.pid)
                            .append(" path=").append(sanitize(e.path))
                            .append(" target=").append(sanitize(target))
                            .append(" nativeOk=").append(nativeOk)
                            .append('\n');
                    continue;
                }
                writeFileText(f, target + "\n");
                String rb = readFileTrim(f, 64);
                boolean eventOk = waitFrozenValue(e.path, target, timeoutMs, out, tagPrefix + "_WAIT_RESTORE");
                boolean ok = target.equals(normalizeFreezeValue(rb)) && eventOk;
                out.append(tagPrefix).append("_RESTORE pid=").append(e.pid)
                        .append(" path=").append(sanitize(e.path))
                        .append(" write=").append(target)
                        .append(" readback=").append(sanitize(rb))
                        .append(" eventOk=").append(eventOk)
                        .append(" ok=").append(ok)
                        .append('\n');
                if (ok) stats.restored++; else stats.failed++;
            } catch (Throwable t) {
                stats.failed++;
                out.append(tagPrefix).append("_RESTORE_ERROR pid=").append(e.pid)
                        .append(" path=").append(sanitize(e.path))
                        .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                        .append('\n');
            }
        }
        return stats;
    }

    private static String summaryLine(String stage, FreezeSession session, int checked, int frozen, int alreadyFrozen, int skipped, boolean stateFlag, int restored, int missingPath, int failed, boolean ok, long startMs) {
        String backend = summarizeBackends(session);
        String pids = summarizePids(session);
        StringBuilder line = new StringBuilder(256);
        line.append("CGROUP_FREEZER_SUMMARY stage=").append(stage)
                .append(" ok=").append(ok)
                .append(" token=").append(session == null ? -1 : session.token)
                .append(" user=").append(session == null ? -1 : session.userId)
                .append(" package=").append(session == null ? "-" : sanitize(session.packageName))
                .append(" backend=").append(backend)
                .append(" pids=").append(pids)
                .append(" checked=").append(checked)
                .append(" frozenCount=").append(frozen)
                .append(" alreadyFrozen=").append(alreadyFrozen)
                .append(" skipped=").append(skipped)
                .append(" restored=").append(restored)
                .append(" missingPath=").append(missingPath)
                .append(" failed=").append(failed)
                .append(" stateFlag=").append(stateFlag)
                .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                .append('\n');
        return line.toString();
    }

    private static String summarizeBackends(FreezeSession session) {
        if (session == null || session.entries.isEmpty()) return "none";
        boolean v1 = false;
        boolean v2 = false;
        boolean other = false;
        for (FreezeEntry e : session.entries) {
            if (isV1FreezerPath(e.path)) v1 = true;
            else if (e.path != null && e.path.endsWith("cgroup.freeze")) v2 = true;
            else other = true;
        }
        StringBuilder b = new StringBuilder();
        if (v2) b.append("v2");
        if (v1) { if (b.length() > 0) b.append('+'); b.append("v1"); }
        if (other) { if (b.length() > 0) b.append('+'); b.append("other"); }
        return b.length() == 0 ? "none" : b.toString();
    }

    private static String summarizePids(FreezeSession session) {
        if (session == null || session.entries.isEmpty()) return "-";
        StringBuilder b = new StringBuilder();
        int count = 0;
        for (FreezeEntry e : session.entries) {
            if (count >= 16) { b.append(",..."); break; }
            if (b.length() > 0) b.append(',');
            b.append(e.pid).append(':').append(e.uid);
            count++;
        }
        return sanitize(b.toString());
    }

    private static String doneLine(String stage, boolean ok, int token, int checked, int frozen, int skipped, String reason, long startMs) {
        return new OperationResult("cgroup-start", ok).token(token).counts(checked, frozen, 0, -1, -1).appendTo("CGROUP_FREEZE_" + stage + "_DONE ok=" + ok
                + " token=" + token
                + " checked=" + checked
                + " frozenCount=" + frozen
                + " skipped=" + skipped
                + " reason=" + sanitize(reason)
                + " elapsedMs=" + (System.currentTimeMillis() - startMs) + "\n");
    }

    private static int resolvePackageUid(int userId, String pkg, StringBuilder out, String tag) {
        try {
            String raw = AppInventoryUtil.pkgUidSingle(userId, pkg, true);
            int uid = parseUidFromInventory(raw, pkg);
            out.append(tag).append(" source=appInventory uid=").append(uid)
                    .append(" raw=").append(sanitize(firstLine(raw))).append('\n');
            return uid;
        } catch (Throwable t) {
            out.append(tag).append(" source=appInventory uid=-1 error=")
                    .append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage())).append('\n');
            return -1;
        }
    }

    private static int parseUidFromInventory(String raw, String pkg) {
        if (raw == null) return -1;
        String[] lines = raw.split("\\n");
        for (String line : lines) {
            String v = line == null ? "" : line.trim();
            if (v.isEmpty()) continue;
            String[] parts = v.split("\\t");
            if (parts.length >= 2 && pkg.equals(parts[0])) {
                try { return Integer.parseInt(parts[1].trim()); } catch (Throwable ignored) { return -1; }
            }
        }
        return -1;
    }

    private static CgroupRootInfo inspectCgroupRoot() {
        long now = System.currentTimeMillis();
        CgroupRootInfo cached = rootCache;
        if (cached != null && now - rootCacheAt >= 0 && now - rootCacheAt < ROOT_CACHE_TTL_MS) {
            return cached;
        }
        CgroupRootInfo info = new CgroupRootInfo();
        File root = new File(CGROUP_ROOT);
        info.rootExists = root.exists() && root.isDirectory();
        File controllers = new File(root, "cgroup.controllers");
        info.controllersFileExists = controllers.exists();
        try {
            info.controllers = readFileTrim(controllers, 4096);
            info.controllersReadable = info.controllers.length() > 0 || controllers.length() == 0;
            String padded = " " + info.controllers + " ";
            info.hasFreezer = padded.contains(" freezer ");
        } catch (Throwable t) {
            info.controllers = t.getClass().getSimpleName();
            info.controllersReadable = false;
            info.hasFreezer = false;
        }
        rootCache = info;
        rootCacheAt = now;
        return info;
    }

    private static List<PidInfo> findPackagePids(String pkg, int userId, StringBuilder out) {
        List<PidInfo> nativeResult = tryNativeScanPackage(pkg, userId, out);
        if (nativeResult != null) return nativeResult;
        return findPackagePidsJava(pkg, userId);
    }

    private static List<PidInfo> findPackagePidsJava(String pkg, int userId) {
        List<PidInfo> result = new ArrayList<>();
        File[] entries = new File("/proc").listFiles();
        if (entries == null) throw new IllegalStateException("Process inventory unavailable");
        for (File entry : entries) {
            String name = entry.getName();
            if (!isDigits(name)) continue;
            int pid;
            try { pid = Integer.parseInt(name); } catch (Throwable ignored) { continue; }
            String cmdline = readProcCmdline(pid);
            if (!isPackageProcess(cmdline, pkg)) continue;
            PidInfo info = new PidInfo();
            info.pid = pid;
            info.cmdline = cmdline;
            info.uid = readStatusUid(pid);
            if (info.uid < 0) {
                if (entry.exists()) throw new IllegalStateException("Process UID unavailable: " + pid);
                continue;
            }
            if (userIdFromUid(info.uid) != userId) continue;
            result.add(info);
        }
        return result;
    }
    private static PidInfo explicitPidInfo(String pkg, int userId, int pid, StringBuilder out) {
        String cmdline = readProcCmdline(pid);
        int uid = readStatusUid(pid);
        boolean userOk = uid >= 0 && userIdFromUid(uid) == userId;
        boolean pkgOk = isPackageProcess(cmdline, pkg);
        if (out != null) {
            out.append("CGROUP_FREEZE_EXPLICIT_PID_CHECK pid=").append(pid)
                    .append(" uid=").append(uid)
                    .append(" userOk=").append(userOk)
                    .append(" packageOk=").append(pkgOk)
                    .append(" cmd=").append(sanitize(cmdline))
                    .append('\n');
        }
        if (!userOk || !pkgOk) return null;
        PidInfo info = new PidInfo();
        info.pid = pid;
        info.uid = uid;
        info.cmdline = cmdline;
        return info;
    }


    private static List<PidInfo> tryNativeScanPackage(String pkg, int userId, StringBuilder out) {
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return null;
        long startMs = System.currentTimeMillis();
        try {
            NativeRun run = runNativeCommand(helper, new String[] {"scan-package", pkg, String.valueOf(userId)}, "SCAN " + pkg + " " + userId, 1200);
            if (out != null) {
                out.append("CGROUP_FREEZE_NATIVE_HELPER_SCAN package=").append(sanitize(pkg))
                        .append(" helper=").append(sanitize(helper))
                        .append(" viaDaemon=").append(run.viaDaemon)
                        .append(" exit=").append(run.exitCode)
                        .append(" timedOut=").append(run.timedOut)
                        .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                        .append(" uidPidByC=true perAppQuery=true daemonPersistent=").append(batchDaemonPinned)
                        .append(" output=").append(sanitize(run.output))
                        .append('\n');
            }
            if (run.timedOut || run.exitCode != 0 || !containsToken(run.output, "CGFREEZER_SCAN_DONE ok=true")) return null;
            String csv = valueOfKey(run.output, "pids");
            List<PidInfo> parsed = parseNativePidCsv(csv);
            int expected = parseInt(valueOfKey(run.output, "count"), -1);
            return parsed != null && expected == parsed.size() ? parsed : null;
        } catch (Throwable t) {
            if (out != null) {
                out.append("CGROUP_FREEZE_NATIVE_HELPER_SCAN_ERROR package=").append(sanitize(pkg))
                        .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                        .append('\n');
            }
            return null;
        }
    }

    private static List<PidInfo> parseNativePidCsv(String csv) {
        if (csv == null || csv.isEmpty() || "-".equals(csv)) return new ArrayList<>();
        List<PidInfo> result = new ArrayList<>();
        String[] items = csv.split(",");
        for (String item : items) {
            if (item == null || item.isEmpty()) continue;
            String[] parts = item.split(":", 3);
            if (parts.length < 3) continue;
            int pid = parseInt(parts[0], -1);
            int uid = parseInt(parts[1], -1);
            String cmd = parts[2];
            if (pid <= 0 || cmd.isEmpty()) continue;
            PidInfo info = new PidInfo();
            info.pid = pid;
            info.uid = uid;
            info.cmdline = cmd;
            result.add(info);
        }
        return result;
    }

    private static boolean isPackageProcess(String cmdline, String pkg) {
        return cmdline != null && pkg != null && !pkg.isEmpty() && (cmdline.equals(pkg) || cmdline.startsWith(pkg + ":"));
    }

    private static int userIdFromUid(int uid) {
        if (uid < 0) return -1;
        return uid >= 100000 ? uid / 100000 : 0;
    }

    private static CandidateSelection selectWritableCandidate(PidInfo pidInfo, int packageUid, String rawCgroup, StringBuilder out, String tag) {
        Set<Candidate> candidates = buildCandidates(pidInfo, packageUid, rawCgroup);
        for (Candidate c : candidates) {
            CandidateProbe probe = inspectCandidate(c);
            out.append(tag).append(" pid=").append(pidInfo.pid)
                    .append(" source=").append(sanitize(c.source))
                    .append(" path=").append(sanitize(c.freezePath))
                    .append(" exists=").append(probe.exists)
                    .append(" readable=").append(probe.readable)
                    .append(" writable=").append(probe.writable)
                    .append(" freezeValue=").append(sanitize(probe.freezeValue))
                    .append(" eventsReadable=").append(probe.eventsReadable)
                    .append(" frozen=").append(sanitize(probe.frozen))
                    .append(" populated=").append(sanitize(probe.populated))
                    .append('\n');
            if (probe.exists && probe.readable && probe.writable && probe.eventsReadable) {
                CandidateSelection sel = new CandidateSelection();
                sel.candidate = c;
                sel.probe = probe;
                return sel;
            }
        }
        return null;
    }

    private static CandidateProbe inspectCandidate(Candidate c) {
        CandidateProbe p = new CandidateProbe();
        File freeze = new File(c.freezePath);
        p.exists = freeze.exists();
        p.readable = freeze.canRead();
        p.writable = freeze.canWrite();
        if (p.exists && p.readable) {
            try { p.freezeValue = readFileTrim(freeze, 64); } catch (Throwable t) { p.freezeValue = t.getClass().getSimpleName(); }
        } else {
            p.freezeValue = "-";
        }
        File events = eventsFileForFreezePath(c.freezePath);
        p.eventsExists = events.exists();
        p.eventsReadable = events.canRead();
        if (p.eventsExists && p.eventsReadable) {
            try { p.eventsRaw = readFileTrim(events, 4096); } catch (Throwable t) { p.eventsRaw = t.getClass().getSimpleName(); }
            p.frozen = parseEventsValue(p.eventsRaw, "frozen");
            p.populated = parseEventsValue(p.eventsRaw, "populated");
        } else {
            p.eventsRaw = "-";
            p.frozen = "-";
            p.populated = "-";
        }
        return p;
    }

    private static Set<Candidate> buildCandidates(PidInfo pidInfo, int packageUid, String rawCgroup) {
        Set<Candidate> candidates = new LinkedHashSet<>();
        String unified = parseUnifiedCgroupPath(rawCgroup);
        if (unified != null) candidates.add(new Candidate("proc-cgroup", buildCgroupFile(unified, "cgroup.freeze")));
        int uidForPath = pidInfo != null && pidInfo.uid >= 0 ? pidInfo.uid : packageUid;
        int pid = pidInfo == null ? -1 : pidInfo.pid;
        if (uidForPath >= 0 && pid > 0) {
            candidates.add(new Candidate("uid-pid", CGROUP_ROOT + "/uid_" + uidForPath + "/pid_" + pid + "/cgroup.freeze"));
            candidates.add(new Candidate("uid", CGROUP_ROOT + "/uid_" + uidForPath + "/cgroup.freeze"));
        }
        if (packageUid >= 0 && packageUid != uidForPath && pid > 0) {
            candidates.add(new Candidate("package-uid-pid", CGROUP_ROOT + "/uid_" + packageUid + "/pid_" + pid + "/cgroup.freeze"));
            candidates.add(new Candidate("package-uid", CGROUP_ROOT + "/uid_" + packageUid + "/cgroup.freeze"));
        }
        return candidates;
    }

    private static boolean waitFrozenValue(String freezePath, String expected, int timeoutMs, StringBuilder out, String tag) {
        long start = System.currentTimeMillis();
        long deadline = start + Math.max(1, timeoutMs);
        String lastFrozen = "-";
        String lastEvents = "-";
        File events = eventsFileForFreezePath(freezePath);
        while (System.currentTimeMillis() <= deadline) {
            try {
                lastEvents = readFileTrim(events, 4096);
                lastFrozen = normalizeFreezeValue(parseEventsValue(lastEvents, "frozen"));
                if (expected.equals(lastFrozen)) {
                    out.append(tag).append(" ok=true expected=").append(sanitize(expected))
                            .append(" frozen=").append(sanitize(lastFrozen))
                            .append(" elapsedMs=").append(System.currentTimeMillis() - start)
                            .append(" events=").append(sanitize(lastEvents))
                            .append('\n');
                    return true;
                }
            } catch (Throwable t) {
                lastFrozen = t.getClass().getSimpleName();
                lastEvents = t.getMessage();
            }
            sleepQuiet(20);
        }
        out.append(tag).append(" ok=false expected=").append(sanitize(expected))
                .append(" frozen=").append(sanitize(lastFrozen))
                .append(" elapsedMs=").append(System.currentTimeMillis() - start)
                .append(" events=").append(sanitize(lastEvents))
                .append('\n');
        return false;
    }

    private static boolean writePersistentSession(FreezeSession session, StringBuilder out) {
        try {
            File state = new File(STATE_FILE);
            File parent = state.getParentFile();
            if (parent != null && !parent.isDirectory()) parent.mkdirs();
            try (FileOutputStream fos = new FileOutputStream(state, true)) {
                for (FreezeEntry e : session.entries) {
                    fos.write(encodeEntry(e).getBytes());
                    fos.write('\n');
                }
                fos.flush();
                fos.getFD().sync();
            }
            return true;
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_STATE_WRITE_FAILED token=").append(session.token)
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage())).append('\n');
            return false;
        }
    }

    private static FreezeSession readPersistentSession(int token) {
        List<FreezeSession> all = readAllPersistentSessions(new StringBuilder());
        for (FreezeSession s : all) if (s.token == token) return s;
        return null;
    }


    private static List<Integer> readPersistentTokensForPackage(int userId, String pkg) {
        List<FreezeSession> sessions = readAllPersistentSessions();
        List<Integer> tokens = new ArrayList<>();
        for (FreezeSession s : sessions) {
            if (s.userId == userId && pkg.equals(s.packageName)) tokens.add(s.token);
        }
        return tokens;
    }

    private static List<FreezeSession> readAllPersistentSessions() {
        return readAllPersistentSessions(null);
    }

    // Recovery can process independent valid rows while retaining every corrupt row.
    // Normal start/ownership queries stay strict: unknown ownership must not permit freezing.
    private static List<FreezeSession> readAllPersistentSessions(StringBuilder diagnostics) {
        Map<Integer, FreezeSession> map = new HashMap<>();
        File state = new File(STATE_FILE);
        if (!state.exists()) return new ArrayList<>();
        try {
            String raw = new String(java.nio.file.Files.readAllBytes(state.toPath()), java.nio.charset.StandardCharsets.UTF_8);
            String[] lines = raw.split("\\n");
            for (String line : lines) {
                FreezeEntry e = decodeEntry(line);
                if (line.trim().isEmpty()) continue;
                if (e == null) {
                    if (diagnostics == null) throw new java.io.IOException("Malformed freeze state");
                    diagnostics.append("CGROUP_FREEZE_STATE_INVALID stateRetained=true\n");
                    continue;
                }
                FreezeSession s = map.get(e.token);
                if (s == null) {
                    s = new FreezeSession();
                    s.token = e.token;
                    s.userId = e.userId;
                    s.packageName = e.packageName;
                    s.owner = e.owner;
                    s.startedAt = e.startedAt;
                    map.put(e.token, s);
                }
                s.entries.add(e);
            }
        } catch (Exception e) {
            throw new IllegalStateException("Freeze recovery state unreadable; retained", e);
        }
        return new ArrayList<>(map.values());
    }

    private static boolean removePersistentToken(int token) {
        File state = new File(STATE_FILE);
        if (!state.exists()) return true;
        File tmp = new File(STATE_FILE + ".tmp." + android.os.Process.myPid() + "." + System.currentTimeMillis());
        boolean wrote = false;
        try {
            String raw = new String(java.nio.file.Files.readAllBytes(state.toPath()), java.nio.charset.StandardCharsets.UTF_8);
            try (FileOutputStream fos = new FileOutputStream(tmp, false)) {
                String[] lines = raw.split("\\n");
                for (String line : lines) {
                    FreezeEntry e = decodeEntry(line);
                    if (line.trim().isEmpty()) continue;
                    // Never discard an unidentified recovery row. It remains visible to
                    // strict readers and makes aggregate cleanup report incomplete.
                    if (e != null && e.token == token) continue;
                    fos.write(line.getBytes());
                    fos.write('\n');
                    wrote = true;
                }
                fos.flush();
                fos.getFD().sync();
            }
            if (wrote) {
                if (!tmp.renameTo(state)) {
                    throw new java.io.IOException("Atomic state replacement failed");
                }
            } else {
                if (!state.delete() && state.exists()) throw new java.io.IOException("State deletion failed");
                tmp.delete();
            }
            return true;
        } catch (Throwable ignored) {
            try { tmp.delete(); } catch (Throwable ignored2) {}
            return false;
        }
    }

    private static String encodeEntry(FreezeEntry e) {
        return e.token + "\t" + e.userId + "\t" + safeWord(e.packageName) + "\t" + e.pid + "\t" + e.uid + "\t"
                + e.startedAt + "\t" + safeWord(e.owner) + "\t" + safeWord(e.originalFreeze) + "\t"
                + safeWord(e.originalFrozen) + "\t" + encodeField(e.path) + "\t" + encodeField(e.processName) + "\t" + e.procStartTime;
    }

    private static FreezeEntry decodeEntry(String line) {
        if (line == null || line.trim().isEmpty()) return null;
        String[] p = line.split("\\t", -1);
        if (p.length < 11) return null;
        try {
            FreezeEntry e = new FreezeEntry();
            e.token = Integer.parseInt(p[0]);
            e.userId = Integer.parseInt(p[1]);
            e.packageName = p[2];
            e.pid = Integer.parseInt(p[3]);
            e.uid = Integer.parseInt(p[4]);
            e.startedAt = Long.parseLong(p[5]);
            e.owner = p[6];
            e.originalFreeze = p[7];
            e.originalFrozen = p[8];
            e.path = decodeField(p[9]);
            e.processName = decodeField(p[10]);
            e.procStartTime = p.length > 11 ? Long.parseLong(p[11]) : 0;
            return e;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static String encodeField(String raw) {
        if (raw == null) return "";
        return raw.replace("%", "%25").replace("\t", "%09").replace("\n", "%0A").replace("\r", "%0D");
    }

    private static String decodeField(String raw) {
        if (raw == null) return "";
        return raw.replace("%0D", "\r").replace("%0A", "\n").replace("%09", "\t").replace("%25", "%");
    }



    private static File eventsFileForFreezePath(String freezePath) {
        File freeze = new File(freezePath == null ? "" : freezePath);
        File dir = freeze.getParentFile();
        return dir == null ? new File("/dev/null") : new File(dir, "cgroup.events");
    }

    private static String normalizeFreezeValue(String v) {
        if (v == null) return "-";
        String t = v.trim();
        if (t.startsWith("0")) return "0";
        if (t.startsWith("1")) return "1";
        return t.isEmpty() ? "-" : t;
    }

    private static int clamp(int value, int min, int max, int fallback) {
        if (value < min || value > max) return fallback;
        return value;
    }

    private static void writeFileText(File f, String value) throws Exception {
        try (FileOutputStream out = new FileOutputStream(f, false)) {
            out.write(value.getBytes());
            out.flush();
        }
    }

    private static void sleepQuiet(long ms) {
        if (ms <= 0) return;
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }

    private static String parseEventsValue(String raw, String key) {
        if (raw == null || key == null) return "-";
        String[] lines = raw.split("\\n");
        for (String line : lines) {
            String v = line == null ? "" : line.trim();
            if (v.startsWith(key + " ")) return v.substring(key.length()).trim();
        }
        return "-";
    }

    private static String parseUnifiedCgroupPath(String raw) {
        if (raw == null || raw.isEmpty()) return null;
        String[] lines = raw.split("\\n");
        for (String line : lines) {
            if (line == null) continue;
            if (line.startsWith("0::")) {
                String path = line.substring(3).trim();
                if (path.isEmpty()) return "/";
                return path.startsWith("/") ? path : "/" + path;
            }
        }
        return null;
    }

    private static String buildCgroupFile(String unifiedPath, String fileName) {
        String path = unifiedPath == null || unifiedPath.isEmpty() ? "/" : unifiedPath;
        if ("/".equals(path)) return CGROUP_ROOT + "/" + fileName;
        return CGROUP_ROOT + path + "/" + fileName;
    }

    private static String readProcCmdline(int pid) {
        try {
            byte[] data = readFileBytes(new File("/proc/" + pid + "/cmdline"), 8192);
            if (data.length == 0) return "";
            int end = data.length;
            while (end > 0 && data[end - 1] == 0) end--;
            String value = new String(data, 0, end);
            int nul = value.indexOf('\0');
            if (nul >= 0) value = value.substring(0, nul);
            return value.trim();
        } catch (Exception failure) {
            if (new File("/proc/" + pid).exists()) throw new IllegalStateException("Process cmdline unavailable: " + pid, failure);
            return "";
        }
    }

    private static int readStatusUid(int pid) {
        try {
            String status = readFileTrim(new File("/proc/" + pid + "/status"), 8192);
            String[] lines = status.split("\\n");
            for (String line : lines) {
                if (line != null && line.startsWith("Uid:")) {
                    String rest = line.substring(4).trim();
                    String[] parts = rest.split("\\s+");
                    if (parts.length > 0) return Integer.parseInt(parts[0]);
                }
            }
        } catch (Throwable ignored) {}
        return -1;
    }

    private static String readProcCgroup(int pid) {
        try { return readFileTrim(new File("/proc/" + pid + "/cgroup"), 16384); }
        catch (Throwable t) { return t.getClass().getSimpleName() + ":" + t.getMessage(); }
    }

    private static String readFileTrim(File f, int maxBytes) throws Exception {
        return new String(readFileBytes(f, maxBytes)).trim();
    }

    private static byte[] readFileBytes(File f, int maxBytes) throws Exception {
        if (f == null || maxBytes <= 0) return new byte[0];
        try (FileInputStream in = new FileInputStream(f); ByteArrayOutputStream out = new ByteArrayOutputStream(Math.min(4096, maxBytes))) {
            byte[] buf = new byte[1024];
            int total = 0;
            while (total < maxBytes) {
                int want = Math.min(buf.length, maxBytes - total);
                int n = in.read(buf, 0, want);
                if (n < 0) break;
                out.write(buf, 0, n);
                total += n;
            }
            return out.toByteArray();
        }
    }

    private static boolean isDigits(String v) {
        if (v == null || v.isEmpty()) return false;
        for (int i = 0; i < v.length(); i++) {
            char c = v.charAt(i);
            if (c < '0' || c > '9') return false;
        }
        return true;
    }

    private static String renderPids(List<PidInfo> pids) {
        if (pids == null || pids.isEmpty()) return "-";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < pids.size(); i++) {
            if (i > 0) out.append(',');
            PidInfo p = pids.get(i);
            out.append(p.pid).append(':').append(p.uid).append(':').append(p.cmdline);
        }
        return out.toString();
    }

    private static String firstLine(String raw) {
        if (raw == null) return "";
        int idx = raw.indexOf('\n');
        return idx >= 0 ? raw.substring(0, idx) : raw;
    }

    private static String safePackage(String packageName) {
        if (packageName == null) return "";
        String p = packageName.trim();
        if (p.length() < 3 || p.length() > 128) return "";
        if (p.indexOf('.') < 1 || p.indexOf('\n') >= 0 || p.indexOf('\r') >= 0 || p.indexOf('\0') >= 0) return "";
        for (int i = 0; i < p.length(); i++) {
            char c = p.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_';
            if (!ok) return "";
        }
        return p;
    }

    private static String safeWord(String raw) {
        if (raw == null || raw.trim().isEmpty()) return "-";
        return raw.trim().replace('\t', '_').replace('\n', '_').replace('\r', '_').replace(' ', '_');
    }

    private static String sanitizeMultiLine(String raw) {
        return raw == null ? "-" : raw.replace('\n', '|').replace('\r', '|');
    }

    private static String sanitize(String raw) {
        if (raw == null || raw.length() == 0) return "-";
        String v = raw.replace('\n', '|').replace('\r', '|').replace('\t', '_').replace(' ', '_').replace('\0', '_');
        if (v.length() > 1500) v = v.substring(0, 1500) + "...";
        StringBuilder out = new StringBuilder(v.length());
        for (int i = 0; i < v.length(); i++) {
            char c = v.charAt(i);
            if (c >= 0x21 && c <= 0x7e) out.append(c); else out.append('_');
        }
        return out.toString();
    }

    private static final class NativeRun {
        int exitCode;
        boolean timedOut;
        boolean viaDaemon;
        String output = "";
    }

    private static final class CgroupRootInfo {
        boolean rootExists;
        boolean controllersFileExists;
        boolean controllersReadable;
        boolean hasFreezer;
        String controllers = "";
    }

    private static final class PidInfo {
        int pid;
        int uid;
        String cmdline;
    }

    private static final class Candidate {
        final String source;
        final String freezePath;
        Candidate(String source, String freezePath) {
            this.source = source == null ? "" : source;
            this.freezePath = freezePath == null ? "" : freezePath;
        }
        @Override public boolean equals(Object other) {
            return other instanceof Candidate && freezePath.equals(((Candidate) other).freezePath);
        }
        @Override public int hashCode() { return freezePath.hashCode(); }
    }

    private static final class CandidateSelection {
        Candidate candidate;
        CandidateProbe probe;
    }

    private static final class CandidateProbe {
        boolean exists;
        boolean readable;
        boolean writable;
        String freezeValue = "-";
        boolean eventsExists;
        boolean eventsReadable;
        String eventsRaw = "-";
        String frozen = "-";
        String populated = "-";
    }

    private static final class FreezeSession {
        // Process-local liveness only: never serialized or inferred from recovery.
        boolean activePrimary;
        int token;
        int userId;
        String packageName;
        String owner;
        long startedAt;
        final List<FreezeEntry> entries = new ArrayList<>();
    }

    private static final class FreezeEntry {
        int token;
        int userId;
        String packageName;
        int pid;
        int uid;
        String processName;
        String path;
        String originalFreeze;
        String originalFrozen;
        long startedAt;
        long procStartTime;
        String owner;
    }

    private static final class NativePackageFreezeResult {
        boolean noRetry;
        boolean accepted;
        int checked;
        int frozen;
        int failed;
        int alreadyFrozen;
    }

    private static final class StartPidResult {
        boolean ok;
        boolean originallyFrozen;
        String reason = "unknown";
    }

    private static final class StopStats {
        int restored;
        int missingPath;
        int failed;
    }
}
