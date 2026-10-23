package com.display.tablet.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log

class AudioRenderer(
    private val sampleRate: Int = 48000,
    private val channels: Int = 2
) {
    companion object {
        private const val TAG = "AudioRenderer"
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false

    fun start() {
        try {
            val channelMask = AudioFormat.CHANNEL_OUT_STEREO
            val encoding = AudioFormat.ENCODING_PCM_16BIT
            val minBufSize = AudioTrack.getMinBufferSize(sampleRate, channelMask, encoding)
            // Use ~40ms buffer to guarantee zero audio underruns while maintaining ultra-low latency (<20ms)
            val bufferSize = (minBufSize * 2).coerceAtLeast(sampleRate * channels * 2 * 40 / 1000)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelMask)
                        .setEncoding(encoding)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()

            track.play()
            this.audioTrack = track
            this.isPlaying = true
            Log.i(TAG, "AudioTrack started: ${sampleRate}Hz stereo low-latency (bufferSize=$bufferSize)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AudioTrack: ${e.message}", e)
        }
    }

    fun playPcm(data: ByteArray, offset: Int = 0, length: Int = data.size) {
        val track = audioTrack ?: return
        if (!isPlaying) return

        try {
            track.write(data, offset, length, AudioTrack.WRITE_NON_BLOCKING)
        } catch (e: Exception) {
            Log.e(TAG, "Error playing audio: ${e.message}")
        }
    }

    fun stop() {
        try {
            isPlaying = false
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
            audioTrack = null
            Log.i(TAG, "AudioTrack stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AudioTrack: ${e.message}")
        }
    }
}
