@file:OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
package io.github.yawasau.speedbackup.webview

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

/** Controller acknowledgements own route changes; Material owns their presentation. */
@Composable internal fun <T:Any> NativeMaterialNavHost(route:String,value:T,reducedMotion:Boolean,modifier:Modifier,
    onBack:()->Unit,root:Boolean,backRoute:String,previewBack:Boolean,boundaryBack:Boolean,onMotion:(Boolean)->Unit,content:@Composable (T)->Unit) {
    val models=remember{mutableStateMapOf<String,T>()}
    val history=remember{mutableListOf<String>()}
    var returning by remember{mutableStateOf(false)}
    remember(route,value,backRoute){
        models[route]=value
        if(root&&history.firstOrNull()!=route)history.clear()
        if(history.lastOrNull()!=route){
            val index=history.indexOf(route)
            returning=index>=0
            if(index>=0)while(history.size>index+1)history.removeAt(history.lastIndex)
            else {if(history.size>=32)history.removeAt(1);history.add(route)}
        }
        val parent=history.indexOf(backRoute)
        if(parent>=0&&parent<history.lastIndex-1){
            while(history.size>parent+1)history.removeAt(history.lastIndex)
            history.add(route)
        }
        if(models.size>64){
            val live=history.toSet()
            models.keys.toList().filter{it !in live}.take(models.size-64).forEach{models.remove(it)}
        }
        true
    }
    val transition=updateTransition(route,label="MaterialNavigation")
    val motion=MaterialTheme.motionScheme
    val spatial:FiniteAnimationSpec<Float> = if(reducedMotion)snap() else motion.defaultSpatialSpec()
    val effects:FiniteAnimationSpec<Float> = if(reducedMotion)snap() else motion.defaultEffectsSpec()
    val back by rememberUpdatedState(onBack)
    val currentRoute by rememberUpdatedState(route)
    val currentBackRoute by rememberUpdatedState(backRoute)
    val currentPreview by rememberUpdatedState(previewBack)
    var previewOrigin by remember{mutableStateOf("")}
    var previewRoute by remember{mutableStateOf("")}
    var rightEdge by remember{mutableStateOf(false)}
    val notify by rememberUpdatedState(onMotion)
    val progress=remember{Animatable(0f)}
    val scope=rememberCoroutineScope()
    var settle by remember{mutableStateOf<Job?>(null)}
    var pendingOrigin by remember{mutableStateOf<String?>(null)}
    var committedOrigin by remember{mutableStateOf<String?>(null)}
    val backProgress=if(previewOrigin==route)progress.value else 0f
    LaunchedEffect(route,backRoute,pendingOrigin){
        val origin=pendingOrigin ?: return@LaunchedEffect
        if(route!=origin){pendingOrigin=null;return@LaunchedEffect}
        if(backRoute!=previewRoute){pendingOrigin=null;committedOrigin=null;settle=scope.launch{progress.animateTo(0f,spatial)};return@LaunchedEffect}
        delay(5000)
        if(pendingOrigin==origin){pendingOrigin=null;committedOrigin=null;settle=scope.launch{progress.animateTo(0f,spatial)}}
    }
    LaunchedEffect(transition.currentState,transition.targetState,transition.isRunning,pendingOrigin){
        if(!transition.isRunning&&transition.currentState==transition.targetState&&transition.currentState!=previewOrigin&&pendingOrigin==null){
            settle?.cancel();progress.snapTo(0f)
            previewOrigin="";previewRoute="";committedOrigin=null
        }
    }
    NativePredictiveBackHandler(enabled=boundaryBack||pendingOrigin!=null) { events ->
        if(pendingOrigin!=null){events.collect{};return@NativePredictiveBackHandler}
        val origin=currentRoute
        settle?.cancel()
        if(previewOrigin!=origin)progress.snapTo(0f)
        committedOrigin=null
        previewOrigin=origin
        previewRoute=currentBackRoute.takeIf{currentPreview&&it!=origin&&it in history&&models.containsKey(it)}.orEmpty()
        settle?.cancel()
        progress.stop()
        val anchor=progress.value
        try {
            events.collect {
                rightEdge=it.swipeEdge==androidx.activity.BackEventCompat.EDGE_RIGHT
                if(!reducedMotion)progress.snapTo(anchor+(1f-anchor)*it.progress.coerceIn(0f,1f))
            }
            // Controller acknowledgement still owns the route: a dirty form may open a dialog.
            if(currentRoute==origin){
                if(previewRoute.isNotEmpty()&&previewRoute==currentBackRoute){pendingOrigin=origin;committedOrigin=origin}
                back()
            }
            if(pendingOrigin==null)settle=scope.launch{progress.animateTo(0f,spatial)}
        } catch(cancelled:CancellationException){
            settle=scope.launch{progress.animateTo(0f,spatial)}
            throw cancelled
        }
    }
    LaunchedEffect(route,transition.isRunning,backProgress>0f,pendingOrigin){
        notify(transition.isRunning||backProgress>0f||pendingOrigin!=null)
        // Keep bounded parent snapshots for predictive preview, not just outgoing transitions.
    }
    DisposableEffect(Unit){onDispose{notify(false)}}
    val preview=previewRoute.takeIf{previewOrigin==route&&backRoute==it&&backProgress>0f}?.let{models[it]}
    Box(modifier) {
        if(preview!=null)CompositionLocalProvider(LocalNativeNavigationActive provides false){
            Box(Modifier.fillMaxSize()){content(preview)}
        }
        transition.AnimatedContent(transitionSpec={
            if(committedOrigin==initialState&&previewRoute==targetState){
                // Continue from the released transform; do not reset to full size then scale again.
                fadeIn(effects) togetherWith fadeOut(effects)
            }else{
                (fadeIn(effects)+scaleIn(spatial,initialScale=if(returning)1.1f else .9f)) togetherWith
                    (fadeOut(effects)+scaleOut(spatial,targetScale=if(returning).9f else 1.1f))
            }
        },modifier=Modifier.fillMaxSize(),contentKey={it}) { key ->
            models[key]?.let { model -> CompositionLocalProvider(LocalNativeNavigationActive provides (key==route&&(pendingOrigin==null||pendingOrigin!=route))){
                Box(Modifier.fillMaxSize().graphicsLayer {
                    val p=if(key==previewOrigin)progress.value else 0f
                    scaleX=1f-p*.1f;scaleY=scaleX
                    alpha=if(previewRoute.isEmpty())1f-p*.2f else 1f
                    translationX=if(previewRoute.isNotEmpty())32.dp.toPx()*p*(if(rightEdge)-1f else 1f) else 0f
                    shape=RoundedCornerShape(28.dp);clip=p>0f
                }){content(model)}
            } }
        }
        if(transition.isRunning||backProgress>0f||pendingOrigin!=null)Box(Modifier.fillMaxSize().pointerInput(Unit){
            awaitPointerEventScope {while(true)awaitPointerEvent().changes.forEach{it.consume()}}
        })
    }
}
