package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.background
import androidx.compose.animation.core.*
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.preferredFrameRate
import androidx.compose.ui.FrameRateCategory
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.catalog.components.GlassMaterial
import org.json.JSONObject
import kotlinx.coroutines.isActive

/** Semantic documents only; scrolling, geometry and hit testing belong to Compose. */
class NativeChrome(activity:ComponentActivity,private val dispatch:Action) {
    init { NativeUserWallpaper.initialize() }
    fun interface Action { fun invoke(id:String,epoch:String) }
    private var state by mutableStateOf<JSONObject?>(null)
    private var contentSignature=""
    private var navigationPending=false
    private var navigationGeneration by mutableIntStateOf(0)
    private var navMoving by mutableStateOf(false)
    fun hasContent():Boolean=state!=null
    fun beginNavigation(){navigationPending=true}
    fun endNavigation(){navigationPending=false}
    private var menuReturnRoute=""
    fun resetNavigationHistory(){menuReturnRoute="";navigationGeneration++}
    fun clearForDocument(){if(!navigationPending)clear()}
    private var uiMoving by mutableStateOf(false)
    private var navigationMotionActive by mutableStateOf(false)
    fun setNavigationMoving(value:Boolean){navigationMotionActive=value}
    private val composeView=ComposeView(activity).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent {
            var resumed by remember { mutableStateOf(activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) }
            DisposableEffect(activity) {
                val observer=androidx.lifecycle.LifecycleEventObserver { _,_ -> resumed=activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) }
                activity.lifecycle.addObserver(observer)
                onDispose { activity.lifecycle.removeObserver(observer) }
            }

