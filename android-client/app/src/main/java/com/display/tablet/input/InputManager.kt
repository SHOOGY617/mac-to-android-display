package com.display.tablet.input

import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import com.display.tablet.network.StreamClient
import kotlin.math.abs
import kotlin.math.hypot

class InputManager(private val streamClient: StreamClient) {

    private val handler = Handler(Looper.getMainLooper())

    companion object {
        const val ACTION_DOWN = 0
        const val ACTION_MOVE = 1
        const val ACTION_UP = 2
        const val ACTION_SCROLL = 3
        const val ACTION_RIGHT_CLICK = 4
        const val ACTION_MAGNIFY = 5
        const val ACTION_MISSION_CONTROL = 6
        const val ACTION_APP_EXPOSE = 7
        const val ACTION_SWIPE_SPACES_LEFT = 8
        const val ACTION_SWIPE_SPACES_RIGHT = 9
    }

    private enum class TwoFingerMode {
        UNDECIDED,
        SCROLL,
        PINCH,
        TAP_HANDLED
    }

    // View reference for haptic feedback
    private var attachedView: View? = null

    // Single touch tracking
    private var downX = 0f
    private var downY = 0f
    private var isDragging = false
    private var hasMovedSignificantly = false
    private var isLongPressTriggered = false

    // Multi-touch tracking
    private var twoFingerMode = TwoFingerMode.UNDECIDED
    private var twoFingerStartTime = 0L
    private var twoFingerStartMidX = 0f
    private var twoFingerStartMidY = 0f
    private var twoFingerStartSpan = 0f
    private var lastMidX = 0f
    private var lastMidY = 0f
    private var lastSpan = 0f
    private var multiTouchInProgress = false

    // Three-finger tracking
    private var threeFingerStartX = 0f
    private var threeFingerStartY = 0f
    private var threeFingerSwiped = false

    private val longPressRunnable = Runnable {
        if (!hasMovedSignificantly && !multiTouchInProgress) {
            isLongPressTriggered = true
            attachedView?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            val width = attachedView?.width?.toFloat() ?: 1f
            val height = attachedView?.height?.toFloat() ?: 1f
            val normX = (downX / width).coerceIn(0f, 1f)
            val normY = (downY / height).coerceIn(0f, 1f)
            streamClient.sendInput(ACTION_RIGHT_CLICK, normX, normY, 0f, 0)
        }
    }

    fun attachTo(view: View) {
        this.attachedView = view
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

        // ----------------------------------------------------
        // 1. THREE OR MORE FINGERS: Mission Control & Spaces
        // ----------------------------------------------------
        if (pointerCount >= 3) {
            handler.removeCallbacks(longPressRunnable)
            if (isDragging) {
                val normX = (downX / width).coerceIn(0f, 1f)
                val normY = (downY / height).coerceIn(0f, 1f)
                streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                isDragging = false
            }
            multiTouchInProgress = true

            val centroidX = (event.getX(0) + event.getX(1) + event.getX(2)) / 3f
            val centroidY = (event.getY(0) + event.getY(1) + event.getY(2)) / 3f

            when (event.actionMasked) {
                MotionEvent.ACTION_POINTER_DOWN -> {
                    threeFingerStartX = centroidX
                    threeFingerStartY = centroidY
                    threeFingerSwiped = false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!threeFingerSwiped) {
                        val deltaX = centroidX - threeFingerStartX
                        val deltaY = centroidY - threeFingerStartY
                        val threshold = 110f

                        if (abs(deltaY) > threshold && abs(deltaY) > 1.3f * abs(deltaX)) {
                            if (deltaY < -threshold) {
                                // 3-finger swipe UP: Mission Control
                                streamClient.sendInput(ACTION_MISSION_CONTROL, 0f, 0f, 0f, 0)
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                threeFingerSwiped = true
                            } else if (deltaY > threshold) {
                                // 3-finger swipe DOWN: App Exposé
                                streamClient.sendInput(ACTION_APP_EXPOSE, 0f, 0f, 0f, 0)
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                threeFingerSwiped = true
                            }
                        } else if (abs(deltaX) > threshold && abs(deltaX) > 1.3f * abs(deltaY)) {
                            if (deltaX < -threshold) {
                                // 3-finger swipe LEFT: Space to the right
                                streamClient.sendInput(ACTION_SWIPE_SPACES_RIGHT, 0f, 0f, 0f, 0)
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                threeFingerSwiped = true
                            } else if (deltaX > threshold) {
                                // 3-finger swipe RIGHT: Space to the left
                                streamClient.sendInput(ACTION_SWIPE_SPACES_LEFT, 0f, 0f, 0f, 0)
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                threeFingerSwiped = true
                            }
                        }
                    }
                }
            }
            return
        }

