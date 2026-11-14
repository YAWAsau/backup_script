package io.github.yawasau.speedbackup.webview

import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Display state for Rust's event stream; all discovery and validation live in Rust. */
internal class NativeDiscovery(private val session:NativeSession,private val onUpdate:()->Unit={}):AutoCloseable {
    data class Endpoint(val name:String,val type:String,val address:String,val url:String,val identity:String,val candidate:Boolean=false) {
        val title:String get(){
            val path=runCatching{android.net.Uri.parse(url).lastPathSegment}.getOrNull().orEmpty()
            if(type=="SMB")return if(path.isEmpty())"SMB · $address" else "SMB · $path"
            val product=runCatching{JSONObject(identity).optString("product")}.getOrNull()
            if(product=="SpeedBackup")return "SpeedBackup Server · WebDAV"
            return if(name.startsWith("WebDAV 服務")||name.startsWith("WebDAV 候選")||name.isBlank())"WebDAV · $address" else "$name · WebDAV"
        }
    }
    private val id=UUID.randomUUID().toString().replace("-","")
    private val stopped=AtomicBoolean()
    private var closed=false
    private var targetTransport:NativeApi?=null
    private var targetId=""
    var resolving=false; private set
    private val transport=session.api.fork()
    var running=false; private set
    var failed=false; private set
    var message=""; private set
    var endpoints=emptyList<Endpoint>(); private set
    fun start(fresh:Boolean=false){
        if(stopped.get()||running)return
        running=true;failed=false;message="正在尋找區域網路中的 WebDAV／SMB 服務…"
        Thread({
            try {
                if(stopped.get())return@Thread
                transport.discovery(id,fresh){line->
                    val data=JSONObject(line)
                    session.execute {
                        if(!stopped.get()) {
                            data.optJSONArray("endpoints")?.let{rows->
                                endpoints=(0 until rows.length()).map{rows.getJSONObject(it)}.map{
                                    Endpoint(it.getString("name"),it.getString("type"),it.getString("address"),it.getString("url"),it.optString("identity"),it.optBoolean("candidate"))
                                }
                            }
                            running=data.optBoolean("running")
                            failed=data.optString("error").isNotEmpty()
                            if(!running)message=data.optString("error").ifEmpty{summary()}
                            onUpdate()
                            session.emit()
                        }
                    }
                }
                session.execute{if(!stopped.get()&&running){running=false;failed=true;message="搜尋連線提前中斷，請重試或手動輸入。";onUpdate();session.emit()}}
            }catch(_:Exception){session.execute{if(!stopped.get()){running=false;failed=true;message="搜尋連線失敗，請重試或手動輸入。";onUpdate();session.emit()}}}
            finally{transport.close()}
        },"native-discovery-events").apply{isDaemon=true;start()}
    }
    private fun summary()=if(endpoints.isEmpty())"未找到公告的服務。請確認在相同區域網路，伺服器已啟用 Bonjour／Avahi；也可手動輸入。" else "搜尋結束，共 ${endpoints.size} 個地址。選擇後仍需儲存設定；不會自動登入或開始備份。"
    fun networkUnavailable(reason:String){close();running=false;resolving=false;endpoints=emptyList();message=reason}
    fun stop(){running=false;message=summary();cancel()}
    private fun cancel(){
        if(!stopped.compareAndSet(false,true))return
        // Separate cancellation transport remains usable during session teardown.
        Thread({
            try{session.api.fork().use{it.post("discovery-stop",id)}}catch(_:Exception){}
            finally{transport.close()}
        },"native-discovery-stop").apply{isDaemon=true;start()}
    }
    fun resolve(endpoint:Endpoint,user:String,password:String,onAuthenticationRequired:(Endpoint,String)->Unit,onVerified:(Endpoint)->Unit){
        if(closed||resolving)return
        stop();resolving=true;message=if(endpoint.type=="SMB")"正在讀取共用資料夾並確認地址…" else "正在確認 WebDAV 完整地址…"
        val api=session.api.fork();targetTransport=api
        targetId=UUID.randomUUID().toString().replace("-","")
        val body=JSONObject().put("requestId",targetId).put("protocol",if(endpoint.type=="SMB")"smb" else "webdav").put("url",endpoint.url).put("identity",endpoint.identity).put("user",user).put("password",password).toString()
        session.emit()
        Thread({
            try{
                val result=JSONObject(api.post("discovery-target",body))
                session.execute{
                    if(!closed&&targetTransport===api){
                        resolving=false;targetTransport=null
                        val error=result.optString("error")
                        if(error.isNotEmpty()){
                            message=error
                            if(result.optString("reason")=="auth_failed")onAuthenticationRequired(endpoint,error)
                        }
                        else if(result.optBoolean("verified"))onVerified(endpoint)
                        else {
                            val urls=result.getJSONArray("urls")
                            endpoints=(0 until urls.length()).map{endpoint.copy(url=urls.getString(it))}
                            message="已找到完整地址，請選擇共用資料夾；確認可存取後即可儲存。"
                            if(endpoints.size==1)resolve(endpoints.single(),user,password,onAuthenticationRequired,onVerified)
                        }
                        session.emit()
                    }
                }
            }catch(_:Exception){session.execute{if(!closed&&targetTransport===api){resolving=false;targetTransport=null;message="完整地址讀取失敗，請重試或手動設定。";session.emit()}}}
            finally{api.close()}
        },"native-discovery-target").apply{isDaemon=true;start()}
    }
    override fun close(){
        closed=true
        val requestId=targetId
        if(targetTransport!=null&&requestId.isNotEmpty())Thread({
            try{session.api.fork().use{it.post("discovery-target-stop",requestId)}}catch(_:Exception){}
        },"native-target-cancel").apply{isDaemon=true;start()}
        targetTransport?.close();targetTransport=null;cancel()
    }
}
