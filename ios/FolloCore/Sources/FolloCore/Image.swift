import Foundation
import CoreVideo

/// 8-bit image planes used by the own computations (field mask, halfway line, background): BGR or grey.
public struct Image8 {
    public let w: Int, h: Int, ch: Int
    public var data: [UInt8]
    public init(w: Int, h: Int, ch: Int, data: [UInt8]? = nil) { self.w = w; self.h = h; self.ch = ch; self.data = data ?? [UInt8](repeating: 0, count: w * h * ch) }

    /// From a BGRA CVPixelBuffer → BGR (drops alpha).
    public init(bgra pb: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var d = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h { let row = base + y * bpr; var o = y * w * 3
            for x in 0..<w { let p = row + x * 4; d[o] = p[0]; d[o + 1] = p[1]; d[o + 2] = p[2]; o += 3 } }
        self.init(w: w, h: h, ch: 3, data: d)
    }

    /// cv2 grey: 0.299 R + 0.587 G + 0.114 B.
    public func grey() -> Image8 {
        precondition(ch == 3); var g = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { let b = Double(data[i * 3]), gg = Double(data[i * 3 + 1]), r = Double(data[i * 3 + 2]); g[i] = UInt8(min(255, (0.299 * r + 0.587 * gg + 0.114 * b).rounded())) }
        return Image8(w: w, h: h, ch: 1, data: g)
    }

    /// Half size by 2×2 mean (cv2.resize INTER_LINEAR at exactly 0.5).
    public func half() -> Image8 {
        let w2 = w / 2, h2 = h / 2; var d = [UInt8](repeating: 0, count: w2 * h2 * ch)
        for y in 0..<h2 { for x in 0..<w2 { for c in 0..<ch {
            let i = ((2 * y) * w + 2 * x) * ch + c, j = ((2 * y + 1) * w + 2 * x) * ch + c
            d[(y * w2 + x) * ch + c] = UInt8((Int(data[i]) + Int(data[i + ch]) + Int(data[j]) + Int(data[j + ch]) + 2) / 4)
        } } }
        return Image8(w: w2, h: h2, ch: ch, data: d)
    }

    /// cv2 BGR → HSV (H 0–179, S and V 0–255), one pixel.
    public static func hsv(b: UInt8, g: UInt8, r: UInt8) -> (Int, Int, Int) {
        let bf = Double(b), gf = Double(g), rf = Double(r); let v = max(bf, gf, rf), mn = min(bf, gf, rf), d = v - mn
        let s = v == 0 ? 0.0 : d / v * 255
        var hh = 0.0
        if d != 0 {
            if v == rf { hh = 60 * (gf - bf) / d } else if v == gf { hh = 120 + 60 * (bf - rf) / d } else { hh = 240 + 60 * (rf - gf) / d }
            if hh < 0 { hh += 360 }
        }
        return (Int((hh / 2).rounded()) % 180, Int(s.rounded()), Int(v.rounded()))
    }

    /// Per-pixel, per-channel median of several images of the same size.
    public static func median(_ imgs: [Image8]) -> Image8 {
        let a = imgs[0]; var out = Image8(w: a.w, h: a.h, ch: a.ch); var v = [UInt8](repeating: 0, count: imgs.count)
        for i in 0..<(a.w * a.h * a.ch) {
            for k in 0..<imgs.count { v[k] = imgs[k].data[i] }
            v.sort(); let n = imgs.count
            out.data[i] = n % 2 == 1 ? v[n / 2] : UInt8((Int(v[n / 2 - 1]) + Int(v[n / 2])) / 2)
        }
        return out
    }
}
