package com.display.tablet.network

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

class StreamClient(
    private val host: String = "127.0.0.1",
    private val port: Int = 8080,
    private val onFrameReceived: (ByteArray, Int, String) -> Unit,
    private val onAudioReceived: ((ByteArray, Int) -> Unit)? = null,
    private val onConnectionStateChanged: (Boolean, String) -> Unit
) {
    companion object {
        private const val TAG = "StreamClient"
        private const val PACKET_VIDEO_H264: Byte = 0x01
        private const val PACKET_DISPLAY_INFO: Byte = 0x02
        private const val PACKET_AUDIO: Byte = 0x03
        private const val PACKET_VIDEO_HEVC: Byte = 0x04
        private const val PACKET_INPUT: Byte = 0x10
        private const val PACKET_ORIENTATION: Byte = 0x11
    }

    private var socket: Socket? = null
    private var outputStream: DataOutputStream? = null
    private var isRunning = false
    private var job: Job? = null
    private var inputJob: Job? = null
    
    // Non-blocking input queue: touch events never block the UI thread
    private val inputChannel = Channel<ByteArray>(64)
    
    // Reusable buffers to eliminate GC allocation churn
    private var frameBuffer = ByteArray(1024 * 512)
    private var audioBuffer = ByteArray(32 * 1024)

    fun start(scope: CoroutineScope) {
        if (isRunning) return
        isRunning = true

        // Dedicated background coroutine for sending touch inputs with sub-ms latency
        inputJob = scope.launch(Dispatchers.IO) {
            for (packet in inputChannel) {
                val out = outputStream ?: continue
                try {
                    out.write(packet)
                    out.flush()
                } catch (e: Exception) {
                    Log.w(TAG, "Input send error: ${e.message}")
                }
            }
        }

        job = scope.launch(Dispatchers.IO) {
            while (isRunning && isActive) {
                try {
                    onConnectionStateChanged(false, "Connecting to Mac on $host:$port (USB)...")
                    val s = Socket()
                    s.tcpNoDelay = true
                    s.setReceiveBufferSize(512 * 1024)
                    s.setSendBufferSize(64 * 1024)
                    s.connect(InetSocketAddress(host, port), 3000)
                    socket = s
                    outputStream = DataOutputStream(s.getOutputStream())
                    val dis = DataInputStream(s.getInputStream())

                    onConnectionStateChanged(true, "Connected to Mac Display Stream!")
                    Log.i(TAG, "Connected to $host:$port with TCP_NODELAY and zero-alloc buffer")

                    while (isRunning && isActive && !s.isClosed) {
                        val packetType = dis.readByte()
                        if (packetType == PACKET_VIDEO_H264 || packetType == PACKET_VIDEO_HEVC) {
                            val length = dis.readInt()
                            if (length in 1..20_000_000) {
                                if (length > frameBuffer.size) {
                                    frameBuffer = ByteArray(length + 64 * 1024)
                                }
                                dis.readFully(frameBuffer, 0, length)
                                val mimeType = if (packetType == PACKET_VIDEO_HEVC) {
                                    android.media.MediaFormat.MIMETYPE_VIDEO_HEVC
                                } else {
                                    android.media.MediaFormat.MIMETYPE_VIDEO_AVC
                                }
                                onFrameReceived(frameBuffer, length, mimeType)
                            }
                        } else if (packetType == PACKET_AUDIO) {
                            val length = dis.readInt()
                            if (length in 1..200_000) {
                                if (length > audioBuffer.size) {
                                    audioBuffer = ByteArray(length + 8 * 1024)
                                }
                                dis.readFully(audioBuffer, 0, length)
                                onAudioReceived?.invoke(audioBuffer, length)
                            }
                        }
                    }
                } catch (e: EOFException) {
                    Log.w(TAG, "Host closed connection: ${e.message}")
                    onConnectionStateChanged(false, "Host disconnected. Retrying...")
                } catch (e: Exception) {
                    Log.w(TAG, "Connection failed: ${e.message}")
                    onConnectionStateChanged(false, "Waiting for Host (adb reverse)...")
                } finally {
                    closeSocket()
                }

                if (isRunning && isActive) {
                    delay(1000) // Fast reconnect
                }
            }
        }
    }

    fun sendInput(action: Int, normX: Float, normY: Float, pressure: Float, toolType: Int) {
        try {
            val bb = ByteBuffer.allocate(15).order(ByteOrder.BIG_ENDIAN)
            bb.put(PACKET_INPUT)
            bb.put(action.toByte())
            bb.putFloat(normX)
            bb.putFloat(normY)
            bb.putFloat(pressure)
            bb.put(toolType.toByte())

            // Non-blocking trySend to keep touch response at 120Hz without UI thread stalls
            inputChannel.trySend(bb.array())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enqueue input: ${e.message}")
        }
    }

    fun sendOrientation(width: Int, height: Int) {
        try {
            val packet = ByteArray(9)
            packet[0] = PACKET_ORIENTATION
            packet[1] = (width ushr 24).toByte()
            packet[2] = (width ushr 16).toByte()
            packet[3] = (width ushr 8).toByte()
            packet[4] = width.toByte()
            packet[5] = (height ushr 24).toByte()
            packet[6] = (height ushr 16).toByte()
            packet[7] = (height ushr 8).toByte()
            packet[8] = height.toByte()

            inputChannel.trySend(packet)
            Log.i(TAG, "Sent orientation change to Mac: ${width}x${height}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send orientation: ${e.message}")
        }
    }

    private fun closeSocket() {
        try {
            outputStream = null
            socket?.close()
            socket = null
        } catch (_: Exception) {}
    }

    fun stop() {
        isRunning = false
        job?.cancel()
        inputJob?.cancel()
        closeSocket()
    }
}
