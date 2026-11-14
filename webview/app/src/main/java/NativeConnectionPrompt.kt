package io.github.yawasau.speedbackup.webview

import org.json.JSONObject

/** A discovery offer never starts a backup. Only the explicitly selected host gets credentials. */
internal class NativeConnectionPrompt(private val session:NativeSession,private val eligible:()->Boolean,private val automatic:()->Boolean):AutoCloseable {
    private val c get()=session.controls
    private var scan:NativeDiscovery?=null
    private var offered=false
    private var closed=false
    private var requested=false
    var showing=false; private set
    private var selected:NativeDiscovery.Endpoint?=null
    private var user=""
    private var password=""
    private var revision=""
    private var revisionEpoch=0L
    private var revisionTransport:NativeApi?=null
    private fun clearRevision(){++revisionEpoch;revisionTransport?.close();revisionTransport=null;revision=""}
    private fun loadRevision(){
        clearRevision()
        val epoch=revisionEpoch
        val api=session.api.fork();revisionTransport=api
        message="正在讀取連線設定…";session.emit()
        Thread({
            val value=try{api.get("connection-revision")}catch(_:Exception){""}
            finally{api.close()}
            session.execute{
                if(!closed&&showing&&revisionEpoch==epoch&&revisionTransport===api){
                    revisionTransport=null;revision=value
                    message=if(value.isEmpty())"無法讀取設定版本，請取消後重試。" else "請輸入登入帳密；匿名服務可留空驗證。"
                    session.emit()
                }
            }
        },"native-connection-revision").apply{isDaemon=true;start()}
    }
    private var message=""
    private var saving=false
    private var foundAny=false
    private var completed=false
    private var scanError=""
    val scanning get()=scan?.running==true
    val found get()=foundAny
    val searched get()=completed
    val error get()=scanError
    private fun canOffer()=eligible()&&(requested||automatic())
    fun reopen(){if(closed||saving||!eligible())return;scan?.close();scan=null;offered=false;requested=true;start()}
    fun connected(){
        if(saving)return
        clearRevision();scan?.close();scan=null;showing=false;selected=null;user="";password="";message=""
        foundAny=false;completed=false;scanError="";requested=false;offered=false
        c.forgetPrefix("connection:user");c.forgetPrefix("connection:password")
    }
    fun pause(){if(saving)return;if(showing){back(false)}else{scan?.close();scan=null}}
    fun start(){
        if(closed||offered||!canOffer())return
        if(scan!=null){if(foundAny){offered=true;showing=true};return}
        completed=false;scanError=""
        scan=NativeDiscovery(session){
            foundAny=scan?.endpoints?.any{!it.candidate}==true
            completed=scan?.running==false&&scan?.failed==false
            scanError=if(scan?.failed==true)scan?.message.orEmpty() else ""
            if(!offered&&canOffer()&&foundAny){offered=true;showing=true}
        }.also{it.start()}
    }
    fun back(emit:Boolean=true){if(saving)return;clearRevision();showing=false;offered=true;selected=null;password="";scan?.close();scan=null;if(emit)session.emit()}
    private fun verify(){
        val endpoint=selected?:return
        val discovery=scan?:return
        if(saving||discovery.resolving||revision.isEmpty())return
        message=""
        val enteredUser=user;val enteredPassword=password
        discovery.resolve(endpoint,enteredUser,enteredPassword,{target,error->selected=target;message=error}){verified->
            selected=verified;saving=true;message="連線可用，正在儲存…";session.emit()
            val body=obj("protocol" to if(verified.type=="SMB")"smb" else "webdav","url" to verified.url,"identity" to verified.identity,"user" to enteredUser,"password" to enteredPassword,"revision" to revision).toString()
            Thread({
                val ok=try{session.api.fork().use{it.post("discovery-save",body)};true}catch(_:Exception){false}
                session.execute{if(!closed){saving=false;if(ok){session.status="連線驗證成功，地址與帳密已儲存。";back()}else{message="連線可用，但儲存失敗或設定已變更。請取消後從設定頁確認，未自動覆蓋。";session.emit()}}}
            },"native-connection-save").apply{isDaemon=true;start()}
        }
    }
    fun model():JSONObject? {
        if(!showing)return null
        val discovery=scan?:return null
        val busy=saving||discovery.resolving
        val endpoint=selected
        val nodes=mutableListOf(c.node("connection:title","text",if(endpoint==null)"發現 SMB／WebDAV 服務" else "${endpoint.type} 連線設定"))
        if(endpoint==null){
            nodes+=c.node("connection:hint","text","選擇設備後輸入帳密；驗證可用才儲存，不會開始備份。")
            discovery.endpoints.filterNot{it.candidate}.forEach{item->nodes+=c.button("connection:choose:${item.url}","${item.title}\n${item.url}"){
                c.forgetPrefix("connection:user");c.forgetPrefix("connection:password")
                selected=item;user="";password="";message="請輸入登入帳密；匿名服務可留空驗證。"
                loadRevision()
            }.put("literalLabel",true).put("navigation",true)}
        }else{
            nodes+=c.node("connection:url","text",endpoint.url).put("translate",false)
            nodes+=c.node("connection:message",if(busy)"loading" else "text",if(discovery.resolving||message.isEmpty()||discovery.endpoints.none{it.url==endpoint.url})discovery.message else message)
            nodes+=c.input("connection:user","帳號",user){user=it}.put("disabled",busy)
            nodes+=c.input("connection:password","密碼",password){password=it}.put("password",true).put("disabled",busy)
            if(!busy&&discovery.endpoints.none{it.url==endpoint.url}){
                discovery.endpoints.forEach{share->nodes+=c.button("connection:share:${share.url}","${share.title}\n${share.url}"){selected=share;verify()}.put("literalLabel",true).put("navigation",true)}
            }
        }
        nodes+=c.group("connection:actions","row",listOf(c.button("connection:cancel","取消",saving){back()})+
            if(endpoint==null)emptyList() else listOf(c.button("connection:verify","驗證並儲存",busy||revision.isEmpty()){verify()}.put("materialPrimary",true))).put("dialogAction",true)
        return obj("id" to c.bind("connection:dialog"){_,_,_->back()},"nodes" to arr(nodes))
    }
    override fun close(){closed=true;clearRevision();showing=false;password="";scan?.close();scan=null}
}