            LaunchedEffect(Unit){NativeUserWallpaper.load(activity)}
            val customWallpaper=NativeUserWallpaper.rendered.takeIf{NativeUserWallpaper.enabled}
            val skyBackdrop=rememberLayerBackdrop()
            var skyCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
            val backdrop=remember(skyBackdrop){GlassWindowBackdrop(skyBackdrop.graphicsLayer){skyCoordinates}}
            val data=state
            LaunchedEffect(customWallpaper,NativeUserWallpaper.committedOpacity,data?.optBoolean("fontAdaptive"),data?.optString("epoch")){
                if(data?.optBoolean("fontAdaptive")==true)dispatch.invoke("native:refresh",data.optString("epoch"))
            }
            var exportEpoch by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
            val logExporter=androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/x-tar")){uri->
                dispatch.invoke("diagnostic-export:"+(uri?.toString()?:""),exportEpoch)
            }
            var launchedExport by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
            LaunchedEffect(data?.optString("diagnosticExportRequest")){
                val request=data?.optString("diagnosticExportRequest").orEmpty()
                if(request.isNotEmpty()&&request!=launchedExport){
                    launchedExport=request;exportEpoch=data?.optString("epoch").orEmpty()
                    logExporter.launch("SpeedBackup_debug_${System.currentTimeMillis()}.tar")
                }
            }
            val moving=uiMoving||navigationMotionActive||navMoving
            val glassControls=remember(data?.optString("epoch")) { GlassMaterial.Controls(data?.optInt("glassLight",100)?:100,data?.optInt("glassTransparency",100)?:100,data?.optInt("glassRefraction",100)?:100,data?.optBoolean("glassAdaptive")==true,data?.optInt("glassBlurStrength",100)?:100) }
            LaunchedEffect(data?.optInt("glassLight",100),glassControls.editing,glassControls.pending){if(!glassControls.editing&&!glassControls.pending)glassControls.light=(data?.optInt("glassLight",100)?:100).coerceIn(0,100).toFloat()}
            LaunchedEffect(data?.optInt("glassTransparency",100),glassControls.editing,glassControls.pending){if(!glassControls.editing&&!glassControls.pending)glassControls.transparency=(data?.optInt("glassTransparency",100)?:100).coerceIn(0,100).toFloat()}
            LaunchedEffect(glassControls,data?.optInt("glassBlurStrength",100),glassControls.editing,glassControls.pending){if(!glassControls.editing&&!glassControls.pending)glassControls.blurStrength=(data?.optInt("glassBlurStrength",100)?:100).coerceIn(0,100).toFloat()}
            LaunchedEffect(data?.optInt("glassRefraction",100),glassControls.editing,glassControls.pending){if(!glassControls.editing&&!glassControls.pending)glassControls.refraction=(data?.optInt("glassRefraction",100)?:100).coerceIn(0,100).toFloat()}
            SideEffect{glassControls.adaptive=data?.optBoolean("glassAdaptive")==true}
            val background=Color(data?.optLong("background",0xff151c30L)?.toInt()?:0xff151c30.toInt())
            val initialLuminance=remember(customWallpaper,background,NativeUserWallpaper.transparency,NativeUserWallpaper.dim,data?.optLong("foreground")){
                if(customWallpaper==null)background.red*.2126f+background.green*.7152f+background.blue*.0722f
                else {
                    var sum=0.0
                    for(y in 0..4)for(x in 0..4){val pixel=customWallpaper.getPixel((customWallpaper.width-1)*x/4,(customWallpaper.height-1)*y/4);sum+=.2126*((pixel shr 16)and 255)+.7152*((pixel shr 8)and 255)+.0722*(pixel and 255)}
                    val opacity=NativeUserWallpaper.transparency/100f
                    val original=(sum/(25*255)).toFloat()*opacity+(background.red*.2126f+background.green*.7152f+background.blue*.0722f)*(1f-opacity)
                    val overlay=if(Color(data?.optLong("foreground",0xffffffffL)?.toInt()?:-1).red>.5f)0f else 1f
                    val dim=NativeUserWallpaper.dim/100f*opacity
                    original*(1f-dim)+overlay*dim
                }
            }
            val accent=Color(data?.optLong("accent",0xff96bdffL)?.toInt()?:0xff96bdff.toInt())
            val halo=remember { HaloPosition() }
            val hasLight=customWallpaper==null&&background.red+background.green+background.blue<1.5f&&data!=null&&data.optString("theme")!in setOf("space","night")&&data.optJSONObject("picker")==null
            val dynamicGlassBackground=customWallpaper==null&&data?.optBoolean("reducedMotion")!=true&&(hasLight||data?.optBoolean("nativeNightSky")==true||data?.optBoolean("nativeSky")==true)
            LaunchedEffect(glassControls,glassControls.adaptive,glassControls.light,data?.optBoolean("glassContent"),resumed,moving,customWallpaper,dynamicGlassBackground){
                if(!com.kyant.backdrop.isRuntimeShaderSupported()&&glassControls.adaptive&&resumed&&!moving){
                    kotlinx.coroutines.delay(80)
                    glassControls.sampleTick++
                    if(dynamicGlassBackground)while(kotlinx.coroutines.currentCoroutineContext().isActive){kotlinx.coroutines.delay(1500);glassControls.sampleTick++}
                }
            }
            Box(Modifier.fillMaxSize().then(if(moving)Modifier.preferredFrameRate(FrameRateCategory.High) else Modifier)) {
                Box(Modifier.fillMaxSize().onGloballyPositioned{skyCoordinates=it}.layerBackdrop(skyBackdrop).graphicsLayer { compositingStrategy=CompositingStrategy.Offscreen }) {
                    if(customWallpaper!=null)
                        Box(Modifier.fillMaxSize().background(background)){
                            androidx.compose.foundation.Image(customWallpaper.asImageBitmap(),null,Modifier.fillMaxSize(),alpha=NativeUserWallpaper.transparency/100f,contentScale=androidx.compose.ui.layout.ContentScale.Crop)
                        }
                    else if(data?.optBoolean("nativeNightSky")==true)
                        NativeNightSky(Modifier.fillMaxSize(),resumed&&!data.optBoolean("reducedMotion"))
                    else if(data?.optBoolean("nativeSky")==true&&data.optJSONObject("picker")==null)
                        NativeSky(Modifier.fillMaxSize(),resumed&&!data.optBoolean("reducedMotion"))
                    else NativeWallpaper(background,accent,false)
                    // Merge light into the one cached source BEFORE glass effects.
                    // Every control samples this texture once, as it does for stars.
                    if(hasLight)NativeWallpaper(background,accent,resumed&&!data!!.optBoolean("reducedMotion"),true,glassControls,halo)
                    // Record the same dimmed wallpaper that the page displays.
                    // Glass refraction and luminance must not sample the undimmed photo.
                    if(customWallpaper!=null)androidx.compose.foundation.Canvas(Modifier.fillMaxSize()){
                        val foreground=Color(data?.optLong("foreground",0xffffffffL)?.toInt()?:-1)
                        drawRect((if(foreground.red>.5f)Color.Black else Color.White).copy(alpha=NativeUserWallpaper.dim/100f*NativeUserWallpaper.transparency/100f))
                        // Protect black header/status-bar text on dark photos without washing
                        // out the entire wallpaper or changing the user's dim preference.
                        if(foreground.red<.5f){
                            val extent=300.dp.toPx()*(data?.optDouble("scale",1.0)?.toFloat()?:1f)
                            drawRect(androidx.compose.ui.graphics.Brush.verticalGradient(
                                0f to Color.White.copy(alpha=.76f),.65f to Color.White.copy(alpha=.76f),1f to Color.Transparent,
                                startY=0f,endY=extent))
                        }
                    }
                }
                if(data!=null) {
                    val foreground=Color(data.optLong("foreground",0xffeeeeeeL).toInt())
                    val controlForeground=Color(data.optLong("controlForeground",data.optLong("foreground")).toInt())
                    NativeAppTheme(data) {
                    CompositionLocalProvider(LocalNativeBackdrop provides backdrop,LocalNativeUiScale provides data.optDouble("scale",1.0).toFloat().coerceIn(.7f,1.5f),com.kyant.backdrop.catalog.components.LocalGlassBackgroundKey provides ("${customWallpaper?.hashCode()}:${NativeUserWallpaper.transparency}:${NativeUserWallpaper.dim}:${data.optLong("foreground")}:${data.optString("theme")}:${data.optLong("background")}:${data.optDouble("scale")}"),com.kyant.backdrop.catalog.components.LocalGlassInitialLuminance provides initialLuminance,com.kyant.backdrop.catalog.components.LocalGlassDynamicBackground provides dynamicGlassBackground,GlassMaterial.LocalActive provides (resumed&&!moving),GlassMaterial.LocalReducedMotion provides data.optBoolean("reducedMotion"),GlassMaterial.LocalControls provides glassControls,GlassMaterial.LocalBlurEnabled provides data.optBoolean("glassBlur",true)) {
                    key(navigationGeneration){NativeNavHost(route(data),currentPrepared!!,data.optBoolean("reducedMotion"),
                        modifier=Modifier.fillMaxSize().then(if(android.os.Build.VERSION.SDK_INT>=30)Modifier.imePadding() else Modifier),
                        onBack={dispatch.invoke("back",state?.optString("epoch").orEmpty())},root=data.optBoolean("navigationRoot"),backRoute=data.optString("backRoute").ifEmpty{if(data.optBoolean("returnToMenu"))menuReturnRoute else ""},onMotion={navMoving=it}) { prepared ->
                        val page=prepared.data
                        // Give each moving page the same cached wallpaper, so transparent controls
                        // cannot expose the outgoing page's text during Miuix parallax.
                        Box(Modifier.fillMaxSize().drawWithCache{onDrawBehind{drawLayer(skyBackdrop.graphicsLayer)}}) {
                            page.optJSONObject("menu")?.let { menu -> key(page.getString("epoch")){NativeMainMenu(menu,page,backdrop,dispatch){uiMoving=it}} }
                            page.optJSONObject("screen")?.let { screen ->
                                NativeDocument(screen,page,prepared.logs,backdrop,resumed,dispatch){uiMoving=it}
                            }
                            page.optJSONObject("picker")?.let { picker ->
                                val density=androidx.compose.ui.platform.LocalDensity.current
                                CompositionLocalProvider(LocalNativeUiScale provides 1f,androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,density.fontScale*page.optDouble("scale",1.0).toFloat().coerceIn(.7f,1.5f))){ NativePathPicker(picker,Color(page.optLong("foreground",0xffeeeeeeL).toInt()),background,accent,page.optString("uiStyle"),page.optBoolean("reducedMotion"),resumed){id->dispatch.invoke(id,page.getString("epoch"))} } }
                        }
                    }}
                    }
                    }
                }
            }
        }
    }
    val view=android.widget.FrameLayout(activity).apply{addView(composeView,android.widget.FrameLayout.LayoutParams(-1,-1))}
    private fun route(data:JSONObject?):String = data?.let {
        it.optJSONObject("picker")?.let{picker->"picker:"+picker.getString("session")} ?: it.optString("sectionRoute").takeIf{key->key.isNotEmpty()} ?: it.optJSONObject("menu")?.let{menu->"menu:"+menu.optString("title")}
            ?:it.optJSONObject("screen")?.let{screen->screen.optString("key")} ?:"picker"
    }?:""
    fun routeKey():String=route(state)
    fun motionAllowed():Boolean = state?.optBoolean("reducedMotion") == false
    fun clear(){menuReturnRoute="";navigationPending=false;navigationGeneration++;navMoving=false;uiMoving=false;state=null;currentPrepared=null;contentSignature=""}
    data class Prepared(val data:JSONObject,val signature:String,val logs:List<NativeLogChunk>,val sequence:Long)
    companion object {
        /** Called only on the bounded model worker. Invalid models are rejected before rendering. */
        @JvmStatic fun prepare(next:JSONObject,viewportWidth:Int,density:Float,logTextSize:Float,cache:NativeLogCache):Prepared {
            require(viewportWidth in 1..65536&&density.isFinite()&&density>0f&&logTextSize.isFinite()&&logTextSize>0f)
            require(listOf("menu","screen","picker").count{next.optJSONObject(it)!=null}==1)
            require((next.optJSONArray("body")?.length()?:0)==0)
            validateNativeMenu(next.optJSONObject("menu"))
            validateNativeDocument(next.optJSONObject("screen"))
            val buttons=next.getJSONArray("buttons");require(buttons.length() in 0..4)
            val allowed=setOf("nav-home","nav-actions","nav-style","cancel","save","continue","stop","close")
            for(i in 0 until buttons.length()) {
                val button=buttons.getJSONObject(i)
                require(button.getString("id") in allowed&&button.getString("label").length in 1..128)
            }
            require(next.getString("epoch").length in 1..80)
            require(next.optString("sectionRoute").length<=512)
        next.optJSONObject("picker")?.let { picker ->
            require(picker.getString("session").length in 1..80)
            for(key in listOf("title","path","parent","error"))require(picker.getString(key).length<=8192)
            val entries=picker.getJSONArray("entries");require(entries.length()<=20000)
            for(i in 0 until entries.length()) { val item=entries.getJSONObject(i);require(item.getString("path").length<=8192&&item.getString("name").length<=8192) }
            val selected=picker.getJSONArray("selected");require(selected.length()<=256)
            for(i in 0 until selected.length())require(selected.getString(i).length<=8192)
        }
            val sequence=next.optLong("seq",0);next.remove("seq")
            val logs=ArrayList<NativeLogRow>()
            cache.begin(next.getString("epoch"),Color(next.optLong("foreground",0xffeeeeeeL).toInt()),(viewportWidth-24*density).toInt().coerceAtLeast(1),logTextSize)
            next.optJSONObject("screen")?.takeIf{it.optString("key")=="console"}?.let { screen ->
                val nodes=screen.getJSONArray("nodes");val controls=org.json.JSONArray()
                for(i in 0 until nodes.length()) {
                    val node=nodes.getJSONObject(i)
                    if(node.getString("kind")=="log")logs.add(cache.row(node)) else controls.put(node)
                }
                screen.put("nodes",controls)
            }
            cache.retain(logs.map{it.id}.toSet())
            return Prepared(next,next.toString(),chunkNativeLogs(logs,(4*density).toInt()),sequence)
        }
    }
    private var currentPrepared by mutableStateOf<Prepared?>(null)
    fun applyPrepared(prepared:Prepared):Boolean {
        navigationPending=false
        // Preserve the actual main-menu destination across preparation/log pages in
        // this Binder lifetime: managed selectors still cancel to that same menu.
        // Console Back itself never uses it. Rebind/clear resets this cached target.
        val incoming=prepared.data
        if(incoming.optJSONObject("menu")!=null)
            menuReturnRoute=route(incoming)
        // Log rows are extracted before the JSON signature is computed. Compare
        // the cached immutable chunks too, or log-only updates are discarded.
        if(prepared.signature!=contentSignature||prepared.logs!=currentPrepared?.logs){
            contentSignature=prepared.signature
            currentPrepared=prepared
            state=prepared.data
        }
        return true
    }

}

