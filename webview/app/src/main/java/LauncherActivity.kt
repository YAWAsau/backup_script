package io.github.yawasau.speedbackup.webview

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.os.Handler
import android.os.Looper
import com.topjohnwu.superuser.Shell
import com.topjohnwu.superuser.CallbackList

/** Only runs entries registered by the DUMP-protected root UI; no caller-supplied commands. */
class LauncherActivity:ComponentActivity() {
    companion object { init { Shell.setDefaultBuilder(Shell.Builder.create().setFlags(Shell.FLAG_MOUNT_MASTER).setTimeout(30)) } }
    private val handler=Handler(Looper.getMainLooper())
    private var requested=false
    private var busy by mutableStateOf(false)
    private var status by mutableStateOf("")
    private var picker:ShortcutPathPicker?=null
    private var pickerModel by mutableStateOf<org.json.JSONObject?>(null)
    private fun text(s:String)=NativeLanguage.text(this,s)
    override fun onCreate(state:Bundle?){
        super.onCreate(state)
        val appearance=NativeAppearance(this).apply{loadLocal()}
        setContent {
            val configuration=androidx.compose.ui.platform.LocalConfiguration.current
            val theme=remember(configuration){appearance.apply(org.json.JSONObject())}
            NativeAppTheme(theme) {
            val uiStyle=theme.optString("uiStyle","miuix")
            val foreground=Color(theme.getLong("controlForeground").toInt())
            val background=Color(theme.getLong("background").toInt())
            val field=Color(theme.getLong("fieldColor").toInt())
            val accent=Color(theme.getLong("accent").toInt())
            val selection=pickerModel
            NativeNavHost(if(selection!=null)"launcher:picker:${selection.optString("session")}" else "launcher",
                selection to status,theme.optBoolean("reducedMotion"),Modifier.fillMaxSize(),
                root=selection==null,backRoute=if(selection!=null)"launcher" else "",boundaryBack=selection!=null,
                onBack={picker?.back()}) { page ->
            val shownPicker=page.first
            if(shownPicker!=null) NativePathPicker(shownPicker,foreground,background,accent,uiStyle,reducedMotion=theme.optBoolean("reducedMotion"),onBack={picker?.back()},delegateRootBack=true){picker?.action(it)} else
            Column(Modifier.fillMaxSize().background(background).systemBarsPadding().padding(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
                BasicText("SpeedBackup",style=nativeTextStyle(color=foreground,fontSize=24.sp))
                BasicText(page.second,style=nativeTextStyle(color=foreground,fontSize=16.sp))
                CompositionLocalProvider(LocalNativeFooterAction provides true) {
                NativeDialogButton(text("重試"),uiStyle,foreground,field,nativeTextStyle(fontSize=17.sp),!busy,Modifier.fillMaxWidth(),primary=LocalNativeMaterial.current){launchEntry()}
                if(EntryShortcuts.path(this@LauncherActivity,intent.getStringExtra("entryId"))!=null)NativeDialogButton(text("重新選擇 start.sh"),uiStyle,foreground,field,nativeTextStyle(fontSize=17.sp),!busy,Modifier.fillMaxWidth()){
                    picker?.close();picker=ShortcutPathPicker(this@LauncherActivity,intent.getStringExtra("entryId")!!,{pickerModel=it},{path->status=text("捷徑路徑已更新，按重試啟動。")+"\n"+path});picker!!.start()
                }
                NativeDialogButton(text("關閉"),uiStyle,foreground,field,nativeTextStyle(fontSize=17.sp),true,Modifier.fillMaxWidth()){finish()}
                }
            }
            }
        } }
    }
    override fun onNewIntent(value:Intent){super.onNewIntent(value);if(!busy){picker?.close();picker=null;setIntent(value);requested=false;if(hasWindowFocus())launchEntry()}else EntryShortcuts.toast(this,"目前正在啟動，請等待完成後再試") }
    override fun onDestroy(){picker?.close();handler.removeCallbacksAndMessages(null);super.onDestroy()}
    override fun onWindowFocusChanged(focus:Boolean){super.onWindowFocusChanged(focus);if(focus&&!requested&&!busy)launchEntry()}
    private fun launchEntry(){
        if(busy)return
        requested=true
        val id=intent.getStringExtra("entryId")
        val path=EntryShortcuts.path(this,id)
        if(!EntryShortcuts.validPath(path)){status=text("捷徑入口未登記，請先從該目錄的 start.sh 啟動並建立捷徑。");return}
        busy=true;status=text("正在啟動，首次使用請授予 Root 權限…")+"\n"+path
        Thread({
            var outcome:String
            try {
                val quoted="'"+path!!.replace("'","'\\''")+"'"
                // File move/deletion must fail explicitly, never fall back to another backup directory.
                val parent="'"+java.io.File(path).parent!!.replace("'","'\\''")+"'"
                val command="(export SHELL=/system/bin/sh PATH=/system/bin:/system/xbin:/data/adb/ksu/bin:/sbin:/system_ext/bin:/vendor/bin; if [ -f $quoted ]; then cd $parent && /system/bin/sh $quoted; else echo '無法存取入口（可能不存在或沒有目錄權限），請確認 Root 設定與原路徑'; exit 66; fi)"
                val shell=checkedShortcutRootShell()
                val output=StringBuilder()
                val lines=object:CallbackList<String>(java.util.concurrent.Executor { it.run() }) {
                    override fun onAddElement(line:String){synchronized(output){output.append(line).append('\n');if(output.length>32768)output.delete(0,output.length-32768)}}
                }
                val waiting=Runnable{if(!isDestroyed&&busy)status=text("啟動尚未完成；不會重複提交。可關閉此畫面，請查看服務日誌確認工作狀態。")+"\n"+path+"\n/data/.speedbackup/console/active/service.log"}
                handler.postDelayed(waiting,150000)
                shell.newJob().add(command).to(lines,lines).submit { result->
                    handler.removeCallbacks(waiting)
                    if(!isDestroyed){
                        busy=false
                        status=(if(result.isSuccess)text("啟動程序已完成。") else text("啟動失敗，請確認 Root 授權與入口路徑。")+"\n"+synchronized(output){output.toString()})+"\n"+path+"\n/data/.speedbackup/console/active/service.log\n/data/.speedbackup/console/active/crashes/"
                    }
                }
                return@Thread // Completion callback owns the pending job; no unbounded get/thread wait.

            }catch(e:Exception){outcome=text("無法啟動，請先在 Root 管理器允許 SpeedBackup 使用超級使用者權限，再重試。")+"\n"+(e.message?:e.javaClass.simpleName)}
            runOnUiThread{busy=false;status=outcome+"\n"+path+"\n"+text("服務日誌：")+"/data/.speedbackup/console/active/service.log\n"+text("崩潰日誌：")+"/data/.speedbackup/console/active/crashes/"}
        },"shortcut-start").start()
    }
}
