package com.kyant.backdrop.catalog.utils

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.util.fastFirstOrNull
import kotlin.math.abs

suspend fun PointerInputScope.inspectDragGestures(
    consumeHorizontalDrag: Boolean = false,
    gesturePosition: (Offset) -> Offset = { it },
    onDragStart: (down: PointerInputChange) -> Unit = {},
    onDragEnd: (change: PointerInputChange) -> Unit = {},
    onDragCancel: () -> Unit = {},
    onDrag: (change: PointerInputChange, dragAmount: Offset) -> Unit
) {
    awaitEachGesture {
        val initialDown = awaitFirstDown(false, PointerEventPass.Initial)
        // A scrolling ancestor may consume DOWN to stop a fling. This gesture
        // cannot become a click: do not show a glass press or capture its drag.
        // Check in Initial, before the button's own clickable consumes Main.
        if (consumeHorizontalDrag && initialDown.isConsumed) return@awaitEachGesture

        val down = awaitFirstDown(false)
        val drag = initialDown

        onDragStart(down)
        onDrag(drag, Offset.Zero)
        if(consumeHorizontalDrag) {
            val gestureStart = gesturePosition(down.position)
            var completed=false
            var horizontal=false
            try {
                while(true) {
                    // Inner button receives Main before clickable and pager.
                    val change=awaitPointerEvent(PointerEventPass.Main).changes.fastFirstOrNull{it.id==down.id}
                    if(change==null || (change.isConsumed&&!horizontal)){onDragCancel();completed=true;break}
                    // Layout motion is not finger motion. A stationary tap during a
                    // pager spring changes local coordinates without being a drag.
                    val delta=gesturePosition(change.position)-gestureStart
                    if(!horizontal && (abs(delta.x)>viewConfiguration.touchSlop || abs(delta.y)>viewConfiguration.touchSlop)) {
                        if(abs(delta.x)>abs(delta.y))horizontal=true
                        else {onDragCancel();completed=true;break} // vertical list keeps ownership
                    }
                    if(change.changedToUpIgnoreConsumed()) {
                        if(horizontal)change.consume() // dragging is never a click
                        onDragEnd(change);completed=true;break
                    }
                    val movement=change.positionChange() // Capture before consumption zeroes positionChange().
                    if(horizontal)change.consume()
                    val finalChange=awaitPointerEvent(PointerEventPass.Final).changes.fastFirstOrNull{it.id==down.id}
                    if(!horizontal&&finalChange?.isConsumed==true){onDragCancel();completed=true;break}
                    onDrag(change,movement)
                }
            } finally {if(!completed)onDragCancel()}
            return@awaitEachGesture
        }
        var completed=false
        try {
        val upEvent =
            drag(
                pointerId = drag.id,
                onDrag = { onDrag(it, it.positionChange()) }
            )
        if (upEvent == null) {
            onDragCancel()
        } else {
            onDragEnd(upEvent)
        }
        completed=true
        } finally { if(!completed)onDragCancel() }
    }
}

private suspend inline fun AwaitPointerEventScope.drag(
    pointerId: PointerId,
    onDrag: (PointerInputChange) -> Unit
): PointerInputChange? {
    val isPointerUp = currentEvent.changes.fastFirstOrNull { it.id == pointerId }?.pressed != true
    if (isPointerUp) {
        return null
    }
    var pointer = pointerId
    while (true) {
        val change = awaitDragOrUp(pointer) ?: return null
        if (change.isConsumed) {
            return null
        }
        if (change.changedToUpIgnoreConsumed()) {
            return change
        }
        onDrag(change)
        pointer = change.id
    }
}

private suspend inline fun AwaitPointerEventScope.awaitDragOrUp(
    pointerId: PointerId
): PointerInputChange? {
    var pointer = pointerId
    while (true) {
        val event = awaitPointerEvent()
        val dragEvent = event.changes.fastFirstOrNull { it.id == pointer } ?: return null
        if (dragEvent.changedToUpIgnoreConsumed()) {
            val otherDown = event.changes.fastFirstOrNull { it.pressed }
            if (otherDown == null) {
                return dragEvent
            } else {
                pointer = otherDown.id
            }
        } else {
            val hasDragged = dragEvent.previousPosition != dragEvent.position
            if (hasDragged) {
                return dragEvent
            }
        }
    }
}
