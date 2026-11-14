package io.github.yawasau.speedbackup.webview

import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.basic.ArrowUpDown
import top.yukonga.miuix.kmp.icon.basic.ArrowRight
import top.yukonga.miuix.kmp.icon.basic.Close
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.Canvas
import top.yukonga.miuix.kmp.squircle.squircleBorder
import top.yukonga.miuix.kmp.squircle.addSquircleRect
import androidx.compose.ui.graphics.graphicsLayer
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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.DpSize
import org.json.JSONObject
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.catalog.components.GlassMaterial
import androidx.compose.foundation.shape.RoundedCornerShape

internal val LocalNativeUiScale=staticCompositionLocalOf { 1f }
internal val LocalNativeBackdrop=staticCompositionLocalOf<Backdrop?>{null}
internal val LocalNativeSurfaceBacked=staticCompositionLocalOf{false}
internal data class NativeSurface(val modifier:Modifier,val color:Color,val frosted:Boolean)
@Composable internal fun nativeSurface(color:Color,shape:androidx.compose.ui.graphics.Shape?=null,cornerRadius:androidx.compose.ui.unit.Dp=24.dp,showOutline:Boolean=true,isolated:Boolean=false,backdrop:Backdrop?=LocalNativeBackdrop.current):NativeSurface {
    if(LocalNativeMaterial.current)return NativeSurface(Modifier,color,false)
    val blurStrength=GlassMaterial.LocalControls.current.blurStrength
    val frosted=backdrop!=null&&GlassMaterial.LocalBlurEnabled.current&&android.os.Build.VERSION.SDK_INT>=31
    if(!frosted)return NativeSurface(Modifier,color,false)
    // Child controls share the parent's blur; popups own a separate window surface.
    val edge=(if(color.luminance()>.4f)Color.Black else Color.White).copy(alpha=if(isolated).26f else .20f)
    val squircle=top.yukonga.miuix.kmp.squircle.isSquircleEnabled()
    val componentShape=remember(cornerRadius,squircle){object:androidx.compose.ui.graphics.Shape{
        private var cachedSize=androidx.compose.ui.geometry.Size.Unspecified
        private var cachedDensity=0f
        private var cachedOutline:androidx.compose.ui.graphics.Outline?=null
        override fun createOutline(size:androidx.compose.ui.geometry.Size,layoutDirection:androidx.compose.ui.unit.LayoutDirection,density:androidx.compose.ui.unit.Density):androidx.compose.ui.graphics.Outline {
            if(size==cachedSize&&density.density==cachedDensity)cachedOutline?.let{return it}
            val path=androidx.compose.ui.graphics.Path().apply{addSquircleRect(size.width,size.height,with(density){cornerRadius.toPx()},squircleEnabled=squircle)}
            return androidx.compose.ui.graphics.Outline.Generic(path).also{cachedSize=size;cachedDensity=density.density;cachedOutline=it}
        }
    }}
    val actualShape=shape?:componentShape
    val outline=if(!showOutline)Modifier else if(shape!=null)Modifier.border(1.dp,edge,shape) else Modifier.squircleBorder(1.dp,edge,cornerRadius)
    if(!isolated&&LocalNativeSurfaceBacked.current)return NativeSurface(outline,color.copy(alpha=color.alpha*.85f),true)
    return NativeSurface(Modifier.drawBackdrop(backdrop=backdrop!!,shape={actualShape},highlight=null,shadow=null,
        effects={blur((36f*blurStrength/100f).dp.toPx())},onDrawSurface={drawRect(color.copy(alpha=color.alpha*(if(isolated).78f else .68f)))}).then(outline),Color.Transparent,true)
}

/** Call inside the trigger's Box: Miuix measures that native anchor, never WebView coordinates. */
@Composable internal fun NativeSelectionPopup(show:Boolean,style:String,options:List<JSONObject>,value:String,foreground:Color,background:Color,accent:Color,onDismiss:()->Unit,onSelect:(String)->Unit) {
    // A navigation snapshot must never create a separate interactive window.
    if(!LocalNativeNavigationActive.current)return
    if(LocalNativeMaterial.current){MaterialSelectionPopup(show,options,value,onDismiss,onSelect);return}

    val surface=nativeSurface(background,isolated=true)
    val density=androidx.compose.ui.platform.LocalDensity.current
    val scale=LocalNativeUiScale.current
    CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,density.fontScale*scale)) {
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

}

internal val NativeActionHeight = 56.dp

