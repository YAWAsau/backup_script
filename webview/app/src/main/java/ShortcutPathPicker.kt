package io.github.yawasau.speedbackup.webview

import android.app.Activity
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Uses the existing Rust directory browser and Miuix picker without starting an entry. */
internal class ShortcutPathPicker(private val activity:Activity,private val id:String,private val publish:(JSONObject?)->Unit,private val done:(String)->Unit){
    private val original=EntryShortcuts.path(activity,id)?:""
    private val mode=EntryShortcuts.mode(activity,id)
    private val identity=UUID.randomUUID().toString()
    private var closed=false
    private var loading=false
    private var path=""
    private var parent=""
    private var entries=emptyList<JSONObject>()
    private var next:Long?=null
    private var selected=""
    private var revision=0L
    private var error=""
    fun close(){closed=true;publish(null)}
    private fun emit(){if(!closed)publish(JSONObject().put("session",identity).put("resumeSession",identity).put("selectionRevision",revision).put("title",NativeLanguage.text(activity,if(mode=="2")"重新選擇恢復 start.sh" else "重新選擇備份 start.sh")).put("files",true).put("multi",false).put("selected",JSONArray(if(selected.isEmpty())emptyList<String>() else listOf(selected))).put("path",path).put("parent",parent).put("entries",JSONArray(entries)).put("next",next?:JSONObject.NULL).put("loading",loading).put("error",error).put("selectionHint",NativeLanguage.text(activity,"確認後更新原捷徑，不會立即執行腳本")))}
    private fun quote(s:String)="'"+s.replace("'","'\\''")+"'"
    private fun request(op:String,target:String,last:String,complete:(JSONObject)->Unit){
        if(closed||loading)return
        loading=true;error="";emit()
        Thread({
            val result=runCatching {
                val backend=EntryShortcuts.backend(activity)
                require(backend.startsWith("/data/")&&backend.endsWith("/speednative")){"請先從新版 start.sh 啟動一次，以準備路徑選擇服務"}
                val shell=checkedShortcutRootShell()
                val output=ArrayList<String>();val errors=ArrayList<String>()
                val r=shell.newJob().add(quote(backend)+" speedscan shortcut-path "+listOf(op,target,last).joinToString(" "){quote(it)}).to(output,errors).exec()
                require(r.isSuccess){errors.joinToString("\n").take(2048).ifEmpty{"無法讀取路徑，請從新版 start.sh 啟動一次後重試"}}
                JSONObject(output.joinToString("\n"))
            }
            activity.runOnUiThread {if(!closed&&!activity.isDestroyed){loading=false;result.fold({try{complete(it)}catch(e:Exception){error=e.message?:"無法更新捷徑"}},{error=it.message?:"無法讀取路徑"});emit()}}
        },"shortcut-picker").start()
    }
    fun start(){load("/")}
    fun back(){
        if(closed)return
        // Cancel the picker during an in-flight read/validation; its late result
        // is discarded by request(), so Back never finishes the Activity.
        if(loading){close();return}
        if(parent.isNotEmpty()&&parent!=path)load(parent)else close()
    }
    private fun load(target:String,offset:Long=0){request("browse",target,offset.toString()){v->
        val a=v.getJSONArray("entries");val rows=(0 until a.length()).map{a.getJSONObject(it)}.filter{it.getBoolean("directory")||it.getString("name").endsWith(".sh")}
        require((if(offset==0L)0 else entries.size)+rows.size<=10000){"目錄項目過多"}
        if(offset==0L&&path!=v.getString("path")){selected="";revision++}
        entries=if(offset==0L)rows else entries+rows;path=v.getString("path");parent=v.getString("parent");next=if(v.isNull("next"))null else v.getLong("next")
    }}
    fun action(raw:String){
        val v=runCatching{JSONObject(raw.substringAfter("picker:"))}.getOrNull()?:return
        if(closed||v.optString("session")!=identity)return
        val target=v.optString("path")
        if(v.optString("kind")=="cancel"){close();return}
        if(loading)return
        when(v.optString("kind")){
            "open"->if(target in listOf(parent,"/sdcard","/storage")||entries.any{it.optBoolean("directory")&&it.optString("path")==target})load(target)
            "more"->next?.let{load(path,it)}
            "select"->if(entries.any{!it.optBoolean("directory")&&it.optString("path")==target}){selected=if(selected==target)"" else target;revision++;emit()}
            "remove"->if(v.optLong("revision")==revision){selected="";revision++;emit()}
            "confirm"->if(selected.isNotEmpty())request("validate",selected,mode){result->
                require(result.getString("mode")==mode){"入口類型不符，請重新選擇對應的備份或恢復 start.sh"}
                require(EntryShortcuts.relocate(activity,id,original,result.getString("path"))){"捷徑已變更或無法儲存，請重新開啟捷徑"}
                close();done(result.getString("path"))
            }
        }
    }
}
