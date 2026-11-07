package io.github.yawasau.speedbackup.webview

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.Backdrop
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

private val nativeControlId=Regex("control-[0-9]{1,12}")
private val nativeEditRevision=java.util.concurrent.atomic.AtomicLong()
private fun JSONArray.nodes()=(0 until length()).map{getJSONObject(it)}
internal fun validateNativeDocument(screen:JSONObject?) {
    if(screen==null)return
    require(screen.optString("unset").length<=256)
    var count=0;var logCount=0;var logCharacters=0
    val ids=HashSet<String>()
    fun validate(a:JSONArray,depth:Int) {
        require(depth<=8&&a.length()<=2200)
        for(n in a.nodes()) {
            require(++count<=6000)
            require(n.getString("kind") in setOf("range","button","toggle","input","select","text","heading","link","log","progress","app","group","license","loading"))
            require(n.getString("id").matches(nativeControlId)&&ids.add(n.getString("id")))
            for(k in listOf("label","value","detail","description","caption","placeholder"))require(n.optString(k).length<=262144)
            require(n.optString("icon").length<=131072)
            if(n.getString("kind")=="loading")require(n.optString("indicator") in setOf("","orbit","circular"))
            val kind=n.getString("kind")
            if(kind=="license"){val uri=android.net.Uri.parse(n.getString("url"));require(n.getString("url").length<=4096&&uri.scheme=="https"&&!uri.host.isNullOrBlank()&&uri.userInfo==null)}
            if(kind=="log"){require(++logCount<=300);val length=n.getString("label").length;val spans=n.optJSONArray("spans");require((spans?.length()?:0)<=25);val rendered=spans?.nodes()?.sumOf{it.getString("text").length}?:length;logCharacters+=maxOf(length,rendered);require(length<=8193&&rendered<=8193&&logCharacters<=65536)}
            require(n.optString("layout") in setOf("","setting","settings-section","toggle","row","edit-row","toolbar","controls","log-actions"))
            if(kind!="group"&&kind!="progress")require(n.getString("label").length<=262144)
            if(kind=="range") {
                val min=n.getInt("min");val max=n.getInt("max");val value=n.getString("value").toInt()
                require(min>=0&&max<=256&&max>min&&value in min..max)
                require(n.optString("preserved").length<=262144&&n.optString("zeroLabel").length<=256)
            }
            if(kind in setOf("input","select"))require(n.getString("value").length<=262144)
            if(kind=="app"||kind=="license"||(kind=="group"&&n.optString("layout")=="setting"))require(n.getString("detail").length<=262144)
            if(kind in setOf("group","app"))require(n.getJSONArray("children").length()<=2200)
            if(kind=="select") {
                val options=n.getJSONArray("options");require(options.length()<=1000)
                require(options.nodes().map{it.getString("value")}.distinct().size==options.length())
                for(o in options.nodes())for(k in listOf("value","label"))require(o.getString(k).length<=262144)
            }
            if(kind=="progress") {
                val rows=n.getJSONArray("rows");require(rows.length()<=8)
                for(r in rows.nodes()){require(r.getString("label").length<=262144);require(r.getDouble("value").let{it.isFinite()&&it in 0.0..1.0})}
            }
            n.optJSONArray("spans")?.let { for(r in it.nodes())require(r.getString("text").length<=262144) }
            n.optJSONArray("children")?.let{validate(it,depth+1)}
            require((n.optJSONArray("spans")?.length()?:0)<=8192)
        }
    }
    for(k in listOf("key","title","eyebrow","subtitle","hint","cancel"))require(screen.getString(k).length<=262144)
    validate(screen.getJSONArray("nodes"),0);validate(screen.getJSONArray("footer"),0)
    screen.optJSONObject("dialog")?.let { require(it.getString("id").matches(nativeControlId));validate(it.getJSONArray("nodes"),0) }
}


/** Worker-confined, bounded cache. Layout objects are read-only after publication. */
class NativeLogCache {
    private var context=""
    private val rows=LinkedHashMap<String,Pair<String,NativeLogRow>>()
    private var foreground=Color.White;private var width=1;private var textSize=1f
    internal fun begin(epoch:String,color:Color,width:Int,textSize:Float){
        val next="$epoch:$color:$width:$textSize"
        if(context!=next){rows.clear();context=next}
        foreground=color;this.width=width;this.textSize=textSize
    }
    internal fun row(node:JSONObject):NativeLogRow {
        val id=node.getString("id");val signature=node.toString()
        rows[id]?.takeIf{it.first==signature}?.let{return it.second}
        val row=prepareNativeLog(node,foreground,width,textSize)
        if(rows.size>=300)rows.remove(rows.keys.first())
        rows[id]=signature to row;return row
    }
    internal fun retain(ids:Set<String>){rows.keys.retainAll(ids)}
}

@Immutable data class NativeLogChunk(val id:String,val rows:List<NativeLogRow>,val height:Int,val gap:Int,val text:AnnotatedString)
internal fun chunkNativeLogs(rows:List<NativeLogRow>,gap:Int):List<NativeLogChunk> {
    val chunks=ArrayList<NativeLogChunk>();var group=ArrayList<NativeLogRow>();var bucket=-1L
    fun flush(){if(group.isNotEmpty()){val copy=group.toList();chunks.add(NativeLogChunk(copy.first().id,copy,copy.sumOf{it.advance(gap)},gap,buildAnnotatedString{copy.forEachIndexed{i,row->if(i>0)append("\n");append(row.text)}}));group=ArrayList()}}
    for(row in rows){val next=row.id.substringAfter("control-").toLong()/8;if(next!=bucket){flush();bucket=next};group.add(row)}
    flush();return chunks
}

