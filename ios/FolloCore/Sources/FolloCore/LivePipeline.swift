import Foundation
import CoreImage
import CoreVideo

/// Detection stage for one frame (players every 4th frame on 2 tiles, ball ROI every 2nd), the same on the Mac
/// (follosim detect) and on the phone. Port of detect() in src/live_sim.py.
public final class LivePipeline {
    public let W: Int, H: Int, fps: Double
    public let players: Detector, ball: Detector
    public let tracker: BallTracker
    public let bg = Background()
    public var playerTiles = 2, playerEvery = 4, ballEvery = 2, roi = 320, roiUp = 2.0
    public var playerConf = 0.12, ballConf = 0.1, bgMin = 15.0
    let fm: Mask
    public var timePlayers = 0.0, timeBall = 0.0, ballCalls = 0
    public var fmd: Mask { tracker.fmd }
    /// Jersey colours sampled on every 2nd player frame (for the kick-off search after Stop).
    public private(set) var jerseys: [JerseySample] = []

    public init(W: Int, H: Int, fps: Double, fm: Mask, fmd: Mask, players: Detector, ball: Detector) {
        self.W = W; self.H = H; self.fps = fps; self.fm = fm; self.players = players; self.ball = ball
        tracker = BallTracker(W: W, H: H, fps: fps, fm: fm, fmd: fmd)
        playerRects = Self.tiles(W: W, H: H, fmd: fmd, inW: players.inW, inH: players.inH, n: playerTiles)
    }

    /// Player tiles. Panoramas (W/H ≥ 2.2, the test matches): `n` full-height tiles, as live_sim.py. A 16:9 phone frame:
    /// full-height tiles would shrink 3840×2160 to the fixed Core ML input 1280×672 at 0.31 (far players lost), so the
    /// tiles cover only the pitch band (field mask rows + 120 px above for the heads of far players) at the model's
    /// aspect ratio, at most 3 tiles. Ultralytics in Python picks its input size itself and never had this problem.
    public var playerRects: [CGRect] = []
    public static func tiles(W: Int, H: Int, fmd: Mask, inW: Int, inH: Int, n: Int) -> [CGRect] {
        if Double(W) / Double(H) >= 2.2 || n <= 1 {
            if n <= 1 { return [CGRect(x: 0, y: 0, width: W, height: H)] }
            let tw = (W + 100) / n
            return (0..<n).map { k in let a = max(0, min(k * (tw - 100 / n), W - tw)); return CGRect(x: a, y: 0, width: tw, height: H) }
        }
        let rows = (0..<fmd.h).filter { y in (0..<fmd.w).contains { fmd.data[y * fmd.w + $0] != 0 } }
        let y0 = max(0, (rows.first ?? 0) - 120), y1 = min(H, (rows.last ?? H - 1) + 20), hb = y1 - y0
        let ov = 100; var tw = Int(Double(hb) * Double(inW) / Double(inH))
        var k = max(1, Int((Double(W - ov) / Double(max(tw - ov, 1))).rounded(.up)))
        if k > 3 { k = 3; tw = (W + 2 * ov) / 3 }                         // budget: at most 3 tiles, then wider tiles
        if k == 1 { return [CGRect(x: 0, y: y0, width: W, height: hb)] }
        tw = max(tw, (W + (k - 1) * ov) / k)
        let step = Double(W - tw) / Double(k - 1)
        return (0..<k).map { CGRect(x: Int((Double($0) * step).rounded()), y: y0, width: tw, height: hb) }
    }

    /// `grey`: full-size grey image of the frame (Y plane on the phone), only read when needed.
    public func process(frame f: Int, image: CIImage, grey: () -> Image8, patch: ((Int, Int, Int, Int) -> Image8)? = nil) -> FrameRecord {
        var rec = FrameRecord(frame: f); var g: Image8? = nil
        func greyImg() -> Image8 { if g == nil { g = grey() }; return g! }
        if Double(f) / fps - bg.lastT >= bg.everyS { bg.push(grey: greyImg(), time: Double(f) / fps) }
        if f % playerEvery == 0 {
            let t = Date(); var ps: [Box] = []; var hints: [Pt] = []
            for r in playerRects {
                for d in players.run(image, rect: r, conf: playerConf) {
                    if d.cls == 0 { ps.append(d.box) }
                    else if d.cls == 32 && d.box.conf >= 0.2 {
                        let hx = d.box.cx, hy = d.box.cy
                        if fm.at(hx, hy) && bg.diff(grey: greyImg(), hx, hy) >= bgMin && tracker.notBlack(hx, hy) { hints.append(Pt(hx, hy)) }
                    }
                }
            }
            rec.persons = ps; if !hints.isEmpty { rec.hints = hints }
            tracker.playersSeen(ps); for h in hints { tracker.addHint(h, frame: f) }
            if f % Jersey.every == 0, let patch = patch { jerseys += Jersey.samples(frame: f, persons: ps, fmd: fmd, patch: patch) }
            timePlayers += Date().timeIntervalSince(t)
        }
        if f % ballEvery == 0 {
            let t = Date(); let rois = tracker.rois(frame: f); rec.rois = rois; var cands: [BallCand] = []
            for (x0, y0) in rois {
                for d in ball.run(image, rect: CGRect(x: x0, y: y0, width: roi, height: roi), scale: roiUp, conf: ballConf) {
                    cands.append(BallCand(box: d.box, bg: bg.diff(grey: greyImg(), d.box.cx, d.box.cy)))
                }
            }
            rec.balls = cands; ballCalls += rois.count
            let (b, black) = tracker.accept(frame: f, cands); rec.ball = b; rec.black = black
            timeBall += Date().timeIntervalSince(t)
        }
        return rec
    }
}
