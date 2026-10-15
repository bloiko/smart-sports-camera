import Foundation

/// Live virtual camera, streaming: the crop for frame f is emitted when frame f + B has been pushed and uses
/// nothing later than f + B. Port of src/live_cam.py (same names; keep both in sync).
/// Part 1: state, input, ball confirmation, per-frame targets. Part 2 (output): LiveCameraOutput.swift.
public final class LiveCamera {
    public struct Frame { public var x, y, cw, ch: Double; public var gon: Bool; public var gi: Int; public var ball: Pt? }
    struct State { var pc: Pt; var spread: Double; var zn: [Int]; var base: [Double]; var goals: [Pt]? }
    typealias Target = (x: Double, y: Double, cw: Double, gw: Double, gi: Int)

    public let W: Double, H: Double, fps: Double
    let fmd: Mask, top: [Double], bot: [Double], C: CameraConfig
    let B: Int, win: Int, fut: Int, sig: Double, P: Int
    let lg: LiveGoals
    var G: [Pt]? = nil; var nextG: Double
    var depth = [150.0, 700.0]; var rows = 0; var ys: [Double] = []
    var pc: Pt; var spread: Double; var zoneHist: [[Double]] = [[], []]; var zn = [0, 0]
    var S: [State] = []
    var balls: [(f: Int, p: Pt)] = []
    var goalsAt: [[Pt]?] = []
    var TX: [Double] = [], TY: [Double] = [], TW: [Double] = [], GW: [Double] = [], GI: [Int] = []
    var gonOn = false, gonLow = 0; var GONf: [Bool] = []
    var X1: [Double] = [], Y1: [Double] = [], CW1: [Double] = []
    var ysm: Causal, zsm: Causal, msm: Causal
    public internal(set) var frames: [Frame] = []
    public private(set) var goalsFirstS: Double? = nil
    var pushed = -1
    var PF: [(f: Int, pl: [Pt])] = []          // field players of every player frame: zone counts for highlights after Stop
    /// Called for every emitted frame (index, frame).
    public var onFrame: ((Int, Frame) -> Void)?

    public init(W: Int, H: Int, fps: Double, fmd: Mask, top: [Double], bot: [Double], centre: ((Double) -> Double)?, bufferS: Double, config: CameraConfig = CameraConfig()) {
        self.W = Double(W); self.H = Double(H); self.fps = fps; self.fmd = fmd; self.top = top; self.bot = bot; C = config
        B = Int((bufferS * fps).rounded()); win = Int(C.confirmS * fps); fut = min(B, win)
        sig = C.smoothS * fps; P = Int(3 * sig)
        lg = LiveGoals(fmask: fmd, sampleDt: Double(C.playerEvery) / fps, centre: C.mirror ? centre : nil, prior: C.goalsPrior); nextG = C.goalMinDataS * fps
        if C.goalsPrior != nil { G = lg.mirrored(); goalsFirstS = 0 }
        pc = Pt(Double(W) / 2, Double(H) / 2); spread = Double(W) / 2
        ysm = Causal(Int(0.2 * fps)); zsm = Causal(Int(0.6 * fps)); msm = Causal(Int(0.5 * fps))
    }

    public var goals: [Pt]? { G }

    func fieldPlayers(_ ps: [Box]) -> [Pt] {
        ps.compactMap { b in (b.conf >= 0.25 && b.h >= 12 && b.h <= 260 && fmd.at(b.cx, b.y1)) ? Pt(b.cx, b.y1) : nil }
    }