@Immutable data class NativeLogRow(val id:String,val text:AnnotatedString,val layout:android.text.StaticLayout,val divider:Boolean=false) {
    fun advance(gap:Int):Int=layout.height+if(divider)gap*3 else gap
}
internal fun prepareNativeLog(n:JSONObject,foreground:Color,width:Int,textSize:Float):NativeLogRow {
    val text=buildAnnotatedString {
        val spans=n.optJSONArray("spans")
        if(spans==null||spans.length()==0)append(n.getString("label"))
        else for(run in spans.nodes())withStyle(SpanStyle(color=if(run.optLong("color")==0L)foreground else Color(run.getLong("color").toInt()),fontWeight=FontWeight(run.optInt("weight",400).coerceIn(100,900)))){append(run.getString("text"))}
    }
    val styled=android.text.SpannableString(text.text)
    for(span in text.spanStyles){
        styled.setSpan(android.text.style.ForegroundColorSpan(span.item.color.toArgb()),span.start,span.end,android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if((span.item.fontWeight?.weight?:400)>=600)styled.setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD),span.start,span.end,android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
    val paint=android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.SUBPIXEL_TEXT_FLAG).apply{this.textSize=textSize;color=foreground.toArgb();typeface=android.graphics.Typeface.DEFAULT}
    val layout=android.text.StaticLayout.Builder.obtain(styled,0,styled.length,paint,width.coerceAtLeast(1)).setIncludePad(false).setBreakStrategy(android.text.Layout.BREAK_STRATEGY_HIGH_QUALITY).build()
    return NativeLogRow(n.getString("id"),text,layout,n.optBoolean("divider"))
}

private data class NativeDocumentStyle(val text:Color,val accent:Color,val backdrop:Backdrop,val scale:Float,val resumed:Boolean,val uiStyle:String,val card:Color,val field:Color,val muted:Color,val line:Color,val compact:Boolean=false,val grouped:Boolean=false,val inDialog:Boolean=false,val unset:String="未設定",val reducedMotion:Boolean=false) {
    fun text(size:Int=16,bold:Boolean=false)=TextStyle(color=text,fontSize=(size*scale).sp,fontWeight=if(bold)FontWeight.Medium else FontWeight.Normal)

}

// View-only state: scoped to the live HTTP session and route, never backup choices.
internal fun resumeKey(session:String,route:String):String = java.security.MessageDigest.getInstance("SHA-256").digest((session+"\n"+route).toByteArray()).joinToString(""){"%02x".format(it)}
@Composable internal fun rememberResumeList(session:String,route:String,enabled:Boolean=true):androidx.compose.foundation.lazy.LazyListState {
    val context=androidx.compose.ui.platform.LocalContext.current.applicationContext
    val prefs=remember{context.getSharedPreferences("native_viewport_v1",android.content.Context.MODE_PRIVATE)}
    val id=remember(session,route){resumeKey(session,route)}
    LaunchedEffect(id){withContext(Dispatchers.IO){val entries=prefs.all;if(entries.size>256){val edit=prefs.edit();entries.entries.filter{it.key!=id}.sortedBy{try{org.json.JSONObject(it.value.toString()).optLong("time")}catch(_:Exception){0L}}.take(entries.size-256).forEach{edit.remove(it.key)};edit.apply()}}}
    val initial=remember(id){try{org.json.JSONObject(prefs.getString(id,null)?:"{}")}catch(_:Exception){org.json.JSONObject()}}
    val fresh=System.currentTimeMillis()-initial.optLong("time",0)<7L*24*3600*1000
    val list=key(id){rememberLazyListState(if(fresh)initial.optInt("index",0).coerceIn(0,100000)else 0,if(fresh)initial.optInt("offset",0).coerceIn(0,100000)else 0)}
    var restored by remember(id){mutableStateOf(!fresh)}
    LaunchedEffect(list,id,enabled){
        if(!enabled||restored)return@LaunchedEffect
        val target=initial.optInt("index",0).coerceIn(0,100000)
        val loaded=kotlinx.coroutines.withTimeoutOrNull(3000){snapshotFlow{Pair(list.layoutInfo.totalItemsCount,list.isScrollInProgress)}.first{it.first>target||it.second}}
        if(list.layoutInfo.totalItemsCount==0)snapshotFlow{list.layoutInfo.totalItemsCount}.first{it>0}
        if(loaded?.second!=true&&!list.isScrollInProgress&&list.layoutInfo.totalItemsCount>0)list.scrollToItem(target.coerceAtMost(list.layoutInfo.totalItemsCount-1),initial.optInt("offset",0).coerceIn(0,100000))
        restored=true
    }
    fun save(){
        if(!restored||!enabled||session.isEmpty()||list.layoutInfo.totalItemsCount==0)return
        val value=org.json.JSONObject().put("index",list.firstVisibleItemIndex).put("offset",list.firstVisibleItemScrollOffset).put("time",System.currentTimeMillis()).toString()
        val edit=prefs.edit().putString(id,value)
        edit.apply()
    }
    LaunchedEffect(list,id,enabled){
        if(!enabled)return@LaunchedEffect
        snapshotFlow{list.layoutInfo.totalItemsCount}.first{it>0}
        var last=0L
        snapshotFlow{Triple(list.firstVisibleItemIndex,list.firstVisibleItemScrollOffset,list.isScrollInProgress)}.collect{p->
            val now=android.os.SystemClock.uptimeMillis()
            if(now-last>=250||!p.third){last=now;save()}
        }
    }
    DisposableEffect(list,id,enabled){onDispose{save()}}
    return list
}

