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

`MacDisplayHost` has built-in support for creating an independent, native macOS virtual screen without needing any third-party drivers or dummy plugs!

### Built-in Native Extended Display (Recommended)
Simply pass the `--extended` flag:
```bash
# Launch server with an independent 2560x1600 virtual screen at 60/120Hz
./mac-host/MacDisplayHost --extended

# Custom FPS or Bitrate:
./mac-host/MacDisplayHost --extended --fps 120 --bitrate 30
```
macOS will immediately register a secondary monitor named **"Galaxy Tab S7"** in **System Settings > Displays**, allowing you to drag windows onto the tablet and arrange its position relative to your Mac.

### Mirror Mode
To mirror your primary display instead:
```bash
./mac-host/MacDisplayHost --mirror
```

---

## Touch Gestures & S-Pen Support

The system provides full trackpad-grade multi-touch gestures and hardware stylus passthrough:

### Multi-Touch Gestures (No S-Pen Needed)
* **Single Tap**: Instant crisp primary left-click under your finger (`leftMouseDown` / `leftMouseUp` with AppKit `clickState = 1`).
* **Tap & Drag**: Smooth window dragging, text selection, and UI slider adjustments at 120Hz.
* **Long Press (Hold 450ms)**: Right-click context menu at finger location with haptic tick.
* **Two-Finger Tap**: Secondary right-click at the midpoint between fingers.
* **Two-Finger Drag**: Natural 2D scrolling (vertical + horizontal) with momentum.
* **Two-Finger Pinch / Spread**: Smooth zoom in / zoom out centered at your pinch focal point.
* **Three-Finger Swipe Up**: Trigger **Mission Control** (`Ctrl + ↑`).
* **Three-Finger Swipe Down**: Trigger **App Exposé / Application Windows** (`Ctrl + ↓`).
* **Three-Finger Swipe Left**: Switch to **Next Desktop / Space** (`Ctrl + →`).
* **Three-Finger Swipe Right**: Switch to **Previous Desktop / Space** (`Ctrl + ←`).

### S-Pen / Stylus
* Automatic detection bypassing gesture delays for direct low-latency pen tracking.
* Continuous **pressure sensitivity** (`tabletPointPressure`), enabling drawing in Photoshop, Illustrator, Blender, and Affinity Photo on macOS.
