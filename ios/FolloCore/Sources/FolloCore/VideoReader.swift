import Foundation
import AVFoundation
import CoreImage

/// Sequential frames of a video file as BGRA pixel buffers (Mac simulator and phone post-processing).
public final class VideoReader {
    public let fps: Double, W: Int, H: Int, frames: Int
    let asset: AVAsset, track: AVAssetTrack
    var reader: AVAssetReader?, output: AVAssetReaderTrackOutput?

    public init(path: String) throws {
        asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let t = asset.tracks(withMediaType: .video).first else { throw NSError(domain: "VideoReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "no video track in \(path)"]) }
        track = t; fps = Double(t.nominalFrameRate)
        let sz = t.naturalSize.applying(t.preferredTransform); W = Int(abs(sz.width)); H = Int(abs(sz.height))
        frames = Int((CMTimeGetSeconds(asset.duration) * fps).rounded())
    }

    public func start(from frame: Int = 0) throws {
        let r = try AVAssetReader(asset: asset)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        o.alwaysCopiesSampleData = false; r.add(o)
        if frame > 0 { r.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps.rounded())), duration: .positiveInfinity) }
        r.startReading(); reader = r; output = o
    }

    public func next() -> CVPixelBuffer? {
        guard let o = output, let sb = o.copyNextSampleBuffer() else { return nil }
        return CMSampleBufferGetImageBuffer(sb)
    }
}

extension Image8 {
    /// Grey from any pixel buffer: the Y plane of a 4:2:0 buffer (camera), or converted from BGRA (file).
    public static func grey(from pb: CVPixelBuffer) -> Image8 {
        if CVPixelBufferGetPlaneCount(pb) >= 2 {
            CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
            var d = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h { d.withUnsafeMutableBufferPointer { $0.baseAddress!.advanced(by: y * w).update(from: base + y * bpr, count: w) } }
            return Image8(w: w, h: h, ch: 1, data: d)
        }
        return Image8(bgra: pb).grey()
    }
}
