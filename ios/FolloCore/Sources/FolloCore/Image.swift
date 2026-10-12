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

extension Image8 {
    /// BGR copy of a rectangle of any pixel buffer (BGRA or 4:2:0 bi-planar from the camera), for jersey colours.
    public static func bgrPatch(_ pb: CVPixelBuffer, x0: Int, y0: Int, w: Int, h: Int) -> Image8 {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let W = CVPixelBufferGetWidth(pb), H = CVPixelBufferGetHeight(pb)
        let x0 = min(max(x0, 0), W - 1), y0 = min(max(y0, 0), H - 1), w = max(min(w, W - x0), 1), h = max(min(h, H - y0), 1)
        var out = Image8(w: w, h: h, ch: 3)
        if CVPixelBufferGetPlaneCount(pb) >= 2 {
            let yb = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self), ybpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let cb = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self), cbpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            let full = CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            for y in 0..<h { for x in 0..<w {
                let Y = Double(yb[(y0 + y) * ybpr + x0 + x]), U = Double(cb[((y0 + y) / 2) * cbpr + ((x0 + x) / 2) * 2]) - 128, V = Double(cb[((y0 + y) / 2) * cbpr + ((x0 + x) / 2) * 2 + 1]) - 128
                let yy = full ? Y : (Y - 16) * 255 / 219, k = full ? 1.0 : 255 / 224.0
                let r = yy + 1.402 * V * k, g = yy - 0.344136 * U * k - 0.714136 * V * k, b = yy + 1.772 * U * k
                let o = (y * w + x) * 3; out.data[o] = UInt8(min(max(b, 0), 255)); out.data[o + 1] = UInt8(min(max(g, 0), 255)); out.data[o + 2] = UInt8(min(max(r, 0), 255))
            } }
        } else {
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), bpr = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h { for x in 0..<w { let p = base + (y0 + y) * bpr + (x0 + x) * 4, o = (y * w + x) * 3; out.data[o] = p[0]; out.data[o + 1] = p[1]; out.data[o + 2] = p[2] } }
        }
        return out
    }
}
