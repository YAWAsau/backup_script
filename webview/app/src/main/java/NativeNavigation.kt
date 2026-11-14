package io.github.yawasau.speedbackup.webview

import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.BackEventCompat
import androidx.compose.ui.platform.LocalView
import androidx.navigationevent.findViewTreeNavigationEventDispatcherOwner
import kotlinx.coroutines.flow.Flow
import androidx.navigationevent.compose.LocalNavigationEventDispatcherOwner
import androidx.navigationevent.NavigationEventDispatcherOwner
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.snap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import top.yukonga.miuix.kmp.nav.transition.NavSettleSpec
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import top.yukonga.miuix.kmp.nav.core.*
import top.yukonga.miuix.kmp.nav.transition.NavTransitions

internal val LocalNativeNavigationActive=staticCompositionLocalOf { true }

private data class NativeRoute(val id:String):NavKey

/** Resolve from the actual window, never from a movable navigation entry's local. */
@Composable
private fun nativeWindowBackOwner():NavigationEventDispatcherOwner {
    val view=LocalView.current
    val activity=LocalActivity.current
    return checkNotNull(view.findViewTreeNavigationEventDispatcherOwner()
        ?: activity as? NavigationEventDispatcherOwner) { "Missing window back dispatcher" }
}

@Composable
private fun NativeAppBackScope(owner:NavigationEventDispatcherOwner,content:@Composable ()->Unit) {
    CompositionLocalProvider(LocalNavigationEventDispatcherOwner provides owner,content=content)
}

/** Re-resolve at registration, including handlers recomposed inside movable entry content. */
@Composable
internal fun NativePredictiveBackHandler(enabled:Boolean=true,onBack:suspend (Flow<BackEventCompat>)->Unit) {
    val owner=nativeWindowBackOwner()
    NativeAppBackScope(owner) { PredictiveBackHandler(enabled=enabled,onBack=onBack) }
}

/** The controller owns navigation and validation; Miuix owns all page motion.
 * In-memory keys deliberately avoid restoring stale document/permission sessions after death.
 * The existing controller and resume store reconstruct the authoritative current document.
 */
