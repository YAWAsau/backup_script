@file:OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
package io.github.yawasau.speedbackup.webview

import androidx.compose.animation.core.*
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.layout.onSizeChanged
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.lazy.LazyColumn
import top.yukonga.miuix.kmp.utils.PagerNavigationSpringSpec
import top.yukonga.miuix.kmp.utils.springAnimateToPage
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.catalog.components.GlassMaterial
import com.kyant.backdrop.catalog.components.LiquidButton
import com.kyant.backdrop.catalog.components.LiquidBottomTab
import com.kyant.backdrop.catalog.components.LiquidBottomTabs
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.PowerSettingsNew
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Home
import top.yukonga.miuix.kmp.icon.extended.GridView
import top.yukonga.miuix.kmp.icon.extended.Settings
import top.yukonga.miuix.kmp.icon.extended.Close2

internal data class NativeUiStyle(val titleSize:Int,val titleWeight:FontWeight,val buttonRadius:Int,val buttonWeight:FontWeight,val dialogRadius:Int)
internal fun nativeUiStyle()=NativeUiStyle(32,FontWeight.Normal,24,FontWeight.Medium,28)

private val nativePageRevision=java.util.concurrent.atomic.AtomicLong()
private fun JSONArray.objects()=(0 until length()).map { getJSONObject(it) }

/** Bounds are checked before accepting an authenticated document's semantic menu. */
internal fun validateNativeMenu(menu:JSONObject?) {
    if(menu==null)return
    fun text(o:JSONObject,k:String)=require(o.getString(k).length<=8192)
    for(k in listOf("title","eyebrow","subtitle","status","cancel"))text(menu,k)
    menu.optJSONObject("connection")?.takeIf{it.length()>0}?.let{c->
        text(c,"label");require(c.getString("id").matches(Regex("control-[0-9]{1,12}")))
        require(c.getString("state") in setOf("local","ready","checking","offline","discovering","setup"))
        c.optJSONArray("daemons")?.let{rows->require(rows.length()<=2);for(r in rows.objects()){text(r,"label");require(r.getString("state") in setOf("idle","ready","checking","offline"))}}
        c.optJSONArray("rows")?.let{rows->require(rows.length()<=6);for(r in rows.objects()){text(r,"label");text(r,"caption")}}
    }
    for(k in listOf("info","choices","appearance"))require(menu.getJSONArray(k).length()<=(if(k=="choices")1000 else 256))
    for(g in menu.getJSONArray("info").objects()) {
        text(g,"title");require(g.getJSONArray("rows").length()<=256)
        for(r in g.getJSONArray("rows").objects()){text(r,"label");text(r,"value")}
    }
    for(k in listOf("choices","appearance"))require(menu.getJSONArray(k).objects().filter{it.has("id")}.map{it.getString("id")}.let{it.size==it.distinct().size})
    for(k in listOf("choices","appearance"))for(r in menu.getJSONArray(k).objects()) {
        text(r,"label")
        require(r.getString("kind") in if(k=="choices")setOf("button","heading") else setOf("note","select","checkbox","range","button"))
        if(k=="choices"||r.optString("kind")!="note")require(r.getString("id").matches(Regex("control-[0-9]{1,12}")))
        if(r.optString("kind")=="range") {
            require(r.getString("key") in setOf("glass-blur-strength","glass-light","glass-transparency","glass-refraction"))
            require(r.getString("value").toInt() in 0..100)
        }
        if(r.optString("kind")=="select") {
            text(r,"value");require(r.getJSONArray("options").length()<=256)
            val options=r.getJSONArray("options").objects();require(options.map{it.getString("value")}.distinct().size==options.size)
            for(o in options){text(o,"value");text(o,"label")}
        }
    }
}

