package com.xayah.dex;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManagerHidden;
import android.os.Build;
import android.os.HandlerThread;
import android.os.Process;

import com.android.providers.settings.SettingsState;
import com.android.providers.settings.SettingsStateApi26;
import com.android.providers.settings.SettingsStateApi31;

import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

/** Internal SSAID storage adapter used only by the canonical AppState engine. */
final class SsaidUtil {
    private static final String SSAID_USER_KEY = "userkey";

    /** One SettingsState/HandlerThread per Android user for the daemon lifetime. */
    private static final Map<Integer, SsaidStateHolder> STATE_CACHE = new HashMap<>();

    private static final class SsaidStateHolder {
        final Object lock;
        final HandlerThread thread;
        final SettingsState state;

        SsaidStateHolder(Object lock, HandlerThread thread, SettingsState state) {
            this.lock = lock;
            this.thread = thread;
            this.state = state;
        }
    }

    private SsaidUtil() {
    }

    private static synchronized SsaidStateHolder getSettingsStateHolder(int userId) {
        SsaidStateHolder cached = STATE_CACHE.get(userId);
        if (cached != null) return cached;

        Object lock = new Object();
        HandlerThread thread = new HandlerThread(
                "appstate_ssaid_u" + userId, Process.THREAD_PRIORITY_BACKGROUND);
        thread.start();
        File file = new File("/data/system/users/" + userId + "/settings_ssaid.xml");
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
        SsaidStateHolder holder = new SsaidStateHolder(lock, thread, settingsState);
        STATE_CACHE.put(userId, holder);
        return holder;
    }

    static String readSsaidValue(int userId, String packageName,
                                 PackageManagerHidden pmHidden) throws Exception {
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId);
        int uid = packageInfo.applicationInfo.uid;
        SsaidStateHolder holder = getSettingsStateHolder(userId);
        synchronized (holder.lock) {
            SettingsState.Setting setting = holder.state.getSettingLocked(getName(packageName, uid));
            return setting == null ? null : setting.getValue();
        }
    }

    static void writeSsaidValue(int userId, String packageName, String ssaid,
                                PackageManagerHidden pmHidden) throws Exception {
        PackageInfo packageInfo = pmHidden.getPackageInfoAsUser(packageName, 0, userId);
        int uid = packageInfo.applicationInfo.uid;
        SsaidStateHolder holder = getSettingsStateHolder(userId);
        synchronized (holder.lock) {
            holder.state.insertSettingLocked(
                    getName(packageName, uid), ssaid, null, true, packageName);
        }
    }

    private static String getName(String packageName, int uid) {
        return Objects.equals(packageName, SettingsState.SYSTEM_PACKAGE_NAME)
                ? SSAID_USER_KEY : String.valueOf(uid);
    }
}
