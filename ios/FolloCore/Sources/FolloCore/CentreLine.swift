import Foundation

/// Halfway line of the pitch: the nearly vertical straight line near the middle of the pitch with the most white
/// pixels (the phone stands at the halfway line). Port of centre_line() in src/goals.py. Returns x(y).
public enum CentreLine {
    public static func find(mask fm: Mask, median med: Image8) -> ((Double) -> Double)? {
        let s = 2; let m2 = med.half(); let w = m2.w, h = m2.h
        var fm2 = Mask(w: w, h: h)
        for y in 0..<h { for x in 0..<w { fm2.data[y * w + x] = fm.data[(y * s) * fm.w + x * s] } }   // INTER_NEAREST
        // V channel top-hat with a 9×1 kernel: V − open(V); S channel for "white"
        var V = [Int](repeating: 0, count: w * h), S = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) { let p = Image8.hsv(b: m2.data[i * 3], g: m2.data[i * 3 + 1], r: m2.data[i * 3 + 2]); S[i] = p.1; V[i] = p.2 }
        var er = V, op = V
        for y in 0..<h { for x in 0..<w { var mn = 255; for dx in -4...4 { let xx = min(max(x + dx, 0), w - 1); mn = min(mn, V[y * w + xx]) }; er[y * w + x] = mn } }
        for y in 0..<h { for x in 0..<w { var mx = 0; for dx in -4...4 { let xx = min(max(x + dx, 0), w - 1); mx = max(mx, er[y * w + xx]) }; op[y * w + x] = mx } }
        let fe = fm2.eroded(7)
        var ridge: [(Int, Int)] = []
        var xmin = w, xmax = 0, ymin = h, ymax = 0
        for y in 0..<h { for x in 0..<w {
            if fm2[x: x, y: y] { xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y) }
            if V[y * w + x] - op[y * w + x] > 35 && S[y * w + x] < 80 && fe[x: x, y: y] { ridge.append((x, y)) }
        } }
        if ridge.isEmpty || xmax <= xmin { return nil }
        let mid = Double(xmin + xmax) / 2, span = Double(xmax - xmin), yc = Double(ymin + ymax) / 2
        var best = (score: 0.0, x0: 0, k: 0.0)
        for i in 0...120 {
            let k = -0.6 + 1.2 * Double(i) / 120
            var col = [Double](repeating: 0, count: w)
            for (x, y) in ridge { let xs = Int((Double(x) + k * (Double(y) - yc)).rounded()); if xs >= 0 && xs < w { col[xs] += 1 } }
            var sm = col
            for x in 0..<w { sm[x] = (col[max(x - 1, 0)] + col[x] + col[min(x + 1, w - 1)]) / 3 }
            let lo = Int(mid - 0.2 * span), hi = Int(mid + 0.2 * span)
            var x0 = lo; for x in lo..<hi where sm[x] > sm[x0] { x0 = x }
            if sm[x0] > best.score { best = (sm[x0], x0, k) }
        }
        let (x0, k) = (Double(best.x0), best.k)
        return { y in (x0 - k * (y / Double(s) - yc)) * Double(s) }
    }
}
