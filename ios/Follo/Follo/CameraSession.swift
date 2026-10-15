import AVFoundation
import UIKit
import CoreImage
import Combine

/// 4K 30 fps з ультраширокої камери, запис файлами по chunkSeconds, кадри для нейромережі через delegate.
final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera")
    private var writer: ChunkWriter?
    @Published var isRecording = false
    @Published var chunkCount = 0
    @Published var frameHandler: ((CMSampleBuffer) -> Void)?
    @Published var previewImage: UIImage?
    @Published var useWide = false        // 1× замість 0.5×: мало світла (автоматично) або стенд удома
    @Published var lowLight: String?      // підказка на екрані, коли кадр недоекспонований
    @Published var testVideo: URL?        // debug: відео замість камери (див. startFile)
    @Published var sourceFps = 30.0
    var fileGen = 0, filePaused = false

    /// Фон: зупинити камеру, інакше вона лишається зайнятою і інші застосунки (та наступний запуск) бачать чорне.
    func pause() { if testVideo != nil { filePaused = true; return }; queue.async { if self.session.isRunning { self.session.stopRunning(); DebugLog.log("session paused") } } }
    func resume() {
        if testVideo != nil { filePaused = false; return }
        queue.async {
            guard !self.session.isRunning else { return }
            if !self.session.inputs.isEmpty { self.session.startRunning() }
            if !self.session.isRunning {                       // після фону сесія інколи не піднімається: перезбираємо
                self.session.beginConfiguration()
                for i in self.session.inputs { self.session.removeInput(i) }
                for o in self.session.outputs { self.session.removeOutput(o) }
                self.session.commitConfiguration(); self.setup()
            }
            DebugLog.log("session resumed \(self.session.isRunning)")
        }
    }

    /// Перемкнути ультраширокy ↔ широку камеру (перезбирає сесію).
    func switchCamera(wide: Bool) {
        useWide = wide
        queue.async {
            self.session.stopRunning(); self.session.beginConfiguration()
            for i in self.session.inputs { self.session.removeInput(i) }
            for o in self.session.outputs { self.session.removeOutput(o) }
            self.session.commitConfiguration(); self.setup()
        }
    }
    private var previewCount = 0
    private var darkCount = 0
    private var lastAutoSwitch = Date.distantPast
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []
    private var pressureObs: NSKeyValueObservation?

    /// Мало світла на ультраширокій 3 виміри поспіль (6 с) → автоматично 1× (світліший об'єктив). Назад не перемикаємо
    /// автоматично (гістерезис): користувач бачить підказку і кнопку.
    private func lowLightCheck(dark: Bool) {
        darkCount = dark ? darkCount + 1 : 0
        guard darkCount >= 3, !useWide, Date().timeIntervalSince(lastAutoSwitch) > 30 else { return }
        darkCount = 0; lastAutoSwitch = Date()
        DebugLog.log("low light on ultra-wide: switching to 1x")
        DispatchQueue.main.async {
            self.lowLight = "Мало світла: перемкнув на камеру 1× (у ній більше світла, але менше поля в кадрі)"
            self.switchCamera(wide: true)
        }
    }

    private func rebuild() {
        queue.async {
            self.session.stopRunning(); self.session.beginConfiguration()
            for i in self.session.inputs { self.session.removeInput(i) }
            for o in self.session.outputs { self.session.removeOutput(o) }
            self.session.commitConfiguration(); self.setup()
        }
    }
    private let previewCtx = CIContext(options: [.cacheIntermediates: false])
    let chunkSeconds: Double = 180

    @Published var cameraError: String?

    func configure() {
        if let v = testVideo { startFile(v); return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DebugLog.log("camera permission \(ok)")
            guard ok else { DispatchQueue.main.async { self.cameraError = "Немає дозволу на камеру: Параметри → Follo → Камера" }; return }
            self.queue.async { self.setup() }
        }
    }

    private func setup() {
        session.beginConfiguration()
        let dev = (useWide ? nil : AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back))
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let dev, let input = try? AVCaptureDeviceInput(device: dev) else {
            session.commitConfiguration(); DispatchQueue.main.async { self.cameraError = "Камеру не знайдено" }; return
        }
        if session.canAddInput(input) { session.addInput(input) }
        // лише пресет (без ручного activeFormat): пресет і activeFormat на iOS взаємовиключні
        session.sessionPreset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        if let c = out.connection(with: .video), c.isVideoRotationAngleSupported(0) { c.videoRotationAngle = 0 }
        session.commitConfiguration()
        // Запас експозиції в темряві: відео 30 fps обмежує затвор до 1/30 с, на ультраширокій f/2.4 вночі це чорний кадр.
        // Дозволяємо камері сама знижувати частоту до 15 fps, коли бракує світла. Робимо ДО startRunning, в окремій
        // конфігурації після того, як пресет обрав формат (пресет скидає тривалості кадру).
        session.beginConfiguration()
        do {
            try dev.lockForConfiguration()
            let ranges = dev.activeFormat.videoSupportedFrameRateRanges
            let minFps = ranges.map(\.minFrameRate).min() ?? 30
            let slow = CMTime(value: 1, timescale: CMTimeScale(max(15, Int(minFps.rounded(.up)))))
            dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            dev.activeVideoMaxFrameDuration = slow
            if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            dev.unlockForConfiguration()
            DebugLog.log("exposure headroom: fps 30…\(slow.timescale), maxISO \(Int(dev.activeFormat.maxISO))")
        } catch { DebugLog.log("exposure headroom failed: \(error)") }
        session.commitConfiguration()
        device = dev
        observe(dev)
        session.startRunning()
        let d = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription)
        DebugLog.log("session running \(session.isRunning) \(dev.localizedName) \(d.width)x\(d.height) inputs \(session.inputs.count) outputs \(session.outputs.count) cost \(String(format: "%.2f", session.hardwareCost))")
        DispatchQueue.main.async { self.cameraError = self.session.isRunning ? nil : "Камера не запустилась"; self.formatInfo = "\(dev.localizedName) \(d.width)×\(d.height)" }
    }

    /// Справжні сигнали AVFoundation замість здогадок: перерви, помилки, тиск системи.
    private func observe(_ dev: AVCaptureDevice) {
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { n in
            let r = (n.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            DebugLog.log("INTERRUPTED reason \(r.map { "\($0.rawValue)" } ?? "?")")
            DispatchQueue.main.async { self.cameraError = Self.text(for: r) }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
            DebugLog.log("interruption ended"); DispatchQueue.main.async { self.cameraError = nil }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { n in
            let e = n.userInfo?[AVCaptureSessionErrorKey] as? AVError
            DebugLog.log("RUNTIME ERROR \(e?.code.rawValue ?? 0) \(e?.localizedDescription ?? "")")
            if e?.code == .mediaServicesWereReset { self.rebuild() } else { self.queue.async { self.session.startRunning() } }
        })
        pressureObs = dev.observe(\.systemPressureState, options: [.new]) { d, _ in
            let p = d.systemPressureState
            DebugLog.log("system pressure \(p.level.rawValue) factors \(p.factors.rawValue)")
        }
    }

    private static func text(for r: AVCaptureSession.InterruptionReason?) -> String {
        switch r {
        case .videoDeviceInUseByAnotherClient: return "Камеру зайняв інший застосунок"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "Камера недоступна в режимі кількох застосунків"
        case .videoDeviceNotAvailableDueToSystemPressure: return "Телефон перегрівся: камеру вимкнено, дай охолонути"
        case .videoDeviceNotAvailableInBackground: return "Застосунок у фоні"
        default: return "Камеру перервано"
        }
    }

    @Published var formatInfo = ""

    func startRecording() {
        queue.async {
            self.writer = ChunkWriter(chunkSeconds: self.chunkSeconds) { n in DispatchQueue.main.async { self.chunkCount = n } }
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        queue.async {
            self.writer?.finish(); self.writer = nil
            DispatchQueue.main.async { self.isRecording = false }
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handle(sampleBuffer)
    }

    /// Один кадр з камери або з тестового відео: запис, конвеєр, прев'ю. На черзі камери.
    func handle(_ sampleBuffer: CMSampleBuffer) {
        writer?.append(sampleBuffer)
        frameHandler?(sampleBuffer)
        previewCount += 1
        if previewCount % 15 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {   // прев'ю 5 fps, 960 px
            let ci = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            if let cg = previewCtx.createCGImage(ci, from: ci.extent) { let ui = UIImage(cgImage: cg); DebugLog.preview(ui); DispatchQueue.main.async { self.previewImage = ui } }
            else { DebugLog.log("preview: createCGImage failed, extent \(ci.extent)") }
            if previewCount % 60 == 0 {                            // яскравість кадру + стан експозиції, раз на 2 с
                CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
                if let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
                    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
                    var sum = 0, sum2 = 0, n = 0, mx = 0; let p8 = base.assumingMemoryBound(to: UInt8.self)
                    for y in stride(from: 0, to: h, by: 60) { for x in stride(from: 0, to: w, by: 60) { let v = Int(p8[y * bpr + x]); sum += v; sum2 += v * v; n += 1; mx = max(mx, v) } }
                    let mean = Double(sum) / Double(n), sd = (Double(sum2) / Double(n) - mean * mean).squareRoot()
                    var exp = ""
                    if let d = device {
                        let iso = d.iso, maxISO = d.activeFormat.maxISO, off = d.exposureTargetOffset
                        exp = String(format: " iso %.0f/%.0f shutter 1/%.0f offset %+.1fEV", iso, maxISO, 1 / CMTimeGetSeconds(d.exposureDuration), off)
                        lowLightCheck(dark: off < -2 && iso >= 0.9 * maxISO && mean < 30)
                    }
                    // екран транслюється/записується (Device Hub, iPhone Mirroring, AirPlay, запис екрана)
                    let captured = DispatchQueue.main.sync { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.isCaptured }.contains(true) }
                    DebugLog.log(String(format: "luma mean %.1f sd %.1f max %d", mean, sd, mx) + exp + " screenCaptured \(captured) mem \(DebugLog.memMB()) MB")
                    if sd < 0.5 && mean < 20 { DispatchQueue.main.async { self.cameraError = captured ? "iOS ховає камеру, поки екран телефона транслюється або записується (Device Hub, Mirroring). Закрий трансляцію." : "Камера віддає чорний кадр" } }
                    else if self.cameraError?.hasPrefix("iOS ховає") == true || self.cameraError == "Камера віддає чорний кадр" { DispatchQueue.main.async { self.cameraError = nil } }
                }
            }
            if previewCount == 6 { DebugLog.log("first frame \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb)) fmt \(CVPixelBufferGetPixelFormatType(pb))") }
        }
    }
}

