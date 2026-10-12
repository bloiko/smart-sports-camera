import Foundation

/// One detector box in source-frame pixels.
public struct Box {
    public var x0: Double, y0: Double, x1: Double, y1: Double, conf: Double
    public init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ conf: Double) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1; self.conf = conf }
    public var cx: Double { (x0 + x1) / 2 }
    public var cy: Double { (y0 + y1) / 2 }
    public var h: Double { y1 - y0 }
}

/// Ball candidate from the ROI pass: box + difference from the static background (0–255, 99 = no background yet).
public struct BallCand { public var box: Box; public var bg: Double; public init(box: Box, bg: Double) { self.box = box; self.bg = bg } }

/// What the detection stage produces per frame (one line of live_det.jsonl).
public struct FrameRecord {
    public var frame: Int
    public var persons: [Box]? = nil
    public var rois: [(Int, Int)]? = nil
    public var balls: [BallCand]? = nil
    public var ball: Pt? = nil
    public var black: Pt? = nil
    public var hints: [Pt]? = nil
    public init(frame: Int) { self.frame = frame }

    /// Parse one JSON line of live_det.jsonl.
    public init?(jsonLine: String) {
        guard let d = jsonLine.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let f = o["frame"] as? Int else { return nil }
        frame = f
        if let p = o["persons"] as? [[Double]] { persons = p.map { Box($0[0], $0[1], $0[2], $0[3], $0[4]) } }
        if let r = o["roi"] as? [[Double]] { rois = r.map { (Int($0[0]), Int($0[1])) } }
        if let b = o["balls"] as? [[Double]] { balls = b.map { BallCand(box: Box($0[0], $0[1], $0[2], $0[3], $0[4]), bg: $0.count > 5 ? $0[5] : 99) } }
        if let b = o["ball"] as? [Double] { ball = Pt(b[0], b[1]) }
        if let b = o["black"] as? [Double] { black = Pt(b[0], b[1]) }
        if let h = o["hints"] as? [[Double]] { hints = h.map { Pt($0[0], $0[1]) } }
    }

    public var jsonLine: String {
        var o: [String: Any] = ["frame": frame]
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        if let p = persons { o["persons"] = p.map { [r1($0.x0), r1($0.y0), r1($0.x1), r1($0.y1), ($0.conf * 1000).rounded() / 1000] } }
        if let r = rois { o["roi"] = r.map { [$0.0, $0.1] } }
        if let b = balls { o["balls"] = b.map { [r1($0.box.x0), r1($0.box.y0), r1($0.box.x1), r1($0.box.y1), ($0.box.conf * 1000).rounded() / 1000, $0.bg] } }
        if let b = ball { o["ball"] = [r1(b.x), r1(b.y)] }
        if let b = black { o["black"] = [r1(b.x), r1(b.y)] }
        if let h = hints { o["hints"] = h.map { [r1($0.x), r1($0.y)] } }
        return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }
}
