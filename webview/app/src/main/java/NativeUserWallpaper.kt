package io.github.yawasau.speedbackup.webview

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.AtomicFile
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

/** Private, bounded, orientation-aware copy: no persistent permission to the original is needed. */
internal object NativeUserWallpaper {
    var bitmap by mutableStateOf<Bitmap?>(null)
        private set
    var rendered by mutableStateOf<Bitmap?>(null)
        private set
    var transparency by mutableIntStateOf(100)
        private set
    var committedOpacity by mutableIntStateOf(100)
        private set
    var blur by mutableIntStateOf(0)
        private set
    var dim by mutableIntStateOf(55)
        private set
    private fun prefs(context:Context)=context.applicationContext.getSharedPreferences("wallpaper",Context.MODE_PRIVATE)
    fun adjust(context:Context,key:String,value:Int){
        val v=value.coerceIn(0,100)
        when(key){"transparency"->transparency=v;"blur"->blur=v;"dim"->dim=v;else->return}
    }
    fun commit(context:Context){
        committedOpacity=transparency
        prefs(context).edit().putInt("opacity",transparency).putInt("blur",blur).putInt("dim",dim).apply()
        refresh()
    }
    private var blurJob:Job?=null
    private var preparedSource:Bitmap?=null
    private var preparedBlur=-1
    private fun refresh(){
        if(preparedSource===bitmap&&preparedBlur==blur)return
        preparedSource=bitmap;preparedBlur=blur
        blurJob?.cancel()
        val original=bitmap;val amount=blur
        if(original==null||amount==0){rendered=original;return}
        blurJob=scope.launch {
            try{val result=withContext(Dispatchers.Default){blurImage(original,amount)};ensureActive();rendered=result}
            catch(e:CancellationException){throw e}
            catch(_:Exception){status="模糊處理失敗，保留原圖。";rendered=original;preparedBlur=-1}
            catch(_:OutOfMemoryError){status="模糊處理記憶體不足，保留原圖。";rendered=original;preparedBlur=-1}
        }
    }
    // Two separable box passes, at most 512px; computed only on committed edits.
    private suspend fun blurImage(source:Bitmap,amount:Int):Bitmap {
        val scale=minOf(1.0,512.0/maxOf(source.width,source.height))
        val small=Bitmap.createScaledBitmap(source,maxOf(1,(source.width*scale).toInt()),maxOf(1,(source.height*scale).toInt()),true)
        val w=small.width;val h=small.height;var a=IntArray(w*h);var b=IntArray(w*h)
        small.getPixels(a,0,w,0,0,w,h)
        val r=maxOf(1,(amount*24/100));val count=2*r+1
        repeat(2){
            for(axis in 0..1){
                currentCoroutineContext().ensureActive()
                val lines=if(axis==0)h else w;val length=if(axis==0)w else h
                fun index(line:Int,pos:Int)=if(axis==0)line*w+pos.coerceIn(0,w-1) else pos.coerceIn(0,h-1)*w+line
                for(line in 0 until lines){
                    var red=0;var green=0;var blue=0;var alpha=0
                    fun add(pixel:Int,sign:Int){alpha+=((pixel ushr 24)and 255)*sign;red+=((pixel ushr 16)and 255)*sign;green+=((pixel ushr 8)and 255)*sign;blue+=(pixel and 255)*sign}
                    for(i in -r..r)add(a[index(line,i)],1)
                    for(pos in 0 until length){b[index(line,pos)]=((alpha/count)shl 24)or((red/count)shl 16)or((green/count)shl 8)or(blue/count);add(a[index(line,pos-r)],-1);add(a[index(line,pos+r+1)],1)}
                }
                val swap=a;a=b;b=swap
            }
        }
        if(small!==source)small.recycle()
        return Bitmap.createBitmap(a,w,h,Bitmap.Config.ARGB_8888)
    }
    var enabled by mutableStateOf(true)
        private set
    fun setEnabled(context:Context,value:Boolean){enabled=value;context.applicationContext.getSharedPreferences("wallpaper",Context.MODE_PRIVATE).edit().putBoolean("enabled",value).apply()}
    var busy by mutableStateOf(false)
        private set
    var status by mutableStateOf("")
        private set
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private val mutex=Mutex()
    private var loaded=false
    private fun file(context:Context)=AtomicFile(File(context.filesDir,"user-wallpaper.png"))
    private fun decode(source:ImageDecoder.Source)=ImageDecoder.decodeBitmap(source){decoder,info,_->
        val ratio=minOf(1.0,2048.0/maxOf(info.size.width,info.size.height))
        decoder.setTargetSize(maxOf(1,(info.size.width*ratio).toInt()),maxOf(1,(info.size.height*ratio).toInt()))
        decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE
    }
    fun load(context:Context){
        if(loaded)return
        loaded=true
        val app=context.applicationContext
        scope.launch { mutex.withLock {
            enabled=withContext(Dispatchers.IO){app.getSharedPreferences("wallpaper",Context.MODE_PRIVATE).getBoolean("enabled",true)}
            val settings=prefs(app)
            transparency=settings.getInt("opacity",100).coerceIn(0,100);blur=settings.getInt("blur",0).coerceIn(0,100);dim=settings.getInt("dim",55).coerceIn(0,100)
            committedOpacity=transparency
            bitmap=withContext(Dispatchers.IO){try{file(app).openRead().use{decode(ImageDecoder.createSource(file(app).baseFile))}}catch(_:Exception){null}catch(_:OutOfMemoryError){null}}
            rendered=bitmap;refresh()
        } }
    }
    fun import(context:Context,uri:Uri)=importImage(context,false){temporary->
        context.contentResolver.openInputStream(uri)?.use{input->temporary.outputStream().use{output->
            val buffer=ByteArray(65536);var total=0L
            while(true){val n=input.read(buffer);if(n<0)break;total+=n;require(total<=32L*1024*1024);output.write(buffer,0,n)}
        }}?:error("無法讀取圖片")
    }
    private var systemDefault=false
    fun importSystem(context:Context,api:NativeApi)=importImage(context,true){temporary->
        systemDefault=false
        val manager=android.app.WallpaperManager.getInstance(context)
        // Live wallpapers have no equivalent static image; never substitute the launcher screenshot.
        check(manager.wallpaperInfo==null){"動態壁紙不提供靜態圖片"}
        try{api.systemWallpaper(android.os.Process.myUid()/100000,temporary)}
        catch(e:NativeApi.ApiFailure){
            if(e.status!=404)throw e
            val drawable=manager.getBuiltInDrawable(1080,1920,true,.5f,.5f,android.app.WallpaperManager.FLAG_SYSTEM)?:throw e
            val image=Bitmap.createBitmap(1080,1920,Bitmap.Config.ARGB_8888)
            try{drawable.setBounds(0,0,image.width,image.height);drawable.draw(android.graphics.Canvas(image));temporary.outputStream().use{check(image.compress(Bitmap.CompressFormat.PNG,100,it))}}
            finally{image.recycle()}
            systemDefault=true
        }
    }
    private fun importImage(context:Context,system:Boolean,copy:(File)->Unit){
        if(busy)return
        busy=true;status="正在匯入背景圖片…"
        val app=context.applicationContext
        scope.launch { mutex.withLock {
            try {
                val result=withContext(Dispatchers.IO){
                    val temporary=File.createTempFile("wallpaper-import-",".tmp",app.cacheDir)
                    val image=try {
                        copy(temporary)
                        decode(ImageDecoder.createSource(temporary))
                    }finally{temporary.delete()}
                    val target=file(app);val output=target.startWrite()
                    try{check(image.compress(Bitmap.CompressFormat.PNG,100,output));target.finishWrite(output)}catch(e:Exception){target.failWrite(output);throw e}
                    image
                }
                bitmap=result;rendered=result;refresh();setEnabled(app,true);status=if(system)if(systemDefault)"未找到可讀取的系統圖片，已套用系統預設壁紙。" else "已套用目前系統壁紙" else "已套用自訂背景"
            }catch(_:OutOfMemoryError){status="記憶體不足，原背景已保留。"}
            catch(_:Exception){status=if(system)"無法讀取系統靜態壁紙；原背景已保留，可改用匯入圖片。" else "匯入失敗，請選擇 32 MB 以內的有效圖片；原背景已保留。"}
            finally{busy=false}
        } }
    }
    fun clear(context:Context){
        if(busy)return
        busy=true
        val app=context.applicationContext
        scope.launch { mutex.withLock {
            try{withContext(Dispatchers.IO){file(app).delete()};bitmap=null;rendered=null;refresh();status="已恢復目前外觀的背景"}
            finally{busy=false}
        } }
    }
}

