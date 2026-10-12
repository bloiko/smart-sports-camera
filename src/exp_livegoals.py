"""Experiment (2026-10-12): live goal estimate over time, variants of the tip rule, on the cached live detections.
Baseline: tips = mean of the 40 px (10 cells) at each end of the largest heat region (grows outward only).
Variants: (b) tip must be a column whose heat mass is ≥ `col_frac` of the busiest column (ignores thin tails);
(c) region threshold thr_s = 6 s instead of 3. Prints the error vs the hand-measured goals at 30, 60, 120, 240 s.
Usage: python src/exp_livegoals.py"""
import json, sys, numpy as np, cv2
sys.path.insert(0, 'src')
from goals import LiveGoals


class TipByMass(LiveGoals):
    def __init__(self, *a, col_frac=0.05, **k): super().__init__(*a, **k); self.col_frac = col_frac

    def update(self):
        s = self.SCALE; heat = self.heat()
        n, lab, st, _ = cv2.connectedComponentsWithStats((heat > self.thr).astype(np.uint8), connectivity=8)
        if n < 2: return self.best
        reg = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        col = (heat * reg).sum(0); ok = np.flatnonzero(col >= self.col_frac * col.max())
        if not len(ok): return self.best
        ys, xs = np.nonzero(reg); x0, x1 = ok[0], ok[-1]
        l, r = (xs >= x0) & (xs <= x0 + 40 // s), (xs <= x1) & (xs >= x1 - 40 // s)
        if not l.any() or not r.any(): return self.best
        t = np.array([[xs[l].mean(), ys[l].mean()], [xs[r].mean(), ys[r].mean()]]) * s + (s - 1) / 2
        if self.best is None: self.best = t; return self.mirrored()
        for k, outward in ((0, t[0, 0] < self.best[0, 0]), (1, t[1, 0] > self.best[1, 0])):
            if not outward: self.pending[k] = None; continue
            if abs(t[k, 0] - self.best[k, 0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            elif self.pending[k] is not None and abs(t[k, 0] - self.pending[k][0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            else: self.pending[k] = t[k]
        return self.mirrored()


def run(m, make):
    det = [json.loads(l) for l in open(f'work/m{m}/live_pre/live_det.jsonl')]
    env = json.load(open(f'work/m{m}/live_pre/env.json')); fmd = (cv2.imread(f'work/m{m}/live_pre/fmd.png', 0) > 127).astype(np.uint8)
    H = env['H']; x0, x1 = env['cline']['x0'], env['cline']['x1']; cl = (lambda y: x0 + (x1 - x0) * y / H) if x0 == x0 else None
    lg = make(fmd, 4 / 25, cl); cl_ = json.load(open(f'specs/checklists/match{m}.json'))['goals']; truth = np.array([cl_['left'], cl_['right']])
    out = {}; nxt = 30 * 25
    for f, r in enumerate(det):
        if 'persons' in r: lg.add(r['persons'])
        if f >= nxt:
            g = lg.update(); nxt += 10 * 25
            if g is not None and (f // 25) in (30, 60, 120, 240): out[f // 25] = np.round(np.abs(g - truth)).astype(int).tolist()
    g = lg.update(); out['end'] = np.round(np.abs(g - truth)).astype(int).tolist() if g is not None else None
    return out


variants = {
    'baseline (region tips, thr 3 s)': lambda fm, dt, cl: LiveGoals(fm, dt, centre=cl),
    'tip by column mass ≥ 5%': lambda fm, dt, cl: TipByMass(fm, dt, centre=cl, col_frac=0.05),
    'tip by column mass ≥ 10%': lambda fm, dt, cl: TipByMass(fm, dt, centre=cl, col_frac=0.10),
    'tip by column mass ≥ 20%': lambda fm, dt, cl: TipByMass(fm, dt, centre=cl, col_frac=0.20),
    'region thr 6 s': lambda fm, dt, cl: LiveGoals(fm, dt, thr_s=6.0, centre=cl),
}
for name, mk in variants.items():
    print('==', name)
    for m in (1, 2, 3):
        o = run(m, mk); print(f'  m{m}: ' + '  '.join(f'{k}s: L{v[0]} R{v[1]}' if k != 'end' else f'end: L{v[0]} R{v[1]}' for k, v in o.items()))


class DenseTip(LiveGoals):
    """Goal = the densest spot of the heat map within the outer `band` px of the play region on each side
    (keeper + penalty-area play), not the extreme pixels (corner kicks pull those to the corner flags)."""
    def __init__(self, *a, band=200, frac=0.5, **k): super().__init__(*a, **k); self.band, self.frac = band, frac

    def update(self):
        s = self.SCALE; heat = self.heat()
        n, lab, st, _ = cv2.connectedComponentsWithStats((heat > self.thr).astype(np.uint8), connectivity=8)
        if n < 2: return self.best
        reg = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])); ys, xs = np.nonzero(reg); x0, x1 = xs.min(), xs.max(); bw = self.band // s
        t = []
        for lo, hi in ((x0, x0 + bw), (x1 - bw, x1)):
            band = heat * reg; band[:, :lo] = 0; band[:, hi + 1:] = 0
            sel = band >= self.frac * band.max(); yy, xx = np.nonzero(sel); w = band[sel]
            # x: outer edge of the dense spot (its heat-weighted mean pushed to the region edge on that side); y: weighted mean
            cx, cy = (xx * w).sum() / w.sum(), (yy * w).sum() / w.sum()
            t.append([cx, cy])
        t = np.array(t) * s + (s - 1) / 2
        if self.best is None: self.best = t; return self.mirrored()
        for k, outward in ((0, t[0, 0] < self.best[0, 0]), (1, t[1, 0] > self.best[1, 0])):
            if not outward: self.pending[k] = None; continue
            if abs(t[k, 0] - self.best[k, 0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            elif self.pending[k] is not None and abs(t[k, 0] - self.pending[k][0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            else: self.pending[k] = t[k]
        return self.mirrored()


class DenseTipFree(DenseTip):
    """Same, but the estimate follows the current dense spot (no 'outward only' rule, no confirmation)."""
    def update(self):
        s = self.SCALE; heat = self.heat()
        n, lab, st, _ = cv2.connectedComponentsWithStats((heat > self.thr).astype(np.uint8), connectivity=8)
        if n < 2: return self.best
        reg = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])); ys, xs = np.nonzero(reg); x0, x1 = xs.min(), xs.max(); bw = self.band // s
        t = []
        for lo, hi in ((x0, x0 + bw), (x1 - bw, x1)):
            band = heat * reg; band[:, :lo] = 0; band[:, hi + 1:] = 0
            sel = band >= self.frac * band.max(); yy, xx = np.nonzero(sel); w = band[sel]
            t.append([(xx * w).sum() / w.sum(), (yy * w).sum() / w.sum()])
        self.best = np.array(t) * s + (s - 1) / 2
        return self.mirrored()


print('\n-- dense-spot tips')
for name, mk in {
    'dense band 200 px, frac 0.5': lambda fm, dt, cl: DenseTip(fm, dt, centre=cl, band=200, frac=0.5),
    'dense band 300 px, frac 0.5': lambda fm, dt, cl: DenseTip(fm, dt, centre=cl, band=300, frac=0.5),
    'dense band 300 px, frac 0.3': lambda fm, dt, cl: DenseTip(fm, dt, centre=cl, band=300, frac=0.3),
    'dense band 300 px, frac 0.5, free (follows)': lambda fm, dt, cl: DenseTipFree(fm, dt, centre=cl, band=300, frac=0.5),
    'dense band 400 px, frac 0.5, free': lambda fm, dt, cl: DenseTipFree(fm, dt, centre=cl, band=400, frac=0.5),
}.items():
    print('==', name)
    for m in (1, 2, 3):
        o = run(m, mk); print(f'  m{m}: ' + '  '.join(f'{k}s: L{v[0]} R{v[1]}' if k != 'end' else f'end: L{v[0]} R{v[1]}' for k, v in o.items()))


class YGuard(LiveGoals):
    """Baseline tips, but an outward move is accepted only if the tip's y changes by ≤ dy_max px: a corner kick pulls
    the tip to the corner flag (a jump in y towards a touchline), a better view of the goal mouth moves it mostly in x."""
    def __init__(self, *a, dy_max=60, **k): super().__init__(*a, **k); self.dy_max = dy_max

    def update(self):
        s = self.SCALE
        n, lab, st, _ = cv2.connectedComponentsWithStats((self.heat() > self.thr).astype(np.uint8), connectivity=8)
        if n < 2: return self.best
        ys, xs = np.nonzero(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
        l, r = xs <= xs.min() + 40 // s, xs >= xs.max() - 40 // s
        t = np.array([[xs[l].mean(), ys[l].mean()], [xs[r].mean(), ys[r].mean()]]) * s + (s - 1) / 2
        if self.best is None: self.best = t; return self.mirrored()
        for k, outward in ((0, t[0, 0] < self.best[0, 0]), (1, t[1, 0] > self.best[1, 0])):
            if not outward or abs(t[k, 1] - self.best[k, 1]) > self.dy_max: self.pending[k] = None; continue
            if abs(t[k, 0] - self.best[k, 0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            elif self.pending[k] is not None and abs(t[k, 0] - self.pending[k][0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            else: self.pending[k] = t[k]
        return self.mirrored()


print('\n-- y-guard on outward moves')
for name, mk in {'y-guard 60 px': lambda fm, dt, cl: YGuard(fm, dt, centre=cl, dy_max=60),
                 'y-guard 100 px': lambda fm, dt, cl: YGuard(fm, dt, centre=cl, dy_max=100),
                 'y-guard 40 px': lambda fm, dt, cl: YGuard(fm, dt, centre=cl, dy_max=40)}.items():
    print('==', name)
    for m in (1, 2, 3):
        o = run(m, mk); print(f'  m{m}: ' + '  '.join(f'{k}s: L{v[0]} R{v[1]}' if k != 'end' else f'end: L{v[0]} R{v[1]}' for k, v in o.items()))
