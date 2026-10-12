import Foundation

/// Closer camera for highlight clips and vertical 9:16 from the live path. Port of close_path() in src/closeup.py.
public enum ClosePath {
    public static let zoom = 0.65, vZoom = 0.9, minSrcH = 300.0, fillS = 2.0, smoothS = 0.6, maxSpeedK = 1.5, margin = 0.12

    static func gauss(_ s: [Double], _ sig: Double) -> [Double] {
        let r = max(Int(sig * 3), 1); let k = (-r...r).map { exp(-0.5 * pow(Double($0) / max(sig, 1e-6), 2)) }; let ks = k.reduce(0, +)
        return (0..<s.count).map { i in var acc = 0.0; for j in -r...r { acc += s[min(max(i + j, 0), s.count - 1)] * k[j + r] }; return acc / ks }   // edge padding
    }

    static func speedLimit(_ s: [Double], _ v: Double) -> [Double] {
        var f = s; for i in 1..<f.count { f[i] = f[i - 1] + Stats.clip(f[i] - f[i - 1], -v, v) }
        var b = s; for i in stride(from: b.count - 2, through: 0, by: -1) { b[i] = b[i + 1] + Stats.clip(b[i] - b[i + 1], -v, v) }
        return (0..<s.count).map { (f[$0] + b[$0]) / 2 }
    }

    /// Linear interpolation of nil gaps up to fillS seconds.
    static func fill(_ v: [Double?], fps: Double) -> [Double?] {
        var out = v; let ok = (0..<v.count).filter { v[$0] != nil }
        for (a, b) in zip(ok, ok.dropFirst()) where b - a > 1 && Double(b - a) <= fillS * fps {
            for i in a...b { out[i] = v[a]! + (v[b]! - v[a]!) * Double(i - a) / Double(b - a) }
        }
        return out
    }

    public static func make(_ fr: [LiveCamera.Frame], fps: Double, W: Int, H: Int, top: [Double], bot: [Double], goals: [Pt]?, vertical: Bool = false) -> [(x: Double, y: Double, cw: Double, ch: Double)] {
        let n = fr.count; let bx = fill(fr.map { $0.ball?.x }, fps: fps), by = fill(fr.map { $0.ball?.y }, fps: fps)
        var tx = [Double](repeating: 0, count: n), ty = tx, cw = tx, ch = tx
        for i in 0..<n {
            var gx = fr[i].x, gy = fr[i].y
            if let g = goals, fr[i].gon, fr[i].gi >= 0 { gx = 0.6 * g[fr[i].gi].x + 0.4 * fr[i].x; gy = 0.6 * g[fr[i].gi].y + 0.4 * fr[i].y }
            if let x = bx[i], let y = by[i] { tx[i] = 0.7 * x + 0.3 * fr[i].x; ty[i] = 0.7 * y + 0.3 * fr[i].y } else { tx[i] = gx; ty[i] = gy }
            ch[i] = max((vertical ? vZoom : zoom) * fr[i].ch, minSrcH); cw[i] = ch[i] * (vertical ? 9.0 / 16 : 16.0 / 9)
        }
        let v = maxSpeedK * 900 / fps
        tx = speedLimit(gauss(tx, smoothS * fps), v); ty = speedLimit(gauss(ty, smoothS * fps), v); ch = gauss(ch, fps); cw = gauss(cw, fps)
        for i in 0..<n { if let x = bx[i], let y = by[i] { let mx = (0.5 - margin) * cw[i], my = (0.5 - margin) * ch[i]; tx[i] = Stats.clip(tx[i], x - mx, x + mx); ty[i] = Stats.clip(ty[i], y - my, y + my) } }
        tx = gauss(tx, 0.2 * fps); ty = gauss(ty, 0.2 * fps)
        for i in 0..<n { tx[i] = Stats.clip(tx[i], cw[i] / 2, Double(W) - cw[i] / 2) }
        for i in 0..<n {
            let a = max(Int(tx[i] - cw[i] / 2), 0), b = max(min(Int(tx[i] + cw[i] / 2), W), a + 1)
            let t = top[a..<b].max()!, bt = bot[a..<b].min()!
            if bt - t < ch[i] { ch[i] = bt - t; cw[i] = ch[i] * (vertical ? 9.0 / 16 : 16.0 / 9) }
            ty[i] = Stats.clip(ty[i], t + ch[i] / 2, bt - ch[i] / 2)
        }
        return (0..<n).map { (tx[$0], ty[$0], cw[$0], ch[$0]) }
    }
}
