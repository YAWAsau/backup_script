package com.kyant.backdrop.catalog.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.preferredFrameRate
import androidx.compose.ui.FrameRateCategory
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastCoerceIn
import androidx.compose.ui.util.fastRoundToInt
import androidx.compose.ui.util.lerp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.catalog.components.GlassMaterial.capsuleRefraction
import com.kyant.backdrop.catalog.components.GlassMaterial.capsuleSurface
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.catalog.utils.DampedDragAnimation
import com.kyant.backdrop.catalog.utils.InteractiveHighlight
import com.kyant.backdrop.drawBackdrop
import io.github.yawasau.speedbackup.webview.safeLens as lens
import com.kyant.backdrop.highlight.Highlight
import com.kyant.shapes.Capsule
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sign

@Composable
fun LiquidBottomTabs(
    selectedTabIndex: () -> Int,
    onTabSelected: (index: Int) -> Unit,
    backdrop: Backdrop,
    tabsCount: Int,
    selectableTabs: Int = tabsCount,
    pageDragPosition: () -> Float? = { null },
    isLightTheme: Boolean = !isSystemInDarkTheme(),
    accentColor: Color = if (isLightTheme) Color(0xFF0088FF) else Color(0xFF0091FF),
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit
) {
    val glassControls=GlassMaterial.LocalControls.current
    val blurEnabled=GlassMaterial.LocalBlurEnabled.current
    val adaptive=rememberAdaptiveGlass(isLightTheme,"navigation")
    val samplingActive=GlassMaterial.LocalActive.current
    val containerColor = GlassMaterial.surface(isLightTheme).copy(alpha=glassControls.opacity)

    val tabsBackdrop = rememberLayerBackdrop()

    BoxWithConstraints(
        modifier,
        contentAlignment = Alignment.CenterStart
    ) {
        val density = LocalDensity.current
        val tabWidth = with(density) {
            (constraints.maxWidth.toFloat() - 8f.dp.toPx()) / tabsCount
        }

        val panelOffset = 0f

        val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
        val animationScope = rememberCoroutineScope()
        val externalIndex=selectedTabIndex()
        val latestExternal by rememberUpdatedState(externalIndex)
        val selectLatest by rememberUpdatedState(onTabSelected)
        val dampedDragAnimation = remember(animationScope,tabWidth,selectableTabs,isLtr) {
            DampedDragAnimation(
                animationScope = animationScope,
                initialValue = selectedTabIndex().toFloat(),
                valueRange = 0f..(selectableTabs - 1).toFloat(),
                visibilityThreshold = 0.001f,
                initialScale = 1f,
                pressedScale = 78f / 56f,
                onDragStarted = {},
                onDragStopped = {
                    val targetIndex = targetValue.fastRoundToInt().fastCoerceIn(0, selectableTabs - 1)
                    selectLatest(targetIndex)
                    animateToValue(targetIndex.toFloat())
                    animationScope.launch {
                        kotlinx.coroutines.delay(250)
                        if(latestExternal!=targetIndex)animateToValue(latestExternal.toFloat())

                    }
                },
                onDrag = { _, dragAmount ->
                    updateValue(
                        (targetValue + dragAmount.x / tabWidth * if (isLtr) 1f else -1f)
                            .fastCoerceIn(0f, (selectableTabs - 1).toFloat())
                    )
                }
            )
        }
        val capsuleActive by remember(dampedDragAnimation){derivedStateOf{dampedDragAnimation.pressProgress>0.001f}}
        val latestPageDrag by rememberUpdatedState(pageDragPosition)
        LaunchedEffect(dampedDragAnimation,externalIndex) {
            snapshotFlow { latestPageDrag() }.collectLatest { position ->
                if(position!=null)dampedDragAnimation.updateValue(position)
                else dampedDragAnimation.animateToValue(externalIndex.toFloat())
            }
        }

        val interactiveHighlight = remember(animationScope) {
            InteractiveHighlight(
                animationScope = animationScope,
                position = { size, offset ->
                    Offset(
                        if (isLtr) (dampedDragAnimation.value + 0.5f) * tabWidth + panelOffset
                        else size.width - (dampedDragAnimation.value + 0.5f) * tabWidth + panelOffset,
                        size.height / 2f
                    )
                }
            )
        }

        Row(
            Modifier.then(if(capsuleActive)Modifier.preferredFrameRate(FrameRateCategory.High) else Modifier)
                .graphicsLayer {
                    translationX = panelOffset
                }
                .drawBackdrop(
                    backdrop = backdrop,
                    shape = { Capsule() },
                    highlight = { GlassMaterial.Rim },
                    shadow = null,
                    effects = {
                        with(adaptive){material(glassControls.adaptive,blurEnabled,glassControls.blurStrength)}
                        lens(GlassMaterial.LensDp.dp.toPx(), GlassMaterial.LensDp.dp.toPx()*glassControls.refraction/100f)
                    },
                    layerBlock = {
                        val progress = dampedDragAnimation.pressProgress
                        val scale = lerp(1f, 1f + 16f.dp.toPx() / size.width, progress)
                        scaleX = scale
                        scaleY = scale
                    },
                    onDrawBackdrop={draw->draw();if(glassControls.adaptive&&samplingActive){with(adaptive){capture(glassControls.sampleTick,draw)}}},
                    onDrawSurface = { drawRect(containerColor) }
                )
                .then(interactiveHighlight.modifier)
                .height(64f.dp)
                .fillMaxWidth()
                .padding(4f.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = {content()}
        )

        CompositionLocalProvider(
            LocalLiquidBottomTabScale provides {
                lerp(1f, 1.2f, dampedDragAnimation.pressProgress)
            }
        ) {
            Row(
                Modifier
                    .clearAndSetSemantics {}
                    .alpha(0f)
                    .layerBackdrop(tabsBackdrop)
                    .graphicsLayer {
                        translationX = panelOffset
                    }
                    .drawBackdrop(
                        backdrop = backdrop,
                        shape = { Capsule() },
                        effects = {
                            val progress = dampedDragAnimation.pressProgress
                            // The selection lens must sample the same material as the bar.
                            with(adaptive){material(glassControls.adaptive,blurEnabled,glassControls.blurStrength)}
                            lens(
                                24f.dp.toPx() * progress,
                                24f.dp.toPx() * progress * glassControls.refraction/100f
                            )
                        },
                        highlight = {
                            val progress = dampedDragAnimation.pressProgress
                            GlassMaterial.capsuleHighlight(progress)
                        },
                        onDrawSurface = { drawRect(containerColor) }
                    )
                    .then(interactiveHighlight.modifier)
                    .height(56f.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 4f.dp)
                    .graphicsLayer(colorFilter = ColorFilter.tint(accentColor)),
                verticalAlignment = Alignment.CenterVertically,
                content = {content()}
            )
        }

        Box(
            Modifier
                .padding(horizontal = 4f.dp)
                .graphicsLayer {
                    translationX =
                        if (isLtr) dampedDragAnimation.value * tabWidth + panelOffset
                        else size.width - (dampedDragAnimation.value + 1f) * tabWidth + panelOffset
                }
                .then(interactiveHighlight.gestureModifier)
                .then(dampedDragAnimation.modifier)
                .drawBackdrop(
                    backdrop = rememberCombinedBackdrop(backdrop, tabsBackdrop),
                    shape = { Capsule() },
                    effects = {
                        val progress = dampedDragAnimation.pressProgress
                        capsuleRefraction(progress,strength=glassControls.refraction/100f)
                    },
                    highlight = {
                        val progress = dampedDragAnimation.pressProgress
                        GlassMaterial.capsuleHighlight(progress)
                    },
                    shadow = {
                        val progress = dampedDragAnimation.pressProgress
                        GlassMaterial.capsuleShadow(progress)
                    },
                    innerShadow = {
                        val progress = dampedDragAnimation.pressProgress
                        GlassMaterial.capsuleInnerShadow(progress)
                    },
                    layerBlock = {
                        scaleX = dampedDragAnimation.scaleX
                        scaleY = dampedDragAnimation.scaleY
                        val velocity = dampedDragAnimation.velocity / 10f
                        scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                        scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                    },
                    onDrawSurface = {
                        val progress = dampedDragAnimation.pressProgress
                        capsuleSurface(isLightTheme,progress)
                    }
                )
                .height(56f.dp)
                .fillMaxWidth(1f / tabsCount)
        )
    }
}