/** Shared static glass source plus visible random halo on an independent layer, at display-aligned 60 Hz. */
private class HaloPosition { var offset by mutableStateOf(Offset(-.2f,-.1f)) }

@Composable private fun NativeWallpaper(background:Color,accent:Color,moving:Boolean,overlay:Boolean=false,controls:GlassMaterial.Controls?=null,position:HaloPosition=remember { HaloPosition() }) {
    var lightOffset by position::offset
    LaunchedEffect(moving) {
        if(!moving)return@LaunchedEffect
        val random=kotlin.random.Random.Default
        while(true) {
            val from=lightOffset
            var to:Offset
            do{to=Offset(random.nextFloat()*.8f-.4f,random.nextFloat()*.6f-.3f)}while((to-from).getDistance()<.28f)
            val duration=random.nextLong(4000,7000)*1_000_000L
            val start=withFrameNanos{it};var last=start;var complete=false
            while(!complete)withFrameNanos { frame ->
                if(frame-last>=16_000_000L) {
                    val t=((frame-start).toFloat()/duration).coerceIn(0f,1f)
                    val smooth=t*t*(3-2*t)
                    lightOffset=from+(to-from)*smooth
                    last=frame;complete=t>=1f
                }
            }
        }
    }
    Box(Modifier.fillMaxSize().then(if(moving)Modifier.preferredFrameRate(60f) else Modifier).drawWithCache {
        // Rasterize smooth gradients once at wallpaper resolution. The animated
        // shared source redraws bitmap samples, not several full-screen shaders.
        val width=384
        val height=(width*size.height/size.width.coerceAtLeast(1f)).toInt().coerceIn(1,1536)
        val w=width.toFloat();val h=height.toFloat()
        val bitmap=android.graphics.Bitmap.createBitmap(width,height,android.graphics.Bitmap.Config.ARGB_8888)
        val canvas=android.graphics.Canvas(bitmap);val paint=android.graphics.Paint(3)
        val dark=background.red+background.green+background.blue<1.5f
        val lightColor=if(dark)accent else Color.White
        fun radial(color:Color,alphas:FloatArray,stops:FloatArray?,x:Float,y:Float,radius:Float) {
            paint.shader=android.graphics.RadialGradient(x,y,radius,alphas.map{color.copy(alpha=it).toArgb()}.toIntArray(),stops,android.graphics.Shader.TileMode.CLAMP)
            canvas.drawRect(0f,0f,w,h,paint)
        }
        if(!overlay)canvas.drawColor(background.toArgb())
        if(overlay&&dark)radial(lightColor,floatArrayOf(.50f,.45f,.20f,0f),floatArrayOf(0f,.10f,.45f,1f),w*.5f,h*.45f,minOf(w,h)*.42f)
        else if(dark) {
            radial(lightColor,floatArrayOf(.25f,0f),null,w*.22f,h*.28f,maxOf(w,h)*.48f)
            radial(Color(0xff8cd6df),floatArrayOf(.12f,0f),null,w*.85f,h*.67f,maxOf(w,h)*.44f)
            radial(Color.White,floatArrayOf(.045f,0f),null,w*.6f,h*.1f,maxOf(w,h)*.38f)
        }
        val image=bitmap.asImageBitmap()
        onDrawBehind {
            // Translate the cached bitmap in the draw phase. The shared parent
            // already supplies an offscreen source; no extra full-screen light FBO.
            withTransform({if(overlay)translate(lightOffset.x*size.width,lightOffset.y*size.height)}) {
                drawImage(image,dstSize=IntSize(size.width.toInt(),size.height.toInt()),alpha=if(overlay)((controls?.light?:100f)/100f).coerceIn(0f,1f) else 1f)
            }
        }
    })
}
