import Foundation

/// Highlight moments from the live camera path: goal-area episodes scored by ball proximity and extra players;
/// goals = the last episode before a kick-off. Port of moments() and mark_goals() in src/highlights.py.
public struct Moment {
    public var start: Double, end: Double, peak: Double, goal: Int, kind: String, epEnd: Double, score: Double, ball: Double, players: Double
    public var kickoff: Double? = nil
    public var file: String? = nil
    public var label: String { let t = Int(peak); return "\(t / 60):" + String(format: "%02d", t % 60) + "  " + (kind == "goal" ? "GOAL  " : "chance  ") + (goal == 0 ? "left goal" : "right goal") }
}

public enum Highlights {
    public static let before = 8.0, after = 4.0, maxLen = 20.0, minEp = 2.5, minScore = 0.3, goalBeforeKickoff = 45.0, goalMaxLen = 30.0

    public static func moments(_ fr: [LiveCamera.Frame], fps: Double, goals: [Pt], sFrames: [Int], zn: [[Int]], base: [Double]) -> [Moment] {
        let n = fr.count; let D = Stats.hypot(goals[1].x - goals[0].x, goals[1].y - goals[0].y); var out: [Moment] = []
        var a = -1
        for f in 0...n {
            let on = f < n && fr[f].gon
            if on && a < 0 { a = f }
            if !on && a >= 0 {
                if let m = moment(fr, a: a, b: f, fps: fps, goals: goals, D: D, sFrames: sFrames, zn: zn, base: base, n: n) { out.append(m) }
                a = -1
            }
        }
        return out
    }

    static func moment(_ fr: [LiveCamera.Frame], a: Int, b: Int, fps: Double, goals: [Pt], D: Double, sFrames: [Int], zn: [[Int]], base: [Double], n: Int) -> Moment? {
        if Double(b - a) / fps < minEp { return nil }
        var cnt = [0, 0]; for f in a..<b where fr[f].gi >= 0 { cnt[fr[f].gi] += 1 }
        let g = cnt[0] + cnt[1] == 0 ? 0 : (cnt[1] > cnt[0] ? 1 : 0)
        var dmin = Double.infinity, seen = false; var hot: [Int] = []
        for f in a..<b { if let p = fr[f].ball { seen = true; let d = Stats.hypot(p.x - goals[g].x, p.y - goals[g].y) / D; dmin = min(dmin, d); if d < 0.1 { hot.append(f) } } }
        let si = (0..<sFrames.count).filter { sFrames[$0] >= a && sFrames[$0] < b }
        let extra = si.map { Double(zn[$0][g]) - base[g] }; let emax = extra.max() ?? 0
        let ball = seen ? Stats.clip(1 - dmin / 0.15, 0, 1) : 0.0
        let players = Stats.clip((si.isEmpty ? 0 : emax) / 10, 0, 1)
        if !si.isEmpty && emax > 0 { for (i, e) in zip(si, extra) where e >= 0.8 * emax { hot.append(sFrames[i]) } }
        let first = hot.min() ?? (a + b) / 2, last = hot.max() ?? (a + b) / 2
        var t0 = max(Double(a) / fps - 3, Double(first) / fps - before); var t1 = min(Double(b) / fps + 2, Double(last) / fps + after, Double(n) / fps)
        t1 = min(t1, t0 + maxLen); t0 = (t0 * 10).rounded() / 10; t1 = (t1 * 10).rounded() / 10
        return Moment(start: t0, end: t1, peak: (Double(first) / fps * 10).rounded() / 10, goal: g, kind: "chance", epEnd: (Double(b) / fps * 10).rounded() / 10,
                      score: ((ball + players) / 2 * 100).rounded() / 100, ball: (ball * 100).rounded() / 100, players: (players * 100).rounded() / 100)
    }

    /// The last episode before each kick-off (within goalBeforeKickoff) is a goal; its clip runs to the episode end + 4 s.
    public static func markGoals(_ ms: inout [Moment], kickoffs: [(Double, Double)]) {
        for (t, _) in kickoffs {
            let idx = (0..<ms.count).filter { ms[$0].epEnd <= t + 1 && t - ms[$0].epEnd <= goalBeforeKickoff }
            guard let i = idx.max(by: { ms[$0].epEnd < ms[$1].epEnd }) else { continue }
            ms[i].kind = "goal"; ms[i].score = 1; ms[i].kickoff = t
            ms[i].end = (min(ms[i].epEnd + after, ms[i].start + goalMaxLen) * 10).rounded() / 10
        }
    }
}
