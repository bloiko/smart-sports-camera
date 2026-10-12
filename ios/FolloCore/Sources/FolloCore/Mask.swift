import Foundation

/// Binary image (0/1) of the pitch, H rows × W columns, row-major.
public struct Mask {
    public let w: Int, h: Int
    public var data: [UInt8]
    public init(w: Int, h: Int, data: [UInt8]? = nil) { self.w = w; self.h = h; self.data = data ?? [UInt8](repeating: 0, count: w * h) }

    public subscript(x x: Int, y y: Int) -> Bool { data[y * w + x] != 0 }

    /// Python `fm[min(int(y), H-1), min(int(x), W-1)]` (int() truncates towards zero; negatives clamped here).
    public func at(_ x: Double, _ y: Double) -> Bool {
        let xi = min(max(Int(x), 0), w - 1), yi = min(max(Int(y), 0), h - 1)
        return self[x: xi, y: yi]
    }

    public var share: Double { Double(data.reduce(0) { $0 + Int($1) }) / Double(w * h) }

    /// cv2.dilate with a k×k square kernel (separable max filter, k odd).
    public func dilated(_ k: Int) -> Mask {
        let r = k / 2; var tmp = [UInt8](repeating: 0, count: w * h); var out = tmp
        for y in 0..<h { for x in 0..<w where data[y * w + x] != 0 {
            for dx in max(0, x - r)...min(w - 1, x + r) { tmp[y * w + dx] = 1 }
        } }
        for y in 0..<h { for x in 0..<w where tmp[y * w + x] != 0 {
            for dy in max(0, y - r)...min(h - 1, y + r) { out[dy * w + x] = 1 }
        } }
        return Mask(w: w, h: h, data: out)
    }

    /// Mask of the largest 8-connected component (cv2.connectedComponentsWithStats, largest area).
    public func largestComponent() -> Mask {
        var label = [Int32](repeating: 0, count: w * h); var best = 0, bestLabel: Int32 = 0; var next: Int32 = 1
        var stack: [Int] = []
        for s in 0..<(w * h) where data[s] != 0 && label[s] == 0 {
            var area = 0; label[s] = next; stack.append(s)
            while let p = stack.popLast() {
                area += 1; let px = p % w, py = p / w
                for dy in -1...1 { for dx in -1...1 {
                    let nx = px + dx, ny = py + dy
                    if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                    let q = ny * w + nx
                    if data[q] != 0 && label[q] == 0 { label[q] = next; stack.append(q) }
                } }
            }
            if area > best { best = area; bestLabel = next }
            next += 1
        }
        var out = [UInt8](repeating: 0, count: w * h)
        if best > 0 { for i in 0..<(w * h) where label[i] == bestLabel { out[i] = 1 } }
        return Mask(w: w, h: h, data: out)
    }

    /// Fill holes: everything not reachable from the border through zeros becomes 1 (cv2.drawContours of the outer contour).
    public func filled() -> Mask {
        var outside = [UInt8](repeating: 0, count: w * h); var stack: [Int] = []
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let p = stack.popLast() {
            if data[p] != 0 || outside[p] != 0 { continue }
            outside[p] = 1; let px = p % w, py = p / w
            if px > 0 { stack.append(p - 1) }; if px < w - 1 { stack.append(p + 1) }
            if py > 0 { stack.append(p - w) }; if py < h - 1 { stack.append(p + w) }
        }
        var out = [UInt8](repeating: 1, count: w * h)
        for i in 0..<(w * h) where outside[i] != 0 { out[i] = 0 }
        return Mask(w: w, h: h, data: out)
    }
}
