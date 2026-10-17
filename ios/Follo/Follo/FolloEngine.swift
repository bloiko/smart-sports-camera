import Foundation
import AVFoundation
import UIKit
import FolloCore

/// The own stream path (stage 1f, behind `Streamer.engine == .follo`): our H.264 + AAC encoders, our RTMP client with the
/// 60–180 s drop buffer (`FolloStreamer`). HaishinKit stays as the default until the phone tests pass
/// (docs/detector-licence-plan.md, rollback plan).
final class FolloEngine: @unchecked Sendable {        // state on `q`
    private var video: VideoEncoder?, audio: AudioEncoder?, streamer: FolloStreamer?
    private let mic = AVAudioEngine()
    private let q = DispatchQueue(label: "follo.engine")
    private var t0: Double?                       // video timeline origin (seconds, the video pts clock)
    private var hostOffset: Double?               // audio host time → video pts clock (test video has its own clock)
    private var headersSet = false, lastVideoMs: Int64 = -1
    private var interleaver = MediaInterleaver()
    private(set) var audioPackets = 0, videoFrames = 0
    var isPublishing: Bool { streamer?.isPublishing ?? false }
    var reconnects: Int { streamer?.reconnects ?? 0 }
    var delayS: Double { streamer?.delayS ?? 0 }
    /// Bytes YouTube acknowledged on this connection (BitrateAdvisor input).
    var ackedBytes: Int { streamer?.ackedBytes ?? 0 }
    /// Mute button: the microphone is replaced by silence; the audio track keeps running (YouTube expects it).
    var muted = false

    func start(url: String, key: String, bitrate: Int, fps: Double) throws {
        var vs = VideoEncoder.Settings(); vs.bitrate = bitrate; vs.fps = fps
        let v = try VideoEncoder(vs); video = v
        v.onEvent = { DebugLog.log("engine follo: " + $0) }
        // iOS invalidates hardware encoder sessions while the app is suspended: recreate on return (HaishinKit does the same)
        fgObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak v] _ in
            DebugLog.log("engine follo: app back in the foreground → new encoder session"); v?.reset()
        }
        v.onFrame = { [weak self] f in self?.q.async { self?.videoOut(f) } }
        let s = FolloStreamer(url: url, key: key); s.log = { DebugLog.log("streamer: " + $0) }; streamer = s; s.start()
        #if targetEnvironment(simulator)
        // the simulator's audio service times out in AURemoteIO::Initialize and aborts the app (UI tests, 2026-10-17)
        DebugLog.log("mic: simulator — stream without audio")
        #else
        do { try startMic() } catch { DebugLog.log("mic: \(error.localizedDescription) — stream without audio") }
        #endif
        DebugLog.log("engine follo: \(bitrate / 1000) kbit/s, audio \(audio != nil)")
    }

    func push(_ pb: CVPixelBuffer, at t: CMTime) { video?.encode(pb, pts: t) }
    /// One line for the live log every 10 s: encoder and streamer counters (a silent stop shows at once).
    var diag: String {
        guard let v = video else { return "" }
        return "enc in \(v.submitted) out \(v.encoded) drop \(v.dropped) resets \(v.resets) err \(v.lastErrorStatus) | audio \(audioPackets) | \(streamer?.diag ?? "")"
    }
    private var fgObserver: NSObjectProtocol?
    func setBitrate(_ b: Int) { video?.setBitrate(b) }
    func catchUp() { streamer?.jumpToLive() }

    func stop() {
        if let o = fgObserver { NotificationCenter.default.removeObserver(o) }
        mic.inputNode.removeTap(onBus: 0); mic.stop()
        video?.flush()
        q.async { [self] in
            streamer?.stop(drainS: 5) { DebugLog.log("engine follo stopped") }
        }
    }

    // ---------------------------------------------------------------- video

    private func videoOut(_ f: VideoEncoder.Frame) {
        guard let s = streamer else { return }
        let sec = CMTimeGetSeconds(f.pts)
        if t0 == nil {
            t0 = sec
            // Camera frames carry their capture time on the host clock, the same clock as the microphone: offset 0 keeps
            // lip-sync although the virtual camera delivers each frame 2 s later. The test video has its own clock:
            // map by arrival (its audio is the microphone anyway, not the match).
            let now = CACurrentMediaTime()
            hostOffset = abs(sec - now) < 30 ? 0 : sec - now
            DebugLog.log("engine follo: video clock \(hostOffset == 0 ? "host (camera)" : "own (test video)")")
        }
        if !headersSet, let avcC = FLV.avcC(of: f.format) {
            s.setHeaders(meta: FLV.metadata(width: 1920, height: 1080, fps: video?.settings.fps ?? 30, videoKbps: Double(video?.settings.bitrate ?? 4_500_000) / 1000, audio: audio != nil),
                         avc: FLV.videoSequenceHeader(avcC: avcC), aac: audio.map { FLV.audioSequenceHeader(asc: $0.audioSpecificConfig) })
            headersSet = true
        }
        let ms = Int64(((sec - t0!) * 1000).rounded()); guard ms >= 0 else { return }
        // audio waits until the video has reached it: one time-ordered stream (the virtual camera delays video by 2 s)
        for o in interleaver.video(ms: ms, body: FLV.videoPacket(f.data, isKey: f.isKey), isKey: f.isKey) {
            switch o {
            case .audio(let a, let body): s.push(.audio, body: body, ms: UInt32(a), isKey: false)
            case .video(let v, let body, let key): s.push(.video, body: body, ms: UInt32(v), isKey: key)
            }
        }
        lastVideoMs = ms; videoFrames += 1
    }

    // ---------------------------------------------------------------- audio (microphone)

    private func startMic() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try session.setActive(true)
        let input = mic.inputNode, fmt = input.outputFormat(forBus: 0)
        var a = AudioEncoder.Settings(); a.sampleRate = fmt.sampleRate; a.channels = min(2, Int(fmt.channelCount))
        let enc = try AudioEncoder(a); audio = enc
        guard let conv = AVAudioConverter(from: fmt, to: enc.inputFormat) else { throw NSError(domain: "FolloEngine", code: 1) }
        var firstSampleHost: Double?
        enc.onPacket = { [weak self] d, sample in
            guard let self, let h0 = firstSampleHost else { return }
            let host = h0 + Double(sample) / a.sampleRate
            self.q.async {
                guard let t0 = self.t0, let off = self.hostOffset else { return }       // before the first video frame: drop
                self.interleaver.audio(ms: Int64(((host + off - t0) * 1000).rounded()), body: FLV.audioPacket(d)); self.audioPackets += 1
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, when in
            if firstSampleHost == nil { firstSampleHost = AVAudioTime.seconds(forHostTime: when.hostTime) }
            guard let out = AVAudioPCMBuffer(pcmFormat: enc.inputFormat, frameCapacity: buf.frameLength) else { return }
            var given = false
            conv.convert(to: out, error: nil) { _, st in if given { st.pointee = .noDataNow; return nil }; given = true; st.pointee = .haveData; return buf }
            if self?.muted == true, let ch = out.floatChannelData {
                for c in 0..<Int(out.format.channelCount) { ch[c].update(repeating: 0, count: Int(out.frameLength)) }
            }
            enc.append(out)
        }
        try mic.start()
    }
}
