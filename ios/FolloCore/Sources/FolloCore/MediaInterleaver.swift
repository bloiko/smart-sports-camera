import Foundation

/// Puts audio and video into one time-ordered stream (stage 1f). The virtual camera delivers each video frame ~2 s
/// after capture while the microphone delivers audio at once, so audio waits here until the video has reached its time.
/// RTMP servers expect the two tracks interleaved by timestamp.
public struct MediaInterleaver {
    public enum Out { case audio(ms: Int64, body: Data), video(ms: Int64, body: Data, isKey: Bool) }
    private var pending: [(ms: Int64, body: Data)] = []
    public let maxPending: Int
    public private(set) var droppedAudio = 0
    public init(maxPending: Int = 3000) { self.maxPending = maxPending }

    /// Audio packet with its time on the video timeline (ms); negative times (before the first frame) are dropped.
    public mutating func audio(ms: Int64, body: Data) {
        guard ms >= 0 else { droppedAudio += 1; return }
        pending.append((ms, body))
        if pending.count > maxPending { droppedAudio += pending.count - maxPending; pending.removeFirst(pending.count - maxPending) }
    }

    /// A video frame: returns the audio that is now due (time ≤ frame time) followed by the frame.
    public mutating func video(ms: Int64, body: Data, isKey: Bool) -> [Out] {
        var out: [Out] = []
        let k = pending.firstIndex(where: { $0.ms > ms }) ?? pending.count
        for a in pending[..<k] { out.append(.audio(ms: a.ms, body: a.body)) }
        pending.removeFirst(k)
        out.append(.video(ms: ms, body: body, isKey: isKey))
        return out
    }
}