    // ---------------------------------------------------------------- input
    public func push(_ rec: FrameRecord) {
        let f = rec.frame; precondition(f == pushed + 1); pushed = f
        if let ps = rec.persons {
            lg.add(ps); rows += 1
            if rows <= 400 { ys += ps.filter { $0.conf >= 0.25 }.map { $0.y1 } }
        }
        if Double(f) >= nextG {
            if let g = lg.update() { G = g; if goalsFirstS == nil { goalsFirstS = Double(f) / fps } }
            nextG += C.goalEveryS * fps
        }
        if f % Int(fps) == 0 && rows <= 400 && ys.count > 50 { depth = [Stats.percentile(ys, 2), Stats.percentile(ys, 98)] }
        goalsAt.append(G)
        if let ps = rec.persons {
            let pl = fieldPlayers(ps); PF.append((f, pl))
            if !pl.isEmpty {
                let mx = Stats.percentile(pl.map { $0.x }, 50), my = Stats.percentile(pl.map { $0.y }, 50)
                let w = pl.map { 1 / (1 + pow(Stats.hypot($0.x - mx, $0.y - my) / C.focusPx, 2)) }; let sw = w.reduce(0, +)
                var sx = 0.0, sy = 0.0; for i in 0..<pl.count { sx += w[i] * pl[i].x; sy += w[i] * pl[i].y }
                pc = Pt(sx / sw, sy / sw)
                var v = 0.0; for i in 0..<pl.count { v += w[i] * pow(pl[i].x - pc.x, 2) }
                spread = 2.5 * (v / sw).squareRoot()
            }
            if let g = G {
                let D = Stats.hypot(g[1].x - g[0].x, g[1].y - g[0].y)
                zn = (0..<2).map { k in pl.filter { Stats.hypot($0.x - g[k].x, $0.y - g[k].y) < C.goalZone[1] * D }.count }
                for k in 0..<2 { zoneHist[k].append(Double(zn[k])) }
            }
        }
        let base = (0..<2).map { zoneHist[$0].isEmpty ? 0.0 : Stats.percentile(zoneHist[$0], 50) }
        S.append(State(pc: pc, spread: spread, zn: zn, base: base, goals: G))
        if let b = rec.ball { balls.append((f, b)) }
        let g = f - fut
        if g >= 0 { finalize(g, horizon: f) }
        let o = f - B
        if o >= 0 { emit(o, horizon: f) }
    }

    func finalize(_ g: Int, horizon h: Int) {
        let t = target(g, horizon: h)
        TX.append(t.x); TY.append(t.y); TW.append(t.cw); GW.append(t.gw); GI.append(t.gi)
        (gonOn, gonLow) = hyst(gonOn, gonLow, t.gw); GONf.append(gonOn)
    }

    /// No more input: flush the last B frames with the horizon at the last frame.
    public func finish() {
        let h = pushed
        if h < 0 { return }
        for g in TX.count...h { finalize(g, horizon: h) }
        if frames.count <= h { for o in frames.count...h { emit(o, horizon: h) } }
    }

    // ---------------------------------------------------------------- ball confirmation and targets
    /// balls[i] has another ball within [-win, min(fut, h - frame)] frames and confirmPx (6 neighbours each side).
    func confirmed(_ i: Int, horizon h: Int) -> Bool {
        let (f, p) = balls[i]
        for j in max(0, i - 6)..<min(balls.count, i + 7) where j != i {
            let (g, q) = balls[j]
            if g > h { break }
            if g - f >= -win && g - f <= min(fut, h - f) && Stats.hypot(q.x - p.x, q.y - p.y) < C.confirmPx { return true }
        }
        return false
    }

    /// Latest confirmed ball at a frame <= g with data up to h; nil if older than hold + 1 s (same effect).
    func lastBall(_ g: Int, horizon h: Int) -> (f: Int, p: Pt)? {
        let limit = g - Int((C.ballHoldS + 1) * fps) - 1
        for i in stride(from: balls.count - 1, through: 0, by: -1) {
            let (f, p) = balls[i]
            if f > g { continue }
            if f < limit { return nil }
            if confirmed(i, horizon: h) { return (f, p) }
        }
        return nil
    }

    /// Confirmed ball exactly at frame j (data up to h).
    func ballAt(_ j: Int, horizon h: Int) -> Pt? {
        for i in stride(from: balls.count - 1, through: 0, by: -1) {
            let (f, p) = balls[i]
            if f < j { return nil }
            if f == j { return confirmed(i, horizon: h) ? p : nil }
        }
        return nil
    }