@Composable internal fun rememberWallpaperImport():()->Unit {
    val context=LocalContext.current
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()){uri->if(uri!=null)NativeUserWallpaper.import(context,uri)}
    return {try{picker.launch("image/*")}catch(_:android.content.ActivityNotFoundException){android.widget.Toast.makeText(context,"找不到圖片選擇器",android.widget.Toast.LENGTH_SHORT).show()}}
}

@Composable internal fun NativeWallpaperSettings(text:Color,container:Color,style:TextStyle,enabled:Boolean,onImport:()->Unit,onSystem:()->Unit){
    val context=LocalContext.current
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
        NativeDialogButton("使用系統壁紙","miuix",text,container,style,enabled&&!NativeUserWallpaper.busy,Modifier.fillMaxWidth(),visualEnabled=!NativeUserWallpaper.busy,onClick=onSystem)
        NativeDialogButton("匯入背景圖片","miuix",text,container,style,enabled&&!NativeUserWallpaper.busy,Modifier.fillMaxWidth(),visualEnabled=!NativeUserWallpaper.busy,onClick=onImport)
        if(NativeUserWallpaper.bitmap!=null)Row(Modifier.fillMaxWidth().heightIn(min=56.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically){
            BasicText("使用自訂背景",Modifier.weight(1f),style=style)
            NativeMiuixSwitch(NativeUserWallpaper.enabled,text,text.copy(alpha=.25f),enabled&&!NativeUserWallpaper.busy,label="使用自訂背景",visualEnabled=!NativeUserWallpaper.busy){NativeUserWallpaper.setEnabled(context,it)}
        }
        if(NativeUserWallpaper.bitmap!=null)NativeDialogButton("恢復原本背景","miuix",text,container,style,enabled&&!NativeUserWallpaper.busy,Modifier.fillMaxWidth(),visualEnabled=!NativeUserWallpaper.busy){NativeUserWallpaper.clear(context)}
        if(NativeUserWallpaper.bitmap!=null){
            for((key,label,value) in listOf(Triple("transparency","壁紙透明度",NativeUserWallpaper.transparency),Triple("blur","壁紙模糊度",NativeUserWallpaper.blur),Triple("dim",if(text.red>.5f)"壁紙壓暗" else "壁紙提亮",NativeUserWallpaper.dim))){
                BasicText("$label $value%",style=style)
                NativeMiuixSlider(label,value.toFloat(),enabled&&!NativeUserWallpaper.busy,!NativeUserWallpaper.busy,text,{NativeUserWallpaper.adjust(context,key,it.toInt())},{},{NativeUserWallpaper.commit(context)})
            }
        }
        if(NativeUserWallpaper.status.isNotEmpty())BasicText(NativeUserWallpaper.status,style=style)
    }
}
