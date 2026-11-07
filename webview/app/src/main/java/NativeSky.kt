package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import kotlin.math.*
import kotlin.random.Random

/** Draw-only animation: no DOM updates, bridge traffic or WebView texture uploads. */
@Composable
fun NativeSky(modifier:Modifier,active:Boolean) {
    val time=remember { mutableFloatStateOf(0f) }
    LaunchedEffect(active) { if(active){val initial=time.floatValue;val start=withFrameNanos{it};var last=start;while(true)withFrameNanos{if(it-last>=32_000_000){time.floatValue=initial+(it-start)/1_000_000_000f;last=it}}} }
    val colors=remember { listOf(Color(0xff72e6f2),Color(0xffb58aff),Color(0xffff8acb),Color(0xffffd47b),Color(0xff8ce1b7),Color(0xff86baff)) }
    val stars=remember { val r=Random(1026);List(96){floatArrayOf(r.nextFloat(),r.nextFloat(),.4f+r.nextFloat(),.7f+r.nextFloat()*1.4f)} }
    val icons=remember { val r=Random(719);List(8){floatArrayOf(r.nextFloat()*70,40+r.nextFloat()*30,r.nextFloat()*6.283f,r.nextFloat()*.7f-.35f,r.nextFloat()*360,(r.nextFloat()-.5f)*18)} }
    val box=remember { Path().apply { moveTo(10.5f,17f);lineTo(14.6f,9.6f);lineTo(33.4f,9.6f);lineTo(37.5f,17f);moveTo(13.7f,17f);lineTo(34.3f,17f);quadraticTo(37.5f,17f,37.5f,20.2f);lineTo(37.5f,33.3f);quadraticTo(37.5f,36.5f,34.3f,36.5f);lineTo(13.7f,36.5f);quadraticTo(10.5f,36.5f,10.5f,33.3f);lineTo(10.5f,20.2f);quadraticTo(10.5f,17f,13.7f,17f);moveTo(11.2f,17f);lineTo(36.8f,17f);moveTo(18.3f,25.8f);lineTo(23f,30.5f);lineTo(30.6f,22f) } }
    BoxWithConstraints(modifier) {
    val background=remember(constraints.maxWidth,constraints.maxHeight) {
        val width=384;val height=(384f*constraints.maxHeight/constraints.maxWidth.coerceAtLeast(1)).toInt().coerceIn(1,1536)
        val bitmap=android.graphics.Bitmap.createBitmap(width,height,android.graphics.Bitmap.Config.ARGB_8888)
        val canvas=android.graphics.Canvas(bitmap);canvas.drawColor(0xff080d22.toInt());val paint=android.graphics.Paint(3)
        val palette=intArrayOf(0xff72e6f2.toInt(),0xffb58aff.toInt(),0xffff8acb.toInt(),0xffffd47b.toInt())
        repeat(4){i->val x=width*(.15f+i*.24f);val y=height*(.15f+i*.23f);paint.shader=android.graphics.RadialGradient(x,y,width*.8f,intArrayOf((palette[i] and 0xffffff) or 0x38000000,0),null,android.graphics.Shader.TileMode.CLAMP);canvas.drawRect(0f,0f,width.toFloat(),height.toFloat(),paint)}
        paint.shader=null;paint.style=android.graphics.Paint.Style.STROKE
        repeat(3){band->val path=android.graphics.Path();repeat(41){point->val x=point/40f*width;val y=height*(.2f+band*.25f+.09f*sin(point/40f*7+band*2)+.025f*sin(point/40f*18+band));if(point==0)path.moveTo(x,y)else path.lineTo(x,y)};for(layer in 6 downTo 1){paint.color=(palette[band] and 0xffffff) or ((255*(.012f+(6-layer)*.003f)).toInt() shl 24);paint.strokeWidth=(12+layer*12)*min(height/800f,1.5f);canvas.drawPath(path,paint)}}
        bitmap.asImageBitmap()
    }
    val starBatch=remember { if(android.os.Build.VERSION.SDK_INT>=29)NativeStarBatch(stars.size) else null }
    val meteorBrushes=remember(constraints.maxWidth) {
        val unit=constraints.maxWidth/420f
        List(8){i->Brush.linearGradient(listOf(Color.Transparent,colors[i%6]),Offset.Zero,Offset((if(i%2==1)-100 else 100)*unit,48*unit))}
    }
    Canvas(Modifier.matchParentSize()) {
        val t=time.floatValue;val w=size.width;val h=size.height;val unit=w/420f
        translate(sin(t*.15f)*w*.025f,cos(t*.12f)*h*.025f){scale(1.07f,1.07f){drawImage(background,dstSize=IntSize(w.toInt(),h.toInt()))}}
        stars.forEachIndexed { i,s ->
            val y=(s[1]*(h+80*unit)+t*s[2]*22*unit)%(h+80*unit)-40*unit
            val edge=min(y/(40*unit),(h-y)/(40*unit)).coerceIn(0f,1f)
            val alpha=(.55f+sin(t*1.8f+s[0]*20)*.2f)*edge*edge*(3-2*edge)
            if(starBatch!=null)starBatch.set(i,s[0]*w,y,s[3]*unit,colors[i%6].copy(alpha=alpha).toArgb())
            else drawCircle(colors[i%6],s[3]*unit,Offset(s[0]*w,y),alpha=alpha)
        }
        starBatch?.let { batch->drawIntoCanvas { batch.draw(it.nativeCanvas) } }
        repeat(8){i->val travel=(t*.28f+i/8f)%1;val x=(if(i%2==1)1-travel else travel)*(w+400*unit)-200*unit;val y=((i*.31f)%.5f+travel*.5f)*h
            val end=Offset(x,y);val start=end-Offset((if(i%2==1)-100 else 100)*unit,48*unit)
            translate(start.x,start.y){drawLine(meteorBrushes[i],Offset.Zero,end-start,2*unit,alpha=sin(travel*PI.toFloat()).pow(2)*.8f)}
        }
        icons.forEachIndexed { i,a -> val age=t+a[0];val travel=(age/a[1])%1;val offset=a[3]*min(w,h);val distance=(travel*2-1)*(hypot(w,h)/2+80*unit+abs(offset));val x=w/2+cos(a[2])*distance-sin(a[2])*offset;val y=h/2+sin(a[2])*distance+cos(a[2])*offset
            translate(x,y){rotate(a[4]+age*a[5],Offset.Zero){scale(unit,unit,Offset.Zero){translate(-24f,-24f){drawPath(box,colors[i%6],alpha=sin(travel*PI.toFloat()).pow(2)*.48f,style=Stroke(3.4f,cap=StrokeCap.Round,join=StrokeJoin.Round))}}}}
        }
    }
    }
}

