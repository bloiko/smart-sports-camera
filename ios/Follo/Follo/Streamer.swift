import Foundation
import Combine
import AVFoundation
import HaishinKit        // SPM: https://github.com/HaishinKit/HaishinKit.swift (BSD-3), 2.x
import RTMPHaishinKit    // RTMP lives in its own module since 2.0

/// RTMPS-стрім 1080p на YouTube з буфером і перепідключенням до тієї самої трансляції.
/// Кадри (CVPixelBuffer 1920×1080 після віртуальної камери) надходять у push(); аудіо — з мікрофона через MediaMixer.
/// Обрив мережі: кадри накопичуються в буфері до bufferSeconds, кожні 2 с спроба reconnect з тим самим ключем.
@MainActor
final class Streamer: ObservableObject {
    enum State: Equatable { case idle, connecting, live, reconnecting(attempt: Int), ended }
    @Published var state: State = .idle
    @Published var bitrateKbps = 4500
    @Published var droppedSeconds = 0.0

    private let conn = RTMPConnection()
    private lazy var stream = RTMPStream(connection: conn)
    private let mixer = MediaMixer(captureSessionMode: .multi)
    private var url = "", key = ""
    private var buffer: [(CVPixelBuffer, CMTime)] = []
    private let bufferSeconds = 60.0
    private var reconnectTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var fps = 30.0
    private let bitrateSteps = [4500, 3000, 2000]        // кбіт/с; 2000 → 720p

    func start(url: String, key: String) async {
        self.url = url; self.key = key
        try? await stream.setVideoSettings(videoSettings())
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
        // аудіо з мікрофона: mixer → stream; відео ми подаємо самі через push()
        try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
        await mixer.addOutput(stream)
        await mixer.startRunning()
        statusTask = Task { [weak self] in
            guard let self else { return }
            for await st in await conn.status {
                switch st.code {
                case "NetConnection.Connect.Success": break
                case "NetConnection.Connect.Closed", "NetConnection.Connect.Failed": self.scheduleReconnect()
                default: break
                }
            }
        }
        await connect()
    }

    private func videoSettings() -> VideoCodecSettings {
        let size: CGSize = bitrateKbps <= 2000 ? .init(width: 1280, height: 720) : .init(width: 1920, height: 1080)
        return VideoCodecSettings(videoSize: size, bitRate: bitrateKbps * 1000,
                                  profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
                                  maxKeyFrameIntervalDuration: 2, expectedFrameRate: fps)
    }

    private func connect() async {
        if state == .idle { state = .connecting }
        do {
            _ = try await conn.connect(url)              // rtmps://a.rtmps.youtube.com:443/live2
            _ = try await stream.publish(key)
            state = .live; reconnectTask?.cancel(); reconnectTask = nil
            await flushBuffer()
        } catch {
            scheduleReconnect()
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
                if attempt % 5 == 0 { await self.stepBitrateDown() }   // пункт 5: слабкий інтернет → менший бітрейт
                try? await self.conn.close()
                await self.connect()
                if self.state == .live { break }
            }
            self?.reconnectTask = nil
        }
    }

    /// Пункт 2: буфер кадрів до 60 с на час обриву.
    func push(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if state == .live {
            let sb = CMSampleBuffer.from(pixelBuffer, time: time)
            Task { await stream.append(sb) }
        } else {
            buffer.append((pixelBuffer, time))
            let limit = Int(bufferSeconds * fps)
            if buffer.count > limit { buffer.removeFirst(buffer.count - limit); droppedSeconds += 1 / fps }
        }
    }

    private func flushBuffer() async {
        let pending = buffer; buffer.removeAll()
        for (pb, t) in pending { await stream.append(CMSampleBuffer.from(pb, time: t)) }
    }

    func stepBitrateDown() async {
        if let i = bitrateSteps.firstIndex(of: bitrateKbps), i + 1 < bitrateSteps.count {
            bitrateKbps = bitrateSteps[i + 1]
            try? await stream.setVideoSettings(videoSettings())
        }
    }

    /// Пункт 4: нагрів → 25 fps.
    func setFrameRate(_ f: Double) { fps = f; Task { try? await stream.setVideoSettings(videoSettings()) } }

    func stop() {
        state = .ended; reconnectTask?.cancel(); statusTask?.cancel()
        Task { _ = try? await stream.close(); try? await conn.close(); await mixer.stopRunning() }
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
