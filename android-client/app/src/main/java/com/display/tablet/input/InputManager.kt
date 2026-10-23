package com.display.tablet.input

import android.view.MotionEvent
import android.view.View
import com.display.tablet.network.StreamClient

class InputManager(private val streamClient: StreamClient) {

    private var isTwoFingerScroll = false
    private var lastMidX = 0f
    private var lastMidY = 0f

    companion object {
        const val ACTION_DOWN = 0
        const val ACTION_MOVE = 1
        const val ACTION_UP = 2
        const val ACTION_SCROLL = 3
    }

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

        val pointerCount = event.pointerCount

        // Multi-touch: 2 fingers for natural trackpad scrolling
        if (pointerCount >= 2) {
            val midX = (event.getX(0) + event.getX(1)) / 2f
            val midY = (event.getY(0) + event.getY(1)) / 2f

            when (event.actionMasked) {
                MotionEvent.ACTION_POINTER_DOWN -> {
                    // Cancel any active 1-finger drag before starting 2-finger scroll
                    if (!isTwoFingerScroll) {
                        val normX = (event.getX(0) / width).coerceIn(0f, 1f)
                        val normY = (event.getY(0) / height).coerceIn(0f, 1f)
                        streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                        isTwoFingerScroll = true
                    }
                    lastMidX = midX
                    lastMidY = midY
                }
                MotionEvent.ACTION_MOVE -> {
                    if (isTwoFingerScroll) {
                        val deltaX = (midX - lastMidX) * 1.5f
                        val deltaY = (midY - lastMidY) * 1.5f
                        lastMidX = midX
                        lastMidY = midY

                        // Send scroll packet with pixel deltas
                        streamClient.sendInput(ACTION_SCROLL, deltaX, deltaY, 0f, 0)
                    } else {
                        lastMidX = midX
                        lastMidY = midY
                        isTwoFingerScroll = true
                    }
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    isTwoFingerScroll = false
                }
            }
            return
        }

        // Single finger / stylus touch interaction
        if (isTwoFingerScroll) {
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                isTwoFingerScroll = false
            }
            return
        }

        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> ACTION_DOWN
            MotionEvent.ACTION_MOVE -> ACTION_MOVE
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> ACTION_UP
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