/** One textured draw for all stars; positions/alpha keep the original animation. */
private class NativeStarBatch(count:Int) {
    private val positions=FloatArray(count*8)
    private val texture=FloatArray(count*8)
    private val colors=IntArray(count*4)
    private val indices=ShortArray(count*6)
    private val paint=android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG).apply {
        val sprite=android.graphics.Bitmap.createBitmap(32,32,android.graphics.Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(sprite).drawCircle(16f,16f,15f,android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply{color=android.graphics.Color.WHITE})
        shader=android.graphics.BitmapShader(sprite,android.graphics.Shader.TileMode.CLAMP,android.graphics.Shader.TileMode.CLAMP)
    }
    init {
        repeat(count){i->
            floatArrayOf(0f,0f,32f,0f,32f,32f,0f,32f).copyInto(texture,i*8)
            val v=i*4
            shortArrayOf(v.toShort(),(v+1).toShort(),(v+2).toShort(),v.toShort(),(v+2).toShort(),(v+3).toShort()).copyInto(indices,i*6)
        }
    }
    fun set(i:Int,x:Float,y:Float,radius:Float,color:Int) {
        // Compensate the 1px transparent border so the visible radius is unchanged.
        val r=radius*16f/15f;val k=i*8
        positions[k]=x-r;positions[k+1]=y-r;positions[k+2]=x+r;positions[k+3]=y-r
        positions[k+4]=x+r;positions[k+5]=y+r;positions[k+6]=x-r;positions[k+7]=y+r
        repeat(4){colors[i*4+it]=color}
    }
    fun draw(canvas:android.graphics.Canvas) {
        canvas.drawVertices(android.graphics.Canvas.VertexMode.TRIANGLES,positions.size,positions,0,texture,0,colors,0,indices,0,indices.size,paint)
    }
}
