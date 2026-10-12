import Foundation

/// Small numeric helpers that mirror numpy calls used in src/live_cam.py.
public enum Stats {
    /// numpy.percentile with linear interpolation.
    public static func percentile(_ v: [Double], _ p: Double) -> Double {
        let s = v.sorted(); let k = p / 100 * Double(s.count - 1); let i = Int(k.rounded(.down)); let t = k - Double(i)
        return i + 1 >= s.count ? s[i] : s[i] * (1 - t) + s[i + 1] * t
    }

    /// numpy.interp for two points (clamped linear).
    public static func interp(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[1] { return ys[1] }
        return ys[0] + (ys[1] - ys[0]) * (x - xs[0]) / (xs[1] - xs[0])
    }

    public static func clip(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo : (v > hi ? hi : v) }

    public static func hypot(_ a: Double, _ b: Double) -> Double { (a * a + b * b).squareRoot() }
}

/// Moving mean over the last r values (gauss_causal of live_sim.py: the first values are means of what exists).
public struct Causal {
    let r: Int; var buf: [Double] = []
    public init(_ r: Int) { self.r = max(r, 1) }
    public mutating func push(_ v: Double) -> Double {
        buf.append(v); if buf.count > r { buf.removeFirst() }
        return buf.reduce(0, +) / Double(buf.count)
    }
}

public struct Pt { public var x: Double; public var y: Double; public init(_ x: Double, _ y: Double) { self.x = x; self.y = y } }
