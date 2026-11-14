@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
package io.github.yawasau.speedbackup.webview

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Check
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.TextStyle
import org.json.JSONObject
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.catalog.components.GlassMaterial

/** Backdrop effect only: shape and tint remain owned by Material. */
@Composable internal fun materialSurface(color:Color,shape:androidx.compose.ui.graphics.Shape,backdrop:Backdrop?=LocalNativeBackdrop.current):NativeSurface {
    val strength=GlassMaterial.LocalControls.current.blurStrength
    if(backdrop==null||!GlassMaterial.LocalBlurEnabled.current||android.os.Build.VERSION.SDK_INT<31)return NativeSurface(Modifier,color,false)
    if(LocalNativeSurfaceBacked.current)return NativeSurface(Modifier,Color.Transparent,true)
    return NativeSurface(Modifier.drawBackdrop(backdrop=backdrop,shape={shape},highlight=null,shadow=null,
        effects={blur((36f*strength/100f).dp.toPx())},onDrawSurface={drawRect(color.copy(alpha=color.alpha*.68f))}),Color.Transparent,true)
}

@Composable internal fun materialScaled(style:TextStyle):TextStyle=style.copy(
    fontSize=style.fontSize*LocalNativeUiScale.current,lineHeight=style.lineHeight*LocalNativeUiScale.current)

internal val LocalMaterialSegment = staticCompositionLocalOf { 0 to 1 }
@Composable internal fun NativeSettingSegment(index:Int,count:Int,content:@Composable ()->Unit){
    if(!LocalNativeMaterial.current){content();return}
    val top=if(index==0)16.dp else 4.dp
    val bottom=if(index==count-1)16.dp else 4.dp
    val shape=androidx.compose.foundation.shape.RoundedCornerShape(top,top,bottom,bottom)
    val surface=materialSurface(MaterialTheme.colorScheme.surfaceBright,shape)
    CompositionLocalProvider(LocalMaterialSegment provides (index to count),LocalNativeSurfaceBacked provides surface.frosted){
        Surface(shape=shape,color=surface.color,contentColor=MaterialTheme.colorScheme.onSurface,modifier=Modifier.fillMaxWidth().then(surface.modifier)) { content() }
    }
}
@Composable internal fun MaterialPreference(title:String,value:String,summary:String,dropdown:Boolean,enabled:Boolean,popupContent:@Composable ()->Unit={},onClick:()->Unit){
    val colors=MaterialTheme.colorScheme
    val container=if(LocalNativeSurfaceBacked.current)Color.Transparent else colors.surfaceBright
    val (index,count)=LocalMaterialSegment.current
    val haptic=LocalHapticFeedback.current
    SegmentedListItem(onClick={haptic.performHapticFeedback(HapticFeedbackType.VirtualKey);onClick()},enabled=enabled,
        shapes=ListItemDefaults.segmentedShapes(index,count),
        colors=ListItemDefaults.segmentedColors(containerColor=container,disabledContainerColor=container,supportingContentColor=colors.onSurfaceVariant),
        leadingContent=nativeSettingIconSlot(enabled),
        supportingContent=if(summary.isBlank())null else {{Text(summary,style=materialScaled(MaterialTheme.typography.bodyMedium))}},
        trailingContent={
            if(dropdown)Box(Modifier.fillMaxWidth(.3f)){
                Text(value,modifier=Modifier.fillMaxWidth(),textAlign=TextAlign.End,
                color=if(enabled)colors.primary else colors.onSurfaceVariant,
                style=materialScaled(LocalTextStyle.current))
                // A native, zero-size end anchor follows the value through layout/scroll changes.
                Box(Modifier.align(Alignment.BottomEnd)){popupContent()}
            }
            else MaterialArrow(false)
        },verticalAlignment=Alignment.CenterVertically,
        content={Text(title,style=materialScaled(MaterialTheme.typography.bodyLarge))})
}
@Composable internal fun MaterialSwitch(checked:Boolean,onCheckedChange:((Boolean)->Unit)?,enabled:Boolean,modifier:Modifier=Modifier){
    val c=MaterialTheme.colorScheme
    Switch(checked=checked,onCheckedChange=onCheckedChange,enabled=enabled,modifier=modifier,
        thumbContent=if(checked||enabled){{Icon(if(checked)Icons.Filled.Check else Icons.Filled.Close,null,Modifier.size(SwitchDefaults.IconSize))}}else null,
        colors=SwitchDefaults.colors(checkedIconColor=c.primary,uncheckedIconColor=c.surfaceContainerHighest,
            disabledCheckedThumbColor=c.surface.copy(alpha=.38f),disabledCheckedTrackColor=c.onSurface.copy(alpha=.12f),
            disabledCheckedIconColor=c.onSurface.copy(alpha=.12f),disabledUncheckedThumbColor=c.outline.copy(alpha=.38f),
            disabledUncheckedTrackColor=c.surfaceContainerHighest.copy(alpha=.12f),disabledUncheckedBorderColor=c.onSurface.copy(alpha=.12f),disabledUncheckedIconColor=c.surfaceContainerHighest))
}
@Composable internal fun MaterialSwitchPreference(title:String,summary:String,checked:Boolean,enabled:Boolean,onChange:(Boolean)->Unit){
    val c=MaterialTheme.colorScheme
    val container=if(LocalNativeSurfaceBacked.current)Color.Transparent else c.surfaceBright
    val (index,count)=LocalMaterialSegment.current
    val haptic=LocalHapticFeedback.current
    SegmentedListItem(onClick={haptic.performHapticFeedback(HapticFeedbackType.VirtualKey);onChange(!checked)},enabled=enabled,
        shapes=ListItemDefaults.segmentedShapes(index,count),
        colors=ListItemDefaults.segmentedColors(containerColor=container,disabledContainerColor=container,supportingContentColor=c.onSurfaceVariant),
        leadingContent=nativeSettingIconSlot(enabled),
        supportingContent=if(summary.isBlank())null else {{Text(summary,style=materialScaled(MaterialTheme.typography.bodyMedium))}},
        trailingContent={Box(Modifier.clearAndSetSemantics{}){MaterialSwitch(checked,null,enabled)}},
        verticalAlignment=Alignment.CenterVertically,
        content={Text(title,style=materialScaled(MaterialTheme.typography.bodyLarge))})
}
@Composable internal fun MaterialSelectionPopup(show:Boolean,options:List<JSONObject>,value:String,onDismiss:()->Unit,onSelect:(String)->Unit) {
    val haptic=LocalHapticFeedback.current
    val gestureHost=LocalView.current
    DropdownMenuPopup(expanded=show,onDismissRequest=onDismiss) {
        DropdownMenuGroup(shapes=MenuDefaults.groupShape(0,1),modifier=materialWindowBack(show,onDismiss,gestureHost=gestureHost).verticalScroll(rememberScrollState())){
            options.forEachIndexed { index,option -> key(option.getString("value")) {
                SelectableDropdownMenuItem(text={Text(option.getString("label"),style=materialScaled(LocalTextStyle.current))},
                    selected=option.getString("value")==value,shapes=MenuDefaults.itemShape(index,options.size),
                    selectedLeadingIcon={Icon(Icons.Filled.Check,null,Modifier.size(MenuDefaults.LeadingIconSize))},
                    enabled=!option.optBoolean("disabled"),onClick={haptic.performHapticFeedback(HapticFeedbackType.VirtualKey);onSelect(option.getString("value"))})
            }}
        }
    }
}

