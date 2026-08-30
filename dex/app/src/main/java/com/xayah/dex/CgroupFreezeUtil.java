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
 * /proc/<pid>/cgroup, freezes all currently alive target package pids for the whole app tar/restore
 * scope, and only accepts paths whose cgroup.freeze and cgroup.events are actually readable/writable.
 * ProcessObserver may open additional pid-specific sessions for newly awakened pids during the same
 * scope.  Stop restores the original frozen state and verifies cgroup.events.
 */
final class CgroupFreezeUtil {
    static final String VERSION = "v1.23-r487-run-tmpdir-state-scope";
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
    private static Process daemonProcess = null;
    private static volatile boolean batchDaemonPinned = false;
    private static volatile long batchDaemonPinnedAt = 0L;
    private static final String[] HELPER_CANDIDATES = new String[] {
            "/data/backup_tools/cgfreezer",
            "/data/adb/modules/SpeedBackup/tools/cgfreezer",
            "/data/local/tmp/cgfreezer"
    };
    private static long rootCacheAt = 0L;
    private static CgroupRootInfo rootCache;
    private static final AtomicInteger NEXT_TOKEN = new AtomicInteger(tokenSeed());
    private static final Map<Integer, FreezeSession> SESSIONS = new HashMap<>();


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

    private CgroupFreezeUtil() {}

    private static int tokenSeed() {
        long seed = (System.currentTimeMillis() % 100000L) * 1000L;
        seed += Math.abs(android.os.Process.myPid() % 1000);
        if (seed < 1000L) seed += 1000L;
        if (seed > Integer.MAX_VALUE - 10000L) seed = 1000L + Math.abs(android.os.Process.myPid() % 1000);
        return (int) seed;
    }