/** One native motion owner for complete pages: no DOM rectangles or frame messages. */
@Composable internal fun NativeMainMenu(menu:JSONObject,data:JSONObject,backdrop:Backdrop,dispatch:NativeChrome.Action,onMotion:(Boolean)->Unit) {
    val epoch=data.getString("epoch")
    val selectedPage=data.optInt("selected").coerceIn(0,2)
    // NativeMenuPage restores and persists panel with its group. A second,
    // settled-only viewport cache can still contain Home when a category is
    // opened mid-animation; restoring it would dispatch Home over the new page.
    val pager=rememberPagerState(initialPage=selectedPage,pageCount={3})
    val scope=rememberCoroutineScope()
    val material=LocalNativeMaterial.current
    val materialPageSpec=androidx.compose.material3.MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val pageSpec=if(material)materialPageSpec else PagerNavigationSpringSpec
    val reduceMotion by rememberUpdatedState(data.optBoolean("reducedMotion"))
    var pageAnimations by remember { mutableIntStateOf(0) }
    suspend fun animatePage(index:Int){
        // Programmatic tab motion must not consume the first child DOWN merely
        // to stop its spring. Keep child clicks live while the transition finishes.
        // A count also covers cancellation when a newer tab replaces this motion.
        pageAnimations++
        try {
            if(reduceMotion)pager.scrollToPage(index)
            else if(material)pager.animateScrollToPage(index,animationSpec=materialPageSpec)
            else pager.springAnimateToPage(index)
        } finally { pageAnimations-- }
    }

    val pageDragging by pager.interactionSource.collectIsDraggedAsState()
    val latestData by rememberUpdatedState(data)
    val latestMenu by rememberUpdatedState(menu)
    val latestSelected by rememberUpdatedState(selectedPage)
    var lastDispatchedPage by remember { mutableIntStateOf(selectedPage) }
    var predictingBack by remember { mutableStateOf(false) }
    val activeNavigation by rememberUpdatedState(LocalNativeNavigationActive.current)
    val backPanel=data.optInt("backPanel",-1)
    // Tab Back belongs to this pager, not the outer document history.
    NativePredictiveBackHandler(enabled=LocalNativeNavigationActive.current&&backPanel in 0..2) { events ->
        val start=pager.settledPage
        val startSelected=latestSelected
        val target=latestData.optInt("backPanel",-1)
        if(target !in 0..2)return@NativePredictiveBackHandler
        predictingBack=true
        var committed=false
        try {
            pager.scroll(androidx.compose.foundation.MutatePriority.PreventUserInput) {
                var previous=0f
                events.collect { event ->
                    val progress=if(latestData.optBoolean("reducedMotion"))0f else event.progress.coerceIn(0f,1f)
                    scrollBy((previous-progress)*(start-target)*(pager.layoutInfo.pageSize+pager.layoutInfo.pageSpacing))
                    previous=progress
                }
            }
            if(!activeNavigation)return@NativePredictiveBackHandler
            if(latestData.optInt("backPanel",-1)!=target||latestSelected!=startSelected){
                lastDispatchedPage=latestSelected
                animatePage(latestSelected)
                return@NativePredictiveBackHandler
            }
            committed=true
            lastDispatchedPage=target
            dispatch.invoke("back",epoch)
            animatePage(target)
        } catch(cancelled:kotlinx.coroutines.CancellationException) {
            // A newer tab can cancel the finishing animation after Back committed.
            // Only a cancelled gesture should restore the original page.
            if(!committed&&activeNavigation)kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable){animatePage(start)}
            throw cancelled
        } finally { predictingBack=false }
    }
    val uiStyle=nativeUiStyle()
    val text=Color(data.optLong("foreground",0xffeeeeeeL).toInt())
    val tint=Color(data.optLong("accent",0xff96bdffL).toInt())
    val background=Color(data.optLong("background",0xff151c30L).toInt())
    val glassControls=GlassMaterial.LocalControls.current
    val scale=data.optDouble("scale",1.0).coerceIn(.7,1.5).toFloat()
    val lists=List(3){rememberResumeList(data.optString("resumeSession"),"main-menu:$it"+if(material&&it==2)":material-rows" else "")}
    val moving=pager.isScrollInProgress||lists.any{it.isScrollInProgress}
    LaunchedEffect(moving){onMotion(moving)}
    DisposableEffect(Unit){onDispose{onMotion(false)}}
    var pendingRevision by remember { mutableLongStateOf(0) }
    var choosing by remember { mutableStateOf<String?>(null) }
    fun send(kind:String,id:String="",value:String=""):Boolean {
        // Miuix starts its scroll mutation on pointer DOWN, even for a tap.
        // Gesture consumption already cancels clicks after horizontal touch slop.
        dispatch.invoke("menu:"+JSONObject().put("kind",kind).put("id",id).put("value",value),epoch)
        return true
    }
    fun commitGlass(id:String,value:Int) {
        val ticket=++glassControls.revision
        glassControls.pending=true;glassControls.editing=false
        dispatch.invoke("menu:"+JSONObject().put("kind","value").put("id",id).put("value",value.toString()),epoch)
        scope.launch {
            kotlinx.coroutines.delay(700)
            snapshotFlow{!glassControls.editing}.first{it}
            if(ticket==glassControls.revision) {
                // Reconcile even a rejected/stale action; never leave local-only state.
                glassControls.light=latestData.optInt("glassLight",100).coerceIn(0,100).toFloat()
                glassControls.transparency=latestData.optInt("glassTransparency",100).coerceIn(0,100).toFloat()
                glassControls.blurStrength=latestData.optInt("glassBlurStrength",100).coerceIn(0,100).toFloat()
                glassControls.refraction=latestData.optInt("glassRefraction",100).coerceIn(0,100).toFloat()
                glassControls.pending=false
            }
        }
    }
    DisposableEffect(glassControls){onDispose{glassControls.editing=false;glassControls.pending=false}}
    fun navigate(index:Int) {
        choosing=null
        // Commit tab intent before its animation: a child can be clicked while
        // the spring is still moving. An older page acknowledgement must not
        // reconcile us back to the previous tab during that interval.
        lastDispatchedPage=index
        pendingRevision=nativePageRevision.incrementAndGet()
        dispatch.invoke("menu:"+JSONObject().put("kind","page").put("index",index).put("revision",pendingRevision),epoch)
        scope.launch { if(latestMenu.optBoolean("reduced"))pager.scrollToPage(index) else animatePage(index) }
    }
    // Only semantic page changes cross the bridge. No currentPageOffsetFraction collector.
    LaunchedEffect(pager,epoch) {
        snapshotFlow { if(predictingBack||pager.isScrollInProgress)null else pager.settledPage }.distinctUntilChanged().collect { page ->
            if(page!=null&&page!=lastDispatchedPage){
                lastDispatchedPage=page
                pendingRevision=nativePageRevision.incrementAndGet()
                dispatch.invoke("menu:"+JSONObject().put("kind","page").put("index",page).put("revision",pendingRevision),epoch)
            }
        }
    }
    LaunchedEffect(pendingRevision) {
        val ticket=pendingRevision
        if(ticket>0){
            kotlinx.coroutines.delay(2000)
            snapshotFlow{pager.isScrollInProgress}.first{!it}
            if(pendingRevision!=ticket)return@LaunchedEffect
            val target=latestSelected
            lastDispatchedPage=target
            // Do not run motion in the effect that clearing pendingRevision cancels.
            scope.launch {
                if(latestMenu.optBoolean("reduced"))pager.scrollToPage(target)
                else animatePage(target)
            }
            pendingRevision=0
        }
    }
    // Reconcile every acknowledged snapshot: a page acknowledgement and Back
    // can be coalesced into one model update. Revision equality is not a Back signal.
    LaunchedEffect(selectedPage,menu.optLong("revision")) {
        val ack=menu.optLong("revision")
        if(ack<pendingRevision)return@LaunchedEffect
        pendingRevision=0
        if(pager.settledPage!=selectedPage||pager.isScrollInProgress) {
            // Back may arrive while a pointer is still down. Resolve it when the
            // gesture ends, unless a newer user page request has superseded it.
            snapshotFlow{pager.isScrollInProgress}.first{!it}
            if(pendingRevision==0L&&latestSelected==selectedPage&&pager.settledPage!=selectedPage) {
                lastDispatchedPage=selectedPage
                if(latestMenu.optBoolean("reduced"))pager.scrollToPage(selectedPage) else animatePage(selectedPage)
            }
        }
    }
    @Composable fun style(size:Int=17,bold:Boolean=false,muted:Boolean=false)=nativeTextStyle(color=text.copy(alpha=if(muted).65f else 1f),fontSize=size.sp,fontWeight=if(bold)FontWeight.Medium else FontWeight.Normal,scale=scale)
    @Composable fun glass(label:String,enabled:Boolean=true,primary:Boolean=false,modifier:Modifier=Modifier,centered:Boolean=false,minHeight:Int=56,navigation:Boolean=false,backwards:Boolean=false,onClick:()->Unit) {
        LiquidButton(adaptationKey=label,isLightTheme=text.red<.5f,onClick=onClick,backdrop=backdrop,enabled=enabled,isInteractive=enabled,
            modifier=modifier.fillMaxWidth().heightIn(min=(minHeight*scale).coerceAtLeast(minHeight.toFloat()).dp),shape=RoundedCornerShape(uiStyle.buttonRadius.dp),
            surfaceColor=if(!enabled)Color.Gray.copy(alpha=.28f) else GlassMaterial.surface(text.red<.5f,if(primary)tint else null)) {
            val ink=text.copy(alpha=if(enabled)1f else .4f)
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                if(navigation&&backwards)NativePreferenceArrow(false,ink,true)
                BasicText(label,Modifier.weight(1f),style=style().copy(textAlign=if(centered)TextAlign.Center else TextAlign.Start,fontWeight=uiStyle.buttonWeight,color=ink))
                if(navigation&&!backwards)NativePreferenceArrow(false,ink)
            }
        }
    }
    val appearanceRows=remember(menu){menu.getJSONArray("appearance").objects()}
    @Composable fun appearanceRow(i:Int,r:JSONObject) {
        val controlText=if(material)androidx.compose.material3.MaterialTheme.colorScheme.onSurface else Color(data.optLong("controlForeground",data.optLong("foreground")).toInt())
        val controlMuted=if(material)androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant else Color(data.optLong("controlMuted",data.optLong("mutedColor")).toInt())
        @Composable fun controlStyle(size:Int,bold:Boolean=false,muted:Boolean=false)=style(size,bold,muted).copy(color=if(muted)controlMuted else controlText)
          NativeSettingSegment(i,menu.getJSONArray("appearance").length()+1) {
          CompositionLocalProvider(LocalNativeSettingIcon provides r.optString("iconKey")) {
          val options=remember(r){r.optJSONArray("options")?.objects().orEmpty()}
          when(r.getString("kind")) {
              "note" -> if(r.getString("label").isNotBlank())BasicText(r.getString("label"),style=controlStyle(14,false,true))
              "select" -> if(!material)NativeMiuixDropdownPreference(
                  r.getString("label"),r.optString("description"),options,r.getString("value"),
                  enabled=!r.optBoolean("disabled"),onExpandedChange={choosing=if(it)r.getString("id") else null}){value->send("value",r.getString("id"),value)}
              else Box(Modifier.fillMaxWidth()) {
                  val option=options.find{it.getString("value")==r.getString("value")}
                  NativePreferenceRow(r.getString("label"),option?.getString("label")?:"",r.optString("description"),true,controlText,controlStyle(17),!r.optBoolean("disabled"),!r.optBoolean("disabled"),popupContent={
                  NativeSelectionPopup(choosing==r.getString("id"),data.optString("uiStyle"),options,r.getString("value"),controlText,Color(data.optLong("cardColor",0xff242424L).toInt()),tint,{choosing=null}) { value ->
                      if(send("value",r.getString("id"),value))choosing=null
                  }
                  }){choosing=r.getString("id")}
              }
              "button" -> if(r.optBoolean("navigation"))NativePreferenceRow(r.getString("label"),"",r.optString("description"),false,controlText,controlStyle(17),!r.optBoolean("disabled"),!r.optBoolean("disabled")){send("click",r.getString("id"))}
              else Column(Modifier.fillMaxWidth().padding(if(material)16.dp else 0.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                  if(r.optString("description").isNotEmpty())BasicText(r.getString("description"),style=controlStyle(14,false,true))
                  NativeDialogButton(r.getString("label"),data.optString("uiStyle"),controlText,Color(data.optLong("fieldColor",0xff2d2d2dL).toInt()),controlStyle(17),!r.optBoolean("disabled"),Modifier.align(Alignment.End),visualEnabled=!r.optBoolean("disabled")){send("click",r.getString("id"))}
              }
              "range" -> {
                  val key=r.getString("key")
                  fun current()=when(key){"glass-blur-strength"->glassControls.blurStrength;"glass-light"->glassControls.light;"glass-refraction"->glassControls.refraction;else->glassControls.transparency}
                  val value=current()
                  Column(Modifier.padding(if(material)16.dp else 0.dp)) {
                      NativeSliderLabel(r.getString("label"),value.roundToInt().toString()+"%",controlStyle(17).copy(color=controlText.copy(alpha=if(r.optBoolean("disabled")) .4f else 1f)),r.optString("description"))
                      NativeGlassSlider(data.optString("uiStyle"),r.getString("label"),value,!r.optBoolean("disabled"),!r.optBoolean("disabled"),tint,{v->glassControls.editing=true;when(key){"glass-blur-strength"->glassControls.blurStrength=v;"glass-light"->glassControls.light=v;"glass-refraction"->glassControls.refraction=v;else->glassControls.transparency=v}},{glassControls.editing=it}){
                          commitGlass(r.getString("id"),current().roundToInt())
                      }
                  }
              }
              "checkbox" -> NativeSwitchPreference(r.getString("label"),"",r.optBoolean("checked"),controlText,tint,controlStyle(17),!r.optBoolean("disabled")){value->if(value!=r.optBoolean("checked"))send("toggle",r.getString("id"))}
          }
          } }
    }
    @Composable fun shortcutRow() {
        val controlText=if(material)androidx.compose.material3.MaterialTheme.colorScheme.onSurface else Color(data.optLong("controlForeground",data.optLong("foreground")).toInt())
        val controlMuted=if(material)androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant else Color(data.optLong("controlMuted",data.optLong("mutedColor")).toInt())
        @Composable fun controlStyle(size:Int,bold:Boolean=false,muted:Boolean=false)=style(size,bold,muted).copy(color=if(muted)controlMuted else controlText)
          NativeSettingSegment(menu.getJSONArray("appearance").length(),menu.getJSONArray("appearance").length()+1) {
          CompositionLocalProvider(LocalNativeSettingIcon provides "shortcut") {
          NativePreferenceRow(NativeLanguage.text(androidx.compose.ui.platform.LocalContext.current,"建立桌面捷徑"),"",NativeLanguage.text(androidx.compose.ui.platform.LocalContext.current,"從桌面直接開啟目前的備份或恢復入口。"),false,controlText,controlStyle(17),true,true){dispatch.invoke("native:create-shortcut",epoch)}
          } }
    }
    val tabs=remember(data){data.getJSONArray("buttons").objects()}
    val contentBackdrop=rememberLayerBackdrop()
    val navigationBackdrop=rememberCombinedBackdrop(backdrop,contentBackdrop)
    val density=androidx.compose.ui.platform.LocalDensity.current
    val navigationBottom=(data.optDouble("safeBottom",(data.optDouble("bottom",20.0)-20.0).coerceAtLeast(0.0))+8.0).coerceIn(8.0,160.0).dp
    // LiquidBottomTabs is 64 dp tall; seed the measured inset to avoid a first-frame jump.
    var navigationHeight by remember(density,navigationBottom) { mutableIntStateOf(with(density){(64.dp+8.dp+navigationBottom).roundToPx()}) }
    val throughContent=data.optBoolean("glassContent")
    val navigationInset=if(tabs.size==4)with(density){navigationHeight.toDp()} else 0.dp
    val bottomSpace=if(tabs.size==4&&throughContent)with(density){navigationHeight.toDp()}+24.dp else 24.dp
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars.only(WindowInsetsSides.Top).union(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal)))) {
        // Native gesture arbitration lets child sliders own horizontal drags and
        // the vertical list own vertical drags, without replacing input nodes on DOWN.
        HorizontalPager(state=pager,userScrollEnabled=choosing==null&&pageAnimations==0,overscrollEffect=null,
            flingBehavior=PagerDefaults.flingBehavior(pager,snapAnimationSpec=pageSpec),
            modifier=Modifier.fillMaxSize().then(if(throughContent)Modifier.layerBackdrop(contentBackdrop) else Modifier.padding(bottom=navigationInset)),key={it}) { page ->
            LazyColumn(state=lists[page],modifier=Modifier.fillMaxSize(),contentPadding=PaddingValues(start=12.dp,top=8.dp,end=12.dp,bottom=bottomSpace),verticalArrangement=Arrangement.spacedBy(if(material&&page==2)2.dp else 12.dp)) {
                item("header") {
                    Column(Modifier.padding(bottom=if(material&&page==2)18.dp else 8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        val wifiRows=remember(menu){menu.optJSONObject("connection")?.optJSONArray("rows")?.objects().orEmpty()}
                        val measure=rememberTextMeasurer()
                        val density=androidx.compose.ui.platform.LocalDensity.current
                        val titleStyle=style(uiStyle.titleSize).copy(fontWeight=uiStyle.titleWeight)
                        val infoStyle=style(12)
                        val labelWidth=with(density){(wifiRows.maxOfOrNull{measure.measure(it.getString("label"),infoStyle).size.width}?:0).toDp()}
                        val valueWidth=with(density){(wifiRows.maxOfOrNull{measure.measure(it.getString("caption"),infoStyle).size.width}?:0).toDp()}
                        @Composable fun heading(){Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
                            BasicText(menu.getString("eyebrow"),style=style(17))
                            BasicText(menu.getString("title"),style=titleStyle)
                            BasicText(menu.getString("subtitle"),style=style(16))
                            if(menu.getString("status").isNotBlank())BasicText(menu.getString("status"),style=style())
                        }}
                        @Composable fun wifiInfo(){Column(verticalArrangement=Arrangement.spacedBy(3.dp)){
                            for(row in wifiRows)Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
                                BasicText(row.getString("label"),Modifier.width(labelWidth),style=infoStyle.copy(color=text.copy(alpha=.65f)))
                                BasicText(row.getString("caption"),Modifier.width(valueWidth),style=infoStyle.copy(textAlign=TextAlign.End,color=text.copy(alpha=.9f)))
                            }
                        }}
                        @Composable fun connectionDetails(){
                            Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        menu.optJSONObject("connection")?.takeIf{it.has("label")}?.let{connection ->
                            val transition=rememberInfiniteTransition(label="connection-status")
                            val pulse = transition.animateFloat(initialValue=.35f,targetValue=1f,animationSpec=infiniteRepeatable(tween(650),RepeatMode.Reverse),label="connection-pulse")
                            @Composable fun statusRow(label:String,state:String,modifier:Modifier=Modifier) {
                                val color=when(state){"ready"->Color(0xff35d779);"checking"->Color(0xffffc857);"local","idle","discovering","setup"->text.copy(alpha=.65f);else->Color(0xffff626b)}
                                Row(modifier.fillMaxWidth().heightIn(min=20.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                                    androidx.compose.foundation.Canvas(Modifier.size(12.dp)) {
                                        // Read animation state only in drawing: pulse without
                                        // recomposing status text or remeasuring the header.
                                        drawCircle(Brush.radialGradient(listOf(color.copy(alpha=if(state=="local"||state=="idle")1f else pulse.value),color.copy(alpha=.15f))))
                                    }
                                    BasicText(label,modifier=Modifier.weight(1f),style=style(14).copy(color=color,textAlign=TextAlign.Start))
                                }
                            }
                            Column(verticalArrangement=Arrangement.spacedBy(2.dp)) {
                            statusRow(connection.getString("label"),connection.optString("state"),Modifier.clickable(enabled=connection.optString("state")!="local"){send("click",connection.getString("id"))})
                            for(daemon in connection.optJSONArray("daemons")?.objects().orEmpty())statusRow(daemon.getString("label"),daemon.getString("state"))
                            }
                        }
                            }
                        }
                        BoxWithConstraints(Modifier.fillMaxWidth()){
                            val rightWidth=maxOf(labelWidth+valueWidth+8.dp,100.dp).coerceAtMost(maxWidth*.47f)
                            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.Top){
                                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(12.dp)){heading();connectionDetails()}
                                Column(Modifier.width(rightWidth),verticalArrangement=Arrangement.spacedBy(6.dp),horizontalAlignment=Alignment.End){
                                    if(wifiRows.isNotEmpty())wifiInfo()
                                    menu.optJSONObject("connection")?.optString("detail")?.takeIf{it.isNotEmpty()}?.let{BasicText(it,style=infoStyle.copy(color=text.copy(alpha=.85f),textAlign=TextAlign.End))}
                                }
                            }
                        }
                    }
                }
                if(page==0) {
                    menu.getJSONArray("info").objects().forEachIndexed { i,g ->
                        item("info-$i") {
                            Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                                BasicText(g.getString("title"),style=style(16,true))
                                NativeHomeInfoGroup(g.getJSONArray("rows").objects(),
                                    Color(data.optLong("cardColor",0xff242424L).toInt()),
                                    Color(data.optLong("controlForeground",0xffffffffL).toInt()))
                                Spacer(Modifier.height(8.dp))
                            }
                        }
                    }
                } else if(page==1) {
                    for(r in menu.getJSONArray("choices").objects())item(r.getString("id")) {
                        if(r.getString("kind")=="heading")BasicText(r.getString("label"),style=style(20,true))
                        else glass(r.getString("label"),!r.optBoolean("disabled"),r.optBoolean("primary")||r.optBoolean("selected"),navigation=r.optBoolean("navigation")||r.optBoolean("backNavigation"),backwards=r.optBoolean("backNavigation")) { send("click",r.getString("id")) }
                    }
                } else {
                    if(material) {
                        appearanceRows.forEachIndexed { i,r ->
                            item("appearance-"+r.optString("id","note-$i"),contentType=r.getString("kind")) {
                                DisposableEffect(r.optString("id")){onDispose{if(choosing==r.optString("id"))choosing=null}}
                                appearanceRow(i,r)
                            }
                        }
                        item("appearance-shortcut",contentType="button"){shortcutRow()}
                    } else item("appearance-card") {
                        NativeSettingsCard("miuix",Color(data.optLong("cardColor",0xff242424L).toInt()),Color(data.optLong("controlForeground",data.optLong("foreground")).toInt()),backdrop=backdrop) {
                            Column(Modifier.padding(16.dp)) {
                                appearanceRows.forEachIndexed { i,r -> key(r.optString("id","note-$i")){appearanceRow(i,r)} }
                                shortcutRow()
                            }
                        }
                    }
                }
            }
        }
        if(tabs.size==4) Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onSizeChanged{navigationHeight=it.height}.padding(start=16.dp,end=16.dp,bottom=navigationBottom,top=8.dp)) {
            LiquidBottomTabs(selectedTabIndex={if(pager.isScrollInProgress)pager.targetPage else pager.settledPage},onTabSelected={if(it in 0..2)navigate(it)},backdrop=if(throughContent)navigationBackdrop else backdrop,tabsCount=4,selectableTabs=3,
                pageDragPosition={if(pageDragging)pager.currentPage+pager.currentPageOffsetFraction else null},isLightTheme=text.red<.5f,accentColor=tint,modifier=Modifier.fillMaxWidth()) {
                tabs.forEachIndexed { index,tab -> LiquidBottomTab(modifier=Modifier.semantics{selected=index==pager.settledPage},onClick={
                    if(!tab.optBoolean("disabled")) { if(index<3)navigate(index) else dispatch.invoke(tab.getString("id"),epoch) }
                }) {
                    val ink=text
                    val icon=if(material)when(index){0->Icons.Default.Home;1->Icons.Default.Apps;2->Icons.Default.Settings;else->Icons.Default.PowerSettingsNew} else when(index){0->MiuixIcons.Home;1->MiuixIcons.GridView;2->MiuixIcons.Settings;else->MiuixIcons.Close2}
                    if(material)androidx.compose.material3.Icon(icon,null,Modifier.size(22.dp),tint=ink)
                    else top.yukonga.miuix.kmp.basic.Icon(icon,null,Modifier.size(22.dp),tint=ink)
                    // Keep the independent liquid-glass label metrics unchanged.
                    BasicText(tab.getString("label"),style=TextStyle(color=ink,fontSize=(14*scale).sp,fontWeight=FontWeight.Medium))
                } }
            }
        }
    }

}

/** Native preview only while dragging; one semantic commit when released. */
@Composable private fun NativeGlassSlider(uiStyle:String,label:String,value:Float,enabled:Boolean,visualEnabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
    NativeMiuixSlider(label,value,enabled,visualEnabled,tint,onValue,onDragging,onCommit)
}
@Composable internal fun NativeSettingSlider(uiStyle:String,label:String,value:Float,min:Int,max:Int,enabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
    NativeMiuixRangeSlider(label,value,min,max,enabled,enabled,tint,onValue,onDragging,onCommit)
}
