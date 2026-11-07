package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal class NativePickerController(private val session:NativeSession,private val mode:String,private val field:JSONObject,private val saved:JSONObject?=null,private val done:()->Unit){
    val identity=saved?.optString("identity")?.takeIf{runCatching{UUID.fromString(it)}.isSuccess}?:UUID.randomUUID().toString()
    private val key=field.getString("key")
    private val multi=key=="Custom_path"
    private val files=key=="list_location"
    private val initial=field.getString("value").let{if(multi)it.split('\n')else listOf(it)}.filter{it.isNotEmpty()&&!Regex("^\\s*[#＃]").containsMatchIn(it)&&it.length<=8192}.toSet()
    private val selected=initial.toMutableSet()
    private var path=""
    private var parent=""
    private var next:Long?=null
    private var entries=emptyList<JSONObject>()
    private var revision=0L
    private var loading=false
    private var error=""
    init{require(key in setOf("Custom_path","Output_path","list_location")&&initial.size<=256)}
    fun model()=obj("session" to identity,"selectionRevision" to revision,"title" to if(multi)"選擇備份資料夾" else if(files)"選擇應用清單檔案" else "選擇備份目的地","multi" to multi,"files" to files,"selected" to arr(selected),"entries" to arr(entries),"path" to path,"parent" to parent,"next" to next,"loading" to loading,"error" to error,"resumeSession" to session.api.identity)
    fun draft()=obj("identity" to identity,"mode" to mode,"key" to key,"base" to field.getString("value"),"path" to path,"selected" to arr(selected),"count" to entries.size)
    fun loadInitial(){
        saved?.optJSONArray("selected")?.takeIf{it.length()<=256}?.let{values->
            val paths=values.strings();require(paths.all{it.length<=8192&&!it.contains('\n')&&!it.contains('\r')});selected.clear();selected.addAll(if(multi)paths else paths.take(1))
        }
        load(saved?.optString("path")?:initial.firstOrNull()?:"")
        val count=saved?.optInt("count",0)?.coerceIn(0,10000)?:0
        while(error.isEmpty()&&entries.size<count&&next!=null){val previous=entries.size;load(path,next!!,true);if(entries.size<=previous)break}
    }
    private fun load(target:String,offset:Long=0,append:Boolean=false){
        require(!target.contains('\n')&&!target.contains('\r')&&target.length<=8192&&offset>=0)
        loading=true;error="";session.emit()
        try{
            val result=JSONObject(session.api.post("browse-path",listOf(mode,key,offset.toString(),target).joinToString("\n")))
            val found=result.getJSONArray("entries").modelObjects();require(found.size<=1000)
            path=result.getString("path");parent=result.getString("parent");next=if(result.isNull("next"))null else result.getLong("next")
            entries=if(append)entries+found else found;require(entries.size<=10000)
        }catch(e:Exception){error=e.message?.take(8192)?:"無法讀取資料夾"}
        finally{loading=false;session.emit()}
    }
    fun back(){
        if(loading)return
        if(parent.isNotEmpty()&&parent!=path)load(parent)else done()
    }
    fun action(event:JSONObject){
        if(event.optString("session")!=identity)return
        when(event.optString("kind")){
            "cancel"->done()
            "open"->{val target=event.optString("path");if(!loading&&(target in listOf(parent,"/sdcard","/storage")||entries.any{it.getBoolean("directory")&&it.getString("path")==target}))load(target)}
            "more"->next?.let{if(!loading)load(path,it,true)}
            "remove"->{if(event.optLong("revision",-1)==revision){val indices=event.optJSONArray("indices")?:return;val paths=selected.toList();require(indices.length()<=256);val remove=(0 until indices.length()).map{indices.getInt(it)};require(remove.all{it in paths.indices});remove.forEach{selected.remove(paths[it])};revision++;session.emit()}}
            "select"->{
                val target=event.optString("path")
                val valid=if(files)entries.any{!it.getBoolean("directory")&&it.getString("path")==target}else target==path||entries.any{it.getBoolean("directory")&&it.getString("path")==target}
                if(!loading&&valid){if(!selected.remove(target)){if(!multi)selected.clear();if(selected.size<256)selected.add(target)else error="一次最多選擇 256 個路徑。"};revision++;session.emit()}
            }
            "confirm"->{
                if(loading)return
                if(multi){
                    val lines=field.getString("value").split('\n').filterNot{it in initial&&it !in selected}.toMutableList()
                    for(item in selected.sorted())if(item !in lines)lines.add(item)
                    field.put("value",lines.joinToString("\n"))
                }else field.put("value",selected.firstOrNull()?:"")
                done()
            }
        }
    }
}
