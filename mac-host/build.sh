#!/bin/bash
set -e

echo "==> Compiling MacDisplayHost using swiftc..."

SDK_FLAGS=""
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
    SDK_FLAGS="-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
elif [ -n "$SDKROOT" ]; then
    SDK_FLAGS="-sdk $SDKROOT"
fi

swiftc $SDK_FLAGS -parse-as-library \
    Sources/Protocol/StreamProtocol.swift \
    Sources/Encoder/H264Encoder.swift \
    Sources/Capture/ScreenCaptureEngine.swift \
    Sources/Input/InputSynthesizer.swift \
    Sources/Server/TCPServer.swift \
    Sources/VirtualDisplay/VirtualDisplayHelper.swift \
    Sources/VirtualDisplay/VirtualDisplayManager.swift \
    Sources/main.swift \
    -o MacDisplayHost \
    -framework ScreenCaptureKit \
    -framework VideoToolbox \
    -framework CoreMedia \
    -framework CoreGraphics \
    -framework Network \
    -O

echo "==> Build successful! Run with: ./MacDisplayHost"
