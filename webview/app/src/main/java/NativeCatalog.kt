package io.github.yawasau.speedbackup.webview

import android.content.Context
import org.json.JSONObject

/** Static data only; callers load this once on the model worker. */
internal class NativeCatalog(context:Context) {
    companion object {
        @Volatile private var cached:NativeCatalog?=null
        fun get(context:Context):NativeCatalog=cached?:synchronized(this){cached?:NativeCatalog(context.applicationContext).also{cached=it}}
    }
    private val language=com.xayah.dex.CCHelper()
    // Compatibility for backend-supplied labels. Local controls use stable IDs.
    private fun metadataAliases(labels:Map<String,String>):Map<String,String> = buildMap {
        for((label,key) in labels) {
            put(label,key);put(language.s2t(label),key);put(language.t2s(label),key)
        }
    }
    private val settingKeys by lazy { metadataAliases(nativeSettingIconLabels) }
    private val homeKeys by lazy { metadataAliases(nativeHomeIconLabels) }
    private val groupKeys by lazy { metadataAliases(mapOf("備份" to "backup","備份相關功能" to "backup","恢復" to "restore","恢復相關功能" to "restore")) }
    fun settingIconKey(label:String):String=settingKeys[label].orEmpty()
    fun homeIconKey(label:String):String=homeKeys[label]?:"unknown"
    fun groupOrder(label:String):Int=when(groupKeys[label]){"backup"->0;"restore"->1;else->2}
    private val translations=object:LinkedHashMap<String,String>(128,0.75f,true){
        override fun removeEldestEntry(eldest:MutableMap.MutableEntry<String,String>?):Boolean=size>512
    }
    fun text(value:String,locale:String):String {
        if(value.all{it.code<128})return value
        val simplified=locale=="zh-Hans"
        val key=(if(simplified)"S:" else "T:")+value
        if(value.length<=2048)synchronized(translations){translations[key]?.let{return it}}
        val converted=if(simplified)language.t2s(value) else language.s2t(value)
        if(value.length<=2048)synchronized(translations){translations[key]=converted}
        return converted
    }
    fun localize(model:JSONObject,locale:String){
        fun convert(value:String)=text(value,locale)
        fun visit(value:Any?){when(value){
            is org.json.JSONArray->for(i in 0 until value.length())visit(value.opt(i))
            is JSONObject->{
                val literal=value.optString("kind") in setOf("app","log","license","contributor")
                for(key in value.keys().asSequence().toList()){
                    if(key=="picker")continue // File names and paths are exact user data.
                    val child=value.opt(key)
                    if(child is String&&key=="detail"&&value.optBoolean("translateDetail"))value.put(key,if(child.startsWith("目前自訂值："))convert("目前自訂值：")+child.substringAfter("目前自訂值：") else convert(child))
                    else if(child is String&&key in setOf("label","title","subtitle","hint","cancel","caption","description","status","zeroLabel","unset")&&!((literal||value.optBoolean("literalLabel"))&&key=="label")&&!(key=="description"&&value.optBoolean("literalDescription")))value.put(key,if(child.startsWith("目前自訂值："))convert("目前自訂值：")+child.substringAfter("目前自訂值：") else convert(child))
                    else visit(child)
                }
                if(value.has("literalDetailSuffix")){value.put("detail",value.optString("detail")+value.optString("literalDetailSuffix"));value.remove("literalDetailSuffix")}
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
