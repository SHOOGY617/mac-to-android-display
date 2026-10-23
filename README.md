# Mac to Galaxy Tab S7 Display Over USB

Turn your **Samsung Galaxy Tab S7** (or any modern Android tablet) into a high-performance, low-latency, 120Hz secondary display and drawing tablet for macOS over a USB cable.

---

## Architecture Overview

* **Host (`mac-host`)**: Native macOS application written in **Swift** using:
  * **ScreenCaptureKit** (macOS 13+) for zero-copy 60/120 FPS hardware capture.
  * **VideoToolbox** for real-time H.264 hardware encoding with Annex B NAL unit streaming.
  * **Network.framework** TCP server for high-throughput frame delivery.
  * **CoreGraphics (`CGEvent`)** for receiving tablet touch gestures and S-Pen pressure/tilt events.
* **Client (`android-client`)**: Native Android app written in **Kotlin** using:
  * **`SurfaceView`** for direct zero-copy GPU compositing.
  * **`MediaCodec`** configured in hardware low-latency mode (`KEY_LOW_LATENCY = 1`).
  * Automatic **120Hz refresh rate** activation for Galaxy Tab S7.
  * **Input listener** reporting touch and S-Pen pressure back to the Mac.
* **USB Transport**: Direct socket over USB via **`adb reverse`** (zero Wi-Fi lag, sub-millisecond transport latency).

---

## Prerequisites

1. **On your Mac**:
   * macOS 13 (Ventura) or newer.
   * Swift 5.9+ / Xcode Command Line Tools (`xcode-select --install`).
   * Android Platform Tools (`brew install android-platform-tools` for `adb`).
2. **On your Galaxy Tab S7**:
   * Enable **Developer Options** (Settings > About tablet > Software information > Tap "Build number" 7 times).
   * Enable **USB Debugging** (Settings > Developer options > USB debugging).
   * Connect the tablet to your Mac using a USB-C cable.

---

## Quick Start Guide

### Step 1: Forward the Port over USB

With your Galaxy Tab S7 plugged into your Mac, run:
```bash
adb devices
# Verify your device is listed

adb reverse tcp:8080 tcp:8080
```
*(This commands the Android tablet to route `localhost:8080` straight across the USB cable to your Mac).*

---

### Step 2: Build & Start the macOS Host

Open a terminal on your Mac and navigate to `mac-host`:
```bash
cd mac-host

# Build and run the server
swift run MacDisplayHost
```

#### Customizing Resolution, FPS & Bitrate:
```bash
# Example: 120 FPS streaming at 30 Mbps for Galaxy Tab S7
swift run MacDisplayHost --fps 120 --bitrate 30 --width 2560 --height 1600

# Target a secondary / virtual display (e.g. Display index 1)
swift run MacDisplayHost --display 1
```

> **Note**: On the first launch, macOS will prompt you to grant **Screen Recording** permissions in `System Settings > Privacy & Security > Screen Recording`.

---

### Step 3: Install & Launch the Android Client

Open the `android-client` folder in **Android Studio** or install via Gradle:
```bash
cd android-client
./gradlew installDebug
```
Open the **Mac Display** app on your Galaxy Tab S7. It will immediately connect to `localhost:8080` over the USB cable and start rendering the desktop at up to 120Hz!

---

## Extended Virtual Display (Using Tablet as 2nd Screen)

By default, `MacDisplayHost` captures display index `0` (mirroring your primary screen). To use your tablet as a true **extended monitor**:

### Option A: Open-Source Virtual Display (Recommended)
You can create an independent 2560×1600 virtual screen using [BetterDisplay CLI](https://github.com/waydabber/BetterDisplay):
```bash
# Create a virtual display matching Tab S7 16:10 aspect ratio
betterdisplaycli create -nam="Galaxy Tab S7" -res=2560x1600
```
Then run the host targeting that new display:
```bash
swift run MacDisplayHost --display 1
```

### Option B: Built-in macOS Native Screen Sharing Driver
You can also enable a virtual display using Apple's DriverKit `IOUserScreenshareDriver` or a dummy HDMI plug configured to 2560×1600.

---

## S-Pen & Touch Support

The app detects whether you are using your finger or the **S-Pen**:
* **Finger Touches**: Transmitted as mouse pointer clicks and drags.
* **S-Pen**: Transmitted with continuous **pressure sensitivity** (`tabletPointPressure`), enabling drawing in apps like Photoshop, Illustrator, Blender, and Affinity Photo on your Mac!