    static synchronized String start(int userId, String packageName, int explicitPid, int timeoutMs, String owner) {
        long startMs = System.currentTimeMillis();
        String pkg = safePackage(packageName);
        int safeTimeoutMs = clamp(timeoutMs, 100, 5000, 1500);
        String safeOwner = safeWord(owner == null || owner.trim().isEmpty() ? "manual" : owner.trim());
        StringBuilder out = new StringBuilder(4096);
        out.append("CGROUP_FREEZE_START_BEGIN version=").append(VERSION)
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
        List<PidInfo> pids;
        if (explicitPid > 0) {
            PidInfo direct = explicitPidInfo(pkg, userId, explicitPid, out);
            pids = new ArrayList<>();
            if (direct != null) pids.add(direct);
            if (pids.isEmpty()) {
                List<PidInfo> scanned = findPackagePids(pkg, userId, out);
                for (PidInfo p : scanned) if (p != null && p.pid == explicitPid) pids.add(p);
            }
        } else {
            pids = findPackagePids(pkg, userId, out);
        }
        out.append("CGROUP_FREEZE_START_PIDS package=").append(sanitize(pkg))
                .append(" count=").append(pids.size())
                .append(" packageUid=").append(packageUid)
                .append(" selectedPid=").append(explicitPid)
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

        NativePackageFreezeResult packageFreeze = explicitPid > 0 ? null
                : tryNativeFreezePackage(session, pids, packageUid, safeTimeoutMs, out);
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

    static synchronized String stop(int token, int expectedUserId, String expectedPackageName) {
        long startMs = System.currentTimeMillis();
        String expectedPkg = safePackage(expectedPackageName);
        StringBuilder out = new StringBuilder(4096);
        out.append("CGROUP_FREEZE_STOP_BEGIN version=").append(VERSION)
                .append(" token=").append(token)
                .append(" expectedUser=").append(expectedUserId)
                .append(" expectedPackage=").append(sanitize(expectedPkg))
                .append('\n');
        FreezeSession session = SESSIONS.remove(token);
        if (session == null) {
            session = readPersistentSession(token);
        }
        if (session == null) {
            removePersistentToken(token);
            out.append("CGROUP_FREEZE_STOP_MISSING token=").append(token).append(" stateDeleted=true\n");
            out.append("CGROUP_FREEZE_STOP_DONE ok=true token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=true reason=missing elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (expectedUserId >= 0 && session.userId != expectedUserId) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_REJECTED token=").append(token)
                    .append(" reason=user_mismatch actualUser=").append(session.userId).append('\n');
            out.append("CGROUP_FREEZE_STOP_DONE ok=false token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=false reason=user_mismatch elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        if (!expectedPkg.isEmpty() && !expectedPkg.equals(session.packageName)) {
            SESSIONS.put(token, session);
            out.append("CGROUP_FREEZE_STOP_REJECTED token=").append(token)
                    .append(" reason=package_mismatch actualPackage=").append(sanitize(session.packageName)).append('\n');
            out.append("CGROUP_FREEZE_STOP_DONE ok=false token=").append(token)
                    .append(" restored=0 missingPath=0 failed=0 stateDeleted=false reason=package_mismatch elapsedMs=")
                    .append(System.currentTimeMillis() - startMs).append('\n');
            return out.toString();
        }
        StopStats stats = restoreSession(session, 1500, out, "CGROUP_FREEZE_STOP");
        boolean stateDeleted = removePersistentToken(token);
        boolean ok = stats.failed == 0 && stateDeleted;
        if (!ok) SESSIONS.put(token, session);
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
        return out.toString();
    }

    static synchronized String status() {
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_STATUS version=").append(VERSION)
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

    static synchronized String restorePersistedPackage(int userId, String packageName, String reason) {
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
            if (r.contains("CGROUP_FREEZE_STOP_DONE ok=true")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_PACKAGE_DONE user=").append(userId)
                .append(" package=").append(sanitize(pkg))
                .append(" tokens=").append(tokens.size())
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append(" stateDeleted=").append(fail == 0)
                .append('\n');
        return out.toString();
    }

    static synchronized String restorePersistedAll(String reason) {
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_ALL_BEGIN reason=").append(sanitize(reason)).append('\n');
        List<Integer> tokens = readAllPersistentTokens();
        int ok = 0;
        int fail = 0;
        for (Integer token : tokens) {
            String r = stop(token, -1, "");
            out.append(sanitizeMultiLine(r)).append('\n');
            if (r.contains("CGROUP_FREEZE_STOP_DONE ok=true")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_PERSISTENT_RESTORE_ALL_DONE tokens=").append(tokens.size())
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append(" stateDeleted=").append(fail == 0)
                .append('\n');
        return out.toString();
    }

    static synchronized String cleanupStalePersistentStates(String reason, long ttlMs) {
        long now = System.currentTimeMillis();
        long ttl = ttlMs < 0 ? 0 : ttlMs;
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_FREEZE_CLEANUP_STALE_BEGIN reason=").append(sanitize(reason))
                .append(" ttlMs=").append(ttl).append('\n');
        List<FreezeSession> sessions = readAllPersistentSessions();
        int stale = 0;
        int ok = 0;
        int fail = 0;
        for (FreezeSession s : sessions) {
            if (ttl > 0 && now - s.startedAt < ttl) continue;
            stale++;
            String r = stop(s.token, -1, "");
            out.append(sanitizeMultiLine(r)).append('\n');
            if (r.contains("CGROUP_FREEZE_STOP_DONE ok=true")) ok++; else fail++;
        }
        out.append("CGROUP_FREEZE_CLEANUP_STALE_DONE scanned=").append(sessions.size())
                .append(" stale=").append(stale)
                .append(" ok=").append(ok)
                .append(" fail=").append(fail)
                .append('\n');
        return out.toString();
    }

    static boolean isStartOk(String result) {
        return result != null && result.contains("CGROUP_FREEZE_START_OK");
    }

    static int parseToken(String result) {
        if (result == null) return -1;
        int idx = result.indexOf("token=");
        if (idx < 0) return -1;
        idx += 6;
        int end = idx;
        while (end < result.length() && Character.isDigit(result.charAt(end))) end++;
        try { return Integer.parseInt(result.substring(idx, end)); } catch (Throwable ignored) { return -1; }
    }

    private static StartPidResult freezePid(FreezeSession session, PidInfo p, int packageUid, int timeoutMs, StringBuilder out) {
        StartPidResult nativeResult = tryNativeFreezePid(session, p, timeoutMs, out);
        if (nativeResult != null && nativeResult.ok) return nativeResult;
        StartPidResult result = new StartPidResult();
        String rawCgroup = readProcCgroup(p.pid);
        out.append("CGROUP_FREEZE_START_PROC_CGROUP pid=").append(p.pid)
                .append(" uid=").append(p.uid)
                .append(" cmdline=").append(sanitize(p.cmdline))
                .append(" raw=").append(sanitize(rawCgroup))
                .append('\n');
        CandidateSelection selection = selectWritableCandidate(p, packageUid, rawCgroup, out, "CGROUP_FREEZE_START_CANDIDATE");
        if (selection == null) {
            result.reason = "no_writable_events_readable_path";
            out.append("CGROUP_FREEZE_START_PID_SKIP pid=").append(p.pid).append(" reason=").append(result.reason).append('\n');
            return result;
        }
        Candidate c = selection.candidate;
        CandidateProbe before = selection.probe;
        String originalFreeze = normalizeFreezeValue(before.freezeValue);
        String originalFrozen = normalizeFreezeValue(before.frozen);
        boolean originalKnown = "0".equals(originalFreeze) || "1".equals(originalFreeze);
        boolean originallyFrozen = "1".equals(originalFreeze) || "1".equals(originalFrozen);
        try {
            writeFileText(new File(c.freezePath), "1\n");
            String rb = readFileTrim(new File(c.freezePath), 64);
            boolean eventOk = waitFrozenValue(c.freezePath, "1", timeoutMs, out, "CGROUP_FREEZE_START_WAIT_FROZEN");
            boolean ok = "1".equals(normalizeFreezeValue(rb)) && eventOk;
            out.append("CGROUP_FREEZE_START_WRITE pid=").append(p.pid)
                    .append(" source=").append(sanitize(c.source))
                    .append(" path=").append(sanitize(c.freezePath))
                    .append(" beforeFreeze=").append(sanitize(before.freezeValue))
                    .append(" beforeFrozen=").append(sanitize(before.frozen))
                    .append(" write=1 readback=").append(sanitize(rb))
                    .append(" eventOk=").append(eventOk)
                    .append(" ok=").append(ok)
                    .append('\n');
            if (!ok) {
                result.reason = "freeze_verify_failed";
                return result;
            }
            FreezeEntry e = new FreezeEntry();
            e.token = session.token;
            e.userId = session.userId;
            e.packageName = session.packageName;
            e.pid = p.pid;
            e.uid = p.uid;
            e.processName = p.cmdline;
            e.path = c.freezePath;
            e.originalFreeze = originalKnown ? originalFreeze : (originallyFrozen ? "1" : "0");
            e.originalFrozen = originallyFrozen ? "1" : "0";
            e.startedAt = session.startedAt;
            e.owner = session.owner;
            session.entries.add(e);
            result.ok = true;
            result.originallyFrozen = originallyFrozen;
            result.reason = "ok";
            return result;
        } catch (Throwable t) {
            result.reason = t.getClass().getSimpleName() + ":" + t.getMessage();
            out.append("CGROUP_FREEZE_START_ERROR pid=").append(p.pid)
                    .append(" error=").append(sanitize(result.reason)).append('\n');
            return result;
        }
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
                e.owner = session.owner;
                parsed.add(e);
                if (originallyFrozen) already++;
            }

            boolean accepted = !run.timedOut && run.exitCode == 0
                    && containsToken(doneLine, "ok=true") && !parsed.isEmpty();
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

    private static void tryNativeEmergencyThawUid(int uid, int timeoutMs, StringBuilder out, String reason) {
        if (uid < 10000) return;
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return;
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
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_NATIVE_EMERGENCY_THAW_UID_ERROR uid=").append(uid)
                    .append(" reason=").append(sanitize(reason))
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage()))
                    .append('\n');
        }
    }

    private static StartPidResult tryNativeFreezePid(FreezeSession session, PidInfo p, int timeoutMs, StringBuilder out) {
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) return null;
        long startMs = System.currentTimeMillis();
        StartPidResult result = new StartPidResult();
        try {
            NativeRun run = runNativeCommand(helper, new String[] {"freeze-pid", String.valueOf(p.pid), String.valueOf(timeoutMs)}, "FREEZE " + p.pid + " " + timeoutMs, timeoutMs + 1200);
            out.append("CGROUP_FREEZE_NATIVE_HELPER_FREEZE pid=").append(p.pid)
                    .append(" helper=").append(sanitize(helper))
                    .append(" viaDaemon=").append(run.viaDaemon)
                    .append(" exit=").append(run.exitCode)
                    .append(" timedOut=").append(run.timedOut)
                    .append(" elapsedMs=").append(System.currentTimeMillis() - startMs)
                    .append(" output=").append(sanitize(run.output))
                    .append('\n');
            if (run.timedOut || run.exitCode != 0 || !containsToken(run.output, "ok=true")) {
                result.reason = "native_helper_failed";
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



    static synchronized String ensureNativeDaemonForBatch(String reason) {
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
                daemonCacheOk = Boolean.TRUE;
                daemonCacheAt = System.currentTimeMillis();
            }
        } catch (Throwable t) {
            helloBeforeOutput = t.getClass().getSimpleName() + ":" + t.getMessage();
        }
        boolean ok = helloBefore;
        boolean started = false;
        String caps = "";
        if (!ok) {
            daemonCacheOk = null;
            daemonCacheAt = 0L;
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
                .append(" version=").append(VERSION)
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
        return out.toString();
    }

    static synchronized String killPackage(int userId, String packageName, int eventPid,
                                           int timeoutMs, String owner) {
        long startMs = System.currentTimeMillis();
        String pkg = safePackage(packageName);
        int safeEventPid = eventPid > 0 ? eventPid : -1;
        int safeTimeoutMs = clamp(timeoutMs, 100, 3000, 700);
        String safeOwner = safeWord(owner == null || owner.trim().isEmpty() ? "native-kill" : owner.trim());
        StringBuilder out = new StringBuilder(8192);
        out.append("CGROUP_NATIVE_KILL_BEGIN version=").append(VERSION)
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

    private static String findNativeHelper() {
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


    private static NativeRun runNativeCommand(String helper, String[] helperArgs, String daemonCommand, int timeoutMs) throws Exception {
        if (ensureNativeDaemon()) {
            try {
                NativeRun daemonRun = runNativeDaemonCommand(daemonCommand, timeoutMs);
                if (!daemonRun.timedOut && daemonRun.exitCode == 0 && daemonRun.output != null && daemonRun.output.trim().length() > 0) {
                    daemonRun.viaDaemon = true;
                    return daemonRun;
                }
            } catch (Throwable ignored) {
                daemonCacheOk = Boolean.FALSE;
                daemonCacheAt = System.currentTimeMillis();
            }
        }
        return runNativeHelper(helper, helperArgs, timeoutMs);
    }

    static boolean ensureNativeDaemon() {
        long now = System.currentTimeMillis();
        if (daemonCacheOk != null && Boolean.TRUE.equals(daemonCacheOk) && batchDaemonPinned) {
            return true;
        }
        if (daemonCacheOk != null && now - daemonCacheAt >= 0 && now - daemonCacheAt < DAEMON_CACHE_TTL_MS) {
            return Boolean.TRUE.equals(daemonCacheOk);
        }
        try {
            NativeRun hello = runNativeDaemonCommand("HELLO", 600);
            if (!hello.timedOut && hello.output.contains("CGFREEZER_DAEMON_HELLO ok=true")) {
                daemonCacheOk = Boolean.TRUE;
                daemonCacheAt = now;
                return true;
            }
        } catch (Throwable ignored) {}
        String helper = findNativeHelper();
        if (helper == null || helper.isEmpty()) {
            daemonCacheOk = Boolean.FALSE;
            daemonCacheAt = now;
            return false;
        }
        try {
            ProcessBuilder pb = new ProcessBuilder(helper, "daemon", DAEMON_SOCKET);
            pb.redirectErrorStream(true);
            daemonProcess = pb.start();
            // Drain daemon stdout/stderr so its pipe does not block.
            Thread drainer = new Thread(() -> {
                try (InputStream in = daemonProcess.getInputStream()) {
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
                        daemonCacheOk = Boolean.TRUE;
                        daemonCacheAt = System.currentTimeMillis();
                        return true;
                    }
                } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {}
        daemonCacheOk = Boolean.FALSE;
        daemonCacheAt = System.currentTimeMillis();
        return false;
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


    private static StopStats restoreSession(FreezeSession session, int timeoutMs, StringBuilder out, String tagPrefix) {
        StopStats stats = new StopStats();
        for (FreezeEntry e : session.entries) {
            boolean v1Entry = isV1FreezerPath(e.path);
            File f = new File(e.path == null ? "" : e.path);
            if (!v1Entry && !f.exists()) {
                stats.missingPath++;
                out.append(tagPrefix).append("_RESTORE_PATH_MISSING pid=").append(e.pid)
                        .append(" path=").append(sanitize(e.path))
                        .append(" original=").append(sanitize(e.originalFreeze))
                        .append(" ok=true reason=process_gone\n");
                continue;
            }
            try {
                String target = "1".equals(e.originalFreeze) ? "1" : "0";
                Boolean nativeOk = tryNativeRestorePath(e, target, timeoutMs, out, tagPrefix);
                if (Boolean.TRUE.equals(nativeOk)) {
                    stats.restored++;
                    continue;
                }
                if (v1Entry) {
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
        return "CGROUP_FREEZE_" + stage + "_DONE ok=" + ok
                + " token=" + token
                + " checked=" + checked
                + " frozenCount=" + frozen
                + " skipped=" + skipped
                + " reason=" + sanitize(reason)
                + " elapsedMs=" + (System.currentTimeMillis() - startMs) + "\n";
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
        return findPackagePidsJava(pkg);
    }

    private static List<PidInfo> findPackagePidsJava(String pkg) {
        List<PidInfo> result = new ArrayList<>();
        File[] entries = new File("/proc").listFiles();
        if (entries == null) return result;
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
            result.add(info);
        }
        return result;
    }
    private static PidInfo explicitPidInfo(String pkg, int userId, int pid, StringBuilder out) {
        String cmdline = readProcCmdline(pid);
        int uid = readStatusUid(pid);
        boolean userOk = uid < 0 || userIdFromUid(uid) == userId;
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
            return parsed == null ? null : parsed;
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
            }
            return true;
        } catch (Throwable t) {
            out.append("CGROUP_FREEZE_STATE_WRITE_FAILED token=").append(session.token)
                    .append(" error=").append(sanitize(t.getClass().getSimpleName() + ":" + t.getMessage())).append('\n');
            return false;
        }
    }

    private static FreezeSession readPersistentSession(int token) {
        List<FreezeSession> all = readAllPersistentSessions();
        for (FreezeSession s : all) if (s.token == token) return s;
        return null;
    }

    private static List<Integer> readAllPersistentTokens() {
        List<FreezeSession> sessions = readAllPersistentSessions();
        List<Integer> tokens = new ArrayList<>();
        for (FreezeSession s : sessions) tokens.add(s.token);
        return tokens;
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
        Map<Integer, FreezeSession> map = new HashMap<>();
        File state = new File(STATE_FILE);
        if (!state.exists()) return new ArrayList<>();
        try {
            String raw = readFileTrim(state, 1024 * 1024);
            String[] lines = raw.split("\\n");
            for (String line : lines) {
                FreezeEntry e = decodeEntry(line);
                if (e == null) continue;
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
        } catch (Throwable ignored) {
        }
        return new ArrayList<>(map.values());
    }

    private static boolean removePersistentToken(int token) {
        File state = new File(STATE_FILE);
        if (!state.exists()) return true;
        File tmp = new File(STATE_FILE + ".tmp." + android.os.Process.myPid() + "." + System.currentTimeMillis());
        boolean wrote = false;
        try {
            String raw = readFileTrim(state, 1024 * 1024);
            try (FileOutputStream fos = new FileOutputStream(tmp, false)) {
                String[] lines = raw.split("\\n");
                for (String line : lines) {
                    FreezeEntry e = decodeEntry(line);
                    if (e == null || e.token == token) continue;
                    fos.write(line.getBytes());
                    fos.write('\n');
                    wrote = true;
                }
                fos.flush();
            }
            if (wrote) {
                if (!tmp.renameTo(state)) {
                    copyFile(tmp, state);
                    tmp.delete();
                }
            } else {
                state.delete();
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
                + safeWord(e.originalFrozen) + "\t" + encodeField(e.path) + "\t" + encodeField(e.processName);
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

    private static void copyFile(File src, File dst) throws Exception {
        try (FileInputStream in = new FileInputStream(src); FileOutputStream out = new FileOutputStream(dst, false)) {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
            out.flush();
        }
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
        } catch (Throwable ignored) {
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
        String owner;
    }

    private static final class NativePackageFreezeResult {
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
