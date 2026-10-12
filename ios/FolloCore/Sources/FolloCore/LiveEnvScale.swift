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
        if b.x0 < W / 50 { return "The left goal may be out of frame: turn the phone left" }
        if b.x1 > W - W / 50 { return "The right goal may be out of frame: turn the phone right" }
        return nil
    }
}
