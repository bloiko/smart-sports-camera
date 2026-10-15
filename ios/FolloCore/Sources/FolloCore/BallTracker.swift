import Foundation

/// Ball search with a phone budget: where to look (one 320 px ROI around the predicted ball, two ROIs while it is
/// lost: ball hints from the player pass, feet near the play centre, player clusters, play centre) and which
/// candidate to accept. Port of the tracker inside detect() of src/live_sim.py (keep in sync).
public final class BallTracker {
    public struct Params {
        public var playerEvery = 4, ballEvery = 2, roi = 320, lostRois = 2
        public var conf = 0.4, confNear = 0.25, bgMin = 15.0
        /// Re-acquiring a lost ball: a candidate far from players (isoNear heights) or from the play centre (isoFar px)
        /// counts only when it flies (moveMin…moveMax px per frame since the first look); stillN looks within stillPx over
        /// ≥ stillS → black list; slow (held, barely rolling) is neither taken nor black-listed
        /// (spare balls beyond the line, a ball boy). Found on the phone: Core ML sees them and the camera drove there.
        public var isoNear = 3.0, isoFar = 800.0, pendS = 2.0, stillS = 0.5, stillPx = 15.0, stillN = 3, moveMin = 4.0, moveMax = 60.0, pendMax = 8
        public init() {}
    }
    public let P: Params
    let W: Double, H: Double, fps: Double, fm: Mask
    public let fmd: Mask
    var ball: Pt? = nil; var ballV = Pt(0, 0); var ballF = -1_000_000_000
    var centre: Pt; var scan = 0; var hot: [Pt] = []; var feet: [Pt] = []
    var black: [Pt] = []; var lastPs: [Box] = []
    var hist: [(f: Int, p: Pt)] = []            // last 200 accepted balls
    var hints: [(x: Double, y: Double, f: Int)] = []   // last 20 ball hints from the player pass
    public var blacklist: [Pt] { black }
    var pends: [(f: Int, p: Pt, n: Int, last: Int)] = []   // isolated candidates waiting: first frame, point, looks in place, last look

    func suspect(_ p: Pt) -> Bool {
        let near = lastPs.map { Stats.hypot(p.x - $0.cx, p.y - $0.y1) / max($0.h, 1) }.min() ?? 99
        return near > P.isoNear || Stats.hypot(p.x - centre.x, p.y - centre.y) > P.isoFar
    }
    /// Hints at a black-listed spot are ignored.
    public func notBlack(_ x: Double, _ y: Double) -> Bool { black.allSatisfy { Stats.hypot(x - $0.x, y - $0.y) > 30 } }

    public init(W: Int, H: Int, fps: Double, fm: Mask, fmd: Mask, params: Params = Params()) {
        self.W = Double(W); self.H = Double(H); self.fps = fps; self.fm = fm; self.fmd = fmd; P = params
        centre = Pt(Double(W) / 2, Double(H) / 2)
    }


    /// A ball hint from the player pass (COCO "sports ball" ≥ 0.2) is kept when on the pitch and unlike the background.
    public func addHint(_ p: Pt, frame f: Int) {
        hints.append((p.x, p.y, f)); if hints.count > 20 { hints.removeFirst() }
    }

    /// Players of a player frame: play centre, clusters (hot) and feet near the centre for the lost-ball search.
    public func playersSeen(_ ps: [Box]) {
        lastPs = ps
        let pl = ps.filter { $0.conf >= 0.25 && fmd.at($0.cx, $0.y1) }.map { Pt($0.cx, $0.y1) }
        guard !pl.isEmpty else { return }
        let mx = Stats.percentile(pl.map { $0.x }, 50), my = Stats.percentile(pl.map { $0.y }, 50)
        let w = pl.map { 1 / (1 + pow(Stats.hypot($0.x - mx, $0.y - my) / 300, 2)) }; let sw = w.reduce(0, +)
        var sx = 0.0, sy = 0.0; for i in 0..<pl.count { sx += w[i] * pl[i].x; sy += w[i] * pl[i].y }
        centre = Pt(sx / sw, sy / sw)
        let dens = pl.map { p in pl.filter { Stats.hypot($0.x - p.x, $0.y - p.y) < 250 }.count }
        hot = []
        for i in (0..<pl.count).sorted(by: { dens[$0] > dens[$1] }) {        // stable: ties keep index order
            if hot.allSatisfy({ Stats.hypot(pl[i].x - $0.x, pl[i].y - $0.y) > 300 }) { hot.append(Pt(pl[i].x, pl[i].y - 30)) }
            if hot.count == 3 { break }
        }
        let d = pl.map { Stats.hypot($0.x - centre.x, $0.y - centre.y) }
        feet = (0..<pl.count).sorted(by: { d[$0] < d[$1] }).prefix(6).map { Pt(pl[$0].x, pl[$0].y - 20) }
    }

