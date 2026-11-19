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
    // Explicit KernelSU palette choice; shared by light and dark.
    private val FIXED_MATERIAL_SEED = Color(0xFF2196F3)
    private data class Key(val seed:Int,val dark:Boolean,val style:String,val spec:String)
    private val cache=object:android.util.LruCache<Key,ColorScheme>(8){}
    val styles=listOf("TonalSpot","Neutral","Vibrant","Expressive","Rainbow","FruitSalad","Monochrome","Fidelity","Content","Cmf")
    fun specs(style:String)=when(style){
        "Cmf"->listOf("SPEC_2026")
        "TonalSpot","Neutral","Vibrant","Expressive"->listOf("SPEC_2021","SPEC_2025")
        else->listOf("SPEC_2021")
    }
    fun effectiveSpec(style:String,spec:String)=spec.takeIf{it in specs(style)}?:specs(style).last()
    fun make(context:Context,dark:Boolean,dynamic:Boolean,styleName:String="TonalSpot",specName:String="SPEC_2025"):ColorScheme {
        val seed=if(dynamic&&android.os.Build.VERSION.SDK_INT>=31) {
            (if(dark)dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)).primary
        } else FIXED_MATERIAL_SEED
        val style=PaletteStyle.fromName(styleName.takeIf{it in styles}?:"TonalSpot")
        val spec=ColorSpec.SpecVersion.valueOf(effectiveSpec(style.name,specName))
        val key=Key(seed.toArgb(),dark,style.name,spec.name)
        cache.get(key)?.let{return it}
        val scheme=dynamicColorScheme(seedColor=seed,isDark=dark,isAmoled=false,
            style=style,specVersion=spec)
        cache.put(key,scheme);return scheme
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
                data.optBoolean("materialDynamic"),
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
            val dark=data.optBoolean("controlDark")
            val dynamic=data.optBoolean("miuixDynamic")
            val seed=data.optInt("miuixSeed",0xff6750a4.toInt())
            // Use the model's exact Android seed snapshot and resolved dark flag.
            // NativeMiuixColors remains the worker-side model cache. The public
            // controller remembers its matching Monet palette in composition.
            val controller=remember(seed,dark,dynamic) {
                top.yukonga.miuix.kmp.theme.ThemeController(
                    colorSchemeMode=if(dynamic)
                        top.yukonga.miuix.kmp.theme.ColorSchemeMode.MonetSystem
                    else top.yukonga.miuix.kmp.theme.ColorSchemeMode.System,
                    keyColor=Color(seed),
                    isDark=dark,
                    paletteStyle=top.yukonga.miuix.kmp.theme.ThemePaletteStyle.TonalSpot,
                    colorSpec=top.yukonga.miuix.kmp.theme.ThemeColorSpec.Spec2025
                )
            }
            // This overload also provides the mode used by isDynamicColor.
            top.yukonga.miuix.kmp.theme.MiuixTheme(controller=controller,content=content)
        }
    }
}

// Mapping and scheme selection adapted from compose-miuix-ui ThemeController.kt
// and MonetMapping.kt.
// Copyright 2025, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy at https://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

internal object NativeMiuixColors {
    private data class Key(val seed:Int,val dark:Boolean,val style:String,val spec:String)
    private val cache=object:android.util.LruCache<Key,top.yukonga.miuix.kmp.theme.Colors>(16){}
    private val light by lazy { top.yukonga.miuix.kmp.theme.lightColorScheme() }
    private val darkColors by lazy { top.yukonga.miuix.kmp.theme.darkColorScheme() }

