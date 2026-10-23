package com.display.tablet.input

import android.view.MotionEvent
import android.view.View
import com.display.tablet.network.StreamClient

class InputManager(private val streamClient: StreamClient) {

    fun attachTo(view: View) {
        view.setOnTouchListener { v, event ->
            handleMotionEvent(v, event)
            true
        }
    }

    private fun handleMotionEvent(view: View, event: MotionEvent) {
        val width = view.width.toFloat()
        val height = view.height.toFloat()
        if (width <= 0 || height <= 0) return

        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> 0
            MotionEvent.ACTION_MOVE -> 1
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 2
            else -> return
        }

        val normX = (event.x / width).coerceIn(0f, 1f)
        val normY = (event.y / height).coerceIn(0f, 1f)
        val pressure = event.pressure.coerceIn(0f, 1f)

        val isStylus = event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS
        val toolType = if (isStylus) 1 else 0

        streamClient.sendInput(action, normX, normY, pressure, toolType)
    }
}
