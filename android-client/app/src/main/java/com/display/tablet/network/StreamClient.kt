package com.display.tablet.network

import android.util.Log
import kotlinx.coroutines.*
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
    private val onFrameReceived: (ByteArray) -> Void?,
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

    fun start(scope: CoroutineScope) {
        if (isRunning) return
        isRunning = true

        job = scope.launch(Dispatchers.IO) {
            while (isRunning && isActive) {
                try {
                    onConnectionStateChanged(false, "Connecting to Mac on $host:$port (USB)...")
                    val s = Socket()
                    s.tcpNoDelay = true
                    s.connect(InetSocketAddress(host, port), 3000)
                    socket = s
                    outputStream = DataOutputStream(s.getOutputStream())
                    val dis = DataInputStream(s.getInputStream())

                    onConnectionStateChanged(true, "Connected to Mac Display Stream!")
                    Log.i(TAG, "Connected to $host:$port")

                    while (isRunning && isActive && !s.isClosed) {
                        val packetType = dis.readByte()
                        if (packetType == PACKET_VIDEO) {
                            val length = dis.readInt()
                            if (length in 1..20_000_000) {
                                val buffer = ByteArray(length)
                                dis.readFully(buffer)
                                onFrameReceived(buffer)
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
                    delay(1500) // Retry connection
                }
            }
        }
    }

    fun sendInput(action: Int, normX: Float, normY: Float, pressure: Float, toolType: Int) {
        val out = outputStream ?: return
        try {
            val bb = ByteBuffer.allocate(15).order(ByteOrder.BIG_ENDIAN)
            bb.put(PACKET_INPUT)
            bb.put(action.toByte())
            bb.putFloat(normX)
            bb.putFloat(normY)
            bb.putFloat(pressure)
            bb.put(toolType.toByte())

            synchronized(out) {
                out.write(bb.array())
                out.flush()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send input: ${e.message}")
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
        closeSocket()
    }
}
