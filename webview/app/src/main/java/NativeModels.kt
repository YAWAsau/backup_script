package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject

internal fun obj(vararg entries:Pair<String,Any?>)=JSONObject().apply{entries.forEach{(k,v)->put(k,v?:JSONObject.NULL)}}
internal fun arr(values:Iterable<Any?>)=JSONArray().apply{values.forEach{put(it?:JSONObject.NULL)}}
internal fun JSONArray.modelObjects()=(0 until length()).map{getJSONObject(it)}
internal fun JSONArray.strings()=(0 until length()).map{getString(it)}

/** Worker-owned semantic controls. Stable IDs preserve focus, scroll and edits across redraws. */
internal class NativeControls {
    private var serial=0L
    private val identities=HashMap<String,String>()
    private val actions=HashMap<String,(String,String,Long)->Unit>()
    private val revisions=HashMap<String,Long>()
    fun begin(){actions.clear()}
    fun forgetPrefix(prefix:String) {
        val keys=identities.keys.filter{it.startsWith(prefix)}
        for(key in keys)identities.remove(key)?.let{actions.remove(it);revisions.remove(it)}
    }
    fun ephemeral(kind:String,label:String)=obj("id" to "control-${++serial}","kind" to kind,"label" to label)
    fun id(key:String):String=identities.getOrPut(key){require(identities.size<100000);"control-${++serial}"}
    fun bind(key:String,action:(String,String,Long)->Unit):String=id(key).also{actions[it]=action}
    fun action(id:String,kind:String,value:String,revision:Long){
        if(revision>0&&revision<(revisions[id]?:0))return
        if(revision>0)revisions[id]=revision
        actions[id]?.invoke(kind,value,revision)
    }
    fun node(key:String,kind:String,label:String="",action:((String,String,Long)->Unit)?=null):JSONObject {
        val id=if(action==null)id(key) else bind(key,action)
        return obj("id" to id,"kind" to kind,"label" to label,"revision" to (revisions[id]?:0))
    }
    fun button(key:String,label:String,disabled:Boolean=false,action:()->Unit)=node(key,"button",label){kind,_,_->if(kind=="click"&&!disabled)action()}.put("disabled",disabled)
    fun input(key:String,label:String,value:String,action:(String)->Unit)=node(key,"input",label){kind,text,_->if(kind=="value")action(text)}.put("value",value)
    fun select(key:String,label:String,value:String,options:List<Pair<String,String>>,action:(String)->Unit):JSONObject {
        val known=options.map{it.first}.toSet()
        val expanded=if(value in known)options else listOf(value to "目前自訂值：$value")+options
        return node(key,"select",label){kind,text,_->if(kind=="value"&&text in expanded.map{it.first})action(text)}
            .put("value",value).put("options",arr(expanded.map{obj("value" to it.first,"label" to it.second,"disabled" to false)}))
    }
    fun group(key:String,layout:String,children:List<JSONObject>,label:String="")=node(key,"group",label).put("layout",layout).put("children",arr(children))
    fun screen(key:String,title:String,nodes:List<JSONObject>,footer:List<JSONObject>,hint:String="",subtitle:String="")=
        obj("key" to key,"title" to title,"eyebrow" to "SpeedBackup","subtitle" to subtitle,"hint" to hint,"cancel" to "取消","nodes" to arr(nodes),"footer" to arr(footer))
}

/** No evaluation: serialize exactly the values accepted by Rust's literal-conf codec. */
internal fun encodeSettings(fields:List<JSONObject>):String=fields.joinToString("\n") { field ->
    val key=field.getString("key");require(key.matches(Regex("[A-Za-z_][A-Za-z_0-9]*")))
    key+"\t"+field.getString("value").toByteArray(Charsets.UTF_8).joinToString(""){"%02x".format(it.toInt() and 255)}
}

internal class NativeSelection {
    var apps=emptyList<JSONObject>();private set
    var page=0
    var search=""
    var filter="all"
    var lease="";private set
    var saved=JSONObject();private set
    var timeline=obj("mode" to "match","target" to "","sources" to JSONArray())
    fun load(list:String,draft:String,singleChoice:Boolean){
        apps=JSONArray(list).modelObjects().map{it.put("original",it.getBoolean("selected")).put("originalApk",it.getBoolean("apk"))}
        require(apps.size<=100000&&apps.map{it.getString("pkg")}.toSet().size==apps.size)
        lease=draft.substringBefore('\n');require(lease.matches(Regex("[1-9][0-9]*")))
        saved=JSONObject(draft.substringAfter('\n',"{}"))
        page=saved.optInt("page",0).coerceAtLeast(0);search=saved.optString("search");filter=saved.optString("filter","all").takeIf{it in setOf("all","yes","no")}?:"all"
        saved.optJSONObject("timeline")?.let{value->
            val kind=value.optString("mode")
            val sources=value.optJSONArray("sources")
            if(kind in setOf("match","account","cross","merge")&&value.opt("target") is String&&sources!=null&&sources.length()<=256&&(0 until sources.length()).all{sources.opt(it) is String})timeline=value
        }
        val byId=apps.associateBy{it.getString("pkg")}
        saved.optJSONArray("choices")?.let{rows->for(i in 0 until rows.length()){
            val row=rows.optJSONArray(i)?:continue
            if(row.length()!=3||row.opt(1) !is Boolean||row.opt(2) !is Boolean)continue
            byId[row.optString(0)]?.takeUnless{it.optBoolean("removed")}?.let{it.put("selected",row.getBoolean(1));it.put("apk",!singleChoice&&row.getBoolean(2))}
        }}
    }
    fun changed()=apps.filter{it.getBoolean("selected")!=it.getBoolean("original")||it.getBoolean("apk")!=it.getBoolean("originalApk")}
    fun filtered():List<JSONObject> {
        val q=search.trim().lowercase(java.util.Locale.ROOT)
        val result=apps.filter{a->("${a.getString("label")} ${a.getString("pkg")} ${a.optString("displayPackage")}").lowercase(java.util.Locale.ROOT).contains(q)&&(filter=="all"||a.getBoolean("selected")== (filter=="yes"))}
        return if(q.isEmpty())result else result.sortedBy{val v=it.getString("label").lowercase(java.util.Locale.ROOT);if(v.startsWith(q))0 else if(v.contains(q))1 else 2}
    }
    fun draft(extra:JSONObject=JSONObject()):String=lease+"\n"+extra.put("timeline",timeline).put("page",page).put("search",search).put("filter",filter)
        .put("choices",arr(changed().filterNot{it.optBoolean("removed")}.map{arr(listOf(it.getString("pkg"),it.getBoolean("selected"),it.getBoolean("apk")))})).toString()
    fun submission():String=apps.filterNot{it.optBoolean("removed")}.joinToString("\n"){it.getString("pkg")+"\t"+(if(it.getBoolean("selected"))1 else 0)+"\t"+(if(it.getBoolean("apk"))1 else 0)}
}