/** Standard Miuix actions share the global surface setting and their parent blur. */
@Composable internal fun NativeDialogButton(label:String,style:String,foreground:Color,background:Color,textStyle:TextStyle,enabled:Boolean=true,modifier:Modifier=Modifier,centered:Boolean=true,singleLine:Boolean=false,visualEnabled:Boolean=enabled,dropdown:Boolean=false,navigation:Boolean=false,returnArrow:Boolean=false,primary:Boolean=false,onClick:()->Unit) {
    if(LocalNativeMaterial.current){MaterialAction(label,textStyle,enabled,modifier,primary,dropdown,navigation,returnArrow,onClick);return}

    if(navigation&&label.isNotBlank()&&!returnArrow&&!label.startsWith("返回")){
        NativePreferenceScale { top.yukonga.miuix.kmp.preference.ArrowPreference(title=label,
            modifier=modifier,enabled=enabled,onClick=onClick,insideMargin=PaddingValues(vertical=12.dp),startAction=nativeSettingIconSlot(enabled)) }
        return
    }
    if(dropdown||navigation){
        val ink=foreground.copy(alpha=if(visualEnabled)1f else .4f)
        if(label.isBlank()){
            top.yukonga.miuix.kmp.basic.IconButton(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp)){NativePreferenceArrow(dropdown,ink.copy(alpha=ink.alpha*.65f),returnArrow)}
            return
        }
        val backwards=returnArrow||label.startsWith("返回")
        NativePreferenceScale {
            top.yukonga.miuix.kmp.basic.BasicComponent(title=label,modifier=modifier,enabled=enabled,onClick=onClick,
                insideMargin=PaddingValues(vertical=12.dp),
                startAction=if(backwards){{NativePreferenceArrow(false,ink,backwards=true)}}else nativeSettingIconSlot(visualEnabled),
                endActions={if(!backwards)NativePreferenceArrow(dropdown,ink.copy(alpha=ink.alpha*.65f))})
        }
        return
    }
    if(LocalNativeSettingIcon.current in setOf("reset","wallpaper")){
        top.yukonga.miuix.kmp.basic.Button(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=NativeActionHeight)){
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){
                NativeSettingIcon(tint=foreground,enabled=visualEnabled)
                BasicText(label,style=textStyle.copy(color=foreground.copy(alpha=if(visualEnabled)1f else .4f)))
            }
        }
        return
    }
    // Match KSU's standard Miuix text actions; retain the requested shared height.
    if(label!="×"){
        top.yukonga.miuix.kmp.basic.TextButton(text=label,onClick=onClick,enabled=enabled,
            modifier=modifier.heightIn(min=NativeActionHeight),minHeight=NativeActionHeight,
            colors=if(primary)top.yukonga.miuix.kmp.basic.ButtonDefaults.textButtonColorsPrimary() else top.yukonga.miuix.kmp.basic.ButtonDefaults.textButtonColors(),
            textStyle=textStyle.copy(color=Color.Unspecified,textAlign=if(centered)TextAlign.Center else TextAlign.Start))
        return
    }
    val iconOnly=label=="×"
    val actionHeight=if(iconOnly)48.dp else NativeActionHeight
    val surface=nativeSurface(background,cornerRadius=if(iconOnly)16.dp else 28.dp,showOutline=false)
    val ink=foreground.copy(alpha=if(visualEnabled)1f else .4f)
    top.yukonga.miuix.kmp.basic.Button(onClick=onClick,enabled=enabled,indication=if(enabled)androidx.compose.foundation.LocalIndication.current else null,
        modifier=modifier.then(surface.modifier).heightIn(min=actionHeight),minHeight=actionHeight,minWidth=48.dp,insideMargin=if(iconOnly)PaddingValues(10.dp,4.dp)else PaddingValues(16.dp,12.dp),
        colors=top.yukonga.miuix.kmp.basic.ButtonColors(surface.color,if(visualEnabled)surface.color else surface.color.copy(alpha=surface.color.alpha*.4f),foreground,ink)) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp,if(centered)Alignment.CenterHorizontally else Alignment.Start)){
            if(label.startsWith("返回"))NativePreferenceArrow(false,ink,backwards=true)
            if(label=="×")Box(Modifier.weight(1f),contentAlignment=Alignment.Center){top.yukonga.miuix.kmp.basic.Icon(MiuixIcons.Basic.Close,null,Modifier.size(16.dp),tint=ink)}
            else BasicText(label,Modifier.weight(1f,fill=!centered),maxLines=if(singleLine)1 else Int.MAX_VALUE,softWrap=!singleLine,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis,style=textStyle.copy(color=ink,textAlign=if(centered)TextAlign.Center else TextAlign.Start))
        }
    }
}

