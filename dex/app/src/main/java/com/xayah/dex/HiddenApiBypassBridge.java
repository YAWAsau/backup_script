package com.xayah.dex;

import android.os.Build;

import org.lsposed.hiddenapibypass.HiddenApiBypass;

import java.lang.reflect.Method;
import java.util.Locale;

/**
 * One-shot hidden API exemption gate.
 *
 * This deliberately never throws to callers: existing Refine/SDK stub routes must remain usable even
 * on ROMs where the upstream bypass is blocked or unavailable.  Enable HIDDENAPI_DEBUG=1 to print the
 * underlying failure reason to stderr.
 */
public final class HiddenApiBypassBridge {
    public static final String VERSION = "lsposed-hiddenapibypass-6.1";

    private static final Object LOCK = new Object();
    private static volatile boolean attempted;
    private static volatile boolean enabled;
    private static volatile String mode = "not-attempted";
    private static volatile String reason = "";

    private HiddenApiBypassBridge() {
    }

    public static boolean installExemptionsOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            attempted = true;
            enabled = true;
            mode = "pre-p-no-enforcement";
            reason = "sdk=" + Build.VERSION.SDK_INT;
            return true;
        }
        if (attempted) {
            return enabled;
        }
        synchronized (LOCK) {
            if (attempted) {
                return enabled;
            }
            attempted = true;
            Throwable last = null;
            try {
                boolean ok = HiddenApiBypass.setHiddenApiExemptions("");
                enabled = ok;
                mode = ok ? "lsposed" : "lsposed-returned-false";
                reason = ok ? "ok" : "setHiddenApiExemptions returned false";
                return ok;
            } catch (Throwable t) {
                last = t;
                debug("LSPosed HiddenApiBypass failed", t);
            }
            try {
                boolean ok = installViaVmRuntimeReflection();
                enabled = ok;
                mode = ok ? "vmruntime-reflection-fallback" : "vmruntime-reflection-returned-false";
                reason = ok ? "ok" : "fallback returned false";
                return ok;
            } catch (Throwable t) {
                last = t;
                debug("VMRuntime fallback failed", t);
            }
            enabled = false;
            mode = "failed";
            reason = last == null ? "unknown" : sanitize(last.getClass().getSimpleName() + ":" + last.getMessage());
            return false;
        }
    }

    public static String statusLine() {
        return "HIDDEN_API_BYPASS attempted=" + attempted
                + " enabled=" + enabled
                + " mode=" + sanitize(mode)
                + " version=" + VERSION
                + " sdk=" + Build.VERSION.SDK_INT
                + " reason=" + sanitize(reason);
    }

    public static void printStatus() {
        installExemptionsOnce();
        System.out.println(statusLine());
    }

    private static boolean installViaVmRuntimeReflection() throws Exception {
        Class<?> vmRuntimeClass = Class.forName("dalvik.system.VMRuntime");
        Method getRuntime = vmRuntimeClass.getDeclaredMethod("getRuntime");
        getRuntime.setAccessible(true);
        Object runtime = getRuntime.invoke(null);
        Method setHiddenApiExemptions = vmRuntimeClass.getDeclaredMethod("setHiddenApiExemptions", String[].class);
        setHiddenApiExemptions.setAccessible(true);
        setHiddenApiExemptions.invoke(runtime, (Object) new String[]{""});
        return true;
    }

    private static void debug(String context, Throwable t) {
        if (!isDebug()) {
            return;
        }
        System.err.println("[HiddenApiBypassBridge][DEBUG] " + context + ": "
                + t.getClass().getName() + (t.getMessage() != null ? ": " + sanitize(t.getMessage()) : ""));
    }

    private static boolean isDebug() {
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

    private static String sanitize(String value) {
        if (value == null || value.isEmpty()) {
            return "";
        }
        StringBuilder out = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c >= 0x21 && c <= 0x7e) {
                out.append(c);
            } else {
                out.append('_');
            }
        }
        return out.toString();
    }
}