    /// Where to look on ball frame f (top-left corners of ROI×ROI tiles, clipped inside the image).
    public func rois(frame f: Int) -> [(Int, Int)] {
        let lost = Double(f - ballF) / fps > 0.5
        var cs: [Pt] = []
        if !lost, let b = ball { cs = [Pt(b.x + ballV.x * Double(f - ballF), b.y + ballV.y * Double(f - ballF))] }
        else {
            let cands = hints.filter { f - $0.f <= P.playerEvery * 2 }.map { Pt($0.x, $0.y) } + feet + hot + [centre]
            pends = pends.filter { Double(f - $0.f) <= P.pendS * fps }
            if let q = pends.max(by: { $0.last < $1.last }) { cs.append(q.p) }      // look again: flying or still?
            for _ in 0..<(P.lostRois - cs.count) { cs.append(cands[scan % cands.count]); scan += 1 }
        }
        roiCentres = cs
        return cs.map { (Int(Stats.clip($0.x - Double(P.roi) / 2, 0, W - Double(P.roi))), Int(Stats.clip($0.y - Double(P.roi) / 2, 0, H - Double(P.roi)))) }
    }
    var roiCentres: [Pt] = []
    public func debugCands(frame f: Int) -> String {
        let hs = hints.filter { f - $0.f <= P.playerEvery * 2 }.map { "h(\(Int($0.x)),\(Int($0.y)))" }
        return (hs + feet.map { "f(\(Int($0.x)),\(Int($0.y)))" } + hot.map { "hot(\(Int($0.x)),\(Int($0.y)))" } + ["c(\(Int(centre.x)),\(Int(centre.y)))"]).joined(separator: " ") + " scan \(scan) ballF \(ballF)"
    }

    /// Candidates of all ROIs of frame f → accepted ball (and a blacklisted static look-alike, if any).
    public func accept(frame f: Int, _ cands: [BallCand]) -> (ball: Pt?, black: Pt?) {
        let lost = Double(f - ballF) / fps > 0.5; let c = roiCentres[0]
        var good = cands.filter { bb in
            let p = Pt(bb.box.cx, bb.box.cy)
            let thr = (!lost && Stats.hypot(p.x - c.x, p.y - c.y) < 60) ? P.confNear : P.conf
            return bb.box.conf >= thr && bb.bg >= P.bgMin && fm.at(p.x, p.y) && black.allSatisfy { Stats.hypot(p.x - $0.x, p.y - $0.y) > 30 }
        }
        if !good.isEmpty && lost {                                  // near the play wins over isolated candidates
            let iso = good.map { suspect(Pt($0.box.cx, $0.box.cy)) }
            if !iso.allSatisfy({ $0 }) { good = zip(good, iso).filter { !$0.1 }.map { $0.0 } }
        }
        guard !good.isEmpty else { return (nil, nil) }
        let pts = good.map { Pt($0.box.cx, $0.box.cy) }
        let ref = lost ? pts[(0..<good.count).max(by: { good[$0].box.conf < good[$1].box.conf })!] : c
        let k = (0..<pts.count).min(by: { Stats.hypot(pts[$0].x - ref.x, pts[$0].y - ref.y) < Stats.hypot(pts[$1].x - ref.x, pts[$1].y - ref.y) })!
        guard lost || Stats.hypot(pts[k].x - c.x, pts[k].y - c.y) < 350 * Double(f - ballF) / Double(P.ballEvery) else { return (nil, nil) }
        if lost && suspect(pts[k]) {
            pends = pends.filter { Double(f - $0.f) <= P.pendS * fps }
            let p = pts[k]; let dist = { (q: (f: Int, p: Pt, n: Int, last: Int)) in Stats.hypot(p.x - q.p.x, p.y - q.p.y) }
            let i = pends.indices.min(by: { dist(pends[$0]) < dist(pends[$1]) })
            let d = i.map { dist(pends[$0]) } ?? 1e9
            if let i, d < P.stillPx {                               // same spot
                pends[i].n += 1; pends[i].last = f
                if pends[i].n >= P.stillN && Double(f - pends[i].f) >= P.stillS * fps { black.append(p); pends.remove(at: i); return (nil, p) }
                return (nil, nil)
            } else if let i, f > pends[i].f, (P.moveMin...P.moveMax).contains(d / Double(f - pends[i].f)) {
                pends.remove(at: i)                                 // flying: the ball
            } else {
                pends.append((f, p, 1, f)); if pends.count > P.pendMax { pends.removeFirst(pends.count - P.pendMax) }
                return (nil, nil)
            }
        }
        if !lost, let b = ball { let d = Double(max(1, f - ballF)); ballV = Pt(0.5 * ballV.x + 0.5 * (pts[k].x - b.x) / d, 0.5 * ballV.y + 0.5 * (pts[k].y - b.y) / d) }
        else { ballV = Pt(0, 0) }
        ball = pts[k]; ballF = f
        hist.append((f, pts[k])); if hist.count > 200 { hist.removeFirst() }
        // a "ball" 3 s in one place with no player near it: a static look-alike (spare ball, a person behind the pitch)
        let old = hist.contains { Double(f - $0.f) >= 3 * fps }
        let still = hist.filter { Double(f - $0.f) <= 3 * fps }.allSatisfy { Stats.hypot($0.p.x - pts[k].x, $0.p.y - pts[k].y) < 25 }
        if old && still {
            let near = lastPs.map { Stats.hypot(pts[k].x - $0.cx, pts[k].y - $0.y1) / max($0.h, 1) }.min() ?? 99
            if near > 1.3 { black.append(pts[k]); ballF = -1_000_000_000; hist.removeAll(); return (nil, pts[k]) }
        }
        return (pts[k], nil)
    }
}