@Composable internal fun NativeBackButton(label:String,color:Color,modifier:Modifier=Modifier,onClick:()->Unit){
    if(LocalNativeMaterial.current){MaterialBackButton(label,modifier,onClick);return}
    top.yukonga.miuix.kmp.basic.IconButton(onClick=onClick,modifier=modifier.size(48.dp).semantics{contentDescription=label}){
        top.yukonga.miuix.kmp.basic.Icon(MiuixIcons.Basic.ArrowRight,null,Modifier.size(10.dp,16.dp).graphicsLayer{rotationZ=180f},tint=color)
    }
}

/** Shared preference layout. One click target includes title, summary, value and arrow. */
@Composable internal fun NativePreferenceRow(title:String,value:String,summary:String,dropdown:Boolean,foreground:Color,textStyle:TextStyle,enabled:Boolean=true,visualEnabled:Boolean=enabled,spacious:Boolean=false,popupContent:@Composable ()->Unit={},onClick:()->Unit){
    if(LocalNativeMaterial.current){MaterialPreference(title,value,summary,dropdown,enabled,popupContent,onClick);return}
    if(!LocalNativeMaterial.current&&!dropdown){
        NativePreferenceScale { top.yukonga.miuix.kmp.preference.ArrowPreference(
            title=title,summary=summary.ifBlank{null},enabled=enabled,onClick=onClick,
            insideMargin=PaddingValues(vertical=12.dp),
            startAction=nativeSettingIconSlot(visualEnabled),endActions={if(value.isNotEmpty())top.yukonga.miuix.kmp.basic.Text(value)}) }
        return
    }

    val ink=foreground.copy(alpha=if(visualEnabled)1f else .4f)
    Row(Modifier.fillMaxWidth().heightIn(min=if(spacious)60.dp else 48.dp).clickable(enabled=enabled,role=Role.Button,onClick=onClick).padding(vertical=if(spacious)8.dp else 6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){
        NativeSettingIcon(tint=ink)
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)){
            BasicText(title,style=textStyle.copy(color=ink,fontWeight=androidx.compose.ui.text.font.FontWeight.Medium))
            if(summary.isNotBlank())BasicText(summary,style=textStyle.copy(color=ink.copy(alpha=ink.alpha*.65f),fontSize=textStyle.fontSize*(14f/17f)))
        }
        if(value.isNotEmpty())BasicText(value,Modifier.widthIn(max=160.dp),style=textStyle.copy(color=ink.copy(alpha=ink.alpha*.7f),textAlign=TextAlign.End))
        NativePreferenceArrow(dropdown,ink.copy(alpha=ink.alpha*.65f))
    }
}

@Composable internal fun NativePreferenceArrow(dropdown:Boolean,tint:Color,backwards:Boolean=false){
    if(LocalNativeMaterial.current){MaterialArrow(dropdown,backwards,tint);return}
    top.yukonga.miuix.kmp.basic.Icon(if(dropdown)MiuixIcons.Basic.ArrowUpDown else MiuixIcons.Basic.ArrowRight,null,Modifier.size(10.dp,16.dp).graphicsLayer{rotationZ=if(backwards)180f else 0f},tint=tint)
}

@Composable internal fun NativeSwitchPreference(title:String,summary:String,checked:Boolean,text:Color,accent:Color,style:TextStyle,enabled:Boolean=true,onChange:(Boolean)->Unit){
    if(LocalNativeMaterial.current){MaterialSwitchPreference(title,summary,checked,enabled,onChange);return}
        NativePreferenceScale { top.yukonga.miuix.kmp.preference.SwitchPreference(
            checked=checked,onCheckedChange=onChange,title=title,summary=summary.ifBlank{null},enabled=enabled,
            insideMargin=PaddingValues(vertical=12.dp),startAction=nativeSettingIconSlot(enabled)) }

}

@Composable internal fun NativeSliderLabel(title:String,value:String,style:TextStyle,summary:String=""){
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(if(LocalNativeMaterial.current)12.dp else 8.dp)){
        NativeSettingIcon(tint=style.color)
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)){
            BasicText(title,style=style.copy(fontWeight=androidx.compose.ui.text.font.FontWeight.Medium))
            if(summary.isNotBlank())BasicText(summary,style=style.copy(fontSize=style.fontSize*(14f/17f),fontWeight=androidx.compose.ui.text.font.FontWeight.Normal,color=style.color.copy(alpha=style.color.alpha*.65f)))
        }
        BasicText(value,style=style.copy(textAlign=TextAlign.End,fontFeatureSettings="tnum"))
    }
}

