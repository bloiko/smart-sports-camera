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

    public init(W: Int, H: Int, fps: Double, fm: Mask, fmd: Mask, players: Detector, ball: Detector) {
        self.W = W; self.H = H; self.fps = fps; self.fm = fm; self.players = players; self.ball = ball
        tracker = BallTracker(W: W, H: H, fps: fps, fm: fm, fmd: fmd)
    }

    /// `grey`: full-size grey image of the frame (Y plane on the phone), only read when needed.
    public func process(frame f: Int, image: CIImage, grey: () -> Image8) -> FrameRecord {
        var rec = FrameRecord(frame: f); var g: Image8? = nil
        func greyImg() -> Image8 { if g == nil { g = grey() }; return g! }
        if Double(f) / fps - bg.lastT >= bg.everyS { bg.push(grey: greyImg(), time: Double(f) / fps) }
        if f % playerEvery == 0 {
            let t = Date(); let tw = (W + 100) / playerTiles; var ps: [Box] = []; var hints: [Pt] = []
            for k in 0..<playerTiles {
                let a = playerTiles > 1 ? max(0, min(k * (tw - 100 / playerTiles), W - tw)) : 0; let b = playerTiles > 1 ? a + tw : W
                for d in players.run(image, rect: CGRect(x: a, y: 0, width: b - a, height: H), conf: playerConf) {
                    if d.cls == 0 { ps.append(d.box) }
                    else if d.cls == 32 && d.box.conf >= 0.2 {
                        let hx = d.box.cx, hy = d.box.cy
                        if fm.at(hx, hy) && bg.diff(grey: greyImg(), hx, hy) >= bgMin { hints.append(Pt(hx, hy)) }
                    }
                }
            }
            rec.persons = ps; if !hints.isEmpty { rec.hints = hints }
            tracker.playersSeen(ps); for h in hints { tracker.addHint(h, frame: f) }
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
