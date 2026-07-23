package com.xayah.dex;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManagerHidden;
import android.os.Build;
import android.os.HandlerThread;
import android.os.Process;
import android.system.ErrnoException;
import android.system.Os;
import android.system.StructStat;

import com.android.providers.settings.SettingsState;
import com.android.providers.settings.SettingsStateApi26;
import com.android.providers.settings.SettingsStateApi31;

import java.io.File;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Pattern;

/** Internal SSAID storage adapter used only by the canonical AppState engine. */
final class SsaidUtil {
    private static final String SSAID_USER_KEY = "userkey";
    private static final String READBACK_SOURCE = "file-settingsstate-readback";
    private static final Pattern SSAID_16_HEX = Pattern.compile("^[0-9a-f]{16}$");

    private static final int SYSTEM_UID = 1000;
    private static final int SYSTEM_GID = 1000;
    private static final int SSAID_FILE_MODE = 0600;

    /** One SettingsState/HandlerThread per Android user for the daemon lifetime. */
    private static final Map<Integer, SsaidStateHolder> STATE_CACHE = new HashMap<>();

    static final class SsaidAccessInfo {
        final int userId;
        final String packageName;
        final int uid;
        final String keyName;
        final String filePath;
        final String readbackSource;
        final boolean providerEffectiveReadback;

        SsaidAccessInfo(int userId, String packageName, int uid, String keyName, String filePath) {
            this.userId = userId;
            this.packageName = packageName;
            this.uid = uid;
            this.keyName = keyName;
            this.filePath = filePath;
            this.readbackSource = READBACK_SOURCE;
            this.providerEffectiveReadback = false;
        }

        String compact() {
            return "userId=" + userId
                    + " uid=" + uid
                    + " uidKey=" + keyName
                    + " file=" + filePath
                    + " readbackSource=" + readbackSource
                    + " providerEffectiveReadback=" + providerEffectiveReadback;
        }
    }

    static final class FileMetadata {
        final String path;
        final boolean exists;
        final boolean statOk;
        final int uid;
        final int gid;
        final int mode;
        final long size;
        final long mtimeSec;
        final boolean contextOk;
        final String context;
        final String error;

        FileMetadata(String path, boolean exists, boolean statOk, int uid, int gid,
                     int mode, long size, long mtimeSec, boolean contextOk,
                     String context, String error) {
            this.path = path;
            this.exists = exists;
            this.statOk = statOk;
            this.uid = uid;
            this.gid = gid;
            this.mode = mode;
            this.size = size;
            this.mtimeSec = mtimeSec;
            this.contextOk = contextOk;
            this.context = context == null ? "" : context;
            this.error = error == null ? "" : error;
        }

        static FileMetadata capture(File file) {
            String path = file.getAbsolutePath();
            boolean exists = file.exists();
            String context = "";
            boolean contextOk = false;
            String contextError = "";
            try {
                context = getFileContext(path);
                contextOk = context != null && !context.isEmpty();
            } catch (Throwable e) {
                contextError = e.getClass().getSimpleName() + ":" + e.getMessage();
            }
            try {
                StructStat st = Os.stat(path);
                return new FileMetadata(path, exists, true, st.st_uid, st.st_gid,
                        st.st_mode, st.st_size, st.st_mtime, contextOk, context, contextError);
            } catch (ErrnoException e) {
                return new FileMetadata(path, exists, false, -1, -1, -1, -1L, -1L,
                        contextOk, context, e.getClass().getSimpleName() + ":" + e.getMessage());
            } catch (Throwable e) {
                return new FileMetadata(path, exists, false, -1, -1, -1, -1L, -1L,
                        contextOk, context, e.getClass().getSimpleName() + ":" + e.getMessage());
            }
        }

        int unixModeOnly() {
            return statOk ? (mode & 07777) : -1;
        }

        boolean ownerModeSame(FileMetadata other) {
            if (other == null) return false;
            if (!statOk || !other.statOk) return false;
            return uid == other.uid && gid == other.gid && unixModeOnly() == other.unixModeOnly();
        }

        boolean contextSame(FileMetadata other) {
            if (other == null) return false;
            if (!contextOk || !other.contextOk) return false;
            return Objects.equals(context, other.context);
        }

