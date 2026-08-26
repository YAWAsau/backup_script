package com.xayah.dex;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.app.ActivityManager;
import android.app.AppOpsManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.Build;
import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.UserHandleHidden;
import android.os.Parcel;
import android.system.Os;
import android.system.OsConstants;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.xayah.dex.compat.ActivityCompat;
import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;

import dev.rikka.tools.refine.Refine;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.lang.reflect.Proxy;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * SpeedBackup process observer test utility.
 *
 * This is a true event-driven ActivityManager Binder callback path. It does not
 * poll /proc and does not run a sleep loop. The only blocking wait is the caller
 * waiting for the requested test duration while Binder callbacks arrive.
 */
final class ProcessObserverUtil {
    static final String VERSION = "v3.17-r432-restore-session-facts-argv-compilefix";
    private static final String DESCRIPTOR = "android.app.IProcessObserver";
    private static final String TASK_STACK_DESCRIPTOR = "android.app.ITaskStackListener";
    private static final long ACTION_DEBOUNCE_MS = 900L;
    private static final SimpleDateFormat TS = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);
    private static final AtomicInteger NEXT_TOKEN = new AtomicInteger(tokenSeed());
    private static final Map<Integer, WatchSession> SESSIONS = new HashMap<>();
    private static final Object GLOBAL_LOCK = new Object();
    private static volatile Object GLOBAL_PROCESS_OBSERVER;
    private static volatile Object GLOBAL_TASK_STACK_LISTENER;
    private static volatile boolean GLOBAL_PROCESS_OBSERVER_REGISTERED = false;
    private static volatile boolean GLOBAL_TASK_STACK_REGISTERED = false;
    private static final AtomicInteger GLOBAL_PROCESS_EVENTS = new AtomicInteger(0);
    private static final AtomicInteger GLOBAL_TASK_EVENTS = new AtomicInteger(0);
    private static final String BATCH_STATE_DIR = "/data/local/tmp/.speedbackup_process_observer_batch_state";
    private static final long BATCH_STATE_TTL_MS = 24L * 60L * 60L * 1000L;

    private static int tokenSeed() {
        long seed = (System.currentTimeMillis() % 100000L) * 1000L;
        seed += Math.abs(android.os.Process.myPid() % 1000);
        if (seed < 1000L) seed += 1000L;
        if (seed > Integer.MAX_VALUE - 10000L) seed = 1000L + Math.abs(android.os.Process.myPid() % 1000);
        return (int) seed;
    }

    private ProcessObserverUtil() {}

    static String watchBlocking(int userId, String packageName, long durationMs, String action, String logPath) {
        int token = NEXT_TOKEN.incrementAndGet();
        WatchSession session = null;
        try {
            session = new WatchSession(userId, safePackage(packageName), Math.max(1000L, durationMs), action, wakeBlockModeFromAction(action), logPath);
            session.token = token;
            synchronized (ProcessObserverUtil.class) {
                SESSIONS.put(token, session);
            }
            session.startTarget();
            session.await();
            synchronized (ProcessObserverUtil.class) {
                SESSIONS.remove(token);
            }
            return session.finish("timeout");
        } catch (Throwable t) {
            synchronized (ProcessObserverUtil.class) {
                SESSIONS.remove(token);
            }
            if (session != null) {
                try { return session.finish("error:" + t.getClass().getSimpleName() + ":" + sanitize(t.getMessage())); } catch (Throwable ignored) {}
            }
            return "PROCESS_OBSERVER_WATCH_FAILED exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage()) + "\n";
        }
    }


    static synchronized String startAsync(int userId, String packageName, String action, String logPath) {
        int token = NEXT_TOKEN.incrementAndGet();
        WatchSession session = null;
        try {
            session = new WatchSession(userId, safePackage(packageName), 0L, action, wakeBlockModeFromAction(action), logPath);
            session.token = token;
            SESSIONS.put(token, session);
            session.startTarget();
            return "PROCESS_OBSERVER_START_OK token=" + token
                    + " user=" + userId
                    + " package=" + safePackage(packageName)
                    + " action=" + normalizeAction(action)
                    + " wakeBlockMode=" + wakeBlockModeFromAction(action)
                    + " lifecycle=global-target"
                    + " log=" + sanitize(logPath) + "\n";
        } catch (Throwable t) {
            SESSIONS.remove(token);
            if (session != null) {
                try { session.finish("start-failed:" + t.getClass().getSimpleName()); } catch (Throwable ignored) {}
            }
            return "PROCESS_OBSERVER_START_FAILED exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage()) + "\n";
        }
    }

    static synchronized String stopAsync(int token) {
        return stopAsync(token, -1, "");
    }

    static synchronized String stopAsync(int token, int expectedUserId, String expectedPackageName) {
        WatchSession session = SESSIONS.remove(token);
        if (session == null) {
            return "PROCESS_OBSERVER_STOP_MISSING token=" + token
                    + " expectedUser=" + expectedUserId
                    + " expectedPackage=" + safePackage(expectedPackageName) + "\n"
                    + AppWakeBlockUtil.restorePersistedObserverToken(token, "process-observer-stop-missing-" + token, expectedUserId, expectedPackageName);
        }
        return session.finish("stop-token-" + token);
    }



    static synchronized String startRestoreSessionFromCompareMap(int userId, String compareMapPath, String pkgsOutPath,
                                                                 String policy, String logPath, String homePkg, String imePkg,
                                                                 String factsOutPath) {
        long t0 = System.currentTimeMillis();
        StringBuilder out = new StringBuilder();
        out.append(cleanupStaleBatchStates("restore-session-direct-start", BATCH_STATE_TTL_MS));
        File cmp = new File(compareMapPath == null ? "" : compareMapPath);
        if (!cmp.isFile()) {
            return "PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_START_FAILED reason=compare_map_missing path="
                    + sanitize(compareMapPath) + "\n" + out;
        }
        int requested = 0;
        int started = 0;
        int failed = 0;
        int factsRows = 0;
        HashSet<String> seen = new HashSet<>();
        String commonLogPath = (logPath == null || logPath.trim().isEmpty()) ? "-" : logPath.trim();
        RestoreSessionPolicyOptions opts = parseRestoreSessionPolicy(policy);
        String home = normalizeOptionalPackageArg(homePkg);
        String ime = normalizeOptionalPackageArg(imePkg);
        if (opts.defaultHomeEnabled && home.isEmpty()) home = resolveDefaultHomePackage(userId);
        if (opts.defaultImeEnabled && ime.isEmpty()) ime = resolveDefaultImePackage(userId);
        PrintWriter pkgsOut = null;
        PrintWriter factsOut = null;
        Context ctx = null;
        PackageManager realPm = null;
        PackageManagerHidden pmHidden = null;
        try {
            ctx = HiddenApiHelper.getContext();
            realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            pmHidden = Refine.unsafeCast(realPm);
        } catch (Throwable t) {
            out.append("PROCESS_OBSERVER_RESTORE_SESSION_FACTS_CONTEXT_FAILED exception=")
                    .append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
        try {
            if (pkgsOutPath != null && !pkgsOutPath.trim().isEmpty() && !"-".equals(pkgsOutPath.trim())) {
                File pkgsFile = new File(pkgsOutPath.trim());
                File parent = pkgsFile.getParentFile();
                if (parent != null) parent.mkdirs();
                pkgsOut = new PrintWriter(new OutputStreamWriter(new FileOutputStream(pkgsFile, false), StandardCharsets.UTF_8));
            }
            if (factsOutPath != null && !factsOutPath.trim().isEmpty() && !"-".equals(factsOutPath.trim())) {
                File factsFile = new File(factsOutPath.trim());
                File parent = factsFile.getParentFile();
                if (parent != null) parent.mkdirs();
                factsOut = new PrintWriter(new OutputStreamWriter(new FileOutputStream(factsFile, false), StandardCharsets.UTF_8));
                factsOut.println("#schema\tspeedbackup.restore_session_facts.v1");
                factsOut.println("#fields\tkind\trole\tpackage\tlabel\tuserId\tinstalled\tuid\taction\treason\tsource\tsystem\tversionCode\tsourceDir");
                factsRows += appendRestoreSessionFactRow(factsOut, realPm, pmHidden, userId, "META", "DEFAULT_HOME", home, home, "", "default-home", "AppStateEngine.defaultHome");
                factsRows += appendRestoreSessionFactRow(factsOut, realPm, pmHidden, userId, "META", "DEFAULT_IME", ime, ime, "", "default-ime", "AppStateEngine.defaultIme");
                factsRows += appendRestoreSessionRoleFacts(factsOut, ctx, realPm, pmHidden, userId);
            }
            HashMap<String, Integer> header = new HashMap<>();
            try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(cmp), StandardCharsets.UTF_8))) {
                String line;
                boolean headerSeen = false;
                while ((line = br.readLine()) != null) {
                    if (line.trim().isEmpty() || line.startsWith("#")) continue;
                    String[] parts = line.split("\t", -1);
                    if (!headerSeen) {
                        headerSeen = true;
                        for (int i = 0; i < parts.length; i++) header.put(parts[i].trim(), i);
                        if (header.containsKey("package") && header.containsKey("label")) continue;
                    }
                    int pkgIdx = header.containsKey("package") ? header.get("package") : 2;
                    int labelIdx = header.containsKey("label") ? header.get("label") : 1;
                    String pkg = pkgIdx >= 0 && pkgIdx < parts.length ? safePackage(parts[pkgIdx]) : "";
                    String label = labelIdx >= 0 && labelIdx < parts.length ? parts[labelIdx].trim() : pkg;
                    if (pkg.isEmpty() || !pkg.matches("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+")) continue;
                    if (!seen.add(pkg)) continue;
                    requested++;
                    if (isSpeedBackupSelfPackage(pkg)) {
                        out.append("PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_SKIP package=").append(pkg)
                                .append(" label=").append(sanitize(label)).append(" reason=self\n");
                        factsRows += appendRestoreSessionFactRow(factsOut, realPm, pmHidden, userId, "PKG", "RESTORE", pkg, label, "none", "skip:self", "compare-map");
                        continue;
                    }
                    if (label.isEmpty()) label = pkg;
                    RestoreSessionActionDecision decision = restoreSessionActionForPackage(pkg, opts, home, ime);
                    if (isDisabledAction(decision.action)) {
                        out.append("PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_SKIP package=").append(pkg)
                                .append(" label=").append(sanitize(label)).append(" reason=action_off action=").append(sanitize(decision.action)).append('\n');
                        factsRows += appendRestoreSessionFactRow(factsOut, realPm, pmHidden, userId, "PKG", "RESTORE", pkg, label, decision.action, "skip:" + decision.reason, "compare-map");
                        continue;
                    }
                    factsRows += appendRestoreSessionFactRow(factsOut, realPm, pmHidden, userId, "PKG", "RESTORE", pkg, label, decision.action, decision.reason, "compare-map");
                    int token = NEXT_TOKEN.incrementAndGet();
                    WatchSession session = null;
                    try {
                        session = new WatchSession(userId, pkg, 0L, decision.action, wakeBlockModeFromAction(decision.action), commonLogPath);
                        session.token = token;
                        SESSIONS.put(token, session);
                        session.startTarget();
                        boolean stateOk = persistBatchState(token, userId, pkg, label, decision.action, commonLogPath, "restore-session-direct-start:" + decision.reason);
                        started++;
                        if (pkgsOut != null) pkgsOut.println(pkg + "\t" + label + "\t" + decision.action + "\t" + decision.reason);
                        out.append("PROCESS_OBSERVER_BATCH_START_ITEM token=").append(token)
                                .append(" user=").append(userId)
                                .append(" package=").append(pkg)
                                .append(" label=").append(sanitize(label))
                                .append(" action=").append(decision.action)
                                .append(" actionReason=").append(sanitize(decision.reason))
                                .append(" wakeBlockMode=").append(wakeBlockModeFromAction(decision.action))
                                .append(" lifecycle=batch-watchset")
                                .append(" persistentState=").append(stateOk)
                                .append(" log=").append(sanitize(commonLogPath)).append('\n');
                    } catch (Throwable t) {
                        failed++;
                        SESSIONS.remove(token);
                        deleteBatchState(token);
                        if (session != null) {
                            try { session.finish("restore-session-direct-start-failed:" + t.getClass().getSimpleName()); } catch (Throwable ignored) {}
                        }
                        out.append("PROCESS_OBSERVER_BATCH_START_ITEM_FAILED index=").append(requested)
                                .append(" package=").append(pkg)
                                .append(" label=").append(sanitize(label))
                                .append(" action=").append(sanitize(decision.action))
                                .append(" actionReason=").append(sanitize(decision.reason))
                                .append(" exception=").append(sanitize(t.getClass().getName()))
                                .append(" message=").append(sanitize(t.getMessage())).append('\n');
                    }
                }
            }
        } catch (Throwable t) {
            return "PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_START_FAILED exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage()) + "\n" + out;
        } finally {
            if (pkgsOut != null) {
                try { pkgsOut.flush(); pkgsOut.close(); } catch (Throwable ignored) {}
            }
            if (factsOut != null) {
                try { factsOut.flush(); factsOut.close(); } catch (Throwable ignored) {}
            }
        }
        long elapsed = Math.max(0L, System.currentTimeMillis() - t0);
        if (started > 0) {
            out.insert(0, "PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_START_OK version=" + VERSION
                    + " user=" + userId
                    + " requested=" + requested
                    + " started=" + started
                    + " failed=" + failed
                    + " source=" + sanitize(cmp.getName())
                    + " pkgsOut=" + sanitize(pkgsOutPath)
                    + " factsOut=" + sanitize(factsOutPath)
                    + " factsRows=" + factsRows
                    + " policy=" + sanitize(opts.raw)
                    + " policyBase=" + sanitize(opts.base)
                    + " policyBuilder=dex-r430"
                    + " home=" + sanitize(home)
                    + " ime=" + sanitize(ime)
                    + " elapsedMs=" + elapsed
                    + " lifecycle=batch-watchset\n");
        } else {
            out.insert(0, "PROCESS_OBSERVER_RESTORE_SESSION_DIRECT_START_FAILED version=" + VERSION
                    + " reason=no_candidates requested=" + requested + " started=0 failed=" + failed
                    + " source=" + sanitize(cmp.getName()) + " factsOut=" + sanitize(factsOutPath)
                    + " factsRows=" + factsRows + " elapsedMs=" + elapsed + "\n");
        }
        return out.toString();
    }

    private static final class RestoreSessionPolicyOptions {
        String raw = "smart";
        String base = "smart";
        boolean defaultHomeEnabled = true;
        boolean defaultImeEnabled = true;
        final Set<String> hardFreeze = new HashSet<>();
    }

    private static final class RestoreSessionActionDecision {
        final String action;
        final String reason;
        RestoreSessionActionDecision(String action, String reason) {
            this.action = action == null ? "" : action;
            this.reason = reason == null ? "" : reason;
        }
    }

    private static String normalizeOptionalPackageArg(String raw) {
        if (raw == null) return "";
        String v = raw.trim();
        if (v.isEmpty()) return "";
        if ("-".equals(v) || "__EMPTY__".equals(v)) return "";
        return safePackage(v);
    }

    private static RestoreSessionPolicyOptions parseRestoreSessionPolicy(String policy) {
        RestoreSessionPolicyOptions opts = new RestoreSessionPolicyOptions();
        opts.raw = (policy == null || policy.trim().isEmpty()) ? "smart" : policy.trim();
        String[] parts = opts.raw.split(";");
        if (parts.length > 0 && parts[0] != null && !parts[0].trim().isEmpty()) opts.base = parts[0].trim().toLowerCase(Locale.US);
        for (int i = 1; i < parts.length; i++) {
            String part = parts[i] == null ? "" : parts[i].trim();
            if (part.isEmpty()) continue;
            int eq = part.indexOf('=');
            String k = eq >= 0 ? part.substring(0, eq).trim().toLowerCase(Locale.US) : part.toLowerCase(Locale.US);
            String v = eq >= 0 ? part.substring(eq + 1).trim() : "1";
            if ("home".equals(k) || "default_home".equals(k)) opts.defaultHomeEnabled = optionEnabled(v);
            else if ("ime".equals(k) || "default_ime".equals(k)) opts.defaultImeEnabled = optionEnabled(v);
            else if ("hard".equals(k) || "hardfreeze".equals(k) || "hard_freeze".equals(k) || "highrisk".equals(k)) {
                for (String p : v.split("[, ]+")) {
                    String pkg = safePackage(p);
                    if (!pkg.isEmpty()) opts.hardFreeze.add(pkg);
                }
            }
        }
        return opts;
    }

    private static boolean optionEnabled(String raw) {
        String v = raw == null ? "" : raw.trim().toLowerCase(Locale.US);
        return !(v.isEmpty() || "0".equals(v) || "false".equals(v) || "no".equals(v) || "off".equals(v) || "disable".equals(v) || "disabled".equals(v));
    }

    private static RestoreSessionActionDecision restoreSessionActionForPackage(String pkg, RestoreSessionPolicyOptions opts, String homePkg, String imePkg) {
        if (pkg == null || pkg.isEmpty()) return new RestoreSessionActionDecision("none", "empty-package");
        if (isRestoreHardFreezePackage(pkg)) return new RestoreSessionActionDecision("cgroup-freeze", "builtin-hard-freeze");
        if (opts != null && opts.hardFreeze.contains(pkg)) return new RestoreSessionActionDecision("cgroup-freeze", "policy-hard-freeze");
        if (opts != null && opts.defaultHomeEnabled && homePkg != null && !homePkg.isEmpty() && pkg.equals(homePkg)) return new RestoreSessionActionDecision("cgroup-freeze", "default-home");
        if (opts != null && opts.defaultImeEnabled && imePkg != null && !imePkg.isEmpty() && pkg.equals(imePkg)) return new RestoreSessionActionDecision("cgroup-freeze", "default-ime");
        if (isNeverPausePackage(pkg)) return new RestoreSessionActionDecision("monitor", "never-pause-framework");
        String p = opts == null ? "smart" : opts.base;
        if ("all".equals(p) || "full".equals(p) || "restricted".equals(p) || "guard-stop-restricted".equals(p)) return new RestoreSessionActionDecision("guard-stop-restricted", "policy-" + p);
        if ("basic".equals(p) || "lite".equals(p) || "force-stop".equals(p) || "guard-stop".equals(p)) return new RestoreSessionActionDecision("guard-stop:nologd", "policy-" + p);
        if ("appops".equals(p) || "guard-stop-appops".equals(p)) return new RestoreSessionActionDecision("guard-stop-appops", "policy-" + p);
        if ("monitor".equals(p) || "log".equals(p) || "none".equals(p) || "off".equals(p) || "disable".equals(p)) return new RestoreSessionActionDecision(p, "policy-" + p);
        return new RestoreSessionActionDecision(isRestoreHardFreezePackage(pkg) ? "guard-stop-restricted" : "guard-stop:nologd", "policy-smart");
    }

    private static String resolveDefaultHomePackage(int userId) {
        try {
            AppStateEngine.EngineResponse response = AppStateEngine.defaultHome(userId);
            String body = response == null ? "" : response.body;
            for (String line : body.split("\\n")) {
                if (line == null || line.trim().isEmpty()) continue;
                JsonObject o = JsonParser.parseString(line).getAsJsonObject();
                if (o == null || !"defaultHome".equals(jsonValue(o, "recordType"))) continue;
                JsonObject result = o.has("result") && o.get("result").isJsonObject() ? o.getAsJsonObject("result") : null;
                if (result != null && !"OK".equals(jsonValue(result, "name"))) continue;
                String pkg = safePackage(jsonValue(o, "packageName"));
                boolean resolver = false;
                try { if (o.has("isResolver")) resolver = o.get("isResolver").getAsBoolean(); } catch (Throwable ignored) {}
                if (!pkg.isEmpty() && !resolver) return pkg;
            }
        } catch (Throwable ignored) {}
        return "";
    }

    private static String resolveDefaultImePackage(int userId) {
        try {
            AppStateEngine.EngineResponse response = AppStateEngine.defaultIme(userId);
            String body = response == null ? "" : response.body;
            for (String line : body.split("\\n")) {
                if (line == null || line.trim().isEmpty()) continue;
                JsonObject o = JsonParser.parseString(line).getAsJsonObject();
                if (o == null || !"defaultIme".equals(jsonValue(o, "recordType"))) continue;
                JsonObject result = o.has("result") && o.get("result").isJsonObject() ? o.getAsJsonObject("result") : null;
                if (result != null && !"OK".equals(jsonValue(result, "name"))) continue;
                String pkg = safePackage(jsonValue(o, "packageName"));
                if (!pkg.isEmpty()) return pkg;
            }
        } catch (Throwable ignored) {}
        return "";
    }

    private static String jsonValue(JsonObject o, String key) {
        try { if (o != null && o.has(key) && !o.get(key).isJsonNull()) return o.get(key).getAsString(); } catch (Throwable ignored) {}
        return "";
    }

    private static int appendRestoreSessionRoleFacts(PrintWriter out, Context ctx, PackageManager pm, PackageManagerHidden pmHidden, int userId) {
        if (out == null || ctx == null) return 0;
        int rows = 0;
        String[][] roles = new String[][] {
                {"HOME", "android.app.role.HOME"},
                {"DIALER", "android.app.role.DIALER"},
                {"SMS", "android.app.role.SMS"},
                {"BROWSER", "android.app.role.BROWSER"},
                {"ASSISTANT", "android.app.role.ASSISTANT"}
        };
        Object roleManager = null;
        Method m = null;
        try {
            roleManager = ctx.getSystemService("role");
            if (roleManager != null) m = roleManager.getClass().getMethod("getRoleHoldersAsUser", String.class, android.os.UserHandle.class);
        } catch (Throwable ignored) { m = null; }
        for (String[] role : roles) {
            boolean any = false;
            if (roleManager != null && m != null) {
                try {
                    Object holders = m.invoke(roleManager, role[1], UserHandleHidden.of(userId));
                    if (holders instanceof List) {
                        for (Object h : (List<?>) holders) {
                            String pkg = safePackage(String.valueOf(h == null ? "" : h));
                            if (pkg.isEmpty()) continue;
                            rows += appendRestoreSessionFactRow(out, pm, pmHidden, userId, "ROLE", role[0], pkg, pkg, "", "role-holder", "RoleManager");
                            any = true;
                        }
                    }
                } catch (Throwable t) {
                    out.println("ROLE\t" + tsv(role[0]) + "\t-\t-\t" + userId + "\tfalse\t-1\t\terror:" + tsv(t.getClass().getSimpleName()) + "\tRoleManager\tfalse\t-1\t");
                    rows++;
                    any = true;
                }
            }
            if (!any) {
                out.println("ROLE\t" + tsv(role[0]) + "\t-\t-\t" + userId + "\tfalse\t-1\t\tno-holder\tRoleManager\tfalse\t-1\t");
                rows++;
            }
        }
        return rows;
    }

    private static int appendRestoreSessionFactRow(PrintWriter out, PackageManager pm, PackageManagerHidden pmHidden, int userId,
                                                   String kind, String role, String pkg, String label, String action, String reason, String source) {
        if (out == null) return 0;
        String safePkg = safePackage(pkg);
        if (safePkg.isEmpty()) {
            out.println(tsv(kind) + "\t" + tsv(role) + "\t-\t" + tsv(label) + "\t" + userId + "\tfalse\t-1\t" + tsv(action) + "\t" + tsv(reason) + "\t" + tsv(source) + "\tfalse\t-1\t");
            return 1;
        }
        boolean installed = false;
        boolean system = false;
        int uid = -1;
        long versionCode = -1L;
        String sourceDir = "";
        String finalLabel = label == null || label.trim().isEmpty() ? safePkg : label.trim();
        if (pmHidden != null) {
            try {
                PackageInfo pi = pmHidden.getPackageInfoAsUser(safePkg, PackageManager.GET_META_DATA, userId);
                if (pi != null && pi.applicationInfo != null) {
                    installed = true;
                    uid = pi.applicationInfo.uid;
                    system = (pi.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
                    sourceDir = safeString(pi.applicationInfo.sourceDir);
                    versionCode = longVersionCode(pi);
                    if (pm != null) {
                        try {
                            CharSequence cs = pi.applicationInfo.loadLabel(pm);
                            if (cs != null && cs.length() > 0) finalLabel = cs.toString();
                        } catch (Throwable ignored) {}
                    }
                }
            } catch (Throwable ignored) {}
        }
        if (uid < 0) uid = resolveTargetUid(userId, safePkg);
        out.println(tsv(kind) + "\t" + tsv(role) + "\t" + tsv(safePkg) + "\t" + tsv(finalLabel) + "\t" + userId + "\t" + installed + "\t" + uid
                + "\t" + tsv(action) + "\t" + tsv(reason) + "\t" + tsv(source) + "\t" + system + "\t" + versionCode + "\t" + tsv(sourceDir));
        return 1;
    }

    private static String tsv(String raw) {
        if (raw == null) return "";
        return raw.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').replace('\0', ' ').trim();
    }

    private static boolean isDisabledAction(String action) {
        if (action == null) return true;
        String a = action.trim().toLowerCase(Locale.US);
        return a.isEmpty() || "none".equals(a) || "off".equals(a) || "disable".equals(a) || "disabled".equals(a);
    }

    private static boolean isSpeedBackupSelfPackage(String pkg) {
        return "bin.mt.plus".equals(pkg) || "bin.mt.plus.canary".equals(pkg) || "com.termux".equals(pkg);
    }

    private static boolean isRestoreHardFreezePackage(String pkg) {
        return "com.tencent.mm".equals(pkg)
                || "com.tencent.mobileqq".equals(pkg)
                || "com.tencent.tim".equals(pkg)
                || "com.tencent.wework".equals(pkg)
                || "com.eg.android.AlipayGphone".equals(pkg)
                || "com.taobao.taobao".equals(pkg)
                || "com.ss.android.ugc.aweme".equals(pkg)
                || (pkg != null && pkg.startsWith("com.baidu.input"));
    }

    private static boolean isNeverPausePackage(String pkg) {
        if (pkg == null) return false;
        return "android".equals(pkg)
                || "system".equals(pkg)
                || "com.android.systemui".equals(pkg)
                || "com.android.phone".equals(pkg)
                || pkg.startsWith("com.android.providers.")
                || "com.android.server.telecom".equals(pkg)
                || "com.android.nfc".equals(pkg)
                || "com.android.bluetooth".equals(pkg)
                || "com.android.shell".equals(pkg)
                || "com.android.permissioncontroller".equals(pkg)
                || "com.google.android.permissioncontroller".equals(pkg)
                || "com.android.vending".equals(pkg)
                || "com.google.android.gms".equals(pkg)
                || "com.google.android.gsf".equals(pkg)
                || pkg.startsWith("com.android.launcher")
                || "com.google.android.apps.nexuslauncher".equals(pkg)
                || "com.miui.home".equals(pkg)
                || "com.sec.android.app.launcher".equals(pkg)
                || "com.oppo.launcher".equals(pkg)
                || "com.coloros.launcher".equals(pkg)
                || "com.huawei.android.launcher".equals(pkg)
                || "com.vivo.launcher".equals(pkg);
    }

    static synchronized String startBatchAsync(int userId, String specPath) {
        StringBuilder out = new StringBuilder();
        out.append(cleanupStaleBatchStates("batch-start", BATCH_STATE_TTL_MS));
        File spec = new File(specPath == null ? "" : specPath);
        if (!spec.isFile()) {
            return "PROCESS_OBSERVER_BATCH_START_FAILED reason=spec_missing path=" + sanitize(specPath) + "\n" + out;
        }
        int requested = 0;
        int started = 0;
        int failed = 0;
        try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(spec), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (line.trim().isEmpty() || line.startsWith("#")) continue;
                requested++;
                String[] parts = line.split("\t", -1);
                String pkg = parts.length > 0 ? safePackage(parts[0]) : "";
                String label = parts.length > 1 ? parts[1].trim() : pkg;
                String action = parts.length > 2 ? parts[2].trim() : "guard-stop";
                String logPath = parts.length > 3 ? parts[3].trim() : "-";
                if (pkg.isEmpty()) {
                    failed++;
                    out.append("PROCESS_OBSERVER_BATCH_START_ITEM_FAILED index=").append(requested)
                            .append(" reason=empty_package label=").append(sanitize(label)).append('\n');
                    continue;
                }
                int token = NEXT_TOKEN.incrementAndGet();
                WatchSession session = null;
                try {
                    session = new WatchSession(userId, pkg, 0L, action, wakeBlockModeFromAction(action), logPath);
                    session.token = token;
                    SESSIONS.put(token, session);
                    session.startTarget();
                    boolean stateOk = persistBatchState(token, userId, pkg, label, action, logPath, "start-ok");
                    started++;
                    out.append("PROCESS_OBSERVER_BATCH_START_ITEM token=").append(token)
                            .append(" user=").append(userId)
                            .append(" package=").append(pkg)
                            .append(" label=").append(sanitize(label))
                            .append(" action=").append(action)
                            .append(" wakeBlockMode=").append(wakeBlockModeFromAction(action))
                            .append(" lifecycle=batch-watchset")
                            .append(" persistentState=").append(stateOk)
                            .append(" log=").append(sanitize(logPath)).append('\n');
                } catch (Throwable t) {
                    failed++;
                    SESSIONS.remove(token);
                    deleteBatchState(token);
                    if (session != null) {
                        try { session.finish("batch-start-failed:" + t.getClass().getSimpleName()); } catch (Throwable ignored) {}
                    }
                    out.append("PROCESS_OBSERVER_BATCH_START_ITEM_FAILED index=").append(requested)
                            .append(" package=").append(pkg)
                            .append(" label=").append(sanitize(label))
                            .append(" exception=").append(sanitize(t.getClass().getName()))
                            .append(" message=").append(sanitize(t.getMessage())).append('\n');
                }
            }
            out.insert(0, "PROCESS_OBSERVER_BATCH_START_OK version=" + VERSION
                    + " user=" + userId
                    + " requested=" + requested
                    + " started=" + started
                    + " failed=" + failed
                    + " lifecycle=batch-watchset persistentSafety=r296\n");
        } catch (Throwable t) {
            return "PROCESS_OBSERVER_BATCH_START_FAILED exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage())
                    + " requested=" + requested
                    + " started=" + started
                    + " failed=" + failed + "\n" + out;
        }
        return out.toString();
    }

    static synchronized String stopBatchAsync(String statePath, int expectedUserId) {
        return stopBatchAsync(statePath, expectedUserId, "");
    }

    static synchronized String stopBatchAsync(String statePath, int expectedUserId, String summaryPath) {
        StringBuilder out = new StringBuilder();
        StringBuilder summaryTsv = new StringBuilder();
        summaryTsv.append("#schema\tspeedbackup.process_observer.batch_stop_summary.v1\n");
        summaryTsv.append("#fields\ttoken\tpackage\tlabel\tresult\trestoreOk\tstateDeleted\taction\tevents\tmatches\tactions\ttaskEvents\tnativeLogdEvents\tnativeLogdMatches\tcgroupFreezeTokens\twakeBlockToken\tstopMs\terror\treason\n");
        int summaryRows = 0;
        out.append(cleanupStaleBatchStates("batch-stop", BATCH_STATE_TTL_MS));
        File state = new File(statePath == null ? "" : statePath);
        if (!state.isFile()) {
            writeBatchStopSummaryIfRequested(summaryPath, summaryTsv, 0, out);
            return "PROCESS_OBSERVER_BATCH_STOP_MISSING path=" + sanitize(statePath) + " expectedUser=" + expectedUserId + " stateRetained=false\n" + out;
        }
        int requested = 0;
        int stopped = 0;
        int recovered = 0;
        int missing = 0;
        int failed = 0;
        int stateDeleteFailed = 0;
        try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(state), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (line.trim().isEmpty() || line.startsWith("#")) continue;
                String[] parts = line.split("\t", -1);
                int token = parsePositiveInt(parts.length > 0 ? parts[0] : "", -1);
                String pkg = parts.length > 1 ? safePackage(parts[1]) : "";
                String label = parts.length > 2 ? parts[2].trim() : pkg;
                if (token <= 0) continue;
                requested++;
                WatchSession session = SESSIONS.get(token);
                if (session == null) {
                    Properties persisted = readBatchState(batchStateFile(token));
                    String action = persisted.getProperty("action", "");
                    BatchSafetyResult r = restoreBatchSafetyNet(token, expectedUserId, pkg, "process-observer-batch-stop-missing-" + token);
                    out.append(r.output);
                    if (r.restoreOk && r.stateDeleted) {
                        recovered++;
                        out.append("PROCESS_OBSERVER_BATCH_STOP_ITEM_RECOVERED token=").append(token)
                                .append(" package=").append(pkg)
                                .append(" label=").append(sanitize(label))
                                .append(" restoreOk=true stateDeleted=true lifecycle=batch-watchset\n");
                        appendBatchStopSummaryRow(summaryTsv, token, pkg, label, "recovered", true, true, action,
                                "0", "0", "0", "0", "0", "0", "0", "-1", "0", "", "safety-restore");
                    } else {
                        missing++;
                        out.append("PROCESS_OBSERVER_BATCH_STOP_ITEM_MISSING token=").append(token)
                                .append(" package=").append(pkg)
                                .append(" label=").append(sanitize(label))
                                .append(" restoreOk=").append(r.restoreOk)
                                .append(" stateDeleted=").append(r.stateDeleted)
                                .append(" stateRetained=true\n");
                        appendBatchStopSummaryRow(summaryTsv, token, pkg, label, "missing", r.restoreOk, r.stateDeleted, action,
                                "0", "0", "0", "0", "0", "0", "0", "-1", "0", "state-retained", "missing-session");
                    }
                    summaryRows++;
                    continue;
                }
                long stopT0 = System.currentTimeMillis();
                try {
                    String summary = session.finish("batch-stop-token-" + token);
                    long stopMs = Math.max(0L, System.currentTimeMillis() - stopT0);
                    SESSIONS.remove(token);
                    boolean deleted = deleteBatchState(token);
                    if (deleted) {
                        stopped++;
                    } else {
                        stateDeleteFailed++;
                        failed++;
                    }
                    out.append("PROCESS_OBSERVER_BATCH_STOP_ITEM token=").append(token)
                            .append(" package=").append(pkg)
                            .append(" label=").append(sanitize(label))
                            .append(" result=stopped restoreOk=true stateDeleted=").append(deleted)
                            .append(" ").append(sanitize(summary.trim())).append('\n');
                    appendBatchStopSummaryRow(summaryTsv, token, pkg, label, "stopped", true, deleted, session.action,
                            summaryValue(summary, "events", "0"), summaryValue(summary, "matches", "0"), summaryValue(summary, "actions", "0"),
                            summaryValue(summary, "taskEvents", "0"), summaryValue(summary, "nativeLogdEvents", "0"), summaryValue(summary, "nativeLogdMatches", "0"),
                            summaryValue(summary, "cgroupFreezeTokens", "0"), summaryValue(summary, "wakeBlockToken", "-1"), String.valueOf(stopMs), deleted ? "" : "state-delete-failed", "normal-stop");
                    summaryRows++;
                } catch (Throwable t) {
                    failed++;
                    long stopMs = Math.max(0L, System.currentTimeMillis() - stopT0);
                    out.append("PROCESS_OBSERVER_BATCH_STOP_ITEM_FAILED token=").append(token)
                            .append(" package=").append(pkg)
                            .append(" label=").append(sanitize(label))
                            .append(" exception=").append(sanitize(t.getClass().getName()))
                            .append(" message=").append(sanitize(t.getMessage()))
                            .append(" stateRetained=true").append('\n');
                    appendBatchStopSummaryRow(summaryTsv, token, pkg, label, "failed", false, false, session.action,
                            String.valueOf(session.events.get()), String.valueOf(session.matches.get()), String.valueOf(session.actions.get()),
                            String.valueOf(session.taskEvents.get()), String.valueOf(session.nativeLogdEvents.get()), String.valueOf(session.nativeLogdMatches.get()),
                            String.valueOf(session.cgroupFreezeTokens.size()), String.valueOf(session.wakeBlockToken), String.valueOf(stopMs),
                            t.getClass().getSimpleName(), "exception");
                    summaryRows++;
                }
            }
            boolean complete = requested > 0 && requested == (stopped + recovered) && missing == 0 && failed == 0 && stateDeleteFailed == 0;
            String header = complete ? "PROCESS_OBSERVER_BATCH_STOP_OK" : "PROCESS_OBSERVER_BATCH_STOP_INCOMPLETE";
            writeBatchStopSummaryIfRequested(summaryPath, summaryTsv, summaryRows, out);
            out.insert(0, header + " version=" + VERSION
                    + " expectedUser=" + expectedUserId
                    + " requested=" + requested
                    + " stopped=" + stopped
                    + " recovered=" + recovered
                    + " missing=" + missing
                    + " failed=" + failed
                    + " stateDeleteFailed=" + stateDeleteFailed
                    + " summaryRows=" + summaryRows
                    + " summaryPath=" + sanitize(summaryPath)
                    + " ok=" + complete
                    + " restoreOk=" + complete
                    + " stateDeleted=" + complete
                    + " stateRetained=" + (!complete)
                    + " lifecycle=batch-watchset safeStop=r430 summaryTsv=true persistentSafety=true\n");
        } catch (Throwable t) {
            writeBatchStopSummaryIfRequested(summaryPath, summaryTsv, summaryRows, out);
            return "PROCESS_OBSERVER_BATCH_STOP_FAILED exception=" + sanitize(t.getClass().getName())
                    + " message=" + sanitize(t.getMessage())
                    + " requested=" + requested
                    + " stopped=" + stopped
                    + " recovered=" + recovered
                    + " missing=" + missing
                    + " failed=" + failed
                    + " summaryRows=" + summaryRows + "\n" + out;
        }
        return out.toString();
    }

    private static void appendBatchStopSummaryRow(StringBuilder sb, int token, String pkg, String label, String result,
                                                  boolean restoreOk, boolean stateDeleted, String action,
                                                  String events, String matches, String actions, String taskEvents,
                                                  String nativeLogdEvents, String nativeLogdMatches, String cgroupFreezeTokens,
                                                  String wakeBlockToken, String stopMs, String error, String reason) {
        sb.append(token).append('\t').append(tsv(pkg)).append('\t').append(tsv(label)).append('\t').append(tsv(result))
                .append('\t').append(restoreOk).append('\t').append(stateDeleted).append('\t').append(tsv(action))
                .append('\t').append(tsv(events)).append('\t').append(tsv(matches)).append('\t').append(tsv(actions))
                .append('\t').append(tsv(taskEvents)).append('\t').append(tsv(nativeLogdEvents)).append('\t').append(tsv(nativeLogdMatches))
                .append('\t').append(tsv(cgroupFreezeTokens)).append('\t').append(tsv(wakeBlockToken)).append('\t').append(tsv(stopMs))
                .append('\t').append(tsv(error)).append('\t').append(tsv(reason)).append('\n');
    }

    private static String summaryValue(String summary, String key, String fallback) {
        if (summary == null || key == null || key.isEmpty()) return fallback;
        String prefix = key + "=";
        String[] parts = summary.split("\\s+");
        for (String part : parts) {
            if (part != null && part.startsWith(prefix)) return part.substring(prefix.length());
        }
        return fallback;
    }

    private static void writeBatchStopSummaryIfRequested(String summaryPath, StringBuilder summaryTsv, int rows, StringBuilder out) {
        if (summaryPath == null || summaryPath.trim().isEmpty() || "-".equals(summaryPath.trim())) return;
        boolean ok = false;
        try {
            File f = new File(summaryPath.trim());
            File parent = f.getParentFile();
            if (parent != null) parent.mkdirs();
            try (PrintWriter pw = new PrintWriter(new OutputStreamWriter(new FileOutputStream(f, false), StandardCharsets.UTF_8))) {
                pw.print(summaryTsv.toString());
            }
            ok = f.isFile() && f.length() > 0;
        } catch (Throwable ignored) {
            ok = false;
        }
        out.append("PROCESS_OBSERVER_BATCH_STOP_SUMMARY_WRITTEN path=").append(sanitize(summaryPath))
                .append(" rows=").append(rows).append(" ok=").append(ok).append('\n');
    }

    private static File batchStateDir() {
        File dir = new File(BATCH_STATE_DIR);
        try { if (!dir.isDirectory()) dir.mkdirs(); } catch (Throwable ignored) {}
        return dir;
    }

    private static File batchStateFile(int token) {
        return new File(batchStateDir(), "process_observer_batch_" + token + ".properties");
    }

    private static boolean persistBatchState(int token, int userId, String pkg, String label, String action, String logPath, String reason) {
        if (token <= 0) return false;
        File file = batchStateFile(token);
        Properties p = new Properties();
        p.setProperty("schema", "speedbackup.process_observer.batch_state.v1");
        p.setProperty("version", VERSION);
        p.setProperty("token", String.valueOf(token));
        p.setProperty("user", String.valueOf(userId));
        p.setProperty("package", safePackage(pkg));
        p.setProperty("label", sanitize(label));
        p.setProperty("action", normalizeAction(action));
        p.setProperty("log", sanitize(logPath));
        p.setProperty("reason", sanitize(reason));
        p.setProperty("updatedAt", String.valueOf(System.currentTimeMillis()));
        try (FileOutputStream fos = new FileOutputStream(file)) {
            p.store(fos, "SpeedBackup process observer batch safety state");
            return file.isFile() && file.length() > 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static Properties readBatchState(File file) {
        Properties p = new Properties();
        if (file == null || !file.isFile()) return p;
        try (FileInputStream fis = new FileInputStream(file)) { p.load(fis); } catch (Throwable ignored) {}
        return p;
    }

    private static boolean deleteBatchState(int token) {
        File file = batchStateFile(token);
        return !file.exists() || file.delete() || !file.exists();
    }

    private static String cleanupStaleBatchStates(String reason, long ttlMs) {
        StringBuilder out = new StringBuilder();
        File[] files = batchStateDir().listFiles();
        long now = System.currentTimeMillis();
        long ttl = ttlMs < 0L ? BATCH_STATE_TTL_MS : ttlMs;
        int total = 0;
        int stale = 0;
        int restored = 0;
        int retained = 0;
        if (files != null) {
            for (File f : files) {
                if (f == null || !f.isFile() || !f.getName().endsWith(".properties")) continue;
                total++;
                Properties p = readBatchState(f);
                int token = parsePositiveInt(p.getProperty("token", ""), -1);
                int userId = parsePositiveInt(p.getProperty("user", ""), -1);
                String pkg = safePackage(p.getProperty("package", ""));
                long updatedAt = parseLongLocal(p.getProperty("updatedAt", ""), f.lastModified());
                long ageMs = Math.max(0L, now - updatedAt);
                if (ageMs < ttl) continue;
                stale++;
                BatchSafetyResult r = restoreBatchSafetyNet(token, userId, pkg, "stale-batch-cleanup-" + sanitize(reason));
                out.append("PROCESS_OBSERVER_BATCH_STALE_CLEANUP token=").append(token)
                        .append(" user=").append(userId)
                        .append(" package=").append(sanitize(pkg))
                        .append(" ageMs=").append(ageMs)
                        .append(" restoreOk=").append(r.restoreOk)
                        .append(" stateDeleted=").append(r.stateDeleted)
                        .append(" reason=").append(sanitize(reason)).append('\n');
                out.append(r.output);
                if (r.restoreOk && r.stateDeleted) restored++; else retained++;
            }
        }
        if (total > 0 || stale > 0) {
            out.append("PROCESS_OBSERVER_BATCH_STALE_CLEANUP_DONE total=").append(total)
                    .append(" stale=").append(stale)
                    .append(" restored=").append(restored)
                    .append(" retained=").append(retained)
                    .append(" ttlMs=").append(ttl)
                    .append(" reason=").append(sanitize(reason)).append('\n');
        }
        return out.toString();
    }

    private static BatchSafetyResult restoreBatchSafetyNet(int token, int userId, String pkg, String reason) {
        StringBuilder out = new StringBuilder();
        String safePkg = safePackage(pkg);
        String wake = "";
        String cgroup = "";
        try { wake = AppWakeBlockUtil.restorePersistedObserverToken(token, reason, userId, safePkg); } catch (Throwable t) { wake = "APP_WAKE_BLOCK_PERSISTENT_RESTORE_FAILED exception=" + sanitize(t.getClass().getName()) + " message=" + sanitize(t.getMessage()) + "\n"; }
        try { cgroup = CgroupFreezeUtil.restorePersistedPackage(userId, safePkg, reason); } catch (Throwable t) { cgroup = "CGROUP_FREEZE_PERSISTENT_RESTORE_PACKAGE_FAILED exception=" + sanitize(t.getClass().getName()) + " message=" + sanitize(t.getMessage()) + "\n"; }
        out.append(sanitizeMultiLineLocal(wake)).append('\n');
        out.append(sanitizeMultiLineLocal(cgroup)).append('\n');
        boolean wakeOk = restoreMissingOrDeleted(wake);
        boolean cgroupOk = cgroupRestoreOk(cgroup);
        boolean restoreOk = wakeOk && cgroupOk;
        boolean stateDeleted = restoreOk && deleteBatchState(token);
        out.append("PROCESS_OBSERVER_BATCH_SAFETY_RESTORE token=").append(token)
                .append(" user=").append(userId)
                .append(" package=").append(sanitize(safePkg))
                .append(" wakeRestoreOk=").append(wakeOk)
                .append(" cgroupRestoreOk=").append(cgroupOk)
                .append(" restoreOk=").append(restoreOk)
                .append(" stateDeleted=").append(stateDeleted)
                .append(" reason=").append(sanitize(reason)).append('\n');
        return new BatchSafetyResult(restoreOk, stateDeleted, out.toString());
    }

    private static boolean restoreMissingOrDeleted(String text) {
        String s = text == null ? "" : text;
        return s.contains("PERSISTENT_RESTORE_MISSING") || s.contains("stateDeleted=true") || s.contains("RESTORE_DONE") || s.contains("STOP_OK") || s.contains("STOP_DONE");
    }

    private static boolean cgroupRestoreOk(String text) {
        String s = text == null ? "" : text;
        if (s.contains("fail=") && !s.contains("fail=0")) return false;
        return s.contains("CGROUP_FREEZE_PERSISTENT_RESTORE_PACKAGE_DONE") || s.contains("PERSISTENT_RESTORE_MISSING") || s.contains("stateDeleted=true") || s.contains("tokens=0");
    }

    private static long parseLongLocal(String raw, long fallback) {
        try { return Long.parseLong(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    private static String sanitizeMultiLineLocal(String raw) {
        if (raw == null) return "";
        StringBuilder out = new StringBuilder();
        String[] lines = raw.split("\\r?\\n");
        for (String line : lines) {
            if (line == null || line.trim().isEmpty()) continue;
            out.append(sanitize(line.trim())).append('\n');
        }
        return out.toString();
    }

    private static final class BatchSafetyResult {
        final boolean restoreOk;
        final boolean stateDeleted;
        final String output;
        BatchSafetyResult(boolean restoreOk, boolean stateDeleted, String output) {
            this.restoreOk = restoreOk;
            this.stateDeleted = stateDeleted;
            this.output = output == null ? "" : output;
        }
    }

    static String topStatus(int userId) {
        TopSnapshot top = findTopApp(userId);
        return "PROCESS_OBSERVER_TOP version=" + VERSION
                + " user=" + userId
                + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                + " topActivity=" + (top == null ? "" : sanitize(top.activityName))
                + " source=" + (top == null ? "none" : sanitize(top.source))
                + " directTopCheck=1 dumpsys=0\n";
    }

    static String foregroundStatus(int userId, String[] args, int start) {
        StringBuilder out = new StringBuilder();
        TopSnapshot top = findTopApp(userId);
        if (args == null || args.length <= start) {
            out.append(topStatus(userId));
            return out.toString();
        }
        for (int i = start; i < args.length; i++) {
            String pkg = safePackage(args[i]);
            if (pkg.isEmpty()) continue;
            int uid = resolveTargetUid(userId, pkg);
            List<PidInfo> alive = findAliveProcesses(userId, pkg, uid);
            boolean topTarget = isTargetTop(top, pkg);
            boolean active = topTarget || !alive.isEmpty();
            out.append("PROCESS_OBSERVER_FOREGROUND version=").append(VERSION)
                    .append(" user=").append(userId)
                    .append(" package=").append(pkg)
                    .append(" targetUid=").append(uid)
                    .append(" active=").append(active)
                    .append(" topTarget=").append(topTarget)
                    .append(" alive=").append(!alive.isEmpty())
                    .append(" aliveCount=").append(alive.size())
                    .append(" alivePids=").append(pidCsv(alive))
                    .append(" topPackage=").append(top == null ? "" : sanitize(top.packageName))
                    .append(" topActivity=").append(top == null ? "" : sanitize(top.activityName))
                    .append(" source=").append(top == null ? "none" : sanitize(top.source))
                    .append(" directTopCheck=1 dumpsys=0 planner=0\n");
        }
        return out.toString();
    }


    static String packageLiveState(int userId, String[] args, int start) {
        StringBuilder out = new StringBuilder();
        TopSnapshot top = findTopApp(userId);
        if (args == null || args.length <= start) {
            out.append("PACKAGE_LIVE_STATE_DONE ok=false reason=empty user=").append(userId).append('\n');
            return out.toString();
        }
        for (int i = start; i < args.length; i++) {
            String pkg = safePackage(args[i]);
            if (pkg.isEmpty()) continue;
            int uid = resolveTargetUid(userId, pkg);
            boolean installed = false;
            boolean enabled = false;
            boolean suspended = false;
            long versionCode = -1L;
            String reason = "OK";
            try {
                JsonObject st = JsonParser.parseString(AppInventoryUtil.packageStatusSingle(userId, pkg, true).trim()).getAsJsonObject();
                if (st.has("installed")) installed = st.get("installed").getAsBoolean();
                if (st.has("enabled")) enabled = st.get("enabled").getAsBoolean();
                if (st.has("suspended")) suspended = st.get("suspended").getAsBoolean();
                if (st.has("versionCode")) versionCode = st.get("versionCode").getAsLong();
                if (st.has("uid")) uid = st.get("uid").getAsInt();
                if (st.has("reason")) reason = st.get("reason").getAsString();
            } catch (Throwable t) {
                reason = t.getClass().getSimpleName();
            }
            List<PidInfo> alive = findAliveProcesses(userId, pkg, uid);
            boolean topTarget = isTargetTop(top, pkg);
            boolean active = topTarget || !alive.isEmpty();
            out.append("PACKAGE_LIVE_STATE version=").append(VERSION)
                    .append(" user=").append(userId)
                    .append(" package=").append(pkg)
                    .append(" installed=").append(installed)
                    .append(" enabled=").append(enabled)
                    .append(" suspended=").append(suspended)
                    .append(" stopped=unknown")
                    .append(" uid=").append(uid)
                    .append(" versionCode=").append(versionCode)
                    .append(" alive=").append(!alive.isEmpty())
                    .append(" aliveCount=").append(alive.size())
                    .append(" alivePids=").append(pidCsv(alive))
                    .append(" active=").append(active)
                    .append(" topTarget=").append(topTarget)
                    .append(" topPackage=").append(top == null ? "" : sanitize(top.packageName))
                    .append(" topActivity=").append(top == null ? "" : sanitize(top.activityName))
                    .append(" source=").append(top == null ? "none" : sanitize(top.source))
                    .append(" pmReason=").append(sanitize(reason))
                    .append(" directTopCheck=1 dumpsys=0 hash=0 planner=0\n");
        }
        return out.toString();
    }


    static String packageInstallSnapshot(int userId, String[] args, int start) {
        StringBuilder out = new StringBuilder();
        if (args == null || args.length <= start) {
            return "PACKAGE_INSTALL_SNAPSHOT_DONE ok=false reason=empty user=" + userId + " hash=0 planner=0\n";
        }
        Context ctx = null;
        PackageManager realPm = null;
        PackageManagerHidden pmHidden = null;
        try {
            ctx = HiddenApiHelper.getContext();
            realPm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            pmHidden = Refine.unsafeCast(realPm);
        } catch (Throwable t) {
            return "PACKAGE_INSTALL_SNAPSHOT_DONE ok=false reason=" + sanitize(t.getClass().getSimpleName()) + " user=" + userId + " hash=0 planner=0\n";
        }
        for (int i = start; i < args.length; i++) {
            String pkg = safePackage(args[i]);
            if (pkg.isEmpty()) continue;
            int uid = -1;
            long versionCode = -1L;
            boolean installed = false;
            boolean matchUninstalled = false;
            String enabled = "unknown";
            String sourceDir = "";
            String publicSourceDir = "";
            String dataDir = "";
            String installer = "";
            String installing = "";
            String initiating = "";
            String originating = "";
            String updateOwner = "";
            String packageSource = "";
            String packagesForUid = "";
            String reason = "OK";
            try {
                PackageInfo pi = pmHidden.getPackageInfoAsUser(pkg, PackageManager.GET_META_DATA, userId);
                installed = pi != null && pi.applicationInfo != null;
                if (pi != null) versionCode = longVersionCode(pi);
                if (pi != null && pi.applicationInfo != null) {
                    ApplicationInfo ai = pi.applicationInfo;
                    uid = ai.uid;
                    enabled = String.valueOf(ai.enabled);
                    sourceDir = safeString(ai.sourceDir);
                    publicSourceDir = safeString(ai.publicSourceDir);
                    dataDir = safeString(ai.dataDir);
                }
            } catch (Throwable t) {
                reason = t.getClass().getSimpleName();
            }
            try {
                int flags = PackageManager.GET_META_DATA | PackageManager.MATCH_UNINSTALLED_PACKAGES;
                PackageInfo pi2 = pmHidden.getPackageInfoAsUser(pkg, flags, userId);
                matchUninstalled = pi2 != null;
                if (uid < 0 && pi2 != null && pi2.applicationInfo != null) uid = pi2.applicationInfo.uid;
                if (versionCode < 0 && pi2 != null) versionCode = longVersionCode(pi2);
                if (sourceDir.isEmpty() && pi2 != null && pi2.applicationInfo != null) sourceDir = safeString(pi2.applicationInfo.sourceDir);
                if (dataDir.isEmpty() && pi2 != null && pi2.applicationInfo != null) dataDir = safeString(pi2.applicationInfo.dataDir);
            } catch (Throwable ignored) {}
            try { installer = safeString(realPm.getInstallerPackageName(pkg)); } catch (Throwable ignored) {}
            try {
                Object info = HiddenApiReflection.invokeFlexible(realPm, "getInstallSourceInfo", pkg);
                installing = firstNonEmptyLocal(safeObjectString(invokeNoArgLocal(info, "getInstallingPackageName")), installer);
                initiating = safeObjectString(invokeNoArgLocal(info, "getInitiatingPackageName"));
                originating = safeObjectString(invokeNoArgLocal(info, "getOriginatingPackageName"));
                updateOwner = safeObjectString(invokeNoArgLocal(info, "getUpdateOwnerPackageName"));
                packageSource = safeObjectString(invokeNoArgLocal(info, "getPackageSource"));
            } catch (Throwable ignored) {
                installing = installer;
            }
            try {
                if (uid >= 0) {
                    String[] pfu = realPm.getPackagesForUid(uid);
                    if (pfu != null) packagesForUid = joinCsv(pfu);
                }
            } catch (Throwable ignored) {}
            out.append("PACKAGE_INSTALL_SNAPSHOT version=").append(VERSION)
                    .append(" user=").append(userId)
                    .append(" package=").append(pkg)
                    .append(" installed=").append(installed)
                    .append(" matchUninstalled=").append(matchUninstalled)
                    .append(" uid=").append(uid)
                    .append(" versionCode=").append(versionCode)
                    .append(" enabled=").append(enabled)
                    .append(" sourceDir=").append(sanitize(sourceDir))
                    .append(" publicSourceDir=").append(sanitize(publicSourceDir))
                    .append(" dataDir=").append(sanitize(dataDir))
                    .append(" installer=").append(sanitize(installer))
                    .append(" installing=").append(sanitize(installing))
                    .append(" initiating=").append(sanitize(initiating))
                    .append(" originating=").append(sanitize(originating))
                    .append(" updateOwner=").append(sanitize(updateOwner))
                    .append(" packageSource=").append(sanitize(packageSource))
                    .append(" packagesForUid=").append(sanitize(packagesForUid))
                    .append(" reason=").append(sanitize(reason))
                    .append(" hash=0 planner=0\n");
        }
        return out.toString();
    }

    static String packageRestrictionSnapshot(int userId, String[] args, int start) {
        StringBuilder out = new StringBuilder();
        if (args == null || args.length <= start) {
            return "PACKAGE_RESTRICTION_SNAPSHOT_DONE ok=false reason=empty user=" + userId + " hash=0 planner=0\n";
        }
        Context ctx = null;
        AppOpsManager appOps = null;
        try {
            ctx = HiddenApiHelper.getContext();
            appOps = (AppOpsManager) ctx.getSystemService(Context.APP_OPS_SERVICE);
        } catch (Throwable ignored) {}
        for (int i = start; i < args.length; i++) {
            String pkg = safePackage(args[i]);
            if (pkg.isEmpty()) continue;
            int uid = resolveTargetUid(userId, pkg);
            String standbyBucket = readStandbyBucket(pkg, userId);
            String runBg = readAppOpMode(appOps, "android:run_in_background", uid, pkg);
            String runAnyBg = readAppOpMode(appOps, "android:run_any_in_background", uid, pkg);
            String autoRevoke = readAppOpMode(appOps, "android:auto_revoke_permissions_if_unused", uid, pkg);
            String hibernating = readHibernationState(pkg, userId);
            String unusedRestrictions = readUnusedAppRestrictions(pkg, userId);
            String backgroundRestricted = readBackgroundRestricted(pkg, userId);
            out.append("PACKAGE_RESTRICTION_SNAPSHOT version=").append(VERSION)
                    .append(" user=").append(userId)
                    .append(" package=").append(pkg)
                    .append(" uid=").append(uid)
                    .append(" standbyBucket=").append(sanitize(standbyBucket))
                    .append(" backgroundRestricted=").append(sanitize(backgroundRestricted))
                    .append(" hibernating=").append(sanitize(hibernating))
                    .append(" unusedAppRestrictions=").append(sanitize(unusedRestrictions))
                    .append(" autoRevokeAppOp=").append(sanitize(autoRevoke))
                    .append(" runInBackgroundAppOp=").append(sanitize(runBg))
                    .append(" runAnyInBackgroundAppOp=").append(sanitize(runAnyBg))
                    .append(" batteryRestricted=unknown")
                    .append(" hash=0 planner=0\n");
        }
        return out.toString();
    }

    private static long longVersionCode(PackageInfo pi) {
        if (pi == null) return -1L;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return pi.getLongVersionCode();
        } catch (Throwable ignored) {}
        return pi.versionCode;
    }

    private static Object invokeNoArgLocal(Object target, String method) throws Exception {
        if (target == null || method == null || method.isEmpty()) return null;
        java.lang.reflect.Method m = target.getClass().getMethod(method);
        m.setAccessible(true);
        return m.invoke(target);
    }

    private static String safeObjectString(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private static String safeString(String value) {
        return value == null ? "" : value;
    }

    private static String firstNonEmptyLocal(String a, String b) {
        return a != null && !a.isEmpty() ? a : (b == null ? "" : b);
    }

    private static String joinCsv(String[] values) {
        if (values == null || values.length == 0) return "";
        StringBuilder b = new StringBuilder();
        for (String v : values) {
            if (v == null || v.isEmpty()) continue;
            if (b.length() > 0) b.append(',');
            b.append(sanitize(v));
        }
        return b.toString();
    }

    private static String readAppOpMode(AppOpsManager appOps, String op, int uid, String pkg) {
        if (appOps == null || uid < 0 || pkg == null || pkg.isEmpty()) return "unknown";
        try {
            Object r = HiddenApiReflection.invokeFlexible(appOps, "unsafeCheckOpNoThrow", op, uid, pkg);
            return String.valueOf(r);
        } catch (Throwable first) {
            try {
                Object r = HiddenApiReflection.invokeFlexible(appOps, "checkOpNoThrow", op, uid, pkg);
                return String.valueOf(r);
            } catch (Throwable ignored) {
                return "unknown";
            }
        }
    }

    private static String readStandbyBucket(String pkg, int userId) {
        try {
            Object svc = HiddenApiReflection.invokeFlexible(HiddenApiReflection.classForNameCached("android.os.ServiceManager"), "getService", "usagestats");
            if (svc == null) return "unknown";
            Object iusage = HiddenApiReflection.invokeFlexible(Class.forName("android.app.usage.IUsageStatsManager$Stub"), "asInterface", svc);
            Object r;
            try {
                r = HiddenApiReflection.invokeFlexible(iusage, "getAppStandbyBucket", pkg, null, userId);
            } catch (Throwable first) {
                r = HiddenApiReflection.invokeFlexible(iusage, "getAppStandbyBucket", pkg, userId);
            }
            return String.valueOf(r);
        } catch (Throwable t) {
            return "unknown";
        }
    }

    private static String readHibernationState(String pkg, int userId) {
        try {
            Object svc = HiddenApiReflection.invokeFlexible(HiddenApiReflection.classForNameCached("android.os.ServiceManager"), "getService", "app_hibernation");
            if (svc == null) return "unsupported";
            Object mgr = HiddenApiReflection.invokeFlexible(Class.forName("android.apphibernation.IAppHibernationService$Stub"), "asInterface", svc);
            Object r;
            try { r = HiddenApiReflection.invokeFlexible(mgr, "isHibernatingForUser", pkg, userId); }
            catch (Throwable first) { r = HiddenApiReflection.invokeFlexible(mgr, "isHibernatingForUser", pkg, userId, null); }
            return String.valueOf(r);
        } catch (Throwable t) {
            return "unknown";
        }
    }

    private static String readUnusedAppRestrictions(String pkg, int userId) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
            Object r;
            try { r = HiddenApiReflection.invokeFlexible(pm, "getUnusedAppRestrictionsStatus", pkg); }
            catch (Throwable first) { r = HiddenApiReflection.invokeFlexible(pm, "getUnusedAppRestrictionsStatus", pkg, userId); }
            return String.valueOf(r);
        } catch (Throwable t) {
            return "unknown";
        }
    }

    private static String readBackgroundRestricted(String pkg, int userId) {
        try {
            Object svc = HiddenApiReflection.invokeFlexible(HiddenApiReflection.classForNameCached("android.os.ServiceManager"), "getService", "activity");
            if (svc == null) return "unknown";
            Object am = HiddenApiServices.activity();
            Object r;
            try { r = HiddenApiReflection.invokeFlexible(am, "isBackgroundRestricted", pkg, userId); }
            catch (Throwable first) { return "unknown"; }
            return String.valueOf(r);
        } catch (Throwable t) {
            return "unknown";
        }
    }


    static String uidLiveState(int userId, String[] args, int start) {
        StringBuilder out = new StringBuilder();
        TopSnapshot top = findTopApp(userId);
        boolean uidObserverApi = hasRegisterUidObserverApi();
        if (args == null || args.length <= start) {
            out.append("UID_LIVE_STATE_DONE ok=false reason=empty user=").append(userId)
                    .append(" uidObserverApi=").append(uidObserverApi)
                    .append(" hash=0 planner=0\n");
            return out.toString();
        }
        for (int i = start; i < args.length; i++) {
            String pkg = safePackage(args[i]);
            if (pkg.isEmpty()) continue;
            int uid = resolveTargetUid(userId, pkg);
            List<PidInfo> alive = findAliveProcesses(userId, pkg, uid);
            UidRuntimeSnapshot runtime = runningProcessSnapshot(uid);
            boolean topTarget = isTargetTop(top, pkg);
            boolean active = topTarget || !alive.isEmpty() || runtime.runningCount > 0;
            out.append("UID_LIVE_STATE version=").append(VERSION)
                    .append(" user=").append(userId)
                    .append(" package=").append(pkg)
                    .append(" uid=").append(uid)
                    .append(" active=").append(active)
                    .append(" topTarget=").append(topTarget)
                    .append(" alive=").append(!alive.isEmpty())
                    .append(" aliveCount=").append(alive.size())
                    .append(" alivePids=").append(pidCsv(alive))
                    .append(" runningCount=").append(runtime.runningCount)
                    .append(" runningPids=").append(runtime.pids)
                    .append(" runningNames=").append(runtime.names)
                    .append(" minProcState=").append(runtime.minProcState)
                    .append(" minImportance=").append(runtime.minImportance)
                    .append(" uidObserverApi=").append(uidObserverApi)
                    .append(" event_source=IActivityManager.registerUidObserver-probe+getRunningAppProcesses")
                    .append(" topPackage=").append(top == null ? "" : sanitize(top.packageName))
                    .append(" directTopCheck=1 dumpsys=0 hash=0 planner=0\n");
        }
        return out.toString();
    }

    static String uidObserverProbe() {
        boolean api = hasRegisterUidObserverApi();
        StringBuilder methods = new StringBuilder();
        try {
            Object am = HiddenApiServices.activity();
            java.lang.reflect.Method[] ms = am.getClass().getMethods();
            for (java.lang.reflect.Method m : ms) {
                if (m == null || !"registerUidObserver".equals(m.getName())) continue;
                if (methods.length() > 0) methods.append(',');
                methods.append(m.getName()).append('/').append(m.getParameterTypes().length);
            }
        } catch (Throwable ignored) {}
        return "UID_OBSERVER_PROBE version=" + VERSION
                + " ok=" + api
                + " registerUidObserver=" + api
                + " methods=" + sanitize(methods.toString())
                + " event_source=IActivityManager.registerUidObserver hiddenApi=1 hash=0 planner=0\n";
    }


    static String uidObserverWatch(int userId, String[] args, int start) {
        String pkg = args != null && args.length > start ? safePackage(args[start]) : "";
        int durationMs = args != null && args.length > start + 1 ? parsePositiveInt(args[start + 1], 800) : 800;
        if (durationMs < 100) durationMs = 100;
        if (durationMs > 5000) durationMs = 5000;
        int uid = pkg.isEmpty() ? -1 : resolveTargetUid(userId, pkg);
        StringBuilder out = new StringBuilder();
        out.append("UID_OBSERVER_WATCH_BEGIN version=").append(VERSION)
                .append(" user=").append(userId)
                .append(" package=").append(pkg)
                .append(" uid=").append(uid)
                .append(" durationMs=").append(durationMs)
                .append(" hash=0 planner=0\n");
        if (uid < 0) {
            out.append("UID_OBSERVER_WATCH_DONE ok=false reason=no_uid events=0 hash=0 planner=0\n");
            return out.toString();
        }
        UidObserverLog log = new UidObserverLog(uid, out);
        Object observer = new UidObserverBinder(log);
        boolean registered = false;
        try {
            Object am = HiddenApiServices.activity();
            int flags = 1 | 2 | 4 | 8 | 32;
            try {
                HiddenApiReflection.invokeFlexible(am, "registerUidObserver", observer, flags, -1, "speedbackup");
                registered = true;
            } catch (Throwable first) {
                HiddenApiReflection.invokeFlexible(am, "registerUidObserver", observer, flags, -1, null);
                registered = true;
            }
            try { Thread.sleep(durationMs); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        } catch (Throwable t) {
            out.append("UID_OBSERVER_WATCH_ERROR exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        } finally {
            if (registered) {
                try { HiddenApiReflection.invokeFlexible(HiddenApiServices.activity(), "unregisterUidObserver", observer); } catch (Throwable ignored) {}
            }
        }
        out.append("UID_OBSERVER_WATCH_DONE ok=").append(registered)
                .append(" user=").append(userId)
                .append(" package=").append(pkg)
                .append(" uid=").append(uid)
                .append(" events=").append(log.events.get())
                .append(" registered=").append(registered)
                .append(" event_source=IActivityManager.registerUidObserver")
                .append(" hash=0 planner=0\n");
        return out.toString();
    }

    static String forceStopPackageVerify(int userId, String[] args, int start) {
        long begin = System.currentTimeMillis();
        StringBuilder out = new StringBuilder();
        if (args == null || args.length <= start) {
            return "FORCE_STOP_VERIFY ok=false reason=empty user=" + userId + "\n";
        }
        String pkg = safePackage(args[start]);
        int timeoutMs = 700;
        if (args.length > start + 1) {
            try { timeoutMs = Integer.parseInt(args[start + 1]); } catch (Throwable ignored) {}
        }
        if (timeoutMs < 100) timeoutMs = 100;
        if (timeoutMs > 3000) timeoutMs = 3000;
        if (pkg.isEmpty()) return "FORCE_STOP_VERIFY ok=false reason=bad_package user=" + userId + "\n";
        TopSnapshot beforeTop = findTopApp(userId);
        int uid = resolveTargetUid(userId, pkg);
        List<PidInfo> before = findAliveProcesses(userId, pkg, uid);
        boolean forceStopOk = ActivityCompat.forceStopPackageNoThrow(pkg, userId);
        List<PidInfo> after = findAliveProcesses(userId, pkg, uid);
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (!after.isEmpty() && System.currentTimeMillis() < deadline) {
            try { Thread.sleep(60L); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); break; }
            after = findAliveProcesses(userId, pkg, uid);
        }
        TopSnapshot afterTop = findTopApp(userId);
        boolean ok = forceStopOk && after.isEmpty() && !isTargetTop(afterTop, pkg);
        out.append("FORCE_STOP_VERIFY ok=").append(ok)
                .append(" version=").append(VERSION)
                .append(" user=").append(userId)
                .append(" package=").append(pkg)
                .append(" forceStopOk=").append(forceStopOk)
                .append(" aliveBefore=").append(!before.isEmpty())
                .append(" aliveBeforeCount=").append(before.size())
                .append(" aliveBeforePids=").append(pidCsv(before))
                .append(" aliveAfter=").append(!after.isEmpty())
                .append(" aliveAfterCount=").append(after.size())
                .append(" aliveAfterPids=").append(pidCsv(after))
                .append(" topBefore=").append(beforeTop == null ? "" : sanitize(beforeTop.packageName))
                .append(" topAfter=").append(afterTop == null ? "" : sanitize(afterTop.packageName))
                .append(" topTargetAfter=").append(isTargetTop(afterTop, pkg))
                .append(" directTopCheck=1 dumpsys=0 hash=0 planner=0")
                .append(" elapsedMs=").append(System.currentTimeMillis() - begin)
                .append('\n');
        return out.toString();
    }

    static synchronized String status() {
        StringBuilder out = new StringBuilder();
        out.append("PROCESS_OBSERVER_STATUS total=").append(SESSIONS.size())
                .append(" globalProcessObserver=").append(GLOBAL_PROCESS_OBSERVER_REGISTERED)
                .append(" globalTaskStack=").append(GLOBAL_TASK_STACK_REGISTERED)
                .append(" globalProcessEvents=").append(GLOBAL_PROCESS_EVENTS.get())
                .append(" globalTaskEvents=").append(GLOBAL_TASK_EVENTS.get())
                .append('\n');
        for (Map.Entry<Integer, WatchSession> e : SESSIONS.entrySet()) {
            WatchSession s = e.getValue();
            out.append("PROCESS_OBSERVER_SESSION token=").append(e.getKey())
                    .append(" user=").append(s.userId)
                    .append(" package=").append(s.packageName)
                    .append(" targetUid=").append(s.targetUid)
                    .append(" action=").append(s.action)
                    .append(" wakeBlockMode=").append(s.wakeBlockMode.isEmpty() ? "none" : s.wakeBlockMode)
                    .append(" wakeBlockToken=").append(s.wakeBlockToken)
                    .append(" events=").append(s.events.get())
                    .append(" matches=").append(s.matches.get())
                    .append(" actions=").append(s.actions.get())
                    .append(" taskEvents=").append(s.taskEvents.get())
                    .append(" running=").append(s.running.get())
                    .append('\n');
        }
        return out.toString();
    }

    static String killGuardOnce(int userId, String packageName, String action) {
        StringBuilder out = new StringBuilder();
        String pkg = safePackage(packageName);
        String mode = normalizeAction(action);
        if (pkg.isEmpty()) {
            return "APP_KILL_GUARD_FAILED reason=empty-package\n";
        }
        int uid = resolveTargetUid(userId, pkg);
        GuardResult result = runGuardStop(userId, pkg, uid, mode, "direct", -1, -1, "");
        for (String line : result.lines) {
            out.append(now()).append(' ').append(line).append('\n');
        }
        return out.toString();
    }


    private static void ensureGlobalListeners(WatchSession logSession) throws Exception {
        synchronized (GLOBAL_LOCK) {
            if (!GLOBAL_PROCESS_OBSERVER_REGISTERED) {
                GlobalObserverBinder binder = new GlobalObserverBinder();
                Class<?> iface = HiddenApiReflection.classForNameCached(DESCRIPTOR);
                GLOBAL_PROCESS_OBSERVER = Proxy.newProxyInstance(iface.getClassLoader(), new Class<?>[]{iface}, (proxy, method, args) -> {
                    String name = method == null ? "" : method.getName();
                    if ("asBinder".equals(name)) return binder;
                    if ("toString".equals(name)) return "SpeedBackupGlobalProcessObserver";
                    if ("hashCode".equals(name)) return System.identityHashCode(proxy);
                    if ("equals".equals(name)) return proxy == (args != null && args.length > 0 ? args[0] : null);
                    return null;
                });
                Object am = HiddenApiServices.activity();
                HiddenApiReflection.invokeFlexible(am, "registerProcessObserver", GLOBAL_PROCESS_OBSERVER);
                GLOBAL_PROCESS_OBSERVER_REGISTERED = true;
                if (logSession != null) {
                    logSession.logLine("PROCESS_OBSERVER_GLOBAL_LISTEN_OK event_source=IActivityManager.registerProcessObserver true_event_driven=1 sleep_loop=0 poll_proc=0 lifecycle=daemon-global");
                }
            } else if (logSession != null) {
                logSession.logLine("PROCESS_OBSERVER_GLOBAL_LISTEN_REUSE lifecycle=daemon-global");
            }
            if (!GLOBAL_TASK_STACK_REGISTERED) {
                try {
                    GlobalTaskStackBinder binder = new GlobalTaskStackBinder();
                    Class<?> iface = HiddenApiReflection.classForNameCached(TASK_STACK_DESCRIPTOR);
                    GLOBAL_TASK_STACK_LISTENER = Proxy.newProxyInstance(iface.getClassLoader(), new Class<?>[]{iface}, (proxy, method, args) -> {
                        String name = method == null ? "" : method.getName();
                        if ("asBinder".equals(name)) return binder;
                        if ("toString".equals(name)) return "SpeedBackupGlobalTaskStackListener";
                        if ("hashCode".equals(name)) return System.identityHashCode(proxy);
                        if ("equals".equals(name)) return proxy == (args != null && args.length > 0 ? args[0] : null);
                        return null;
                    });
                    Object atm = activityTaskService();
                    HiddenApiReflection.invokeFlexible(atm, "registerTaskStackListener", GLOBAL_TASK_STACK_LISTENER);
                    GLOBAL_TASK_STACK_REGISTERED = true;
                    if (logSession != null) {
                        logSession.logLine("PROCESS_OBSERVER_TASKSTACK_LISTEN_OK event_source=IActivityTaskManager.registerTaskStackListener true_event_driven=1 poll_proc=0 sleep_loop=0 lifecycle=daemon-global");
                    }
                } catch (Throwable t) {
                    GLOBAL_TASK_STACK_LISTENER = null;
                    GLOBAL_TASK_STACK_REGISTERED = false;
                    if (logSession != null) {
                        logSession.logLine("PROCESS_OBSERVER_TASKSTACK_LISTEN_FAILED exception=" + sanitize(t.getClass().getName())
                                + " message=" + sanitize(t.getMessage()) + " lifecycle=daemon-global");
                    }
                }
            } else if (logSession != null) {
                logSession.logLine("PROCESS_OBSERVER_TASKSTACK_LISTEN_REUSE lifecycle=daemon-global");
            }
        }
    }

    private static WatchSession[] sessionsSnapshot() {
        synchronized (ProcessObserverUtil.class) {
            return SESSIONS.values().toArray(new WatchSession[0]);
        }
    }

    private static void dispatchProcessEvent(String callback, int pid, int uid, String extraKey, String extraValue) {
        dispatchProcessEvent(callback, pid, uid, extraKey, extraValue, -1);
    }

    private static void dispatchProcessEvent(String callback, int pid, int uid, String extraKey, String extraValue, int rawCode) {
        GLOBAL_PROCESS_EVENTS.incrementAndGet();
        WatchSession[] sessions = sessionsSnapshot();
        for (WatchSession session : sessions) {
            try {
                session.onProcessEvent(callback, pid, uid, extraKey, extraValue, rawCode);
            } catch (Throwable t) {
                try {
                    session.logLine("PROCESS_OBSERVER_DISPATCH_ERROR callback=" + sanitize(callback)
                            + " exception=" + sanitize(t.getClass().getName())
                            + " message=" + sanitize(t.getMessage()));
                } catch (Throwable ignored) {}
            }
        }
    }

    private static void dispatchTaskStackEvent(String callback, int code) {
        GLOBAL_TASK_EVENTS.incrementAndGet();
        WatchSession[] sessions = sessionsSnapshot();
        for (WatchSession session : sessions) {
            try {
                session.onTaskStackEvent(callback, code);
            } catch (Throwable t) {
                try {
                    session.logLine("PROCESS_OBSERVER_TASKSTACK_DISPATCH_ERROR callback=" + sanitize(callback)
                            + " code=" + code
                            + " exception=" + sanitize(t.getClass().getName())
                            + " message=" + sanitize(t.getMessage()));
                } catch (Throwable ignored) {}
            }
        }
    }

    private static final class WatchSession {
        final int userId;
        final String packageName;
        final long durationMs;
        final String action;
        final String wakeBlockMode;
        final String logPath;
        final AtomicBoolean running = new AtomicBoolean(false);
        final AtomicInteger events = new AtomicInteger(0);
        final AtomicInteger matches = new AtomicInteger(0);
        final AtomicInteger actions = new AtomicInteger(0);
        final AtomicInteger taskEvents = new AtomicInteger(0);
        final AtomicInteger nativeLogdEvents = new AtomicInteger(0);
        final AtomicInteger nativeLogdMatches = new AtomicInteger(0);
        final AtomicInteger nativeLogdStarts = new AtomicInteger(0);
        final AtomicInteger nativeLogdDeaths = new AtomicInteger(0);
        final List<Integer> cgroupFreezeTokens = new ArrayList<>();
        final List<Integer> cgroupFrozenPids = new ArrayList<>();
        final Map<Integer, List<Integer>> cgroupTokenPids = new HashMap<>();
        final CountDownLatch done = new CountDownLatch(1);
        volatile int targetUid = -1;
        volatile Object observer;
        volatile Object taskStackListener;
        volatile PrintWriter log;
        volatile long lastFinalOkMs = 0L;
        volatile boolean lastTaskStateKnown;
        volatile boolean lastTaskTopTarget;
        volatile boolean lastTaskTargetAlive;
        volatile String lastTaskTopPackage = "";
        volatile int wakeBlockToken = -1;
        volatile int token = -1;
        volatile NativeLogdObserver nativeLogdObserver;
        volatile boolean nativeLogdEnabled = true;
        volatile boolean callbacksReady = false;

        WatchSession(int userId, String packageName, long durationMs, String action, String wakeBlockMode, String logPath) {
            this.userId = userId;
            this.packageName = packageName;
            this.durationMs = durationMs;
            this.nativeLogdEnabled = nativeLogdEnabledFromAction(action);
            this.action = normalizeAction(action);
            this.wakeBlockMode = wakeBlockMode == null ? "" : wakeBlockMode.trim();
            this.logPath = logPath == null ? "" : logPath.trim();
        }

        void startTarget() throws Exception {
            if (packageName.isEmpty()) throw new IllegalArgumentException("packageName is empty");
            targetUid = resolveTargetUid(userId, packageName);
            log = openLog(logPath);
            running.set(true);
            ensureGlobalListeners(this);
            logLine("PROCESS_OBSERVER_LISTEN_OK schema=speedbackup.process_observer.v1 version=" + VERSION
                    + " event_source=RootDaemon.global.IActivityManager.registerProcessObserver true_event_driven=1 sleep_loop=0 poll_proc=0"
                    + " user=" + userId + " package=" + packageName + " targetUid=" + targetUid
                    + " action=" + action
                    + " wakeBlockMode=" + (wakeBlockMode.isEmpty() ? "none" : wakeBlockMode)
                    + " durationMs=" + durationMs + " token=" + token
                    + " lifecycle=global-target");
            startNativeLogdObserverIfAvailable();
            startIntegratedWakeBlockIfNeeded();
            runPreGuardIfNeeded();
            callbacksReady = true;
            logLine("PROCESS_OBSERVER_READY callbacks=enabled lifecycle=global-target wakeBlockMode=" + (wakeBlockMode.isEmpty() ? "none" : wakeBlockMode));
        }

        void await() {
            try { done.await(durationMs, TimeUnit.MILLISECONDS); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        }

        String finish(String reason) {
            running.set(false);
            stopNativeLogdObserverIfNeeded(reason);
            stopIntegratedWakeBlockIfNeeded(reason);
            stopIntegratedCgroupFreezerIfNeeded(reason);
            String summary = "PROCESS_OBSERVER_DONE reason=" + sanitize(reason)
                    + " user=" + userId
                    + " package=" + packageName
                    + " targetUid=" + targetUid
                    + " wakeBlockMode=" + (wakeBlockMode.isEmpty() ? "none" : wakeBlockMode)
                    + " wakeBlockToken=" + wakeBlockToken
                    + " cgroupFreezeTokens=" + cgroupFreezeTokens.size()
                    + " cgroupFrozenPids=" + cgroupFrozenPids.size()
                    + " events=" + events.get()
                    + " matches=" + matches.get()
                    + " actions=" + actions.get()
                    + " taskEvents=" + taskEvents.get()
                    + " nativeLogdEvents=" + nativeLogdEvents.get()
                    + " nativeLogdMatches=" + nativeLogdMatches.get()
                    + " nativeLogdStarts=" + nativeLogdStarts.get()
                    + " nativeLogdDeaths=" + nativeLogdDeaths.get()
                    + " lifecycle=global-target"
                    + " globalProcessObserver=" + GLOBAL_PROCESS_OBSERVER_REGISTERED
                    + " globalTaskStack=" + GLOBAL_TASK_STACK_REGISTERED
                    + "\n";
            logLine(summary.trim());
            if (log != null) {
                try { log.flush(); log.close(); } catch (Throwable ignored) {}
            }
            return summary;
        }

        void onNativeLogdLine(String rawLine) {
            if (!running.get() || rawLine == null || rawLine.trim().isEmpty()) return;
            nativeLogdEvents.incrementAndGet();
            String line = rawLine.trim();
            if (line.startsWith("CGFREEZER_LOGD_WATCH_START")) {
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_START helper=1 detail=" + sanitize(line));
                return;
            }
            if (line.startsWith("CGFREEZER_LOGD_WATCH_DONE")) {
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_DONE helper=1 detail=" + sanitize(line));
                return;
            }
            if (!line.startsWith("CGFREEZER_LOGD_EVENT")) {
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_RAW detail=" + sanitize(line));
                return;
            }
            String type = valueOfLineKey(line, "type");
            int pid = parsePositiveInt(valueOfLineKey(line, "pid"), -1);
            int uid = parsePositiveInt(valueOfLineKey(line, "uid"), -1);
            int eventUser = parsePositiveInt(valueOfLineKey(line, "user"), userIdFromUid(uid));
            int tag = parsePositiveInt(valueOfLineKey(line, "tag"), -1);
            String processName = valueOfLineKey(line, "process").replace('_', ' ');
            // sanitize_print() replaces spaces with underscores, but package processes do not contain spaces; keep exact package tests.
            processName = valueOfLineKey(line, "process");
            boolean userMatches = eventUser == userId;
            boolean nameMatches = processName.equals(packageName) || processName.startsWith(packageName + ":");
            if (!userMatches || !nameMatches) return;
            int matchNo = nativeLogdMatches.incrementAndGet();
            if ("am_proc_start".equals(type)) nativeLogdStarts.incrementAndGet();
            if ("am_proc_died".equals(type)) nativeLogdDeaths.incrementAndGet();
            logLine("PROCESS_OBSERVER_NATIVE_LOGD_DETECTED match=" + matchNo
                    + " type=" + sanitize(type)
                    + " tag=" + tag
                    + " user=" + userId
                    + " eventUser=" + eventUser
                    + " pid=" + pid
                    + " uid=" + uid
                    + " package=" + packageName
                    + " process=" + sanitize(processName));
            if (!callbacksReady) {
                logLine("PROCESS_OBSERVER_BOOTSTRAP_SKIP callback=native-logd-" + sanitize(type)
                        + " pid=" + pid
                        + " uid=" + uid
                        + " reason=callbacks-not-ready");
                return;
            }
            if ("am_proc_start".equals(type)) {
                performAction("native-logd-am_proc_start", pid, uid, processName);
            }
        }

        void onProcessEvent(String callback, int pid, int uid, String extraKey, String extraValue, int rawCode) {
            if (!running.get()) return;
            events.incrementAndGet();
            int eventUser = userIdFromUid(uid);
            String processName = readCmdline(pid);
            boolean uidMatches = targetUid >= 0 && uid == targetUid;
            boolean userMatches = eventUser == userId;
            boolean nameMatches = processName.equals(packageName) || processName.startsWith(packageName + ":");
            boolean matched = uidMatches && userMatches && (nameMatches || processName.isEmpty());
            if (!matched) {
                return;
            }
            int matchNo = matches.incrementAndGet();
            String matchMode = nameMatches ? "uid+process" : "uid-only";
            logLine("PROCESS_OBSERVER_DETECTED match=" + matchNo
                    + " callback=" + callback
                    + (rawCode >= 0 ? " rawCode=" + rawCode : "")
                    + " user=" + userId
                    + " eventUser=" + eventUser
                    + " pid=" + pid
                    + " uid=" + uid
                    + " package=" + packageName
                    + " process=" + sanitize(processName)
                    + " matchMode=" + matchMode
                    + (extraKey == null || extraKey.isEmpty() ? "" : " " + extraKey + "=" + sanitize(extraValue)));
            if (!callbacksReady) {
                logLine("PROCESS_OBSERVER_BOOTSTRAP_SKIP callback=" + sanitize(callback)
                        + " pid=" + pid
                        + " uid=" + uid
                        + " reason=callbacks-not-ready");
                return;
            }
            performAction(callback, pid, uid, processName);
        }

        private synchronized void performAction(String callback, int pid, int uid, String processName) {
            if ("monitor".equals(action) || "log".equals(action)) {
                return;
            }
            int n = actions.incrementAndGet();
            long nowMs = System.currentTimeMillis();
            TopSnapshot top = findTopApp(userId);
            List<PidInfo> alive = findAliveProcesses(userId, packageName, targetUid >= 0 ? targetUid : uid);
            boolean targetTop = top != null && packageName.equals(top.packageName);
            long rawElapsed = lastFinalOkMs > 0L ? nowMs - lastFinalOkMs : Long.MAX_VALUE;
            long elapsed = rawElapsed < 0L ? 0L : rawElapsed;
            if (eventPidAlreadyFrozen(pid)) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n
                        + " DEBOUNCE_SKIP reason=pid-already-cgroup-frozen"
                        + " pid=" + pid
                        + " elapsedMs=" + elapsed
                        + " rawElapsedMs=" + rawElapsed
                        + " alive=" + (!alive.isEmpty())
                        + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                        + " topTarget=" + targetTop
                        + " callback=" + sanitize(callback));
                return;
            }
            if (cgroupFreezerPreferredForAction(packageName, action)) pruneStaleCgroupTokens(alive, callback);
            if (cgroupFreezerPreferredForAction(packageName, action) && pid <= 0 && allAlivePidsAlreadyFrozen(alive)) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n
                        + " PROCESS_OBSERVER_CGROUP_FREEZE_REUSE reason=package-pids-already-frozen"
                        + " pid=-1"
                        + " cgroupTokens=" + cgroupFreezeTokens.size()
                        + " alivePids=" + pidCsv(alive)
                        + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                        + " topTarget=" + targetTop
                        + " callback=" + sanitize(callback)
                        + " mode=r304");
                lastFinalOkMs = System.currentTimeMillis();
                return;
            }
            if (cgroupFreezerPreferredForAction(packageName, action) && pid <= 0 && !targetTop) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n
                        + " PACKAGE_SCOPE_TRIGGER reason=target-alive-not-top-cgroup-freeze"
                        + " pid=-1"
                        + " cgroupTokens=" + cgroupFreezeTokens.size()
                        + " alive=" + (!alive.isEmpty())
                        + " alivePids=" + pidCsv(alive)
                        + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                        + " topTarget=false"
                        + " callback=" + sanitize(callback)
                        + " mode=r304");
            }
            if (cgroupFreezerPreferredForAction(packageName, action) && pid <= 0 && targetTop) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n
                        + " PACKAGE_SCOPE_TRIGGER reason=taskstack-top-target"
                        + " pid=-1 alivePids=" + pidCsv(alive)
                        + " callback=" + sanitize(callback));
            }
            if (lastFinalOkMs > 0L && rawElapsed <= ACTION_DEBOUNCE_MS
                    && alive.isEmpty() && !targetTop) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n
                        + " DEBOUNCE_SKIP reason=recent-final-ok"
                        + " elapsedMs=" + elapsed
                        + " rawElapsedMs=" + rawElapsed
                        + " alive=" + (!alive.isEmpty())
                        + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                        + " topTarget=" + targetTop
                        + " callback=" + sanitize(callback));
                return;
            }
            GuardResult result = runGuardStop(userId, packageName, targetUid >= 0 ? targetUid : uid, action, callback, pid, uid, processName);
            if (result.cgroupToken > 0) {
                cgroupFreezeTokens.add(result.cgroupToken);
                List<Integer> tokenPids = new ArrayList<>();
                if (result.cgroupPid > 0) addFrozenPid(result.cgroupPid, tokenPids);
                for (Integer frozenPid : result.cgroupPids) {
                    if (frozenPid != null && frozenPid > 0) addFrozenPid(frozenPid, tokenPids);
                }
                // r303/r304: pid-scope cgroup freeze may freeze the whole package pid-set, but older
                // bookkeeping recorded only the eventPid. Record the alive pid-set observed just
                // before the freeze too, so the next foreground-service/activity callback reuses
                // the existing token instead of opening another cgroup freezer token for the
                // sibling process such as com.tencent.mobileqq:MSF.
                if (cgroupFreezerPreferredForAction(packageName, action) && alive != null) {
                    for (PidInfo info : alive) {
                        if (info != null && info.pid > 0) addFrozenPid(info.pid, tokenPids);
                    }
                }
                cgroupTokenPids.put(result.cgroupToken, tokenPids);
            }
            if (!result.finalAlive) {
                lastFinalOkMs = System.currentTimeMillis();
            }
            for (String line : result.lines) {
                logLine("PROCESS_OBSERVER_ACTION actionNo=" + n + " " + line);
            }
        }

        private void addFrozenPid(int pid, List<Integer> tokenPids) {
            if (pid <= 0) return;
            if (!cgroupFrozenPids.contains(pid)) cgroupFrozenPids.add(pid);
            if (tokenPids != null && !tokenPids.contains(pid)) tokenPids.add(pid);
        }

        private void pruneStaleCgroupTokens(List<PidInfo> alive, String callback) {
            if (cgroupFreezeTokens.isEmpty() || cgroupTokenPids.isEmpty()) return;
            Set<Integer> aliveSet = new HashSet<>();
            if (alive != null) {
                for (PidInfo info : alive) {
                    if (info != null && info.pid > 0) aliveSet.add(info.pid);
                }
            }
            if (aliveSet.isEmpty()) return;
            List<Integer> staleTokens = new ArrayList<>();
            for (Integer token : new ArrayList<>(cgroupFreezeTokens)) {
                if (token == null || token <= 0) continue;
                List<Integer> pids = cgroupTokenPids.get(token);
                if (pids == null || pids.isEmpty()) continue;
                boolean anyAlive = false;
                for (Integer oldPid : pids) {
                    if (oldPid != null && aliveSet.contains(oldPid)) { anyAlive = true; break; }
                }
                if (!anyAlive) staleTokens.add(token);
            }
            for (Integer token : staleTokens) {
                if (token == null || token <= 0) continue;
                List<Integer> oldPids = cgroupTokenPids.remove(token);
                cgroupFreezeTokens.remove(token);
                if (oldPids != null) {
                    for (Integer oldPid : oldPids) {
                        if (oldPid != null) cgroupFrozenPids.remove(oldPid);
                    }
                }
                String stopResult = CgroupFreezeUtil.stop(token, userId, packageName);
                logLine("PROCESS_OBSERVER_CGROUP_TOKEN_PRUNE reason=stale-frozen-pids-gone"
                        + " token=" + token
                        + " oldPids=" + intPidCsv(oldPids)
                        + " alivePids=" + pidCsv(alive)
                        + " callback=" + sanitize(callback)
                        + " mode=r304"
                        + " result=" + sanitize(stopResult));
            }
        }

        private boolean eventPidAlreadyFrozen(int pid) {
            return pid > 0 && cgroupFrozenPids.contains(pid);
        }

        private boolean allAlivePidsAlreadyFrozen(List<PidInfo> alive) {
            if (alive == null || alive.isEmpty() || cgroupFreezeTokens.isEmpty()) return false;
            for (PidInfo info : alive) {
                if (info == null || info.pid <= 0 || !cgroupFrozenPids.contains(info.pid)) return false;
            }
            return true;
        }

        private synchronized boolean tryFastCgroupFreezeTopTarget(String callback, List<PidInfo> alive) {
            if (!cgroupFreezerPreferredForAction(packageName, action)) return false;
            if (alive == null || alive.isEmpty()) return false;
            pruneStaleCgroupTokens(alive, callback);
            if (allAlivePidsAlreadyFrozen(alive)) {
                logLine("PROCESS_OBSERVER_CGROUP_FREEZE_REUSE reason=top-target-fast-already-frozen"
                        + " package=" + packageName
                        + " tokenCount=" + cgroupFreezeTokens.size()
                        + " alivePids=" + pidCsv(alive)
                        + " callback=" + sanitize(callback)
                        + " mode=r304");
                lastFinalOkMs = System.currentTimeMillis();
                return true;
            }
            long startMs = System.currentTimeMillis();
            String freezeResult = CgroupFreezeUtil.start(userId, packageName, -1, 1000, "processObserver-fast-top");
            int freezeToken = CgroupFreezeUtil.parseToken(freezeResult);
            boolean freezeOk = CgroupFreezeUtil.isStartOk(freezeResult) && freezeToken > 0;
            if (freezeOk) {
                cgroupFreezeTokens.add(freezeToken);
                List<Integer> tokenPids = new ArrayList<>();
                for (PidInfo info : alive) {
                    if (info != null && info.pid > 0) addFrozenPid(info.pid, tokenPids);
                }
                cgroupTokenPids.put(freezeToken, tokenPids);
                lastFinalOkMs = System.currentTimeMillis();
                logLine("PROCESS_OBSERVER_CGROUP_FAST_FREEZE_OK reason=top-target-fast-freeze"
                        + " package=" + packageName
                        + " token=" + freezeToken
                        + " alivePids=" + pidCsv(alive)
                        + " elapsedMs=" + (System.currentTimeMillis() - startMs)
                        + " callback=" + sanitize(callback)
                        + " mode=r304"
                        + " detail=" + sanitize(freezeResult));
                return true;
            }
            logLine("PROCESS_OBSERVER_CGROUP_FAST_FREEZE_FAIL reason=top-target-fast-freeze"
                    + " package=" + packageName
                    + " token=" + freezeToken
                    + " alivePids=" + pidCsv(alive)
                    + " elapsedMs=" + (System.currentTimeMillis() - startMs)
                    + " callback=" + sanitize(callback)
                    + " mode=r304"
                    + " detail=" + sanitize(freezeResult));
            return false;
        }

        private void startNativeLogdObserverIfAvailable() {
            if ("monitor".equals(action) || "log".equals(action)) {
                return;
            }
            if (!nativeLogdEnabled) {
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_SKIP reason=action-nologd optional=1 action=" + sanitize(action));
                return;
            }
            String daemonSocket = CgroupFreezeUtil.nativeDaemonSocketPath();
            String helper = daemonSocket == null || daemonSocket.isEmpty() ? CgroupFreezeUtil.nativeHelperPath() : daemonSocket;
            boolean daemonMode = daemonSocket != null && !daemonSocket.isEmpty();
            if (helper == null || helper.isEmpty()) {
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_UNAVAILABLE reason=no-helper optional=1");
                return;
            }
            try {
                NativeLogdObserver observer = new NativeLogdObserver(this, helper, daemonMode);
                nativeLogdObserver = observer;
                observer.start();
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_LISTEN_OK helper=" + sanitize(helper)
                        + " daemon=" + daemonMode
                        + " event_source=LOG_ID_EVENTS tags=am_proc_start,am_proc_died optional=1");
            } catch (Throwable t) {
                nativeLogdObserver = null;
                logLine("PROCESS_OBSERVER_NATIVE_LOGD_LISTEN_FAILED helper=" + sanitize(helper)
                        + " daemon=" + daemonMode
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage())
                        + " optional=1");
            }
        }

        private void stopNativeLogdObserverIfNeeded(String reason) {
            NativeLogdObserver observer = nativeLogdObserver;
            nativeLogdObserver = null;
            if (observer == null) return;
            String result = observer.stop(reason);
            logLine("PROCESS_OBSERVER_NATIVE_LOGD_STOP reason=" + sanitize(reason)
                    + " result=" + sanitize(result));
        }

        private void startIntegratedWakeBlockIfNeeded() {
            if (wakeBlockMode == null || wakeBlockMode.isEmpty()) {
                return;
            }
            String result = AppWakeBlockUtil.start(userId, packageName, wakeBlockMode, logPath, token, "processObserver");
            wakeBlockToken = result.contains("APP_WAKE_BLOCK_START_OK") ? parseTokenFromLine(result, "token=") : -1;
            logLine("PROCESS_OBSERVER_WAKE_BLOCK_START integrated=1 mode=" + wakeBlockMode
                    + " token=" + wakeBlockToken
                    + " result=" + sanitize(result));
        }

        private void stopIntegratedWakeBlockIfNeeded(String reason) {
            if (wakeBlockToken <= 0) {
                return;
            }
            int token = wakeBlockToken;
            wakeBlockToken = -1;
            String result = AppWakeBlockUtil.stop(token);
            logLine("PROCESS_OBSERVER_WAKE_BLOCK_STOP integrated=1 mode=" + wakeBlockMode
                    + " token=" + token
                    + " reason=" + sanitize(reason)
                    + " result=" + sanitize(result));
        }

        private void stopIntegratedCgroupFreezerIfNeeded(String reason) {
            if (cgroupFreezeTokens.isEmpty()) {
                return;
            }
            List<Integer> tokens = new ArrayList<>(cgroupFreezeTokens);
            cgroupFreezeTokens.clear();
            cgroupFrozenPids.clear();
            cgroupTokenPids.clear();
            for (Integer token : tokens) {
                if (token == null || token <= 0) continue;
                String result = CgroupFreezeUtil.stop(token, userId, packageName);
                logLine("PROCESS_OBSERVER_CGROUP_FREEZER_STOP integrated=1 token=" + token
                        + " reason=" + sanitize(reason)
                        + " result=" + sanitize(result));
            }
        }

        private void runPreGuardIfNeeded() {
            if ("monitor".equals(action) || "log".equals(action)) {
                return;
            }
            int n = actions.incrementAndGet();
            logLine("PROCESS_OBSERVER_PRE_GUARD_SKIP actionNo=" + n
                    + " reason=log-summary-cleanup"
                    + " noForceStop=true"
                    + " noPackageWideToken=true"
                    + " package=" + packageName
                    + " action=" + normalizeAction(action));
        }

        private void registerTaskStackListenerBestEffort() {
            // r111: task stack listener is registered once globally by ensureGlobalListeners().
        }

        void onTaskStackEvent(String callback, int code) {
            if (!running.get()) return;
            taskEvents.incrementAndGet();
            TopSnapshot top = findTopApp(userId);
            List<PidInfo> alive = findAliveProcesses(userId, packageName, targetUid);
            boolean targetTop = top != null && packageName.equals(top.packageName);
            boolean targetAlive = !alive.isEmpty();
            String topPackage = top == null ? "" : top.packageName;
            boolean stateChanged = !lastTaskStateKnown
                    || targetTop != lastTaskTopTarget
                    || targetAlive != lastTaskTargetAlive
                    || !topPackage.equals(lastTaskTopPackage);
            lastTaskStateKnown = true;
            lastTaskTopTarget = targetTop;
            lastTaskTargetAlive = targetAlive;
            lastTaskTopPackage = topPackage;
            if (stateChanged || targetTop || targetAlive) {
                logLine("PROCESS_OBSERVER_TASKSTACK_CHANGED callback=" + sanitize(callback)
                        + " code=" + code
                        + " user=" + userId
                        + " package=" + packageName
                        + " topPackage=" + sanitize(topPackage)
                        + " topActivity=" + (top == null ? "" : sanitize(top.activityName))
                        + " topTarget=" + targetTop
                        + " targetAlive=" + targetAlive
                        + " alivePids=" + pidCsv(alive)
                        + " stateChanged=" + stateChanged);
            }
            if (targetTop) {
                if (!callbacksReady) {
                    logLine("PROCESS_OBSERVER_BOOTSTRAP_SKIP callback=" + sanitize(callback)
                            + " code=" + code
                            + " reason=callbacks-not-ready topTarget=" + targetTop
                            + " targetAlive=" + targetAlive);
                    return;
                }
                // r302: high-risk topTarget uses the shortest cgroup path first, before the heavier
                // guard-stop context collection. If fast freeze is unavailable, fall back to the
                // existing performAction path so safety is not weakened.
                if (tryFastCgroupFreezeTopTarget(callback, alive)) {
                    return;
                }
                performAction(callback, -1, targetUid, topPackage);
            } else if (targetAlive && stateChanged) {
                if (!callbacksReady) {
                    logLine("PROCESS_OBSERVER_BOOTSTRAP_SKIP callback=" + sanitize(callback)
                            + " code=" + code
                            + " reason=callbacks-not-ready targetAlive=true topTarget=false");
                    return;
                }
                logLine("PROCESS_OBSERVER_TASKSTACK_GUARD_ACTION reason=target-alive-not-top"
                        + " package=" + packageName
                        + " alivePids=" + pidCsv(alive)
                        + " callback=" + sanitize(callback)
                        + " mode=r304");
                performAction(callback + "-target-alive-not-top", -1, targetUid, packageName);
            }
        }

        synchronized void logLine(String line) {
            PrintWriter w = log;
            String out = now() + " " + line;
            if (w != null) {
                w.println(out);
                w.flush();
            } else {
                System.out.println(out);
            }
        }
    }

    private static final class NativeLogdObserver {
        final WatchSession session;
        final String helper;
        final boolean daemonMode;
        volatile Process process;
        volatile LocalSocket socket;
        volatile Thread readerThread;
        final AtomicBoolean active = new AtomicBoolean(false);
        final AtomicInteger lines = new AtomicInteger(0);

        NativeLogdObserver(WatchSession session, String helper, boolean daemonMode) {
            this.session = session;
            this.helper = helper;
            this.daemonMode = daemonMode;
        }

        void start() throws Exception {
            long duration = session.durationMs > 0L ? session.durationMs + 5000L : 0L;
            active.set(true);
            final InputStream source;
            if (daemonMode) {
                LocalSocket s = new LocalSocket();
                s.connect(new LocalSocketAddress(helper, LocalSocketAddress.Namespace.FILESYSTEM));
                OutputStream os = s.getOutputStream();
                os.write(("SUBSCRIBE " + session.packageName + " " + session.userId + " " + duration + "\n").getBytes(StandardCharsets.UTF_8));
                os.flush();
                try { s.shutdownOutput(); } catch (Throwable ignored) {}
                socket = s;
                source = s.getInputStream();
            } else {
                ProcessBuilder pb = new ProcessBuilder(helper, "watch-logd", session.packageName, String.valueOf(session.userId), String.valueOf(duration));
                pb.redirectErrorStream(true);
                process = pb.start();
                source = process.getInputStream();
            }
            readerThread = new Thread(() -> {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(source, StandardCharsets.UTF_8))) {
                    String line;
                    while (active.get() && (line = br.readLine()) != null) {
                        lines.incrementAndGet();
                        session.onNativeLogdLine(line);
                    }
                } catch (Throwable t) {
                    if (active.get()) {
                        session.logLine("PROCESS_OBSERVER_NATIVE_LOGD_READER_ERROR exception=" + sanitize(t.getClass().getName())
                                + " message=" + sanitize(t.getMessage())
                                + " daemon=" + daemonMode);
                    }
                }
            }, "speedbackup-native-logd-reader-" + session.token);
            readerThread.setDaemon(true);
            readerThread.start();
        }

        String stop(String reason) {
            active.set(false);
            LocalSocket s = socket;
            if (s != null) {
                try { s.close(); } catch (Throwable ignored) {}
            }
            Process p = process;
            if (p != null) {
                try { p.destroy(); } catch (Throwable ignored) {}
                try { if (!p.waitFor(300, TimeUnit.MILLISECONDS)) p.destroyForcibly(); } catch (Throwable ignored) { try { p.destroyForcibly(); } catch (Throwable ignored2) {} }
            }
            Thread t = readerThread;
            if (t != null) {
                try { t.join(300); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            }
            return "helper=" + sanitize(helper) + " daemon=" + daemonMode + " lines=" + lines.get() + " reason=" + sanitize(reason);
        }
    }

    private static final class PidInfo {
        final int pid;
        final int uid;
        final String processName;

        PidInfo(int pid, int uid, String processName) {
            this.pid = pid;
            this.uid = uid;
            this.processName = processName == null ? "" : processName;
        }
    }

    private static final class GuardResult {
        final List<String> lines = new ArrayList<>();
        final List<Integer> cgroupPids = new ArrayList<>();
        boolean finalAlive;
        int cgroupToken = -1;
        int cgroupPid = -1;
    }

    private static final class TopSnapshot {
        final String packageName;
        final String activityName;
        final String source;
        final String raw;

        TopSnapshot(String packageName, String activityName, String source, String raw) {
            this.packageName = packageName == null ? "" : packageName;
            this.activityName = activityName == null ? "" : activityName;
            this.source = source == null ? "" : source;
            this.raw = raw == null ? "" : raw;
        }
    }

    private static GuardResult runGuardStop(int userId, String packageName, int targetUid, String action,
                                           String callback, int eventPid, int eventUid, String eventProcess) {
        GuardResult result = new GuardResult();
        String normalized = normalizeAction(action);
        boolean cgroupFallbackInstantKill = false;
        int uid = targetUid;
        if (uid < 0) uid = resolveTargetUid(userId, packageName);
        TopSnapshot topBefore = findTopApp(userId);
        List<PidInfo> before = findAliveProcesses(userId, packageName, uid);
        String killState = classifyKillState(topBefore, before, packageName, callback, eventProcess);
        result.lines.add("ACTION_BEGIN action=" + normalized
                + " callback=" + sanitize(callback)
                + " eventPid=" + eventPid
                + " eventUid=" + eventUid
                + " targetUid=" + uid
                + " package=" + packageName
                + " eventProcess=" + sanitize(eventProcess)
                + " killState=" + killState);

        result.lines.add(topLine("before", topBefore, packageName));
        result.lines.add(verifyLine("before", before));
        result.lines.add(killContextLine(killState, topBefore, before, packageName, callback, eventProcess));

        if ("already-dead".equals(killState) && isProcessDiedCallback(callback)
                && (before == null || before.isEmpty())) {
            result.finalAlive = false;
            result.lines.add("ACTION_RESULT stage=already-dead-skip ok=true"
                    + " pid=" + eventPid
                    + " noCgroup=true noForceStop=true"
                    + " reason=dead-event-no-alive");
            result.lines.add("FINAL result=ok alive=false topTarget="
                    + isTargetTop(topBefore, packageName)
                    + " finalStage=already-dead-skip forceStopOk=skipped directKillOk=skipped");
            return result;
        }

        boolean packageScopeTrigger = eventPid <= 0 && before != null && !before.isEmpty()
                && (isTargetTop(topBefore, packageName) || isTargetAliveNotTopCallback(callback));
        if (cgroupFreezerPreferredForAction(packageName, action) && (eventPid > 0 || packageScopeTrigger)) {
            int pidForFreeze = eventPid > 0 ? eventPid : -1;
            String freezeScope = pidForFreeze > 0 ? "pid" : "package";
            String freezeResult = CgroupFreezeUtil.start(userId, packageName, pidForFreeze, 1500, "processObserver-" + freezeScope);
            int freezeToken = CgroupFreezeUtil.parseToken(freezeResult);
            boolean freezeOk = CgroupFreezeUtil.isStartOk(freezeResult) && freezeToken > 0;
            result.lines.add("ACTION_RESULT stage=cgroup-freeze ok=" + freezeOk
                    + " token=" + freezeToken
                    + " pid=" + pidForFreeze
                    + " scope=" + freezeScope
                    + " trigger=" + sanitize(callback)
                    + " detail=" + sanitize(freezeResult));
            if (freezeOk) {
                result.cgroupToken = freezeToken;
                result.cgroupPid = pidForFreeze;
                if (pidForFreeze <= 0) {
                    for (PidInfo info : before) {
                        if (info != null && info.pid > 0 && !result.cgroupPids.contains(info.pid)) result.cgroupPids.add(info.pid);
                    }
                }
                TopSnapshot topAfterFreeze = findTopApp(userId);
                result.lines.add(topLine("after-cgroup-freeze", topAfterFreeze, packageName));
                List<PidInfo> aliveAfterFreeze = findAliveProcesses(userId, packageName, uid);
                result.lines.add(verifyLine("after-cgroup-freeze", aliveAfterFreeze));
                result.finalAlive = false;
                result.lines.add("FINAL result=ok alive=false frozen=true topTarget="
                        + isTargetTop(topAfterFreeze, packageName)
                        + " finalStage=cgroup-freeze scope=" + freezeScope
                        + " token=" + freezeToken
                        + " frozenPids=" + pidCsv(before)
                        + " fallback=not-needed");
                return result;
            }
            // r315: onProcessDied can arrive for a pid that has already vanished while
            // sibling processes of the same high-risk app are still alive.  Freezing the
            // dead event pid returns false and previously fell through to force-stop,
            // even though package-scope cgroup freeze is the desired cgroup-first
            // policy.  Retry a package-scope freeze before any kill/force-stop fallback.
            if (pidForFreeze > 0 && isProcessDiedCallback(callback) && before != null && !before.isEmpty()) {
                String packageFreezeResult = CgroupFreezeUtil.start(userId, packageName, -1, 1500,
                        "processObserver-package-retry-after-dead-pid");
                int packageFreezeToken = CgroupFreezeUtil.parseToken(packageFreezeResult);
                boolean packageFreezeOk = CgroupFreezeUtil.isStartOk(packageFreezeResult) && packageFreezeToken > 0;
                result.lines.add("ACTION_RESULT stage=cgroup-freeze-package-retry ok=" + packageFreezeOk
                        + " token=" + packageFreezeToken
                        + " pid=-1"
                        + " scope=package"
                        + " trigger=" + sanitize(callback)
                        + " reason=dead-event-pid"
                        + " detail=" + sanitize(packageFreezeResult));
                if (packageFreezeOk) {
                    result.cgroupToken = packageFreezeToken;
                    result.cgroupPid = -1;
                    for (PidInfo info : before) {
                        if (info != null && info.pid > 0 && !result.cgroupPids.contains(info.pid)) result.cgroupPids.add(info.pid);
                    }
                    TopSnapshot topAfterPackageFreeze = findTopApp(userId);
                    result.lines.add(topLine("after-cgroup-freeze-package-retry", topAfterPackageFreeze, packageName));
                    List<PidInfo> aliveAfterPackageFreeze = findAliveProcesses(userId, packageName, uid);
                    result.lines.add(verifyLine("after-cgroup-freeze-package-retry", aliveAfterPackageFreeze));
                    result.finalAlive = false;
                    result.lines.add("FINAL result=ok alive=false frozen=true topTarget="
                            + isTargetTop(topAfterPackageFreeze, packageName)
                            + " finalStage=cgroup-freeze-package-retry"
                            + " scope=package"
                            + " token=" + packageFreezeToken
                            + " frozenPids=" + pidCsv(before)
                            + " fallback=not-needed"
                            + " reason=dead-event-pid");
                    return result;
                }
            }
            cgroupFallbackInstantKill = true;
            result.lines.add("CGROUP_FREEZER_FALLBACK reason=unavailable_or_failed next=native-kill-package-live-rescan scope="
                    + freezeScope + " eventPid=" + eventPid
                    + " order=native-kill-pre,force-stop,native-kill-post,dex-escalation"
                    + " killUidFallback=true killProcessGroupFallback=true sigkillPidFallback=true");
        }

        boolean directKillOk = true;
        boolean nativeKillPreAttempted = false;
        boolean nativeKillPreOk = false;
        boolean nativeKillPostAttempted = false;
        boolean nativeKillPostOk = false;
        if (cgroupFallbackInstantKill) {
            nativeKillPreAttempted = true;
            String nativeKillPre = CgroupFreezeUtil.killPackage(userId, packageName, eventPid, 700,
                    "processObserver-pre-force-stop");
            nativeKillPreOk = CgroupFreezeUtil.isNativePackageKillOk(nativeKillPre);
            directKillOk = nativeKillPreOk;
            result.lines.add("ACTION_RESULT stage=native-kill-package-pre-force-stop ok=" + nativeKillPreOk
                    + " eventPid=" + eventPid
                    + " remain=" + CgroupFreezeUtil.nativePackageKillRemain(nativeKillPre)
                    + " detail=" + sanitize(nativeKillPre));
            if (!nativeKillPreOk && eventPid > 0) {
                directKillOk = killEventPid(eventPid);
                result.lines.add("ACTION_RESULT stage=event-sigkill-fallback ok=" + directKillOk
                        + " pid=" + eventPid
                        + " reason=native-kill-package-unavailable-or-failed"
                        + " detail=" + (directKillOk ? "sigkill=ok" : "sigkill=failed"));
            }
        } else if ("kill".equals(normalized) || "kill-stop".equals(normalized)) {
            directKillOk = killEventPid(eventPid);
            result.lines.add("ACTION_RESULT stage=event-sigkill ok=" + directKillOk
                    + " pid=" + eventPid
                    + " detail=" + (directKillOk ? "sigkill=ok" : "sigkill=failed"));
        }

        boolean forceStopOk = true;
        if (usesForceStop(normalized) || cgroupFallbackInstantKill) {
            forceStopOk = ActivityCompat.forceStopPackageNoThrow(packageName, userId);
            result.lines.add("ACTION_RESULT stage=force-stop ok=" + forceStopOk
                    + " package=" + packageName
                    + " detail=forceStop=" + (forceStopOk ? "ok" : "failed"));
        }

        if (cgroupFallbackInstantKill) {
            nativeKillPostAttempted = true;
            String nativeKillPost = CgroupFreezeUtil.killPackage(userId, packageName, -1, 500,
                    "processObserver-post-force-stop");
            nativeKillPostOk = CgroupFreezeUtil.isNativePackageKillOk(nativeKillPost);
            result.lines.add("ACTION_RESULT stage=native-kill-package-post-force-stop ok=" + nativeKillPostOk
                    + " remain=" + CgroupFreezeUtil.nativePackageKillRemain(nativeKillPost)
                    + " detail=" + sanitize(nativeKillPost));
        }

        TopSnapshot topAfterForceStop = findTopApp(userId);
        result.lines.add(topLine(cgroupFallbackInstantKill ? "after-native-kill-post-force-stop" : "after-force-stop",
                topAfterForceStop, packageName));
        List<PidInfo> afterForceStop = findAliveProcesses(userId, packageName, uid);
        result.lines.add(verifyLine(cgroupFallbackInstantKill ? "after-native-kill-post-force-stop" : "after-force-stop",
                afterForceStop));
        if (afterForceStop.isEmpty() && !isTargetTop(topAfterForceStop, packageName)) {
            result.finalAlive = false;
            result.lines.add("FINAL result=ok alive=false topTarget=false finalStage="
                    + (cgroupFallbackInstantKill ? "native-kill-package-post-force-stop" : "force-stop")
                    + " forceStopOk=" + forceStopOk
                    + " directKillOk=" + directKillOk
                    + " nativeKillPreAttempted=" + nativeKillPreAttempted
                    + " nativeKillPreOk=" + nativeKillPreOk
                    + " nativeKillPostAttempted=" + nativeKillPostAttempted
                    + " nativeKillPostOk=" + nativeKillPostOk);
            return result;
        }

        if (usesKillUid(normalized) || cgroupFallbackInstantKill) {
            result.lines.add("ESCALATE from=force-stop to=kill-uid alivePids=" + pidCsv(afterForceStop));
            boolean killUidOk = ActivityCompat.killUidNoThrow(uid, userId, "speedbackup-process-observer");
            result.lines.add("ACTION_RESULT stage=kill-uid ok=" + killUidOk
                    + " uid=" + uid
                    + " detail=killUid=" + (killUidOk ? "ok" : "failed"));
            TopSnapshot topAfterKillUid = findTopApp(userId);
            result.lines.add(topLine("after-kill-uid", topAfterKillUid, packageName));
            List<PidInfo> afterKillUid = findAliveProcesses(userId, packageName, uid);
            result.lines.add(verifyLine("after-kill-uid", afterKillUid));
            if (afterKillUid.isEmpty() && !isTargetTop(topAfterKillUid, packageName)) {
                result.finalAlive = false;
                result.lines.add("FINAL result=ok alive=false topTarget=false finalStage=kill-uid forceStopOk=" + forceStopOk);
                return result;
            }
            afterForceStop = afterKillUid;
        }

        if (usesProcessGroupKill(normalized) || cgroupFallbackInstantKill) {
            result.lines.add("ESCALATE from=kill-uid to=kill-process-group alivePids=" + pidCsv(afterForceStop));
            int okCount = 0;
            int failCount = 0;
            for (PidInfo info : afterForceStop) {
                boolean ok = ActivityCompat.killProcessGroupNoThrow(info.uid, info.pid);
                if (!ok) ok = killPidNoThrow(info.pid);
                if (ok) okCount++; else failCount++;
            }
            result.lines.add("ACTION_RESULT stage=kill-process-group ok=" + (failCount == 0)
                    + " okCount=" + okCount
                    + " failCount=" + failCount);
            TopSnapshot topAfterGroup = findTopApp(userId);
            result.lines.add(topLine("after-kill-process-group", topAfterGroup, packageName));
            List<PidInfo> afterGroup = findAliveProcesses(userId, packageName, uid);
            result.lines.add(verifyLine("after-kill-process-group", afterGroup));
            if (afterGroup.isEmpty() && !isTargetTop(topAfterGroup, packageName)) {
                result.finalAlive = false;
                result.lines.add("FINAL result=ok alive=false topTarget=false finalStage=kill-process-group forceStopOk=" + forceStopOk);
                return result;
            }
            afterForceStop = afterGroup;
        }

        int sigOk = 0;
        int sigFail = 0;
        if (usesPidKillFallback(normalized) || cgroupFallbackInstantKill) {
            result.lines.add("ESCALATE from=kill-process-group to=sigkill-pid alivePids=" + pidCsv(afterForceStop));
            for (PidInfo info : afterForceStop) {
                if (killPidNoThrow(info.pid)) sigOk++; else sigFail++;
            }
            result.lines.add("ACTION_RESULT stage=sigkill-pid ok=" + (sigFail == 0)
                    + " okCount=" + sigOk
                    + " failCount=" + sigFail);
        }
        TopSnapshot topFinal = findTopApp(userId);
        result.lines.add(topLine("final", topFinal, packageName));
        List<PidInfo> finalAlive = findAliveProcesses(userId, packageName, uid);
        result.lines.add(verifyLine("final", finalAlive));
        boolean topFinalTarget = isTargetTop(topFinal, packageName);
        result.finalAlive = !finalAlive.isEmpty() || topFinalTarget;
        result.lines.add("FINAL result=" + (result.finalAlive ? "still-alive" : "ok")
                + " alive=" + result.finalAlive
                + " topTarget=" + topFinalTarget
                + " finalStage=" + ((usesPidKillFallback(normalized) || cgroupFallbackInstantKill) ? "sigkill-pid" : "force-stop")
                + " pids=" + pidCsv(finalAlive)
                + " forceStopOk=" + forceStopOk
                + " nativeKillPreAttempted=" + nativeKillPreAttempted
                + " nativeKillPreOk=" + nativeKillPreOk
                + " nativeKillPostAttempted=" + nativeKillPostAttempted
                + " nativeKillPostOk=" + nativeKillPostOk);
        return result;
    }

    private static boolean isTargetAliveNotTopCallback(String callback) {
        return callback != null && callback.contains("target-alive-not-top");
    }

    private static boolean usesCgroupFreezeAction(String action) {
        String a = normalizeAction(action);
        return "cgroup-freeze".equals(a);
    }

    private static boolean cgroupFreezerPreferredForAction(String packageName, String action) {
        return usesCgroupFreezeAction(action) || cgroupFreezerPreferred(packageName);
    }

    private static boolean cgroupFreezerPreferred(String packageName) {
        // r302: keep cgroup freeze as the primary path only for the hardcoded high-risk set.
        // TOP and targetAlive-not-top task-stack events both use package-scope freeze first;
        // duplicate events reuse existing frozen pid sets to avoid redundant cgroup tokens,
        // while ordinary packages still use immediate force-stop/kill guard.
        if (packageName == null || packageName.isEmpty()) return false;
        switch (packageName) {
            case "com.tencent.mm":
            case "com.tencent.mobileqq":
            case "com.tencent.tim":
            case "com.tencent.wework":
            case "com.eg.android.AlipayGphone":
            case "com.taobao.taobao":
            case "com.ss.android.ugc.aweme":
                return true;
            default:
                return false;
        }
    }

    private static boolean usesForceStop(String action) {
        return "stop-app".equals(action) || "guard-stop".equals(action) || "kill-stop".equals(action) || "guard-kill".equals(action);
    }

    private static boolean usesKillUid(String action) {
        return "guard-stop".equals(action) || "kill-stop".equals(action) || "guard-kill".equals(action);
    }

    private static boolean usesProcessGroupKill(String action) {
        return "guard-stop".equals(action) || "kill-stop".equals(action) || "guard-kill".equals(action) || "kill".equals(action);
    }

    private static boolean usesPidKillFallback(String action) {
        return "guard-stop".equals(action) || "kill-stop".equals(action) || "guard-kill".equals(action) || "kill".equals(action);
    }

    private static boolean killEventPid(int pid) {
        if (pid <= 0) return false;
        return killPidNoThrow(pid);
    }

    private static boolean killPidNoThrow(int pid) {
        if (pid <= 0) return false;
        try {
            Os.kill(pid, OsConstants.SIGKILL);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }



    private static final class UidObserverLog {
        final int targetUid;
        final StringBuilder out;
        final AtomicInteger events = new AtomicInteger(0);
        UidObserverLog(int targetUid, StringBuilder out) { this.targetUid = targetUid; this.out = out; }
        synchronized void event(String name, int uid, int procState, long seq, int capability, boolean disabled) {
            if (uid != targetUid) return;
            events.incrementAndGet();
            out.append("UID_OBSERVER_EVENT name=").append(sanitize(name))
                    .append(" uid=").append(uid)
                    .append(" procState=").append(procState)
                    .append(" seq=").append(seq)
                    .append(" capability=").append(capability)
                    .append(" disabled=").append(disabled)
                    .append(" event_source=IUidObserver")
                    .append('\n');
        }
    }

    private static final class UidObserverBinder extends Binder {
        private static final String UID_DESCRIPTOR = "android.app.IUidObserver";
        private final UidObserverLog log;
        UidObserverBinder(UidObserverLog log) {
            this.log = log;
            attachInterface(null, UID_DESCRIPTOR);
        }
        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            try {
                if (code == INTERFACE_TRANSACTION) {
                    if (reply != null) reply.writeString(UID_DESCRIPTOR);
                    return true;
                }
                try { data.enforceInterface(UID_DESCRIPTOR); } catch (Throwable ignored) {}
                int uid = -1;
                int procState = -1;
                long seq = -1L;
                int capability = -1;
                boolean disabled = false;
                try { uid = data.readInt(); } catch (Throwable ignored) {}
                String name = "code" + code;
                switch (code - IBinder.FIRST_CALL_TRANSACTION) {
                    case 0:
                        name = "onUidGone";
                        try { disabled = data.readInt() != 0; } catch (Throwable ignored) {}
                        break;
                    case 1:
                        name = "onUidActive";
                        break;
                    case 2:
                        name = "onUidIdle";
                        try { disabled = data.readInt() != 0; } catch (Throwable ignored) {}
                        break;
                    case 3:
                        name = "onUidStateChanged";
                        try { procState = data.readInt(); } catch (Throwable ignored) {}
                        try { seq = data.readLong(); } catch (Throwable ignored) {}
                        try { capability = data.readInt(); } catch (Throwable ignored) {}
                        break;
                    case 4:
                        name = "onUidProcAdjChanged";
                        break;
                    default:
                        name = "uidObserverCode" + code;
                        break;
                }
                if (log != null) log.event(name, uid, procState, seq, capability, disabled);
                return true;
            } catch (Throwable ignored) {
                return true;
            }
        }
    }

    private static final class UidRuntimeSnapshot {
        int runningCount = 0;
        int minProcState = Integer.MAX_VALUE;
        int minImportance = Integer.MAX_VALUE;
        String pids = "";
        String names = "";
    }

    private static boolean hasRegisterUidObserverApi() {
        try {
            Object am = HiddenApiServices.activity();
            for (java.lang.reflect.Method m : am.getClass().getMethods()) {
                if (m != null && "registerUidObserver".equals(m.getName())) return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    @SuppressWarnings("unchecked")
    private static List<ActivityManager.RunningAppProcessInfo> getRunningAppProcessesHidden() {
        try {
            Object raw = HiddenApiReflection.invokeFlexible(HiddenApiServices.activity(), "getRunningAppProcesses");
            if (raw instanceof List) return (List<ActivityManager.RunningAppProcessInfo>) raw;
            if (raw != null) {
                Object list = HiddenApiReflection.invokeFlexible(raw, "getList");
                if (list instanceof List) return (List<ActivityManager.RunningAppProcessInfo>) list;
            }
        } catch (Throwable ignored) {}
        return new ArrayList<>();
    }

    private static UidRuntimeSnapshot runningProcessSnapshot(int uid) {
        UidRuntimeSnapshot snap = new UidRuntimeSnapshot();
        if (uid < 0) {
            snap.minProcState = -1;
            snap.minImportance = -1;
            return snap;
        }
        StringBuilder pids = new StringBuilder();
        StringBuilder names = new StringBuilder();
        for (ActivityManager.RunningAppProcessInfo info : getRunningAppProcessesHidden()) {
            if (info == null || info.uid != uid) continue;
            snap.runningCount++;
            if (info.pid > 0) {
                if (pids.length() > 0) pids.append(',');
                pids.append(info.pid);
            }
            if (info.processName != null && !info.processName.isEmpty()) {
                if (names.length() > 0) names.append(',');
                names.append(info.pid).append(':').append(sanitize(info.processName));
            }
            int procState = processStateOf(info);
            if (procState >= 0 && procState < snap.minProcState) snap.minProcState = procState;
            if (info.importance > 0 && info.importance < snap.minImportance) snap.minImportance = info.importance;
        }
        snap.pids = pids.toString();
        snap.names = names.toString();
        if (snap.minProcState == Integer.MAX_VALUE) snap.minProcState = -1;
        if (snap.minImportance == Integer.MAX_VALUE) snap.minImportance = -1;
        return snap;
    }

    private static int processStateOf(ActivityManager.RunningAppProcessInfo info) {
        try {
            java.lang.reflect.Field field = ActivityManager.RunningAppProcessInfo.class.getDeclaredField("processState");
            field.setAccessible(true);
            Object v = field.get(info);
            if (v instanceof Number) return ((Number) v).intValue();
        } catch (Throwable ignored) {}
        return -1;
    }

    private static List<PidInfo> findAliveProcesses(int userId, String packageName, int targetUid) {
        List<PidInfo> list = new ArrayList<>();
        File proc = new File("/proc");
        File[] entries = proc.listFiles();
        if (entries == null) return list;
        for (File entry : entries) {
            String name = entry.getName();
            int pid = parsePositiveInt(name, -1);
            if (pid <= 0) continue;
            int uid = readStatusUid(pid);
            if (uid >= 0 && userIdFromUid(uid) != userId) continue;
            String cmd = readCmdline(pid);
            if (cmd.equals(packageName) || cmd.startsWith(packageName + ":")) {
                list.add(new PidInfo(pid, uid, cmd));
            }
        }
        return list;
    }

    private static int readStatusUid(int pid) {
        File f = new File("/proc/" + pid + "/status");
        try (FileInputStream in = new FileInputStream(f)) {
            byte[] buf = new byte[4096];
            int n = in.read(buf);
            if (n <= 0) return -1;
            String s = new String(buf, 0, n, StandardCharsets.UTF_8);
            int idx = s.indexOf("Uid:");
            if (idx < 0) return -1;
            int end = s.indexOf('\n', idx);
            String line = end >= 0 ? s.substring(idx, end) : s.substring(idx);
            String[] parts = line.trim().split("\\s+");
            if (parts.length >= 2) return parsePositiveInt(parts[1], -1);
        } catch (Throwable ignored) {}
        return -1;
    }


    private static String killContextLine(String killState, TopSnapshot top, List<PidInfo> alive, String packageName,
                                          String callback, String eventProcess) {
        boolean targetTop = isTargetTop(top, packageName);
        return "KILL_CONTEXT killState=" + killState
                + " topTarget=" + targetTop
                + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                + " callback=" + sanitize(callback)
                + " eventProcess=" + sanitize(eventProcess)
                + " alive=" + (alive != null && !alive.isEmpty())
                + " aliveCount=" + (alive == null ? 0 : alive.size())
                + " alivePids=" + pidCsv(alive)
                + " processes=" + processCsv(alive);
    }

    private static boolean isProcessDiedCallback(String callback) {
        return callback != null && callback.contains("ProcessDied");
    }

    private static String classifyKillState(TopSnapshot top, List<PidInfo> alive, String packageName,
                                            String callback, String eventProcess) {
        if (isTargetTop(top, packageName)) return "foreground";
        String cb = callback == null ? "" : callback;
        if (cb.contains("ForegroundActivities")) return "foreground-activity-event";
        if (cb.contains("ForegroundServices")) return "foreground-service-event";
        if (alive == null || alive.isEmpty()) return "already-dead";
        boolean onlySubprocess = true;
        for (PidInfo info : alive) {
            if (info != null && packageName != null && packageName.equals(info.processName)) {
                onlySubprocess = false;
                break;
            }
        }
        if (onlySubprocess) return "background-subprocess";
        return "background";
    }

    private static String verifyLine(String stage, List<PidInfo> alive) {
        return "VERIFY stage=" + stage
                + " alive=" + (!alive.isEmpty())
                + " count=" + alive.size()
                + " pids=" + pidCsv(alive)
                + " processes=" + processCsv(alive);
    }


    private static String intPidCsv(List<Integer> pids) {
        if (pids == null || pids.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (Integer pid : pids) {
            if (pid == null) continue;
            if (sb.length() > 0) sb.append(',');
            sb.append(pid);
        }
        return sb.toString();
    }

    private static String pidCsv(List<PidInfo> alive) {
        if (alive == null || alive.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (PidInfo info : alive) {
            if (sb.length() > 0) sb.append(',');
            sb.append(info.pid);
        }
        return sb.toString();
    }

    private static String processCsv(List<PidInfo> alive) {
        if (alive == null || alive.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (PidInfo info : alive) {
            if (sb.length() > 0) sb.append(',');
            sb.append(info.pid).append(':').append(sanitize(info.processName));
        }
        return sb.toString();
    }

    private static String valueOfLineKey(String line, String key) {
        if (line == null || key == null || key.isEmpty()) return "";
        String prefix = key + "=";
        String[] parts = line.trim().split("\\s+");
        for (String part : parts) {
            if (part != null && part.startsWith(prefix)) return part.substring(prefix.length());
        }
        return "";
    }

    private static int parsePositiveInt(String raw, int fallback) {
        try {
            int value = Integer.parseInt(raw == null ? "" : raw.trim());
            return value > 0 ? value : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static final class GlobalTaskStackBinder extends Binder {
        GlobalTaskStackBinder() {
            attachInterface(null, TASK_STACK_DESCRIPTOR);
        }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            try {
                if (code == INTERFACE_TRANSACTION) {
                    if (reply != null) reply.writeString(TASK_STACK_DESCRIPTOR);
                    return true;
                }
                try {
                    data.enforceInterface(TASK_STACK_DESCRIPTOR);
                } catch (Throwable ignored) {
                    // Some platform builds send compatible task-stack callbacks with shifted payloads.
                }
                dispatchTaskStackEvent("onTaskStackChanged", code);
                return true;
            } catch (Throwable t) {
                System.err.println("PROCESS_OBSERVER_TASKSTACK_TRANSACTION_ERROR code=" + code
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage()));
                return true;
            }
        }
    }

    private static final class GlobalObserverBinder extends Binder {
        private static final int TRANSACTION_onForegroundActivitiesChanged = IBinder.FIRST_CALL_TRANSACTION;
        private static final int TRANSACTION_onForegroundServicesChanged = IBinder.FIRST_CALL_TRANSACTION + 1;
        private static final int TRANSACTION_onProcessDied_or_StateChanged = IBinder.FIRST_CALL_TRANSACTION + 2;
        private static final int TRANSACTION_onProcessDied_v2 = IBinder.FIRST_CALL_TRANSACTION + 3;

        GlobalObserverBinder() {
            attachInterface(null, DESCRIPTOR);
        }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            try {
                if (code == INTERFACE_TRANSACTION) {
                    if (reply != null) reply.writeString(DESCRIPTOR);
                    return true;
                }
                if (code == TRANSACTION_onForegroundActivitiesChanged) {
                    data.enforceInterface(DESCRIPTOR);
                    int pid = data.readInt();
                    int uid = data.readInt();
                    boolean fg = readBooleanCompat(data);
                    dispatchProcessEvent("onForegroundActivitiesChanged", pid, uid, "foreground", String.valueOf(fg), code);
                    return true;
                }
                if (code == TRANSACTION_onForegroundServicesChanged) {
                    data.enforceInterface(DESCRIPTOR);
                    int pid = data.readInt();
                    int uid = data.readInt();
                    int serviceTypes = data.readInt();
                    dispatchProcessEvent("onForegroundServicesChanged", pid, uid, "serviceTypes", String.valueOf(serviceTypes), code);
                    return true;
                }
                if (code == TRANSACTION_onProcessDied_or_StateChanged) {
                    data.enforceInterface(DESCRIPTOR);
                    int pid = data.readInt();
                    int uid = data.readInt();
                    if (safeDataAvail(data) >= 4) {
                        int procState = data.readInt();
                        dispatchProcessEvent("onProcessStateChanged", pid, uid, "procState", String.valueOf(procState), code);
                    } else {
                        dispatchProcessEvent("onProcessDied", pid, uid, "dead", "true", code);
                    }
                    return true;
                }
                if (code == TRANSACTION_onProcessDied_v2) {
                    data.enforceInterface(DESCRIPTOR);
                    int pid = data.readInt();
                    int uid = data.readInt();
                    dispatchProcessEvent("onProcessDied", pid, uid, "dead", "true", code);
                    return true;
                }
            } catch (Throwable t) {
                System.err.println("PROCESS_OBSERVER_TRANSACTION_ERROR code=" + code
                        + " exception=" + sanitize(t.getClass().getName())
                        + " message=" + sanitize(t.getMessage()));
                return true;
            }
            return false;
        }
    }

    private static Object activityTaskService() throws Exception {
        return HiddenApiServices.interfaceService("activity_task", "android.app.IActivityTaskManager$Stub");
    }

    private static TopSnapshot findTopApp(int userId) {
        return findTopAppDirect(userId);
    }

    private static TopSnapshot findTopAppDirect(int userId) {
        Object atm;
        try {
            atm = activityTaskService();
        } catch (Throwable ignored) {
            return null;
        }

        TopSnapshot top = topFromRootTaskInfo(invokeNoThrow(atm, "getFocusedRootTaskInfo"), "activity_task.getFocusedRootTaskInfo", userId);
        if (top != null) return top;

        top = topFromRootTaskInfo(invokeNoThrow(atm, "getFocusedStackInfo"), "activity_task.getFocusedStackInfo", userId);
        if (top != null) return top;

        top = topFromTaskList(invokeNoThrow(atm, "getTasks", 1), "activity_task.getTasks/1", userId);
        if (top != null) return top;
        top = topFromTaskList(invokeNoThrow(atm, "getTasks", 1, false), "activity_task.getTasks/2", userId);
        if (top != null) return top;
        top = topFromTaskList(invokeNoThrow(atm, "getTasks", 1, false, false), "activity_task.getTasks/3", userId);
        if (top != null) return top;
        top = topFromTaskList(invokeNoThrow(atm, "getTasks", 1, false, false, userId), "activity_task.getTasks/4_user", userId);
        if (top != null) return top;
        top = topFromTaskList(invokeNoThrow(atm, "getTasks", 1, false, false, -1), "activity_task.getTasks/4_all", userId);
        if (top != null) return top;

        top = topFromRootTaskList(invokeNoThrow(atm, "getAllRootTaskInfos"), "activity_task.getAllRootTaskInfos", userId);
        if (top != null) return top;
        top = topFromRootTaskList(invokeNoThrow(atm, "getAllStackInfos"), "activity_task.getAllStackInfos", userId);
        return top;
    }

    private static Object invokeNoThrow(Object target, String method, Object... args) {
        try {
            return HiddenApiReflection.invokeFlexible(target, method, args);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static TopSnapshot topFromTaskList(Object value, String source, int userId) {
        if (!(value instanceof List<?>)) return null;
        List<?> list = (List<?>) value;
        for (Object item : list) {
            TopSnapshot top = topFromTaskInfo(item, source, userId);
            if (top != null) return top;
        }
        return null;
    }

    private static TopSnapshot topFromRootTaskList(Object value, String source, int userId) {
        if (!(value instanceof List<?>)) return null;
        List<?> list = (List<?>) value;
        TopSnapshot first = null;
        for (Object item : list) {
            TopSnapshot top = topFromRootTaskInfo(item, source, userId);
            if (top == null) continue;
            if (first == null) first = top;
            Object visible = fieldValueDeep(item, "visible");
            Object focused = fieldValueDeep(item, "focused");
            Object resumed = fieldValueDeep(item, "resumed");
            if (Boolean.TRUE.equals(focused) || Boolean.TRUE.equals(resumed) || Boolean.TRUE.equals(visible)) {
                return top;
            }
        }
        return first;
    }

    private static TopSnapshot topFromTaskInfo(Object info, String source, int userId) {
        if (info == null || !userMatches(info, userId)) return null;
        TopSnapshot top = topFromComponent(fieldValueDeep(info, "topActivity"), source, info);
        if (top != null) return top;
        top = topFromComponent(fieldValueDeep(info, "realActivity"), source, info);
        if (top != null) return top;
        top = topFromComponent(fieldValueDeep(info, "baseActivity"), source, info);
        if (top != null) return top;
        return topFromActivityInfo(fieldValueDeep(info, "topActivityInfo"), source, info);
    }

    private static TopSnapshot topFromRootTaskInfo(Object info, String source, int userId) {
        if (info == null || !userMatches(info, userId)) return null;
        TopSnapshot top = topFromComponent(fieldValueDeep(info, "topActivity"), source, info);
        if (top != null) return top;
        top = topFromActivityInfo(fieldValueDeep(info, "topActivityInfo"), source, info);
        if (top != null) return top;
        top = topFromComponent(fieldValueDeep(info, "realActivity"), source, info);
        if (top != null) return top;
        top = topFromComponent(fieldValueDeep(info, "baseActivity"), source, info);
        if (top != null) return top;
        return topFromTaskInfo(fieldValueDeep(info, "topTask"), source + ".topTask", userId);
    }

    private static TopSnapshot topFromComponent(Object component, String source, Object rawOwner) {
        if (!(component instanceof android.content.ComponentName)) return null;
        android.content.ComponentName cn = (android.content.ComponentName) component;
        String pkg = cn.getPackageName();
        if (pkg == null || pkg.trim().isEmpty() || pkg.startsWith("android.")) return null;
        return new TopSnapshot(pkg, cn.flattenToShortString(), source, rawSummary(rawOwner));
    }

    private static TopSnapshot topFromActivityInfo(Object info, String source, Object rawOwner) {
        if (info == null) return null;
        Object packageName = fieldValueDeep(info, "packageName");
        Object name = fieldValueDeep(info, "name");
        if (!(packageName instanceof String) || ((String) packageName).trim().isEmpty()) return null;
        String pkg = (String) packageName;
        if (pkg.startsWith("android.")) return null;
        String activity = name instanceof String && !((String) name).trim().isEmpty() ? pkg + "/" + name : pkg;
        return new TopSnapshot(pkg, activity, source + ".activityInfo", rawSummary(rawOwner));
    }

    private static boolean userMatches(Object info, int userId) {
        if (userId < 0 || info == null) return true;
        Integer taskUser = intFieldDeep(info, "userId");
        if (taskUser == null) taskUser = intFieldDeep(info, "mUserId");
        return taskUser == null || taskUser == userId;
    }

    private static Integer intFieldDeep(Object target, String name) {
        Object value = fieldValueDeep(target, name);
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Number) return ((Number) value).intValue();
        return null;
    }

    private static Object fieldValueDeep(Object target, String name) {
        if (target == null || name == null) return null;
        Class<?> c = target.getClass();
        while (c != null) {
            try {
                java.lang.reflect.Field f = c.getDeclaredField(name);
                f.setAccessible(true);
                return f.get(target);
            } catch (Throwable ignored) {
                c = c.getSuperclass();
            }
        }
        return null;
    }

    private static String rawSummary(Object value) {
        if (value == null) return "";
        String raw;
        try {
            raw = String.valueOf(value);
        } catch (Throwable ignored) {
            raw = value.getClass().getName();
        }
        raw = raw.replace('\n', ' ').replace('\r', ' ').trim();
        return raw.length() > 240 ? raw.substring(0, 240) : raw;
    }

    private static boolean isTargetTop(TopSnapshot top, String packageName) {
        return top != null && packageName != null && packageName.equals(top.packageName);
    }

    private static String topLine(String stage, TopSnapshot top, String packageName) {
        boolean targetTop = isTargetTop(top, packageName);
        return "TOP_CHECK stage=" + stage
                + " topPackage=" + (top == null ? "" : sanitize(top.packageName))
                + " topActivity=" + (top == null ? "" : sanitize(top.activityName))
                + " topTarget=" + targetTop
                + " source=" + (top == null ? "none" : sanitize(top.source));
    }

    private static int resolveTargetUid(int userId, String packageName) {
        try {
            String status = AppInventoryUtil.packageStatusSingle(userId, packageName, true);
            JsonObject o = JsonParser.parseString(status.trim()).getAsJsonObject();
            if (o.has("uid")) return o.get("uid").getAsInt();
        } catch (Throwable ignored) {}
        return -1;
    }

    private static String readCmdline(int pid) {
        if (pid <= 0) return "";
        File f = new File("/proc/" + pid + "/cmdline");
        try (FileInputStream in = new FileInputStream(f)) {
            byte[] buf = new byte[512];
            int n = in.read(buf);
            if (n <= 0) return "";
            int len = 0;
            while (len < n && buf[len] != 0) len++;
            return new String(buf, 0, len, StandardCharsets.UTF_8).trim();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static int userIdFromUid(int uid) {
        if (uid >= 100000) return uid / 100000;
        return 0;
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

    private static String normalizeAction(String action) {
        String a = action == null ? "monitor" : action.trim().toLowerCase(Locale.ROOT);
        a = stripRuntimeSuffix(a);
        a = stripWakeBlockSuffix(a);
        if (a.equals("log")) return "log";
        if (a.equals("monitor")) return "monitor";
        if (a.equals("freeze") || a.equals("cgroup-freeze") || a.equals("guard-freeze") || a.equals("freeze-cgroup")) return "cgroup-freeze";
        if (a.equals("stop") || a.equals("stop-app") || a.equals("force-stop")) return "stop-app";
        if (a.equals("guard") || a.equals("guard-stop") || a.equals("verify-stop") || a.equals("stop-guard")) return "guard-stop";
        if (a.equals("kill")) return "kill";
        if (a.equals("kill-stop") || a.equals("kill_force_stop")) return "kill-stop";
        if (a.equals("guard-kill") || a.equals("hard") || a.equals("hard-stop")) return "guard-kill";
        return "monitor";
    }

    private static String wakeBlockModeFromAction(String action) {
        String a = action == null ? "" : action.trim().toLowerCase(Locale.ROOT);
        a = stripRuntimeSuffix(a);
        if (a.isEmpty() || a.equals("monitor") || a.equals("log")) return "";
        if (a.contains("restricted") || a.contains("restrict") || a.contains("wake-block")) return "restricted";
        if (a.contains("appops") || a.contains("wake-appops") || a.contains("bg-deny")) return "appops";
        if (a.endsWith("-wake") || a.endsWith("+wake") || a.endsWith(":wake") || a.contains("integrated-wake")) return "normal";
        return "";
    }


    private static boolean nativeLogdEnabledFromAction(String action) {
        String a = action == null ? "" : action.trim().toLowerCase(Locale.ROOT);
        return !(a.contains(":nologd") || a.contains("+nologd") || a.contains("-nologd") || a.contains("_nologd")
                || a.contains(":no-logd") || a.contains("+no-logd") || a.contains("-no-logd") || a.contains("_no_logd"));
    }

    private static String stripRuntimeSuffix(String action) {
        String a = action == null ? "monitor" : action.trim().toLowerCase(Locale.ROOT);
        String[] suffixes = new String[]{
                ":nologd", "+nologd", "-nologd", "_nologd",
                ":no-logd", "+no-logd", "-no-logd", "_no_logd"
        };
        boolean changed;
        do {
            changed = false;
            for (String suffix : suffixes) {
                if (a.endsWith(suffix)) {
                    a = a.substring(0, a.length() - suffix.length());
                    changed = true;
                }
            }
        } while (changed);
        return a;
    }

    private static String stripWakeBlockSuffix(String action) {
        String a = action == null ? "monitor" : action.trim().toLowerCase(Locale.ROOT);
        String[] suffixes = new String[]{
                ":restricted", "+restricted", "-restricted", "_restricted",
                ":restrict", "+restrict", "-restrict", "_restrict",
                ":appops", "+appops", "-appops", "_appops",
                ":wake-appops", "+wake-appops", "-wake-appops", "_wake_appops",
                ":wake-block", "+wake-block", "-wake-block", "_wake_block",
                ":wake", "+wake", "-wake", "_wake",
                ":bg-deny", "+bg-deny", "-bg-deny", "_bg_deny"
        };
        boolean changed;
        do {
            changed = false;
            for (String suffix : suffixes) {
                if (a.endsWith(suffix)) {
                    a = a.substring(0, a.length() - suffix.length());
                    changed = true;
                }
            }
        } while (changed);
        return a;
    }

    private static int parseTokenFromLine(String text, String key) {
        if (text == null || key == null) return -1;
        int idx = text.indexOf(key);
        if (idx < 0) return -1;
        idx += key.length();
        int end = idx;
        while (end < text.length()) {
            char c = text.charAt(end);
            if (c < '0' || c > '9') break;
            end++;
        }
        if (end <= idx) return -1;
        try { return Integer.parseInt(text.substring(idx, end)); } catch (Throwable ignored) { return -1; }
    }

    private static boolean readBooleanCompat(Parcel data) {
        try { return data.readInt() != 0; } catch (Throwable ignored) { return false; }
    }

    private static int safeDataAvail(Parcel data) {
        try { return data.dataAvail(); } catch (Throwable ignored) { return 0; }
    }

    private static String now() {
        try { return TS.format(new Date()); } catch (Throwable ignored) { return String.valueOf(System.currentTimeMillis()); }
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        String v = raw.replace('\n', ' ').replace('\r', ' ').replace('\0', ' ');
        return v.length() > 220 ? v.substring(0, 220) : v;
    }
}