/// Пише кадри в MP4 (HEVC, апаратно) файлами по chunkSeconds у Documents/chunks/.
final class ChunkWriter {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var chunkStart: CMTime?
    private var index = 0
    private let chunkSeconds: Double
    private let onChunk: (Int) -> Void

    init(chunkSeconds: Double, onChunk: @escaping (Int) -> Void) {
        self.chunkSeconds = chunkSeconds; self.onChunk = onChunk
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
    }

    static var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chunks") }

    private func open(at time: CMTime, w: Int, h: Int) {
        index += 1
        let url = Self.dir.appendingPathComponent(String(format: "chunk_%03d.mp4", index))
        try? FileManager.default.removeItem(at: url)
        let bitRate: Int = 30_000_000 * (w * h) / (3840 * 2160)
        guard let wr = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate]])
        i.expectsMediaDataInRealTime = true
        wr.add(i); wr.startWriting(); wr.startSession(atSourceTime: time)
        writer = wr; input = i; chunkStart = time
    }

    func append(_ sb: CMSampleBuffer) {
        let t = CMSampleBufferGetPresentationTimeStamp(sb)
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)   // 4K з камери; тестове відео — свій розмір
        if writer == nil { open(at: t, w: w, h: h) }
        if let s = chunkStart, CMTimeGetSeconds(CMTimeSubtract(t, s)) >= chunkSeconds { finish(); open(at: t, w: w, h: h) }
        if input?.isReadyForMoreMediaData == true { input?.append(sb) }
    }

    func finish() {
        guard let w = writer else { return }
        input?.markAsFinished()
        let n = index
        w.finishWriting { self.onChunk(n) }
        writer = nil; input = nil
    }
}

