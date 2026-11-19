package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.background
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.preferredFrameRate
import androidx.compose.ui.FrameRateCategory
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
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
    private var promptBackground by mutableStateOf<Prepared?>(null)
    private var navigationGeneration by mutableIntStateOf(0)
    private var navMoving by mutableStateOf(false)
    private var menuHandoff by mutableStateOf(false)
    private var handoffTerminal:Prepared?=null
    fun hasContent():Boolean=state!=null
    private var menuReturnRoute=""
    fun resetNavigationHistory(){menuReturnRoute="";navigationGeneration++}
    private var uiMoving by mutableStateOf(false)
    private val composeView=ComposeView(activity).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent {
            var resumed by remember { mutableStateOf(activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) }
            var presentationVisible by remember { mutableStateOf(activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) }
            DisposableEffect(activity) {
                val observer=androidx.lifecycle.LifecycleEventObserver { _,_ -> resumed=activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED);presentationVisible=activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED) }
                activity.lifecycle.addObserver(observer)
                onDispose { activity.lifecycle.removeObserver(observer) }
            }

            LaunchedEffect(Unit){NativeUserWallpaper.load(activity)}
            val customWallpaper=NativeUserWallpaper.rendered.takeIf{NativeUserWallpaper.enabled}
            val skyBackdrop=rememberLayerBackdrop()
            var skyCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
            val backdrop=remember(skyBackdrop){GlassWindowBackdrop(skyBackdrop.graphicsLayer){skyCoordinates}}
            val data=state
            LaunchedEffect(menuHandoff,data?.optString("epoch"),data?.optLong("handoffDeadline")) {
                if(menuHandoff) {
                    // Match the session's bounded host-navigation wait. If the host
                    // never replaces the menu, expose the real terminal state.
                    val deadline=data?.optLong("handoffDeadline")?:0L
                    kotlinx.coroutines.delay((deadline-android.os.SystemClock.elapsedRealtime()).coerceIn(0L,HOST_HANDOFF_TIMEOUT_MS))
                    handoffTerminal?.let { currentPrepared=it }
                    handoffTerminal=null;menuHandoff=false
                }
            }
            val prompt=data?.optBoolean("prompt")==true
            val base=if(prompt)promptBackground else currentPrepared
            val baseData=base?.data?:data
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
            val moving=uiMoving||navMoving
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
            val dynamicGlassBackground=customWallpaper==null&&data?.optBoolean("reducedMotion")!=true&&(data?.optBoolean("nativeNightSky")==true||data?.optBoolean("nativeSky")==true)
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
                    else if(data?.optBoolean("nativeSky")==true)
                        NativeSky(Modifier.fillMaxSize(),resumed&&!data.optBoolean("reducedMotion"))
                    else if(data?.optBoolean("nativeNightSky")==true)
                        NativeNightSky(Modifier.fillMaxSize(),resumed&&!data.optBoolean("reducedMotion"))
                    else Box(Modifier.fillMaxSize().background(background))
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
                    key(navigationGeneration){NativeNavHost(route(baseData),base?:currentPrepared!!,data.optBoolean("reducedMotion"),
                        modifier=Modifier.fillMaxSize().then(if(android.os.Build.VERSION.SDK_INT>=30)Modifier.imePadding() else Modifier),
                        onBack={dispatch.invoke("back",state?.optString("epoch").orEmpty())},root=data.optBoolean("navigationRoot"),previewBack=!prompt,boundaryBack=!prompt,backRoute=data.optString("backRoute").ifEmpty{if(data.optBoolean("returnToMenu"))menuReturnRoute else ""},onMotion={navMoving=it}) { prepared ->
                        val page=prepared.data
                        val pageDispatch=if(prompt||menuHandoff)Action{_,_->} else dispatch
                        CompositionLocalProvider(LocalNativeNavigationActive provides (LocalNativeNavigationActive.current&&!prompt),LocalNativePresentationVisible provides (LocalNativePresentationVisible.current&&presentationVisible)) {
                        // Give each moving page the same cached wallpaper, so transparent controls
                        // cannot expose the outgoing page's text during Miuix parallax.
                        Box(Modifier.fillMaxSize().drawWithCache{onDrawBehind{drawLayer(skyBackdrop.graphicsLayer)}}) {
                            page.optJSONObject("menu")?.let { menu -> key(page.getString("epoch")){NativeMainMenu(menu,page,backdrop,pageDispatch){uiMoving=it}} }
                            page.optJSONObject("screen")?.takeUnless{prompt&&base==null}?.let { screen ->
                                NativeDocument(screen,page,prepared.logs,backdrop,resumed,pageDispatch){uiMoving=it}
                            }
                            page.optJSONObject("picker")?.let { picker ->
                                val density=androidx.compose.ui.platform.LocalDensity.current
                                CompositionLocalProvider(LocalNativeUiScale provides 1f,androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,density.fontScale*page.optDouble("scale",1.0).toFloat().coerceIn(.7f,1.5f))){ NativePathPicker(picker,Color(page.optLong("foreground",0xffeeeeeeL).toInt()),background,accent,page.optString("uiStyle"),page.optBoolean("reducedMotion"),resumed){id->pageDispatch.invoke(id,page.getString("epoch"))} } }
                        }
                    }}}
                    val overlay=if(prompt)data.optJSONObject("screen") else data.optJSONObject("overlay")
                    overlay?.let{NativeDocument(it,data,emptyList(),backdrop,resumed,dispatch){uiMoving=it}}
                    if(menuHandoff)Box(Modifier.fillMaxSize().clearAndSetSemantics{}.pointerInput(Unit){
                        awaitPointerEventScope { while(true)awaitPointerEvent().changes.forEach{it.consume()} }
                    })
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
    fun clear(){menuReturnRoute="";navigationGeneration++;navMoving=false;uiMoving=false;menuHandoff=false;handoffTerminal=null;state=null;currentPrepared=null;contentSignature="";promptBackground=null}
    data class Prepared(val data:JSONObject,val signature:String,val logs:List<NativeLogChunk>,val sequence:Long)
    companion object {
        /** Called only on the bounded model worker. Invalid models are rejected before rendering. */
        @JvmStatic fun prepare(next:JSONObject,viewportWidth:Int,density:Float,logTextSize:Float,cache:NativeLogCache):Prepared {
            require(viewportWidth in 1..65536&&density.isFinite()&&density>0f&&logTextSize.isFinite()&&logTextSize>0f)
            require(listOf("menu","screen","picker").count{next.optJSONObject(it)!=null}==1)
            require((next.optJSONArray("body")?.length()?:0)==0)
            validateNativeMenu(next.optJSONObject("menu"))
            validateNativeDocument(next.optJSONObject("screen"))
            validateNativeDocument(next.optJSONObject("overlay"))
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
        // Preserve the actual main-menu destination across preparation/log pages in
        // this Binder lifetime: managed selectors still cancel to that same menu.
        // Console Back itself never uses it. Rebind/clear resets this cached target.
        val incoming=prepared.data
        // Never overwrite a live menu's cached navigation entry with the
        // temporary disabled controls/status produced by successful submission.
        // The session remains finished; this changes presentation only.
        val previous=currentPrepared
        val holdMenu=incoming.optBoolean("menuHandoff")&&previous?.data?.optJSONObject("menu")!=null&&
            !previous.data.optBoolean("menuHandoff")&&previous.data.optString("epoch")==incoming.optString("epoch")&&
            route(previous.data)==route(incoming)
        menuHandoff=holdMenu
        handoffTerminal=if(holdMenu)prepared else null
        if(incoming.optBoolean("prompt")){
            if(state?.optBoolean("prompt")!=true)promptBackground=currentPrepared
        }else promptBackground=null
        if(incoming.optJSONObject("menu")!=null)
            menuReturnRoute=route(incoming)
        // Log rows are extracted before the JSON signature is computed. Compare
        // the cached immutable chunks too, or log-only updates are discarded.
        if(prepared.signature!=contentSignature||prepared.logs!=currentPrepared?.logs){
            contentSignature=prepared.signature
            if(!holdMenu)currentPrepared=prepared
            state=prepared.data
        }
        return true
    }

}
