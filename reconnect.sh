#!/bin/bash
# Reconnect helper for USB disconnect/reconnect

echo "[ADB] Checking connected devices..."
adb wait-for-device
echo "[ADB] Establishing port forwarding (tcp:8080 -> tcp:8080)..."
adb reverse tcp:8080 tcp:8080
if [ $? -eq 0 ]; then
    echo "[ADB] Successfully reversed port 8080! The tablet will reconnect immediately."
else
    echo "[ADB] Failed to reverse port. Make sure USB debugging is authorized on your Galaxy Tab."
fi