/** A single renderer choice shared by editors, menus and confirmation dialogs. */
@Composable internal fun NativeComponentDialog(show:Boolean,style:String,background:Color,text:Color,onDismissRequest:()->Unit,onDismissFinished:()->Unit,content:@Composable ()->Unit) {
    // A navigation snapshot must never create a separate interactive window.
    if(!LocalNativeNavigationActive.current)return
    if(LocalNativeMaterial.current){MaterialComponentDialog(show,onDismissRequest,onDismissFinished,content);return}

    var requested by remember { mutableStateOf(false) }
    LaunchedEffect(show,requested){
        if(!show)requested=false
        else if(requested){kotlinx.coroutines.delay(400);requested=false}
    }
    val dismiss={if(show&&!requested){requested=true;onDismissRequest()}}
    top.yukonga.miuix.kmp.window.WindowDialog(
        show=show,onDismissRequest=dismiss,onDismissFinished=onDismissFinished,
        insideMargin=DpSize(0.dp,0.dp),largeScreen=true){
        CompositionLocalProvider(LocalNativeBackdrop provides null,LocalNativeSurfaceBacked provides false){content()}
    }
}

/** Parent owns the only click action and semantics, so a tap cannot toggle twice. */
@Composable internal fun NativeChoiceMark(selected:Boolean,style:String,accent:Color,enabled:Boolean=true) {
    if(LocalNativeMaterial.current){androidx.compose.material3.RadioButton(selected,onClick=null,enabled=enabled,modifier=Modifier.clearAndSetSemantics{});return}

    top.yukonga.miuix.kmp.basic.RadioButton(selected=selected,onClick=null,enabled=enabled,
        colors=top.yukonga.miuix.kmp.basic.RadioButtonColors(accent,accent.copy(alpha=.4f)),modifier=Modifier.clearAndSetSemantics{})
}

@Composable internal fun NativeMiuixSlider(label:String,value:Float,enabled:Boolean,visualEnabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
 NativeMiuixRangeSlider(label,value,0,100,enabled,visualEnabled,tint,onValue,onDragging,onCommit)
}
@Composable internal fun NativeMiuixRangeSlider(label:String,value:Float,min:Int,max:Int,enabled:Boolean,visualEnabled:Boolean,tint:Color,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
    if(LocalNativeMaterial.current){MaterialRangeSlider(label,value,min,max,enabled,onValue,onDragging,onCommit);return}

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
        top.yukonga.miuix.kmp.basic.Slider(value=value,valueRange=min.toFloat()..max.toFloat(),enabled=enabled,height=20.dp,
            onValueChange={if(enabled)update(it)},onValueChangeFinished={drag(false);if(enabled)commit()},
            colors=top.yukonga.miuix.kmp.basic.SliderColors(tint,if(visualEnabled)tint else Color.Gray.copy(alpha=.4f),tint.copy(alpha=.18f),if(visualEnabled)tint.copy(alpha=.18f) else Color.Gray.copy(alpha=.15f),Color.White,Color.White.copy(alpha=if(visualEnabled)1f else .4f),tint,Color.White),
            modifier=Modifier.fillMaxWidth().height(20.dp).pointerInput(enabled){if(enabled)awaitEachGesture {
                awaitFirstDown(requireUnconsumed=false,pass=PointerEventPass.Initial)
                drag(true)
                try { do {val event=awaitPointerEvent(PointerEventPass.Final)} while(event.changes.any{it.pressed}) }
                finally {drag(false)}
            }})
    }
}

/** Card shell changes style while the caller retains stable row keys and layout. */
@Composable internal fun NativeComponentCard(style:String,color:Color,text:Color,modifier:Modifier=Modifier,backdrop:Backdrop?=LocalNativeBackdrop.current,content:@Composable ColumnScope.()->Unit) {
    if(LocalNativeMaterial.current){
        val colors=androidx.compose.material3.CardDefaults.cardColors()
        val surface=materialSurface(colors.containerColor,androidx.compose.material3.MaterialTheme.shapes.medium,backdrop)
        androidx.compose.material3.Card(modifier=modifier.fillMaxWidth().then(surface.modifier),colors=colors.copy(containerColor=surface.color)){
            CompositionLocalProvider(LocalNativeSurfaceBacked provides surface.frosted){content()}
        }
        return
    }

    val surface=nativeSurface(color,backdrop=backdrop)
    top.yukonga.miuix.kmp.basic.Card(modifier=modifier.fillMaxWidth().then(surface.modifier),cornerRadius=24.dp,
        colors=top.yukonga.miuix.kmp.basic.CardColors(surface.color,text)) {
        CompositionLocalProvider(LocalNativeSurfaceBacked provides surface.frosted){content()}
    }
}

