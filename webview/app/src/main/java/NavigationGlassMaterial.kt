package com.kyant.backdrop.catalog.components

import androidx.compose.ui.graphics.RenderEffect
import com.kyant.backdrop.BackdropEffectScope
import com.kyant.backdrop.isRuntimeShaderSupported

/** Shares material effect descriptions, never background pixels or shape-dependent refraction.
 * Owned by one navigation bar; each drawBackdrop still records its own padded source region.
 */
internal class NavigationGlassMaterial(private val adaptive: AdaptiveGlass) {
    private var initialized = false
    private var previousEnabled = false
    private var previousBlur = false
    private var previousStrength = 0f
    private var previousDensity = 0f
    private var previousLuminance = 0f
    private var materialEffect: RenderEffect? = null
    private var materialPadding = 0f

    fun BackdropEffectScope.applyMaterial(enabled: Boolean, blurEnabled: Boolean, strength: Float) {
        // Read every state dependency even on a hit, so both consuming nodes stay observed.
        val luminance = if (enabled && !isRuntimeShaderSupported()) adaptive.luminance.value else 0f
        // This cache describes the first stage only; preserve callers with an existing chain.
        if (renderEffect != null || padding != 0f) {
            with(adaptive) { material(enabled, blurEnabled, strength) }
            return
        }
        if (!initialized || previousEnabled != enabled || previousBlur != blurEnabled ||
            previousStrength != strength || previousDensity != density || previousLuminance != luminance) {
            with(adaptive) { material(enabled, blurEnabled, strength) }
            materialEffect = renderEffect
            materialPadding = padding
            previousEnabled = enabled
            previousBlur = blurEnabled
            previousStrength = strength
            previousDensity = density
            previousLuminance = luminance
            initialized = true
        } else {
            renderEffect = materialEffect
            padding = materialPadding
        }
    }
}
