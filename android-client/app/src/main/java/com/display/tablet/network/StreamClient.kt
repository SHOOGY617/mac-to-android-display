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
    private val onFrameReceived: (ByteArray, Int) -> Unit,
    private val onConnectionStateChanged: (Boolean, String) -> Unit
) {
    companion object {
        private const val TAG = "StreamClient"
        private const val PACKET_VIDEO: Byte = 0x01
        private const val PACKET_INPUT: Byte = 0x10
    }

    private var socket: Socket? = null
    private var outputStream: DataOutputStream? = null
    private var isRunning = false
    private var job: Job? = null
    private var inputJob: Job? = null
    
    // Non-blocking input queue: touch events never block the UI thread
    private val inputChannel = Channel<ByteArray>(64)
    
    // Reusable buffer to eliminate 30MB/s of GC allocation churn
    private var frameBuffer = ByteArray(1024 * 512)

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
                        if (packetType == PACKET_VIDEO) {
                            val length = dis.readInt()
                            if (length in 1..20_000_000) {
                                if (length > frameBuffer.size) {
                                    frameBuffer = ByteArray(length + 64 * 1024)
                                }
                                dis.readFully(frameBuffer, 0, length)
                                onFrameReceived(frameBuffer, length)
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
