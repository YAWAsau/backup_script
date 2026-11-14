package io.github.yawasau.speedbackup.webview

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import org.json.JSONObject
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.compositeOver
import top.yukonga.miuix.kmp.theme.darkColorScheme
import top.yukonga.miuix.kmp.theme.lightColorScheme
import com.materialkolor.scheme.SchemeTonalSpot
import com.materialkolor.hct.Hct
import com.materialkolor.dynamiccolor.ColorSpec
import com.materialkolor.dynamiccolor.DynamicScheme

internal class NativeAppearance(private val context:Context) {
    private data class PaletteCache(val seeds:Pair<Int,Int>,val json:String)
    companion object { @Volatile private var cachedPalette:PaletteCache?=null }
    private fun systemSeeds():Pair<Int,Int>?=try{
        if(android.os.Build.VERSION.SDK_INT<31)null else {
            // Match AppListTheme's resource source and seed selection. Recheck
            // on every entry so wallpaper/system palette changes invalidate it.
            val resources=context.createPackageContext("com.android.shell",0).resources
            fun seed(dark:Boolean):Int {
                val name=if(android.os.Build.VERSION.SDK_INT>=34)"system_primary_${if(dark)"dark" else "light"}" else "system_accent1_${if(dark)"200" else "600"}"
                val id=resources.getIdentifier(name,"color","android")
                require(id!=0)
                return resources.getColor(id,null) and 0xffffff
            }
            seed(false) to seed(true)
        }
    }catch(_:Exception){null}
    private var paletteSeeds:Pair<Int,Int>?=null
    private fun refreshPalette() {
        if(values["monet"]!="on"||values["appearance"] in setOf("space","night"))return
        // Same TonalSpot / 2025 / PHONE / contrast 0 as AppListTheme, using the
        // library already shipped by Miuix. No new root JVM on cold entry.
        // Check on every model so enabling Monet and system configuration changes
        // work within the current page, even if initial entry skipped the palette.
        val seeds=systemSeeds()?:Pair(0x6750a4,0xd0bcff)
        if(paletteSeeds==seeds)return
        val cached=cachedPalette?.takeIf{it.seeds==seeds}
        palette=if(cached!=null)JSONObject(cached.json) else {
            val result=JSONObject()
            for((mode,seed) in listOf("light" to seeds.first,"dark" to seeds.second)){
                val dark=mode=="dark"
                val s=SchemeTonalSpot(Hct.fromInt(seed or 0xff000000.toInt()),dark,0.0,ColorSpec.SpecVersion.SPEC_2025,DynamicScheme.Platform.PHONE)
                val roles=mapOf("seed" to seed,"bg" to if(dark)s.background else s.surfaceContainerLow,
                    "card" to s.surfaceBright,"field" to s.surfaceContainerHighest,"text" to s.onSurface,
                    "muted" to s.onSurfaceVariant,"line" to s.outline,"primary" to s.primary,
                    "pressed" to s.primaryContainer,"footer" to s.surfaceContainer,"danger" to s.error,
                    "selected" to s.secondaryContainer,"on-primary" to s.onPrimary,"accent" to s.secondaryContainer)
                result.put(mode,JSONObject().apply{for((key,color) in roles)put(key,"#%06x".format(java.util.Locale.ROOT,color and 0xffffff))})
            }
            cachedPalette=PaletteCache(seeds,result.toString());result
        }
        paletteSeeds=seeds
    }
    private val defaults=linkedMapOf("style" to "miuix","material-palette" to "TonalSpot","material-spec" to "SPEC_2025","appearance" to "system","scale" to "100","monet" to "on","glass-blur" to "on","glass-blur-strength" to "100","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off","glass-content" to "off","font-adaptive" to "off","language" to "zh-Hant")
    val values=LinkedHashMap(defaults)
    // A local appearance-only snapshot lets shortcut errors render before root/API startup.
    private val local=context.getSharedPreferences("native-appearance",Context.MODE_PRIVATE)
    fun loadLocal(){for(key in defaults.keys)local.getString(key,null)?.let{values[key]=it}}
    private fun rememberLocal(){
        val changed=values.filter{(key,value)->local.getString(key,null)!=value}
        if(changed.isNotEmpty())local.edit().apply{for((key,value) in changed)putString(key,value)}.apply()
    }
    private var palette=JSONObject()
    fun load(api:NativeApi){
        val preferences=try{JSONObject(api.get("preferences"))}catch(e:NativeApi.ApiFailure){if(e.status==400||e.status==404)null else throw e}
        for((key,default) in defaults)values[key]=(preferences?.optString(key,null)?:if(key in setOf("font-adaptive","glass-content","material-palette","material-spec"))default else api.get(key)).trim().substringBefore('\t').ifEmpty{default}
        for(key in listOf("glass-blur-strength","glass-light","glass-transparency","glass-refraction"))values[key]=(values[key]?.toIntOrNull()?:100).coerceIn(0,100).toString()
    }
    fun dark():Boolean=when(values["appearance"]){"dark","amoled","space","night"->true;"light"->false;else->(context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES}
    fun apply(model:JSONObject):JSONObject {
        rememberLocal()
        val material=values["style"]=="material"
        if(!material)refreshPalette()
        val dark=dark();val space=values["appearance"]=="space";val night=values["appearance"]=="night"
        if(!material){
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
        }
        model.put("materialDynamic",values["monet"]=="on")
        model.put("materialPalette",values["material-palette"]).put("materialSpec",values["material-spec"])
        if(material){
            val m=NativeMaterialColors.make(context,dark,values["monet"]=="on",values["appearance"]=="amoled",values["material-palette"]?:"TonalSpot",values["material-spec"]?:"SPEC_2025")
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
        return model.put("theme",values["appearance"]).put("nativeSky",space).put("nativeNightSky",night).put("uiStyle",values["style"]?:"miuix")
            .put("scale",((values["scale"]?.toIntOrNull()?:100)/100.0).coerceIn(.7,1.5)).put("uiLanguage",values["language"])
            .put("glassBlurStrength",values["glass-blur-strength"]?.toIntOrNull()?:100).put("glassBlur",values["glass-blur"]!="off").put("glassLight",values["glass-light"]?.toIntOrNull()?:100)
            .put("glassContent",values["glass-content"]=="on")
            .put("glassTransparency",values["glass-transparency"]?.toIntOrNull()?:100)
            .put("glassRefraction",values["glass-refraction"]?.toIntOrNull()?:100).put("glassAdaptive",values["glass-adaptive"]=="on")
            .put("reducedMotion",android.provider.Settings.Global.getFloat(context.contentResolver,android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,1f)==0f)
    }
}
