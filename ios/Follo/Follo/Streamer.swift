import Foundation
import AVFoundation
import HaishinKit   // SPM: https://github.com/HaishinKit/HaishinKit.swift (BSD-3)

/// RTMPS-стрім 1080p на YouTube з буфером і перепідключенням до тієї самої трансляції.
/// Кадри (CVPixelBuffer 1920×1080 після віртуальної камери) надходять у push(); аудіо — з мікрофона HaishinKit.
/// Обрив мережі: кадри накопичуються в буфері до bufferSeconds, кожні 2 с спроба reconnect з тим самим ключем.
@MainActor
final class Streamer: ObservableObject {
    enum State: Equatable { case idle, connecting, live, reconnecting(attempt: Int), ended }
    @Published var state: State = .idle
    @Published var bitrateKbps = 4500
    @Published var droppedSeconds = 0.0

    private let conn = RTMPConnection()
    private lazy var stream = RTMPStream(connection: conn)
    private var url = "", key = ""
    private var buffer: [(CVPixelBuffer, CMTime)] = []
    private let bufferSeconds = 60.0
    private var reconnectTask: Task<Void, Never>?
    private var fps = 30.0
    private let bitrateSteps = [4500, 3000, 2000]        // Мбіт/с × 1000; 2000 → 720p

    func start(url: String, key: String) async {
        self.url = url; self.key = key
        stream.videoSettings = .init(videoSize: .init(width: 1920, height: 1080), bitRate: bitrateKbps * 1000,
                                     profileLevel: kVTProfileLevel_H264_High_AutoLevel as String, maxKeyFrameIntervalDuration: 2)
        stream.frameRate = fps
        stream.audioSettings = .init(bitRate: 128_000)
        try? stream.attachAudio(AVCaptureDevice.default(for: .audio))
        conn.addEventListener(.rtmpStatus, selector: #selector(onStatus), observer: self)
        await connect()
    }

    private func connect() async {
        state = state == .idle ? .connecting : state
        conn.connect(url)                     // rtmps://a.rtmps.youtube.com:443/live2
        stream.publish(key)
    }

    @objc private func onStatus(_ n: Notification) {
        guard let e = Event.from(n), let data = e.data as? ASObject, let code = data["code"] as? String else { return }
        switch RTMPConnection.Code(rawValue: code) {
        case .connectSuccess: state = .live; reconnectTask?.cancel(); flushBuffer()
        case .connectClosed, .connectFailed: scheduleReconnect()
        default: break
        }
    }

    /// Пункт 1: перепідключення до тієї самої трансляції кожні 2 с; YouTube тримає broadcast ~2 хв без даних.
    private func scheduleReconnect() {
        guard state != .ended, reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            var attempt = 0
            while let self, self.state != .ended, !Task.isCancelled {
                attempt += 1; self.state = .reconnecting(attempt: attempt)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if attempt % 5 == 0 { self.stepBitrateDown() }     // пункт 5: слабкий інтернет → менший бітрейт
                await self.connect()
                if self.state == .live { break }
            }
            self?.reconnectTask = nil
        }
    }

    /// Пункт 2: буфер кадрів до 60 с на час обриву.
    func push(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if state == .live {
            stream.append(CMSampleBuffer.from(pixelBuffer, time: time))
        } else {
            buffer.append((pixelBuffer, time))
            let limit = Int(bufferSeconds * fps)
            if buffer.count > limit { buffer.removeFirst(buffer.count - limit); droppedSeconds += 1 / fps }
        }
    }

    private func flushBuffer() {
        for (pb, t) in buffer { stream.append(CMSampleBuffer.from(pb, time: t)) }
        buffer.removeAll()
    }

    func stepBitrateDown() {
        if let i = bitrateSteps.firstIndex(of: bitrateKbps), i + 1 < bitrateSteps.count {
            bitrateKbps = bitrateSteps[i + 1]
            let size: CGSize = bitrateKbps <= 2000 ? .init(width: 1280, height: 720) : .init(width: 1920, height: 1080)
            stream.videoSettings.bitRate = bitrateKbps * 1000; stream.videoSettings.videoSize = size
        }
    }

    /// Пункт 4: нагрів → 25 fps.
    func setFrameRate(_ f: Double) { fps = f; stream.frameRate = f }

    func stop() {
        state = .ended; reconnectTask?.cancel()
        stream.close(); conn.close()
    }
}

extension CMSampleBuffer {
    static func from(_ pb: CVPixelBuffer, time: CMTime) -> CMSampleBuffer {
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: fmt!, sampleTiming: &timing, sampleBufferOut: &sb)
        return sb!
    }
}
