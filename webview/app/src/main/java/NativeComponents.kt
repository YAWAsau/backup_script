package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.Canvas
import top.yukonga.miuix.kmp.squircle.squircleBorder
import androidx.compose.foundation.border
import androidx.compose.ui.graphics.luminance
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.DpSize
import org.json.JSONObject
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.catalog.components.GlassMaterial
import androidx.compose.foundation.shape.RoundedCornerShape

internal val LocalNativeBackdrop=staticCompositionLocalOf<Backdrop?>{null}
internal val LocalNativeSurfaceBacked=staticCompositionLocalOf{false}
internal data class NativeSurface(val modifier:Modifier,val color:Color,val frosted:Boolean)
@Composable internal fun nativeSurface(color:Color,shape:androidx.compose.ui.graphics.Shape?=null,cornerRadius:androidx.compose.ui.unit.Dp=24.dp,showOutline:Boolean=true,isolated:Boolean=false,backdrop:Backdrop?=LocalNativeBackdrop.current):NativeSurface {
    val frosted=backdrop!=null&&GlassMaterial.LocalBlurEnabled.current&&android.os.Build.VERSION.SDK_INT>=31
    if(!frosted)return NativeSurface(Modifier,color,false)
    // Child controls share the parent's blur; popups own a separate window surface.
    val edge=(if(color.luminance()>.4f)Color.Black else Color.White).copy(alpha=if(isolated).26f else .20f)
    val actualShape=shape?:RoundedCornerShape(cornerRadius)
    val outline=if(!showOutline)Modifier else if(shape!=null)Modifier.border(1.dp,edge,shape) else Modifier.squircleBorder(1.dp,edge,cornerRadius)
    if(!isolated&&LocalNativeSurfaceBacked.current)return NativeSurface(outline,color.copy(alpha=color.alpha*.85f),true)
    return NativeSurface(Modifier.drawBackdrop(backdrop=backdrop!!,shape={actualShape},highlight=null,shadow=null,
        effects={blur(12.dp.toPx())},onDrawSurface={drawRect(color.copy(alpha=color.alpha*(if(isolated).78f else .68f)))}).then(outline),Color.Transparent,true)
}

/** Call inside the trigger's Box: Miuix measures that native anchor, never WebView coordinates. */
@Composable internal fun NativeSelectionPopup(show:Boolean,style:String,options:List<JSONObject>,value:String,foreground:Color,background:Color,accent:Color,onDismiss:()->Unit,onSelect:(String)->Unit) {
    val surface=nativeSurface(background,isolated=true)
    top.yukonga.miuix.kmp.theme.MiuixTheme(colors=top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme.copy(
        surfaceContainer=surface.color,onBackground=foreground,primary=accent)) {
      top.yukonga.miuix.kmp.window.WindowListPopup(show=show,onDismissRequest=onDismiss,
        alignment=top.yukonga.miuix.kmp.basic.PopupPositionProvider.Align.End) {
        Box(surface.modifier) { top.yukonga.miuix.kmp.basic.ListPopupColumn {
            options.forEachIndexed { index,o -> key(o.getString("value")) {
                top.yukonga.miuix.kmp.basic.DropdownImpl(text=o.getString("label"),optionSize=options.size,
                    isSelected=o.getString("value")==value,index=index,enabled=!o.optBoolean("disabled"),
                    dropdownColors=top.yukonga.miuix.kmp.basic.DropdownDefaults.dropdownColors(
                        contentColor=foreground,summaryColor=foreground,containerColor=if(surface.frosted)Color.Transparent else background,
                        selectedContentColor=accent,selectedSummaryColor=accent,selectedContainerColor=if(surface.frosted)accent.copy(alpha=.15f) else background,selectedIndicatorColor=accent)) {
                    if(show)onSelect(o.getString("value"))
                }
            } }
        } }
      }
    }
}

