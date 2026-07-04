package com.xayah.dex.compat;

/** ActivityManager hidden APIs used by backup soft-freeze. */
public final class ActivityCompat {
    private ActivityCompat() {
    }

    public static void forceStopPackage(String packageName, int userId) throws Exception {
        Object activity = HiddenApiServices.activity();
        try {
            HiddenApiReflection.invokeFlexible(activity, "forceStopPackage", packageName, userId);
            return;
        } catch (Throwable first) {
            CompatDebug.throwable("forceStopPackage(pkg,userId)", first);
        }
        // Some vendor builds keep reason/flags variants. Try common extended forms without changing caller output.
        try {
            HiddenApiReflection.invokeFlexible(activity, "forceStopPackage", packageName, userId, "speedbackup");
            return;
        } catch (Throwable second) {
            CompatDebug.throwable("forceStopPackage(pkg,userId,reason)", second);
            if (second instanceof Exception) {
                throw (Exception) second;
            }
            throw new Exception(second);
        }
    }

    public static boolean forceStopPackageNoThrow(String packageName, int userId) {
        try {
            forceStopPackage(packageName, userId);
            return true;
        } catch (Throwable throwable) {
            CompatDebug.throwable("forceStopPackageNoThrow " + packageName + " user=" + userId, throwable);
            return false;
        }
    }
}
