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
    private var previewCount = 0
    private let previewCtx = CIContext(options: [.cacheIntermediates: false])
    let chunkSeconds: Double = 180

    @Published var cameraError: String?

    func configure() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { self.cameraError = "Немає дозволу на камеру: Параметри → Follo → Камера" }; return }
            self.queue.async { self.setup() }
        }
    }

    private func setup() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        let dev = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let dev, let input = try? AVCaptureDeviceInput(device: dev) else {
            session.commitConfiguration(); DispatchQueue.main.async { self.cameraError = "Камеру не знайдено" }; return
        }
        if session.canAddInput(input) { session.addInput(input) }
        // найбільший формат до 3840 px шириною з 30 fps (4K на ультраширокій є не на всіх моделях)
        let fmts = dev.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width <= 3840 && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
                && CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        if let fmt = fmts.max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
            do {
                try dev.lockForConfiguration()
                dev.activeFormat = fmt
                dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                dev.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.cameraError = "Формат: \(error.localizedDescription)" } }
        }
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        if let c = out.connection(with: .video), c.isVideoRotationAngleSupported(0) { c.videoRotationAngle = 0 }
        session.commitConfiguration()
        session.startRunning()
        let d = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription)
        DispatchQueue.main.async { self.cameraError = self.session.isRunning ? nil : "Камера не запустилась"; self.formatInfo = "\(dev.localizedName) \(d.width)×\(d.height)" }
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
        writer?.append(sampleBuffer)
        frameHandler?(sampleBuffer)
        previewCount += 1
        if previewCount % 6 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {   // прев'ю 5 fps, 960 px
            let ci = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            if let cg = previewCtx.createCGImage(ci, from: ci.extent) { let ui = UIImage(cgImage: cg); DispatchQueue.main.async { self.previewImage = ui } }
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

    private func open(at time: CMTime) {
        index += 1
        let url = Self.dir.appendingPathComponent(String(format: "chunk_%03d.mp4", index))
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 3840, AVVideoHeightKey: 2160,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 30_000_000]])
        i.expectsMediaDataInRealTime = true
        w.add(i); w.startWriting(); w.startSession(atSourceTime: time)
        writer = w; input = i; chunkStart = time
    }

    func append(_ sb: CMSampleBuffer) {
        let t = CMSampleBufferGetPresentationTimeStamp(sb)
        if writer == nil { open(at: t) }
        if let s = chunkStart, CMTimeGetSeconds(CMTimeSubtract(t, s)) >= chunkSeconds { finish(); open(at: t) }
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
