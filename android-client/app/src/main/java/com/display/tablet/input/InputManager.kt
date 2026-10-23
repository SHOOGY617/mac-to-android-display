package com.display.tablet.input

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import com.display.tablet.network.StreamClient
import kotlin.math.abs
import kotlin.math.hypot

class InputManager(private val streamClient: StreamClient) {

    private val handler = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "InputManager"
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

    private var attachedView: View? = null

    // Single touch tracking
    private var downX = 0f
    private var downY = 0f
    private var isDragging = false
    private var hasMovedSignificantly = false
    private var isLongPressTriggered = false

    // Two-finger tracking
    private var isTwoFingerActive = false
    private var twoFingerStartTime = 0L
    private var twoFingerStartMidX = 0f
    private var twoFingerStartMidY = 0f
    private var twoFingerStartSpan = 0f
    private var lastMidX = 0f
    private var lastMidY = 0f
    private var lastSpan = 0f
    private var twoFingerMoved = false
    private var pinchAccumulator = 0f

    // Three-finger tracking
    private var isThreeFingerActive = false
    private var threeFingerStartX = 0f
    private var threeFingerStartY = 0f
    private var threeFingerSwiped = false
    private var lastThreeFingerEndTime = 0L

    // Guard against phantom multi-touch releases triggering taps
    private var multiTouchCooldown = false

