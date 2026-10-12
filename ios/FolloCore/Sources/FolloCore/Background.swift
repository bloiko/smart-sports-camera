import Foundation

/// Static background during the live: median of the last 9 half-size frames taken every 3 s. A "ball" that looks
/// the same as the background is a painted letter or a dummy, not the ball. Port of bg_diff() in live_sim.py.
public final class Background {
    public var everyS = 3.0, keep = 9
    var frames: [Image8] = []       // grey, half size
    var lastT = -1e9
    public init() {}

    /// Call with every frame (grey, full size); keeps a half-size copy every `everyS` seconds.
    public func push(grey: Image8, time t: Double) {
        guard t - lastT >= everyS else { return }
        frames.append(grey.half()); if frames.count > keep { frames.removeFirst() }; lastT = t
    }

    /// 75th percentile of |frame − background| in a 14×14 window at (cx, cy); 99 while there is no background yet.
    public func diff(grey img: Image8, _ cx: Double, _ cy: Double) -> Double {
        guard frames.count >= 3 else { return 99 }
        let hw = frames[0].w, hh = frames[0].h
        let x0 = max(Int(cy) / 2 - 3, 0), x1 = min(Int(cy) / 2 + 4, hh); let y0 = max(Int(cx) / 2 - 3, 0), y1 = min(Int(cx) / 2 + 4, hw)
        // (rows x0..<x1 of the half image, columns y0..<y1) — names follow the Python slice order (y first)
        let rows = x1 - x0, cols = y1 - y0
        guard rows > 0 && cols > 0 else { return 99 }
        var diffs: [Double] = []; var v = [Int](repeating: 0, count: frames.count)
        let cy0 = max(Int(cy) - 6, 0), cx0 = max(Int(cx) - 6, 0)
        for r in 0..<rows { for c in 0..<cols {
            for k in 0..<frames.count { v[k] = Int(frames[k].data[(x0 + r) * hw + y0 + c]) }
            v.sort(); let n = v.count; let bg = n % 2 == 1 ? Double(v[n / 2]) : Double(v[n / 2 - 1] + v[n / 2]) / 2
            // current patch (14×14 full res) resized to the background patch size: 2×2 mean
            let yy = min(cy0 + 2 * r, img.h - 2), xx = min(cx0 + 2 * c, img.w - 2)
            let cur = (Int(img.data[yy * img.w + xx]) + Int(img.data[yy * img.w + xx + 1]) + Int(img.data[(yy + 1) * img.w + xx]) + Int(img.data[(yy + 1) * img.w + xx + 1]) + 2) / 4
            diffs.append(abs(Double(cur) - bg))
        } }
        return (Stats.percentile(diffs, 75) * 10).rounded() / 10
    }
}
