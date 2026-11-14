package io.github.yawasau.speedbackup.webview

import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/** Tweak-Alpha style full-screen browser; directory access remains in Rust. */
@Composable
fun NativePathPicker(state: JSONObject, foreground: Color, background: Color, accent: Color, uiStyle:String, reducedMotion:Boolean=false, resumed:Boolean=true, onBack:(()->Unit)?=null, delegateRootBack:Boolean=false, send: (String)->Unit) {
    val session=state.getString("session")
    var manageSelected by remember(session) { mutableStateOf(false) }
    val removals=remember(session) { mutableStateListOf<String>() }
    val languageContext=androidx.compose.ui.platform.LocalContext.current
    fun label(text:String)=NativeLanguage.text(languageContext,text)
    fun action(kind:String,path:String="")=send("picker:"+JSONObject().put("session",session).put("kind",kind).put("path",path).toString())
    val selected=state.getJSONArray("selected").let { a -> (0 until a.length()).map{a.getString(it)}.toSet() }
    val entries=state.getJSONArray("entries").let { a -> (0 until a.length()).map{a.getJSONObject(it)} }.filter { state.optBoolean("files") || it.optBoolean("directory") }.distinctBy{it.getString("path")}
    val loading=state.optBoolean("loading")
    val files=state.optBoolean("files")
    val directory=PickerDirectory(state.optString("path"),state.optString("parent"),entries,!state.isNull("next"))
    val hasParent=directory.parent.isNotEmpty()&&directory.parent!=directory.path
    // At filesystem root the enclosing document owns the return to the editor.
    // Do not let either nested host consume it with a current-page-only animation.
    val ownsDirectoryBack=hasParent||(onBack!=null&&!delegateRootBack)
    var footerHeightPx by remember{mutableIntStateOf(0)}
    val footerPadding=maxOf(100.dp,with(LocalDensity.current){footerHeightPx.toDp()}+8.dp)
    val loadingHeight=maxOf(36f,24f*LocalDensity.current.fontScale).dp
    val card=androidx.compose.ui.graphics.lerp(background,foreground,.07f)
    // Consume only otherwise-unhandled taps. Consuming every MOVE here cancels
    // LazyColumn's touch-slop detection before it can begin scrolling.
    Box(Modifier.fillMaxSize().background(background).clickable(interactionSource=null,indication=null){}) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars)) {
            Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically) {
                NativeBackButton(label("取消路徑選擇"),foreground){action("cancel")}
                Column(Modifier.weight(1f).padding(start=8.dp)) {
                    BasicText(label(state.optString("title")),style=nativeTextStyle(color=foreground,fontSize=20.sp,fontWeight=FontWeight.Medium))
                    BasicText(state.optString("path"),style=nativeTextStyle(color=foreground.copy(alpha=.65f),fontSize=14.sp),maxLines=2,overflow=TextOverflow.Ellipsis)
                }
            }
            Row(Modifier.padding(horizontal=16.dp).height(IntrinsicSize.Min),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                listOf(label("內部儲存空間") to "/sdcard",label("儲存裝置") to "/storage").forEach { (label,path) ->
                    NativeDialogButton(label,uiStyle,foreground,card,nativeTextStyle(fontSize=14.sp),!loading,Modifier.weight(1f).fillMaxHeight()){manageSelected=false;removals.clear();action("open",path)}
                }
            }
            // Keep the viewport fixed while the next listing loads.
            Box(Modifier.fillMaxWidth().height(loadingHeight).padding(horizontal=16.dp),contentAlignment=Alignment.CenterStart){
                if(loading)NativeLoadingStatus(label("讀取資料夾…"),uiStyle,foreground.copy(alpha=.65f),accent,nativeTextStyle(fontSize=14.sp),resumed&&!reducedMotion)
            }
            if(state.optString("error").isNotEmpty()) BasicText(label("無法讀取：")+state.optString("error"),Modifier.padding(16.dp),style=nativeTextStyle(color=if(LocalNativeMaterial.current)androidx.compose.material3.MaterialTheme.colorScheme.onSurface else foreground,fontSize=14.sp))
            NativeDialogButton(label(if(manageSelected) "返回資料夾" else "管理已選路徑")+" (${selected.size})",uiStyle,accent,card,nativeTextStyle(fontSize=16.sp),modifier=Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=8.dp),centered=false,navigation=true){manageSelected=!manageSelected;removals.clear()}
            NativeNavHost(if(manageSelected)"selected" else "directory",manageSelected,reducedMotion,
                modifier=Modifier.weight(1f).fillMaxWidth().clipToBounds(),
                backRoute=if(manageSelected)"directory" else "",root=!manageSelected,
                boundaryBack=manageSelected||ownsDirectoryBack,
                onBack={if(manageSelected){manageSelected=false;removals.clear()}else if(onBack!=null)onBack()else send("back")}) { showManaged ->
            if(showManaged) {
                LazyColumn(state=rememberResumeList(state.optString("resumeSession"),"picker:selected:"+state.optString("title")),modifier=Modifier.fillMaxSize().background(background),contentPadding=PaddingValues(start=16.dp,end=16.dp,top=8.dp,bottom=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    items(selected.toList(),key={it}) { path ->
                        fun toggle(){if(path in removals)removals.remove(path)else removals.add(path)}
                        PickerRow(path.substringAfterLast('/').ifEmpty{path},path,!files,path in removals,manageSelected,foreground,card,accent,uiStyle,label("選取"),label("開啟資料夾"),{toggle()},{toggle()},showArrow=false)
                    }
                    item {
                        val removeSelected={
                            send("picker:"+JSONObject().put("session",session).put("kind","remove").put("revision",state.optInt("selectionRevision")).put("indices",org.json.JSONArray(selected.toList().mapIndexedNotNull { index,path -> if(path in removals)index else null })).toString());removals.clear()
                        }
                        NativeDialogButton(label("移除勾選路徑")+" (${removals.size})",uiStyle,accent,card,nativeTextStyle(fontSize=16.sp),manageSelected&&removals.isNotEmpty(),Modifier.fillMaxWidth(),onClick=removeSelected)
                    }
                    item { Spacer(Modifier.height(footerPadding)) }
                }
            } else NativeNavHost(directory.path,directory,reducedMotion,Modifier.fillMaxSize().clipToBounds(),
                backRoute=directory.parent.takeIf{it!=directory.path}.orEmpty(),previewBack=!loading,
                root=!hasParent,boundaryBack=ownsDirectoryBack,
                onBack={if(onBack!=null)onBack()else send("back")}) { listing ->
                // Outgoing rows retain their own listing, but cannot dispatch stale actions.
                val active=!manageSelected&&!loading&&listing.path==directory.path
                LazyColumn(state=rememberResumeList(state.optString("resumeSession"),"picker:path:"+listing.path,!loading),modifier=Modifier.fillMaxSize().background(background),contentPadding=PaddingValues(start=16.dp,end=16.dp,top=8.dp,bottom=footerPadding),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    if(!files&&listing.path.isNotEmpty()) item {
                        PickerRow(label("選擇目前資料夾"),listing.path,true,selected.contains(listing.path),active,foreground,card,accent,uiStyle,label("選取"),label("開啟資料夾"),{action("select",listing.path)},{action("select",listing.path)},showArrow=false)
                    }
                    if(listing.parent.isNotEmpty()&&listing.parent!=listing.path) item {
                        PickerRow(label("上一層"),listing.parent,true,null,active,foreground,card,accent,uiStyle,label("選取"),label("開啟資料夾"),{action("open",listing.parent)},{},returnArrow=true)
                    }
                    items(listing.entries,key={it.getString("path")}) { entry ->
                        val path=entry.getString("path");val isDirectory=entry.optBoolean("directory")
                        PickerRow(entry.getString("name"),"",isDirectory,if(isDirectory!=files)selected.contains(path) else null,active&&(isDirectory||files),foreground,card,accent,uiStyle,label("選取"),label("開啟資料夾"),
                            {if(isDirectory)action("open",path)else if(files)action("select",path)},{action("select",path)})
                    }
                    if(listing.hasMore) item {NativeDialogButton(label("載入更多"),uiStyle,accent,card,nativeTextStyle(fontSize=16.sp),active,Modifier.fillMaxWidth()){action("more")} }
                    if(listing.entries.isEmpty()&&!loading) item {BasicText(label("這個資料夾沒有符合的項目"),Modifier.padding(20.dp),style=nativeTextStyle(color=foreground.copy(alpha=.65f),fontSize=14.sp))}
                }
            }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().then(if(LocalNativeMaterial.current)Modifier.background(androidx.compose.material3.MaterialTheme.colorScheme.surfaceContainer) else Modifier).onSizeChanged{footerHeightPx=it.height}.windowInsetsPadding(WindowInsets.navigationBars).padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            BasicText(state.optString("selectionHint").ifEmpty{label("已選")+" ${selected.size} "+label("個；確認後填入，儲存設定才生效")},style=nativeTextStyle(color=if(LocalNativeMaterial.current)androidx.compose.material3.MaterialTheme.colorScheme.onSurface else foreground,fontSize=14.sp))
            NativeDialogButton(label("確認選擇"),uiStyle,foreground,accent.copy(alpha=.28f),nativeTextStyle(fontSize=17.sp,fontWeight=FontWeight.Medium),!loading,Modifier.align(Alignment.End).width(160.dp),primary=LocalNativeMaterial.current){action("confirm")}

        }
    }
}

