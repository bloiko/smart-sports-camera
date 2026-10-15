import Foundation

extension Mask {
    /// Nearest-neighbour upscale by an integer factor (the phone computes the field mask at half resolution).
    public func scaled(_ k: Int) -> Mask {
        var out = Mask(w: w * k, h: h * k)
        for y in 0..<out.h { for x in 0..<out.w { out.data[y * out.w + x] = data[(y / k) * w + x / k] } }
        return out
    }

    /// Bounding box of the set pixels (nil if empty).
    public var bounds: (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        for y in 0..<h { for x in 0..<w where data[y * w + x] != 0 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        return x1 < 0 ? nil : (x0, y0, x1, y1)
    }
}

extension LiveEnv {
    /// Environment computed on k× smaller frames, brought to full frame coordinates.
    public func scaled(_ k: Int) -> LiveEnv {
        let c = centre; let kk = Double(k)
        var e = LiveEnv(W: W * k, H: H * k, fps: fps, fmd: fmd.scaled(k),
                        top: (0..<(W * k)).map { top[$0 / k] * kk }, bot: (0..<(W * k)).map { bot[$0 / k] * kk },
                        centre: c.map { f in { y in f(y / kk) * kk } })
        e.fm = fm?.scaled(k); e.centreEnds = centreEnds.map { ($0.0 * kk, $0.1 * kk) }
        return e
    }

    /// Position check before Go live: the pitch takes a reasonable part of the frame and does not touch the left
    /// or right edge (both goals in frame). Returns nil when fine, otherwise a hint for the user.
    public var positionProblem: String? {
        guard let fm = fm, let b = fm.bounds else { return "No pitch found: point the camera at the field" }
        if fm.share < 0.15 { return "The pitch is too small in the frame: move closer or use the wide camera" }
        _ = b
        // Goals stand at the far corners. Near the camera the grass legitimately reaches the frame sides (wide lens,
        // panoramas m1/m2), so only the far quarter of the pitch must keep a margin from the left/right edges.
        guard let (l, r) = fm.farBand else { return "No pitch found: point the camera at the field" }
        let m = Double(fm.w) / 33
        if l < m { return "The left goal may be out of frame: turn the phone left" }
        if r > Double(fm.w - 1) - m { return "The right goal may be out of frame: turn the phone right" }
        return nil
    }
}

extension Mask {
    /// Left/right extent of the far quarter of the pitch (rows with ≥ 5% grass; 10th/90th percentile of row ends,
    /// so stray blobs of trees do not count). Same rule as tried in Python on m1–m3 and cropped masks.
    public var farBand: (Double, Double)? {
        let minCount = max(1, w / 20)
        var counts = [Int](repeating: 0, count: h)
        for y in 0..<h { var c = 0; for x in 0..<w where data[y * w + x] != 0 { c += 1 }; counts[y] = c }
        guard let y0 = counts.firstIndex(where: { $0 >= minCount }), let y1 = counts.lastIndex(where: { $0 >= minCount }) else { return nil }
        var L: [Int] = [], R: [Int] = []
        for y in y0..<(y0 + max(1, (y1 - y0) / 4)) where counts[y] >= minCount {
            var l = 0; while data[y * w + l] == 0 { l += 1 }
            var r = w - 1; while data[y * w + r] == 0 { r -= 1 }
            L.append(l); R.append(r)
        }
        L.sort(); R.sort()
        return (Double(L[Int(Double(L.count - 1) * 0.1)]), Double(R[Int(Double(R.count - 1) * 0.9)]))
    }
}
