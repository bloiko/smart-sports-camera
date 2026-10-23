import Foundation

/// Pitch mask from a median frame: grass colour, largest component, holes filled. Port of src/fieldmask.py.
/// Fixed green range first (bright artificial grass); if the field comes out too small (pale grass, evening),
/// the adaptive mode takes the grass colour from points along the lower half of the frame.
public enum FieldMask {
    public static func make(median med: Image8) -> Mask { makeWithLine(median: med).mask }

    /// The mask cut above the far touchline when one is found (FarLine.swift), and the line.
    public static func makeWithLine(median med: Image8) -> (mask: Mask, line: FarLine?) {
        let m = grassMask(median: med)
        guard FarLine.enabled, let L = FarLine.find(median: med, mask: m) else { return (m, nil) }
        return (FarLine.cutEnabled ? L.cut(m) : m, L)
    }

    static func grassMask(median med: Image8) -> Mask {
        let w = med.w, h = med.h; var g = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let (hh, s, v) = Image8.hsv(b: med.data[i * 3], g: med.data[i * 3 + 1], r: med.data[i * 3 + 2])
            g[i] = (hh >= 35 && hh <= 90 && s >= 50 && v >= 40) ? 1 : 0
        }
        let m = Mask(w: w, h: h, data: g).closed(25).largestComponent().filled()
        if m.share > 0.25 { return m }
        return adaptive(med)
    }

    static func adaptive(_ med: Image8) -> Mask {
        let w = med.w, h = med.h
        let blurred = med.medianBlur9()
        var hsv = [(Int, Int, Int)](repeating: (0, 0, 0), count: w * h)
        for i in 0..<(w * h) { hsv[i] = Image8.hsv(b: blurred.data[i * 3], g: blurred.data[i * 3 + 1], r: blurred.data[i * 3 + 2]) }
        var g = [UInt8](repeating: 0, count: w * h)
        for fx in [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8] { for fy in [0.45, 0.55] {
            let cx = Int(Double(w) * fx), cy = Int(Double(h) * fy); var hs: [Double] = [], ss: [Double] = [], vs: [Double] = []
            for y in (cy - 30)..<(cy + 30) { for x in (cx - 30)..<(cx + 30) { let p = hsv[y * w + x]; hs.append(Double(p.0)); ss.append(Double(p.1)); vs.append(Double(p.2)) } }
            let h0 = Stats.percentile(hs, 50), s0 = Stats.percentile(ss, 50), v0 = Stats.percentile(vs, 50)
            if !(h0 >= 35 && h0 <= 95 && s0 >= 15) { continue }
            for i in 0..<(w * h) {
                let p = hsv[i]; var dh = abs(Double(p.0) - h0); dh = min(dh, 180 - dh)
                if dh < 10 && abs(Double(p.1) - s0) < 25 && abs(Double(p.2) - v0) < 60 { g[i] = 1 }
            }
        } }
        return Mask(w: w, h: h, data: g).opened(5).closed(41).largestComponent()
    }

    /// Image content bounds per column (the curved black border of stitched panoramas): first and last row with
    /// max(B, G, R) > 12 (`content_bounds` of closeup.py / live_sim.py).
    public static func contentBounds(_ med: Image8) -> (top: [Double], bot: [Double]) {
        let w = med.w, h = med.h; var top = [Double](repeating: 0, count: w), bot = [Double](repeating: Double(h), count: w)
        for x in 0..<w {
            var t = -1, b = -1
            for y in 0..<h { let i = (y * w + x) * 3; if max(med.data[i], med.data[i + 1], med.data[i + 2]) > 12 { if t < 0 { t = y }; b = y } }
            if t >= 0 { top[x] = Double(t); bot[x] = Double(b + 1) }
        }
        return (top, bot)
    }
}

extension Mask {
    /// cv2.erode with a k×k square (separable min filter).
    public func eroded(_ k: Int) -> Mask {
        let r = k / 2; var tmp = [UInt8](repeating: 1, count: w * h); var out = tmp
        for y in 0..<h { for x in 0..<w where data[y * w + x] == 0 {
            for dx in max(0, x - r)...min(w - 1, x + r) { tmp[y * w + dx] = 0 }
        } }
        for y in 0..<h { for x in 0..<w where tmp[y * w + x] == 0 {
            for dy in max(0, y - r)...min(h - 1, y + r) { out[dy * w + x] = 0 }
        } }
        return Mask(w: w, h: h, data: out)
    }
    public func closed(_ k: Int) -> Mask { dilated(k).eroded(k) }
    public func opened(_ k: Int) -> Mask { eroded(k).dilated(k) }
}

extension Image8 {
    /// cv2.medianBlur(img, 9) on a BGR image (border replicated).
    func medianBlur9() -> Image8 {
        var out = self; var v = [UInt8](repeating: 0, count: 81)
        for y in 0..<h { for x in 0..<w { for c in 0..<ch {
            var n = 0
            for dy in -4...4 { for dx in -4...4 { let yy = min(max(y + dy, 0), h - 1), xx = min(max(x + dx, 0), w - 1); v[n] = data[(yy * w + xx) * ch + c]; n += 1 } }
            v.sort(); out.data[(y * w + x) * ch + c] = v[40]
        } } }
        return out
    }
}
