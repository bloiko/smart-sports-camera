import Foundation

/// Part 2 of LiveCamera: smoothing with the look-ahead buffer, hard constraints (ball, goal), post-processing.
extension LiveCamera {
    /// Targets for frames a...b with data up to h: final where available, provisional after.
    func targetsRange(_ a: Int, _ b: Int, horizon h: Int) -> [Target] {
        var out: [Target] = []
        for g in a...b {
            if g < TX.count { out.append((x: TX[g], y: TY[g], cw: TW[g], gw: GW[g], gi: GI[g])) } else { out.append(target(g, horizon: h)) }
        }
        return out
    }

    /// Goal mode (hysteresis + anticipation inside the horizon) for frames o...h; tg = targets o...h.
    func gonRange(_ o: Int, _ h: Int, _ tg: ArraySlice<Target>) -> ([Bool], [Int]) {
        let n = h - o + 1; var gon = [Bool](repeating: false, count: n), gi = [Int](repeating: -1, count: n)
        var on = gonOn, low = gonLow; let t = Array(tg)
        for i in 0..<n {
            let g = o + i
            if g < GONf.count { gon[i] = GONf[g] } else { (on, low) = hyst(on, low, t[i].gw); gon[i] = on }
            gi[i] = t[i].gi
        }
        let ant = min(B, Int(C.anticipateS * fps)); var outOn = gon, outGi = gi; var nxt = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if gon[i] { nxt = i } else if nxt >= 0 && nxt - i <= ant { outOn[i] = true; outGi[i] = gi[nxt] }
        }
        return (outOn, outGi)
    }

    func emit(_ o: Int, horizon h: Int) {
        let a = max(0, o - P), b = min(h, o + P)
        let tg = targetsRange(a, h, horizon: h); let (gon, gi) = gonRange(o, h, tg[(o - a)...])
        var sw = 0.0, sx = 0.0, sy = 0.0, scw = 0.0
        for g in a...b {
            let w = exp(-0.5 * pow(Double(g - o) / sig, 2)); let t = tg[g - a]
            sw += w; sx += w * t.x; sy += w * t.y; scw += w * t.cw
        }
        var x = sx / sw, y = sy / sw, cw = scw / sw
        let vmax = C.maxSpeed / fps, vcatch = C.catchK * C.maxSpeed / fps, asp = C.outH / C.outW
        var loX = -Double.infinity, hiX = Double.infinity, needW = 0.0, ylo = Double.infinity, yhi = -Double.infinity
        for k in stride(from: 0, through: B, by: 2) {
            let g = o + k
            if g > h { break }
            var pts: [(Double, Double, Double)] = []
            var j = g
            while j >= max(0, g - Int(0.3 * fps)) && ballAt(j, horizon: h) == nil { j -= 1 }
            if j >= 0, let p = ballAt(j, horizon: h) { pts.append((p.x, p.y, 0)) }
            if gon[k] && gi[k] >= 0, let gs = goalsAt[g] {
                let gg = gs[gi[k]]; let hw = C.goalBoxK * Stats.interp(gg.y, depth, C.minCropW) + C.goalUnc; pts.append((gg.x, gg.y, hw))
            }
            for (px, py, hw) in pts {
                let m = C.margin * cw
                let l = px + hw + m - cw / 2 - vcatch * Double(k), hh = px - hw - m + cw / 2 + vcatch * Double(k)
                if l <= hh { loX = max(loX, l); hiX = min(hiX, hh) }
                needW = max(needW, 2 * hw + 2 * m)
                if k == 0 {
                    let hh2 = hw * 0.6 + (hw != 0 ? C.goalUnc * 0.4 : 0)
                    ylo = min(ylo, py - hh2 - m * asp); yhi = max(yhi, py + hh2 + m * asp)
                }
            }
        }
        cw = max(cw, needW)
        if loX <= hiX { x = Stats.clip(x, loX, hiX) }
        if o > 0 {
            let lim = loX > -Double.infinity ? vcatch : vmax
            x = X1[o - 1] + Stats.clip(x - X1[o - 1], -lim, lim); y = Y1[o - 1] + Stats.clip(y - Y1[o - 1], -vmax, vmax)
            cw = CW1[o - 1] + Stats.clip(cw - CW1[o - 1], -vmax, vmax)
        }
        X1.append(x); Y1.append(y); CW1.append(cw)
        post(o, x, y, cw, ylo, yhi, loX <= hiX ? (loX, hiX) : nil, gon[0], gi[0], horizon: h)
    }

    func topMax(_ a: Int, _ b: Int) -> Double { let a2 = max(a, 0), b2 = max(min(b, top.count), a2 + 1); return top[a2..<b2].max()! }
    func botMin(_ a: Int, _ b: Int) -> Double { let a2 = max(a, 0), b2 = max(min(b, bot.count), a2 + 1); return bot[a2..<b2].min()! }

    func post(_ o: Int, _ x0: Double, _ y0: Double, _ cw0: Double, _ ylo: Double, _ yhi: Double, _ lim: (Double, Double)?, _ gon: Bool, _ gi: Int, horizon h: Int) {
        let asp = C.outH / C.outW
        var cw = min(cw0, H / asp), ch = cw * asp
        var x = Stats.clip(x0, cw / 2, W - cw / 2), y = y0 - ch * 0.08
        if ylo < Double.infinity {
            if yhi - ylo > ch { ch = yhi - ylo; cw = ch / asp }
            y = Stats.clip(y, yhi - ch / 2, ylo + ch / 2)
        }
        y = ysm.push(y); cw = min(cw, H / asp); ch = cw * asp
        let push = (topMax(Int(max(0, x - cw / 2)), Int(min(W, x + cw / 2))) - (y - ch / 2)) / ch
        var zf = 1.0
        if push > 0.2 && !gon { zf = max(0.75, 1 - (push - 0.2)) }
        zf = zsm.push(zf); cw = cw * zf; ch = cw * asp
        var ns = 0
        if ylo < Double.infinity && gon && gi >= 0 {
            let step = gi == 0 ? 10 : -10; var sh = 0
            for _ in 0..<(C.borderShiftMax / 10) {
                if topMax(Int(max(0, x + Double(sh) - cw / 2)), Int(min(W, x + Double(sh) + cw / 2))) <= ylo { break }
                sh += step
            }
            ns = sh
        }
        let m = msm.push(Double(abs(ns)))
        if m > 0 {
            x = x + (gi == 1 ? -1.0 : 1.0) * m
            if let (lo, hi) = lim { x = Stats.clip(x, lo, hi) }
        }
        let a = Int(x - cw / 2), b = Int(x + cw / 2); let t = topMax(a, b), bt = botMin(a, b)
        if bt - t < ch { ch = bt - t; cw = ch / asp; x = Stats.clip(x, cw / 2, W - cw / 2) }
        y = Stats.clip(y, t + ch / 2, bt - ch / 2)
        let fr = Frame(x: x, y: y, cw: cw, ch: ch, gon: gon, gi: gi, ball: ballAt(o, horizon: h))
        frames.append(fr); onFrame?(o, fr)
    }
}
