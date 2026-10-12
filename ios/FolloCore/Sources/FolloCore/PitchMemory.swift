import Foundation

/// Memory of a known pitch: when the phone stands where it stood before (same field mask and halfway line), the goals
/// of the previous match are known from the first second (LiveGoals prior). Stored as JSON in the app's Documents.
/// Matching (2026-10-12, matches 1 and 2 of the test set, same stadium on different days): mask IoU 0.81, halfway line
/// within 6 px, hand-measured goals within 13 px → thresholds IoU ≥ 0.75 and line within 30 px.
public struct PitchMemory: Codable {
    public var w: Int, h: Int
    public var maskSmall: [UInt8]            // field mask at 1/16 resolution
    public var clineX0: Double, clineX1: Double
    public var goals: [[Double]]
    public var date: Date

    public static let small = 16

    public init(env: LiveEnv, goals: [Pt]) {
        w = env.W; h = env.H; maskSmall = Self.shrink(env.fm ?? env.fmd); clineX0 = env.centreEnds?.0 ?? .nan; clineX1 = env.centreEnds?.1 ?? .nan
        self.goals = goals.map { [$0.x, $0.y] }; date = Date()
    }

    static func shrink(_ m: Mask) -> [UInt8] {
        let s = small, sw = m.w / s, sh = m.h / s; var out = [UInt8](repeating: 0, count: sw * sh)
        for y in 0..<sh { for x in 0..<sw { out[y * sw + x] = m[x: x * s + s / 2, y: y * s + s / 2] ? 1 : 0 } }
        return out
    }

    /// Goals of this memory if `env` is the same pitch from the same place, else nil.
    public func prior(for env: LiveEnv) -> [Pt]? {
        guard env.W == w, env.H == h, let c = env.centreEnds, !clineX0.isNaN else { return nil }
        let m = Self.shrink(env.fm ?? env.fmd); var inter = 0, uni = 0
        for i in 0..<min(m.count, maskSmall.count) { if m[i] != 0 && maskSmall[i] != 0 { inter += 1 }; if m[i] != 0 || maskSmall[i] != 0 { uni += 1 } }
        let iou = uni > 0 ? Double(inter) / Double(uni) : 0
        guard iou >= 0.75, abs(c.0 - clineX0) <= 30, abs(c.1 - clineX1) <= 30 else { return nil }
        return goals.map { Pt($0[0], $0[1]) }
    }

    // ---- store: a list of pitches in a JSON file
    public static func load(_ url: URL) -> [PitchMemory] { (try? JSONDecoder().decode([PitchMemory].self, from: Data(contentsOf: url))) ?? [] }

    public static func remember(_ m: PitchMemory, in url: URL) {
        var all = load(url)
        all.removeAll { $0.w == m.w && $0.h == m.h && abs($0.clineX0 - m.clineX0) <= 30 && abs($0.clineX1 - m.clineX1) <= 30 }   // replace the same pitch
        all.append(m); if all.count > 20 { all.removeFirst(all.count - 20) }
        try? JSONEncoder().encode(all).write(to: url)
    }
}
