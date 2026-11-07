package com.kyant.backdrop.catalog.components

import androidx.compose.ui.unit.dp
import com.kyant.backdrop.BackdropEffectScope
import io.github.yawasau.speedbackup.webview.safeLens as lens
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.highlight.HighlightStyle
import com.kyant.backdrop.shadow.Shadow
import com.kyant.backdrop.shadow.InnerShadow
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.runtime.*

/** Shared optical surface for page buttons, action buttons and navigation. */
object GlassMaterial {
    class Controls(light:Int=100,transparency:Int=100,refraction:Int=100,adaptive:Boolean=false) {
        var refraction by mutableFloatStateOf(refraction.toFloat())
        var adaptive by mutableStateOf(adaptive)
        var editing by mutableStateOf(false)
        var pending by mutableStateOf(false)
        var revision=0L
        var sampleTick by mutableIntStateOf(0)
        var light by mutableFloatStateOf(light.toFloat())
        var transparency by mutableFloatStateOf(transparency.toFloat())
        val opacity:Float get()=(1f-transparency/100f).coerceIn(0f,1f)
    }
    val LocalControls=staticCompositionLocalOf { Controls() }
    val LocalActive=staticCompositionLocalOf { true }
    val LocalReducedMotion=staticCompositionLocalOf { false }
    val LocalBlurEnabled=staticCompositionLocalOf { true }
    const val BlurDp=8f
    const val LensDp=24f
    // A continuous rim has no directional zero crossings at diagonal corners.
    // Plain uses the existing outline pass without an extra shader or layer.
    val Rim=Highlight.Default.copy(style=HighlightStyle.Plain)
    // Shared with the navigation selection capsule. Keep this optical-only:
    // no position, scale, extra captured layer, or second blur pass.
    fun BackdropEffectScope.capsuleRefraction(progress:Float,baseDp:Float=0f,strength:Float=1f) {
        val amount=progress.coerceIn(0f,1f)
        // Blend into the capsule in ONE refraction pass; no stacked lens shaders.
        if(strength>0f&&(amount>0f||baseDp>0f)) lens((baseDp+(10f-baseDp)*amount).dp.toPx(),(baseDp+(14f-baseDp)*amount).dp.toPx()*strength,chromaticAberration=amount>0f)
    }
    fun capsuleHighlight(progress:Float)=Rim.copy(alpha=progress.coerceIn(0f,1f))
    fun capsuleShadow(progress:Float)=Shadow(alpha=progress.coerceIn(0f,1f))
    fun capsuleInnerShadow(progress:Float)=InnerShadow(radius=8f.dp*progress.coerceIn(0f,1f),alpha=progress.coerceIn(0f,1f))
    fun DrawScope.capsuleSurface(light:Boolean,progress:Float) {
        val amount=progress.coerceIn(0f,1f)
        drawRect(if(light)Color.Black.copy(alpha=.1f) else Color.White.copy(alpha=.1f),alpha=1f-amount)
        drawRect(Color.Black.copy(alpha=.03f*amount))
    }
    fun surface(light:Boolean,selected:Color?=null):Color {
        val base=if(light)Color(0xFFFAFAFA) else Color(0xFF121212)
        return (if(selected==null)base else lerp(base,selected,.18f)).copy(alpha=.32f)
    }
}
