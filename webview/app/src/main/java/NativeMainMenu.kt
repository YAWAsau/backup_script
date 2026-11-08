package io.github.yawasau.speedbackup.webview

import androidx.compose.animation.core.tween
import androidx.compose.ui.layout.onSizeChanged
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.lazy.LazyColumn
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

internal data class NativeUiStyle(val titleSize:Int,val titleWeight:FontWeight,val buttonRadius:Int,val buttonWeight:FontWeight,val dialogRadius:Int)
internal fun nativeUiStyle()=NativeUiStyle(32,FontWeight.Normal,24,FontWeight.Medium,28)

private val nativePageRevision=java.util.concurrent.atomic.AtomicLong()
private fun JSONArray.objects()=(0 until length()).map { getJSONObject(it) }

/** Bounds are checked before accepting an authenticated document's semantic menu. */
internal fun validateNativeMenu(menu:JSONObject?) {
    if(menu==null)return
    fun text(o:JSONObject,k:String)=require(o.getString(k).length<=8192)
    for(k in listOf("title","eyebrow","subtitle","status","cancel"))text(menu,k)
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
    val resumePrefs=androidx.compose.ui.platform.LocalContext.current.getSharedPreferences("native_viewport_v1",android.content.Context.MODE_PRIVATE)
    val resumePageKey=remember(data.optString("resumeSession")){resumeKey(data.optString("resumeSession"),"main-menu:selected")}
    val resumePage=remember(resumePageKey){try{JSONObject(resumePrefs.getString(resumePageKey,null)?:"{}").optInt("page",selectedPage).coerceIn(0,2)}catch(_:Exception){selectedPage}}
    val pager=rememberPagerState(initialPage=resumePage,pageCount={3})
    val scope=rememberCoroutineScope()
    val pageDragging by pager.interactionSource.collectIsDraggedAsState()
    val latestData by rememberUpdatedState(data)
    val latestMenu by rememberUpdatedState(menu)
    val latestSelected by rememberUpdatedState(selectedPage)
    var lastDispatchedPage by remember { mutableIntStateOf(selectedPage) }
    val uiStyle=nativeUiStyle()
    val text=Color(data.optLong("foreground",0xffeeeeeeL).toInt())
    val tint=Color(data.optLong("accent",0xff96bdffL).toInt())
    val background=Color(data.optLong("background",0xff151c30L).toInt())
    val glassControls=GlassMaterial.LocalControls.current
    var adjustingGlass by remember { mutableStateOf(false) }
    val scale=data.optDouble("scale",1.0).coerceIn(.7,1.5).toFloat()
    val lists=List(3){rememberResumeList(data.optString("resumeSession"),"main-menu:$it")}
    val moving=pager.isScrollInProgress||lists.any{it.isScrollInProgress}
    LaunchedEffect(moving){onMotion(moving)}
    DisposableEffect(Unit){onDispose{onMotion(false)}}
    var pendingRevision by remember { mutableLongStateOf(0) }
    var previousAck by remember { mutableLongStateOf(menu.optLong("revision")) }
    var previousSelection by remember { mutableIntStateOf(selectedPage) }
    var choosing by remember { mutableStateOf<String?>(null) }
    fun send(kind:String,id:String="",value:String=""):Boolean {
        if(moving)return false
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
        scope.launch { if(latestMenu.optBoolean("reduced"))pager.scrollToPage(index) else pager.animateScrollToPage(index,animationSpec=tween(260)) }
    }
    // Only semantic page changes cross the bridge. No currentPageOffsetFraction collector.
    LaunchedEffect(pager,epoch) {
        snapshotFlow { if(pager.isScrollInProgress)null else pager.settledPage }.distinctUntilChanged().collect { page ->
            if(page!=null)resumePrefs.edit().putString(resumePageKey,JSONObject().put("page",page).put("time",System.currentTimeMillis()).toString()).apply()
            if(page!=null&&page!=lastDispatchedPage){
                lastDispatchedPage=page
                pendingRevision=nativePageRevision.incrementAndGet()
                dispatch.invoke("menu:"+JSONObject().put("kind","page").put("index",page).put("revision",pendingRevision),epoch)
            }
        }
    }
    LaunchedEffect(pendingRevision) {
        if(pendingRevision>0){
            kotlinx.coroutines.delay(2000)
            snapshotFlow{pager.isScrollInProgress}.first{!it}
            pendingRevision=0
            lastDispatchedPage=latestSelected
            if(pager.settledPage!=latestSelected)pager.animateScrollToPage(latestSelected,animationSpec=tween(260))
        }
    }
    // Back/navigation initiated by the existing document is also native motion.
    LaunchedEffect(selectedPage,menu.optLong("revision")) {
        val ack=menu.optLong("revision")
        val external=ack==previousAck&&selectedPage!=previousSelection
        previousAck=ack;previousSelection=selectedPage
        if(ack<pendingRevision)return@LaunchedEffect
        pendingRevision=0
        if(external&&!pager.isScrollInProgress&&pager.settledPage!=selectedPage) {
            lastDispatchedPage=selectedPage
            if(menu.optBoolean("reduced"))pager.scrollToPage(selectedPage) else pager.animateScrollToPage(selectedPage,animationSpec=tween(260))
        }
    }
    fun style(size:Int=17,bold:Boolean=false,muted:Boolean=false)=TextStyle(color=text.copy(alpha=if(muted).65f else 1f),fontSize=(size*scale).sp,fontWeight=if(bold)FontWeight.Medium else FontWeight.Normal)
    @Composable fun glass(label:String,enabled:Boolean=true,primary:Boolean=false,modifier:Modifier=Modifier,centered:Boolean=false,minHeight:Int=52,navigation:Boolean=false,backwards:Boolean=false,onClick:()->Unit) {
        LiquidButton(adaptationKey=label,isLightTheme=text.red<.5f,onClick=onClick,backdrop=backdrop,enabled=enabled&&!pager.isScrollInProgress,isInteractive=enabled,
            modifier=modifier.fillMaxWidth().heightIn(min=(minHeight*scale).coerceAtLeast(minHeight.toFloat()).dp),shape=RoundedCornerShape(uiStyle.buttonRadius.dp),
            surfaceColor=GlassMaterial.surface(text.red<.5f,if(primary)tint else null)) {
            val ink=(com.kyant.backdrop.catalog.components.LocalGlassContentColor.current.takeUnless{it==Color.Unspecified}?:text).copy(alpha=if(enabled)1f else .4f)
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                if(navigation&&backwards)NativePreferenceArrow(false,ink,true)
                BasicText(label,Modifier.weight(1f),style=style().copy(textAlign=if(centered)TextAlign.Center else TextAlign.Start,fontWeight=uiStyle.buttonWeight,color=ink))
                if(navigation&&!backwards)NativePreferenceArrow(false,ink)
            }
        }
    }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars.only(WindowInsetsSides.Top).union(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal)))) {
        HorizontalPager(state=pager,userScrollEnabled=choosing==null&&!adjustingGlass,modifier=Modifier.weight(1f).fillMaxWidth(),key={it}) { page ->
            LazyColumn(state=lists[page],modifier=Modifier.fillMaxSize(),contentPadding=PaddingValues(12.dp,24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                item("header") {
                    Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        BasicText(menu.getString("eyebrow"),style=style(17))
                        BasicText(menu.getString("title"),style=style(uiStyle.titleSize).copy(fontWeight=uiStyle.titleWeight))
                        BasicText(menu.getString("subtitle"),style=style(17))
                        if(menu.getString("status").isNotBlank())BasicText(menu.getString("status"),style=style())
                        Spacer(Modifier.height(8.dp))
                    }
                }
                if(page==0) {
                    menu.getJSONArray("info").objects().forEachIndexed { i,g ->
                        item("info-$i") {
                            Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                                BasicText(g.getString("title"),style=style(16,true))
                                for(r in g.getJSONArray("rows").objects()) Row(horizontalArrangement=Arrangement.spacedBy(16.dp),verticalAlignment=Alignment.CenterVertically) {
                                    val label=r.getString("label")
                                    val labelStyle=style(17)
                                    val measurer=rememberTextMeasurer()
                                    var labelWidth by remember { mutableIntStateOf(0) }
                                    val fittedSize=remember(measurer,label,labelStyle,labelWidth) {
                                        val original=labelStyle.fontSize
                                        if(labelWidth<=1) original else {
                                            fun fits(ratio:Float)=measurer.measure(label,labelStyle.copy(fontSize=original*ratio),softWrap=false,maxLines=1).size.width<=labelWidth-1
                                            if(fits(1f)) original else {
                                                var low=.25f;var high=1f
                                                repeat(10){val mid=(low+high)/2f;if(fits(mid))low=mid else high=mid}
                                                original*low
                                            }
                                        }
                                    }
                                    BasicText(label,Modifier.weight(1f).alignByBaseline().onSizeChanged{labelWidth=it.width},style=labelStyle.copy(fontSize=fittedSize),maxLines=1,softWrap=false,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                                    BasicText(r.getString("value"),Modifier.weight(2f).alignByBaseline(),style=style(17))
                                }
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
                    item("appearance-card") {
                      NativeComponentCard("miuix",Color(data.optLong("cardColor",0xff242424L).toInt()),text,backdrop=backdrop) {
                       Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(0.dp)) {
                        menu.getJSONArray("appearance").objects().forEachIndexed { i,r -> key(r.optString("id","note-$i")) {
                        when(r.getString("kind")) {
                            "note" -> if(r.getString("label").isNotBlank())BasicText(r.getString("label"),style=style(14,false,true))
                            "select" -> Box(Modifier.fillMaxWidth()) {
                                val option=r.getJSONArray("options").objects().find{it.getString("value")==r.getString("value")}
                                NativePreferenceRow(r.getString("label"),option?.getString("label")?:"","",true,text,style(17),!r.optBoolean("disabled")&&!moving,!r.optBoolean("disabled")){choosing=r.getString("id")}
                                NativeSelectionPopup(choosing==r.getString("id"),data.optString("uiStyle"),r.getJSONArray("options").objects(),r.getString("value"),text,Color(data.optLong("cardColor",0xff242424L).toInt()),tint,{choosing=null}) { value ->
                                    if(send("value",r.getString("id"),value))choosing=null
                                }
                            }
                            "button" -> NativeDialogButton(r.getString("label"),"miuix",text,Color(data.optLong("fieldColor",0xff2d2d2dL).toInt()),style(17),!r.optBoolean("disabled")&&!moving,Modifier.fillMaxWidth(),visualEnabled=!r.optBoolean("disabled"),navigation=r.optBoolean("navigation")){send("click",r.getString("id"))}
                            "range" -> {
                                val key=r.getString("key")
                                fun current()=when(key){"glass-blur-strength"->glassControls.blurStrength;"glass-light"->glassControls.light;"glass-refraction"->glassControls.refraction;else->glassControls.transparency}
                                val value=current()
                                Column {
                                    NativeSliderLabel(r.getString("label"),value.roundToInt().toString()+"%",style(17).copy(color=text.copy(alpha=if(r.optBoolean("disabled")) .4f else 1f)))
                                    NativeGlassSlider(data.optString("uiStyle"),r.getString("label"),value,!r.optBoolean("disabled")&&!moving,!r.optBoolean("disabled"),tint,{v->glassControls.editing=true;when(key){"glass-blur-strength"->glassControls.blurStrength=v;"glass-light"->glassControls.light=v;"glass-refraction"->glassControls.refraction=v;else->glassControls.transparency=v}},{adjustingGlass=it;glassControls.editing=it}){
                                        commitGlass(r.getString("id"),current().roundToInt())
                                    }
                                }
                            }
                            "checkbox" -> NativeSwitchPreference(r.getString("label"),"",r.optBoolean("checked"),text,tint,style(17),!r.optBoolean("disabled")&&!moving){value->if(value!=r.optBoolean("checked"))send("toggle",r.getString("id"))}
                        }
                        } }
                       }
                      }
                    }
                }
            }
        }
        val tabs=data.getJSONArray("buttons").objects()
        if(tabs.size==4) Box(Modifier.fillMaxWidth().padding(start=16.dp,end=16.dp,bottom=data.optDouble("bottom",20.0).coerceIn(0.0,160.0).dp,top=8.dp)) {
            LiquidBottomTabs(selectedTabIndex={if(pager.isScrollInProgress)pager.targetPage else pager.settledPage},onTabSelected={if(it in 0..2)navigate(it)},backdrop=backdrop,tabsCount=4,selectableTabs=3,
                pageDragPosition={if(pageDragging)pager.currentPage+pager.currentPageOffsetFraction else null},isLightTheme=text.red<.5f,accentColor=tint,modifier=Modifier.fillMaxWidth()) {
                tabs.forEachIndexed { index,tab -> LiquidBottomTab(modifier=Modifier.semantics{selected=index==pager.settledPage},onClick={
                    if(!tab.optBoolean("disabled")) { if(index<3)navigate(index) else if(!pager.isScrollInProgress)dispatch.invoke(tab.getString("id"),epoch) }
                }) { BasicText(tab.getString("label"),style=style(17,true).copy(color=com.kyant.backdrop.catalog.components.LocalGlassContentColor.current.takeUnless{it==Color.Unspecified}?:text)) } }
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
