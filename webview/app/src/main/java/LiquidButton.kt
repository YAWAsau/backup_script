package com.kyant.backdrop.catalog.components

import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.preferredFrameRate
import androidx.compose.ui.FrameRateCategory
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.catalog.components.GlassMaterial.capsuleRefraction
import com.kyant.backdrop.catalog.components.GlassMaterial.capsuleSurface
import com.kyant.backdrop.catalog.utils.InteractiveHighlight
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import io.github.yawasau.speedbackup.webview.safeLens as lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.shapes.Capsule

@Composable
fun LiquidButton(
    onClick: () -> Unit,
    backdrop: Backdrop,
    modifier: Modifier = Modifier,
    isInteractive: Boolean = true,
    adaptationKey: String = "button",
    enabled: Boolean = true,
    shape: Shape = Capsule(),
    horizontalPadding: Dp = 16.dp,
    isLightTheme: Boolean = !isSystemInDarkTheme(),
    tint: Color = Color.Unspecified,
    surfaceColor: Color = Color.Unspecified,
    content: @Composable RowScope.() -> Unit
) {
    val glassControls=GlassMaterial.LocalControls.current
    val blurEnabled=GlassMaterial.LocalBlurEnabled.current
    val adaptive=rememberAdaptiveGlass(isLightTheme,"button:"+adaptationKey)
    val samplingActive=GlassMaterial.LocalActive.current
    val animationScope=rememberCoroutineScope()
    // Keep gesture and drawing state on the same instance across theme changes.
    val latestLightTheme by rememberUpdatedState(isLightTheme)
    val interactiveHighlight=remember(animationScope) {
        InteractiveHighlight(animationScope,immediateCancel=true,consumeHorizontalDrag=true,lightSurface={latestLightTheme})
    }
    val buttonBackdrop=rememberLayerBackdrop()
    val combinedBackdrop=rememberCombinedBackdrop(backdrop,buttonBackdrop)
    val progress={if(isInteractive&&enabled)interactiveHighlight.pressProgress.coerceIn(0f,1f) else 0f}
    val opticallyActive by remember(enabled,isInteractive,interactiveHighlight) {
        derivedStateOf { enabled&&isInteractive&&interactiveHighlight.pressProgress>0.001f }
    }
    // Replace Backdrop's cached clipping outline only when the actual shape changes.
    key(shape) {
        Box(modifier.then(if(opticallyActive)Modifier.preferredFrameRate(FrameRateCategory.High) else Modifier).clickable(enabled=enabled,interactionSource=null,
            indication=if(isInteractive)null else LocalIndication.current,role=Role.Button,onClick=onClick)
            .then(if(isInteractive&&enabled)interactiveHighlight.gestureModifier else Modifier),
            propagateMinConstraints=true) {
            // Same blurred/refracted base as the bottom bar. Capture this one
            // button, including its label, for the same combined capsule sampling.
            Box(Modifier.then(if(opticallyActive)Modifier.layerBackdrop(buttonBackdrop) else Modifier),propagateMinConstraints=true) {
            // drawBackdrop already owns its clipped offscreen layer; avoid a second FBO.
            Box(Modifier.matchParentSize()
                .drawBackdrop(backdrop=backdrop,shape={shape},highlight={GlassMaterial.Rim},shadow=null,
                    effects={with(adaptive){material(glassControls.adaptive,blurEnabled,glassControls.blurStrength)};lens(GlassMaterial.LensDp.dp.toPx(),GlassMaterial.LensDp.dp.toPx()*glassControls.refraction/100f)},
                    onDrawBackdrop={draw->draw();if(glassControls.adaptive&&samplingActive){with(adaptive){capture(glassControls.sampleTick,draw)}}},
                    onDrawSurface={
                        drawRect((if(surfaceColor.isSpecified)surfaceColor else GlassMaterial.surface(isLightTheme)).copy(alpha=glassControls.opacity))
                        if(tint.isSpecified)drawRect(tint,blendMode=BlendMode.Hue)
                    }))
            Row(Modifier.clip(shape).then(if(isInteractive&&enabled)interactiveHighlight.modifier else Modifier)
                .height(48.dp).fillMaxWidth().padding(horizontal=horizontalPadding),
                horizontalArrangement=Arrangement.spacedBy(8.dp,Alignment.CenterHorizontally),
                verticalAlignment=Alignment.CenterVertically){
                    content()
                }
            }
            // The capsule optical layer shares all material functions with the
            // bottom selection. No translation or scaling of page controls.
            val capsule=if(opticallyActive)Modifier.drawBackdrop(
                backdrop=combinedBackdrop,shape={shape},
                effects={capsuleRefraction(progress(),strength=glassControls.refraction/100f)},
                highlight={GlassMaterial.capsuleHighlight(progress())},
                shadow={GlassMaterial.capsuleShadow(progress())},
                innerShadow={GlassMaterial.capsuleInnerShadow(progress())},
                layerBlock=null,
                onDrawSurface={capsuleSurface(isLightTheme,progress())}
            ) else Modifier.clip(shape).drawBehind {
                // At rest the capsule lens/highlight/shadows are all zero.
                // Sampling the base again is pixel-equivalent to this surface
                // over the already drawn base, without N redundant captures.
                capsuleSurface(isLightTheme,0f)
            }
            Box(Modifier.matchParentSize().then(capsule))
        }
    }
}
