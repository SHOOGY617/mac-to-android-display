package com.display.tablet.decoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface

typealias VideoDecoder = H264Decoder

class H264Decoder(private val surface: Surface) {
    companion object {
        private const val TAG = "VideoDecoder"
    }

    private var codec: MediaCodec? = null
    private var isConfigured = false
    private var currentMimeType: String = ""
    private var currentWidth: Int = 2560
    private var currentHeight: Int = 1600
    private val bufferInfo = MediaCodec.BufferInfo()

    fun init(width: Int = 2560, height: Int = 1600, mimeType: String = MediaFormat.MIMETYPE_VIDEO_HEVC) {
        if (isConfigured && currentMimeType == mimeType && currentWidth == width && currentHeight == height) {
            return
        }
        
        release()

        try {
            this.currentWidth = width
            this.currentHeight = height
            this.currentMimeType = mimeType

            val format = MediaFormat.createVideoFormat(mimeType, width, height)
            
            // Android 11+ Low latency configuration
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            
            val decoder = MediaCodec.createDecoderByType(mimeType)
            decoder.configure(format, surface, null, 0)
            decoder.start()
            this.codec = decoder
            this.isConfigured = true
            val codecName = if (mimeType == MediaFormat.MIMETYPE_VIDEO_HEVC) "H.265 / HEVC" else "H.264 / AVC"
            Log.i(TAG, "Hardware $codecName Decoder initialized for ${width}x${height} with low latency")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize MediaCodec ($mimeType): ${e.message}", e)
        }
    }

    fun decodeNalu(data: ByteArray, length: Int = data.size, mimeType: String = currentMimeType, presentationTimeUs: Long = System.nanoTime() / 1000) {
        if (!isConfigured || (mimeType.isNotEmpty() && mimeType != currentMimeType)) {
            init(currentWidth, currentHeight, if (mimeType.isNotEmpty()) mimeType else MediaFormat.MIMETYPE_VIDEO_HEVC)
        }

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
