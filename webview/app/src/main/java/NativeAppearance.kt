package io.github.yawasau.speedbackup.webview

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import org.json.JSONObject
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.compositeOver

internal class NativeAppearance(private val context:Context) {
    private val defaults=linkedMapOf("style" to "miuix","material-palette" to "TonalSpot","material-spec" to "SPEC_2025","appearance" to "system","scale" to "100","monet" to "on","miuix-monet" to "off","glass-blur" to "on","glass-blur-strength" to "100","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off","glass-content" to "off","font-adaptive" to "off","language" to "zh-Hant")
    val values=LinkedHashMap(defaults)
    // A local appearance-only snapshot lets shortcut errors render before root/API startup.
    private val local=context.getSharedPreferences("native-appearance",Context.MODE_PRIVATE)
    private fun normalizeAppearance() {
        values["appearance"]=when(values["appearance"]?.trim()?.substringBefore('\t')) {
            "amoled","rainbow"->"dark"
            "space"->"space"
            "light"->"light"
            "dark"->"dark"
            "night"->"night"
            else->"system"
        }
    }
    fun loadLocal(){
        for(key in defaults.keys)local.getString(key,null)?.let{values[key]=it}
        normalizeAppearance()
    }
    private fun rememberLocal(){
        val changed=values.filter{(key,value)->local.getString(key,null)!=value}
        if(changed.isNotEmpty())local.edit().apply{for((key,value) in changed)putString(key,value)}.apply()
    }
    fun load(api:NativeApi){
        val preferences=try{JSONObject(api.get("preferences"))}catch(e:NativeApi.ApiFailure){if(e.status==400||e.status==404)null else throw e}
        for((key,default) in defaults)values[key]=(preferences?.optString(key,null)?:if(key in setOf("font-adaptive","glass-content","material-palette","material-spec","miuix-monet"))default else api.get(key)).trim().substringBefore('\t').ifEmpty{default}
        normalizeAppearance()
        for(key in listOf("glass-blur-strength","glass-light","glass-transparency","glass-refraction"))values[key]=(values[key]?.toIntOrNull()?:100).coerceIn(0,100).toString()
    }
    fun dark():Boolean=when(values["appearance"]){"dark","night","space"->true;"light"->false;else->(context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES}
    fun apply(model:JSONObject):JSONObject {
        normalizeAppearance()
        rememberLocal()
        val material=values["style"]=="material"
        val dark=dark()
        val night=values["appearance"]=="night"
        val space=values["appearance"]=="space"
        // Animated backdrops use standard Miuix controls, independently of Material Monet.
        val miuixDynamic=values["miuix-monet"]=="on"&&!night&&!space&&android.os.Build.VERSION.SDK_INT>=31
        val seed=NativeMiuixColors.systemSeed(context,dark)
        model.put("miuixSeed",seed).put("miuixDynamic",miuixDynamic)
        if(!material){
            val base=NativeMiuixColors.make(seed,dark,miuixDynamic,
                "TonalSpot","SPEC_2025")
            for((key,color) in mapOf(
                "background" to base.surface,
                "cardColor" to base.surfaceContainer,
                "fieldColor" to base.secondaryContainer,
                "foreground" to base.onSurface,
                "mutedColor" to base.onSurfaceVariantSummary.compositeOver(base.surfaceContainer),
                "lineColor" to base.outline,
                "accent" to base.primary
            ))model.put(key,color.toArgb().toLong() and 0xffffffffL)
        }
        model.put("materialDynamic",values["monet"]=="on")
        model.put("materialPalette",values["material-palette"]).put("materialSpec",values["material-spec"])
        if(material){
            val m=NativeMaterialColors.make(context,dark,values["monet"]=="on",values["material-palette"]?:"TonalSpot",values["material-spec"]?:"SPEC_2025")
            for((key,color) in mapOf("background" to m.surfaceContainer,"cardColor" to m.surfaceContainerLow,
                "fieldColor" to m.surfaceContainerHighest,"foreground" to m.onSurface,
                "mutedColor" to m.onSurfaceVariant,"lineColor" to m.outline,"accent" to m.primary))
                model.put(key,color.toArgb().toLong() and 0xffffffffL)
        }
        model.put("controlForeground",model.getLong("foreground"))
        model.put("controlMuted",model.getLong("mutedColor"))
        model.put("controlDark",dark)
        val fontAdaptive=values["font-adaptive"]=="on"
        if(fontAdaptive){
            val ink=if(NativeUserWallpaper.backgroundLuminance(model.getLong("background").toInt())>=.82f)Color.BLACK else Color.WHITE
            model.put("foreground",ink.toLong() and 0xffffffffL)
            model.put("mutedColor",(ink and 0x00ffffff or 0xaa000000.toInt()).toLong() and 0xffffffffL)

        }
        model.put("fontAdaptive",fontAdaptive)
        return model.put("theme",values["appearance"]).put("nativeNightSky",night).put("nativeSky",space).put("uiStyle",values["style"]?:"miuix")
            .put("scale",((values["scale"]?.toIntOrNull()?:100)/100.0).coerceIn(.7,1.5)).put("uiLanguage",values["language"])
            .put("glassBlurStrength",values["glass-blur-strength"]?.toIntOrNull()?:100).put("glassBlur",values["glass-blur"]!="off").put("glassLight",values["glass-light"]?.toIntOrNull()?:100)
            .put("glassContent",values["glass-content"]=="on")
            .put("glassTransparency",values["glass-transparency"]?.toIntOrNull()?:100)
            .put("glassRefraction",values["glass-refraction"]?.toIntOrNull()?:100).put("glassAdaptive",values["glass-adaptive"]=="on")
            .put("reducedMotion",android.provider.Settings.Global.getFloat(context.contentResolver,android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,1f)==0f)
    }
}