/// Тестовий режим (лише debug-збірки): кадри з відео в Documents/testvideo/ замість камери, у реальному часі і по колу.
/// Далі той самий конвеєр, що й для камери: перевірка позиції, віртуальна камера, запис, стрім. Відео копіюється
/// з Mac: `devicectl device copy to --domain-type appDataContainer ... --destination Documents/testvideo/m2.mp4`.
extension CameraSession {
    static var testVideoDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("testvideo") }
    static var testVideos: [URL] {
        #if DEBUG
        let all = (try? FileManager.default.contentsOfDirectory(at: testVideoDir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #else
        return []
        #endif
    }

    /// Перемкнути джерело: nil — камера, інакше файл. Зупиняє поточне джерело.
    func setSource(_ url: URL?) {
        guard url != testVideo else { return }
        fileGen += 1                                            // зупиняє потік читання файлу
        if testVideo == nil { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
        testVideo = url; previewImage = nil; cameraError = nil
        UserDefaults.standard.set(url?.lastPathComponent, forKey: "debug.testVideo")
        DebugLog.log("source \(url?.lastPathComponent ?? "camera")")
        configure()
    }

    func startFile(_ url: URL) {
        fileGen += 1; let gen = fileGen; filePaused = false
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { cameraError = "Не можу прочитати \(url.lastPathComponent)"; return }
        let fps = Double(track.nominalFrameRate) > 0 ? Double(track.nominalFrameRate) : 30
        let size = track.naturalSize
        sourceFps = fps
        formatInfo = "Тестове відео \(url.lastPathComponent) \(Int(size.width))×\(Int(size.height)) \(Int(fps)) fps"
        DebugLog.log("test video \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height)) \(fps) fps")
        Thread.detachNewThread { [weak self] in
            var offset = CMTime.zero, t0 = CACurrentMediaTime(), dropped = 0
            while let self, self.fileGen == gen {
                guard let reader = try? AVAssetReader(asset: asset) else { break }
                let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
                out.alwaysCopiesSampleData = false
                reader.add(out); reader.startReading()
                var last = offset
                while self.fileGen == gen { let more: Bool = autoreleasepool {   // потік без run loop: без пулу кадри не звільняються
                    guard let sb = out.copyNextSampleBuffer() else { return false }
                    while self.filePaused && self.fileGen == gen { Thread.sleep(forTimeInterval: 0.1); t0 += 0.1 }
                    let pts = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sb), offset); last = pts
                    let wait = t0 + CMTimeGetSeconds(pts) - CACurrentMediaTime()
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                    else if wait < -0.1 { dropped += 1; if dropped % 100 == 1 { DebugLog.log("test video: late, dropped \(dropped)") }; return true }  // як alwaysDiscardsLateVideoFrames
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(fps.rounded())), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
                    var copy: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
                    if let c = copy { self.queue.sync { self.handle(c) } }
                    return true
                }; if !more { break } }
                reader.cancelReading()
                offset = CMTimeAdd(last, CMTime(value: 1, timescale: CMTimeScale(fps.rounded())))   // по колу, час іде далі
                if self.fileGen == gen { DebugLog.log("test video: loop") }
            }
        }
    }
}
