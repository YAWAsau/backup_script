package top.yukonga.miuix.kmp.nav.core

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.v2.runComposeUiTest
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigationevent.DirectNavigationEventInput
import androidx.navigationevent.NavigationEvent
import androidx.navigationevent.NavigationEventDispatcher
import androidx.navigationevent.NavigationEventDispatcherOwner
import androidx.navigationevent.compose.LocalNavigationEventDispatcherOwner
import kotlin.test.Test
import kotlin.test.assertEquals

private data object DeferredRoot : NavKey
private data object DeferredEditor : NavKey

@OptIn(ExperimentalTestApi::class)
class NavDeferredBackTest {
    @Test
    fun controllerRetainsDirtyEditor_settlesBackAndAcceptsLaterPop() = runComposeUiTest {
        val owner = object : NavigationEventDispatcherOwner {
            override val navigationEventDispatcher = NavigationEventDispatcher()
        }
        val input = DirectNavigationEventInput().also { owner.navigationEventDispatcher.addInput(it) }
        val stack = navBackStackOf(DeferredRoot, DeferredEditor)
        var requested = 0
        var lifecycle: Lifecycle? = null
        setContent {
            CompositionLocalProvider(LocalNavigationEventDispatcherOwner provides owner) {
                NavDisplay(stack, effects = NavDisplayEffects.None, onBack = { requested++ }) {
                    entry<DeferredRoot> { Box(Modifier.fillMaxSize()) }
                    entry<DeferredEditor> {
                        lifecycle = LocalLifecycleOwner.current.lifecycle
                        Box(Modifier.fillMaxSize())
                    }
                }
            }
        }
        waitForIdle()
        runOnIdle { input.backStarted(NavigationEvent(progress = 0f)) }
        waitForIdle()
        runOnIdle { input.backProgressed(NavigationEvent(progress = 0.6f)) }
        waitForIdle()
        runOnIdle { input.backCompleted() }
        waitForIdle()
        assertEquals(1, requested)
        assertEquals(2, stack.size)
        assertEquals(Lifecycle.State.RESUMED, checkNotNull(lifecycle).currentState)
        // The confirmation/controller may acknowledge the pop on a later frame.
        runOnIdle { stack.removeAt(stack.lastIndex) }
        waitForIdle()
        assertEquals(listOf<NavKey>(DeferredRoot), stack.toList())
    }
}