    // KSU's Miuix ThemeController keyColor source, not shell resource guesses.
    // Called at model boundaries, never from an animation or drawing loop.
    fun systemSeed(context:Context,dark:Boolean):Int =
        if(android.os.Build.VERSION.SDK_INT>=31)
            (if(dark)dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)).primary.toArgb()
        else 0xff6750a4.toInt()

    @Synchronized
    fun make(seed:Int,dark:Boolean,dynamic:Boolean,styleName:String,specName:String):top.yukonga.miuix.kmp.theme.Colors {
        if(!dynamic)return if(dark)darkColors else light
        val style=styleName.takeIf{it in NativeMaterialColors.styles}?:"TonalSpot"
        val specNameEffective=NativeMaterialColors.effectiveSpec(style,specName)
        val key=Key(seed,dark,style,specNameEffective)
        cache.get(key)?.let{return it}
        val result=generate(seed,dark,style,ColorSpec.SpecVersion.valueOf(specNameEffective))
        cache.put(key,result)
        return result
    }

    private fun generate(seed:Int,dark:Boolean,style:String,spec:ColorSpec.SpecVersion):top.yukonga.miuix.kmp.theme.Colors {
        val hct=com.materialkolor.hct.Hct.fromInt(seed)
        val platform=com.materialkolor.dynamiccolor.DynamicScheme.Platform.PHONE
        val s:com.materialkolor.dynamiccolor.DynamicScheme=when(style) {
            "Neutral"->com.materialkolor.scheme.SchemeNeutral(hct,dark,0.0,spec,platform)
            "Vibrant"->com.materialkolor.scheme.SchemeVibrant(hct,dark,0.0,spec,platform)
            "Expressive"->com.materialkolor.scheme.SchemeExpressive(hct,dark,0.0,spec,platform)
            "Rainbow"->com.materialkolor.scheme.SchemeRainbow(hct,dark,0.0,spec,platform)
            "FruitSalad"->com.materialkolor.scheme.SchemeFruitSalad(hct,dark,0.0,spec,platform)
            "Monochrome"->com.materialkolor.scheme.SchemeMonochrome(hct,dark,0.0,spec,platform)
            "Fidelity"->com.materialkolor.scheme.SchemeFidelity(hct,dark,0.0,spec,platform)
            "Content"->com.materialkolor.scheme.SchemeContent(hct,dark,0.0,spec,platform)
            "Cmf"->com.materialkolor.scheme.SchemeCmf(hct,dark,0.0,spec,platform)
            else->com.materialkolor.scheme.SchemeTonalSpot(hct,dark,0.0,spec,platform)
        }
        // Exact upstream alpha compositing, including opaque disabled roles.
        fun opaque(color:Color,alpha:Float,bg:Color):Color {
            val fg=color.copy(alpha=alpha)
            val fa=fg.alpha
            val ba=bg.alpha
            val outA=fa+ba*(1f-fa)
            if(outA==0f)return Color(0f,0f,0f,1f)
            return Color(
                (fg.red*fa+bg.red*ba*(1f-fa))/outA,
                (fg.green*fa+bg.green*ba*(1f-fa))/outA,
                (fg.blue*fa+bg.blue*ba*(1f-fa))/outA,1f)
        }
        val surface=Color(s.surface)
        val disabledPrimary=opaque(Color(s.primary),.38f,surface)
        val disabledSecondary=opaque(Color(s.outlineVariant),.5f,surface)
        val disabledSecondaryVariant=opaque(Color(s.surfaceContainerHigh),.6f,surface)
        return top.yukonga.miuix.kmp.theme.Colors(
            primary=Color(s.primary),
            onPrimary=Color(s.onPrimary),
            primaryVariant=Color(s.primaryFixed),
            onPrimaryVariant=Color(s.onPrimaryFixed),
            error=Color(s.error),
            onError=Color(s.onError),
            errorContainer=Color(s.errorContainer),
            onErrorContainer=Color(s.onErrorContainer),
            primaryContainer=Color(s.primaryContainer),
            onPrimaryContainer=Color(s.onPrimaryContainer),
            secondary=Color(s.outlineVariant),
            onSecondary=Color(s.outline),
            secondaryVariant=Color(s.surfaceContainerHigh),
            onSecondaryVariant=Color(s.onSurface),
            secondaryContainer=Color(s.secondaryContainer),
            onSecondaryContainer=Color(s.onSecondaryContainer),
            secondaryContainerVariant=Color(s.surfaceContainerHighest),
            onSecondaryContainerVariant=Color(s.onSurfaceVariant),
            tertiaryContainer=Color(s.tertiaryContainer),
            onTertiaryContainer=Color(s.onTertiaryContainer),
            tertiaryContainerVariant=Color(s.onTertiaryContainer),
            background=Color(s.background),
            onBackground=Color(s.onBackground),
            onBackgroundVariant=Color(s.primary),
            surface=Color(s.surface),
            onSurface=Color(s.onSurface),
            surfaceVariant=Color(s.surfaceVariant),
            onSurfaceVariantSummary=Color(s.onSurfaceVariant),
            onSurfaceVariantActions=Color(s.onSurfaceVariant),
            disabledOnSurface=Color(s.onSurface),
            surfaceContainer=Color(s.surfaceContainer),
            onSurfaceContainer=Color(s.onSurface),
            onSurfaceContainerVariant=Color(s.onSurfaceVariant),
            surfaceContainerHigh=Color(s.surfaceContainerHigh),
            surfaceContainerHighest=Color(s.surfaceContainerHighest),
            onSurfaceContainerHighest=Color(s.onSurface),
            outline=Color(s.outline),
            dividerLine=Color(s.outlineVariant),
            sliderKeyPoint=Color(s.primary),
            sliderKeyPointForeground=Color(s.surfaceContainerHigh),
            onSurfaceSecondary=opaque(Color(s.onSurface),.8f,surface),
            onSurfaceContainerHigh=opaque(Color(s.onSurface),.8f,Color(s.surfaceContainerHigh)),
            sliderBackground=opaque(Color(s.primary),.2f,surface),
            disabledPrimary=disabledPrimary,
            disabledOnPrimary=opaque(Color(s.onPrimary),.38f,disabledPrimary),
            disabledPrimaryButton=disabledPrimary,
            disabledOnPrimaryButton=opaque(Color(s.onPrimary),.6f,disabledPrimary),
            disabledPrimarySlider=disabledPrimary,
            disabledSecondary=disabledSecondary,
            disabledOnSecondary=opaque(Color(s.onSurface),.38f,disabledSecondary),
            disabledSecondaryVariant=disabledSecondaryVariant,
            disabledOnSecondaryVariant=opaque(Color(s.onSurface),.38f,disabledSecondaryVariant),
            windowDimming=Color.Black.copy(alpha=if(dark).6f else .3f)
        )
    }
}
