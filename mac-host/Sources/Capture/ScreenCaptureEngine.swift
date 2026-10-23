import Foundation
import ScreenCaptureKit
import CoreMedia

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let targetFPS: Int32
    private let targetWidth: Int
    private let targetHeight: Int
    private let displayIndex: Int
    private let targetDisplayID: CGDirectDisplayID?
    
    public var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    
    private let captureQueue = DispatchQueue(label: "com.display.captureQueue", qos: .userInteractive)
    
    public init(displayID: CGDirectDisplayID? = nil, displayIndex: Int = 0, width: Int = 2560, height: Int = 1600, fps: Int32 = 60) {
        self.targetDisplayID = displayID
        self.displayIndex = displayIndex
        self.targetWidth = width
        self.targetHeight = height
        self.targetFPS = fps
        super.init()
    }
    
    public func startCapture() async throws {
        var content: SCShareableContent?
        var selectedDisplay: SCDisplay?
        
        // Retry for up to 2 seconds if looking for a specific displayID
        for _ in 0..<15 {
            let candidate = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let targetID = targetDisplayID {
                if let matched = candidate.displays.first(where: { $0.displayID == targetID }) {
                    content = candidate
                    selectedDisplay = matched
                    break
                }
            } else if !candidate.displays.isEmpty {
                content = candidate
                selectedDisplay = displayIndex < candidate.displays.count ? candidate.displays[displayIndex] : candidate.displays[0]
                break
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        
        guard content != nil, let displayToCapture = selectedDisplay else {
            throw NSError(
                domain: "ScreenCaptureEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Target display \(targetDisplayID.map { "ID \($0)" } ?? "index \(displayIndex)") not found"]
            )
        }
        
        print("[Capture] Selected Display: ID \(displayToCapture.displayID), Resolution: \(displayToCapture.width)x\(displayToCapture.height)")
        
        let filter = SCContentFilter(display: displayToCapture, excludingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = targetWidth
        config.height = targetHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: targetFPS)
        config.queueDepth = 3
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        
        try await scStream.startCapture()
        self.stream = scStream
        print("[Capture] Screen capture started successfully at \(targetWidth)x\(targetHeight) @ \(targetFPS)fps")
    }
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrameCaptured?(imageBuffer, pts)
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Capture] SCStream stopped with error: \(error.localizedDescription)")
    }
    
    public func stop() async {
        if let stream = stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }
}