@Composable internal fun NativeDocument(screen:JSONObject,data:JSONObject,logs:List<NativeLogChunk>,backdrop:Backdrop,resumed:Boolean,dispatch:NativeChrome.Action,onMotion:(Boolean)->Unit) {
    val style=NativeDocumentStyle(Color(data.optLong("foreground",0xffeeeeeeL).toInt()),Color(data.optLong("accent",0xff96bdffL).toInt()),backdrop,data.optDouble("scale",1.0).coerceIn(.7,1.5).toFloat(),resumed,data.optString("uiStyle","miuix"),Color(data.optLong("cardColor",0xff242424L).toInt()),Color(data.optLong("fieldColor",0xff2d2d2dL).toInt()),Color(data.optLong("mutedColor",0xffaaaaaaL).toInt()),Color(data.optLong("lineColor",0xff404040L).toInt()),unset=screen.optString("unset","未設定"),reducedMotion=data.optBoolean("reducedMotion"))
    val importWallpaper=rememberWallpaperImport()
    val epoch=data.getString("epoch")
    val list=rememberResumeList(data.optString("resumeSession"),data.optString("sectionRoute").ifEmpty{screen.getString("key")},(screen.optInt("appPage",-1)>=0||screen.getString("key")!="editor:apps")&&(screen.getString("key")!="console"||screen.optJSONObject("history")?.optBoolean("loading")!=true))
    val appPage=screen.optInt("appPage",-1)
    val previousAppPage=remember {intArrayOf(appPage)}
    SideEffect {
        if(appPage>=0 && previousAppPage[0]!=appPage)list.requestScrollToItem(0)
        previousAppPage[0]=appPage
    }
    LaunchedEffect(list.isScrollInProgress){onMotion(list.isScrollInProgress)}
    DisposableEffect(Unit){onDispose{onMotion(false)}}
    val viewPrefs=androidx.compose.ui.platform.LocalContext.current.getSharedPreferences("native_viewport_v1",android.content.Context.MODE_PRIVATE)
    val followKey=remember(data.optString("resumeSession")){resumeKey(data.optString("resumeSession"),"console:following")}
    var following by remember(followKey) { mutableStateOf(try{JSONObject(viewPrefs.getString(followKey,null)?:"{}").optBoolean("following",true)}catch(_:Exception){true}) }
    var userScrolled by remember(followKey){mutableStateOf(false)}
    fun saveFollowing(value:Boolean){if(screen.getString("key")=="console")viewPrefs.edit().putString(followKey,JSONObject().put("following",value).put("time",System.currentTimeMillis()).toString()).apply()}
    var followRequest by remember { mutableIntStateOf(0) }
    val console=screen.getString("key")=="console"
    val history=screen.optJSONObject("history")
    val historyActive=history?.optBoolean("active")==true
    val licensePage=screen.getString("key")=="menu:licenses"
    val nodes=remember(screen){screen.getJSONArray("nodes").nodes()}
    val dialog=screen.optJSONObject("dialog")
    fun send(kind:String,id:String,value:String=""):Long {
        fun follows(items:List<JSONObject>):Boolean=items.any{(it.optString("id")==id&&it.optBoolean("follow"))||(it.optJSONArray("children")?.nodes()?.let{children->follows(children)}==true)}
        if(kind=="click"&&follows(nodes+screen.getJSONArray("footer").nodes())){following=true;saveFollowing(true);followRequest++}
        val r=nativeEditRevision.incrementAndGet()
        if(kind=="license"){dispatch.invoke("license:"+id,epoch);return r}
        dispatch.invoke("screen:"+JSONObject().put("kind",kind).put("id",id).put("value",value).put("revision",r),epoch)
        return r
    }
    val viewportHeight by remember{derivedStateOf{list.layoutInfo.viewportSize.height}}
    val density=LocalDensity.current.density
    val dividerPaint=remember(density,style.scale,style.muted) {
        val unit=density*style.scale
        val lineColor=style.muted.copy(alpha=.65f).toArgb()
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color=lineColor;strokeWidth=unit
            this.style=android.graphics.Paint.Style.STROKE
            pathEffect=android.graphics.DashPathEffect(floatArrayOf(4f*unit,4f*unit),0f)
        }
    }
    val userDragging by list.interactionSource.collectIsDraggedAsState()
    // Queue the tail position for the same measure pass as the new rows. A
    // post-layout coroutine briefly displays the old position before correcting it.
    val tailTarget=listOf(nodes.size,logs.size,logs.lastOrNull()?.rows?.lastOrNull()?.id,
        logs.lastOrNull()?.height,viewportHeight,followRequest,following,historyActive,dialog!=null)
    val appliedTail=remember { arrayOf<List<Any?>?>(null) }
    SideEffect {
        if(appliedTail[0]!=tailTarget){
            appliedTail[0]=tailTarget
            if(console&&following&&!historyActive&&history?.optBoolean("loading")!=true&&dialog==null&&!userDragging&&!list.isScrollInProgress)
                list.requestScrollToItem((nodes.size+logs.size).coerceAtLeast(0),((logs.lastOrNull()?.height?:0)-viewportHeight+(48*density).toInt()).coerceAtLeast(0))
        }
    }
    LaunchedEffect(userDragging) { if(console&&userDragging){following=false;userScrolled=true;saveFollowing(false)} }
    LaunchedEffect(list,console,historyActive) {
        snapshotFlow{!list.isScrollInProgress&&list.layoutInfo.totalItemsCount>0&&!list.canScrollForward}.collect{atEnd->if(console&&!historyActive&&atEnd&&userScrolled){following=true;saveFollowing(true)}}
    }
    LaunchedEffect(history?.optLong("revision",0)) {
        if(historyActive){
            following=false
            if(history?.optString("direction")=="before")list.scrollToItem((nodes.size+logs.size).coerceAtLeast(0),((logs.lastOrNull()?.height?:0)-viewportHeight).coerceAtLeast(0))
            else if(history?.optString("direction")!="resume")list.scrollToItem(0)
        }else if(history?.optString("direction")=="live"){following=true;saveFollowing(true);followRequest++}
    }
    // At most one older-page request per physical upward-scroll gesture.
    // A page replacement cannot recursively trigger another request.
    LaunchedEffect(userDragging) {
        if(userDragging&&console&&history?.optBoolean("loading")==false&&history.optBoolean("canLoadOlder")){
            snapshotFlow{list.lastScrolledBackward&&list.firstVisibleItemIndex<=nodes.size+1}.first{it}
            send("click",history.getString("olderId"))
        }
    }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars.only(WindowInsetsSides.Top).union(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal)))) {
        LazyColumn(state=list,modifier=Modifier.weight(1f).fillMaxWidth(),contentPadding=PaddingValues(12.dp,24.dp),verticalArrangement=Arrangement.spacedBy(0.dp)) {
            item("header") { Column(Modifier.padding(bottom=20.dp),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                if(licensePage) {
                    val back=screen.getJSONArray("footer").nodes().firstOrNull()
                    if(back!=null)BasicText("‹",Modifier.clickable(role=Role.Button){send("click",back.getString("id"))}.padding(8.dp).semantics{contentDescription=back.getString("label")},style=style.text(32))
                }
                if(!licensePage)BasicText(screen.getString("eyebrow"),style=style.text(17))
                BasicText(screen.getString("title"),Modifier.semantics{heading()},style=style.text(32).copy(fontWeight=nativeUiStyle().titleWeight))
                BasicText(screen.getString("subtitle"),style=style.text(17))
            } }
            if(screen.has("wallpaperSystem"))item("wallpaper-settings"){
                NativeComponentCard("miuix",style.card,style.text,backdrop=style.backdrop) {
                    Box(Modifier.padding(16.dp)) {NativeWallpaperSettings(style.text,style.field,style.text(17),!list.isScrollInProgress,importWallpaper){send("click",screen.getString("wallpaperSystem"))}}
                }
            }
            for(n in nodes) {
                if(n.getString("kind")=="progress")stickyHeader(key=n.getString("id")) { NativeNode(n,style,::send) }
                else item(n.getString("id")) { Box(Modifier.padding(bottom=if(n.optString("kind")=="app"){9.dp}else if(n.optString("layout")=="setting"){if(n.optBoolean("last"))12.dp else 0.dp}else 12.dp)) { NativeNode(n,style) { kind,id,value ->
                    if(n.optBoolean("follow")){following=true;saveFollowing(true);followRequest++}
                    send(kind,id,value)
                } } }
            }
            for(chunk in logs)item(chunk.id){
                val density=LocalDensity.current
                val height=with(density){chunk.height.toDp()}
                Canvas(Modifier.fillMaxWidth().height(height).semantics{text=chunk.text}){
                    drawIntoCanvas{canvas->
                        val native=canvas.nativeCanvas;native.save()
                        for(row in chunk.rows){
                            if(row.divider)native.drawLine(0f,row.layout.height*.5f,size.width,row.layout.height*.5f,dividerPaint)
                            else row.layout.draw(native)
                            native.translate(0f,row.advance(chunk.gap).toFloat())
                        }
                        native.restore()
                    }
                }
            }
        }
        if(!licensePage)Column(Modifier.fillMaxWidth().padding(start=16.dp,end=16.dp,bottom=data.optDouble("bottom",20.0).coerceIn(0.0,160.0).dp,top=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if(screen.getString("hint").isNotEmpty())BasicText(screen.getString("hint"),style=style.text(12))
            val footer=screen.getJSONArray("footer").nodes()
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp,Alignment.End)) {
                for(n in footer)Box(if(footer.size==1)Modifier.width(160.dp) else Modifier.weight(1f)){NativeNode(JSONObject(n.toString()).put("centerLabel",true),style,::send)}
            }
        }
    }
    // Retain the body until the library finishes its exit animation.
    var retainedDialog by remember(screen.optString("key"),data.optString("epoch")) { mutableStateOf<JSONObject?>(null) }
    SideEffect { if(dialog!=null)retainedDialog=dialog }
    val displayedDialog=dialog?:retainedDialog
    if(displayedDialog!=null)key(displayedDialog.getString("id"),style.uiStyle) {
        val active=dialog!=null&&dialog.optString("id")==displayedDialog.optString("id")
        val dialogSend:(String,String,String)->Long={kind,id,value -> if(active)send(kind,id,value) else -1L}
        NativeComponentDialog(active,style.uiStyle,style.card,style.text,
            onDismissRequest={if(active)send("dismiss",displayedDialog.getString("id"))},
            onDismissFinished={if(dialog==null)retainedDialog=null}) {
            val items=displayedDialog.getJSONArray("nodes").nodes()
            val dialogStyle=style.copy(inDialog=true)
            Column(Modifier.fillMaxWidth().heightIn(max=(LocalConfiguration.current.screenHeightDp*.85f).dp)
                .clip(RoundedCornerShape(nativeUiStyle().dialogRadius.dp)).padding(20.dp)) {
                LazyColumn(state=rememberResumeList(data.optString("resumeSession"),data.optString("sectionRoute")+":dialog:"+items.take(3).joinToString("|"){it.optString("kind")+":"+it.optString("label")+":"+it.optString("text")}),modifier=Modifier.fillMaxWidth().weight(1f,fill=false),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    for(n in items.filterNot{it.optBoolean("dialogAction")})item(n.getString("id")){NativeNode(n,dialogStyle,dialogSend)}
                }
                for(n in items.filter{it.optBoolean("dialogAction")})key(n.getString("id")) {
                    Box(Modifier.padding(top=12.dp)){NativeNode(n,dialogStyle,dialogSend)}
                }
            }
        }
    }
}

