package io.github.yawasau.speedbackup.webview

import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Display state for Rust's event stream; all discovery and validation live in Rust. */
internal class NativeDiscovery(private val session:NativeSession):AutoCloseable {
    data class Endpoint(val name:String,val type:String,val address:String,val url:String,val identity:String)
    private val id=UUID.randomUUID().toString().replace("-","")
    private val stopped=AtomicBoolean()
    private val transport=session.api.fork()
    var running=false; private set
    var message=""; private set
    var endpoints=emptyList<Endpoint>(); private set
    fun start(){
        if(stopped.get()||running)return
        running=true;message="正在尋找區域網路中的 WebDAV／SMB 服務…"
        Thread({
            try {
                if(stopped.get())return@Thread
                transport.discovery(id){line->
                    val data=JSONObject(line)
                    session.execute {
                        if(!stopped.get()) {
                            data.optJSONArray("endpoints")?.let{rows->
                                endpoints=(0 until rows.length()).map{rows.getJSONObject(it)}.map{
                                    Endpoint(it.getString("name"),it.getString("type"),it.getString("address"),it.getString("url"),it.optString("identity"))
                                }
                            }
                            running=data.optBoolean("running")
                            if(!running)message=data.optString("error").ifEmpty{summary()}
                            session.emit()
                        }
                    }
                }
                session.execute{if(!stopped.get()&&running){running=false;message=summary();session.emit()}}
            }catch(_:Exception){session.execute{if(!stopped.get()){running=false;message="搜尋連線失敗，請重試或手動輸入。";session.emit()}}}
            finally{transport.close()}
        },"native-discovery-events").apply{isDaemon=true;start()}
    }
    private fun summary()=if(endpoints.isEmpty())"未找到公告的服務。請確認在相同區域網路，伺服器已啟用 Bonjour／Avahi；也可手動輸入。" else "搜尋結束，共 ${endpoints.size} 個地址。選擇後仍需儲存設定；不會自動登入或開始備份。"
    fun stop(){running=false;message=summary();cancel()}
    private fun cancel(){
        if(!stopped.compareAndSet(false,true))return
        // Separate cancellation transport remains usable during session teardown.
        Thread({
            try{session.api.fork().use{it.post("discovery-stop",id)}}catch(_:Exception){}
            finally{transport.close()}
        },"native-discovery-stop").apply{isDaemon=true;start()}
    }
    override fun close()=cancel()
}