@Composable internal fun MaterialArrow(dropdown:Boolean,backwards:Boolean=false,tint:Color=MaterialTheme.colorScheme.onSurfaceVariant) {
    Icon(if(dropdown)Icons.Default.ExpandMore else if(backwards)Icons.AutoMirrored.Filled.ArrowBack else Icons.AutoMirrored.Filled.KeyboardArrowRight,null,tint=tint)
}

internal val LocalNativeFooterAction = staticCompositionLocalOf { false }
internal val LocalNativeToolbarAction = staticCompositionLocalOf { false }

@Composable internal fun MaterialAction(label:String,textStyle:TextStyle,enabled:Boolean,modifier:Modifier,primary:Boolean,dropdown:Boolean=false,navigation:Boolean=false,backwards:Boolean=false,onClick:()->Unit) {
    if(label.isBlank()||label=="×") {
        IconButton(onClick=onClick,enabled=enabled,modifier=modifier) {
            if(label=="×")Icon(Icons.Default.Close,null) else MaterialArrow(dropdown,backwards)
        };return
    }
    if(navigation&&!backwards&&!primary&&!LocalNativeToolbarAction.current&&!LocalNativeFooterAction.current) TextButton(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp),contentPadding=PaddingValues(horizontal=12.dp,vertical=12.dp)) {
        Text(label,modifier=Modifier.weight(1f),style=materialScaled(MaterialTheme.typography.labelLarge),textAlign=TextAlign.Start)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.width(24.dp),contentAlignment=Alignment.Center){MaterialArrow(false)}
    } else if(primary) Button(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp)) {
        Text(label,style=materialScaled(MaterialTheme.typography.labelLarge))
    } else if(LocalNativeToolbarAction.current) FilledTonalButton(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp)) {
        Text(label,style=materialScaled(MaterialTheme.typography.labelLarge))
    } else if(LocalNativeFooterAction.current) OutlinedButton(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp)) {
        if(backwards)MaterialArrow(false,true)
        Text(label,style=materialScaled(MaterialTheme.typography.labelLarge))
    } else TextButton(onClick=onClick,enabled=enabled,modifier=modifier.heightIn(min=48.dp)) {
        if(backwards)MaterialArrow(false,true)
        else if(LocalNativeSettingIcon.current in setOf("reset","wallpaper")){NativeSettingIcon(enabled=enabled);Spacer(Modifier.width(8.dp))}
        Text(label,style=materialScaled(MaterialTheme.typography.labelLarge))
    }
}

