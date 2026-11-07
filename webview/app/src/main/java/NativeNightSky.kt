/*
 * Copyright (C) 2020 The Android Open Source Project
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Adapted from Android android-17.0.0_r1 PlatLogoActivity.Starfield.
 * Changes: Compose lifecycle, normalized positions, SDR colors, background only.
 * No logo, touch interaction, warp, vibration, HDR flash or game launch.
 */
package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import kotlinx.coroutines.isActive
import kotlin.math.*
import kotlin.random.Random

/** One persistent star field across pages and IME changes; state is read only during draw. */
@Composable
internal fun NativeNightSky(modifier:Modifier, active:Boolean) {
    val stars=remember { NightStars() }
    val frame=remember { mutableIntStateOf(0) }
    LaunchedEffect(active) {
        if(active) {
            var previous=withFrameNanos { it }
            while(isActive) withFrameNanos { now ->
                val elapsed=now-previous
                if(elapsed>=32_000_000L) {
                    if(elapsed<1_000_000_000L) stars.advance(elapsed/1_000_000_000f)
                    previous=now
                    frame.intValue++
                }
            }
        }
    }
    Canvas(modifier) {
        frame.intValue
        drawIntoCanvas { stars.draw(it.nativeCanvas,size.width,size.height,density) }
    }
}

private class NightStars {
    private val random=Random(1701090)
    private val positions=FloatArray(128*2)
    private val pixels=FloatArray(128*2)
    private val paint=android.graphics.Paint().apply { style=android.graphics.Paint.Style.STROKE }
    init { repeat(128) { spawn(it,1f) } }
    private fun spawn(index:Int,radius:Float) {
        val angle=random.nextDouble()*2*PI
        val distance=random.nextFloat()*radius
        positions[index*2]=(cos(angle)*distance).toFloat()
        positions[index*2+1]=(sin(angle)*distance).toFloat()
    }
    fun advance(seconds:Float) {
        repeat(128) { i ->
            val scale=1f+.05f*seconds*(i/32+1)
            val x=positions[i*2]*scale;val y=positions[i*2+1]*scale
            if(x*x+y*y>=1f)spawn(i,.1f)
            else {positions[i*2]=x;positions[i*2+1]=y}
        }
    }
    fun draw(canvas:android.graphics.Canvas,width:Float,height:Float,density:Float) {
        canvas.drawColor(android.graphics.Color.BLACK)
        if(width<=0f||height<=0f)return
        // Match AOSP's padded radial field; normalized positions survive a real resize.
        val radius=hypot(width,height)*.5f+density*256f
        for(i in positions.indices)pixels[i]=positions[i]*radius
        val save=canvas.save()
        try {
            canvas.translate(width*.5f,height*.5f)
            canvas.rotate(45f)
            repeat(4) { plane ->
                val white=((plane+1)/3f*255).toInt().coerceIn(0,255)
                paint.color=android.graphics.Color.rgb(white,white,white)
                paint.strokeWidth=2*density*(plane+1)
                canvas.drawPoints(pixels,plane*64,64,paint)
            }
        } finally { canvas.restoreToCount(save) }
    }
}
