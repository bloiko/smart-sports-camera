"""Live camera, streaming form: the camera path for frame f is produced when frame f + B has arrived and uses
nothing later than f + B. Mirrors ios/FolloCore/Sources/FolloCore/LiveCamera*.swift line by line (keep both in sync).

Why a rewrite of the batch version in live_sim.py (2026-10-12): the batch code quietly looked further ahead than
the buffer: goal-mode anticipation up to B frames beyond f + B, ball confirmation 0.6 s beyond, field depth from
the first 64 s of the match before frame 0, the border shift 2 s ahead. On the phone none of this exists.

Usage from live_sim.py:  cam = LiveCamera(W, H, fps, fmd, top, bot, cline, B_s, CAM); for f, rec in ...: cam.push(f, rec)
then cam.finish() → dict of arrays (same keys as before).
"""
import math, numpy as np
from goals import LiveGoals

PLAYER_EVERY = 4


def percentile(v, p):
    """numpy.percentile with linear interpolation (mirrors Stats.percentile in Swift)."""
    s = sorted(v); k = p / 100 * (len(s) - 1); i = int(math.floor(k)); t = k - i
    return s[i] if i + 1 >= len(s) else s[i] * (1 - t) + s[i + 1] * t


def interp(x, xs, ys):
    """numpy.interp for 2 points (clamped linear)."""
    if x <= xs[0]: return ys[0]
    if x >= xs[1]: return ys[1]
    return ys[0] + (ys[1] - ys[0]) * (x - xs[0]) / (xs[1] - xs[0])


