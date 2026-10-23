package com.display.tablet

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.display.tablet.decoder.H264Decoder
import com.display.tablet.input.InputManager
import com.display.tablet.network.StreamClient

class MainActivity : AppCompatActivity(), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView
    private lateinit var statusText: TextView
    private var decoder: H264Decoder? = null
    private var streamClient: StreamClient? = null
    private var inputManager: InputManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val rootLayout = FrameLayout(this)
        rootLayout.setBackgroundColor(Color.BLACK)

        surfaceView = SurfaceView(this)
        surfaceView.holder.addCallback(this)
        rootLayout.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        statusText = TextView(this).apply {
            text = "Waiting for Mac host...\nRun on Mac: adb reverse tcp:8080 tcp:8080"
            setTextColor(Color.WHITE)
            textSize = 16f
            setBackgroundColor(Color.argb(180, 20, 20, 20))
            setPadding(32, 24, 32, 24)
            gravity = Gravity.CENTER
        }
        val textParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
        }
        rootLayout.addView(statusText, textParams)

        setContentView(rootLayout)

        hideSystemUI()
        enable120HzRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUI()
        }
    }

    private fun enable120HzRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.post {
                val modes = display?.supportedModes ?: emptyArray()
                // Find 120Hz mode on Galaxy Tab S7
                val highFpsMode = modes.filter { it.refreshRate >= 119f }
                    .maxByOrNull { it.physicalWidth * it.physicalHeight }
                if (highFpsMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = highFpsMode.modeId
                    window.attributes = params
                }
            }
        }
    }

    private fun hideSystemUI() {
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
        controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        val dec = H264Decoder(holder.surface)
        dec.init(2560, 1600)
        this.decoder = dec

        val client = StreamClient(
            host = "127.0.0.1",
            port = 8080,
            onFrameReceived = { data ->
                dec.decodeNalu(data)
                null
            },
            onConnectionStateChanged = { connected, message ->
                runOnUiThread {
                    statusText.text = message
                    if (connected) {
                        statusText.animate().alpha(0f).setDuration(1000).start()
                    } else {
                        statusText.alpha = 1f
                    }
                }
            }
        )
        this.streamClient = client

        val input = InputManager(client)
        input.attachTo(surfaceView)
        this.inputManager = input

        client.start(lifecycleScope)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        streamClient?.stop()
        streamClient = null
        decoder?.release()
        decoder = null
    }

    override fun onDestroy() {
        super.onDestroy()
        streamClient?.stop()
        decoder?.release()
    }
}