@Composable internal fun NativeMiuixProgress(label:String,progress:()->Float,accent:Color,track:Color) {
    if(LocalNativeMaterial.current){
        androidx.compose.material3.LinearProgressIndicator(progress={progress().coerceIn(0f,1f)},modifier=Modifier.fillMaxWidth().semantics{contentDescription=label});return
    }

    val value=progress().coerceIn(0f,1f)
    top.yukonga.miuix.kmp.basic.LinearProgressIndicator(progress=value,height=8.dp,
        colors=top.yukonga.miuix.kmp.basic.ProgressIndicatorColors(if(value==0f)track else accent,accent.copy(alpha=.4f),track),
        modifier=Modifier.fillMaxWidth().semantics{contentDescription=label})
}

/** Unknown duration is never presented as a percentage; stop motion off-screen. */
@Composable internal fun NativeMiuixWaitingBar(label:String,animate:Boolean,accent:Color,track:Color) {
    if(LocalNativeMaterial.current&&animate){
        androidx.compose.material3.LinearProgressIndicator(modifier=Modifier.fillMaxWidth().semantics{contentDescription=label});return
    }

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
        if(animate&&LocalNativeMaterial.current)androidx.compose.material3.CircularProgressIndicator(modifier=decoration.size(28.dp))
        else if(animate&&orbit)top.yukonga.miuix.kmp.basic.InfiniteProgressIndicator(color=accent,size=28.dp,modifier=decoration)
        else if(animate)top.yukonga.miuix.kmp.basic.CircularProgressIndicator(progress=null,size=28.dp,
            colors=top.yukonga.miuix.kmp.basic.ProgressIndicatorColors(accent,accent.copy(alpha=.4f),accent.copy(alpha=.16f)),modifier=decoration)
        else Canvas(decoration.size(28.dp)){drawCircle(accent,style=Stroke(2.dp.toPx()))}
        BasicText(label,Modifier.weight(1f),style=textStyle.copy(color=foreground))
    }
}

/** Resolve legacy document sizes to the selected theme's semantic hierarchy before scaling. */
@Composable internal fun nativeTextStyle(color:Color=Color.Unspecified,fontSize:androidx.compose.ui.unit.TextUnit=17.sp,fontWeight:androidx.compose.ui.text.font.FontWeight?=null,scale:Float=1f):TextStyle {
    val prominent=(fontWeight?.weight?:400)>=500
    val size=fontSize.value
    val base=if(LocalNativeMaterial.current){
        val t=androidx.compose.material3.MaterialTheme.typography
        when {
            size>=30->t.headlineLarge
            size>=24->t.headlineSmall
            size>=20->t.titleLarge
            size>=18->t.titleMedium
            size>=16&&prominent->t.titleMedium
            size>=16->t.bodyLarge
            size>=14&&prominent->t.labelLarge
            size>=14->t.bodyMedium
            size>=12->t.bodySmall
            else->t.labelSmall
        }
    }else{
        val t=top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles
        when {
            size>=30->t.title1
            size>=24->t.title2
            size>=20->t.title3
            size>=18->t.title4
            size>=17&&prominent->t.headline1
            size>=17->t.main
            size>=16&&prominent->t.headline2
            size>=16->t.body1
            size>=14&&prominent->t.subtitle
            size>=14->t.body2
            size>=12->t.footnote1
            else->t.footnote2
        }
    }
    return base.copy(color=color,fontSize=base.fontSize*scale,
        lineHeight=if(base.lineHeight.isSp)base.lineHeight*scale else base.lineHeight)
}

/** Settings use Miuix's grouped card or Material's individually shaped segments. */
@Composable internal fun NativeSettingsCard(style:String,color:Color,text:Color,backdrop:Backdrop?=LocalNativeBackdrop.current,content:@Composable ColumnScope.()->Unit){
    if(LocalNativeMaterial.current)Column(Modifier.fillMaxWidth(),content=content)
    else NativeComponentCard(style,color,text,backdrop=backdrop,content=content)
}