/** Standard Miuix actions share the global surface setting and their parent blur. */
@Composable internal fun NativeDialogButton(label:String,style:String,foreground:Color,background:Color,textStyle:TextStyle,enabled:Boolean=true,modifier:Modifier=Modifier,centered:Boolean=true,singleLine:Boolean=false,visualEnabled:Boolean=enabled,onClick:()->Unit) {
    val surface=nativeSurface(background,cornerRadius=16.dp,showOutline=false)
    val ink=foreground.copy(alpha=if(visualEnabled)1f else .4f)
    top.yukonga.miuix.kmp.basic.Button(onClick=onClick,enabled=enabled,indication=if(enabled)androidx.compose.foundation.LocalIndication.current else null,
        modifier=modifier.then(surface.modifier).heightIn(min=48.dp),minHeight=48.dp,minWidth=48.dp,insideMargin=PaddingValues(12.dp,8.dp),
        colors=top.yukonga.miuix.kmp.basic.ButtonColors(surface.color,if(visualEnabled)surface.color else surface.color.copy(alpha=surface.color.alpha*.4f),foreground,ink)) {
        BasicText(label,Modifier.fillMaxWidth(),maxLines=if(singleLine)1 else Int.MAX_VALUE,softWrap=!singleLine,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis,style=textStyle.copy(color=ink,textAlign=if(centered)TextAlign.Center else TextAlign.Start))
    }
}

/** A single renderer choice shared by editors, menus and confirmation dialogs. */
@Composable internal fun NativeComponentDialog(show:Boolean,style:String,background:Color,text:Color,onDismissRequest:()->Unit,onDismissFinished:()->Unit,content:@Composable ()->Unit) {
    var requested by remember { mutableStateOf(false) }
    LaunchedEffect(show,requested){
        if(!show)requested=false
        else if(requested){kotlinx.coroutines.delay(400);requested=false}
    }
    val dismiss={if(show&&!requested){requested=true;onDismissRequest()}}
    val surface=nativeSurface(background,cornerRadius=28.dp,isolated=true)
    top.yukonga.miuix.kmp.window.WindowDialog(
        show=show,onDismissRequest=dismiss,onDismissFinished=onDismissFinished,
        backgroundColor=surface.color,titleColor=text,summaryColor=text.copy(alpha=.65f),
        insideMargin=DpSize(0.dp,0.dp),largeScreen=true,cornerRadius=28.dp){Box(surface.modifier){CompositionLocalProvider(LocalNativeSurfaceBacked provides surface.frosted){content()}}}
}

/** Parent owns the only click action and semantics, so a tap cannot toggle twice. */
@Composable internal fun NativeChoiceMark(selected:Boolean,style:String,accent:Color,enabled:Boolean=true) {
    top.yukonga.miuix.kmp.basic.RadioButton(selected=selected,onClick=null,enabled=enabled,
        colors=top.yukonga.miuix.kmp.basic.RadioButtonColors(accent,accent.copy(alpha=.4f)),modifier=Modifier.clearAndSetSemantics{})
}

@Composable internal fun NativeMiuixSlider(label:String,value:Float,enabled:Boolean,visualEnabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
 NativeMiuixRangeSlider(label,value,0,100,enabled,visualEnabled,tint,onValue,onDragging,onCommit)
}
@Composable internal fun NativeMiuixRangeSlider(label:String,value:Float,min:Int,max:Int,enabled:Boolean,visualEnabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
    val update by rememberUpdatedState(onValue)
    val drag by rememberUpdatedState(onDragging)
    val commit by rememberUpdatedState(onCommit)
    DisposableEffect(Unit){onDispose{drag(false)}}
    Box(Modifier.fillMaxWidth().height(48.dp).clearAndSetSemantics {
        contentDescription=label
        progressBarRangeInfo=ProgressBarRangeInfo(value,min.toFloat()..max.toFloat(),max-min-1)
        if(!enabled)disabled()
        setProgress { if(!enabled)false else {update(it.coerceIn(min.toFloat(),max.toFloat()));commit();true} }
    },contentAlignment=androidx.compose.ui.Alignment.Center) {
        top.yukonga.miuix.kmp.basic.Slider(value=value,valueRange=min.toFloat()..max.toFloat(),enabled=enabled,height=28.dp,
            onValueChange={if(enabled)update(it)},onValueChangeFinished={drag(false);if(enabled)commit()},
            colors=top.yukonga.miuix.kmp.basic.SliderColors(tint,tint.copy(alpha=if(visualEnabled)1f else .4f),tint.copy(alpha=.18f),tint.copy(alpha=if(visualEnabled).18f else .08f),Color.White,Color.White.copy(alpha=if(visualEnabled)1f else .4f),tint,Color.White),
            modifier=Modifier.fillMaxWidth().height(28.dp).pointerInput(enabled){if(enabled)awaitEachGesture {
                awaitFirstDown(requireUnconsumed=false,pass=PointerEventPass.Initial)
                drag(true)
                try { do {val event=awaitPointerEvent(PointerEventPass.Final)} while(event.changes.any{it.pressed}) }
                finally {drag(false)}
            }})
    }
}

