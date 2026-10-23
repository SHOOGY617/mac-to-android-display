#!/bin/bash
set -e

echo "==> Compiling MacDisplayHost using swiftc directly..."

swiftc \
    Sources/Protocol/StreamProtocol.swift \
    Sources/Encoder/H264Encoder.swift \
    Sources/Capture/ScreenCaptureEngine.swift \
    Sources/Input/InputSynthesizer.swift \
    Sources/Server/TCPServer.swift \
    Sources/VirtualDisplay/VirtualDisplayHelper.swift \
    Sources/main.swift \
    -o MacDisplayHost \
    -framework ScreenCaptureKit \
    -framework VideoToolbox \
    -framework CoreMedia \
    -framework CoreGraphics \
    -framework Network \
    -O

echo "==> Build successful! Run with: ./MacDisplayHost"