@Composable internal fun MaterialComponentDialog(show:Boolean,onDismiss:()->Unit,onDismissFinished:()->Unit,content:@Composable ()->Unit) {
    var backCommitted by remember{mutableStateOf(false)}
    LaunchedEffect(show){if(show)backCommitted=false}
    val visible=remember{MutableTransitionState(false)}
    visible.targetState=show
    val finished by rememberUpdatedState(onDismissFinished)
    var wasVisible by remember{mutableStateOf(false)}
    LaunchedEffect(show){if(show)wasVisible=true}
    LaunchedEffect(visible.currentState,visible.isIdle,show){
        if(wasVisible&&!show&&visible.isIdle&&!visible.currentState){wasVisible=false;finished()}
    }
    if(visible.currentState||visible.targetState) {
        val motion=MaterialTheme.motionScheme
        val spatial:FiniteAnimationSpec<Float> = if(LocalNativeReducedMotion.current)snap() else motion.defaultSpatialSpec()
        val effects:FiniteAnimationSpec<Float> = if(LocalNativeReducedMotion.current)snap() else motion.defaultEffectsSpec()
        BasicAlertDialog(onDismissRequest=onDismiss) {
            AnimatedVisibility(visibleState=visible,
                enter=fadeIn(effects)+scaleIn(spatial,initialScale=.9f),
                exit=if(backCommitted)fadeOut(effects) else fadeOut(effects)+scaleOut(spatial,targetScale=.9f)) {
                Surface(modifier=materialWindowBack(show,onDismiss,onCommitted={backCommitted=it}),shape=MaterialTheme.shapes.extraLarge,color=MaterialTheme.colorScheme.surfaceContainerHigh,
                    contentColor=MaterialTheme.colorScheme.onSurface) {
                    CompositionLocalProvider(LocalNativeBackdrop provides null,LocalNativeSurfaceBacked provides false){content()}
                }
            }
        }
    }
}

@Composable internal fun MaterialRangeSlider(label:String,value:Float,min:Int,max:Int,enabled:Boolean,onValue:(Float)->Unit,onDragging:(Boolean)->Unit,onCommit:()->Unit) {
    val interaction=remember{MutableInteractionSource()}
    val dragging by interaction.collectIsDraggedAsState()
    val currentDrag by rememberUpdatedState(onDragging)
    LaunchedEffect(dragging){currentDrag(dragging)}
    DisposableEffect(Unit){onDispose{currentDrag(false)}}
    Slider(value=value.coerceIn(min.toFloat(),max.toFloat()),onValueChange=onValue,
        enabled=enabled,valueRange=min.toFloat()..max.toFloat(),
        onValueChangeFinished=onCommit,interactionSource=interaction,
        modifier=Modifier.fillMaxWidth().semantics{contentDescription=label})
}

@Composable internal fun MaterialBackButton(label:String,modifier:Modifier,onClick:()->Unit){
    IconButton(onClick=onClick,modifier=modifier.size(48.dp),
        colors=IconButtonDefaults.iconButtonColors(containerColor=MaterialTheme.colorScheme.surfaceContainerHighest,contentColor=MaterialTheme.colorScheme.onSurfaceVariant)){
        Icon(Icons.AutoMirrored.Rounded.ArrowBack,label)
    }
}

/** Dialog and Popup own separate windows: the Activity back dispatcher cannot animate them.
 * Keep the component's existing pre-34/key/outside dismissal; only bridge gesture progress.
 */
