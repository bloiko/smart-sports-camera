import Foundation

/// Jersey colour of each on-field player: median Lab a, b of the torso without grass pixels.
/// Port of jersey_colours() in src/kickoff.py. Sampled on every 2nd player frame during the live.
public struct JerseySample { public var frame: Int; public var x: Double; public var a: Double; public var b: Double }

public enum Jersey {
    public static let every = 8

    /// cv2 BGR (8-bit) → Lab a, b in cv2's 8-bit scale (a + 128, b + 128).
    static func lab(b: UInt8, g: UInt8, r: UInt8) -> (Double, Double) {
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(b)
        let X = (0.412453 * R + 0.357580 * G + 0.180423 * B) / 0.950456, Y = 0.212671 * R + 0.715160 * G + 0.072169 * B, Z = (0.019334 * R + 0.119193 * G + 0.950227 * B) / 1.088754
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (500 * (f(X) - f(Y)) + 128, 200 * (f(Y) - f(Z)) + 128)
    }

    /// `img`: the whole BGR frame; `persons`: detector boxes; `fmd`: dilated field mask.
    public static func samples(frame f: Int, img: Image8, persons: [Box], fmd: Mask) -> [JerseySample] {
        samples(frame: f, persons: persons, fmd: fmd) { x0, y0, w, h in
            var o = Image8(w: w, h: h, ch: 3)
            for y in 0..<h { for x in 0..<w { for c in 0..<3 { o.data[(y * w + x) * 3 + c] = img.data[((y0 + y) * img.w + x0 + x) * 3 + c] } } }
            return o
        }
    }

    /// `patch(x0, y0, w, h)` returns that BGR rectangle of the frame (on the phone: Image8.bgrPatch of the camera buffer).
    public static func samples(frame f: Int, persons: [Box], fmd: Mask, patch: (Int, Int, Int, Int) -> Image8) -> [JerseySample] {
        var out: [JerseySample] = []
        for p in persons {
            let h = p.y1 - p.y0
            guard p.conf >= 0.25, h >= 12, h <= 260, fmd.at(p.cx, p.y1) else { continue }
            let ty0 = Int(p.y0 + 0.2 * h), ty1 = max(Int(p.y0 + 0.5 * h), Int(p.y0 + 0.2 * h) + 1)
            let tx0 = Int(p.x0 + 0.25 * (p.x1 - p.x0)), tx1 = max(Int(p.x1 - 0.25 * (p.x1 - p.x0)), Int(p.x0 + 0.25 * (p.x1 - p.x0)) + 1)
            let x0 = max(tx0, 0), y0 = max(ty0, 0), w = min(tx1, fmd.w) - x0, hh2 = min(ty1, fmd.h) - y0
            guard w > 0, hh2 > 0 else { continue }
            let img = patch(x0, y0, w, hh2)
            var av: [Double] = [], bv: [Double] = []
            for y in 0..<img.h { for x in 0..<img.w {
                let i = (y * img.w + x) * 3; let (hh, s, _) = Image8.hsv(b: img.data[i], g: img.data[i + 1], r: img.data[i + 2])
                if hh >= 35 && hh <= 95 && s >= 30 { continue }          // grass
                let (a, b) = lab(b: img.data[i], g: img.data[i + 1], r: img.data[i + 2]); av.append(a); bv.append(b)
            } }
            if av.count < 4 { continue }
            out.append(JerseySample(frame: f, x: p.cx, a: Stats.percentile(av, 50), b: Stats.percentile(bv, 50)))
        }
        return out
    }
}