    func target(_ g: Int, horizon h: Int) -> Target {
        let s = S[g]; let lb = lastBall(g, horizon: h)
        let ballOk = lb != nil && Double(g - lb!.f) / fps <= C.ballHoldS
        // after ballHoldS the ball weight fades over ballFadeS instead of dropping to zero (live_cam.py)
        let fade = ballOk ? 1.0 : (lb != nil && C.ballFadeS > 0 ? max(0.0, 1 - (Double(g - lb!.f) / fps - C.ballHoldS) / C.ballFadeS) : 0.0)
        let bw = C.ballWeight * fade
        var c = fade > 0 ? Pt(bw * lb!.p.x + (1 - bw) * s.pc.x, bw * lb!.p.y + (1 - bw) * s.pc.y) : s.pc
        let lo = Stats.interp(c.y, depth, C.minCropW), hi = Stats.interp(c.y, depth, C.maxCropW)
        var cw = Stats.clip(s.spread * C.spreadK, lo, hi)
        if !ballOk {
            let lostS = lb != nil ? Double(g - lb!.f) / fps : 1e9
            cw = min(cw * (1 + (C.lostZoom - 1) * min(1.0, (lostS - C.ballHoldS) / 1.0)), hi * C.lostZoom)
        }
        var gw = 0.0, gi = -1
        if let G = s.goals {
            let D = Stats.hypot(G[1].x - G[0].x, G[1].y - G[0].y); let focus = fade > 0 ? Pt(fade * lb!.p.x + (1 - fade) * s.pc.x, fade * lb!.p.y + (1 - fade) * s.pc.y) : s.pc
            // players in the goal zone averaged over znAvgS (the instant count jumps 1–5 and moved the target ~225 px each)
            let zw = max(1, Int(C.znAvgS * fps)), j0 = max(0, g - zw + 1)
            var znm = [0.0, 0.0]
            for j in j0...g { znm[0] += Double(S[j].zn[0]); znm[1] += Double(S[j].zn[1]) }
            znm = znm.map { $0 / Double(g - j0 + 1) }
            var w = [0.0, 0.0]
            for k in 0..<2 {
                let d = Stats.hypot(focus.x - G[k].x, focus.y - G[k].y) / D
                let wk = Stats.clip((C.goalZone[1] - d) / (C.goalZone[1] - C.goalZone[0]), 0, 1)
                var wa = Stats.clip((znm[k] - s.base[k] - 1) / (C.goalAttackN - 1), 0, 1)
                if ballOk && d > C.goalZone[1] { wa *= 0.3 }
                w[k] = max(wk, wa)
            }
            gi = w[1] > w[0] ? 1 : (w[0] > 0 ? 0 : -1)
            // sticky goal: the other one only when its weight is more than giKeep higher (equal counts flipped the camera)
            let prev = GI.last ?? -1
            if C.giKeep > 0 && prev >= 0 && w[prev] > 0 && w[prev] >= (gi >= 0 ? w[gi] : 0) - C.giKeep { gi = prev }
            gw = gi >= 0 ? w[gi] : 0
            if gw > 0 {
                let gx = G[gi].x, gy = G[gi].y; let hw = C.goalBoxK * Stats.interp(gy, depth, C.minCropW) + C.goalUnc
                var xs = [gx - hw, gx + hw], ys = [gy - hw * 0.6, gy + hw * 0.6]
                if ballOk { xs.append(focus.x); ys.append(focus.y) }
                let need = (xs.max()! - xs.min()!) * (1 + 2 * C.margin) * 1.1
                let gc = Pt((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
                c = Pt((1 - gw) * c.x + gw * gc.x, (1 - gw) * c.y + gw * gc.y); cw = (1 - gw) * cw + gw * Stats.clip(need, lo, hi)
            }
        }
        return (c.x, c.y, cw, gw, gi)
    }

    func hyst(_ on: Bool, _ low: Int, _ gw: Double) -> (Bool, Int) {
        if !on { return (gw > 0.5, 0) }
        let l = gw <= 0.25 ? low + 1 : 0
        return (Double(l) < C.goalHoldS * fps, l)
    }
}

extension LiveCamera {
    /// For highlights after Stop (as follow.py's S_FRAMES / ZN / ZONE_BASE): players in each goal zone per player
    /// frame with the final goals, and the usual count (median).
    public func zoneCounts() -> (frames: [Int], zn: [[Int]], base: [Double]) {
        guard let g = G else { return ([], [], [0, 0]) }
        let D = Stats.hypot(g[1].x - g[0].x, g[1].y - g[0].y)
        let zn = PF.map { pf in (0..<2).map { k in pf.pl.filter { Stats.hypot($0.x - g[k].x, $0.y - g[k].y) < C.goalZone[1] * D }.count } }
        let base = (0..<2).map { k in zn.isEmpty ? 0.0 : Stats.percentile(zn.map { Double($0[k]) }, 50) }
        return (PF.map { $0.f }, zn, base)
    }
}
