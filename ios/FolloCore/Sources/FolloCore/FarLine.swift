import Foundation

/// The far touchline as y(x) = y0 + b·u + c·u², u = x/W − 0.5. Port of `far_line` in src/fieldmask.py, line for line.
/// The grass mask also took the trees and a neighbouring pitch behind the stand (m2: "balls" on people there held the
/// camera; with the near corners out of frame the green behind the goals reached the frame edges and the position
/// check said "turn" for nothing). There is no pitch above the far touchline: the mask is cut there, with a margin
/// for a ball in the air, and the ends of the line were meant as the ends of the pitch. On: FIELD_LINE=1 / --field-line.
public struct FarLine: Equatable {
    public var y0: Double, b: Double, c: Double
    public var xl: Int, xr: Int, cover: Double

    /// OFF by default (2026-10-23), experiments only (results.md): the ends of the line are the far corners, and the
    /// goals stand further out, so "line ends in frame" passed a frame with the left goal cut off (test10 video).
    public static let enabled = ProcessInfo.processInfo.environment["FIELD_LINE"] == "1" || CommandLine.arguments.contains("--field-line")
    /// Also cut the mask above the line: on m2 it changed the ball search both ways (0:13.5 full frame 100% → 48%).
    public static let cutEnabled = enabled && (ProcessInfo.processInfo.environment["FIELD_LINE_CUT"] == "1" || CommandLine.arguments.contains("--field-line-cut"))
    static let bs: [Double] = stride(from: -300, through: 300, by: 10).map(Double.init)
    static let cs: [Double] = stride(from: -200, through: 2000, by: 20).map(Double.init)
    static let margin = 0.04

    public func y(_ x: Double, W: Int) -> Double { let u = x / Double(W) - 0.5; return y0 + b * u + c * u * u }

    /// Candidates: white pixels with grass 4 px above and below, in the upper 45% of the pitch in each column,
    /// the 3 highest per column. (b, c) on a grid, y0 = peak of a 1 px histogram (±1 px); no randomness.
    public static func find(median med: Image8, mask m: Mask) -> FarLine? {
        let W = m.w, H = m.h
        var white = [Bool](repeating: false, count: W * H), grass = white
        for i in 0..<(W * H) {
            let (hh, s, v) = Image8.hsv(b: med.data[i * 3], g: med.data[i * 3 + 1], r: med.data[i * 3 + 2])
            white[i] = s < 70 && v > 150; grass[i] = hh >= 35 && hh <= 95 && s >= 30 && v >= 30
        }
        var xs: [Double] = [], ys: [Double] = []
        for x in 0..<W {
            var top = -1, bot = -1
            for y in 0..<H where m.data[y * W + x] != 0 { if top < 0 { top = y }; bot = y }
            guard top >= 0 else { continue }
            let lim = Double(top) + 0.45 * Double(bot - top); var n = 0
            for y in 4..<(H - 4) where n < 3 {
                if Double(y) > lim { break }
                let i = y * W + x
                if white[i] && grass[i - 4 * W] && grass[i + 4 * W] && m.data[i] != 0 { xs.append(Double(x)); ys.append(Double(y)); n += 1 }
            }
        }
        if xs.count < 50 { return nil }
        let u = xs.map { $0 / Double(W) - 0.5 }
        var best = (n: -1, b: 0.0, c: 0.0, y0: 0)
        var hist = [Int](repeating: 0, count: H)
        for b in bs { for c in cs {
            for k in 0..<H { hist[k] = 0 }
            for i in 0..<xs.count { let y0 = Int((ys[i] - b * u[i] - c * u[i] * u[i]).rounded(.down)); if y0 >= 0 && y0 < H { hist[y0] += 1 } }
            var bk = 0, bv = -1
            for k in 0..<(H - 2) { let v = hist[k] + hist[k + 1] + hist[k + 2]; if v > bv { bv = v; bk = k } }
            if bv > best.n { best = (bv, b, c, bk + 1) }
        } }
        let y0 = Double(best.y0), b = best.b, c = best.c
        var cols: [Int] = []
        for i in 0..<xs.count where abs(ys[i] - (y0 + b * u[i] + c * u[i] * u[i])) <= 2 { cols.append(Int(xs[i])) }
        cols = Array(Set(cols)).sorted()
        if cols.count < 2 { return nil }
        let gap = max(1, Int(0.05 * Double(W))); var runs: [(Int, Int)] = []; var s0 = cols[0], prev = cols[0]
        for x in cols.dropFirst() { if x - prev > gap { runs.append((s0, prev)); s0 = x }; prev = x }
        runs.append((s0, prev))
        var run = runs[0]; for r in runs.dropFirst() where r.1 - r.0 > run.1 - run.0 { run = r }
        let (xl, xr) = run
        let cover = Double(cols.filter { $0 >= xl && $0 <= xr }.count) / Double(W)
        if cover < 0.15 || Double(xr - xl) < 0.4 * Double(W) { return nil }
        return FarLine(y0: y0, b: b, c: c, xl: xl, xr: xr, cover: (cover * 1000).rounded() / 1000)
    }

    /// The mask without everything above the line minus the margin.
    public func cut(_ m: Mask) -> Mask {
        var out = m
        for x in 0..<m.w {
            let lim = y(Double(x), W: m.w) - Self.margin * Double(m.h)
            for y in 0..<m.h where Double(y) < lim { out.data[y * m.w + x] = 0 }
        }
        return out
    }

    public func scaled(_ k: Int) -> FarLine { let kk = Double(k); return FarLine(y0: y0 * kk, b: b * kk, c: c * kk, xl: xl * k, xr: xr * k, cover: cover) }
    public var json: [String: Any] { ["y0": y0, "b": b, "c": c, "xl": xl, "xr": xr, "cover": cover] }
    public init(y0: Double, b: Double, c: Double, xl: Int, xr: Int, cover: Double) { self.y0 = y0; self.b = b; self.c = c; self.xl = xl; self.xr = xr; self.cover = cover }
    public init?(json o: Any?) {
        guard let o = o as? [String: Any], let y0 = o["y0"] as? Double, let b = o["b"] as? Double, let c = o["c"] as? Double,
              let xl = o["xl"] as? Int, let xr = o["xr"] as? Int else { return nil }
        self.init(y0: y0, b: b, c: c, xl: xl, xr: xr, cover: o["cover"] as? Double ?? 0)
    }
}
