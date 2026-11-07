package com.kyant.backdrop.catalog.components

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
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
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/** Adapted from AndroidLiquidGlass AdaptiveLuminanceGlassContent (Apache-2.0).
 * Sample only while visible, once per second, never in the drawing callback.
 */
internal class AdaptiveGlass(val layer:GraphicsLayer,val luminance:Animatable<Float,androidx.compose.animation.core.AnimationVector1D>,val textLight:Animatable<Float,androidx.compose.animation.core.AnimationVector1D>,var samplingNeeded:Boolean){
    var recordedTick=-1
    fun DrawScope.capture(tick:Int,draw:DrawScope.()->Unit){
        if(!samplingNeeded||recordedTick==tick||size.width<=0f||size.height<=0f)return
        val sx=5f/size.width;val sy=5f/size.height
        layer.record(size=IntSize(5,5)){scale(sx,sy,pivot=Offset.Zero){draw()}}
        recordedTick=tick
    }
    val contentColor:Color get()=androidx.compose.ui.graphics.lerp(Color.Black,Color.White,textLight.value)
    fun fixedContentColor(surface:Color,opacity:Float):Color {
        val a=opacity.coerceIn(0f,1f)
        val surfaceLight=surface.red*.2126f+surface.green*.7152f+surface.blue*.0722f
        val effective=luminance.value*(1f-a)+surfaceLight*a
        return if(effective>.5f)Color.Black else Color.White
    }
    fun BackdropEffectScope.material(enabled:Boolean,blurEnabled:Boolean){
        if(!enabled){vibrancy();if(blurEnabled)blur(GlassMaterial.BlurDp.dp.toPx());return}
        val v=luminance.value*2f-1f
        val l=kotlin.math.sign(v)*v*v
        colorControls(brightness=if(l>0f).1f+.4f*l else .1f+.3f*l,contrast=if(l>0f)1f-l else 1f,saturation=1.5f)
        if(blurEnabled)blur((if(l>0f)8f+8f*l else 8f+6f*l).dp.toPx())
    }
}
internal val LocalGlassContrastEnabled=staticCompositionLocalOf { false }
internal val LocalGlassContentColor=staticCompositionLocalOf { Color.Unspecified }

internal val LocalGlassBackgroundKey=staticCompositionLocalOf { "default" }
internal val LocalGlassDynamicBackground=staticCompositionLocalOf { false }
internal val LocalGlassInitialLuminance=staticCompositionLocalOf { .5f }
private val adaptiveCache=object:LinkedHashMap<String,Pair<Float,Float>>(64,.75f,true){
    override fun removeEldestEntry(eldest:MutableMap.MutableEntry<String,Pair<Float,Float>>)=size>64
}

@Composable internal fun rememberAdaptiveGlass(light:Boolean,identity:String):AdaptiveGlass {
    val controls=GlassMaterial.LocalControls.current
    val active=GlassMaterial.LocalActive.current
    val contrast=LocalGlassContrastEnabled.current
    val reduced=GlassMaterial.LocalReducedMotion.current
    val layer=rememberGraphicsLayer()
    val config=androidx.compose.ui.platform.LocalConfiguration.current
    val dynamic=LocalGlassDynamicBackground.current
    val cacheKey=LocalGlassBackgroundKey.current+":"+config.screenWidthDp+":"+config.screenHeightDp+":"+light+":"+identity
    val seed=LocalGlassInitialLuminance.current
    val sample=remember(layer,cacheKey,dynamic){
        val initial=adaptiveCache[cacheKey]?:Pair(seed,if(seed>.5f)0f else 1f)
        AdaptiveGlass(layer,Animatable(initial.first),Animatable(initial.second),dynamic||!adaptiveCache.containsKey(cacheKey))
    }
    val tick=controls.sampleTick
    LaunchedEffect(sample,controls.adaptive,contrast,active,reduced,tick){
        if((!controls.adaptive&&!contrast)||!active||!sample.samplingNeeded)return@LaunchedEffect
        delay(350) // Never adapt against an in-flight page position.
        withFrameNanos{}
        withFrameNanos{}
        if(sample.recordedTick==tick){
            try {
                val snapshot=layer.toImageBitmap().asAndroidBitmap()
                val readable=if(snapshot.config==Bitmap.Config.HARDWARE)snapshot.copy(Bitmap.Config.ARGB_8888,false) else snapshot
                val pixels=IntArray(25)
                val value=try{
                    readable.getPixels(pixels,0,5,0,0,5,5)
                    pixels.sumOf{p->.2126*((p shr 16)and 255)+.7152*((p shr 8)and 255)+.0722*(p and 255)}.toFloat()/(25*255)
                }finally{if(readable!==snapshot)readable.recycle();snapshot.recycle()}
                val textTarget=when{value>.55f->0f;value<.45f->1f;else->sample.textLight.targetValue}
                if(reduced){sample.luminance.snapTo(value);sample.textLight.snapTo(textTarget)}
                else coroutineScope{launch{sample.textLight.animateTo(textTarget,tween(300))};sample.luminance.animateTo(value,tween(300))}
                adaptiveCache[cacheKey]=Pair(sample.luminance.value,sample.textLight.value)
                if(!dynamic)sample.samplingNeeded=false
            }catch(e:kotlinx.coroutines.CancellationException){throw e}catch(_:Exception){/* Keep last valid material. */}
        }
    }
    return sample
}
