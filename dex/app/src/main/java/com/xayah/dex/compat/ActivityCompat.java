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

    public static void killUid(int uid, int userId, String reason) throws Exception {
        Object activity = HiddenApiServices.activity();
        int appId = uid % 100000;
        String why = reason == null || reason.trim().isEmpty() ? "speedbackup" : reason;
        try {
            HiddenApiReflection.invokeFlexible(activity, "killUid", appId, userId, why);
            return;
        } catch (Throwable first) {
            CompatDebug.throwable("killUid(appId,userId,reason)", first);
        }
        try {
            HiddenApiReflection.invokeFlexible(activity, "killUid", uid, why);
            return;
        } catch (Throwable second) {
            CompatDebug.throwable("killUid(uid,reason)", second);
            if (second instanceof Exception) {
                throw (Exception) second;
            }
            throw new Exception(second);
        }
    }

    public static boolean killUidNoThrow(int uid, int userId, String reason) {
        if (uid <= 0) return false;
        try {
            killUid(uid, userId, reason);
            return true;
        } catch (Throwable throwable) {
            CompatDebug.throwable("killUidNoThrow uid=" + uid + " user=" + userId, throwable);
            return false;
        }
    }

    public static boolean killProcessGroupNoThrow(int uid, int pid) {
        if (uid <= 0 || pid <= 0) return false;
        try {
            Object rc = HiddenApiReflection.invokeFlexible(
                    HiddenApiReflection.classForNameCached("android.os.Process"),
                    "killProcessGroup", uid, pid);
            if (rc instanceof Integer) {
                return ((Integer) rc) == 0;
            }
            return true;
        } catch (Throwable first) {
            CompatDebug.throwable("killProcessGroup(uid,pid)", first);
        }
        try {
            Object rc = HiddenApiReflection.invokeFlexible(
                    HiddenApiReflection.classForNameCached("android.os.Process"),
                    "killProcessGroup", uid, pid, android.system.OsConstants.SIGKILL);
            if (rc instanceof Integer) {
                return ((Integer) rc) == 0;
            }
            return true;
        } catch (Throwable second) {
            CompatDebug.throwable("killProcessGroup(uid,pid,signal)", second);
            return false;
        }
    }

}