@Composable private fun NativeNode(n:JSONObject,s:NativeDocumentStyle,send:(String,String,String)->Long) {
    val id=n.getString("id")
    val enabled=!n.optBoolean("disabled")
    when(n.getString("kind")) {
        "button","link" -> NativeDialogButton(n.getString("label")+(if(n.optBoolean("dropdown"))"  ▾" else ""),s.uiStyle,s.text,
            if(n.optBoolean("primary")||n.optBoolean("selected"))s.accent.copy(alpha=.28f) else s.field,s.text(17),enabled,
            Modifier.fillMaxWidth().heightIn(min=if(s.compact)48.dp else 52.dp).semantics{if(n.optString("description").isNotEmpty())contentDescription=n.getString("description");selected=n.optBoolean("selected")},
            centered=s.inDialog||n.optBoolean("standard")||s.compact||n.optBoolean("centerLabel"),singleLine=n.optBoolean("fitSingleLine")){send("click",id,"")}
        "heading" -> BasicText(n.getString("label"),Modifier.semantics{heading()},style=s.text(if(n.optString("level")=="H3")14 else 20,n.optString("level")!="H3").copy(color=if(n.optString("level")=="H3")s.accent else s.text))
        "text" -> BasicText(n.getString("label"),style=s.text(if(n.optBoolean("muted"))14 else 16).copy(color=if(n.optBoolean("muted"))s.muted else s.text,textAlign=if(n.optBoolean("centerLabel"))androidx.compose.ui.text.style.TextAlign.Center else androidx.compose.ui.text.style.TextAlign.Start),modifier=if(n.optBoolean("centerLabel"))Modifier.fillMaxWidth() else Modifier)
        "toggle" -> Row(Modifier.fillMaxWidth().heightIn(min=48.dp).toggleable(n.optBoolean("checked"),enabled=enabled,role=if(n.optBoolean("radio"))Role.RadioButton else Role.Checkbox,onValueChange={send("click",id,"")}),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            if(n.optBoolean("radio"))NativeChoiceMark(n.optBoolean("checked"),s.uiStyle,s.accent,enabled) else NativeCheck(n,s)
            BasicText(n.getString("label"),Modifier.weight(1f),style=s.text(17))
        }
        "range" -> {
            val min=n.getInt("min");val max=n.getInt("max")
            var value by remember(id){mutableFloatStateOf(n.getString("value").toFloat())}
            var pending by remember(id){mutableLongStateOf(0)}
            var dragging by remember(id){mutableStateOf(false)}
            var touched by remember(id){mutableStateOf(false)}
            LaunchedEffect(n.optLong("revision"),n.getString("value")) {if(!dragging&&n.optLong("revision")>=pending)value=n.getString("value").toFloat()}
            Column(Modifier.fillMaxWidth()) {
                BasicText(if(!touched&&n.optString("preserved").isNotEmpty())n.getString("preserved") else if(value.toInt()==0&&n.optString("zeroLabel").isNotEmpty())n.getString("zeroLabel") else value.toInt().toString(),style=s.text(17))
                NativeSettingSlider(s.uiStyle,n.getString("label"),value,min,max,enabled,s.accent,{value=kotlin.math.round(it);touched=true},{dragging=it}){pending=send("value",id,value.toInt().toString())}
            }
        }
        "input" -> {
            var value by remember(id){mutableStateOf(TextFieldValue(n.getString("value")))}
            var pending by remember(id){mutableLongStateOf(0)}
            LaunchedEffect(n.optLong("revision"),n.getString("value")) {
                if(n.optLong("revision")>=pending&&value.text!=n.getString("value"))value=TextFieldValue(n.getString("value"),selection=TextRange(value.selection.start.coerceIn(0,n.getString("value").length),value.selection.end.coerceIn(0,n.getString("value").length)))
            }
            Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
                if(!n.optBoolean("inGroup")&&n.getString("label").isNotBlank())BasicText(n.getString("label"),style=s.text(14))
                val change:(TextFieldValue)->Unit={v->if(v.text.length<=n.optInt("maxLength",262144).coerceIn(0,262144)||v.text.length<value.text.length){val changed=v.text!=value.text;value=v;if(changed)pending=send("value",id,v.text)}}
                val fieldSurface=nativeSurface(s.field)
                top.yukonga.miuix.kmp.basic.TextField(
                    value=value,onValueChange=change,enabled=enabled,readOnly=n.optBoolean("readOnly"),singleLine=!n.optBoolean("multi"),minLines=if(n.optBoolean("multi"))3 else 1,
                    label=n.optString("placeholder"),useLabelAsPlaceholder=true,textStyle=s.text(17),
                    colors=top.yukonga.miuix.kmp.basic.TextFieldColors(fieldSurface.color,s.muted,s.accent),cursorBrush=SolidColor(s.accent),
                    keyboardOptions=KeyboardOptions(autoCorrectEnabled=false,keyboardType=if(n.optBoolean("password"))KeyboardType.Password else KeyboardType.Text),
                    visualTransformation=if(n.optBoolean("password"))PasswordVisualTransformation() else VisualTransformation.None,
                    modifier=Modifier.fillMaxWidth().then(fieldSurface.modifier).semantics{contentDescription=n.getString("label")})

            }
        }
        "select" -> {
            var open by remember(id){mutableStateOf(false)}
            val options=n.getJSONArray("options").nodes()
            val selected=options.find{it.getString("value")==n.getString("value")}
            Box(Modifier.fillMaxWidth()) {
                NativeDialogButton((selected?.getString("label")?:"")+" ▾",s.uiStyle,s.text,s.field,s.text(17),enabled,Modifier.fillMaxWidth(),centered=false){open=true}
                NativeSelectionPopup(open,s.uiStyle,options,n.getString("value"),s.text,s.card,s.accent,{open=false}) { value ->send("value",id,value);open=false}
            }
        }
        "license" -> NativeComponentCard(s.uiStyle,s.card,s.text) { Row(Modifier.fillMaxWidth().clickable(role=Role.Button){send("license",id,"")}.padding(18.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                BasicText(n.getString("label"),style=s.text(17,true))
                BasicText(n.getString("detail"),style=s.text(14).copy(color=s.muted))
            }
            BasicText("›",Modifier.clearAndSetSemantics{},style=s.text(26).copy(color=s.muted))
        }
        }
        "group" -> NativeGroup(n,s,send)
        "app" -> NativeAppRow(n,s,send)
        "loading" -> NativeLoadingStatus(n.getString("label"),s.uiStyle,s.text,s.accent,s.text(14),s.resumed&&!s.reducedMotion,n.optString("indicator")=="orbit")
        "progress" -> NativeFlowProgress(n,s)
    }
}

