package com.xayah.dex.compat;

import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.UserHandle;
import android.os.UserHandleHidden;

/** Version-tolerant permission APIs. */
public final class PermissionCompat {
    private PermissionCompat() {
    }

    public static int getPermissionFlags(PackageManagerHidden packageManager, String packageName,
                                         String permissionName, int userId) {
        try {
            Object value = HiddenApiReflection.invokeFlexible(packageManager, "getPermissionFlags",
                    permissionName, packageName, UserHandleHidden.of(userId));
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable first) {
            CompatDebug.throwable("getPermissionFlags(perm,pkg,user) " + packageName + " " + permissionName, first);
        }
        try {
            Object value = HiddenApiReflection.invokeFlexible(packageManager, "getPermissionFlags",
                    packageName, permissionName, userId);
            if (value instanceof Integer) {
                return (Integer) value;
            }
        } catch (Throwable second) {
            CompatDebug.throwable("getPermissionFlags(pkg,perm,userId) " + packageName + " " + permissionName, second);
        }
        return 0;
    }

    public static void updatePermissionFlags(PackageManagerHidden packageManager, String packageName,
                                             String permissionName, int mask, int values,
                                             int userId, UserHandle user) throws Exception {
        try {
            HiddenApiReflection.invokeFlexible(packageManager, "updatePermissionFlags",
                    permissionName, packageName, mask, values, user);
            return;
        } catch (Throwable first) {
            CompatDebug.throwable("updatePermissionFlags(perm,pkg,mask,values,user) " + packageName + " " + permissionName, first);
        }
        try {
            HiddenApiReflection.invokeFlexible(packageManager, "updatePermissionFlags",
                    packageName, permissionName, mask, values, false, userId);
        } catch (Throwable second) {
            CompatDebug.throwable("updatePermissionFlags(pkg,perm,mask,values,false,userId) " + packageName + " " + permissionName, second);
            if (second instanceof Exception) {
                throw (Exception) second;
            }
            throw new Exception(second);
        }
    }

    public static int packageManagerFlag(String fieldName, int fallback) {
        return HiddenApiReflection.intField(PackageManager.class, fieldName, fallback);
    }
}
