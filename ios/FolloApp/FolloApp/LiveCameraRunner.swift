import Foundation
import AVFoundation
import CoreImage
import QuartzCore
import ImageIO
import FolloCore

/// The virtual camera on the phone: camera frames → Core ML detection (LivePipeline) → LiveCamera (buffer B s) →
/// 1920×1080 crop for the streamer. Frames are copied into a ring of B s (4K 4:2:0 ≈ 12 MB each: 2 s ≈ 750 MB).
final class LiveCameraRunner {
    let bufferS = 2.0
    private(set) var env: LiveEnv?
    /// What the position check found, drawn over the preview ("Що бачить застосунок"); computed once with the env.
    private(set) var positionOverlay: PositionOverlay?
    private var pipe: LivePipeline?, cam: LiveCamera?
    private var ring: [Int: (CVPixelBuffer, CMTime)] = [:]
    private var ringPool: CVPixelBufferPool?, outPool: CVPixelBufferPool?
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private var frame = 0
    private var preroll: [(Double, Image8)] = []
    private(set) var prerollCount = 0, building = false
    private let envQueue = DispatchQueue(label: "follo.env", qos: .utility)   // низький пріоритет: build 10 с на userInitiated душив потік камери
    var fps = 30.0
    /// Output crop (1920×1080) with the capture time of its source frame.
    var onOutput: ((CVPixelBuffer, CMTime) -> Void)?
    /// Те саме для «погляду глядача» на екрані (пункт 10).
    var onPreview: ((CVPixelBuffer, CMTime) -> Void)?
    /// For the icon row: ball found share, goals known, detection ms per frame.
    private(set) var ballPasses = 0, ballFound = 0, outFrames = 0, inFrames = 0
    var goalsKnown: Bool { cam?.goals != nil }
    var isLive: Bool { cam != nil }
    private(set) var knownPitch = false
    static var pitchesURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pitches.json") }
    var ballShare: Double { ballPasses > 0 ? Double(ballFound) / Double(ballPasses) : 0 }

    /// Position check: call with a frame every ~1.5 s while the setup screen is open (7 frames over 10 s).
    /// Half-resolution median of the last 7 frames → field mask, image bounds, halfway line.
    func resetPosition() { preroll.removeAll(); prerollCount = 0; env = nil; positionOverlay = nil; building = false }

