package com.kyant.backdrop.catalog.components

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.BackdropEffectScope
import com.kyant.backdrop.effects.colorControls
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.vibrancy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.graphics.asComposeRenderEffect
import com.kyant.backdrop.asAndroidRuntimeShader
import com.kyant.backdrop.isRuntimeShaderSupported
import com.kyant.backdrop.effects.effect

// Adapt the material at the point where content passes underneath it. The small
// neighbourhood feathers the lighting boundary without blurring the source image.
private const val SpatialMaterialShader = """
uniform shader content;
uniform float radius;
float lightAt(float2 p) {
    half4 c = content.eval(p);
    return dot(float3(c.rgb) / max(float(c.a), 0.0001), float3(0.2126, 0.7152, 0.0722));
}
half4 main(float2 p) {
    half4 src = content.eval(p);
    float a = float(src.a);
    float3 rgb = float3(src.rgb) / max(a, 0.0001);
    float gray = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float light = (4.0 * gray
        + lightAt(p + float2(radius, 0.0)) + lightAt(p - float2(radius, 0.0))
        + lightAt(p + float2(0.0, radius)) + lightAt(p - float2(0.0, radius))) / 8.0;
    float v = clamp(light, 0.0, 1.0) * 2.0 - 1.0;
    float l = sign(v) * v * v;
    float brightness = l > 0.0 ? 0.1 * (1.0 - l) : 0.1 + 0.3 * l;
    rgb = clamp(mix(float3(gray), rgb, 1.5) + brightness, 0.0, 1.0);
    return half4(half3(rgb * a), src.a);
}
"""

/** Adapted from AndroidLiquidGlass AdaptiveLuminanceGlassContent (Apache-2.0).
 * Per-pixel material on API 33+. Older devices sample only while stationary and visible.
 */
internal class AdaptiveGlass(val layer:GraphicsLayer,val luminance:Animatable<Float,androidx.compose.animation.core.AnimationVector1D>){
    var recordedTick=-1
    var sampledTick=-1
    fun DrawScope.capture(tick:Int,draw:DrawScope.()->Unit){
        if(isRuntimeShaderSupported())return
        if(recordedTick==tick||size.width<=0f||size.height<=0f)return
        val sx=5f/size.width;val sy=5f/size.height
        layer.record(size=IntSize(5,5)){scale(sx,sy,pivot=Offset.Zero){draw()}}
        recordedTick=tick
    }
    fun BackdropEffectScope.material(enabled:Boolean,blurEnabled:Boolean,blurStrength:Float){
        if(!enabled){vibrancy();if(blurEnabled)blur((GlassMaterial.BlurDp*3f*blurStrength/100f).dp.toPx());return}
        if(isRuntimeShaderSupported()){
            val shader=obtainRuntimeShader("SpatialAdaptiveGlass",SpatialMaterialShader)
            shader.setFloatUniform("radius",10.dp.toPx())
            effect(android.graphics.RenderEffect.createRuntimeShaderEffect(shader.asAndroidRuntimeShader(),"content").asComposeRenderEffect())
            if(blurEnabled)blur((GlassMaterial.BlurDp*3f*blurStrength/100f).dp.toPx())
            return
        }
        val v=luminance.value*2f-1f
        val l=kotlin.math.sign(v)*v*v
        // Bright content must keep its texture: reducing contrast toward zero and
        // adding up to .5 brightness turns an entire navigation bar into a white sheet.
        // Keep dark-background adaptation, and taper the small positive lift toward
        // zero as the sampled background approaches white. No foreground-based clamp.
        val brightness=if(l>0f).1f*(1f-l) else .1f+.3f*l
        colorControls(brightness=brightness,contrast=1f,saturation=1.5f)
        if(blurEnabled)blur(((if(l>0f)8f+8f*l else 8f+6f*l)*3f*blurStrength/100f).dp.toPx())
    }
}

internal val LocalGlassBackgroundKey=staticCompositionLocalOf { "default" }
internal val LocalGlassDynamicBackground=staticCompositionLocalOf { false }
internal val LocalGlassInitialLuminance=staticCompositionLocalOf { .5f }
private val adaptiveCache=object:LinkedHashMap<String,Float>(64,.75f,true){
    override fun removeEldestEntry(eldest:MutableMap.MutableEntry<String,Float>)=size>64
}

@Composable internal fun rememberAdaptiveGlass(light:Boolean,identity:String):AdaptiveGlass {
    val controls=GlassMaterial.LocalControls.current
    val active=GlassMaterial.LocalActive.current
    val reduced=GlassMaterial.LocalReducedMotion.current
    val layer=rememberGraphicsLayer()
    val config=androidx.compose.ui.platform.LocalConfiguration.current
    val dynamic=LocalGlassDynamicBackground.current
    val cacheKey=LocalGlassBackgroundKey.current+":"+config.screenWidthDp+":"+config.screenHeightDp+":"+light+":"+identity
    val seed=LocalGlassInitialLuminance.current
    val sample=remember(layer,cacheKey,dynamic){
        val initial=adaptiveCache[cacheKey]?:seed
        AdaptiveGlass(layer,Animatable(initial))
    }
    val tick=controls.sampleTick
    LaunchedEffect(sample,controls.adaptive,active,reduced,tick){
        if(isRuntimeShaderSupported()||!controls.adaptive||!active)return@LaunchedEffect
        // NativeChrome already debounces settled-view events. Do not re-read an old tick on resume.
        if(sample.sampledTick==tick)return@LaunchedEffect
        withFrameNanos{}
        withFrameNanos{}
        if(sample.recordedTick==tick){
            try {
                val snapshot=layer.toImageBitmap().asAndroidBitmap()
                // Hardware -> CPU copy can wait for the GPU. Never block Compose's
                // frame thread for that readback or the pixel reduction.
                val value=try {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default){
                        val readable=if(snapshot.config==Bitmap.Config.HARDWARE)snapshot.copy(Bitmap.Config.ARGB_8888,false) else snapshot
                        try {
                            val pixels=IntArray(25)
                            readable.getPixels(pixels,0,5,0,0,5,5)
                            pixels.sumOf{p->.2126*((p shr 16)and 255)+.7152*((p shr 8)and 255)+.0722*(p and 255)}.toFloat()/(25*255)
                        } finally { if(readable!==snapshot)readable.recycle() }
                    }
                } finally { snapshot.recycle() }
                val previous=sample.luminance.value
                if(android.util.Log.isLoggable("SpeedBackupGlass",android.util.Log.DEBUG))
                    android.util.Log.d("SpeedBackupGlass","surface=$identity sample=$value previous=$previous seed=$seed")
                // A moving halo must not make the entire capsule flash at each sample.
                // Ignore tiny dynamic noise; genuine changes use the same short transition.
                val target=if(dynamic&&kotlin.math.abs(value-previous)<.015f)previous else value
                // Commit the measurement before the cosmetic animation, which may be cancelled by motion.
                adaptiveCache[cacheKey]=target
                sample.sampledTick=tick
                if(reduced)sample.luminance.snapTo(target)
                else sample.luminance.animateTo(target,tween(180))
                // Cache is only an initial estimate. Every settled-view event must revalidate it.
            }catch(e:kotlinx.coroutines.CancellationException){throw e}catch(_:Exception){/* Keep last valid material. */}
        }
    }
    return sample
}