        String compact() {
            StringBuilder out = new StringBuilder();
            if (!statOk) {
                out.append("exists=").append(exists).append(" stat=fail error=").append(error);
            } else {
                out.append("exists=").append(exists)
                        .append(" uid=").append(uid)
                        .append(" gid=").append(gid)
                        .append(" mode=0").append(Integer.toOctalString(mode))
                        .append(" unixMode=0").append(Integer.toOctalString(unixModeOnly()))
                        .append(" size=").append(size)
                        .append(" mtime=").append(mtimeSec);
            }
            if (contextOk) {
                out.append(" context=").append(context);
            } else if (!error.isEmpty()) {
                // stat error already printed above; leave context unavailable implicit.
            }
            return out.toString();
        }
    }

    static final class MetadataRestoreResult {
        final boolean attempted;
        final boolean chownAttempted;
        final boolean chmodAttempted;
        final boolean contextAttempted;
        final boolean chownOk;
        final boolean chmodOk;
        final boolean contextOk;
        final int targetUid;
        final int targetGid;
        final int targetMode;
        final String targetContext;
        final String reason;
        final String error;

        MetadataRestoreResult(boolean attempted, boolean chownAttempted, boolean chmodAttempted,
                              boolean contextAttempted, boolean chownOk, boolean chmodOk,
                              boolean contextOk, int targetUid, int targetGid, int targetMode,
                              String targetContext, String reason, String error) {
            this.attempted = attempted;
            this.chownAttempted = chownAttempted;
            this.chmodAttempted = chmodAttempted;
            this.contextAttempted = contextAttempted;
            this.chownOk = chownOk;
            this.chmodOk = chmodOk;
            this.contextOk = contextOk;
            this.targetUid = targetUid;
            this.targetGid = targetGid;
            this.targetMode = targetMode;
            this.targetContext = targetContext == null ? "" : targetContext;
            this.reason = reason == null ? "" : reason;
            this.error = error == null ? "" : error;
        }

        static MetadataRestoreResult skipped(String reason) {
            return new MetadataRestoreResult(false, false, false, false, false, false, false,
                    -1, -1, -1, "", reason, "");
        }

        String compact() {
            if (!attempted) return "attempted=false reason=" + reason;
            return "attempted=true"
                    + " reason=" + reason
                    + " targetUid=" + targetUid
                    + " targetGid=" + targetGid
                    + " targetMode=0" + Integer.toOctalString(targetMode)
                    + " chown=" + (chownAttempted ? chownOk : "skip")
                    + " chmod=" + (chmodAttempted ? chmodOk : "skip")
                    + " context=" + (contextAttempted ? contextOk : "skip")
                    + (targetContext.isEmpty() ? "" : " targetContext=" + targetContext)
                    + (error.isEmpty() ? "" : " error=" + error);
        }
    }

    static final class SsaidWriteResult {
        final SsaidAccessInfo accessInfo;
        final String expected;
        final String readBack;
        final FileMetadata beforeMeta;
        final FileMetadata afterWriteMeta;
        final MetadataRestoreResult metadataRestore;
        final FileMetadata afterMeta;

        SsaidWriteResult(SsaidAccessInfo accessInfo, String expected, String readBack,
                         FileMetadata beforeMeta, FileMetadata afterWriteMeta,
                         MetadataRestoreResult metadataRestore, FileMetadata afterMeta) {
            this.accessInfo = accessInfo;
            this.expected = expected;
            this.readBack = readBack;
            this.beforeMeta = beforeMeta;
            this.afterWriteMeta = afterWriteMeta;
            this.metadataRestore = metadataRestore;
            this.afterMeta = afterMeta;
        }

        boolean readbackMatched() {
            return expected != null && expected.equals(normalizeSsaidOrNull(readBack));
        }

        String compactDetails() {
            StringBuilder out = new StringBuilder();
            out.append(accessInfo.compact());
            out.append(" expected=").append(expected);
            out.append(" actual=").append(safe(readBack));
            out.append(" metadataOwnerModeSame=").append(beforeMeta.ownerModeSame(afterMeta));
            out.append(" metadataContextSame=").append(beforeMeta.contextSame(afterMeta));
            out.append(" metadataChangedByWrite=").append(!beforeMeta.ownerModeSame(afterWriteMeta));
            out.append(" metadataRestore={").append(metadataRestore.compact()).append('}');
            out.append(" beforeMeta={").append(beforeMeta.compact()).append('}');
            out.append(" afterWriteMeta={").append(afterWriteMeta.compact()).append('}');
            out.append(" afterMeta={").append(afterMeta.compact()).append('}');
            return out.toString();
        }
    }

