package io.github.yawasau.speedbackup.webview

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/** Observe the host lifetime; no animation clock survives a paused Activity. */
@Composable internal fun rememberNativeResumed():Boolean {
    val owner=LocalLifecycleOwner.current
    var resumed by remember(owner){mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))}
    DisposableEffect(owner){
        val observer=LifecycleEventObserver{_,_->resumed=owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)}
        owner.lifecycle.addObserver(observer)
        onDispose{owner.lifecycle.removeObserver(observer)}
    }
    return resumed
}
