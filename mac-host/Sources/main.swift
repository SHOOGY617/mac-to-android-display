import Foundation
import CoreGraphics

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
        if let id = targetDisplayID {
            print("  - Target Virtual Display ID: \(id)")
        } else {
            print("  - Target Display Index: \(displayIndex)")
        }
        print("  - USB/TCP Port: \(port)")
        print("------------------------------------------------------")
        
        let server = TCPServer(port: port)
        let encoder = H264Encoder(width: Int32(width), height: Int32(height), fps: fps, bitrate: bitrate)
        let capture = ScreenCaptureEngine(
            displayID: targetDisplayID,
            displayIndex: displayIndex,
            width: width,
            height: height,
            fps: fps
        )
        let inputSynthesizer = InputSynthesizer(displayID: targetDisplayID)
        
        // Connect Pipeline:
        // 1. Capture -> Encoder
        var captureCount = 0
        capture.onFrameCaptured = { pixelBuffer, pts in
            captureCount += 1
            if captureCount <= 3 || captureCount % 60 == 0 {
                print("[Host] Frame captured #\(captureCount)")
            }
            encoder.encode(pixelBuffer: pixelBuffer, presentationTimestamp: pts)
        }
        
        // 2. Encoder -> Server
        var encodedCount = 0
        encoder.onNALUEncoded = { naluData in
            encodedCount += 1
            if encodedCount <= 3 || encodedCount % 60 == 0 {
                print("[Host] NALU encoded #\(encodedCount), size: \(naluData.count) bytes")
            }
            server.sendVideoFrame(naluData: naluData)
        }
        
        // 3. Server Input -> InputSynthesizer (Touch/S-Pen to Mac mouse/pen)
        server.onInputEventReceived = { inputEvent in
            inputSynthesizer.handleInput(event: inputEvent)
        }
        inputSynthesizer.onSpaceChanged = {
            print("[Host] Space changed! Requesting immediate full keyframe...")
            encoder.requestKeyframe()
        }
        
        // 4. Force full keyframe when tablet connects
        server.onClientConnected = {
            print("[Host] Tablet connected! Requesting immediate full keyframe from encoder...")
            encoder.requestKeyframe()
        }
        
        Task {
            do {
                try server.start()
                try await capture.startCapture()
                print("\n[Host] Ready! Waiting for Galaxy Tab S7...")
                print("[Host] Make sure you ran: adb reverse tcp:\(port) tcp:\(port)")
                print("Press Ctrl+C to terminate.\n")
            } catch {
                print("[Host] Failed to start services: \(error.localizedDescription)")
                MacDisplayHostApp.virtualDisplayManager?.destroy()
                exit(1)
            }
        }
        
        // Run main runloop to keep process alive and pump virtual display events
        RunLoop.main.run()
    }
}