@Composable
private fun PickerRow(name:String,path:String,directory:Boolean,checked:Boolean?,enabled:Boolean,foreground:Color,card:Color,accent:Color,uiStyle:String,selectLabel:String,openLabel:String,open:()->Unit,toggle:()->Unit,showArrow:Boolean=directory,returnArrow:Boolean=false) {
    NativeComponentCard(uiStyle,card,foreground) { Row(Modifier.fillMaxWidth().heightIn(min=56.dp),verticalAlignment=Alignment.CenterVertically) {
        CompositionLocalProvider(LocalNativeSettingIcon provides if(directory)"Output_path" else "logs") {
        if(LocalNativeMaterial.current)androidx.compose.material3.ListItem(
            content={androidx.compose.material3.Text(name,style=androidx.compose.material3.MaterialTheme.typography.bodyLarge)},
            supportingContent=if(path.isEmpty())null else {{androidx.compose.material3.Text(path,style=androidx.compose.material3.MaterialTheme.typography.bodyMedium)}},
            leadingContent=nativeSettingIconSlot(enabled),
            verticalAlignment=Alignment.CenterVertically,
            colors=androidx.compose.material3.ListItemDefaults.colors(containerColor=Color.Transparent,
                contentColor=androidx.compose.material3.MaterialTheme.colorScheme.onSurface.copy(alpha=if(enabled)1f else .38f),
                supportingContentColor=androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=if(enabled)1f else .38f)),
            modifier=Modifier.weight(1f).clickable(enabled=enabled,onClick=if(checked!=null)toggle else open))
        else top.yukonga.miuix.kmp.basic.BasicComponent(modifier=Modifier.weight(1f),title=name,summary=path.ifEmpty{null},
            startAction=nativeSettingIconSlot(enabled),
            titleColor=top.yukonga.miuix.kmp.basic.BasicComponentColors(foreground,foreground.copy(alpha=.4f)),
            summaryColor=top.yukonga.miuix.kmp.basic.BasicComponentColors(foreground.copy(alpha=.65f),foreground.copy(alpha=.3f)),
            enabled=enabled,role=Role.Button,onClick=if(checked!=null)toggle else open)
        }
        if(checked!=null)Box(Modifier.toggleable(value=checked,enabled=enabled,role=Role.Checkbox,onValueChange={toggle()}).semantics{contentDescription="$selectLabel $name"}.sizeIn(minWidth=48.dp,minHeight=48.dp).padding(12.dp),contentAlignment=Alignment.Center) {
            if(LocalNativeMaterial.current)androidx.compose.material3.Checkbox(checked=checked,onCheckedChange=null,enabled=enabled,modifier=Modifier.clearAndSetSemantics{})
            else top.yukonga.miuix.kmp.basic.Checkbox(
            state=if(checked)androidx.compose.ui.state.ToggleableState.On else androidx.compose.ui.state.ToggleableState.Off,
            onClick=null,enabled=enabled,modifier=Modifier.drawBehind { if(!checked)drawCircle(foreground.copy(alpha=if(enabled) .6f else .3f),radius=(size.minDimension/2-1.dp.toPx()).coerceAtLeast(0f),style=Stroke(2.dp.toPx())) }.clearAndSetSemantics{},
            colors=top.yukonga.miuix.kmp.basic.CheckboxColors(Color.White,foreground.copy(alpha=.5f),Color.White.copy(alpha=.4f),foreground.copy(alpha=.2f),accent,Color.Transparent,accent.copy(alpha=.4f),Color.Transparent))
        }
        if(showArrow)NativeDialogButton("",uiStyle,foreground,Color.Transparent,nativeTextStyle(fontSize=24.sp),enabled,Modifier.width(48.dp).semantics{contentDescription="$openLabel $name"},navigation=true,returnArrow=returnArrow,onClick=open)
    }
}

}

private data class PickerDirectory(val path:String,val parent:String,val entries:List<JSONObject>,val hasMore:Boolean)
