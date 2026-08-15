package com.xayah.dex;

import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicInteger;

import dev.rikka.tools.refine.Refine;

/**
 * Per-UID network block used as a high-risk app backup guard.
 *
 * Default provider is netpolicy Binder (INetworkPolicyManager.setUidPolicy / addUidPolicy),
 * not shell iptables. Optional netd provider is available for diagnostics/hard mode, but is
 * not used by tools by default because it has stronger system firewall side effects.
 */
final class UidNetworkBlockUtil {
    static final String VERSION = "v1.0-r121-uid-netblock-direct";
    private static final SimpleDateFormat TS = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);
    private static final long PROCESS_START_MS = System.currentTimeMillis();
    private static final String PROCESS_SESSION_ID = android.os.Process.myPid() + "-" + PROCESS_START_MS;
    private static final AtomicInteger NEXT_TOKEN = new AtomicInteger(tokenSeed());
    private static final Map<Integer, NetBlockSession> SESSIONS = new HashMap<>();
    private static final String STATE_DIR = "/data/local/tmp/.speedbackup_uid_netblock_state";
    private static final long STATE_TTL_MS = 24L * 60L * 60L * 1000L;

    private UidNetworkBlockUtil() {}

    static synchronized String start(int userId, String packageName, String mode, String logPath) {
        return start(userId, packageName, mode, logPath, -1, "direct");
    }

    static synchronized String start(int userId, String packageName, String mode, String logPath, int ownerToken, String ownerKind) {
        int token = NEXT_TOKEN.incrementAndGet();
        NetBlockSession session = new NetBlockSession(token, userId, safePackage(packageName), normalizeMode(mode), logPath);
        session.ownerToken = ownerToken;
        session.ownerKind = ownerKind == null ? "" : ownerKind.trim();
        try {
            session.apply();
            SESSIONS.put(token, session);
            return "UID_NET_BLOCK_START_OK token=" + token
                    + " user=" + userId
                    + " package=" + session.packageName
                    + " uid=" + session.uid
                    + " mode=" + session.mode
                    + " provider=" + sanitize(session.provider)
                    + " ownerToken=" + ownerToken
                    + " ownerKind=" + sanitize(session.ownerKind)
                    + " log=" + sanitize(logPath) + "\n";
        } catch (Throwable t) {
            try { session.restore("start-failed"); } catch (Throwable ignored) {}
            return "UID_NET_BLOCK_START_FAILED token=" + token
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
        NetBlockSession session = SESSIONS.remove(token);
        if (session == null) {
            return "UID_NET_BLOCK_STOP_MISSING token=" + token
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName) + "\n"
                    + restorePersistedToken(token, "stop-missing-" + token, expectedUserId, expectedPackageName);
        }
        return session.restore("stop-token-" + token);
    }

    static synchronized String status() {
        StringBuilder out = new StringBuilder();
        out.append("UID_NET_BLOCK_STATUS version=").append(VERSION)
                .append(" sessions=").append(SESSIONS.size())
                .append(" persistentStates=").append(countPersistentStates()).append('\n');
        for (NetBlockSession s : SESSIONS.values()) {
            out.append("UID_NET_BLOCK_SESSION token=").append(s.token)
                    .append(" user=").append(s.userId)
                    .append(" package=").append(s.packageName)
                    .append(" uid=").append(s.uid)
                    .append(" mode=").append(s.mode)
                    .append(" provider=").append(s.provider)
                    .append(" applied=").append(s.applied)
                    .append(" restored=").append(s.restored).append('\n');
        }
        return out.toString();
    }

    static synchronized String restorePersistedToken(int token, String reason, int expectedUserId, String expectedPackageName) {
        File file = findStateByToken(token, expectedUserId, expectedPackageName);
        if (file == null) {
            return "UID_NET_BLOCK_PERSISTENT_RESTORE_MISSING token=" + token
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName)
                    + " reason=" + sanitize(reason) + "\n";
        }
        return restorePersistedFile(file, reason, "token", token, expectedUserId, safePackage(expectedPackageName));
    }

    static synchronized String restorePersistedPackage(int userId, String packageName, String reason) {
        String pkg = safePackage(packageName);
        File file = findStateByPackage(userId, pkg);
        if (file == null) {
            return "UID_NET_BLOCK_PERSISTENT_RESTORE_MISSING user=" + userId
                    + " package=" + pkg
                    + " reason=" + sanitize(reason) + "\n";
        }
        return restorePersistedFile(file, reason, "package", -1, userId, pkg);
    }

    static synchronized String restorePersistedAll(String reason) {
        StringBuilder out = new StringBuilder();
        File[] files = stateDir().listFiles();
        int total = 0;
        int restored = 0;
        if (files != null) {
            for (File f : files) {
                if (!isStateFile(f)) continue;
                total++;
                String r = restorePersistedFile(f, reason, "all", -1, -1, "");
                out.append(r);
                if (restoreDoneAndStateDeleted(r)) restored++;
            }
        }
        out.append("UID_NET_BLOCK_PERSISTENT_RESTORE_ALL_DONE total=").append(total)
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
        out.append("UID_NET_BLOCK_PERSISTENT_CLEANUP_BEGIN reason=").append(sanitize(reason))
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
                out.append("UID_NET_BLOCK_PERSISTENT_CLEANUP_STALE path=").append(sanitize(f.getAbsolutePath()))
                        .append(" ageMs=").append(ageMs)
                        .append(" token=").append(sanitize(p.getProperty("token", "")))
                        .append(" user=").append(sanitize(p.getProperty("user", "")))
                        .append(" package=").append(sanitize(p.getProperty("package", "")))
                        .append(" uid=").append(sanitize(p.getProperty("uid", ""))).append('\n');
                String r = restorePersistedFile(f, "stale-cleanup-" + sanitize(reason), "stale-cleanup", -1, -1, "");
                out.append(r);
                if (restoreDoneAndStateDeleted(r)) restored++;
                boolean del = !f.exists() || f.delete();
                if (del) deleted++;
                out.append("UID_NET_BLOCK_PERSISTENT_CLEANUP_DELETE path=").append(sanitize(f.getAbsolutePath()))
                        .append(" deleted=").append(del)
                        .append(" restoreDone=").append(restoreDoneAndStateDeleted(r))
                        .append(" reason=").append(sanitize(reason)).append('\n');
            }
        }
        out.append("UID_NET_BLOCK_PERSISTENT_CLEANUP_DONE total=").append(total)
                .append(" stale=").append(stale)
                .append(" restored=").append(restored)
                .append(" deleted=").append(deleted)
                .append(" reason=").append(sanitize(reason)).append('\n');
        return out.toString();
    }

    static synchronized String probe(int userId, String packageName) {
        String pkg = safePackage(packageName);
        StringBuilder out = new StringBuilder();
        out.append("UID_NET_BLOCK_PROBE_BEGIN version=").append(VERSION)
                .append(" user=").append(userId)
                .append(" package=").append(pkg).append('\n');
        int uid = -1;
        try {
            uid = resolveUid(userId, pkg);
            out.append("UID_NET_BLOCK_PROBE type=uid ok=true uid=").append(uid).append('\n');
        } catch (Throwable t) {
            out.append("UID_NET_BLOCK_PROBE type=uid ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
        try {
            Object service = netPolicyService();
            Object p = HiddenApiReflection.invokeFlexible(service, "getUidPolicy", uid);
            int policy = asInt(p, 0);
            out.append("UID_NET_BLOCK_PROBE type=netpolicy method=getUidPolicy ok=true policy=").append(policy)
                    .append(" rejectMetered=").append(policyRejectMeteredBackground()).append('\n');
            boolean add = hasMethod(service, "addUidPolicy", Integer.valueOf(uid), Integer.valueOf(policyRejectMeteredBackground()));
            boolean set = hasMethod(service, "setUidPolicy", Integer.valueOf(uid), Integer.valueOf(policy));
            out.append("UID_NET_BLOCK_PROBE type=netpolicy method=addUidPolicy ok=").append(add).append('\n');
            out.append("UID_NET_BLOCK_PROBE type=netpolicy method=setUidPolicy ok=").append(set).append('\n');
        } catch (Throwable t) {
            out.append("UID_NET_BLOCK_PROBE type=netpolicy ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
        try {
            Object service = netdService();
            boolean add = hasMethod(service, "bandwidthAddNaughtyApp", Integer.valueOf(uid));
            boolean remove = hasMethod(service, "bandwidthRemoveNaughtyApp", Integer.valueOf(uid));
            out.append("UID_NET_BLOCK_PROBE type=netd method=bandwidthAddNaughtyApp ok=").append(add).append('\n');
            out.append("UID_NET_BLOCK_PROBE type=netd method=bandwidthRemoveNaughtyApp ok=").append(remove).append('\n');
        } catch (Throwable t) {
            out.append("UID_NET_BLOCK_PROBE type=netd ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
        out.append("UID_NET_BLOCK_PROBE_DONE user=").append(userId).append(" package=").append(pkg).append(" uid=").append(uid).append('\n');
        return out.toString();
    }

    private static final class NetBlockSession {
        final int token;
        final int userId;
        final String packageName;
        final String mode;
        final String logPath;
        int ownerToken = -1;
        String ownerKind = "";
        int uid = -1;
        int originalUidPolicy = 0;
        int targetPolicy = 0;
        String provider = "none";
        boolean policyTouched = false;
        boolean netdTouched = false;
        boolean applied = false;
        boolean restored = false;
        int restoreAttempts = 0;
        PrintWriter log;

        NetBlockSession(int token, int userId, String packageName, String mode, String logPath) {
            this.token = token;
            this.userId = userId;
            this.packageName = packageName;
            this.mode = mode;
            this.logPath = logPath == null ? "-" : logPath;
        }

        void apply() throws Exception {
            openLog();
            uid = resolveUid(userId, packageName);
            logLine("UID_NET_BLOCK_START schema=speedbackup.uid_net_block.v1 version=" + VERSION
                    + " user=" + userId + " package=" + packageName + " uid=" + uid
                    + " mode=" + mode + " token=" + token + " ownerToken=" + ownerToken
                    + " ownerKind=" + sanitize(ownerKind));
            originalUidPolicy = snapshotUidPolicy();
            targetPolicy = selectTargetPolicy(mode);
            persistState("snapshot");
            boolean ok = false;
            String m = mode;
            if ("none".equals(m) || "off".equals(m) || "disable".equals(m)) {
                ok = true;
                provider = "none";
            } else if ("netd".equals(m) || "naughty".equals(m)) {
                ok = applyNetdNaughty();
            } else {
                ok = applyNetPolicy();
                if (!ok && ("auto".equals(m) || "hard".equals(m))) {
                    ok = applyNetdNaughty();
                }
            }
            if (!ok) throw new IllegalStateException("uid-net-block-apply-failed provider=" + provider);
            applied = true;
            persistState("apply-done");
            logLine("UID_NET_BLOCK_APPLY_DONE token=" + token
                    + " user=" + userId + " package=" + packageName + " uid=" + uid
                    + " mode=" + mode + " provider=" + provider
                    + " policyTouched=" + policyTouched + " netdTouched=" + netdTouched);
        }

        private boolean applyNetPolicy() {
            try {
                Object service = netPolicyService();
                int next = originalUidPolicy | targetPolicy;
                try {
                    HiddenApiReflection.invokeFlexible(service, "addUidPolicy", uid, targetPolicy);
                    provider = "direct-netpolicy-addUidPolicy";
                } catch (Throwable addError) {
                    HiddenApiReflection.invokeFlexible(service, "setUidPolicy", uid, next);
                    provider = "direct-netpolicy-setUidPolicy addError=" + addError.getClass().getSimpleName();
                }
                int verify = snapshotUidPolicy();
                boolean ok = (verify & targetPolicy) == targetPolicy;
                policyTouched = ok;
                logLine("UID_NET_BLOCK_APPLY stage=netpolicy targetPolicy=" + targetPolicy
                        + " originalPolicy=" + originalUidPolicy
                        + " verifyPolicy=" + verify
                        + " ok=" + ok + " provider=" + provider);
                persistState("apply-netpolicy");
                return ok;
            } catch (Throwable t) {
                provider = "direct-netpolicy-failed";
                logLine("UID_NET_BLOCK_APPLY stage=netpolicy ok=false exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage()));
                return false;
            }
        }

        private boolean applyNetdNaughty() {
            try {
                Object service = netdService();
                HiddenApiReflection.invokeFlexible(service, "bandwidthAddNaughtyApp", uid);
                provider = "direct-netd-bandwidthAddNaughtyApp";
                netdTouched = true;
                logLine("UID_NET_BLOCK_APPLY stage=netd method=bandwidthAddNaughtyApp ok=true uid=" + uid);
                persistState("apply-netd");
                return true;
            } catch (Throwable t) {
                provider = "direct-netd-failed";
                logLine("UID_NET_BLOCK_APPLY stage=netd method=bandwidthAddNaughtyApp ok=false exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage()));
                return false;
            }
        }

        String restore(String reason) {
            StringBuilder out = new StringBuilder();
            openLog();
            restoreAttempts++;
            persistState("restore-attempt-" + restoreAttempts);
            boolean policyOk = true;
            boolean netdOk = true;
            logLine("UID_NET_BLOCK_RESTORE_BEGIN token=" + token + " reason=" + sanitize(reason)
                    + " user=" + userId + " package=" + packageName + " uid=" + uid
                    + " mode=" + mode + " provider=" + provider + " restoreAttempts=" + restoreAttempts);
            if (netdTouched) {
                try {
                    Object service = netdService();
                    HiddenApiReflection.invokeFlexible(service, "bandwidthRemoveNaughtyApp", uid);
                    logLine("UID_NET_BLOCK_RESTORE stage=netd method=bandwidthRemoveNaughtyApp ok=true uid=" + uid);
                } catch (Throwable t) {
                    netdOk = false;
                    logLine("UID_NET_BLOCK_RESTORE stage=netd method=bandwidthRemoveNaughtyApp ok=false exception=" + sanitize(t.getClass().getName())
                            + " message=" + sanitize(t.getMessage()));
                }
            } else {
                logLine("UID_NET_BLOCK_RESTORE stage=netd skipped=true touched=false");
            }
            if (policyTouched) {
                try {
                    Object service = netPolicyService();
                    HiddenApiReflection.invokeFlexible(service, "setUidPolicy", uid, originalUidPolicy);
                    int verify = snapshotUidPolicy();
                    policyOk = verify == originalUidPolicy;
                    logLine("UID_NET_BLOCK_RESTORE stage=netpolicy targetPolicy=" + originalUidPolicy
                            + " verifyPolicy=" + verify + " ok=" + policyOk + " provider=direct-netpolicy-setUidPolicy");
                } catch (Throwable t) {
                    policyOk = false;
                    logLine("UID_NET_BLOCK_RESTORE stage=netpolicy targetPolicy=" + originalUidPolicy
                            + " ok=false exception=" + sanitize(t.getClass().getName())
                            + " message=" + sanitize(t.getMessage()));
                }
            } else {
                logLine("UID_NET_BLOCK_RESTORE stage=netpolicy skipped=true touched=false");
            }
            boolean restoreOk = policyOk && netdOk;
            boolean stateDeleted = false;
            if (restoreOk) {
                persistState("restore-ok-before-delete");
                stateDeleted = deletePersistedState("restore-done");
            } else {
                persistState("restore-failed-retained");
            }
            restored = restoreOk && stateDeleted;
            if (restored) {
                logLine("UID_NET_BLOCK_RESTORE_DONE token=" + token + " user=" + userId + " package=" + packageName
                        + " uid=" + uid + " restoreOk=true stateDeleted=true policyRestored=" + policyOk + " netdRestored=" + netdOk);
                out.append("UID_NET_BLOCK_STOP_OK token=").append(token)
                        .append(" user=").append(userId)
                        .append(" package=").append(packageName)
                        .append(" uid=").append(uid)
                        .append(" mode=").append(mode)
                        .append(" provider=").append(sanitize(provider))
                        .append(" restoreOk=true stateDeleted=true\n");
            } else {
                logLine("UID_NET_BLOCK_RESTORE_FAILED token=" + token + " user=" + userId + " package=" + packageName
                        + " uid=" + uid + " restoreOk=" + restoreOk + " stateDeleted=" + stateDeleted
                        + " policyRestored=" + policyOk + " netdRestored=" + netdOk + " stateRetained=true");
                out.append("UID_NET_BLOCK_STOP_FAILED token=").append(token)
                        .append(" user=").append(userId)
                        .append(" package=").append(packageName)
                        .append(" uid=").append(uid)
                        .append(" mode=").append(mode)
                        .append(" provider=").append(sanitize(provider))
                        .append(" restoreOk=").append(restoreOk)
                        .append(" stateDeleted=").append(stateDeleted)
                        .append(" stateRetained=true\n");
            }
            closeLog();
            return out.toString();
        }

        private int snapshotUidPolicy() throws Exception {
            Object service = netPolicyService();
            Object v = HiddenApiReflection.invokeFlexible(service, "getUidPolicy", uid);
            return asInt(v, 0);
        }

        private void persistState(String phase) {
            try {
                File file = stateFileFor(this);
                Properties p = new Properties();
                p.setProperty("schema", "speedbackup.uid_net_block.persistent.v1");
                p.setProperty("version", VERSION);
                p.setProperty("createdAt", String.valueOf(PROCESS_START_MS));
                p.setProperty("processPid", String.valueOf(android.os.Process.myPid()));
                p.setProperty("processSessionId", PROCESS_SESSION_ID);
                p.setProperty("token", String.valueOf(token));
                p.setProperty("ownerToken", String.valueOf(ownerToken));
                p.setProperty("ownerKind", ownerKind == null ? "" : ownerKind);
                p.setProperty("user", String.valueOf(userId));
                p.setProperty("package", packageName);
                p.setProperty("uid", String.valueOf(uid));
                p.setProperty("mode", mode);
                p.setProperty("provider", provider == null ? "" : provider);
                p.setProperty("logPath", logPath == null ? "" : logPath);
                p.setProperty("originalUidPolicy", String.valueOf(originalUidPolicy));
                p.setProperty("targetPolicy", String.valueOf(targetPolicy));
                p.setProperty("policyTouched", String.valueOf(policyTouched));
                p.setProperty("netdTouched", String.valueOf(netdTouched));
                p.setProperty("applied", String.valueOf(applied));
                p.setProperty("restored", String.valueOf(restored));
                p.setProperty("restoreAttempts", String.valueOf(restoreAttempts));
                p.setProperty("phase", phase == null ? "" : phase);
                p.setProperty("updatedAt", String.valueOf(System.currentTimeMillis()));
                writePropertiesAtomic(file, p);
                logLine("UID_NET_BLOCK_PERSIST_STATE token=" + token
                        + " phase=" + sanitize(phase)
                        + " path=" + sanitize(file.getAbsolutePath()));
            } catch (Throwable t) {
                logLine("UID_NET_BLOCK_PERSIST_STATE_FAILED token=" + token
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
                logLine("UID_NET_BLOCK_PERSIST_DELETE token=" + token
                        + " reason=" + sanitize(reason)
                        + " existedBefore=" + existedBefore
                        + " deleted=" + deleted
                        + " path=" + sanitize(file.getAbsolutePath()));
                return deleted;
            } catch (Throwable t) {
                logLine("UID_NET_BLOCK_PERSIST_DELETE_FAILED token=" + token
                        + " reason=" + sanitize(reason)
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage())
                        + " deleted=false");
                return false;
            }
        }

        private void openLog() {
            if (log != null) return;
            try {
                if (logPath == null || logPath.isEmpty() || "-".equals(logPath)) return;
                File f = new File(logPath);
                File parent = f.getParentFile();
                if (parent != null && !parent.isDirectory()) parent.mkdirs();
                log = new PrintWriter(new OutputStreamWriter(new FileOutputStream(f, true), StandardCharsets.UTF_8), true);
            } catch (Throwable ignored) {
                log = null;
            }
        }

        private void closeLog() {
            if (log != null) {
                try { log.flush(); log.close(); } catch (Throwable ignored) {}
                log = null;
            }
        }

        private void logLine(String line) {
            String out = now() + " " + line;
            if (log != null) {
                log.println(out);
                log.flush();
            } else {
                System.out.println(out);
            }
        }
    }

    private static String restorePersistedFile(File file, String reason, String source, int token, int userId, String packageName) {
        StringBuilder out = new StringBuilder();
        Properties p = readProperties(file);
        if (p.isEmpty()) {
            return "UID_NET_BLOCK_PERSISTENT_RESTORE_FAILED source=" + sanitize(source)
                    + " reason=" + sanitize(reason)
                    + " path=" + sanitize(file == null ? "" : file.getAbsolutePath())
                    + " message=empty-state\n";
        }
        NetBlockSession s = sessionFromProperties(p);
        String mismatch = expectedMismatch(s, userId, packageName);
        if (!mismatch.isEmpty()) {
            return "UID_NET_BLOCK_PERSISTENT_RESTORE_REJECTED source=" + sanitize(source)
                    + " reason=" + sanitize(reason)
                    + " token=" + s.token
                    + " stateUser=" + s.userId
                    + " statePackage=" + s.packageName
                    + " expectedUser=" + userId
                    + " expectedPackage=" + sanitize(packageName)
                    + " mismatch=" + sanitize(mismatch)
                    + " stateRetained=true"
                    + " path=" + sanitize(file.getAbsolutePath()) + "\n";
        }
        out.append("UID_NET_BLOCK_PERSISTENT_RESTORE_BEGIN source=").append(sanitize(source))
                .append(" reason=").append(sanitize(reason))
                .append(" token=").append(s.token)
                .append(" user=").append(s.userId)
                .append(" package=").append(s.packageName)
                .append(" uid=").append(s.uid)
                .append(" mode=").append(s.mode)
                .append(" provider=").append(sanitize(s.provider))
                .append(" path=").append(sanitize(file.getAbsolutePath())).append('\n');
        try {
            String restoreOut = s.restore("persistent-" + reason);
            out.append(restoreOut);
            if (restoreDoneAndStateDeleted(restoreOut)) {
                out.append("UID_NET_BLOCK_PERSISTENT_RESTORE_DONE source=").append(sanitize(source))
                        .append(" token=").append(s.token)
                        .append(" user=").append(s.userId)
                        .append(" package=").append(s.packageName)
                        .append(" stateDeleted=true")
                        .append(" reason=").append(sanitize(reason)).append('\n');
            } else {
                out.append("UID_NET_BLOCK_PERSISTENT_RESTORE_FAILED source=").append(sanitize(source))
                        .append(" token=").append(s.token)
                        .append(" user=").append(s.userId)
                        .append(" package=").append(s.packageName)
                        .append(" reason=").append(sanitize(reason))
                        .append(" message=restore-step-failed stateRetained=true").append('\n');
            }
        } catch (Throwable t) {
            out.append("UID_NET_BLOCK_PERSISTENT_RESTORE_FAILED source=").append(sanitize(source))
                    .append(" token=").append(s.token)
                    .append(" exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage()))
                    .append(" stateRetained=true").append('\n');
        }
        return out.toString();
    }

    private static boolean restoreDoneAndStateDeleted(String raw) {
        return raw != null && raw.contains("UID_NET_BLOCK_STOP_OK") && raw.contains("stateDeleted=true");
    }

    private static NetBlockSession sessionFromProperties(Properties p) {
        int token = parseInt(p.getProperty("token"), -1);
        int userId = parseInt(p.getProperty("user"), 0);
        String pkg = safePackage(p.getProperty("package", ""));
        String mode = normalizeMode(p.getProperty("mode", "netpolicy"));
        String logPath = p.getProperty("logPath", "-");
        NetBlockSession s = new NetBlockSession(token, userId, pkg, mode, logPath);
        s.ownerToken = parseInt(p.getProperty("ownerToken"), -1);
        s.ownerKind = p.getProperty("ownerKind", "");
        s.uid = parseInt(p.getProperty("uid"), -1);
        s.originalUidPolicy = parseInt(p.getProperty("originalUidPolicy"), 0);
        s.targetPolicy = parseInt(p.getProperty("targetPolicy"), policyRejectMeteredBackground());
        s.provider = p.getProperty("provider", "persisted");
        s.policyTouched = Boolean.parseBoolean(p.getProperty("policyTouched", "false"));
        s.netdTouched = Boolean.parseBoolean(p.getProperty("netdTouched", "false"));
        s.applied = Boolean.parseBoolean(p.getProperty("applied", "true"));
        s.restoreAttempts = parseInt(p.getProperty("restoreAttempts"), 0);
        return s;
    }

    private static File stateDir() {
        File dir = new File(STATE_DIR);
        try { if (!dir.isDirectory()) dir.mkdirs(); } catch (Throwable ignored) {}
        return dir;
    }

    private static File stateFileFor(NetBlockSession s) {
        return new File(stateDir(), "unb" + s.token + "_u" + s.userId + "_uid" + s.uid + "_" + safeFilePart(s.packageName) + ".properties");
    }

    private static File findStateByToken(int token, int expectedUserId, String expectedPackageName) {
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
            if (best == null || t > bestTime) { best = f; bestTime = t; }
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

    private static String expectedMismatch(NetBlockSession s, int expectedUserId, String expectedPackageName) {
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
        int count = 0;
        for (File f : files) if (isStateFile(f)) count++;
        return count;
    }

    private static Properties readProperties(File file) {
        Properties p = new Properties();
        if (file == null || !file.isFile()) return p;
        try (FileInputStream in = new FileInputStream(file)) { p.load(in); } catch (Throwable ignored) {}
        return p;
    }

    private static void writePropertiesAtomic(File file, Properties props) throws Exception {
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory()) parent.mkdirs();
        File tmp = new File(file.getAbsolutePath() + ".tmp");
        try (FileOutputStream out = new FileOutputStream(tmp)) {
            props.store(out, "SpeedBackup UID net block state");
            out.flush();
            try { out.getFD().sync(); } catch (Throwable ignored) {}
        }
        if (!tmp.renameTo(file)) throw new IllegalStateException("rename failed: " + tmp + " -> " + file);
    }

    private static int resolveUid(int userId, String packageName) throws Exception {
        Context ctx = HiddenApiHelper.getContext();
        PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
        PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
        PackageInfo info = pmHidden.getPackageInfoAsUser(packageName, 0, userId);
        if (info == null || info.applicationInfo == null) throw new IllegalStateException("package-info-missing");
        return info.applicationInfo.uid;
    }

    private static Object netPolicyService() throws Exception {
        return HiddenApiServices.interfaceService("netpolicy", "android.net.INetworkPolicyManager$Stub");
    }

    private static Object netdService() throws Exception {
        return HiddenApiServices.interfaceService("netd", "android.net.INetd$Stub");
    }

    private static int policyRejectMeteredBackground() {
        return intField("android.net.NetworkPolicyManager", "POLICY_REJECT_METERED_BACKGROUND", 1);
    }

    private static int policyRejectAll() {
        return intField("android.net.NetworkPolicyManager", "POLICY_REJECT_ALL", -1);
    }

    private static int selectTargetPolicy(String mode) {
        String m = normalizeMode(mode);
        if ("all".equals(m) || "reject-all".equals(m)) {
            int v = policyRejectAll();
            if (v > 0) return v;
        }
        return policyRejectMeteredBackground();
    }

    private static int intField(String className, String fieldName, int fallback) {
        try {
            Class<?> clazz = HiddenApiReflection.classForNameCached(className);
            Object v = HiddenApiReflection.fieldValue(clazz, fieldName, fallback);
            return v instanceof Integer ? ((Integer) v).intValue() : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static boolean hasMethod(Object target, String method, Object... args) {
        if (target == null || method == null) return false;
        Class<?> clazz = target instanceof Class<?> ? (Class<?>) target : target.getClass();
        int argc = args == null ? 0 : args.length;
        for (java.lang.reflect.Method m : clazz.getMethods()) {
            if (method.equals(m.getName()) && m.getParameterTypes().length == argc) return true;
        }
        for (java.lang.reflect.Method m : clazz.getDeclaredMethods()) {
            if (method.equals(m.getName()) && m.getParameterTypes().length == argc) return true;
        }
        return false;
    }

    private static int asInt(Object v, int fallback) {
        if (v instanceof Integer) return ((Integer) v).intValue();
        if (v instanceof Number) return ((Number) v).intValue();
        return fallback;
    }

    private static String normalizeMode(String mode) {
        String m = mode == null ? "" : mode.trim().toLowerCase(Locale.ROOT);
        if (m.isEmpty()) return "netpolicy";
        if (m.equals("metered") || m.equals("policy") || m.equals("networkpolicy")) return "netpolicy";
        if (m.equals("naughty") || m.equals("bandwidth")) return "netd";
        if (m.equals("off") || m.equals("none") || m.equals("disable")) return m;
        if (m.equals("hard") || m.equals("auto") || m.equals("netd") || m.equals("netpolicy") || m.equals("all") || m.equals("reject-all")) return m;
        return "netpolicy";
    }

    private static String safePackage(String pkg) {
        String p = pkg == null ? "" : pkg.trim();
        if (p.length() > 255) p = p.substring(0, 255);
        return p;
    }

    private static String safeFilePart(String raw) {
        String s = safePackage(raw).replaceAll("[^A-Za-z0-9._-]", "_");
        return s.isEmpty() ? "unknown" : s;
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        return raw.replace('\n', '|').replace('\r', '|').replace('\t', ' ').trim();
    }

    private static int parseInt(String raw, int fallback) {
        try { return Integer.parseInt(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static long parseLong(String raw, long fallback) {
        try { return Long.parseLong(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static int tokenSeed() {
        long now = System.currentTimeMillis();
        int pid = android.os.Process.myPid() & 0x3FF;
        long seed = (Math.abs(now % 100000L) * 1000L) + pid;
        if (seed > Integer.MAX_VALUE - 100000L) seed = seed % 1000000000L;
        return (int) Math.max(3000L, seed);
    }

    private static String now() {
        try { return TS.format(new Date()); } catch (Throwable ignored) { return String.valueOf(System.currentTimeMillis()); }
    }
}
