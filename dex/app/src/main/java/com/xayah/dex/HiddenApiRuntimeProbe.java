package com.xayah.dex;

import android.os.Build;

import com.xayah.dex.compat.HiddenApiReflection;
import com.xayah.dex.compat.HiddenApiServices;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/** Runtime hidden/non-SDK API probe for SpeedBackup capability diagnostics. */
final class HiddenApiRuntimeProbe {
    static final String VERSION = "v1.4-r334-observer-version-procsnap-runtime-probe";

    private HiddenApiRuntimeProbe() {}

    static String run(int userId, String packageName) {
        StringBuilder out = new StringBuilder();
        boolean bootstrapOk = false;
        try {
            bootstrapOk = HiddenApiBypassBridge.installExemptionsOnce();
        } catch (Throwable ignored) {}
        out.append("HIDDEN_API_BOOTSTRAP source=AndroidHiddenApiBypass")
                .append(" ok=").append(bootstrapOk)
                .append(" required=false softGate=true")
                .append(" sdk=").append(Build.VERSION.SDK_INT)
                .append(' ')
                .append(HiddenApiBypassBridge.statusLine())
                .append('\n');

        probeClass(out, "dalvik.system.VMRuntime");
        probeMethod(out, "dalvik.system.VMRuntime", "getRuntime", 0);
        probeMethod(out, "dalvik.system.VMRuntime", "setHiddenApiExemptions", 1);
        probeService(out, "activity", "android.app.IActivityManager$Stub");
        probeClass(out, "android.app.IActivityManager");
        probeMethod(out, "android.app.IActivityManager", "registerProcessObserver", 1);
        probeMethod(out, "android.app.IActivityManager", "unregisterProcessObserver", 1);
        probeMethod(out, "android.app.IActivityManager", "forceStopPackage", 2);
        probeMethod(out, "android.app.IActivityManager", "forceStopPackage", 3);
        probeMethod(out, "android.app.IActivityManager", "killUid", 2);
        probeMethod(out, "android.app.IActivityManager", "killUid", 3);
        probeService(out, "activity_task", "android.app.IActivityTaskManager$Stub");
        probeClass(out, "android.app.IActivityTaskManager");
        probeMethod(out, "android.app.IActivityTaskManager", "registerTaskStackListener", 1);
        probeMethod(out, "android.app.IActivityTaskManager", "unregisterTaskStackListener", 1);
        probeClass(out, "android.app.AppOpsManager");
        probeMethod(out, "android.app.AppOpsManager", "setMode", 4);
        probeMethod(out, "android.app.AppOpsManager", "setUidMode", 3);
        probeMethod(out, "android.app.AppOpsManager", "getUidMode", 2);
        probeClass(out, "android.app.usage.UsageStatsManager");
        probeMethod(out, "android.app.usage.UsageStatsManager", "setAppStandbyBucket", 2);
        probeMethod(out, "android.app.usage.UsageStatsManager", "setAppStandbyBucket", 3);
        if (packageName != null && !packageName.trim().isEmpty()) {
            String pkg = safePackage(packageName);
            probeShell(out, "cmd_appops_get_run_any", "cmd appops get --user " + userId + " " + shellQuote(pkg) + " RUN_ANY_IN_BACKGROUND");
            probeShell(out, "am_get_standby_bucket", "am get-standby-bucket --user " + userId + " " + shellQuote(pkg));
        }
        out.append("HIDDEN_API_PROBE_DONE version=").append(VERSION)
                .append(" bootstrapOk=").append(bootstrapOk)
                .append(" bootstrapRequired=false functionalGate=true")
                .append(" sdk=").append(Build.VERSION.SDK_INT)
                .append('\n');
        return out.toString();
    }

    private static void probeClass(StringBuilder out, String className) {
        try {
            Class<?> cls = HiddenApiReflection.classForNameCached(className);
            out.append("HIDDEN_API_PROBE type=class name=").append(className)
                    .append(" ok=").append(cls != null)
                    .append(" exception=\n");
        } catch (Throwable t) {
            out.append("HIDDEN_API_PROBE type=class name=").append(className)
                    .append(" ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
    }

    private static void probeService(StringBuilder out, String serviceName, String stubClassName) {
        try {
            Object service = HiddenApiServices.interfaceService(serviceName, stubClassName);
            out.append("HIDDEN_API_PROBE type=service name=").append(serviceName)
                    .append(" stub=").append(stubClassName)
                    .append(" ok=").append(service != null)
                    .append(" exception=\n");
        } catch (Throwable t) {
            out.append("HIDDEN_API_PROBE type=service name=").append(serviceName)
                    .append(" stub=").append(stubClassName)
                    .append(" ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
    }

    private static void probeMethod(StringBuilder out, String className, String methodName, int arity) {
        try {
            Class<?> cls = HiddenApiReflection.classForNameCached(className);
            Method method = findMethod(cls, methodName, arity);
            out.append("HIDDEN_API_PROBE type=method class=").append(className)
                    .append(" method=").append(methodName)
                    .append(" arity=").append(arity)
                    .append(" ok=").append(method != null)
                    .append(method == null ? " exception=NoSuchMethod" : " exception=")
                    .append('\n');
        } catch (Throwable t) {
            out.append("HIDDEN_API_PROBE type=method class=").append(className)
                    .append(" method=").append(methodName)
                    .append(" arity=").append(arity)
                    .append(" ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        }
    }

    private static Method findMethod(Class<?> cls, String name, int arity) {
        for (Method m : cls.getMethods()) {
            if (m.getName().equals(name) && m.getParameterTypes().length == arity) return m;
        }
        for (Method m : cls.getDeclaredMethods()) {
            if (m.getName().equals(name) && m.getParameterTypes().length == arity) {
                try { m.setAccessible(true); } catch (Throwable ignored) {}
                return m;
            }
        }
        return null;
    }

    private static void probeShell(StringBuilder out, String name, String command) {
        Process process = null;
        try {
            process = new ProcessBuilder("sh", "-c", command).redirectErrorStream(true).start();
            StringBuilder raw = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                int lines = 0;
                while ((line = reader.readLine()) != null && lines < 12) {
                    if (raw.length() > 0) raw.append(" | ");
                    raw.append(line);
                    lines++;
                }
            }
            boolean finished = process.waitFor(2500L, TimeUnit.MILLISECONDS);
            int rc = finished ? process.exitValue() : 124;
            out.append("HIDDEN_API_PROBE type=shell name=").append(name)
                    .append(" ok=").append(rc == 0)
                    .append(" rc=").append(rc)
                    .append(" raw=").append(sanitize(raw.toString())).append('\n');
        } catch (Throwable t) {
            out.append("HIDDEN_API_PROBE type=shell name=").append(name)
                    .append(" ok=false exception=").append(sanitize(t.getClass().getName()))
                    .append(" message=").append(sanitize(t.getMessage())).append('\n');
        } finally {
            if (process != null) {
                try { process.destroy(); } catch (Throwable ignored) {}
            }
        }
    }

    private static String safePackage(String packageName) {
        if (packageName == null) return "";
        String p = packageName.trim();
        if (p.indexOf('\n') >= 0 || p.indexOf('\r') >= 0 || p.indexOf('\0') >= 0) return "";
        return p;
    }

    private static String shellQuote(String raw) {
        if (raw == null) return "''";
        return "'" + raw.replace("'", "'\\''") + "'";
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        String v = raw.replace('\n', ' ').replace('\r', ' ').replace('\0', ' ');
        return v.length() > 260 ? v.substring(0, 260) : v;
    }
}
