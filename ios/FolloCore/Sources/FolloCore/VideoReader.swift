import Foundation
import AVFoundation
import CoreImage

/// Sequential frames of a video file as BGRA pixel buffers (Mac simulator and phone post-processing).
public final class VideoReader {
    public let fps: Double, W: Int, H: Int, frames: Int
    let asset: AVAsset, track: AVAssetTrack
    var reader: AVAssetReader?, output: AVAssetReaderTrackOutput?
    /// BGRA by default; `follosim bench` asks for the camera's 4:2:0 so the phone's frame path is timed on its own format.
    public var pixelFormat: OSType = kCVPixelFormatType_32BGRA

    public init(path: String) throws {
        asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let t = asset.tracks(withMediaType: .video).first else { throw NSError(domain: "VideoReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "no video track in \(path)"]) }
        track = t; fps = Double(t.nominalFrameRate)
        let sz = t.naturalSize.applying(t.preferredTransform); W = Int(abs(sz.width)); H = Int(abs(sz.height))
        frames = Int((CMTimeGetSeconds(asset.duration) * fps).rounded())
    }

    public func start(from frame: Int = 0) throws {
        let r = try AVAssetReader(asset: asset)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        o.alwaysCopiesSampleData = false; r.add(o)
        if frame > 0 { r.timeRange = CMTimeRange(start: CMTimeAdd(CMTime(seconds: videoStart, preferredTimescale: 600), CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps.rounded()))), duration: .positiveInfinity) }
        r.startReading(); reader = r; output = o
    }

    public func next() -> CVPixelBuffer? {
        guard let o = output else { return nil }
        while let sb = o.copyNextSampleBuffer() {
            // An empty edit at the start (video starting after the audio: m2 1.68 s, m3 0.98 s) makes the decoder emit
            // the first picture once more at time 0; cv2/ffmpeg do not. Skipping it keeps frame f = Python's frame f.
            if CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) < videoStart - 0.001 { continue }
            return CMSampleBufferGetImageBuffer(sb)
        }
        return nil
    }
    /// Track time of the first real picture (after an empty edit), see next().
    public var videoStart: Double { Self.videoStart(of: track) }
    public static func videoStart(of t: AVAssetTrack) -> Double {
        t.segments.first(where: { !$0.isEmpty }).map { CMTimeGetSeconds($0.timeMapping.target.start) } ?? 0
    }
}

extension Image8 {
    /// Grey from any pixel buffer: the Y plane of a 4:2:0 buffer (camera), or converted from BGRA (file).
    public static func grey(from pb: CVPixelBuffer) -> Image8 {
        if CVPixelBufferGetPlaneCount(pb) >= 2 {
            CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
            // one block copy (rows contiguous) or one memcpy per row, into an uninitialised array: 24 ms → ~1 ms for 4K
            // on the M1 (2026-10-22: the old per-row closure with a zero-filled array was most of a ball pass)
            let d = [UInt8](unsafeUninitializedCapacity: w * h) { buf, n in
                let dst = buf.baseAddress!
                if bpr == w { memcpy(dst, base, w * h) } else { for y in 0..<h { memcpy(dst + y * w, base + y * bpr, w) } }
                n = w * h
            }
            return Image8(w: w, h: h, ch: 1, data: d)
        }
        return Image8(bgra: pb).grey()
    }
}

/// Copy of a camera frame into a buffer from `pool` (the live camera keeps B s of frames; the camera's own pool is small).
/// One memcpy per plane when rows line up, else one per row; base addresses read once (2026-10-22 speed-up).
public func copyPixelBuffer(_ pb: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var out: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
    guard let dst = out else { return nil }
    CVPixelBufferLockBaseAddress(pb, .readOnly); CVPixelBufferLockBaseAddress(dst, [])
    defer { CVPixelBufferUnlockBaseAddress(dst, []); CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let planes = CVPixelBufferGetPlaneCount(pb)
    for p in 0..<max(1, planes) {
        let src = planes > 0 ? CVPixelBufferGetBaseAddressOfPlane(pb, p)! : CVPixelBufferGetBaseAddress(pb)!
        let to = planes > 0 ? CVPixelBufferGetBaseAddressOfPlane(dst, p)! : CVPixelBufferGetBaseAddress(dst)!
        let sb = planes > 0 ? CVPixelBufferGetBytesPerRowOfPlane(pb, p) : CVPixelBufferGetBytesPerRow(pb)
        let db = planes > 0 ? CVPixelBufferGetBytesPerRowOfPlane(dst, p) : CVPixelBufferGetBytesPerRow(dst)
        let rows = planes > 0 ? CVPixelBufferGetHeightOfPlane(pb, p) : CVPixelBufferGetHeight(pb)
        if sb == db { memcpy(to, src, sb * rows) } else { let n = min(sb, db); for y in 0..<rows { memcpy(to + y * db, src + y * sb, n) } }
    }
    return dst
}