@Composable
internal fun <T:Any> NativeNavHost(
    route:String, value:T, reducedMotion:Boolean, modifier:Modifier=Modifier,
    onBack:()->Unit, root:Boolean=false, backRoute:String="", previewBack:Boolean=true, boundaryBack:Boolean=true, onMotion:(Boolean)->Unit={}, content: @Composable (T)->Unit
) {
    if(!LocalNativeNavigationActive.current){Box(modifier){content(value)};return}
    if(LocalNativeMaterial.current){
        NativeMaterialNavHost(route,value,reducedMotion,modifier,onBack,root,backRoute,previewBack,boundaryBack,onMotion,content)
        return
    }
    // A captured composition-local owner can itself belong to a removed entry.
    // Window ownership survives loading-document swaps and navigation host disposal.
    val appDispatcherOwner by rememberUpdatedState(nativeWindowBackOwner())
    val stack=remember { navBackStackOf(NativeRoute(route)) }
    val models=remember { mutableStateMapOf<String,T>() }
    val currentBack by rememberUpdatedState(onBack)
    val currentMotion by rememberUpdatedState(onMotion)
    val currentRoute by rememberUpdatedState(route)
    val currentParent by rememberUpdatedState(backRoute)
    val currentPreview by rememberUpdatedState(previewBack)
    // Presentation may finish a verified pop immediately, but never dispatch from its
    // cached destination until the controller acknowledges it. Keep the origin for rollback.
    var pendingOrigin by remember { mutableStateOf<String?>(null) }
    var pendingTarget by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(pendingOrigin) {
        val origin=pendingOrigin ?: return@LaunchedEffect
        delay(5000)
        if(pendingOrigin==origin){
            if(currentRoute==origin&&stack.lastOrNull()!=NativeRoute(origin))stack.add(NativeRoute(origin))
            pendingOrigin=null;pendingTarget=null
        }
    }
    // Route changes come from acknowledged controller models, never optimistic button clicks.
    remember(route,value,backRoute) {
        models[route]=value
        if(pendingOrigin!=null&&(route!=pendingOrigin||backRoute!=pendingTarget)){
            pendingOrigin=null;pendingTarget=null
        }
        val key=NativeRoute(route)
        if(pendingOrigin==route)return@remember true
        if(root&&stack.firstOrNull()!=key){stack.clear();stack.add(key)}
        val index=stack.indexOf(key)
        if(index>=0)while(stack.size>index+1)stack.removeAt(stack.lastIndex)
        else {
            // Keep the root so a long navigation session still animates returning home as a pop.
            if(stack.size>=32)stack.removeAt(1)
            stack.add(key)
        }
        // A sibling visit is not necessarily Back's destination (editor tabs, paging).
        val parent=stack.indexOf(NativeRoute(backRoute))
        if(parent>=0&&parent<stack.lastIndex-1){
            while(stack.size>parent+1)stack.removeAt(stack.lastIndex)
            stack.add(key)
        }
        // Bound snapshots even when a long jump skips entries that were never composed.
        if(models.size>64){
            val live=stack.map{(it as NativeRoute).id}.toSet()
            models.keys.toList().filter{it !in live}.take(models.size-64).forEach{models.remove(it)}
        }
        true
    }
    Box(modifier) {
    NavDisplay(backStack=stack,modifier=Modifier.fillMaxSize(),
        transition=if(reducedMotion)NavTransitions.None else NavTransitions.MiuixDefault,
        effects=NavDisplayEffects(cornerClipRadius=rememberNavSystemCornerRadius(),blockInputDuringTransition=true),
        onBack={
            if(pendingOrigin==null){
                val parent=NativeRoute(currentParent)
                if(currentPreview&&currentParent.isNotEmpty()&&stack.lastOrNull()==NativeRoute(currentRoute)&&stack.getOrNull(stack.lastIndex-1)==parent){
                    pendingOrigin=currentRoute;pendingTarget=currentParent
                    stack.removeAt(stack.lastIndex)
                }
                currentBack()
            }
        }) {
        entry<NativeRoute> { key ->
            NativeAppBackScope(appDispatcherOwner) {
            val transition=LocalNavTransitionScope.current
            val top=key.id==currentRoute&&pendingOrigin==null
            val boundary=boundaryBack&&top&&(!previewBack||stack.size==1||backRoute.isEmpty()||stack.getOrNull(stack.lastIndex-1)!=NativeRoute(backRoute))
            val progress=remember(key){Animatable(0f)}
            val scope=rememberCoroutineScope()
            var settling by remember(key){mutableStateOf<Job?>(null)}
            val currentBoundary by rememberUpdatedState(boundary)
            val motion=remember{NavSettleSpec.Spring()}
            val settleSpec=if(reducedMotion)snap<Float>() else spring<Float>(motion.dampingRatio,motion.stiffness)
            LaunchedEffect(top,transition.isRunning,progress.value>0f) {
                if(top){
                    currentMotion(transition.isRunning||progress.value>0f)
                }
            }
            DisposableEffect(key){onDispose{if(key !in stack&&key.id!=pendingOrigin)models.remove(key.id)}}
            // With no verified parent (external editor / dirty form), animate only the
            // current page. Never fabricate a previous document or cancel before commit.
            // A real in-stack parent continues to use NavDisplay's native predictive pop.
            NativePredictiveBackHandler(enabled=boundary) { events ->
                settling?.cancel()
                progress.stop()
                val anchor=progress.value
                try {
                    events.collect { event ->
                        if(!reducedMotion)progress.snapTo(anchor+(1f-anchor)*event.progress.coerceIn(0f,1f))
                    }
                    if(currentBoundary&&key.id==currentRoute)currentBack()
                } catch(cancelled:CancellationException) {
                    throw cancelled
                } finally {
                    settling=scope.launch{progress.animateTo(0f,settleSpec)}
                }
            }
            models[key.id]?.let { model -> CompositionLocalProvider(LocalNativeNavigationActive provides top){
                Box(Modifier.fillMaxSize().graphicsLayer {
                    val p=progress.value
                    scaleX=1f-p*.08f;scaleY=scaleX
                }){content(model)}
            } }
            }
        }
    }
    if(pendingOrigin!=null)Box(Modifier.fillMaxSize().pointerInput(Unit){
        awaitPointerEventScope {while(true)awaitPointerEvent().changes.forEach{it.consume()}}
    })
    // Consume repeat Back while awaiting the already-dispatched controller result.
    NativePredictiveBackHandler(enabled=pendingOrigin!=null){events->events.collect{}}
    }
    DisposableEffect(Unit){onDispose{currentMotion(false)}}
}