// Stable numeric cells shared by packaging/compression and extraction. The
// event stream and progress animation retain their original update cadence.
private val transferProgress=Regex("^(.+?)\\s+已[處处]理[約约]([0-9]+(?:\\.[0-9]+)?\\s+\\S+)\\s+([0-9]+(?:\\.[0-9]+)?\\s+\\S+/s)$")
@Composable private fun NativeProgressLabel(label:String,s:NativeDocumentStyle) {
    val match=transferProgress.matchEntire(label.trim())
    if(match==null){BasicText(label,style=s.text().copy(fontFeatureSettings="tnum"));return}
    val phase=match.groupValues[1]
    val phaseMatch=Regex("^(.*?)([0-9]+(?:\\.[0-9]+)?%)$").matchEntire(phase)
    val numeric=s.text().copy(fontFamily=androidx.compose.ui.text.font.FontFamily.Monospace,fontFeatureSettings="tnum")
    val measurer=rememberTextMeasurer()
    val density=LocalDensity.current
    val metricWidth=with(density){measurer.measure("1023.99 GB/s",numeric).size.width.toDp()}
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){
            BasicText(phaseMatch?.groupValues?.get(1)?.trim()?:phase,Modifier.weight(1f),style=s.text())
            phaseMatch?.let{BasicText(it.groupValues[2],style=numeric)}
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val wide=maxWidth>=metricWidth*2+12.dp
            @Composable fun metric(title:String,value:String,modifier:Modifier=Modifier){
                Column(modifier,verticalArrangement=Arrangement.spacedBy(2.dp)){
                    BasicText(title,style=s.text().copy(color=s.text.copy(alpha=.75f),fontSize=s.text().fontSize*.8f))
                    BasicText(value,style=numeric,maxLines=1)
                }
            }
            if(wide)Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)){
                metric(if(label.contains("已处理"))"已处理约" else "已處理約",match.groupValues[2],Modifier.weight(1f))
                metric("速度",match.groupValues[3],Modifier.weight(1f))
            }else Column(verticalArrangement=Arrangement.spacedBy(6.dp)){
                metric(if(label.contains("已处理"))"已处理约" else "已處理約",match.groupValues[2])
                metric("速度",match.groupValues[3])
            }
        }
    }
}

