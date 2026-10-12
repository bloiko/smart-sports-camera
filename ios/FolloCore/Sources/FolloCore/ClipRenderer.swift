import Foundation
import AVFoundation
import CoreImage

/// Renders a clip [t0, t1] of the source video along a camera path into an H.264 MP4 (1920×1080 or 1080×1920):
/// fade-in 0.4 s and a time/goal label for 3 s, as closeup.render() in Python. Works on the Mac and the phone.
public final class ClipRenderer {
    let ctx = CIContext(options: [.cacheIntermediates: false])
    public init() {}

    public func render(video: String, path: [(x: Double, y: Double, cw: Double, ch: Double)], out: URL, t0: Double, t1: Double, size: (Int, Int), label: String?, fade: Double = 0.4) throws {
        let reader = try VideoReader(path: video); let fps = reader.fps; let (ow, oh) = size
        try? FileManager.default.removeItem(at: out)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: ow, AVVideoHeightKey: oh,
                                                                            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: ow, kCVPixelBufferHeightKey as String: oh])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let f0 = Int(t0 * fps), nFrames = Int((t1 - t0) * fps); try reader.start(from: f0)
        let labelImg = label.map { Self.labelImage($0, scale: Double(min(ow, oh)) / 1080, canvasH: Double(oh)) }
        var k = 0
        while k < nFrames {
            let ok: Bool = autoreleasepool {
                guard let pb = reader.next() else { return false }
                let f = min(f0 + k, path.count - 1); let p = path[f]; let H = Double(CVPixelBufferGetHeight(pb))
                let rect = CGRect(x: (p.x - p.cw / 2).rounded(.down), y: H - (p.y - p.ch / 2).rounded(.down) - p.ch.rounded(.down), width: p.cw.rounded(.down), height: p.ch.rounded(.down))
                var img = CIImage(cvPixelBuffer: pb).cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                img = img.transformed(by: CGAffineTransform(scaleX: Double(ow) / rect.width, y: Double(oh) / rect.height))
                let t = Double(k) / fps
                if let l = labelImg, t < 3 { img = l.composited(over: img) }
                if t < fade { img = img.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: t / fade, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: t / fade, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: t / fade, w: 0)]) }
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                var out: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &out)
                guard let dst = out else { return false }
                ctx.render(img, to: dst, bounds: CGRect(x: 0, y: 0, width: ow, height: oh), colorSpace: CGColorSpaceCreateDeviceRGB())
                adaptor.append(dst, withPresentationTime: CMTime(value: CMTimeValue(k), timescale: CMTimeScale(fps.rounded())))
                k += 1; return true
            }
            if !ok { break }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "ClipRenderer", code: 1) }
    }

    /// White text on a dark translucent box at the top-left (CoreImage text generator; no UIKit).
    static func labelImage(_ text: String, scale: Double, canvasH: Double) -> CIImage {
        let gen = CIFilter(name: "CIAttributedTextImageGenerator")!
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44 * scale, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)])
        gen.setValue(attr, forKey: "inputText"); gen.setValue(1.0, forKey: "inputScaleFactor")
        guard let txt = gen.outputImage else { return CIImage.empty() }
        let pad = 16 * scale; let box = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55)).cropped(to: txt.extent.insetBy(dx: -pad, dy: -pad))
        let img = txt.composited(over: box)
        // top-left corner: x = 40·scale, top edge 30·scale below the top (CoreImage's y grows upward)
        return img.transformed(by: CGAffineTransform(translationX: 40 * scale - img.extent.minX, y: canvasH - 30 * scale - img.extent.maxY))
    }
}
