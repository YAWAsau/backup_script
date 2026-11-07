package io.github.yawasau.speedbackup.webview

import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.unit.Density
import com.kyant.backdrop.Backdrop

/** Shared viewport sampling across WebView and outer Compose owners, without exceptions. */
internal class GlassWindowBackdrop(private val layer:GraphicsLayer,private val origin:()->LayoutCoordinates?):Backdrop {
    override val isCoordinatesDependent=true
    private val inverse=GlassInverseLayerScope()
    override fun DrawScope.drawBackdrop(density:Density,coordinates:LayoutCoordinates?,layerBlock:(GraphicsLayerScope.()->Unit)?) {
        val source=origin()?:return
        if(coordinates==null||!coordinates.isAttached||!source.isAttached)return
        val offset=coordinates.positionOnScreen()-source.positionOnScreen()
        withTransform({
            if(layerBlock!=null){inverse.reset();with(inverse){inverseTransform(density,layerBlock)}}
            translate(-offset.x,-offset.y)
        }) { drawLayer(layer) }
    }
}