@Composable private fun materialWindowBack(enabled:Boolean,onDismiss:()->Unit,gestureHost:android.view.View?=null,onCommitted:(Boolean)->Unit={}):Modifier {
    if(android.os.Build.VERSION.SDK_INT<34)return Modifier
    val view=LocalView.current
    // Compose Popup dismisses on ACTION_OUTSIDE before Android recognizes edge Back.
    // Reserve only the system gesture edge; ordinary outside taps retain upstream handling.
    DisposableEffect(view,enabled,gestureHost){
        val root=view.rootView
        val listener=android.view.View.OnTouchListener { _,event ->
            val edges=(gestureHost?:root).rootWindowInsets?.getInsets(android.view.WindowInsets.Type.systemGestures())
            val width=root.context.resources.displayMetrics.widthPixels
            enabled&&gestureHost!=null&&edges!=null&&
                (event.actionMasked==android.view.MotionEvent.ACTION_OUTSIDE||
                    (event.actionMasked==android.view.MotionEvent.ACTION_DOWN&&
                        (event.x<0||event.x>=root.width||event.y<0||event.y>=root.height)))&&
                (event.rawX<edges.left||event.rawX>=width-edges.right)
        }
        if(enabled&&gestureHost!=null)root.setOnTouchListener(listener)
        onDispose{if(enabled&&gestureHost!=null)root.setOnTouchListener(null)}
    }
    val imeVisible=WindowInsets.ime.getBottom(LocalDensity.current)>0
    val dismiss by rememberUpdatedState(onDismiss)
    var committed by remember{mutableStateOf(false)}
    val reportCommitted by rememberUpdatedState(onCommitted)
    val active by rememberUpdatedState(enabled&&!imeVisible&&!committed)
    var gesture by remember{mutableStateOf(false)}
    var progress by remember{mutableFloatStateOf(0f)}
    val motion=MaterialTheme.motionScheme
    val spec:FiniteAnimationSpec<Float> = if(gesture||LocalNativeReducedMotion.current)snap() else motion.fastSpatialSpec()
    val animated by animateFloatAsState(if(LocalNativeReducedMotion.current)0f else progress,spec,label="MaterialWindowBack")
    LaunchedEffect(enabled,imeVisible){if(enabled){committed=false;reportCommitted(false);gesture=false;progress=0f}}
    LaunchedEffect(committed,enabled){
        if(committed&&enabled){
            kotlinx.coroutines.delay(5000)
            committed=false;reportCommitted(false);gesture=false;progress=0f
        }
    }
    DisposableEffect(view,enabled,imeVisible){
        // Let the IME's own callback handle Back first while a text field is being edited.
        val remove=if(enabled&&!imeVisible)MaterialWindowBackApi34.install(view,
            {active},{value->gesture=true;progress=value},
            {gesture=false;progress=0f},{if(active){committed=true;reportCommitted(true);gesture=true;dismiss()}}) else ({})
        onDispose{remove()}
    }
    return Modifier.graphicsLayer {val p=animated.coerceIn(0f,1f);scaleX=1f-.1f*p;scaleY=scaleX}
}

@androidx.annotation.RequiresApi(34)
private object MaterialWindowBackApi34 {
    fun install(view:android.view.View,enabled:()->Boolean,onProgress:(Float)->Unit,onCancel:()->Unit,onCommit:()->Unit):()->Unit {
        var dispatcher:android.window.OnBackInvokedDispatcher?=null
        var disposed=false
        val callback=object:android.window.OnBackAnimationCallback {
            override fun onBackStarted(event:android.window.BackEvent){if(enabled())onProgress(0f)}
            override fun onBackProgressed(event:android.window.BackEvent){if(enabled())onProgress(event.progress.coerceIn(0f,1f))}
            override fun onBackCancelled(){onCancel()}
            override fun onBackInvoked(){if(enabled())onCommit()}
        }
        fun unregister(){dispatcher?.unregisterOnBackInvokedCallback(callback);dispatcher=null}
        // Popup installs its default completed-only callback on attach. Register after that
        // at the same priority, so only this window's most recent callback handles Back.
        val register=Runnable {
            if(!disposed&&view.isAttachedToWindow&&enabled()){
                val next=view.findOnBackInvokedDispatcher()
                if(next!==dispatcher){unregister();next?.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY,callback);dispatcher=next}
            }
        }
        val listener=object:android.view.View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v:android.view.View){v.post(register)}
            override fun onViewDetachedFromWindow(v:android.view.View){v.removeCallbacks(register);unregister()}
        }
        view.addOnAttachStateChangeListener(listener)
        if(view.isAttachedToWindow)view.post(register)
        return {disposed=true;view.removeCallbacks(register);view.removeOnAttachStateChangeListener(listener);unregister()}
    }
}
