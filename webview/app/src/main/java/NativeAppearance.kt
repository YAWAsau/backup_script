package io.github.yawasau.speedbackup.webview

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import org.json.JSONObject
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.compositeOver
import top.yukonga.miuix.kmp.theme.darkColorScheme
import top.yukonga.miuix.kmp.theme.lightColorScheme

internal class NativeAppearance(private val context:Context) {
    private val defaults=linkedMapOf("appearance" to "system","scale" to "100","monet" to "on","glass-blur" to "on","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off","language" to "zh-Hant")
    val values=LinkedHashMap(defaults)
    private var palette=JSONObject()
    fun load(api:NativeApi){
        val preferences=try{JSONObject(api.get("preferences"))}catch(e:NativeApi.ApiFailure){if(e.status==400||e.status==404)null else throw e}
        for((key,default) in defaults)values[key]=(preferences?.optString(key,null)?:api.get(key)).trim().substringBefore('\t').ifEmpty{default}
        for(key in listOf("glass-light","glass-transparency","glass-refraction"))values[key]=(values[key]?.toIntOrNull()?:100).coerceIn(0,100).toString()
        palette=try{JSONObject(api.get("theme"))}catch(_:Exception){JSONObject()}
    }
    fun dark():Boolean=when(values["appearance"]){"dark","space","night"->true;"light"->false;else->(context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES}
    fun apply(model:JSONObject):JSONObject {
        val dark=dark();val space=values["appearance"]=="space";val night=values["appearance"]=="night"
        // Same Miuix semantic palette used by KernelSU's light/dark themes.
        val base=if(dark)darkColorScheme() else lightColorScheme()
        fun hex(c:androidx.compose.ui.graphics.Color)="#%08x".format(c.toArgb())
        val standard=mapOf("background" to hex(base.surface),"cardColor" to hex(base.surfaceVariant),
            "fieldColor" to hex(base.secondaryContainer),"foreground" to hex(base.onSurface),
            "mutedColor" to hex(base.onSurfaceVariantSummary.compositeOver(base.surfaceVariant)),
            "lineColor" to hex(base.outline),"accent" to hex(base.primary))
        // Sky choices change the backdrop animation, not the Miuix control palette.
        val colors=standard
        val mapping=mapOf("background" to "bg","cardColor" to "card","fieldColor" to "field","foreground" to "text","mutedColor" to "muted","lineColor" to "line","accent" to "primary")
        val dynamic=palette.optJSONObject(if(dark)"dark" else "light")
        for((key,fallback) in colors){
            val color=if(!space&&!night&&values["monet"]=="on")dynamic?.optString(mapping[key],fallback)?:fallback else fallback
            model.put(key,(try{Color.parseColor(color)}catch(_:Exception){Color.parseColor(fallback)}).toLong() and 0xffffffffL)
        }
        return model.put("theme",values["appearance"]).put("nativeSky",space).put("nativeNightSky",night).put("uiStyle","miuix")
            .put("scale",((values["scale"]?.toIntOrNull()?:100)/100.0).coerceIn(.7,1.5)).put("uiLanguage",values["language"])
            .put("glassBlur",values["glass-blur"]!="off").put("glassLight",values["glass-light"]?.toIntOrNull()?:100)
            .put("glassTransparency",values["glass-transparency"]?.toIntOrNull()?:100)
            .put("glassRefraction",values["glass-refraction"]?.toIntOrNull()?:100).put("glassAdaptive",values["glass-adaptive"]=="on")
            .put("reducedMotion",android.provider.Settings.Global.getFloat(context.contentResolver,android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,1f)==0f)
    }
}
