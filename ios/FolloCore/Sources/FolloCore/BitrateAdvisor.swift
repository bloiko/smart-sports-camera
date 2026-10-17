import Foundation

/// Picks the stream bitrate from what actually reaches YouTube (owner, 2026-10-17: "на 3 Мбіт/с нема сенсу пхати
/// 4,5"). Input once a second: the bytes the server has acknowledged on this connection and how far the stream is
/// behind live. No third-party speed test: the measurement is the real path to the ingest server.
/// - Down: the stream falls behind (delay > 2 s and growing over 10 s) → one step down, or straight to the step
///   below 85% of the measured rate (measured between acknowledgement arrivals over up to 30 s).
/// - Up: after 2 minutes steady at a lower step, try one step up; if that falls behind again, stay down 5 minutes.
public struct BitrateAdvisor: Sendable {
    public static let steps = [4500, 3500, 2500, 1800, 1200]    // kbit/s; 1080p at every step (own encoder)
    public private(set) var kbps: Int
    /// Throughput YouTube acknowledged over the last 10 s, kbit/s (at most what we send).
    public private(set) var measuredKbps: Double?
    private var samples: [(t: Double, acked: Int, delay: Double)] = []
    private var lastChange = -1e9, steadySince: Double?, noUpUntil = -1e9

    public init(startKbps: Int = 4500) { kbps = Self.steps.first { $0 <= startKbps } ?? Self.steps.last! }

    /// Returns the new bitrate when it should change.
    public mutating func update(t: Double, ackedBytes: Int, delayS: Double) -> Int? {
        if let last = samples.last, ackedBytes < last.acked { samples.removeAll() }      // new connection: counter restarts
        samples.append((t, ackedBytes, delayS)); samples.removeAll { t - $0.t > 30.5 }
        // Servers acknowledge in large windows (often 2.5 MB = 10 s at 2 Mbit/s): measure between the moments an
        // acknowledgement arrived, over up to 30 s, never between arbitrary samples.
        var arrivals: [(t: Double, acked: Int)] = []
        for s in samples where arrivals.last.map({ s.acked > $0.acked }) ?? true { arrivals.append((s.t, s.acked)) }
        if let f = arrivals.first, let l = arrivals.last, l.t - f.t >= 8 { measuredKbps = Double(l.acked - f.acked) * 8 / 1000 / (l.t - f.t) }
        if delayS < 1.5 { steadySince = steadySince ?? t } else { steadySince = nil }     // auto catch-up stops at 1 s
        guard t - lastChange >= 15, let ago = samples.last(where: { t - $0.t >= 10 }) else { return nil }
        // falling behind: the link carries less than we send → at least one step down, more if the measurement says so
        if delayS > 2, delayS > ago.delay + 0.5, let i = Self.steps.firstIndex(of: kbps), i + 1 < Self.steps.count {
            var target = Self.steps[i + 1]
            if let m = measuredKbps, let s = Self.steps.first(where: { Double($0) <= m * 0.85 }), s < target { target = s }
            if t - lastChange < 150 { noUpUntil = t + 300 }                               // a step up just failed
            return change(to: target, at: t)
        }
        // steady for 2 minutes below the top: probe one step up
        if kbps < Self.steps[0], t >= noUpUntil, let s = steadySince, t - s >= 120, t - lastChange >= 120,
           let i = Self.steps.firstIndex(of: kbps), i > 0 {
            return change(to: Self.steps[i - 1], at: t)
        }
        return nil
    }

    private mutating func change(to k: Int, at t: Double) -> Int { kbps = k; lastChange = t; steadySince = nil; return k }
}
