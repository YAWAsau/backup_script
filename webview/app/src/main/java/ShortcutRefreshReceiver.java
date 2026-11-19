package io.github.yawasau.speedbackup.webview;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Refresh launcher-cached images after replacing the APK, without repinning. */
public final class ShortcutRefreshReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent){
        if(Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction()))EntryShortcuts.refreshPinned(context);
    }
}
