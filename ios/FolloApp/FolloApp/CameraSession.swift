import AVFoundation
import Combine

/// 4K 30 fps з ультраширокої камери, запис файлами по chunkSeconds, кадри для нейромережі через delegate.
final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera")
    private var writer: ChunkWriter?
    @Published var isRecording = false
    @Published var chunkCount = 0
    @Published var frameHandler: ((CMSampleBuffer) -> Void)?
    let chunkSeconds: Double = 180

    func configure() {
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .inputPriority
            guard let dev = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: dev) else { self.session.commitConfiguration(); return }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            // формат 3840×2160 @30
            if let fmt = dev.formats.first(where: { f in
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                return d.width == 3840 && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            }) {
                try? dev.lockForConfiguration()
                dev.activeFormat = fmt
                dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                dev.unlockForConfiguration()
            }
            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(out) { self.session.addOutput(out) }
            out.connection(with: .video)?.videoRotationAngle = 0
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

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
