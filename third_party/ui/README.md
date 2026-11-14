# v1079 native UI

The runtime now uses native Compose components. Legacy browser HTML/JS/CSS implementations below are historical provenance only and are no longer shipped or served. See APP_LIST_WEB.md and native UI source.

# WebUI fonts and motion references

Version1025 uses the device system font. OPPO Sans assets and font download routes have been removed.


Web button rendering is a CSS adaptation inspired by Kyant0/AndroidLiquidGlass LiquidButton: translucent tint, Gaussian blur, specular highlight and press expansion. It does not claim to run the native Compose runtime lens shader in WebView.
Reference commit: 65ab177e90e5c1d8c62e70cf7755841982da65f6, Apache-2.0; license included.
https://github.com/Kyant0/AndroidLiquidGlass

Motion adapted from lumkit/Tweak-Alpha navigation and damped drag parameters into Web Animations: 400ms FastOutSlowIn; press release spring stiffness250/damping .6. UI rendering is independent WebUI code, not a Compose runtime dependency. v1025 tab navigation uses matched full-width translations; shorter generic entrance effects remain for other panels and dialogs.
Reference commit: 785261ce45b028ef36d477055d6bdc0b787b26c1, GPL-3.0; license included.
https://github.com/lumkit/Tweak-Alpha

Reduced motion/hidden document disables and cancels UI animation. Gaussian blur is limited to visible controls and the single modal backdrop; app rows are not individually blurred. Main worker and progress update cadence remain unchanged.



Button tint uses 40% surface/primary color, following Tweak-Alpha BlurX.kt glassBlur surface alpha .4, with 8px Gaussian blur. Selected buttons retain a primary border and theme text for legibility; pressed tint is 55%. CSS alpha is multiplied by the source theme color alpha.

Version1024 adds held press tracking, damped release (stiffness250/damping.6), bounded drag and moving/stretching bottom-tab lens inspired by the supplied Tweak-Alpha recording. Optical refraction uses an independently generated local128x128 displacement texture in SVG backdrop filtering, active only while held. This is not the upstream AGSL shader; WebView support is validated with a pixel-difference probe. Transitions do not delay actions. Outgoing clones are inert, stripped of IDs and names, pointer-disabled, and removed after400ms.

The themed path picker follows Tweak-Alpha FilePickerScreen's folder navigation and cross-folder selection interaction. Its implementation is independent WebUI plus a token-authenticated read-only Rust directory endpoint, not an embedded Compose file manager. Custom_path selects directories to preserve existing media backup semantics; Output_path is a single directory and list_location a single file. No shell execution, recursive enumeration or automatic settings save is performed by browsing.

Version1025 uses matched400ms full-width page translation for both outgoing/incoming tab pages and swipe completion. No page crossfade or shrink overlaps text. The pressed nav lens stretches1.32x horizontally and1.26x vertically; text scales1.2x. Its tint is16% surface instead of26% primary, and refraction is confined to the lens. These remain WebView approximations, not the native AGSL renderer.

The nav blur is a sibling pseudo-layer, not an ancestor backdrop-filter, so the selected lens can sample the actual page backdrop. A dedicated selected-lens pixel probe checks displacement separately from ordinary held buttons. Footer stacking stays above outgoing page ghosts.


Version 1087: SafeLens.kt and SafeLensShaders.kt adapt the Apache-2.0 lens implementation from Kyant Backdrop 2.0.1 (Copyright 2025 Kyant). The shader guards zero-length normals at inner rounded-rectangle boundaries and at the center; public Backdrop effect APIs retain effect chaining and shader caching. Original refraction and dispersion formulas remain.

Version 1098: Light/dark semantic colors follow the standard Miuix theme approach used by KernelSU manager (reference commit 730f644615969cfd4a84b45d7f62a667b7b95a50, manager/app/src/main/java/me/weishu/kernelsu/ui/theme/MiuixTheme.kt). This uses the existing Miuix dependency, with independent wallpaper contrast and surface treatments; no KernelSU source was copied.