    private val longPressRunnable = Runnable {
        if (!hasMovedSignificantly && !multiTouchCooldown && !isTwoFingerActive && !isThreeFingerActive) {
            isLongPressTriggered = true
            attachedView?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            val width = attachedView?.width?.toFloat() ?: 1f
            val height = attachedView?.height?.toFloat() ?: 1f
            val normX = (downX / width).coerceIn(0f, 1f)
            val normY = (downY / height).coerceIn(0f, 1f)
            Log.i(TAG, "Long-press triggered -> RIGHT CLICK at ($normX, $normY)")
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
            multiTouchCooldown = true
            isTwoFingerActive = false

            val centroidX = (event.getX(0) + event.getX(1) + event.getX(2)) / 3f
            val centroidY = (event.getY(0) + event.getY(1) + event.getY(2)) / 3f

            if (!isThreeFingerActive) {
                isThreeFingerActive = true
                threeFingerStartX = centroidX
                threeFingerStartY = centroidY
                threeFingerSwiped = false
                Log.d(TAG, "Three-finger gesture active at ($centroidX, $centroidY)")
            }

            if (event.actionMasked == MotionEvent.ACTION_MOVE && !threeFingerSwiped) {
                val deltaX = centroidX - threeFingerStartX
                val deltaY = centroidY - threeFingerStartY

                // Vertical gestures: swipe UP (Mission Control) or DOWN (App Exposé)
                if (abs(deltaY) > 85f && abs(deltaY) > 1.35f * abs(deltaX)) {
                    if (deltaY < -85f) {
                        Log.i(TAG, "⚡️ Swiped UP -> Mission Control (deltaY=$deltaY)")
                        streamClient.sendInput(ACTION_MISSION_CONTROL, 0f, 0f, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        threeFingerSwiped = true
                    } else if (deltaY > 85f) {
                        Log.i(TAG, "⚡️ Swiped DOWN -> App Exposé (deltaY=$deltaY)")
                        streamClient.sendInput(ACTION_APP_EXPOSE, 0f, 0f, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        threeFingerSwiped = true
                    }
                }
                // Horizontal gestures: swipe LEFT (Space Right) or RIGHT (Space Left)
                else if (abs(deltaX) > 95f && abs(deltaX) > 1.35f * abs(deltaY)) {
                    if (deltaX < -95f) {
                        Log.i(TAG, "⚡️ Swiped LEFT -> Switch Space Right (deltaX=$deltaX)")
                        streamClient.sendInput(ACTION_SWIPE_SPACES_RIGHT, 0f, 0f, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        threeFingerSwiped = true
                    } else if (deltaX > 95f) {
                        Log.i(TAG, "⚡️ Swiped RIGHT -> Switch Space Left (deltaX=$deltaX)")
                        streamClient.sendInput(ACTION_SWIPE_SPACES_LEFT, 0f, 0f, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        threeFingerSwiped = true
                    }
                }
            }
            return
        } else if (isThreeFingerActive) {
            isThreeFingerActive = false
            lastThreeFingerEndTime = System.currentTimeMillis()
            multiTouchCooldown = true // Lock out any 2-finger tap or 1-finger tap until all fingers leave
        }

        // ----------------------------------------------------
        // 2. TWO FINGERS: Pinch Zoom, Scroll, Right-Click Tap
        // ----------------------------------------------------
        if (pointerCount == 2) {
            handler.removeCallbacks(longPressRunnable)
            if (isDragging) {
                val normX = (downX / width).coerceIn(0f, 1f)
                val normY = (downY / height).coerceIn(0f, 1f)
                streamClient.sendInput(ACTION_UP, normX, normY, 0f, 0)
                isDragging = false
            }

            // If we just finished a 3-finger swipe, do not start 2-finger actions
            if (multiTouchCooldown) {
                return
            }

            val midX = (event.getX(0) + event.getX(1)) / 2f
            val midY = (event.getY(0) + event.getY(1)) / 2f
            val span = hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0))

            if (!isTwoFingerActive) {
                isTwoFingerActive = true
                twoFingerStartTime = System.currentTimeMillis()
                twoFingerStartMidX = midX
                twoFingerStartMidY = midY
                twoFingerStartSpan = span
                lastMidX = midX
                lastMidY = midY
                lastSpan = span
                twoFingerMoved = false
                pinchAccumulator = 0f
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    val dSpan = span - lastSpan
                    val dMidX = midX - lastMidX
                    val dMidY = midY - lastMidY
                    val dMidDist = hypot(dMidX, dMidY)

                    val totalSpanChange = abs(span - twoFingerStartSpan)
                    val totalMidDist = hypot(midX - twoFingerStartMidX, midY - twoFingerStartMidY)

                    if (totalSpanChange > 16f || totalMidDist > 16f) {
                        twoFingerMoved = true
                    }

                    // Dynamically prioritize Pinch-to-Zoom if finger distance changes
                    if (abs(dSpan) > 1.1f * dMidDist && abs(dSpan) > 1.8f) {
                        pinchAccumulator += dSpan
                        val zoomThreshold = 10f // Smooth step every 10px span change
                        if (abs(pinchAccumulator) >= zoomThreshold) {
                            val steps = (pinchAccumulator / zoomThreshold).toInt()
                            pinchAccumulator -= steps * zoomThreshold
                            val normX = (midX / width).coerceIn(0f, 1f)
                            val normY = (midY / height).coerceIn(0f, 1f)
                            streamClient.sendInput(ACTION_MAGNIFY, normX, normY, steps.toFloat(), 0)
                        }
                    } else if (dMidDist > 1.5f) {
                        // Natural 2D scroll
                        val deltaX = dMidX * 1.5f
                        val deltaY = dMidY * 1.5f
                        streamClient.sendInput(ACTION_SCROLL, deltaX, deltaY, 0f, 0)
                    }

                    lastMidX = midX
                    lastMidY = midY
                    lastSpan = span
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    val duration = System.currentTimeMillis() - twoFingerStartTime
                    val distMoved = hypot(lastMidX - twoFingerStartMidX, lastMidY - twoFingerStartMidY)
                    val spanMoved = abs(lastSpan - twoFingerStartSpan)

                    // Quick two-finger tap detection (<350ms with minimal travel) -> Right Click
                    if (!twoFingerMoved && duration < 350 && distMoved < 25f && spanMoved < 30f && !multiTouchCooldown) {
                        val normX = (twoFingerStartMidX / width).coerceIn(0f, 1f)
                        val normY = (twoFingerStartMidY / height).coerceIn(0f, 1f)
                        Log.i(TAG, "🖱️ Two-finger tap -> RIGHT CLICK at ($normX, $normY)")
                        streamClient.sendInput(ACTION_RIGHT_CLICK, normX, normY, 0f, 0)
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    }
                    isTwoFingerActive = false
                    multiTouchCooldown = true // Prevent trailing single finger click
                }
            }
            return
        } else {
            isTwoFingerActive = false
        }

        // ----------------------------------------------------
        // 3. SINGLE FINGER OR STYLUS
        // ----------------------------------------------------
        if (multiTouchCooldown) {
            // When all fingers leave the screen, reset multi-touch cooldown flag
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                multiTouchCooldown = false
                isThreeFingerActive = false
                isTwoFingerActive = false
            }
            return
        }

        val toolType = event.getToolType(0)
        val isMouseOrStylus = toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_MOUSE

        // Mouse or Stylus: bypass gesture detection for instantaneous native 1:1 hardware tracking
        if (isMouseOrStylus) {
            val action = when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> ACTION_DOWN
                MotionEvent.ACTION_MOVE -> ACTION_MOVE
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> ACTION_UP
                else -> return
            }
            val normX = (event.x / width).coerceIn(0f, 1f)
            val normY = (event.y / height).coerceIn(0f, 1f)
            val pressure = event.pressure.coerceIn(0f, 1f)
            streamClient.sendInput(action, normX, normY, pressure, if (toolType == MotionEvent.TOOL_TYPE_STYLUS) 1 else 0)
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
                // Minimal touch slop (7px) for instantaneous drag initiation without jitter
                if (travel > 7f) {
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