@Composable private fun NativeFlowProgress(n:JSONObject,s:NativeDocumentStyle) {
    val rows=n.getJSONArray("rows").nodes()
    val animate=s.resumed&&!s.reducedMotion&&n.optBoolean("animate",true)
    val positions=rows.mapIndexed { index,r -> key(r.optString("key",index.toString())) {
                val target=r.optDouble("value").toFloat().coerceIn(0f,1f)
                val position=remember { Animatable(target) }
                val waiting=r.optBoolean("indeterminate")
                LaunchedEffect(animate,waiting,target,r.optBoolean("visible"),s.uiStyle) {
                    if(!animate||!r.optBoolean("visible"))position.snapTo(target)
                    else if(waiting)position.snapTo(0f)
                    else if(target<position.value)position.snapTo(target) // A new phase must not sweep backwards.
                    else position.animateTo(target,tween(160,easing=LinearEasing))
                }
                position
    } }
    NativeComponentCard(s.uiStyle,s.card,s.text) {
        Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            for((index,r) in rows.withIndex())key(r.optString("key",index.toString())) {
                val target=r.optDouble("value").toFloat().coerceIn(0f,1f)
                val position=positions[index]
                val waiting=r.optBoolean("indeterminate")
                if(r.getString("label").isNotEmpty())NativeProgressLabel(r.getString("label"),s)
                if(r.optBoolean("visible")) {
                    if(waiting)NativeMiuixWaitingBar(r.getString("label"),animate,s.accent,s.text.copy(alpha=.16f))
                    else NativeMiuixProgress(r.getString("label"),{position.value},s.accent,s.text.copy(alpha=.16f))
                }

            }
        }
    }
}

