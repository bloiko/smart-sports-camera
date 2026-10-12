import Foundation
import AVFoundation
import CoreImage
import FolloCore

/// The virtual camera on the phone: camera frames → Core ML detection (LivePipeline) → LiveCamera (buffer B s) →
/// 1920×1080 crop for the streamer. Frames are copied into a ring of B s (4K 4:2:0 ≈ 12 MB each: 2 s ≈ 750 MB).
final class LiveCameraRunner {
    let bufferS = 2.0
    private(set) var env: LiveEnv?
    private var pipe: LivePipeline?, cam: LiveCamera?
    private var ring: [Int: (CVPixelBuffer, CMTime)] = [:]
    private var ringPool: CVPixelBufferPool?, outPool: CVPixelBufferPool?
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private var frame = 0
    private var preroll: [(Double, Image8)] = []
    var fps = 30.0
    /// Output crop (1920×1080) with the capture time of its source frame.
    var onOutput: ((CVPixelBuffer, CMTime) -> Void)?
    /// Те саме для «погляду глядача» на екрані (пункт 10).
    var onPreview: ((CVPixelBuffer, CMTime) -> Void)?
    /// For the icon row: ball found share, goals known, detection ms per frame.
    private(set) var ballPasses = 0, ballFound = 0
    var goalsKnown: Bool { cam?.goals != nil }
    var isLive: Bool { cam != nil }
    var ballShare: Double { ballPasses > 0 ? Double(ballFound) / Double(ballPasses) : 0 }

    /// Position check: call with a frame every ~1.5 s while the setup screen is open (7 frames over 10 s).
    /// Half-resolution median of the last 7 frames → field mask, image bounds, halfway line.
    func addPrerollFrame(_ pb: CVPixelBuffer, time: Double) {
        guard preroll.last.map({ time - $0.0 >= 1.4 }) ?? true else { return }
        let w = CVPixelBufferGetWidth(pb) / 2, h = CVPixelBufferGetHeight(pb) / 2
        guard let small = render(CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)), w: w, h: h, pool: nil) else { return }
        preroll.append((time, Image8(bgra: small))); if preroll.count > 7 { preroll.removeFirst() }
        if preroll.count == 7 { env = LiveEnv.make(frames: preroll.map { $0.1 }, fps: fps).scaled(2) }
    }

    /// Start the live camera once the position check is fine. Models: players.mlmodelc and ball.mlmodelc in the bundle
    /// (drag models/coreml/*.mlpackage into Xcode; it compiles them).
    func start() throws {
        guard let env = env else { throw NSError(domain: "Follo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Position check not finished"]) }
        let pl = try Detector(url: Bundle.main.url(forResource: "players", withExtension: "mlmodelc")!)
        let bd = try Detector(url: Bundle.main.url(forResource: "ball", withExtension: "mlmodelc")!)
        pipe = LivePipeline(W: env.W, H: env.H, fps: fps, fm: env.fm!, fmd: env.fmd, players: pl, ball: bd)
        cam = LiveCamera(W: env.W, H: env.H, fps: fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: bufferS)
        cam?.onFrame = { [weak self] f, fr in self?.emit(f, fr) }
        frame = 0; ring = [:]; ballPasses = 0; ballFound = 0
    }

    /// Після Стоп: траєкторія і кольори форми для хайлайтів (HighlightsRunner), потім звільнити пам'ять.
    func stop() -> (cam: LiveCamera, jerseys: [JerseySample])? {
        defer { pipe = nil; cam = nil; ring = [:] }
        guard let cam = cam, let pipe = pipe else { return nil }
        cam.finish(); return (cam, pipe.jerseys)
    }

    /// Thermal step (item 4): detect every 3rd frame instead of every 2nd when hot.
    func setDetectEvery(_ n: Int) { pipe?.ballEvery = n; pipe?.playerEvery = 2 * n }

    /// Every captured frame, on the camera queue.
    func push(_ sb: CMSampleBuffer) {
        guard let pipe = pipe, let cam = cam, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sb)
        let f = frame; frame += 1
        if let copy = copyFrame(pb) { ring[f] = (copy, t) }
        let rec = pipe.process(frame: f, image: CIImage(cvPixelBuffer: pb), grey: { Image8.grey(from: pb) }, patch: { Image8.bgrPatch(pb, x0: $0, y0: $1, w: $2, h: $3) })
        if rec.rois != nil { ballPasses += 1; if rec.ball != nil { ballFound += 1 } }
        cam.push(rec)
    }

    private func emit(_ f: Int, _ fr: LiveCamera.Frame) {
        guard let (src, t) = ring.removeValue(forKey: f) else { return }
        for k in ring.keys where k < f { ring[k] = nil }
        let H = Double(CVPixelBufferGetHeight(src))
        let rect = CGRect(x: fr.x - fr.cw / 2, y: H - (fr.y + fr.ch / 2), width: fr.cw, height: fr.ch)   // CoreImage: origin bottom-left
        var img = CIImage(cvPixelBuffer: src).cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        img = img.transformed(by: CGAffineTransform(scaleX: 1920 / fr.cw, y: 1080 / fr.ch))
        if outPool == nil { outPool = Self.pool(w: 1920, h: 1080, format: kCVPixelFormatType_32BGRA, count: 6) }
        if let out = render(img, w: 1920, h: 1080, pool: outPool) { onOutput?(out, t); onPreview?(out, t) }
    }

    private func copyFrame(_ pb: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), fmt = CVPixelBufferGetPixelFormatType(pb)
        if ringPool == nil { ringPool = Self.pool(w: w, h: h, format: fmt, count: Int(bufferS * fps) + 6) }
        var out: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, ringPool!, &out)
        guard let dst = out else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); CVPixelBufferLockBaseAddress(dst, [])
        for p in 0..<max(1, CVPixelBufferGetPlaneCount(pb)) {
            let rows = CVPixelBufferGetHeightOfPlane(pb, p), bpr = min(CVPixelBufferGetBytesPerRowOfPlane(pb, p), CVPixelBufferGetBytesPerRowOfPlane(dst, p))
            for y in 0..<rows { memcpy(CVPixelBufferGetBaseAddressOfPlane(dst, p)! + y * CVPixelBufferGetBytesPerRowOfPlane(dst, p), CVPixelBufferGetBaseAddressOfPlane(pb, p)! + y * CVPixelBufferGetBytesPerRowOfPlane(pb, p), bpr) }
        }
        CVPixelBufferUnlockBaseAddress(dst, []); CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        return dst
    }

    private func render(_ img: CIImage, w: Int, h: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        if let pool = pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) }
        else { CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &out) }
        guard let pb = out else { return nil }
        ctx.render(img, to: pb, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: CGColorSpaceCreateDeviceRGB())
        return pb
    }

    private static func pool(w: Int, h: Int, format: OSType, count: Int) -> CVPixelBufferPool? {
        var p: CVPixelBufferPool?
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h, kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: count] as CFDictionary, attrs as CFDictionary, &p)
        return p
    }
}
