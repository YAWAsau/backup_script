@file:OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
package io.github.yawasau.speedbackup.webview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.material3.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import com.materialkolor.material3.dynamicColorScheme
import com.materialkolor.PaletteStyle
import com.materialkolor.dynamiccolor.ColorSpec
import org.json.JSONObject

internal val LocalNativeMaterial = staticCompositionLocalOf { false }
internal val LocalNativeReducedMotion = staticCompositionLocalOf { false }

internal object NativeMaterialColors {
    private data class Key(val seed:Int,val dark:Boolean,val amoled:Boolean,val style:String,val spec:String)
    private val cache=object:android.util.LruCache<Key,ColorScheme>(8){}
    val styles=listOf("TonalSpot","Neutral","Vibrant","Expressive","Rainbow","FruitSalad","Monochrome","Fidelity","Content","Cmf")
    fun specs(style:String)=when(style){
        "Cmf"->listOf("SPEC_2026")
        "TonalSpot","Neutral","Vibrant","Expressive"->listOf("SPEC_2021","SPEC_2025")
        else->listOf("SPEC_2021")
    }
    fun effectiveSpec(style:String,spec:String)=spec.takeIf{it in specs(style)}?:specs(style).last()
    fun make(context:Context,dark:Boolean,dynamic:Boolean,amoled:Boolean,styleName:String="TonalSpot",specName:String="SPEC_2025"):ColorScheme {
        val seed=if(dynamic&&android.os.Build.VERSION.SDK_INT>=31) {
            (if(dark)dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)).primary
        } else Color(if(dark)0xffd0bcff else 0xff6750a4)
        val style=PaletteStyle.fromName(styleName.takeIf{it in styles}?:"TonalSpot")
        val spec=ColorSpec.SpecVersion.valueOf(effectiveSpec(style.name,specName))
        val key=Key(seed.toArgb(),dark,amoled,style.name,spec.name)
        cache.get(key)?.let{return it}
        val scheme=dynamicColorScheme(seedColor=seed,isDark=dark,isAmoled=amoled,
            style=style,specVersion=spec)
        val result=if(!amoled)scheme else scheme.copy(background=Color.Black,surface=Color.Black,
            surfaceDim=Color.Black,surfaceContainerLowest=Color.Black,surfaceContainerLow=Color.Black,
            surfaceContainer=Color.Black,surfaceContainerHigh=Color.Black,surfaceContainerHighest=Color.Black)
        cache.put(key,result);return result
    }
}

@Composable internal fun NativeAppTheme(data:JSONObject,content:@Composable ()->Unit) {
    val material=data.optString("uiStyle")=="material"
    val reduced=data.optBoolean("reducedMotion")
    CompositionLocalProvider(LocalNativeMaterial provides material,LocalNativeReducedMotion provides reduced) {
        if(material) {
            val context=LocalContext.current
            val configuration=androidx.compose.ui.platform.LocalConfiguration.current
            // A new model/configuration rechecks the system seed. Animation frames reuse
            // the same target palette while every color role keeps its spring below.
            val colors=remember(context,configuration,data){NativeMaterialColors.make(context,data.optBoolean("controlDark"),
                data.optBoolean("materialDynamic"),data.optString("theme")=="amoled",
                data.optString("materialPalette","TonalSpot"),data.optString("materialSpec","SPEC_2025"))}
            val motion=MotionScheme.expressive()
            @Composable fun animated(color:Color)=animateColorAsState(color,
                animationSpec=if(reduced)snap() else spring(),label="materialPalette").value
            val animatedColors=colors.copy(
                background=animated(colors.background),
                error=animated(colors.error),
                errorContainer=animated(colors.errorContainer),
                inverseOnSurface=animated(colors.inverseOnSurface),
                inversePrimary=animated(colors.inversePrimary),
                inverseSurface=animated(colors.inverseSurface),
                onBackground=animated(colors.onBackground),
                onError=animated(colors.onError),
                onErrorContainer=animated(colors.onErrorContainer),
                onPrimary=animated(colors.onPrimary),
                onPrimaryContainer=animated(colors.onPrimaryContainer),
                onSecondary=animated(colors.onSecondary),
                onSecondaryContainer=animated(colors.onSecondaryContainer),
                onSurface=animated(colors.onSurface),
                onSurfaceVariant=animated(colors.onSurfaceVariant),
                onTertiary=animated(colors.onTertiary),
                onTertiaryContainer=animated(colors.onTertiaryContainer),
                outline=animated(colors.outline),
                outlineVariant=animated(colors.outlineVariant),
                primary=animated(colors.primary),
                primaryContainer=animated(colors.primaryContainer),
                scrim=animated(colors.scrim),
                secondary=animated(colors.secondary),
                secondaryContainer=animated(colors.secondaryContainer),
                surface=animated(colors.surface),
                surfaceTint=animated(colors.surfaceTint),
                surfaceBright=animated(colors.surfaceBright),
                surfaceDim=animated(colors.surfaceDim),
                surfaceContainer=animated(colors.surfaceContainer),
                surfaceContainerHigh=animated(colors.surfaceContainerHigh),
                surfaceContainerHighest=animated(colors.surfaceContainerHighest),
                surfaceContainerLow=animated(colors.surfaceContainerLow),
                surfaceContainerLowest=animated(colors.surfaceContainerLowest),
                surfaceVariant=animated(colors.surfaceVariant),
                tertiary=animated(colors.tertiary),
                tertiaryContainer=animated(colors.tertiaryContainer),
                primaryFixed=animated(colors.primaryFixed),
                primaryFixedDim=animated(colors.primaryFixedDim),
                onPrimaryFixed=animated(colors.onPrimaryFixed),
                onPrimaryFixedVariant=animated(colors.onPrimaryFixedVariant),
                secondaryFixed=animated(colors.secondaryFixed),
                secondaryFixedDim=animated(colors.secondaryFixedDim),
                onSecondaryFixed=animated(colors.onSecondaryFixed),
                onSecondaryFixedVariant=animated(colors.onSecondaryFixedVariant),
                tertiaryFixed=animated(colors.tertiaryFixed),
                tertiaryFixedDim=animated(colors.tertiaryFixedDim),
                onTertiaryFixed=animated(colors.onTertiaryFixed),
                onTertiaryFixedVariant=animated(colors.onTertiaryFixedVariant)
            )
            MaterialExpressiveTheme(colorScheme=animatedColors,motionScheme=motion,content=content)
        } else {
            val base=if(data.optBoolean("controlDark"))top.yukonga.miuix.kmp.theme.darkColorScheme() else top.yukonga.miuix.kmp.theme.lightColorScheme()
            fun color(key:String)=Color(data.getLong(key).toInt())
            top.yukonga.miuix.kmp.theme.MiuixTheme(colors=base.copy(primary=color("accent"),
                onSurface=color("controlForeground"),onBackground=color("controlForeground"),
                surface=color("background"),surfaceVariant=color("cardColor"),surfaceContainer=color("cardColor"),
                secondaryContainer=color("fieldColor")),content=content)
        }
    }
}
