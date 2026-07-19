package com.xayah.dex;

import android.app.AppOpsManagerHidden;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.Build;

import com.xayah.dex.compat.HiddenApiReflection;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Shared Google package readiness snapshot used by install diagnostics and AppState verification. */
final class GooglePackageSnapshot {
    interface PackageInfoReader {
        PackageInfo get(PackageManagerHidden pmHidden, String packageName, int flags, int userId) throws Throwable;
    }

    String state = "missing";
    String enabledState = "missing";
    String uid = "null";
    String versionCode = "null";
    String runInBackgroundMode = "null";
    String runAnyInBackgroundMode = "null";
    String deviceIdleWhitelist = "false";

    private static final Map<String, Integer> OP_CACHE = new HashMap<>();

    static GooglePackageSnapshot collect(PackageManager realPm,
                                         PackageManagerHidden pmHidden,
                                         AppOpsManagerHidden appOps,
                                         Set<String> idleWhitelist,
                                         int userId,
                                         String packageName) {
        return collect(realPm, pmHidden, appOps, idleWhitelist, userId, packageName,
                (hidden, pkg, flags, user) -> hidden.getPackageInfoAsUser(pkg, flags, user));
    }

    static GooglePackageSnapshot collect(PackageManager realPm,
                                         PackageManagerHidden pmHidden,
                                         AppOpsManagerHidden appOps,
                                         Set<String> idleWhitelist,
                                         int userId,
                                         String packageName,
                                         PackageInfoReader reader) {
        GooglePackageSnapshot out = new GooglePackageSnapshot();
        try {
            PackageInfo info = reader == null
                    ? pmHidden.getPackageInfoAsUser(packageName, 0, userId)
                    : reader.get(pmHidden, packageName, 0, userId);
            if (info == null || info.applicationInfo == null) return out;
            out.state = info.applicationInfo.enabled ? "installed_enabled" : "installed_disabled";
            out.uid = String.valueOf(info.applicationInfo.uid);
            out.versionCode = String.valueOf(longVersionCode(info));
            try {
                out.enabledState = String.valueOf(realPm.getApplicationEnabledSetting(packageName));
            } catch (Throwable ignored) {
                out.enabledState = info.applicationInfo.enabled ? "0" : "unknown";
            }
            int runInBackground = resolveOp("android:run_in_background");
            int runAnyInBackground = resolveOp("android:run_any_in_background");
            if (runInBackground != AppOpsManagerHidden.OP_NONE) {
                out.runInBackgroundMode = String.valueOf(getEffectiveOpMode(
                        appOps, runInBackground, info.applicationInfo.uid, packageName));
            }
            if (runAnyInBackground != AppOpsManagerHidden.OP_NONE) {
                out.runAnyInBackgroundMode = String.valueOf(getEffectiveOpMode(
                        appOps, runAnyInBackground, info.applicationInfo.uid, packageName));
            }
            out.deviceIdleWhitelist = String.valueOf(idleWhitelist != null && idleWhitelist.contains(packageName));
        } catch (Throwable ignored) {
            // missing / inaccessible
        }
        return out;
    }

    private static long longVersionCode(PackageInfo packageInfo) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return packageInfo.getLongVersionCode();
        } catch (Throwable ignored) {
        }
        return packageInfo.versionCode;
    }

    private static int getEffectiveOpMode(AppOpsManagerHidden appOps, int op, int uid, String packageName) {
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
}
