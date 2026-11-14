package com.kyant.backdrop.catalog.utils

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.util.fastCoerceIn
import com.kyant.backdrop.RuntimeShader
import com.kyant.backdrop.asComposeShader
import com.kyant.backdrop.isRuntimeShaderSupported
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

class InteractiveHighlight(
    val animationScope: CoroutineScope,
    val immediateCancel: Boolean = false,
    val consumeHorizontalDrag: Boolean = false,
    val lightSurface: () -> Boolean = { false },
    val position: (size: Size, offset: Offset) -> Offset = { _, offset -> offset }
) {

    private val pressProgressAnimationSpec =
        spring(0.5f, 300f, 0.001f)
    private val positionAnimationSpec =
        spring(0.5f, 300f, Offset.VisibilityThreshold)

    private val pressProgressAnimation =
        Animatable(0f, 0.001f)
    private val positionAnimation =
        Animatable(Offset.Zero, Offset.VectorConverter, Offset.VisibilityThreshold)

    private var gestureCoordinates: LayoutCoordinates? = null
    private var startPosition = Offset.Zero
    val pressProgress: Float get() = pressProgressAnimation.value
    val offset: Offset get() = positionAnimation.value - startPosition

    private val shader =
        if (isRuntimeShaderSupported()) {
            RuntimeShader(
                """
uniform float2 size;
layout(color) uniform half4 color;
uniform float radius;
uniform float2 position;

half4 main(float2 coord) {
    float dist = distance(coord, position);
    float intensity = smoothstep(radius, radius * 0.5, dist);
    return color * intensity;
}"""
            )
        } else {
            null
        }

    val modifier: Modifier =
        Modifier.drawWithContent {
            val progress = pressProgressAnimation.value
            val isLightSurface=lightSurface()
            val feedbackColor=if(isLightSurface)Color.Black else Color.White
            val feedbackBlend=if(isLightSurface)BlendMode.SrcOver else BlendMode.Plus
            if (progress > 0f) {
                if (shader != null) {
                    drawRect(
                        feedbackColor.copy((if(isLightSurface).05f else .08f) * progress),
                        blendMode = feedbackBlend
                    )
                    shader.apply {
                        val position = position(size, positionAnimation.value)
                        setFloatUniform("size", size.width, size.height)
                        setColorUniform("color", feedbackColor.copy((if(isLightSurface).12f else .15f) * progress))
                        setFloatUniform("radius", size.minDimension * 1.5f)
                        setFloatUniform(
                            "position",
                            position.x.fastCoerceIn(0f, size.width),
                            position.y.fastCoerceIn(0f, size.height)
                        )
                    }
                    drawRect(
                        ShaderBrush(shader.asComposeShader()),
                        blendMode = feedbackBlend
                    )
                } else {
                    drawRect(
                        feedbackColor.copy((if(isLightSurface).17f else .25f) * progress),
                        blendMode = feedbackBlend
                    )
                }
            }

            drawContent()
        }

    val gestureModifier: Modifier =
        Modifier.then(if(consumeHorizontalDrag)Modifier.onGloballyPositioned { gestureCoordinates = it } else Modifier).pointerInput(animationScope) {
            inspectDragGestures(
                consumeHorizontalDrag = consumeHorizontalDrag,
                gesturePosition = { local ->
                    val coordinates=gestureCoordinates
                    if(coordinates?.isAttached==true)coordinates.localToRoot(local) else local
                },
                onDragStart = { down ->
                    startPosition = down.position
                    animationScope.launch {
                        launch { pressProgressAnimation.animateTo(1f, pressProgressAnimationSpec) }
                        launch { positionAnimation.snapTo(startPosition) }
                    }
                },
                onDragEnd = {
                    animationScope.launch {
                        launch { pressProgressAnimation.animateTo(0f, pressProgressAnimationSpec) }
                        launch { positionAnimation.animateTo(startPosition, positionAnimationSpec) }
                    }
                },
                onDragCancel = {
                    animationScope.launch {
                        if(immediateCancel) {
                            launch { pressProgressAnimation.snapTo(0f) }
                            launch { positionAnimation.snapTo(startPosition) }
                        } else {
                            launch { pressProgressAnimation.animateTo(0f, pressProgressAnimationSpec) }
                            launch { positionAnimation.animateTo(startPosition, positionAnimationSpec) }
                        }
                    }
                }

            ) { change, _ ->
                animationScope.launch { positionAnimation.snapTo(change.position) }
            }
        }
}
