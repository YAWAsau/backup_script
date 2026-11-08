package io.github.yawasau.speedbackup.webview;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** DUMP-protected reconnect entry for APK and root Dex immutable notifications. */
public final class ResumeActivity extends Activity {
    private boolean requested=false;
    private volatile boolean stopped;
    @Override protected void onStop(){stopped=true;super.onStop();finish();}
    @Override protected void onCreate(Bundle state){super.onCreate(state);NativeLanguage.set(getSharedPreferences(WorkGuardService.PREFS,0).getString("uiLanguage","zh-Hant"));TextView status=new TextView(this);status.setText(NativeLanguage.text(this,"正在接回目前工作…"));status.setPadding(32,48,32,32);setContentView(status);}
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused||requested)return;requested=true;
        String url=getSharedPreferences(WorkGuardService.PREFS,0).getString(WorkGuardService.KEY,"");
        // This Activity shares the guardian process, so preferences cannot be stale across processes.
        new Thread(()->{boolean ok=false;try{if(stopped)return;WorkGuardService.request(url,"reopen",true);ok=true;}catch(Exception ignored){}final boolean success=ok;
            runOnUiThread(()->{if(isFinishing()||isDestroyed())return;if(!success){android.widget.Toast.makeText(this,NativeLanguage.text(this,"目前工作無法接回，請重新執行 start.sh"),android.widget.Toast.LENGTH_LONG).show();finish();}
                else new android.os.Handler(getMainLooper()).postDelayed(()->finish(),8000);});
        },"resume-work").start();
    }
}