        // ----------------------------------------------------
        // 2. TWO FINGERS: Right-Click Tap, Scroll, Pinch Zoom
        // ----------------------------------------------------
        if (pointerCount == 2) {
            handler.removeCallbacks(longPressRunnable)
            if (isDragging) {
                val normX = (downX / width).coerceIn(0f, 1f)
                val normY = (downY / height).coerceIn(0f, 1f)
                streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                isDragging = false
            }
            multiTouchInProgress = true

            val midX = (event.getX(0) + event.getX(1)) / 2f
            val midY = (event.getY(0) + event.getY(1)) / 2f
            val span = hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0))

            when (event.actionMasked) {
                MotionEvent.ACTION_POINTER_DOWN -> {
                    twoFingerMode = TwoFingerMode.UNDECIDED
                    twoFingerStartTime = System.currentTimeMillis()
                    twoFingerStartMidX = midX
                    twoFingerStartMidY = midY
                    twoFingerStartSpan = span
                    lastMidX = midX
                    lastMidY = midY
                    lastSpan = span
                }
                MotionEvent.ACTION_MOVE -> {
                    val distMoved = hypot(midX - twoFingerStartMidX, midY - twoFingerStartMidY)
                    val spanDelta = abs(span - twoFingerStartSpan)

                    if (twoFingerMode == TwoFingerMode.UNDECIDED) {
                        if (distMoved > 20f || spanDelta > 28f) {
                            if (spanDelta > 1.3f * distMoved && spanDelta > 24f) {
                                twoFingerMode = TwoFingerMode.PINCH
                            } else {
                                twoFingerMode = TwoFingerMode.SCROLL
                            }
                        }
                    }

                    when (twoFingerMode) {
                        TwoFingerMode.SCROLL -> {
                            val deltaX = (midX - lastMidX) * 1.5f
                            val deltaY = (midY - lastMidY) * 1.5f
                            lastMidX = midX
                            lastMidY = midY
                            streamClient.sendInput(ACTION_SCROLL, deltaX, deltaY, 0f, 0)
                        }
                        TwoFingerMode.PINCH -> {
                            val zoomStep = (span - lastSpan) * 0.45f
                            lastSpan = span
                            lastMidX = midX
                            lastMidY = midY
                            val normX = (midX / width).coerceIn(0f, 1f)
                            val normY = (midY / height).coerceIn(0f, 1f)
                            streamClient.sendInput(ACTION_MAGNIFY, normX, normY, zoomStep, 0)
                        }
                        else -> {
                            lastMidX = midX
                            lastMidY = midY
                        }
                    }
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    val duration = System.currentTimeMillis() - twoFingerStartTime
                    val distMoved = hypot(lastMidX - twoFingerStartMidX, lastMidY - twoFingerStartMidY)
                    val spanMoved = abs(lastSpan - twoFingerStartSpan)

                    // Quick two-finger tap detection (<350ms with minimal travel) -> Right Click
                    if (twoFingerMode == TwoFingerMode.UNDECIDED && duration < 350 && distMoved < 25f && spanMoved < 30f) {
                        val normX = (twoFingerStartMidX / width).coerceIn(0f, 1f)
                        val normY = (twoFingerStartMidY / height).coerceIn(0f, 1f)
                        streamClient.sendInput(ACTION_RIGHT_CLICK, normX, normY, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        twoFingerMode = TwoFingerMode.TAP_HANDLED
                    }
                }
            }
            return
        }

        // ----------------------------------------------------
        // 3. SINGLE FINGER OR STYLUS
        // ----------------------------------------------------
        if (multiTouchInProgress) {
            // When all fingers leave the screen, reset multi-touch flag
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                multiTouchInProgress = false
                twoFingerMode = TwoFingerMode.UNDECIDED
                threeFingerSwiped = false
            }
            return
        }

        val isStylus = event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS

        // Stylus: bypass gesture detection for instantaneous low-latency drawing & writing
        if (isStylus) {
            val action = when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> ACTION_DOWN
                MotionEvent.ACTION_MOVE -> ACTION_MOVE
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> ACTION_UP
                else -> return
            }
            val normX = (event.x / width).coerceIn(0f, 1f)
            val normY = (event.y / height).coerceIn(0f, 1f)
            val pressure = event.pressure.coerceIn(0f, 1f)
            streamClient.sendInput(action, normX, normY, pressure, 1)
            return
        }

        // Single Finger Touch Handling (Tap, Drag, Long-Press Right-Click)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                isDragging = false
                hasMovedSignificantly = false
                isLongPressTriggered = false
                handler.postDelayed(longPressRunnable, 450)
            }
            MotionEvent.ACTION_MOVE -> {
                val travel = hypot(event.x - downX, event.y - downY)
                if (travel > 18f) {
                    if (!hasMovedSignificantly) {
                        hasMovedSignificantly = true
                        handler.removeCallbacks(longPressRunnable)
                        if (!isLongPressTriggered) {
                            val startNormX = (downX / width).coerceIn(0f, 1f)
                            val startNormY = (downY / height).coerceIn(0f, 1f)
                            streamClient.sendInput(ACTION_DOWN, startNormX, startNormY, 0f, 0)
                            isDragging = true
                        }
                    }
                    if (isDragging && !isLongPressTriggered) {
                        val normX = (event.x / width).coerceIn(0f, 1f)
                        val normY = (event.y / height).coerceIn(0f, 1f)
                        streamClient.sendInput(ACTION_MOVE, normX, normY, 0f, 0)
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                handler.removeCallbacks(longPressRunnable)
                if (isLongPressTriggered) {
                    isLongPressTriggered = false
                } else if (isDragging) {
                    val normX = (event.x / width).coerceIn(0f, 1f)
                    val normY = (event.y / height).coerceIn(0f, 1f)
                    streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                    isDragging = false
                } else {
                    // Crisp Single Tap
                    val normX = (downX / width).coerceIn(0f, 1f)
                    val normY = (downY / height).coerceIn(0f, 1f)
                    streamClient.sendInput(ACTION_DOWN, normX, normY, 0f, 0)
                    streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                handler.removeCallbacks(longPressRunnable)
                if (isDragging) {
                    val normX = (downX / width).coerceIn(0f, 1f)
                    val normY = (downY / height).coerceIn(0f, 1f)
                    streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                    isDragging = false
                }
                isLongPressTriggered = false
            }
        }
    }
}
