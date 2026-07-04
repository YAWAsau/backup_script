package com.xayah.dex.compat;

import android.app.AppOpsManagerHidden;

import java.util.Set;

/**
 * Version-tolerant AppOps APIs.
 *
 * Design follows the Rikka HiddenApi style: keep Android/ROM signature drift,
 * reflection fallback and package-scoped safety rules in this compat layer, not
 * in HiddenApiUtil command routing.
 */
public final class AppOpsCompat {
    private AppOpsCompat() {
    }

    public interface OpNameResolver {
        String getPublicName(int op);
    }

    /**
     * package-scoped reset signature cache.
     * 0=unknown, 1=resetAllModes(userId, packageName),
     * 2=resetAllModes(packageName, userId), -1=unsupported.
     *
     * Intentionally never falls back to whole-user resetAllModes: that can reset
     * unrelated packages on Android 16 / vendor ROMs.
     */
    private static int sPackageScopedResetSignature = 0;

    public static final class ResetResult {
        public final boolean ok;
        public final String method;
        public final String signature;
        public final boolean cached;
        public final boolean safePackageScoped;
        public final boolean cachedUnsupported;
        public final Throwable error;

        ResetResult(boolean ok, String method, String signature, boolean cached,
                    boolean safePackageScoped, boolean cachedUnsupported, Throwable error) {
            this.ok = ok;
            this.method = method;
            this.signature = signature;
            this.cached = cached;
            this.safePackageScoped = safePackageScoped;
            this.cachedUnsupported = cachedUnsupported;
            this.error = error;
        }

        public static ResetResult ok(String signature, boolean cached) {
            return new ResetResult(true, "resetAllModes", signature, cached, true, false, null);
        }

        public static ResetResult unsupported(Throwable error) {
            return new ResetResult(false, "resetAllModes", "unsupported", false, true, true, error);
        }
    }

    public static void setUidMode(AppOpsManagerHidden appOpsManager, int op, int uid, int mode,
                                  OpNameResolver resolver) throws Exception {
        try {
            HiddenApiReflection.invokeFlexible(appOpsManager, "setUidMode", op, uid, mode);
            return;
        } catch (Throwable first) {
            CompatDebug.throwable("setUidMode(int,int,int)", first);
        }
        try {
            String publicName = resolver != null ? resolver.getPublicName(op) : AppOpsManagerHidden.opToPublicName(op);
            HiddenApiReflection.invokeFlexible(appOpsManager, "setUidMode", publicName, uid, mode);
        } catch (Throwable second) {
            CompatDebug.throwable("setUidMode(String,int,int)", second);
            if (second instanceof Exception) {
                throw (Exception) second;
            }
            throw new Exception(second);
        }
    }

