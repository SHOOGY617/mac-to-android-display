package com.display.tablet.decoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface

class H264Decoder(private val surface: Surface) {
    companion object {
        private const val TAG = "H264Decoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
    }

    private var codec: MediaCodec? = null
    private var isConfigured = false
    private val bufferInfo = MediaCodec.BufferInfo()

    fun init(width: Int = 2560, height: Int = 1600) {
        try {
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height)
            
            // Android 11+ Low latency configuration
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            
            val decoder = MediaCodec.createDecoderByType(MIME_TYPE)
            decoder.configure(format, surface, null, 0)
            decoder.start()
            this.codec = decoder
            this.isConfigured = true
            Log.i(TAG, "Hardware H264 Decoder initialized for ${width}x${height} with low latency")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize MediaCodec: ${e.message}", e)
        }
    }

    fun decodeNalu(data: ByteArray, length: Int = data.size, presentationTimeUs: Long = System.nanoTime() / 1000) {
        val decoder = codec ?: return
        if (!isConfigured) return

        try {
            val inputIndex = decoder.dequeueInputBuffer(10_000) // 10ms timeout
            if (inputIndex >= 0) {
                val inputBuffer = decoder.getInputBuffer(inputIndex)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    inputBuffer.put(data, 0, length)
                    decoder.queueInputBuffer(
                        inputIndex,
                        0,
                        length,
                        presentationTimeUs,
                        0
                    )
                }
            }

            // Immediately drain available output buffers to display on Surface
            drainOutputBuffers(decoder)
        } catch (e: Exception) {
            Log.e(TAG, "Decode error: ${e.message}")
        }
    }

    private fun drainOutputBuffers(decoder: MediaCodec) {
        var outputIndex = decoder.dequeueOutputBuffer(bufferInfo, 0)
        while (outputIndex >= 0) {
            // true renders directly to the bound Surface with zero CPU copy!
            decoder.releaseOutputBuffer(outputIndex, true)
            outputIndex = decoder.dequeueOutputBuffer(bufferInfo, 0)
        }
    }

    fun release() {
        try {
            isConfigured = false
            codec?.stop()
            codec?.release()
            codec = null
            Log.i(TAG, "Decoder released")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing decoder: ${e.message}")
        }
    }
}