    func addPrerollFrame(_ pb: CVPixelBuffer, time: Double) {
        guard env == nil, !building, !prerollBusy, preroll.last.map({ time - $0.0 >= 1.4 }) ?? true else { return }   // після 7 кадрів нічого не рендеримо
        // важке (CI-рендер + копія) — поза чергою камери, інакше камера відстає і iOS глушить потік
        prerollBusy = true
        envQueue.async { [weak self] in
            guard let self else { return }
            // Повна роздільність: ядра маски поля і центральної лінії задані в пікселях повного кадру (як у live_sim.py).
            // На 1/4 вони ставали вчетверо більшими: маска 90% кадру замість 79%, кадр камери ширший на 20%.
            // Збірка з -O: ~2–5 с і ~250–450 МБ один раз до гри.
            let k = Self.envScale, w = CVPixelBufferGetWidth(pb) / k, h = CVPixelBufferGetHeight(pb) / k
            let img = k == 1 ? CIImage(cvPixelBuffer: pb) : CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: 1 / CGFloat(k), y: 1 / CGFloat(k)))
            if let small = self.render(img, w: w, h: h, pool: nil) {
                let img = Image8(bgra: small)
                DispatchQueue.main.async { self.preroll.append((time, img)); if self.preroll.count > 7 { self.preroll.removeFirst() }; self.prerollBusy = false; self.afterPreroll() }
            } else { DispatchQueue.main.async { self.prerollBusy = false } }
        }
    }

    private var prerollBusy = false
    static let envScale = 1
    private func afterPreroll() {
        DebugLog.log("preroll frame \(preroll.count)")
        prerollCount = preroll.count
        if preroll.count == 7, !building, env == nil {      // маска поля і центральна лінія — не на черзі камери (секунди)
            building = true; let frames = preroll.map { $0.1 }; let f = fps
            DebugLog.log("env build start, mem \(DebugLog.memMB()) MB")
            envQueue.async { [weak self] in
                let t0 = Date()
                let e = Self.envScale == 1 ? LiveEnv.make(frames: frames, fps: f) : LiveEnv.make(frames: frames, fps: f).scaled(Self.envScale)
                DebugLog.log("env build done in \(Int(Date().timeIntervalSince(t0) * 1000)) ms mem \(DebugLog.memMB()): \(e.positionProblem ?? "ok")")
                let ov = e.positionOverlay()
                DispatchQueue.main.async { self?.env = e; self?.positionOverlay = ov; self?.building = false }
            }
        }
    }

    /// Start the live camera once the position check is fine. Models: players.mlmodelc and ball.mlmodelc in the bundle
    /// (drag models/coreml/*.mlpackage into Xcode; it compiles them).
    func start() throws {
        guard let env = env else { throw NSError(domain: "Follo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Position check not finished"]) }
        let pl = try Detector(url: Bundle.main.url(forResource: "players", withExtension: "mlmodelc")!)
        let bd = try Detector(url: Bundle.main.url(forResource: "ball", withExtension: "mlmodelc")!)
        pipe = LivePipeline(W: env.W, H: env.H, fps: fps, fm: env.fm!, fmd: env.fmd, players: pl, ball: bd)
        var cfg = CameraConfig()
        cfg.goalsPrior = PitchMemory.load(Self.pitchesURL).compactMap { $0.prior(for: env) }.last    // пам'ять поля
        knownPitch = cfg.goalsPrior != nil
        cam = LiveCamera(W: env.W, H: env.H, fps: fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: bufferS, config: cfg)
        cam?.onFrame = { [weak self] f, fr in self?.emit(f, fr) }
        frame = 0; ring = [:]; ballPasses = 0; ballFound = 0
        // debug: шлях камери по кадрах у Documents/debug/path.csv — порівняння з live_sim.py на тому самому відео
        let pu = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug/path.csv")
        try? "f,t,x,y,cw,ch,gon,bx,by\n".write(to: pu, atomically: true, encoding: .utf8); pathLog = try? FileHandle(forWritingTo: pu); pathLog?.seekToEndOfFile()
    }

    /// Після Стоп: траєкторія і кольори форми для хайлайтів (HighlightsRunner), потім звільнити пам'ять.
    func stop() -> (cam: LiveCamera, jerseys: [JerseySample])? {
        pipeQueue.sync {}                                                  // let the frame in progress finish
        defer { pipe = nil; cam = nil; ring = [:]; try? pathLog?.close(); pathLog = nil }
        guard let cam = cam, let pipe = pipe else { return nil }
        cam.finish()
        if let g = cam.goals, let e = env { PitchMemory.remember(PitchMemory(env: e, goals: g), in: Self.pitchesURL) }   // запам'ятати поле
        return (cam, pipe.jerseys)
    }

    /// Thermal step (item 4): detect every 3rd frame instead of every 2nd when hot.
    func setDetectEvery(_ n: Int) { pipe?.ballEvery = n; pipe?.playerEvery = 2 * n }

    /// Detection, camera and the output crop run here, not on the camera queue: on the camera queue they took ~47 ms a
    /// frame and iOS discarded late camera frames before the recorder saw them (match 18.10: 4K file at 21 fps instead
    /// of 30). Now the recorder gets every frame; when this queue is behind, a frame is skipped for the stream only.
    /// `--sync-pipeline` (debug): the old way, everything on the camera queue, to compare before/after.
    private let pipeQueue = DispatchQueue(label: "follo.pipeline", qos: .userInitiated)
    static let syncPipeline = CommandLine.arguments.contains("--sync-pipeline")
    private let pendingLock = NSLock()
    private var pending = 0
    private(set) var skipped = 0
    private var procMs = 0.0, procMax = 0.0, procN = 0

    /// Every captured frame, on the camera queue.
    func push(_ sb: CMSampleBuffer) {
        guard pipe != nil, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sb)
        if Self.syncPipeline { process(src: pb, copy: copyFrame(pb), t: t); return }
        pendingLock.lock()
        if pending >= 2 { skipped += 1; pendingLock.unlock(); return }      // behind: this frame goes to the file only
        pending += 1; pendingLock.unlock()
        guard let copy = copyFrame(pb) else { pendingLock.lock(); pending -= 1; pendingLock.unlock(); return }
        pipeQueue.async { [weak self] in
            self?.process(src: copy, copy: copy, t: t)
            self?.pendingLock.lock(); self?.pending -= 1; self?.pendingLock.unlock()
        }
    }

    private func process(src pb: CVPixelBuffer, copy: CVPixelBuffer?, t: CMTime) {
        guard let pipe = pipe, let cam = cam else { return }
        let t0 = CACurrentMediaTime()
        let f = frame; frame += 1; inFrames += 1
        if let copy { ring[f] = (copy, t) }
        let rec = pipe.process(frame: f, image: CIImage(cvPixelBuffer: pb), grey: { Image8.grey(from: pb) }, patch: { Image8.bgrPatch(pb, x0: $0, y0: $1, w: $2, h: $3) })
        if rec.rois != nil { ballPasses += 1; if rec.ball != nil { ballFound += 1 } }
        cam.push(rec)
        let ms = (CACurrentMediaTime() - t0) * 1000; procMs += ms; procMax = max(procMax, ms); procN += 1
        if procN == 300 {
            DebugLog.log(String(format: "pipeline%@: 300 frames, avg %.1f ms, max %.0f ms, skipped for the stream so far %d", Self.syncPipeline ? " (sync)" : "", procMs / 300, procMax, skipped))
            procMs = 0; procMax = 0; procN = 0
        }
    }

    private var pathLog: FileHandle?
    private let overlayLock = NSLock()
    private var overlay: CIImage?
    /// Табло (Scoreboard.render) у лівому верхньому куті кадру 1920×1080; nil — сховати. Викликати з головного потоку.
    func setScoreboard(_ img: CGImage?) {
        let ci = img.map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: CGFloat(Scoreboard.margin), y: CGFloat(1080 - Scoreboard.margin - $0.height))) }
        overlayLock.lock(); overlay = ci; overlayLock.unlock()
    }
    private func emit(_ f: Int, _ fr: LiveCamera.Frame) {
        guard let (src, t) = ring.removeValue(forKey: f) else { return }
        let b = fr.ball.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? ","
        pathLog?.write(String(format: "%d,%.3f,%.1f,%.1f,%.1f,%.1f,%d,", f, CMTimeGetSeconds(t), fr.x, fr.y, fr.cw, fr.ch, fr.gon ? 1 : 0).appending(b + "\n").data(using: .utf8)!)
        for k in ring.keys where k < f { ring[k] = nil }
        let H = Double(CVPixelBufferGetHeight(src))
        let rect = CGRect(x: fr.x - fr.cw / 2, y: H - (fr.y + fr.ch / 2), width: fr.cw, height: fr.ch)   // CoreImage: origin bottom-left
        var img = CIImage(cvPixelBuffer: src).cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        img = img.transformed(by: CGAffineTransform(scaleX: 1920 / fr.cw, y: 1080 / fr.ch))
        overlayLock.lock(); let bug = overlay; overlayLock.unlock()
        if let bug { img = bug.composited(over: img) }                       // табло рахунку в кадрі трансляції
        if outPool == nil { outPool = Self.pool(w: 1920, h: 1080, format: kCVPixelFormatType_32BGRA, count: 6) }
        if let out = render(img, w: 1920, h: 1080, pool: outPool) {
            outFrames += 1; onOutput?(out, t); onPreview?(out, t)
            if outFrames % 250 == 1 { saveDebugFrame(img) }               // debug: кадр трансляції раз на 10 с → Documents/debug/output.jpg
        }
    }

    private func saveDebugFrame(_ img: CIImage) {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug/output.jpg")
        let small = img.cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080)).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        guard let cg = ctx.createCGImage(small, from: small.extent), let d = CGImageDestinationCreateWithURL(u as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary); CGImageDestinationFinalize(d)
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