/** Card shell changes style while the caller retains stable row keys and layout. */
@Composable internal fun NativeComponentCard(style:String,color:Color,text:Color,modifier:Modifier=Modifier,backdrop:Backdrop?=LocalNativeBackdrop.current,content:@Composable ColumnScope.()->Unit) {
    val surface=nativeSurface(color,backdrop=backdrop)
    top.yukonga.miuix.kmp.basic.Card(modifier=modifier.fillMaxWidth().then(surface.modifier),cornerRadius=24.dp,
        colors=top.yukonga.miuix.kmp.basic.CardColors(surface.color,text)) {
        CompositionLocalProvider(LocalNativeSurfaceBacked provides surface.frosted){content()}
    }
}

@Composable internal fun NativeMiuixProgress(label:String,progress:()->Float,accent:Color,track:Color) {
    val value=progress().coerceIn(0f,1f)
    top.yukonga.miuix.kmp.basic.LinearProgressIndicator(progress=value,height=8.dp,
        colors=top.yukonga.miuix.kmp.basic.ProgressIndicatorColors(if(value==0f)track else accent,accent.copy(alpha=.4f),track),
        modifier=Modifier.fillMaxWidth().semantics{contentDescription=label})
}

/** Unknown duration is never presented as a percentage; stop motion off-screen. */
@Composable internal fun NativeMiuixWaitingBar(label:String,animate:Boolean,accent:Color,track:Color) {
    val semantics=Modifier.fillMaxWidth().semantics{contentDescription=label;progressBarRangeInfo=ProgressBarRangeInfo.Indeterminate}
    if(animate)top.yukonga.miuix.kmp.basic.LinearProgressIndicator(progress=null,height=8.dp,
        colors=top.yukonga.miuix.kmp.basic.ProgressIndicatorColors(accent,accent.copy(alpha=.4f),track),modifier=semantics)
    else Canvas(semantics.height(8.dp)) {
        drawRoundRect(track,cornerRadius=androidx.compose.ui.geometry.CornerRadius(size.height/2))
        drawRoundRect(accent, size=androidx.compose.ui.geometry.Size(size.width*.25f,size.height),cornerRadius=androidx.compose.ui.geometry.CornerRadius(size.height/2))
    }
}

@Composable internal fun NativeLoadingStatus(label:String,style:String,foreground:Color,accent:Color,textStyle:TextStyle,animate:Boolean,orbit:Boolean=false) {
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        val decoration=Modifier.clearAndSetSemantics{}
        if(animate&&orbit)top.yukonga.miuix.kmp.basic.InfiniteProgressIndicator(color=accent,size=28.dp,modifier=decoration)
        else if(animate)top.yukonga.miuix.kmp.basic.CircularProgressIndicator(progress=null,size=28.dp,
            colors=top.yukonga.miuix.kmp.basic.ProgressIndicatorColors(accent,accent.copy(alpha=.4f),accent.copy(alpha=.16f)),modifier=decoration)
        else Canvas(decoration.size(28.dp)){drawCircle(accent,style=Stroke(2.dp.toPx()))}
        BasicText(label,Modifier.weight(1f),style=textStyle.copy(color=foreground))
    }
}
