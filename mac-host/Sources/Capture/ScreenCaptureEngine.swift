import Foundation
import ScreenCaptureKit
import CoreMedia

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let targetFPS: Int32
    private let targetWidth: Int
    private let targetHeight: Int
    private let displayIndex: Int
    
    public var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    
    private let captureQueue = DispatchQueue(label: "com.display.captureQueue", qos: .userInteractive)
    
    public init(displayIndex: Int = 0, width: Int = 2560, height: Int = 1600, fps: Int32 = 60) {
        self.displayIndex = displayIndex
        self.targetWidth = width
        self.targetHeight = height
        self.targetFPS = fps
        super.init()
    }
    
    public func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard !content.displays.isEmpty else {
            throw NSError(domain: "ScreenCaptureEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found"])
        }
        
        let selectedDisplay = displayIndex < content.displays.count ? content.displays[displayIndex] : content.displays[0]
        print("[Capture] Selected Display: ID \(selectedDisplay.displayID), Resolution \(selectedDisplay.width)x\(selectedDisplay.height)")
        
        let filter = SCContentFilter(display: selectedDisplay, excludingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = targetWidth
        config.height = targetHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: targetFPS)
        config.queueDepth = 3
        config.showsCursor = true
        // NV12 format is hardware native for VideoToolbox H.264 encoder
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
    
    public func stop() async {
        if let stream = stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }
}