    public static Integer tryGetPackageModeRaw(AppOpsManagerHidden appOpsManager, int op, int uid, String packageName) {
        try {
            Object value = HiddenApiReflection.invokeFlexible(appOpsManager, "checkOpRawNoThrow", op, uid, packageName);
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable ignored) {
        }
        try {
            Object value = HiddenApiReflection.invokeFlexible(appOpsManager, "unsafeCheckOpRawNoThrow", op, uid, packageName);
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    public static Integer tryGetUidModeRaw(AppOpsManagerHidden appOpsManager, int op, int uid,
                                           OpNameResolver resolver) {
        try {
            Object value = HiddenApiReflection.invokeFlexible(appOpsManager, "getUidMode", op, uid);
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable ignored) {
        }
        try {
            String publicName = resolver != null ? resolver.getPublicName(op) : AppOpsManagerHidden.opToPublicName(op);
            Object value = HiddenApiReflection.invokeFlexible(appOpsManager, "getUidMode", publicName, uid);
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    public static int getPackageModeRaw(AppOpsManagerHidden appOpsManager, int op, int uid, String packageName,
                                        int fallbackMode) {
        Integer current = tryGetPackageModeRaw(appOpsManager, op, uid, packageName);
        return current != null ? current : fallbackMode;
    }

    public static int getUidModeRaw(AppOpsManagerHidden appOpsManager, int op, int uid, OpNameResolver resolver) {
        Integer current = tryGetUidModeRaw(appOpsManager, op, uid, resolver);
        return current != null ? current : -999;
    }

    public static void setPackageModeIfNeeded(AppOpsManagerHidden appOpsManager, int op, int uid,
                                              String packageName, int mode) {
        Integer current = tryGetPackageModeRaw(appOpsManager, op, uid, packageName);
        if (current != null && current == mode) {
            return;
        }
        appOpsManager.setMode(op, uid, packageName, mode);
    }

    public static void setUidModeIfNeeded(AppOpsManagerHidden appOpsManager, int op, int uid, int mode,
                                          OpNameResolver resolver) throws Exception {
        Integer current = tryGetUidModeRaw(appOpsManager, op, uid, resolver);
        if (current != null && current == mode) {
            return;
        }
        setUidMode(appOpsManager, op, uid, mode, resolver);
    }

    public static void clearPackageMode(AppOpsManagerHidden appOpsManager, int op, int uid, String packageName) {
        setPackageModeIfNeeded(appOpsManager, op, uid, packageName, AppOpsManagerHidden.MODE_DEFAULT);
    }

    public static void setRuntimePermissionUidMode(AppOpsManagerHidden appOpsManager, int op, int uid, int mode,
                                                   String packageName, OpNameResolver resolver) throws Exception {
        // Runtime/privacy-backed ops must be authoritative at uid scope. Always clear
        // stale package mode first to avoid package+uid double state pollution.
        try {
            clearPackageMode(appOpsManager, op, uid, packageName);
        } catch (Throwable throwable) {
            CompatDebug.throwable("clear package mode before runtime uid op", throwable);
        }
        setUidModeIfNeeded(appOpsManager, op, uid, mode, resolver);
    }

    public static ResetResult resetPackageModesSafe(AppOpsManagerHidden appOpsManager, int userId, String packageName) {
        if (sPackageScopedResetSignature == -1) {
            return ResetResult.unsupported(null);
        }

        int failedCachedSignature = 0;
        Throwable last = null;

        if (sPackageScopedResetSignature == 1) {
            try {
                HiddenApiReflection.invokeFlexible(appOpsManager, "resetAllModes", userId, packageName);
                return ResetResult.ok("user_pkg", true);
            } catch (Throwable throwable) {
                last = throwable;
                failedCachedSignature = 1;
                sPackageScopedResetSignature = 0;
                CompatDebug.throwable("cached resetAllModes(userId,packageName)", throwable);
            }
        } else if (sPackageScopedResetSignature == 2) {
            try {
                HiddenApiReflection.invokeFlexible(appOpsManager, "resetAllModes", packageName, userId);
                return ResetResult.ok("pkg_user", true);
            } catch (Throwable throwable) {
                last = throwable;
                failedCachedSignature = 2;
                sPackageScopedResetSignature = 0;
                CompatDebug.throwable("cached resetAllModes(packageName,userId)", throwable);
            }
        }

        if (failedCachedSignature != 1) {
            try {
                HiddenApiReflection.invokeFlexible(appOpsManager, "resetAllModes", userId, packageName);
                sPackageScopedResetSignature = 1;
                return ResetResult.ok("user_pkg", false);
            } catch (Throwable throwable) {
                last = throwable;
                CompatDebug.throwable("resetAllModes(userId,packageName)", throwable);
            }
        }

        if (failedCachedSignature != 2) {
            try {
                HiddenApiReflection.invokeFlexible(appOpsManager, "resetAllModes", packageName, userId);
                sPackageScopedResetSignature = 2;
                return ResetResult.ok("pkg_user", false);
            } catch (Throwable throwable) {
                last = throwable;
                CompatDebug.throwable("resetAllModes(packageName,userId)", throwable);
            }
        }

        sPackageScopedResetSignature = -1;
        return ResetResult.unsupported(last);
    }

    public static int resetKnownOpsToDefault(AppOpsManagerHidden appOpsManager, int uid, String packageName,
                                             Set<Integer> ops, OpNameResolver resolver) {
        if (ops == null || ops.isEmpty()) {
            return 0;
        }
        int changed = 0;
        for (Integer opObject : ops) {
            if (opObject == null || opObject == AppOpsManagerHidden.OP_NONE) {
                continue;
            }
            int op = opObject;
            try {
                setPackageModeIfNeeded(appOpsManager, op, uid, packageName, AppOpsManagerHidden.MODE_DEFAULT);
                changed++;
            } catch (Throwable throwable) {
                CompatDebug.throwable("fallback reset package op=" + op + " package=" + packageName, throwable);
            }
            try {
                setUidModeIfNeeded(appOpsManager, op, uid, AppOpsManagerHidden.MODE_DEFAULT, resolver);
            } catch (Throwable throwable) {
                CompatDebug.throwable("fallback reset uid op=" + op + " package=" + packageName, throwable);
            }
        }
        return changed;
    }
}
