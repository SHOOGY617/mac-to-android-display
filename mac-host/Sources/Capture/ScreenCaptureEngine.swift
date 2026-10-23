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
    private let capturesAudio: Bool
    
    public var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    public var onAudioCaptured: ((Data) -> Void)?
    
    private let captureQueue = DispatchQueue(label: "com.display.captureQueue", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.display.audioQueue", qos: .userInteractive)
    
    public init(displayID: CGDirectDisplayID? = nil, displayIndex: Int = 0, width: Int = 2560, height: Int = 1600, fps: Int32 = 60, capturesAudio: Bool = true) {
        self.targetDisplayID = displayID
        self.displayIndex = displayIndex
        self.targetWidth = width
        self.targetHeight = height
        self.targetFPS = fps
        self.capturesAudio = capturesAudio
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
        
        if capturesAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
        }
        
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        if capturesAudio {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        
        try await scStream.startCapture()
        self.stream = scStream
        print("[Capture] Screen capture started successfully at \(targetWidth)x\(targetHeight) @ \(targetFPS)fps (Audio: \(capturesAudio ? "48kHz Stereo" : "Disabled"))")
    }
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen {
            guard sampleBuffer.isValid,
                  let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            onFrameCaptured?(imageBuffer, pts)
        } else if type == .audio {
            handleAudioSampleBuffer(sampleBuffer)
        }
    }
    
    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }
        
        var bufferListSizeNeeded: Int = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        
        guard bufferListSizeNeeded > 0 else { return }
        let bufferListRaw = UnsafeMutableRawPointer.allocate(byteCount: bufferListSizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListRaw.deallocate() }
        
        let bufferListPtr = bufferListRaw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPtr,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else { return }
        
        let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        var pcm16Data = Data(count: numSamples * 4) // 2 channels * 2 bytes = 4 bytes per frame
        
        if audioBufferList.count >= 2,
           let leftData = audioBufferList[0].mData,
           let rightData = audioBufferList[1].mData {
            let leftFloats = leftData.assumingMemoryBound(to: Float32.self)
            let rightFloats = rightData.assumingMemoryBound(to: Float32.self)
            pcm16Data.withUnsafeMutableBytes { rawBuf in
                let int16Ptr = rawBuf.bindMemory(to: Int16.self)
                for i in 0..<numSamples {
                    let left = max(-1.0, min(1.0, leftFloats[i]))
                    let right = max(-1.0, min(1.0, rightFloats[i]))
                    int16Ptr[i * 2] = Int16(left * 32767.0)
                    int16Ptr[i * 2 + 1] = Int16(right * 32767.0)
                }
            }
        } else if audioBufferList.count == 1,
                  let monoData = audioBufferList[0].mData {
            let monoFloats = monoData.assumingMemoryBound(to: Float32.self)
            pcm16Data.withUnsafeMutableBytes { rawBuf in
                let int16Ptr = rawBuf.bindMemory(to: Int16.self)
                for i in 0..<numSamples {
                    let sample = max(-1.0, min(1.0, monoFloats[i]))
                    let int16 = Int16(sample * 32767.0)
                    int16Ptr[i * 2] = int16
                    int16Ptr[i * 2 + 1] = int16
                }
            }
        } else {
            return
        }
        
        onAudioCaptured?(pcm16Data)
    }
    
    public func updateResolution(width: Int, height: Int) async throws {
        guard let stream = stream else { return }
        let newConfig = SCStreamConfiguration()
        newConfig.width = width
        newConfig.height = height
        newConfig.minimumFrameInterval = CMTime(value: 1, timescale: targetFPS)
        newConfig.queueDepth = 3
        newConfig.showsCursor = true
        newConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if capturesAudio {
            newConfig.capturesAudio = true
            newConfig.sampleRate = 48000
            newConfig.channelCount = 2
            newConfig.excludesCurrentProcessAudio = true
        }
        try await stream.updateConfiguration(newConfig)
        print("[Capture] 🔄 Updated capture resolution to \(width)x\(height)")
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
