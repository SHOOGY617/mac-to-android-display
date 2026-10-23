import Foundation
import CoreGraphics

@main
struct MacDisplayHostApp {
    static func main() async {
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
        
        // Simple CLI argument parsing
        for i in 0..<args.count {
            if args[i] == "--fps", i + 1 < args.count, let val = Int32(args[i + 1]) { fps = val }
            if args[i] == "--width", i + 1 < args.count, let val = Int(args[i + 1]) { width = val }
            if args[i] == "--height", i + 1 < args.count, let val = Int(args[i + 1]) { height = val }
            if args[i] == "--port", i + 1 < args.count, let val = UInt16(args[i + 1]) { port = val }
            if args[i] == "--display", i + 1 < args.count, let val = Int(args[i + 1]) { displayIndex = val }
            if args[i] == "--bitrate", i + 1 < args.count, let val = Int32(args[i + 1]) { bitrate = val * 1_000_000 }
        }
        
        VirtualDisplayHelper.printDisplayInfo()
        
        print("Configuring Host:")
        print("  - Stream Resolution: \(width)x\(height)")
        print("  - Target Refresh Rate: \(fps) FPS")
        print("  - Target Bitrate: \(bitrate / 1_000_000) Mbps")
        print("  - Target Display Index: \(displayIndex)")
        print("  - USB/TCP Port: \(port)")
        print("------------------------------------------------------")
        
        let server = TCPServer(port: port)
        let encoder = H264Encoder(width: Int32(width), height: Int32(height), fps: fps, bitrate: bitrate)
        let capture = ScreenCaptureEngine(displayIndex: displayIndex, width: width, height: height, fps: fps)
        let inputSynthesizer = InputSynthesizer()
        
        // Connect Pipeline:
        // 1. Capture -> Encoder
        capture.onFrameCaptured = { pixelBuffer, pts in
            encoder.encode(pixelBuffer: pixelBuffer, presentationTimestamp: pts)
        }
        
        // 2. Encoder -> Server
        encoder.onNALUEncoded = { naluData in
            server.sendVideoFrame(naluData: naluData)
        }
        
        // 3. Server Input -> InputSynthesizer (Touch/S-Pen to Mac mouse/pen)
        server.onInputEventReceived = { inputEvent in
            inputSynthesizer.handleInput(event: inputEvent)
        }
        
        do {
            try server.start()
            try await capture.startCapture()
            print("\n[Host] Ready! Waiting for Galaxy Tab S7...")
            print("[Host] Make sure you ran: adb reverse tcp:\(port) tcp:\(port)")
            print("Press Ctrl+C to terminate.\n")
        } catch {
            print("[Host] Failed to start services: \(error.localizedDescription)")
            exit(1)
        }
        
        // Keep process running
        dispatchMain()
    }
}
