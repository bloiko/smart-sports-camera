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
        e.fm = fm?.scaled(k); e.centreEnds = centreEnds.map { ($0.0 * kk, $0.1 * kk) }; e.farLine = farLine?.scaled(k)
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
        // the ends of the far touchline are the ends of the pitch (green behind the goals does not count)
        let ends: (Double, Double)? = (FarLine.enabled ? farLine : nil).map { (Double($0.xl), Double($0.xr)) } ?? fm.farBand
        guard let (l, r) = ends else { return "No pitch found: point the camera at the field" }
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

/// "Що бачить застосунок" (owner, 2026-10-17): what the position check found, to draw over the preview before GO LIVE.
/// Coordinates are in full-frame pixels; `mask` is the pitch shrunk to at most `maxWidth` px for drawing.
public struct PositionOverlay: Sendable {
    public let w: Int, h: Int
    public let maskW: Int, maskH: Int, mask: [UInt8]
    /// Far quarter of the pitch (where the goals stand): left and right ends, rows.
    public let farLeft: Double, farRight: Double, farTop: Double, farBottom: Double
    /// The far corners must stay this far from the frame edges.
    public let margin: Double
    public var leftOK: Bool { farLeft >= margin }
    public var rightOK: Bool { farRight <= Double(w - 1) - margin }
}

extension LiveEnv {
    public func positionOverlay(maxWidth: Int = 320) -> PositionOverlay? {
        guard let fm = fm, var band = fm.farBandRows else { return nil }
        if FarLine.enabled, let L = farLine {                        // markers at the ends of the far touchline
            let yl = L.y(Double(L.xl), W: fm.w), yr = L.y(Double(L.xr), W: fm.w)
            band = (Double(L.xl), Double(L.xr), Int(min(yl, yr)) - 10, Int(max(yl, yr)) + 10)
        }
        let k = max(1, Int((Double(fm.w) / Double(maxWidth)).rounded(.up)))
        let mw = fm.w / k, mh = fm.h / k
        var small = [UInt8](repeating: 0, count: mw * mh)
        for y in 0..<mh { for x in 0..<mw where fm.data[(y * k) * fm.w + x * k] != 0 { small[y * mw + x] = 1 } }
        return PositionOverlay(w: fm.w, h: fm.h, maskW: mw, maskH: mh, mask: small, farLeft: band.l, farRight: band.r,
                               farTop: Double(band.y0), farBottom: Double(band.y1), margin: Double(fm.w) / 33)
    }
}

extension Mask {
    /// `farBand` with the rows it was measured on (for drawing).
    public var farBandRows: (l: Double, r: Double, y0: Int, y1: Int)? {
        guard let (l, r) = farBand else { return nil }
        let minCount = max(1, w / 20)
        var y0 = -1, y1 = -1
        for y in 0..<h { var c = 0; for x in 0..<w where data[y * w + x] != 0 { c += 1 }; if c >= minCount { if y0 < 0 { y0 = y }; y1 = y } }
        return (l, r, y0, y0 + max(1, (y1 - y0) / 4))
    }
}

#if canImport(CoreGraphics)
import CoreGraphics
extension PositionOverlay {
    /// Draws into `rect` (the frame as shown, y pointing down): everything outside the pitch dimmed, the far-corner zones and
    /// both corners — green when inside, red when too close to the edge (turn the phone that way). Shared by the app
    /// (Canvas over the preview) and `follosim overlay` (PNG on the Mac).
    public func draw(in c: CGContext, rect: CGRect) {
        let sx = rect.width / CGFloat(w), sy = rect.height / CGFloat(h)
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + CGFloat(x) * sx, y: rect.minY + CGFloat(y) * sy) }
        // everything that is NOT the pitch is dimmed (a green tint is invisible on grass): one rect per run per row
        c.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        let kx = Double(w) / Double(maskW), ky = Double(h) / Double(maskH)
        for y in 0..<maskH {
            var x = 0
            while x < maskW {
                guard mask[y * maskW + x] == 0 else { x += 1; continue }
                let x0 = x; while x < maskW, mask[y * maskW + x] == 0 { x += 1 }
                let a = P(Double(x0) * kx, Double(y) * ky), b = P(Double(x) * kx, Double(y + 1) * ky)
                c.fill(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
            }
        }
        // edge zones of the far band where a goal corner must not be
        let red = CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1), green = CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1)
        for (x0, ok) in [(0.0, leftOK), (Double(w) - margin, rightOK)] {
            c.setFillColor(ok ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.10) : CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.35))
            let a = P(x0, farTop), b = P(x0 + margin, farBottom); c.fill(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        }
        // far band outline and the two corners (where the goals stand)
        let lw = max(2, rect.width / 300)
        c.setLineWidth(lw); c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        let t = P(farLeft, farTop), u = P(farRight, farBottom); c.stroke(CGRect(x: t.x, y: t.y, width: u.x - t.x, height: u.y - t.y))
        let r = max(6, rect.width / 60)
        for (x, ok) in [(farLeft, leftOK), (farRight, rightOK)] {
            let p = P(x, (farTop + farBottom) / 2)
            c.setFillColor(ok ? green : red); c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            c.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)); c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }
}
#endif
