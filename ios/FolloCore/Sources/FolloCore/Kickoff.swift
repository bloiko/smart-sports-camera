import Foundation

/// Kick-off from the centre = a goal just happened: both teams in their own halves. Port of src/kickoff.py.
public enum Kickoff {
    public static let sep = 0.77, smoothS = 2.0, gapS = 20.0

    /// k-means (2 clusters, k-means++ start, 5 attempts, best compactness) on (a, b); returns labels.
    static func kmeans2(_ pts: [(Double, Double)]) -> [Int] {
        var rng = LCG(seed: 12345); var bestLab: [Int] = []; var bestCost = Double.infinity      // seeded: the same result on every run
        func d2(_ p: (Double, Double), _ q: (Double, Double)) -> Double { (p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) }
        for _ in 0..<5 {
            var c = [pts[Int.random(in: 0..<pts.count, using: &rng)]]
            let w = pts.map { d2($0, c[0]) }; let tot = w.reduce(0, +); var r = Double.random(in: 0..<max(tot, 1e-9), using: &rng); var j = 0
            while j < pts.count - 1 && r > w[j] { r -= w[j]; j += 1 }; c.append(pts[j])
            var lab = [Int](repeating: 0, count: pts.count)
            for _ in 0..<50 {
                var changed = false
                for i in 0..<pts.count { let l = d2(pts[i], c[0]) <= d2(pts[i], c[1]) ? 0 : 1; if l != lab[i] { lab[i] = l; changed = true } }
                for k in 0..<2 { let m = (0..<pts.count).filter { lab[$0] == k }; if !m.isEmpty { c[k] = (m.map { pts[$0].0 }.reduce(0, +) / Double(m.count), m.map { pts[$0].1 }.reduce(0, +) / Double(m.count)) } }
                if !changed { break }
            }
            let cost = (0..<pts.count).map { d2(pts[$0], c[lab[$0]]) }.reduce(0, +)
            if cost < bestCost { bestCost = cost; bestLab = lab }
        }
        return bestLab
    }

    /// Time (s) and smoothed team separation by the halfway line (x = centreX) for every sampled frame.
    public static func separation(_ F: [JerseySample], centreX: Double, fps: Double) -> (t: [Double], s: [Double]) {
        guard F.count >= 8 else { return ([], []) }
        let lab = kmeans2(F.map { ($0.a, $0.b) })
        var cent = [(0.0, 0.0), (0.0, 0.0)], n = [0.0, 0.0]
        for i in 0..<F.count { cent[lab[i]].0 += F[i].a; cent[lab[i]].1 += F[i].b; n[lab[i]] += 1 }
        for k in 0..<2 where n[k] > 0 { cent[k] = (cent[k].0 / n[k], cent[k].1 / n[k]) }
        let d = (0..<F.count).map { Stats.hypot(F[$0].a - cent[lab[$0]].0, F[$0].b - cent[lab[$0]].1) }
        let thr = Stats.percentile(d, 85); let ok = d.map { $0 < thr }
        let frames = Array(Set(F.map { $0.frame })).sorted(); var S: [Double] = []
        for fr in frames {
            var a: [Double] = [], b: [Double] = []
            for i in 0..<F.count where F[i].frame == fr && ok[i] { if lab[i] == 0 { a.append(F[i].x) } else { b.append(F[i].x) } }
            if a.count < 4 || b.count < 4 { S.append(0.5); continue }     // nan → 0.5 as in Python's nan_to_num
            let al = Double(a.filter { $0 < centreX }.count) / Double(a.count), ar = 1 - al
            let br = Double(b.filter { $0 > centreX }.count) / Double(b.count), bl = 1 - br
            S.append(max((al + br) / 2, (ar + bl) / 2))
        }
        let T = frames.map { Double($0) / fps }
        var dt = [Double](); for i in 1..<T.count { dt.append(T[i] - T[i - 1]) }
        let k = max(1, Int((smoothS / max(dt.isEmpty ? 1 : Stats.percentile(dt, 50), 1e-6)).rounded()))
        // numpy.convolve(ones(k)/k, 'same'): window centred, zero padded
        var out = [Double](repeating: 0, count: S.count); let lo = (k - 1) / 2
        for i in 0..<S.count { var acc = 0.0; for j in 0..<k { let idx = i - lo + j; if idx >= 0 && idx < S.count { acc += S[idx] } }; out[i] = acc / Double(k) }
        return (T, out)
    }

    /// Starts of stretches with s ≥ thr, at least gapS apart: [(time, peak)].
    public static func find(_ T: [Double], _ S: [Double], thr: Double = sep) -> [(Double, Double)] {
        var out: [(t: Double, peak: Double, last: Double)] = []
        for i in 0..<S.count where S[i] >= thr {
            if let l = out.last, T[i] - l.last <= gapS { out[out.count - 1].peak = max(l.peak, S[i]); out[out.count - 1].last = T[i] }
            else { out.append((T[i], S[i], T[i])) }
        }
        return out.map { (($0.t * 10).rounded() / 10, ($0.peak * 100).rounded() / 100) }
    }
}

/// Small seeded generator so the kick-off search is reproducible (cv2.kmeans is deterministic per process too).
struct LCG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