private fun rowShape(n:JSONObject,s:NativeDocumentStyle,normal:Int)=if(n.optString("layout")=="setting")
    RoundedCornerShape(topStart=if(n.optBoolean("first"))normal.dp else 0.dp,topEnd=if(n.optBoolean("first"))normal.dp else 0.dp,bottomStart=if(n.optBoolean("last"))normal.dp else 0.dp,bottomEnd=if(n.optBoolean("last"))normal.dp else 0.dp)
    else RoundedCornerShape(normal.dp)

@Composable internal fun NativeMiuixSwitch(checked:Boolean,accent:Color,track:Color,enabled:Boolean=true,label:String="",unset:Boolean=false,unsetLabel:String="未設定",visualEnabled:Boolean=enabled,onChange:((Boolean)->Unit)?=null) {
        top.yukonga.miuix.kmp.basic.Switch(checked=checked,onCheckedChange=onChange,enabled=enabled,modifier=Modifier.semantics{contentDescription=label;if(unset)stateDescription=unsetLabel},
            colors=top.yukonga.miuix.kmp.basic.SwitchColors(Color.White,Color.White,Color.White.copy(alpha=if(visualEnabled)1f else .4f),Color.White.copy(alpha=if(visualEnabled)1f else .4f),accent,track,if(visualEnabled)accent else accent.copy(alpha=.4f),if(visualEnabled)track else track.copy(alpha=.4f)))
}

@Composable private fun NativeCheck(n:JSONObject,s:NativeDocumentStyle) {
    val checked=n.optBoolean("checked");val mixed=n.optBoolean("indeterminate")
        top.yukonga.miuix.kmp.basic.Checkbox(
            state=if(mixed)androidx.compose.ui.state.ToggleableState.Indeterminate else if(checked)androidx.compose.ui.state.ToggleableState.On else androidx.compose.ui.state.ToggleableState.Off,
            onClick=null,enabled=!n.optBoolean("disabled"),modifier=Modifier.drawBehind { if(!checked&&!mixed)drawCircle(s.muted.copy(alpha=if(n.optBoolean("disabled")) .4f else 1f),radius=(size.minDimension/2-1.dp.toPx()).coerceAtLeast(0f),style=Stroke(2.dp.toPx())) }.clearAndSetSemantics{},
            colors=top.yukonga.miuix.kmp.basic.CheckboxColors(
                checkedForegroundColor=if(s.accent.luminance()>.45f)Color.Black else Color.White,
                uncheckedForegroundColor=s.muted,
                disabledCheckedForegroundColor=(if(s.accent.luminance()>.45f)Color.Black else Color.White).copy(alpha=.5f),
                disabledUncheckedForegroundColor=s.muted.copy(alpha=.4f),
                checkedBackgroundColor=s.accent,uncheckedBackgroundColor=Color.Transparent,
                disabledCheckedBackgroundColor=s.accent.copy(alpha=.4f),disabledUncheckedBackgroundColor=Color.Transparent))
}

internal object NativeIconCache {
    // Content keys prevent cross-user/package collisions and naturally invalidate changed icons.
    private val images=object:android.util.LruCache<String,ImageBitmap>(32*1024*1024){
        override fun sizeOf(key:String,value:ImageBitmap)=key.length*2+value.width*value.height*4
    }
    fun get(icon:String):ImageBitmap?=images.get(icon)
    fun decode(icon:String):ImageBitmap? {
        if(icon.isEmpty()||icon.length>131072)return null
        images.get(icon)?.let{return it}
        return try{
            val bytes=Base64.decode(icon,Base64.DEFAULT)
            val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
            BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
            if(bounds.outWidth !in 1..256||bounds.outHeight !in 1..256)null
            else BitmapFactory.decodeByteArray(bytes,0,bytes.size)?.asImageBitmap()?.also{images.put(icon,it)}
        }catch(_:Exception){null}
    }
}

