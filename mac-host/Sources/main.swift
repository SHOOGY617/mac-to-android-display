import Foundation
import CoreGraphics
import AppKit

@main
struct MacDisplayHostApp {
    private static var virtualDisplayManager: VirtualDisplayManager?
    
    static func main() {
        print("======================================================")
        print("    Mac to Android Tablet Display Server (Tab S7)     ")
        print("======================================================")
        
        let args = ProcessInfo.processInfo.arguments
        
        var width: Int = 2560
        var height: Int = 1600
        var fps: Int32 = 60
        var port: UInt16 = 8080
        var displayIndex: Int = 0
        var bitrate: Int32 = 25_000_000
        var isExtended: Bool = false
        var hiDPI: Bool = true
        var displayName: String = "Galaxy Tab S7"
        var enableAudio: Bool = true
        var videoCodec: VideoCodec = .hevc
        
        // Simple CLI argument parsing
        for i in 0..<args.count {
            if args[i] == "--fps", i + 1 < args.count, let val = Int32(args[i + 1]) { fps = val }
            if args[i] == "--width", i + 1 < args.count, let val = Int(args[i + 1]) { width = val }
            if args[i] == "--height", i + 1 < args.count, let val = Int(args[i + 1]) { height = val }
            if args[i] == "--port", i + 1 < args.count, let val = UInt16(args[i + 1]) { port = val }
            if args[i] == "--display", i + 1 < args.count, let val = Int(args[i + 1]) { displayIndex = val }
            if args[i] == "--bitrate", i + 1 < args.count, let val = Int32(args[i + 1]) { bitrate = val * 1_000_000 }
            if args[i] == "--extended" || args[i] == "--extend" || args[i] == "--virtual" { isExtended = true }
            if args[i] == "--mirror" { isExtended = false }
            if args[i] == "--name", i + 1 < args.count { displayName = args[i + 1] }
            if args[i] == "--hidpi", i + 1 < args.count, let val = Bool(args[i + 1]) { hiDPI = val }
            if args[i] == "--no-audio" { enableAudio = false }
            if args[i] == "--audio" { enableAudio = true }
            if args[i] == "--codec", i + 1 < args.count {
                videoCodec = (args[i + 1].lowercased() == "h264" || args[i + 1].lowercased() == "avc") ? .h264 : .hevc
            }
            if args[i] == "--hevc" || args[i] == "--h265" { videoCodec = .hevc }
            if args[i] == "--h264" || args[i] == "--avc" { videoCodec = .h264 }
        }
        
        // Setup clean exit handling
        signal(SIGINT) { _ in
            print("\n[Host] Stopping server...")
            MacDisplayHostApp.virtualDisplayManager?.destroy()
            exit(0)
        }
        signal(SIGTERM) { _ in
            MacDisplayHostApp.virtualDisplayManager?.destroy()
            exit(0)
        }
        
        var targetDisplayID: CGDirectDisplayID? = nil
        
        if isExtended {
            print("\n[Host] Creating Native Virtual Display for Extended Desktop...")
            let vdm = VirtualDisplayManager()
            MacDisplayHostApp.virtualDisplayManager = vdm
            
            targetDisplayID = vdm.create(
                width: width,
                height: height,
                fps: Double(fps),
                hiDPI: hiDPI,
                name: displayName
            )
            
            guard targetDisplayID != nil else {
                print("[Host] Error: Failed to create virtual display. Falling back to mirror.")
                isExtended = false
                targetDisplayID = nil
                MacDisplayHostApp.virtualDisplayManager = nil
                return
            }
        }
        
        VirtualDisplayHelper.printDisplayInfo()
        
        print("Configuring Host:")
        print("  - Mode: \(isExtended ? "Extended Desktop (2nd Monitor)" : "Mirror Primary Screen")")
        print("  - Stream Resolution: \(width)x\(height)")
        print("  - Target Refresh Rate: \(fps) FPS")
        print("  - Target Bitrate: \(bitrate / 1_000_000) Mbps")
        print("  - Video Codec: \(videoCodec.rawValue.uppercased()) (Apple Silicon Hardware Accelerated)")
        print("  - Audio Streaming: \(enableAudio ? "Enabled (48kHz Stereo)" : "Disabled")")
        if let id = targetDisplayID {
            print("  - Target Virtual Display ID: \(id)")
        } else {
            print("  - Target Display Index: \(displayIndex)")
        }
        print("  - USB/TCP Port: \(port)")
        print("------------------------------------------------------")
        
        let server = TCPServer(port: port)
        let encoder = H264Encoder(width: Int32(width), height: Int32(height), fps: fps, bitrate: bitrate, codec: videoCodec)
        let capture = ScreenCaptureEngine(
            displayID: targetDisplayID,
            displayIndex: displayIndex,
            width: width,
            height: height,
            fps: fps,
            capturesAudio: enableAudio
        )
        let inputSynthesizer = InputSynthesizer(displayID: targetDisplayID)
        
        // Active pipeline state tracking
        var currentWidth = width
        var currentHeight = height
        var currentFPS = fps
        var currentCodec = videoCodec
        var isAudioActive = enableAudio
        
        // Initialize Menu Bar Companion App
        let menuBar = MenuBarManager(
            initialWidth: currentWidth,
            initialHeight: currentHeight,
            initialFPS: currentFPS,
            initialCodec: currentCodec,
            audioEnabled: isAudioActive
        )
        menuBar.setup()
        
        menuBar.onResolutionChanged = { newW, newH in
            print("\n[MenuBar] Resolution switched to: \(newW)x\(newH)")
            currentWidth = newW
            currentHeight = newH
            Task {
                MacDisplayHostApp.virtualDisplayManager?.setOrientation(
                    width: newW,
                    height: newH,
                    fps: Double(currentFPS)
                )
                try? await capture.updateResolution(width: newW, height: newH)
                encoder.updateResolution(width: Int32(newW), height: Int32(newH))
                if let id = targetDisplayID {
                    inputSynthesizer.updateDisplay(id: id)
                }
                menuBar.updateStats(fps: currentFPS, codec: currentCodec, width: newW, height: newH)
            }
        }
        
        menuBar.onRefreshRateChanged = { newFPS in
            print("\n[MenuBar] Refresh rate switched to: \(newFPS) FPS")
            currentFPS = newFPS
            Task {
                MacDisplayHostApp.virtualDisplayManager?.setOrientation(
                    width: currentWidth,
                    height: currentHeight,
                    fps: Double(newFPS)
                )
                try? await capture.updateFPS(fps: newFPS)
                encoder.updateFPS(fps: newFPS)
                menuBar.updateStats(fps: newFPS, codec: currentCodec, width: currentWidth, height: currentHeight)
            }
        }
        
        menuBar.onCodecChanged = { newCodec in
            print("\n[MenuBar] Video codec switched to: \(newCodec.rawValue.uppercased())")
            currentCodec = newCodec
            encoder.updateCodec(newCodec)
            menuBar.updateStats(fps: currentFPS, codec: newCodec, width: currentWidth, height: currentHeight)
        }
        
        menuBar.onAudioToggled = { enabled in
            print("\n[MenuBar] Audio streaming toggled: \(enabled ? "Enabled" : "Muted")")
            isAudioActive = enabled
            menuBar.updateStats(fps: currentFPS, codec: currentCodec, width: currentWidth, height: currentHeight)
        }
        
        menuBar.onQuitRequested = {
            print("\n[Host] Stopping server via Menu Bar...")
            MacDisplayHostApp.virtualDisplayManager?.destroy()
            exit(0)
        }
        
        // Connect Pipeline:
        // 1. Video: Capture -> Encoder
        var captureCount = 0
        capture.onFrameCaptured = { pixelBuffer, pts in
            captureCount += 1
            if captureCount <= 3 || captureCount % 60 == 0 {
                print("[Host] Frame captured #\(captureCount)")
            }
            encoder.encode(pixelBuffer: pixelBuffer, presentationTimestamp: pts)
        }
        
        // 2. Video: Encoder -> Server
        var encodedCount = 0
        encoder.onNALUEncoded = { naluData in
            encodedCount += 1
            if encodedCount <= 3 || encodedCount % 60 == 0 {
                print("[Host] NALU encoded #\(encodedCount), size: \(naluData.count) bytes")
            }
            server.sendVideoFrame(naluData: naluData, isHEVC: encoder.codec == .hevc)
        }

        // 3. Audio: Capture -> Server
        if enableAudio {
            var audioPacketCount = 0
            capture.onAudioCaptured = { pcmData in
                guard isAudioActive else { return }
                audioPacketCount += 1
                if audioPacketCount == 1 || audioPacketCount % 500 == 0 {
                    print("[Host] Audio packet #\(audioPacketCount), size: \(pcmData.count) bytes")
                }
                server.sendAudioFrame(pcmData: pcmData)
            }
        }
        
        // 4. Server Input -> InputSynthesizer (Touch/S-Pen to Mac mouse/pen)
        server.onInputEventReceived = { inputEvent in
            inputSynthesizer.handleInput(event: inputEvent)
        }
        
        // 5. Dynamic Orientation Changes (Landscape <-> Portrait)
        server.onOrientationChanged = { newWidth, newHeight in
            print("\n[Host] 🔄 Tablet orientation change received: \(newWidth)x\(newHeight)")
            currentWidth = Int(newWidth)
            currentHeight = Int(newHeight)
            menuBar.updateStats(fps: currentFPS, codec: currentCodec, width: currentWidth, height: currentHeight)
            Task {
                MacDisplayHostApp.virtualDisplayManager?.setOrientation(
                    width: Int(newWidth),
                    height: Int(newHeight),
                    fps: Double(currentFPS)
                )
                try? await capture.updateResolution(width: Int(newWidth), height: Int(newHeight))
                encoder.updateResolution(width: Int32(newWidth), height: Int32(newHeight))
                if let id = targetDisplayID {
                    inputSynthesizer.updateDisplay(id: id)
                }
            }
        }
        
        // 6. Client Connection status
        server.onClientConnected = {
            print("[Host] Tablet connected! Requesting immediate full keyframe from encoder...")
            menuBar.updateConnectionStatus(connected: true)
            encoder.requestKeyframe()
        }
        
        server.onClientDisconnected = {
            print("[Host] Tablet disconnected.")
            menuBar.updateConnectionStatus(connected: false)
        }
        
        Task {
            do {
                try server.start()
                try await capture.startCapture()
                print("\n[Host] Ready! Waiting for Galaxy Tab S7...")
                print("[Host] Make sure you ran: adb reverse tcp:\(port) tcp:\(port)")
                print("Press Ctrl+C or use the macOS Menu Bar item to terminate.\n")
            } catch {
                print("[Host] Failed to start services: \(error.localizedDescription)")
                MacDisplayHostApp.virtualDisplayManager?.destroy()
                exit(1)
            }
        }
        
        // Run Cocoa application event loop so Menu Bar item handles clicks and displays menus
        NSApplication.shared.run()
    }
}