    private static final class SsaidStateHolder {
        final Object lock;
        final HandlerThread thread;
        final SettingsState state;
        final File file;

        SsaidStateHolder(Object lock, HandlerThread thread, SettingsState state, File file) {
            this.lock = lock;
            this.thread = thread;
            this.state = state;
            this.file = file;
        }
    }

    private SsaidUtil() {
    }

    static String normalizeSsaidForRestore(String value) {
        String normalized = normalizeSsaidOrNull(value);
        if (normalized == null) {
            throw new IllegalArgumentException("invalid SSAID format: expected exactly 16 hex chars");
        }
        return normalized;
    }

    static String normalizeSsaidOrNull(String value) {
        if (value == null) return null;
        String normalized = value.trim().toLowerCase(Locale.US);
        return SSAID_16_HEX.matcher(normalized).matches() ? normalized : null;
    }

    private static synchronized SsaidStateHolder getSettingsStateHolder(int userId) {
        SsaidStateHolder cached = STATE_CACHE.get(userId);
        if (cached != null) return cached;

        Object lock = new Object();
        HandlerThread thread = new HandlerThread(
                "appstate_ssaid_u" + userId, Process.THREAD_PRIORITY_BACKGROUND);
        thread.start();
        File file = ssaidFile(userId);
        int key = SettingsState.makeKey(SettingsState.SETTINGS_TYPE_SSAID, userId);
        SettingsState settingsState;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            settingsState = new SettingsStateApi31(
                    lock, file, key, SettingsState.MAX_BYTES_PER_APP_PACKAGE_UNLIMITED,
                    thread.getLooper());
        } else {
            settingsState = new SettingsStateApi26(
                    lock, file, key, SettingsState.MAX_BYTES_PER_APP_PACKAGE_UNLIMITED,
                    thread.getLooper());
        }
        SsaidStateHolder holder = new SsaidStateHolder(lock, thread, settingsState, file);
        STATE_CACHE.put(userId, holder);
        return holder;
    }

    static SsaidAccessInfo resolveAccessInfo(int userId, String packageName,
                                             PackageManagerHidden pmHidden) throws Exception {
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId);
        int uid = packageInfo.applicationInfo.uid;
        String keyName = getName(packageName, uid);
        return new SsaidAccessInfo(userId, packageName, uid, keyName, ssaidFile(userId).getAbsolutePath());
    }

    static String readSsaidValue(int userId, String packageName,
                                 PackageManagerHidden pmHidden) throws Exception {
        SsaidAccessInfo accessInfo = resolveAccessInfo(userId, packageName, pmHidden);
        SsaidStateHolder holder = getSettingsStateHolder(userId);
        synchronized (holder.lock) {
            SettingsState.Setting setting = holder.state.getSettingLocked(accessInfo.keyName);
            return setting == null ? null : setting.getValue();
        }
    }

    static SsaidWriteResult writeSsaidValue(int userId, String packageName, String ssaid,
                                            PackageManagerHidden pmHidden) throws Exception {
        String normalized = normalizeSsaidForRestore(ssaid);
        SsaidAccessInfo accessInfo = resolveAccessInfo(userId, packageName, pmHidden);
        SsaidStateHolder holder = getSettingsStateHolder(userId);
        FileMetadata beforeMeta = FileMetadata.capture(holder.file);
        String readBack;
        synchronized (holder.lock) {
            holder.state.insertSettingLocked(
                    accessInfo.keyName, normalized, null, true, packageName);
            SettingsState.Setting setting = holder.state.getSettingLocked(accessInfo.keyName);
            readBack = setting == null ? null : setting.getValue();
        }
        FileMetadata afterWriteMeta = FileMetadata.capture(holder.file);
        MetadataRestoreResult restore = restoreFileMetadata(holder.file, beforeMeta, afterWriteMeta);
        FileMetadata afterMeta = FileMetadata.capture(holder.file);
        return new SsaidWriteResult(accessInfo, normalized, readBack, beforeMeta, afterWriteMeta, restore, afterMeta);
    }

    private static MetadataRestoreResult restoreFileMetadata(File file, FileMetadata before, FileMetadata afterWrite) {
        if (before == null || afterWrite == null || !afterWrite.statOk) {
            return MetadataRestoreResult.skipped("metadata unavailable");
        }
        int targetUid = before.statOk ? before.uid : SYSTEM_UID;
        int targetGid = before.statOk ? before.gid : SYSTEM_GID;
        int targetMode = before.statOk ? before.unixModeOnly() : SSAID_FILE_MODE;
        String targetContext = before.contextOk ? before.context : "";
        String reason = "preserve-before";

        // 438 exposed that root/app_process AtomicFile writes can flip settings_ssaid.xml
        // from system:system 0600 to root:root 0644.  If the previous run already left
        // that suspicious state behind, self-heal this known SettingsProvider file to the
        // normal Android data-system metadata instead of preserving the damaged metadata.
        if (looksLikeRootOwnedPublicSettingsFile(before)) {
            targetUid = SYSTEM_UID;
            targetGid = SYSTEM_GID;
            targetMode = SSAID_FILE_MODE;
            reason = "self-heal-root-owned-settings_ssaid";
        }
        if (targetMode < 0) targetMode = SSAID_FILE_MODE;

        boolean needChown = targetUid >= 0 && targetGid >= 0
                && (afterWrite.uid != targetUid || afterWrite.gid != targetGid);
        boolean needChmod = targetMode >= 0 && afterWrite.unixModeOnly() != targetMode;
        boolean needContext = !targetContext.isEmpty()
                && (!afterWrite.contextOk || !Objects.equals(afterWrite.context, targetContext));

        if (!needChown && !needChmod && !needContext) {
            return MetadataRestoreResult.skipped("already-matches");
        }

        boolean chownOk = false;
        boolean chmodOk = false;
        boolean contextOk = false;
        String error = "";
        String path = file.getAbsolutePath();
        try {
            if (needChown) {
                Os.chown(path, targetUid, targetGid);
                chownOk = true;
            }
        } catch (Throwable e) {
            error += "chown:" + e.getClass().getSimpleName() + ":" + e.getMessage() + ";";
        }
        try {
            if (needChmod) {
                Os.chmod(path, targetMode);
                chmodOk = true;
            }
        } catch (Throwable e) {
            error += "chmod:" + e.getClass().getSimpleName() + ":" + e.getMessage() + ";";
        }
        try {
            if (needContext) {
                contextOk = setFileContext(path, targetContext);
                if (!contextOk) contextOk = restorecon(path);
            }
        } catch (Throwable e) {
            error += "context:" + e.getClass().getSimpleName() + ":" + e.getMessage() + ";";
        }
        return new MetadataRestoreResult(true, needChown, needChmod, needContext,
                chownOk, chmodOk, contextOk, targetUid, targetGid, targetMode,
                targetContext, reason, error);
    }

    private static boolean looksLikeRootOwnedPublicSettingsFile(FileMetadata meta) {
        if (meta == null || !meta.statOk) return false;
        return meta.path.endsWith("/settings_ssaid.xml")
                && meta.uid == 0 && meta.gid == 0
                && (meta.unixModeOnly() == 0644 || meta.unixModeOnly() == 0666 || meta.unixModeOnly() == 0600);
    }

    private static File ssaidFile(int userId) {
        return new File("/data/system/users/" + userId + "/settings_ssaid.xml");
    }

    private static String getName(String packageName, int uid) {
        return Objects.equals(packageName, SettingsState.SYSTEM_PACKAGE_NAME)
                ? SSAID_USER_KEY : String.valueOf(uid);
    }

    private static String getFileContext(String path) throws Exception {
        Class<?> cls = Class.forName("android.os.SELinux");
        Method m = cls.getMethod("getFileContext", String.class);
        Object out = m.invoke(null, path);
        return out == null ? "" : String.valueOf(out);
    }

    private static boolean setFileContext(String path, String context) {
        try {
            Class<?> cls = Class.forName("android.os.SELinux");
            Method m = cls.getMethod("setFileContext", String.class, String.class);
            Object out = m.invoke(null, path, context);
            return out instanceof Boolean && (Boolean) out;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static boolean restorecon(String path) {
        try {
            Class<?> cls = Class.forName("android.os.SELinux");
            try {
                Method m = cls.getMethod("restorecon", File.class);
                Object out = m.invoke(null, new File(path));
                return !(out instanceof Boolean) || (Boolean) out;
            } catch (NoSuchMethodException ignored) {
                Method m = cls.getMethod("restorecon", String.class);
                Object out = m.invoke(null, path);
                return !(out instanceof Boolean) || (Boolean) out;
            }
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static String safe(String value) {
        return value == null ? "null" : value;
    }
}
