package io.github.yawasau.speedbackup.webview

import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import kotlinx.coroutines.isActive
import kotlin.math.sin

// Time is read only while drawing, never by layout. Cancellation freezes the
// accumulated time, so resume does not jump or restart the color cycle.
@Composable private fun brandTime(playing:Boolean):State<Float> {
    val time=remember{mutableFloatStateOf(0f)}
    LaunchedEffect(playing) {
        if(!playing)return@LaunchedEffect
        val offset=time.floatValue
        val origin=withFrameNanos{it}
        var last=origin
        while(isActive) {
            val now=withFrameNanos{it}
            if(now-last>=16_000_000L){time.floatValue=offset+(now-origin)/1_000_000_000f;last=now}
        }
    }
    return time
}

@Composable internal fun Modifier.brandInk(playing:Boolean,dark:Boolean):Modifier {
    val time=brandTime(playing)
    val colors=remember(dark){if(dark)listOf(Color(0xff7293ff),Color(0xffbd83e8),Color(0xff66c8ee),Color(0xff7293ff))
        else listOf(Color(0xff384cbd),Color(0xff8b3c9b),Color(0xff176c9f),Color(0xff384cbd))}
    return graphicsLayer{compositingStrategy=CompositingStrategy.Offscreen}.drawWithContent {
        drawContent()
        val shift=sin(time.value*.45f)*size.width*.4f
        drawRect(Brush.linearGradient(colors,Offset(-size.width*.4f+shift,0f),Offset(size.width*1.4f+shift,size.height)),blendMode=BlendMode.SrcIn)
    }
}