def clip(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


class Causal:
    """Moving mean over the last r values (gauss_causal of live_sim: first values are means of what exists)."""
    def __init__(self, r): self.r, self.buf = max(r, 1), []
    def push(self, v):
        self.buf.append(v)
        if len(self.buf) > self.r: self.buf.pop(0)
        return sum(self.buf) / len(self.buf)


class LiveCamera:
    def __init__(self, W, H, fps, fmd, top, bot, cline, B_s, C):
        self.W, self.H, self.fps, self.fmd, self.top, self.bot, self.C = W, H, fps, fmd, top, bot, C
        self.B = int(round(B_s * fps)); self.win = int(C['confirm_s'] * fps); self.fut = min(self.B, self.win)
        self.sig = C['smooth_s'] * fps; self.P = int(3 * self.sig)
        self.lg = LiveGoals(fmd, PLAYER_EVERY / fps, centre=cline); self.G = None; self.next_g = C['goal_min_data_s'] * fps
        self.depth = [150.0, 700.0]; self.rows = 0; self.ys = []
        self.pc, self.spread = (W / 2, H / 2), W / 2; self.zone_hist = [[], []]; self.zn = [0, 0]
        self.S = []            # per frame: (pc, spread, zn, base, G)
        self.balls = []        # (frame, (x, y))
        self.goals_at = []     # per frame: G or None
        self.TX, self.TY, self.TW, self.GW, self.GI = [], [], [], [], []   # final targets for g <= f - fut
        self.gon_on, self.gon_low = False, 0; self.GONf = []               # hysteresis state after final frames
        self.X1, self.Y1, self.CW1 = [], [], []                            # stage-1 outputs (speed limit reference)
        self.X, self.Y, self.CW, self.CH, self.GON, self.GIo, self.BX, self.BY = [], [], [], [], [], [], [], []
        self.ysm, self.zsm, self.msm = Causal(int(0.2 * fps)), Causal(int(0.6 * fps)), Causal(int(0.5 * fps))
        self.goals_first = None; self.pushed = -1
        self.PF = []           # (frame, field players) of every player frame: zone counts for highlights after Stop

    # ---------------------------------------------------------------- input
    def field_players(self, ps):
        H, W = self.H, self.W; out = []
        for b in ps:
            if b[4] >= 0.25 and 12 <= b[3] - b[1] <= 260:
                x, y = (b[0] + b[2]) / 2, b[3]
                if self.fmd[min(int(y), H - 1), min(int(x), W - 1)]: out.append((x, y))
        return out

    def push(self, f, rec):
        assert f == self.pushed + 1; self.pushed = f
        C, fps = self.C, self.fps
        if 'persons' in rec:
            self.lg.add(rec['persons']); self.rows += 1
            if self.rows <= 400: self.ys += [b[3] for b in rec['persons'] if b[4] >= 0.25]
        if f >= self.next_g:
            g = self.lg.update()
            if g is not None:
                self.G = [(float(g[0][0]), float(g[0][1])), (float(g[1][0]), float(g[1][1]))]
                if self.goals_first is None: self.goals_first = f / fps
            self.next_g += C['goal_every_s'] * fps
        if f % int(fps) == 0 and self.rows <= 400 and len(self.ys) > 50:
            self.depth = [percentile(self.ys, 2), percentile(self.ys, 98)]
        self.goals_at.append(self.G)
        if 'persons' in rec:
            pl = self.field_players(rec['persons']); self.PF.append((f, pl))
            if pl:
                mx, my = percentile([p[0] for p in pl], 50), percentile([p[1] for p in pl], 50)
                w = [1 / (1 + (math.hypot(p[0] - mx, p[1] - my) / C['focus_px']) ** 2) for p in pl]; sw = sum(w)
                self.pc = (sum(wi * p[0] for wi, p in zip(w, pl)) / sw, sum(wi * p[1] for wi, p in zip(w, pl)) / sw)
                self.spread = 2.5 * math.sqrt(sum(wi * (p[0] - self.pc[0]) ** 2 for wi, p in zip(w, pl)) / sw)
            if self.G is not None:
                D = math.hypot(self.G[1][0] - self.G[0][0], self.G[1][1] - self.G[0][1])
                self.zn = [sum(1 for p in pl if math.hypot(p[0] - self.G[k][0], p[1] - self.G[k][1]) < C['goal_zone'][1] * D) for k in range(2)]
                for k in range(2): self.zone_hist[k].append(self.zn[k])
        base = [percentile(self.zone_hist[k], 50) if self.zone_hist[k] else 0 for k in range(2)]
        self.S.append((self.pc, self.spread, list(self.zn), base, self.G))
        if 'ball' in rec: self.balls.append((f, (rec['ball'][0], rec['ball'][1])))
        g = f - self.fut
        if g >= 0:
            tx, ty, tw, gw, gi = self.target(g, f)
            self.TX.append(tx); self.TY.append(ty); self.TW.append(tw); self.GW.append(gw); self.GI.append(gi)
            self.gon_on, self.gon_low = self.hyst(self.gon_on, self.gon_low, gw); self.GONf.append(self.gon_on)
        o = f - self.B
        if o >= 0: self.emit(o, f)

    # ---------------------------------------------------------------- ball confirmation and targets
    def confirmed(self, i, h):
        """balls[i] has another ball within [-win, min(fut, h - frame)] frames and confirm_px (6 neighbours each side)."""
        f, p = self.balls[i]
        for j in range(max(0, i - 6), min(len(self.balls), i + 7)):
            if j == i: continue
            g, q = self.balls[j]
            if g > h: break
            if -self.win <= g - f <= min(self.fut, h - f) and math.hypot(q[0] - p[0], q[1] - p[1]) < self.C['confirm_px']: return True
        return False

    def last_ball(self, g, h):
        """Latest confirmed ball at a frame <= g, seen with data up to h; None if older than hold + 1 s (same effect)."""
        limit = g - int((self.C['ball_hold_s'] + 1) * self.fps) - 1
        for i in range(len(self.balls) - 1, -1, -1):
            f, p = self.balls[i]
            if f > g: continue
            if f < limit: return None
            if self.confirmed(i, h): return (f, p)
        return None

    def target(self, g, h):
        C = self.C; pc, spread, zn, base, G = self.S[g]; lb = self.last_ball(g, h)
        ball_ok = lb is not None and (g - lb[0]) / self.fps <= C['ball_hold_s']
        c = (C['ball_weight'] * lb[1][0] + (1 - C['ball_weight']) * pc[0], C['ball_weight'] * lb[1][1] + (1 - C['ball_weight']) * pc[1]) if ball_ok else pc
        lo = interp(c[1], self.depth, C['min_crop_w']); hi = interp(c[1], self.depth, C['max_crop_w'])
        cw = clip(spread * C['spread_k'], lo, hi)
        if not ball_ok:
            lost_s = (g - lb[0]) / self.fps if lb else 1e9
            cw = min(cw * (1 + (C['lost_zoom'] - 1) * min(1.0, (lost_s - C['ball_hold_s']) / 1.0)), hi * C['lost_zoom'])
        gw, gi = 0.0, -1
        if G is not None:
            D = math.hypot(G[1][0] - G[0][0], G[1][1] - G[0][1]); focus = lb[1] if ball_ok else pc
            for k in range(2):
                d = math.hypot(focus[0] - G[k][0], focus[1] - G[k][1]) / D
                wk = clip((C['goal_zone'][1] - d) / (C['goal_zone'][1] - C['goal_zone'][0]), 0, 1)
                wa = clip((zn[k] - base[k] - 1) / (C['goal_attack_n'] - 1), 0, 1)
                if ball_ok and d > C['goal_zone'][1]: wa *= 0.3
                if max(wk, wa) > gw: gw, gi = max(wk, wa), k
            if gw > 0:
                gx, gy = G[gi]; hw = C['goal_box_k'] * interp(gy, self.depth, C['min_crop_w']) + C['goal_unc']
                xs = [gx - hw, gx + hw] + ([focus[0]] if ball_ok else []); ys = [gy - hw * 0.6, gy + hw * 0.6] + ([focus[1]] if ball_ok else [])
                need = (max(xs) - min(xs)) * (1 + 2 * C['margin']) * 1.1
                gc = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
                c = ((1 - gw) * c[0] + gw * gc[0], (1 - gw) * c[1] + gw * gc[1]); cw = (1 - gw) * cw + gw * clip(need, lo, hi)
        return c[0], c[1], cw, gw, gi

    def hyst(self, on, low, gw):
        if not on: return gw > 0.5, 0
        low = low + 1 if gw <= 0.25 else 0
        return low < self.C['goal_hold_s'] * self.fps, low

    def targets_range(self, a, b, h):
        """Targets and goal weights for frames a..b with data up to h: final where available, provisional after."""
        out = []
        for g in range(a, b + 1):
            out.append((self.TX[g], self.TY[g], self.TW[g], self.GW[g], self.GI[g]) if g < len(self.TX) else self.target(g, h))
        return out

    def gon_range(self, o, h, tg):
        """Goal mode (with hysteresis and anticipation within the horizon) for frames o..h; tg = targets o..h."""
        n = h - o + 1; gon, gi = [False] * n, [-1] * n
        on, low = self.gon_on, self.gon_low
        for i, g in enumerate(range(o, h + 1)):
            if g < len(self.GONf): gon[i] = self.GONf[g]
            else: on, low = self.hyst(on, low, tg[i][3]); gon[i] = on
            gi[i] = tg[i][4]
        ant = min(self.B, int(self.C['anticipate_s'] * self.fps)); out_on, out_gi = list(gon), list(gi); nxt = -1
        for i in range(n - 1, -1, -1):
            if gon[i]: nxt = i
            elif nxt >= 0 and nxt - i <= ant: out_on[i] = True; out_gi[i] = gi[nxt]
        return out_on, out_gi

    # ---------------------------------------------------------------- output for frame o with data up to h = o + B
    def emit(self, o, h):
        C, fps, B, W, H = self.C, self.fps, self.B, self.W, self.H
        a, b = max(0, o - self.P), min(h, o + self.P)
        tg = self.targets_range(a, h, h); gon, gi = self.gon_range(o, h, tg[o - a:])
        sw = sx = sy = scw = 0.0
        for g in range(a, b + 1):
            w = math.exp(-0.5 * ((g - o) / self.sig) ** 2); t = tg[g - a]
            sw += w; sx += w * t[0]; sy += w * t[1]; scw += w * t[2]
        x, y, cw = sx / sw, sy / sw, scw / sw
        vmax, vcatch = C['max_speed'] / fps, C['catch_k'] * C['max_speed'] / fps
        lo_x, hi_x, need_w = -math.inf, math.inf, 0.0; ylo, yhi = math.inf, -math.inf
        for k in range(0, B + 1, 2):
            g = o + k
            if g > h: break
            pts = []
            j = g
            while j >= max(0, g - int(0.3 * fps)) and self.ball_at(j, h) is None: j -= 1
            if j >= 0 and self.ball_at(j, h) is not None: pts.append(self.ball_at(j, h) + (0.0,))
            if gon[k] and gi[k] >= 0 and self.goals_at[g] is not None:
                gg = self.goals_at[g][gi[k]]; hw = C['goal_box_k'] * interp(gg[1], self.depth, C['min_crop_w']) + C['goal_unc']; pts.append((gg[0], gg[1], hw))
            for px, py, hw in pts:
                m = C['margin'] * cw
                l, hh_ = px + hw + m - cw / 2 - vcatch * k, px - hw - m + cw / 2 + vcatch * k
                if l <= hh_: lo_x, hi_x = max(lo_x, l), min(hi_x, hh_)
                need_w = max(need_w, 2 * hw + 2 * m)
                if k == 0:
                    hh = hw * 0.6 + (C['goal_unc'] * 0.4 if hw else 0)
                    ylo, yhi = min(ylo, py - hh - m * C['out_h'] / C['out_w']), max(yhi, py + hh + m * C['out_h'] / C['out_w'])
        cw = max(cw, need_w)
        if lo_x <= hi_x: x = clip(x, lo_x, hi_x)
        if o:
            lim = vcatch if lo_x > -math.inf else vmax
            x = self.X1[-1] + clip(x - self.X1[-1], -lim, lim); y = self.Y1[-1] + clip(y - self.Y1[-1], -vmax, vmax)
            cw = self.CW1[-1] + clip(cw - self.CW1[-1], -vmax, vmax)
        self.X1.append(x); self.Y1.append(y); self.CW1.append(cw)
        self.post(o, x, y, cw, ylo, yhi, lo_x if lo_x <= hi_x else None, hi_x if lo_x <= hi_x else None, gon[0], gi[0], h)

    def ball_at(self, j, h):
        """Confirmed ball exactly at frame j (data up to h), else None. Balls are sparse, so search from the end."""
        for i in range(len(self.balls) - 1, -1, -1):
            f, p = self.balls[i]
            if f < j: return None
            if f == j: return p if self.confirmed(i, h) else None
        return None

    def post(self, o, x, y, cw, ylo, yhi, lox, hix, gon, gi, h):
        C, W, H, top, bot = self.C, self.W, self.H, self.top, self.bot; asp = C['out_h'] / C['out_w']
        cw = min(cw, H / asp); ch = cw * asp
        x = clip(x, cw / 2, W - cw / 2); y = y - ch * 0.08
        if ylo < math.inf:
            if yhi - ylo > ch: ch = yhi - ylo; cw = ch / asp
            y = clip(y, yhi - ch / 2, ylo + ch / 2)
        y = self.ysm.push(y); cw = min(cw, H / asp); ch = cw * asp
        a, b = int(max(0, x - cw / 2)), int(min(W, x + cw / 2))
        push = (max(top[a:b]) - (y - ch / 2)) / ch; zf = 1.0
        if push > 0.2 and not gon: zf = max(0.75, 1 - (push - 0.2))
        zf = self.zsm.push(zf); cw = cw * zf; ch = cw * asp
        ns = 0
        if ylo < math.inf and gon and gi >= 0:
            step = 10 if gi == 0 else -10; sh = 0
            for _ in range(C['border_shift_max'] // 10):
                a, b = int(max(0, x + sh - cw / 2)), int(min(W, x + sh + cw / 2))
                if max(top[a:b]) <= ylo: break
                sh += step
            ns = sh
        m = self.msm.push(abs(ns))
        if m > 0:
            x = x + (-1.0 if gi == 1 else 1.0) * m
            if lox is not None: x = clip(x, lox, hix)
        a, b = int(x - cw / 2), int(x + cw / 2); t, bt = max(top[max(a, 0):b]), min(bot[max(a, 0):b])
        if bt - t < ch: ch = bt - t; cw = ch / asp; x = clip(x, cw / 2, W - cw / 2)
        y = clip(y, t + ch / 2, bt - ch / 2)
        self.X.append(x); self.Y.append(y); self.CW.append(cw); self.CH.append(ch); self.GON.append(gon); self.GIo.append(gi)
        p = self.ball_at(o, h); self.BX.append(p[0] if p else math.nan); self.BY.append(p[1] if p else math.nan)

    def finish(self):
        """Flush the last B frames (no more input: the horizon stays at the last frame)."""
        h = self.pushed
        for g in range(len(self.TX), h + 1):
            tx, ty, tw, gw, gi = self.target(g, h)
            self.TX.append(tx); self.TY.append(ty); self.TW.append(tw); self.GW.append(gw); self.GI.append(gi)
            self.gon_on, self.gon_low = self.hyst(self.gon_on, self.gon_low, gw); self.GONf.append(self.gon_on)
        for o in range(len(self.X), h + 1): self.emit(o, h)
        G = self.G if self.G is not None else [(math.nan, math.nan)] * 2
        # for highlights.py (as follow.py): players in each goal zone per player frame, with the final goals
        D = math.hypot(G[1][0] - G[0][0], G[1][1] - G[0][1]); S_FRAMES = [f for f, _ in self.PF]
        ZN = [[sum(1 for p in pl if math.hypot(p[0] - G[k][0], p[1] - G[k][1]) < self.C['goal_zone'][1] * D) for k in range(2)] for _, pl in self.PF]
        ZONE_BASE = [percentile([z[k] for z in ZN], 50) if ZN else 0 for k in range(2)]
        return dict(S_FRAMES=np.array(S_FRAMES), ZN=np.array(ZN).reshape(-1, 2), ZONE_BASE=np.array(ZONE_BASE),X=np.array(self.X), Y=np.array(self.Y), CW=np.array(self.CW), CH=np.array(self.CH), FPS=self.fps,
                    GON=np.array(self.GON), GI=np.array(self.GIo), BX=np.array(self.BX), BY=np.array(self.BY), GOALS=np.array(G),
                    GOAL_DIST=float(math.hypot(G[1][0] - G[0][0], G[1][1] - G[0][1])), goals_first_s=float(self.goals_first if self.goals_first is not None else math.nan))
