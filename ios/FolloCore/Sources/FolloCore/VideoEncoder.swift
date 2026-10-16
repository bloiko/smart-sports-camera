import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

/// Own H.264 encoder on VideoToolbox (system framework) for the live stream: replaces the encoder inside HaishinKit and
/// gives us the encoded frames themselves (for the network-drop buffer and our own RTMP client).
/// No B-frames (decode order = presentation order: simple RTMP timestamps), a keyframe every `keyIntervalS`,
/// average bitrate with a hard cap of `peakFactor` × bitrate over one second.
public final class VideoEncoder: @unchecked Sendable {     // VideoToolbox calls back on its own thread
    public struct Settings: Equatable {
        public var width = 1920, height = 1080, bitrate = 4_500_000, fps = 30.0, keyIntervalS = 2.0, peakFactor = 1.5
        public init() {}
    }

    /// One encoded picture: AVCC payload (4-byte length + NAL unit, repeated), timestamps, keyframe flag, and the format
    /// description that carries SPS/PPS (needed for the stream header).
    public struct Frame {
        public let data: Data
        public let pts: CMTime
        public let isKey: Bool
        public let format: CMFormatDescription
    }

    public private(set) var settings: Settings
    public var onFrame: ((Frame) -> Void)?
    public private(set) var encoded = 0, dropped = 0
    private var session: VTCompressionSession?
    private let lock = NSLock()

    public init(_ s: Settings) throws {
        settings = s
        var sess: VTCompressionSession?
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(s.width), height: Int32(s.height), codecType: kCMVideoCodecType_H264,
                                            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                            outputCallback: nil, refcon: nil, compressionSessionOut: &sess)
        guard st == noErr, let sess else { throw NSError(domain: "VideoEncoder", code: Int(st), userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionCreate \(st)"]) }
        session = sess
        func set(_ k: CFString, _ v: CFTypeRef) { VTSessionSetProperty(sess, key: k, value: v) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, s.keyIntervalS as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, Int(s.fps * s.keyIntervalS) as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, s.fps as CFNumber)
        // HD colour: BT.709 conversion from our BGRA frames and the same tags in the stream (VUI), so YouTube and players
        // decode the colours we meant (untagged, VideoToolbox and ffmpeg disagreed by ~6 dB PSNR on identical frames)
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        applyBitrate(s.bitrate)
        VTCompressionSessionPrepareToEncodeFrames(sess)
    }

    deinit { if let s = session { VTCompressionSessionInvalidate(s) } }

    private func applyBitrate(_ b: Int) {
        guard let s = session else { return }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: b as CFNumber)
        let bytesPerSecond = Double(b) * settings.peakFactor / 8
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits, value: [bytesPerSecond, 1.0] as CFArray)
    }

    /// Adaptive bitrate steps (weak network, heat) change the bitrate without a new session.
    public func setBitrate(_ b: Int) { settings.bitrate = b; applyBitrate(b) }

    /// Encode one 1920×1080 frame (BGRA or NV12). Output arrives through `onFrame`, in order, on a VideoToolbox thread.
    public func encode(_ pb: CVPixelBuffer, pts: CMTime, forceKey: Bool = false) {
        guard let s = session else { return }
        let props: CFDictionary? = forceKey ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(s, imageBuffer: pb, presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: CMTimeScale(settings.fps.rounded())),
                                        frameProperties: props, infoFlagsOut: nil) { [weak self] status, flags, sb in
            guard let self else { return }
            guard status == noErr, let sb, !flags.contains(.frameDropped), let fmt = sb.formatDescription,
                  let bb = sb.dataBuffer else { self.lock.lock(); self.dropped += 1; self.lock.unlock(); return }
            var len = 0; var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr) == noErr, let ptr else { return }
            let attach = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
            let notSync = attach?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            let f = Frame(data: Data(bytes: ptr, count: len), pts: sb.presentationTimeStamp, isKey: !notSync, format: fmt)
            self.lock.lock(); self.encoded += 1; self.lock.unlock()
            self.onFrame?(f)
        }
    }

    /// Wait until every submitted frame has come out.
    public func flush() { if let s = session { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid) } }
}

public extension VideoEncoder.Frame {
    /// SPS and PPS of the stream (for the RTMP/FLV AVC sequence header).
    var parameterSets: [Data] {
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        return (0..<count).compactMap { i in
            var p: UnsafePointer<UInt8>?; var n = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p else { return nil }
            return Data(bytes: p, count: n)
        }
    }

    /// The same picture as a compressed sample buffer (for writing an MP4 in tests, or for a player).
    func sampleBuffer() -> CMSampleBuffer? {
        var bb: CMBlockBuffer?
        let n = data.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: n, flags: 0, blockBufferOut: &bb) == noErr, let bb else { return nil }
        _ = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: n) }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: pts)
        var size = n; var sb: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: bb, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb)
        if let sb, !isKey, let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(a, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }
}
