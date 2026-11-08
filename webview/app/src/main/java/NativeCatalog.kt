package io.github.yawasau.speedbackup.webview

import android.content.Context
import org.json.JSONObject

/** Static data only; callers load this once on the model worker. */
internal class NativeCatalog(context:Context) {
    companion object {
        @Volatile private var cached:NativeCatalog?=null
        fun get(context:Context):NativeCatalog=cached?:synchronized(this){cached?:NativeCatalog(context.applicationContext).also{cached=it}}
    }
    private val language=context.assets.open("language.json").bufferedReader().use{JSONObject(it.readText())}
    fun text(value:String,locale:String):String {
        val table=language.getJSONObject(if(locale=="zh-Hans")"simplified" else "traditional")
        return buildString(value.length){for(ch in value)append(table.optString(ch.toString(),ch.toString()))}
    }
    fun localize(model:JSONObject,locale:String){
        val table=language.getJSONObject(if(locale=="zh-Hans")"simplified" else "traditional")
        fun convert(value:String)=buildString(value.length){for(ch in value)append(table.optString(ch.toString(),ch.toString()))}
        fun visit(value:Any?){when(value){
            is org.json.JSONArray->for(i in 0 until value.length())visit(value.opt(i))
            is JSONObject->{
                val literal=value.optString("kind") in setOf("app","log","license","contributor")
                for(key in value.keys().asSequence().toList()){
                    if(key=="picker")continue // File names and paths are exact user data.
                    val child=value.opt(key)
                    if(child is String&&key=="detail"&&value.optBoolean("translateDetail"))value.put(key,if(child.startsWith("目前自訂值："))convert("目前自訂值：")+child.substringAfter("目前自訂值：") else convert(child))
                    else if(child is String&&key in setOf("label","title","subtitle","hint","cancel","caption","description","status","zeroLabel","unset")&&!(literal&&key=="label")&&!(key=="description"&&value.optBoolean("literalDescription")))value.put(key,if(child.startsWith("目前自訂值："))convert("目前自訂值：")+child.substringAfter("目前自訂值：") else convert(child))
                    else visit(child)
                }
            }
        }}
        visit(model)
    }
    val communityUrl=context.assets.open("community.json").bufferedReader().use{JSONObject(it.readText()).getString("url")}
    private val settings=context.assets.open("settings-labels.json").bufferedReader().use{JSONObject(it.readText())}
    fun label(key:String)=settings.getJSONObject("labels").optString(key,key)
    fun help(key:String,fallback:String,mode:String)=when(key){
        "setDisplayPowerMode"->(if(mode=="restore")"恢復" else "備份")+"開始後啟用亮屏偽裝。"
        "Background_apps_ignore"->"選擇略過執行中的應用，或繼續處理這些應用。"
        else->settings.getJSONObject("help").optString(key,fallback.ifEmpty{"沿用原設定值；留空不會自動套入其他值。"})
    }
}
