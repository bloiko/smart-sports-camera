import Foundation

/// Goals during the live: from already-seen players only; the estimate only grows outward.
/// Port of LiveGoals in src/goals.py (heat map on a 1/4 grid, own Gaussian kernel, zero borders).
public final class LiveGoals {
    static let scale = 4
    let fm: Mask, dt: Double, thr: Double, cp: Double, mx: Double
    let gw: Int, gh: Int
    var raw: [Double]
    let kernel: [Double]
    public var best: [Pt]? = nil
    var pending: [Pt?] = [nil, nil]
    public var centre: ((Double) -> Double)?

    public init(fmask: Mask, sampleDt: Double, thrS: Double = 3.0, sigma: Double = 25, confirmPx: Double = 150,
                centre: ((Double) -> Double)? = nil, mirrorPx: Double = 300) {
        let s = Self.scale
        fm = fmask; dt = sampleDt; thr = thrS; cp = confirmPx; mx = mirrorPx; self.centre = centre
        gw = (fmask.w + s - 1) / s; gh = (fmask.h + s - 1) / s
        raw = [Double](repeating: 0, count: gw * gh)
        let r = Int((3 * sigma / Double(s)).rounded(.up))
        kernel = (-r...r).map { exp(-0.5 * pow(Double($0 * s) / sigma, 2)) }
    }

    public func add(_ persons: [Box]) {
        let s = Self.scale
        for b in persons where b.conf >= 0.25 && b.y1 - b.y0 >= 12 && b.y1 - b.y0 <= 260 {
            let x = min(max(Int((b.x0 + b.x1) / 2), 0), fm.w - 1), y = min(max(Int(b.y1), 0), fm.h - 1)
            if fm[x: x, y: y] { raw[(y / s) * gw + x / s] += dt }
        }
    }

    /// Separable convolution with the unnormalised kernel, zero padding (numpy.convolve 'same').
    func heat() -> [Double] {
        let r = kernel.count / 2; var tmp = [Double](repeating: 0, count: gw * gh); var out = tmp
        for y in 0..<gh { for x in 0..<gw {
            var acc = 0.0
            for k in -r...r { let xx = x + k; if xx >= 0 && xx < gw { acc += raw[y * gw + xx] * kernel[k + r] } }
            tmp[y * gw + x] = acc
        } }
        for y in 0..<gh { for x in 0..<gw {
            var acc = 0.0
            for k in -r...r { let yy = y + k; if yy >= 0 && yy < gh { acc += tmp[yy * gw + x] * kernel[k + r] } }
            out[y * gw + x] = acc
        } }
        return out
    }

    public func update() -> [Pt]? {
        let s = Double(Self.scale); let h = heat()
        let region = Mask(w: gw, h: gh, data: h.map { $0 > thr ? 1 : 0 }).largestComponent()
        var xs: [Double] = [], ys: [Double] = []
        for y in 0..<gh { for x in 0..<gw where region[x: x, y: y] { xs.append(Double(x)); ys.append(Double(y)) } }
        if xs.isEmpty { return best }
        let xmin = xs.min()!, xmax = xs.max()!, tip = Double(40 / Self.scale)
        func mean(_ sel: (Double) -> Bool) -> Pt {
            var sx = 0.0, sy = 0.0, n = 0.0
            for i in 0..<xs.count where sel(xs[i]) { sx += xs[i]; sy += ys[i]; n += 1 }
            return Pt(sx / n * s + (s - 1) / 2, sy / n * s + (s - 1) / 2)
        }
        let t = [mean { $0 <= xmin + tip }, mean { $0 >= xmax - tip }]
        guard var b = best else { best = t; return mirrored() }
        for k in 0..<2 {
            let outward = k == 0 ? t[0].x < b[0].x : t[1].x > b[1].x
            if !outward { pending[k] = nil; continue }
            if abs(t[k].x - b[k].x) <= cp { b[k] = t[k]; pending[k] = nil }
            else if let p = pending[k], abs(t[k].x - p.x) <= cp { b[k] = t[k]; pending[k] = nil }
            else { pending[k] = t[k] }
        }
        best = b
        return mirrored()
    }

    /// Our own estimate can only be too far inside; take the outer of own and mirrored (through the halfway line).
    func mirrored() -> [Pt]? {
        guard let o = best, let c = centre else { return best }
        var b = o
        let ml = 2 * c(o[1].y) - o[1].x, mr = 2 * c(o[0].y) - o[0].x
        if ml < o[0].x - mx { b[0] = Pt(ml, o[1].y) }
        if mr > o[1].x + mx { b[1] = Pt(mr, o[0].y) }
        return b
    }
}
