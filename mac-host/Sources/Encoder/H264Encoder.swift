import Foundation
import VideoToolbox
import CoreMedia

public final class H264Encoder {
    private var compressionSession: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private let fps: Int32
    private let bitrate: Int32
    
    public var onNALUEncoded: ((Data) -> Void)?
    private var forceNextKeyframe = true
    
    private let startCode = Data([0x00, 0x00, 0x00, 0x01])
    private var spsData: Data?
    private var ppsData: Data?
    
    public init(width: Int32, height: Int32, fps: Int32 = 60, bitrate: Int32 = 25_000_000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        setupSession()
    }
    
    deinit {
        stop()
    }
    
    private func setupSession() {
        let callback: VTCompressionOutputCallback = { outputCallbackRefCon, _, status, flags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else {
                return
            }
            let encoder = Unmanaged<H264Encoder>.fromOpaque(refCon).takeUnretainedValue()
            encoder.handleSampleBuffer(sampleBuffer, flags: flags)
        }
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("[Encoder] Failed to create VTCompressionSession: \(status)")
            return
        }
        
        // Optimize for ultra-low latency real-time streaming
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        // Disallow B-frames for zero reordering latency
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        // Disable encoder lookahead frames for zero lookahead delay
        VTSessionSetProperty(session, key: "LookAheadFrames" as CFString, value: 0 as CFNumber)
        // Prioritize hardware encoding speed over multi-pass compression
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[Encoder] H.264 Encoder initialized: \(width)x\(height) @ \(fps)fps, \(bitrate / 1_000_000) Mbps")
    }
    
    public func requestKeyframe() {
        forceNextKeyframe = true
    }
    
    public func encode(pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        guard let session = compressionSession else { return }
        
        var frameProps: [CFString: Any] = [:]
        if forceNextKeyframe {
            frameProps[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue
            forceNextKeyframe = false
        }
        
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: CMTime(value: 1, timescale: fps),
            frameProperties: frameProps.isEmpty ? nil : (frameProps as CFDictionary),
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        
        if status != noErr {
            print("[Encoder] Failed to encode frame: \(status)")
        }
    }
    
    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, flags: VTEncodeInfoFlags) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        let isKeyframe = !CFDictionaryContainsKey(
            unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false), 0), to: CFDictionary.self),
            Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
        )
        
        var packetData = Data()
        
        // On keyframes, extract and prepend SPS and PPS in Annex B format
        if isKeyframe {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var parameterSetCount = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
                
                for i in 0..<parameterSetCount {
                    var pointer: UnsafePointer<UInt8>?
                    var size: Int = 0
                    let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        formatDesc,
                        parameterSetIndex: i,
                        parameterSetPointerOut: &pointer,
                        parameterSetSizeOut: &size,
                        parameterSetCountOut: nil,
                        nalUnitHeaderLengthOut: nil
                    )
                    if status == noErr, let ptr = pointer, size > 0 {
                        packetData.append(startCode)
                        packetData.append(ptr, count: size)
                    }
                }
            }
        }
        
        // Extract NALUs from AVCC container (4-byte length prefix -> 0x00 00 00 01 start code)
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        guard status == noErr, let basePtr = dataPointer else { return }
        
        var offset = 0
        while offset < totalLength - 4 {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, basePtr + offset, 4)
            naluLength = CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue) ? UInt32(bigEndian: naluLength) : naluLength
            offset += 4
            
            if offset + Int(naluLength) <= totalLength {
                packetData.append(startCode)
                packetData.append(Data(bytes: basePtr + offset, count: Int(naluLength)))
                offset += Int(naluLength)
            } else {
                break
            }
        }
        
        if !packetData.isEmpty {
            onNALUEncoded?(packetData)
        }
    }
    
    public func stop() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
}
