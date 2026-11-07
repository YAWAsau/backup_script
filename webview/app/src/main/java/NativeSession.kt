package io.github.yawasau.speedbackup.webview

import android.content.Context
import org.json.JSONObject
import org.json.JSONArray
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** One serialized state owner per root-issued session; no DOM or JavaScript. */
internal class NativeSession(private val context:Context,address:String,private val listener:Listener):AutoCloseable {
    interface Listener { fun model(value:JSONObject);fun link(url:String);fun terminal(message:String);fun exit() }
    val epoch=UUID.randomUUID().toString()
    val api=NativeApi(address)
    val controls=NativeControls()
    fun importSystemWallpaper(){android.os.Handler(android.os.Looper.getMainLooper()).post{NativeUserWallpaper.importSystem(context,api)}}
    val appearance=NativeAppearance(context)
    private val statePrefs=context.getSharedPreferences("native_drafts_v1",Context.MODE_PRIVATE)
    private val stateKey=resumeKey(api.identity,"menu-state")
    private var stateWritten=""
    fun readState():JSONObject=try{statePrefs.getString(stateKey,null)?.let{JSONObject(NativeStateCipher.open(it))}?:JSONObject()}catch(_:Exception){JSONObject()}
    fun writeState(value:JSONObject){
        val encoded=value.toString();require(encoded.toByteArray(Charsets.UTF_8).size<=262144)
        if(encoded==stateWritten)return
        stateWritten=encoded
        val sealed=try{NativeStateCipher.seal(encoded)}catch(e:Exception){
            stateWritten="";android.util.Log.w("SpeedBackupNative","resume encryption unavailable: ${e.javaClass.simpleName}");diagnostic("native-resume-encryption");return
        }
        val edit=statePrefs.edit().putString(stateKey,sealed)
        if(statePrefs.all.size>128)statePrefs.all.keys.filter{it!=stateKey}.take(statePrefs.all.size-128).forEach{edit.remove(it)}
        edit.apply()
    }
    lateinit var catalog:NativeCatalog;private set
    private val executor=Executors.newSingleThreadScheduledExecutor { r->Thread(r,"native-session").apply{isDaemon=true} }
    private val closed=AtomicBoolean()
    private val closing=AtomicBoolean()
    private val diagnostics=java.util.concurrent.ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,java.util.concurrent.ArrayBlockingQueue<Runnable>(16),{r->Thread(r,"native-diagnostic").apply{isDaemon=true}},java.util.concurrent.ThreadPoolExecutor.DiscardPolicy())
    init{api.diagnostic=java.util.function.Consumer{event->diagnostic(event)}}
    fun diagnostic(event:String){if(!closing.get())diagnostics.execute{try{api.post("diagnostic",event)}catch(_:Exception){android.util.Log.w("SpeedBackupNative","diagnostic unavailable")}}}
    @Volatile private var page:NativePage?=null
    private var loadFailed=false
    private var sequence=0L
    var status=""
    var finished=false;private set
    private var dialog:JSONObject?=null
    private var dialogAction:(()->Unit)?=null
    private fun sessionKind():String {
        try {
            val identity=JSONObject(api.get("session"))
            require(identity.getInt("protocol")==1&&identity.getBoolean("native")){"不相容的原生通訊協定"}
            return identity.getString("kind")
        }catch(e:NativeApi.ApiFailure){if(e.status!=400&&e.status!=404)throw e}
        // Previously released backends have these authenticated read-only APIs.
        // Never probe by submitting a choice, requesting a draft lease or starting work.
        for((route,kind) in listOf("menu" to "menu","manager" to "editor","history-view" to "console")) {
            try {
                val result=api.get(route)
                when(kind){
                    "menu"->{val data=JSONObject(result);data.getJSONArray("choices");data.getJSONArray("info")}
                    "editor"->{val data=JSONObject(result);require(data.getString("mode") in setOf("apps","backup","restore","remote","media","remote-delete"))}
                    else->require(result.trim()=="live"||result.trim().toLongOrNull()?.let{it>=0}==true)
                }
                return kind
            }catch(e:NativeApi.ApiFailure){if(e.status!=400&&e.status!=404)throw e}
        }
        error("目前工作使用的介面協定不受支援；工作仍保留，未重新執行")
    }
    fun start(){execute{
        val kind=sessionKind()
        catalog=NativeCatalog.get(context);appearance.load(api)
        page=when(kind){"menu"->NativeMenuPage(this);"editor"->NativeEditorPage(this,context);"console"->NativeConsolePage(this);else->error("未知操作畫面")}
        try{page!!.load()}catch(e:Exception){loadFailed=true;throw e};emit()
        diagnostic("native-open")
        page!!.tickIntervalMillis?.let{interval->
            executor.scheduleWithFixedDelay({if(!closed.get()&&!finished)try{page?.tick()}catch(e:Exception){failure(e)}},interval,interval,TimeUnit.MILLISECONDS)
        }
    }}
    fun execute(action:()->Unit){if(!closing.get())try{executor.execute{if(!closed.get())try{action()}catch(e:Exception){failure(e)}}}catch(_:java.util.concurrent.RejectedExecutionException){}}
    fun later(delay:Long,action:()->Unit):java.util.concurrent.ScheduledFuture<*> = executor.schedule({if(!closed.get())try{action()}catch(e:Exception){failure(e)}},delay,TimeUnit.MILLISECONDS)
    private fun failure(error:Exception){
        if(closed.get())return
        // Only stage and exception class enter diagnostics: no paths, account names or secrets.
        android.util.Log.w("SpeedBackupNative","session failed: ${error.javaClass.simpleName}")
        diagnostic("native-action:${error.javaClass.simpleName}")
        status=error.message?.take(8192)?:"操作失敗，請重試"
        if(page!=null&&!loadFailed)try{emit()}catch(_:Exception){listener.terminal(status)}else listener.terminal(status)
    }
    fun dispatch(id:String,eventEpoch:String){if(eventEpoch!=epoch||closed.get())return;execute{
        if(loadFailed){if(id=="back")exit();return@execute}
        if(finished){if(id=="back")exit();return@execute}
        if(id=="back"){if(dialog!=null){dialog=null;dialogAction=null;emit()}else page?.back();return@execute}
        if(id.startsWith("license:")){page?.action(id);return@execute}
        if(id.startsWith("picker:")){page?.action(id);return@execute}
        if(id.startsWith("menu:")||id.startsWith("screen:")){
            val event=JSONObject(id.substringAfter(':'))
            if(dialog!=null){when(event.optString("id")){controls.id("confirm:accept")-> {val action=dialogAction;dialog=null;dialogAction=null;action?.invoke()};controls.id("confirm"),controls.id("confirm:cancel")-> {dialog=null;dialogAction=null;emit()}};return@execute}
            if(event.optString("kind")=="page"){page?.action(id);return@execute}
            controls.action(event.optString("id"),event.optString("kind"),event.optString("value"),event.optLong("revision"))
        }else page?.action(id)
    }}
    fun confirm(text:String,action:()->Unit){dialogAction=action;dialog=obj("id" to controls.id("confirm"),"nodes" to arr(listOf(
        controls.node("confirm:text","text",text),controls.button("confirm:cancel","取消"){},controls.button("confirm:accept","確定"){}
    )));emit()}
    fun finish(message:String){finished=true;status=message;statePrefs.edit().remove(stateKey).apply();emit()}
    fun exit(){listener.exit()}
    fun openLink(url:String){val u=java.net.URI(url);require(u.scheme=="https"&&!u.host.isNullOrEmpty()&&u.userInfo==null);listener.link(url)}
    fun emit(){
        if(closing.get()||loadFailed)return
        controls.begin()
        val model=appearance.apply(obj("epoch" to epoch,"seq" to ++sequence,"resumeSession" to api.identity,"body" to JSONArray(),"buttons" to JSONArray(),"tabs" to false,"selected" to -1,"bottom" to 20,"hint" to status))
        page?.render(model)?:return
        dialog?.let{d->
            // NativeDocument owns confirmation focus and its closing gesture.
            if(model.optJSONObject("screen")==null){model.remove("menu");model.put("screen",controls.screen("confirmation","確認操作",emptyList(),emptyList()))}
            model.getJSONObject("screen").put("dialog",d)
        }
        // Detach nested mutable page state before publishing across threads.
        val snapshot=JSONObject(model.toString())
        catalog.localize(snapshot,appearance.values["language"]?:"zh-Hant")
        listener.model(snapshot)
    }
    fun refresh(){execute{emit()}}
    fun lifecycle(visible:Boolean){diagnostic(if(visible)"native-visible" else "native-hidden");execute{if(!loadFailed)page?.lifecycle(visible)}}
    override fun close(){if(closing.compareAndSet(false,true)){
        diagnostics.shutdownNow()
        // Do not block Android's main thread. Root's draft lease prevents an old
        // window from overwriting a newly connected window during this flush.
        val deadline=Thread{try{Thread.sleep(2000)}catch(_:InterruptedException){return@Thread};closed.set(true);page?.close();api.close();executor.shutdownNow()}.apply{isDaemon=true;name="native-session-close";start()}
        try{executor.execute{try{if(!loadFailed)page?.lifecycle(false)}catch(_:Exception){}finally{closed.set(true);page?.close();api.close();executor.shutdownNow();deadline.interrupt()}}}catch(_:java.util.concurrent.RejectedExecutionException){closed.set(true);page?.close();api.close()}
    }}
}

internal interface NativePage {
    fun load()
    fun render(model:JSONObject)
    fun action(value:String)
    fun back()
    fun tick(){}
    val tickIntervalMillis:Long? get()=null
    fun lifecycle(visible:Boolean){}
    fun close(){}
}