@Composable private fun NativeAppRow(n:JSONObject,s:NativeDocumentStyle,send:(String,String,String)->Long) {
    NativeComponentCard(s.uiStyle,s.card,s.text) { Row(Modifier.fillMaxWidth().heightIn(min=88.dp).padding(horizontal=14.dp,vertical=16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        val icon=n.optString("icon")
        val removed=n.optBoolean("removed")
        val cached=NativeIconCache.get(icon)
        val bitmap by key(icon){produceState<ImageBitmap?>(cached,icon) {
            if(value==null)value=withContext(Dispatchers.Default){NativeIconCache.decode(icon)}
        }}
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(13.dp)).background(if(bitmap==null)s.field else Color.Transparent),contentAlignment=Alignment.Center) {
            if(bitmap!=null)Image(bitmap!!,null,Modifier.fillMaxSize())
            else Canvas(Modifier.size(28.dp)){drawRoundRect(if(removed)s.muted else s.accent,Offset(size.width*.22f,size.height*.07f),Size(size.width*.56f,size.height*.86f),CornerRadius(2.dp.toPx()),style=Stroke(2.dp.toPx()));drawCircle(if(removed)s.muted else s.accent,1.5.dp.toPx(),Offset(size.width*.5f,size.height*.8f))}
        }
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
            BasicText(n.getString("label"),style=s.text(17,true),maxLines=2,overflow=TextOverflow.Ellipsis)
            if(n.optString("badge").isNotEmpty())BasicText(n.getString("badge"),style=s.text(11,true).copy(color=if(removed)s.muted else if(n.getString("badge").contains("Xposed"))Color(0xff277af7) else s.accent))
            if(n.getString("detail").isNotEmpty())BasicText(n.getString("detail"),style=s.text(14).copy(color=s.muted),maxLines=1,overflow=TextOverflow.Ellipsis)
            for(c in n.getJSONArray("children").nodes().filter{it.optString("kind")!="toggle"||it.optBoolean("inlineControl")})key(c.getString("id")) {
                NativeNode(c,s.copy(compact=true),send)
            }
        }
        Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            for(c in n.getJSONArray("children").nodes().filter{it.optString("kind")=="toggle"&&!it.optBoolean("inlineControl")})key(c.getString("id")) {
                Column(Modifier.widthIn(min=42.dp).heightIn(min=52.dp).toggleable(c.optBoolean("checked"),enabled=!c.optBoolean("disabled"),role=Role.Checkbox,onValueChange={send("click",c.getString("id"),"")}).semantics{contentDescription=c.getString("label")},horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(5.dp,Alignment.CenterVertically)) {
                    NativeCheck(c,s)
                    BasicText(c.optString("caption").ifEmpty{c.getString("label").substringBefore('：')},Modifier.clearAndSetSemantics{},style=s.text(11).copy(color=if(c.optBoolean("checked"))s.accent else s.muted))
                }
            }
        }
    }
}
}

@Composable private fun NativeGroup(n:JSONObject,s:NativeDocumentStyle,send:(String,String,String)->Long) {
    val children=n.getJSONArray("children").nodes()
    when(n.optString("layout")) {
        "edit-row" -> Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            for(c in children)key(c.getString("id")){Box(if(c.optString("kind")=="input")Modifier.weight(1f) else Modifier.width(48.dp)){NativeNode(c,s.copy(compact=true),send)}}
        }
        "settings-section" -> {
            val content:@Composable ColumnScope.()->Unit={for(c in children)key(c.getString("id")){NativeNode(c,s.copy(grouped=true),send)}}
            NativeComponentCard(s.uiStyle,s.card,s.text,content=content)
        }
        "setting" -> {
            val wide=children.filter{it.optString("kind") in setOf("input","range")}
            val right=children.filter{it.optString("kind") !in setOf("input","range")}
            val toggleOnly=right.size==1&&right[0].optString("layout")=="toggle"
            val rowSurface=nativeSurface(s.card,rowShape(n,s,18))
            Column(Modifier.fillMaxWidth().then(if(s.grouped)Modifier else rowSurface.modifier.background(rowSurface.color,rowShape(n,s,18))).padding(start=16.dp,end=16.dp,top=if(n.optBoolean("first"))16.dp else 8.dp,bottom=if(n.optBoolean("last"))16.dp else 8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                    Column(Modifier.weight(if(toggleOnly)1f else .65f),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                        BasicText(n.getString("label"),style=s.text(17))
                        BasicText(n.getString("detail"),style=s.text(14).copy(color=s.muted))
                    }
                    if(right.isNotEmpty())Column(if(toggleOnly)Modifier.wrapContentWidth(Alignment.End) else Modifier.weight(.35f),horizontalAlignment=Alignment.End,verticalArrangement=Arrangement.spacedBy(6.dp)){for(c in right)key(c.getString("id")){NativeNode(c,s.copy(compact=true),send)}}
                }
                for(c in wide)key(c.getString("id")){NativeNode(c,s,send)}
            }
        }
        "toggle" -> FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
            for(c in children) {
                if(c.getString("kind")=="toggle")Row(Modifier.heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)) {if(c.optBoolean("indeterminate"))BasicText(s.unset,style=s.text(11).copy(color=s.muted));NativeMiuixSwitch(c.optBoolean("checked"),s.accent,s.line,!c.optBoolean("disabled"),label=c.getString("label"),unset=c.optBoolean("indeterminate"),unsetLabel=s.unset){value->if(value!=c.optBoolean("checked"))send("click",c.getString("id"),"")}}
                else Box(Modifier.widthIn(max=64.dp)){NativeNode(c,s.copy(compact=true),send)}
            }
        }
        "log-actions" -> BoxWithConstraints(Modifier.fillMaxWidth()) {
            val columns=if(maxWidth<240.dp)1 else if(maxWidth>=600.dp)4 else 2
            Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                for(row in children.chunked(columns))Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    for(c in row)key(c.getString("id")){Box(Modifier.weight(1f)){NativeNode(c,s.copy(compact=true),send)}}
                    repeat(columns-row.size){Spacer(Modifier.weight(1f))}
                }
            }
        }
        "row","toolbar" -> Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            for(c in children)key(c.getString("id")){Box(Modifier.weight(if(n.optString("layout")=="toolbar"&&(c.optString("kind")=="select"||c.optBoolean("dropdown")))2.6f else 1f)){NativeNode(c,s.copy(compact=true),send)}}
        }
        "controls" -> NativeComponentCard(s.uiStyle,s.card,s.text,backdrop=s.backdrop) { Column(Modifier.fillMaxWidth().padding(14.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {for(c in children)key(c.getString("id")){NativeNode(c,s.copy(compact=true),send)}} }
        else -> Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(10.dp)){for(c in children)key(c.getString("id")){NativeNode(c,s,send)}}
    }
}
