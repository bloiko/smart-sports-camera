"""Experiment (2026-10-12): which kick-off statistic has a margin? Uses the jersey samples saved by live_highlights.py
(OUT/highlights/live_highlights.json: [frame, x_feet, a, b]) and the known kick-offs: match 1 at 195 s, match 3 at 148 s
(after the goals); match 2 has none; match 3 also starts with a kick-off without a goal (~0–10 s, excluded from "false").
For each statistic: the score at the real kick-offs vs the best false peak (≥ 20 s from any real one) → margin.
Usage: python src/exp_kickoff.py"""
import json, numpy as np, cv2

REAL = {1: [195.2], 2: [], 3: [148.2]}; START = {3: (0, 12)}   # match 3: kick-off at the start of the video, not a goal


def per_frame(F, centre_x):
    ab = F[:, 2:4].astype(np.float32)
    cv2.setRNGSeed(0)
    _, lab, cent = cv2.kmeans(ab, 2, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.2), 5, cv2.KMEANS_PP_CENTERS)
    lab = lab.ravel(); d = np.linalg.norm(ab - cent[lab], axis=1); ok = d < np.percentile(d, 85)
    frames = np.unique(F[:, 0]); rows = []
    for fr in frames:
        s = (F[:, 0] == fr) & ok; x, L = F[s, 1], lab[s]; a, b = x[L == 0], x[L == 1]
        if len(a) < 4 or len(b) < 4: rows.append((fr, np.nan, np.nan, np.nan, np.nan, len(a) + len(b))); continue
        o1 = (np.mean(a < centre_x), np.mean(b > centre_x)); o2 = (np.mean(a > centre_x), np.mean(b < centre_x))
        best = o1 if sum(o1) >= sum(o2) else o2
        near = np.mean(np.abs(x - centre_x) < 250)        # share of players near the halfway line
        rows.append((fr, best[0], best[1], near, np.mean(np.abs(x - centre_x)), len(x)))
    return np.array(rows, float)


def smooth(T, v, win_s, how='mean'):
    out = np.full(len(v), np.nan)
    for i, t in enumerate(T):
        s = (T >= t - win_s / 2) & (T <= t + win_s / 2); w = v[s]; w = w[~np.isnan(w)]
        if len(w): out[i] = w.mean() if how == 'mean' else (w.min() if how == 'min' else np.median(w))
    return out


def peaks(T, S, real, start, gap=20):
    r = [S[np.abs(T - t) <= 3].max() for t in real]
    mask = np.ones(len(T), bool)
    for t in real: mask &= np.abs(T - t) > gap
    if start: mask &= ~((T >= start[0]) & (T <= start[1]))
    return r, float(np.nanmax(S[mask]))


def main():
    stats = {}
    for m in (1, 2, 3):
        rep = json.load(open(f'work/m{m}/live_pre/highlights/live_highlights.json'))
        p = np.load(f'work/m{m}/live_pre/live_B2.npz'); cx = (p['GOALS'][0][0] + p['GOALS'][1][0]) / 2; fps = float(p['FPS'])
        R = per_frame(np.array(rep['jerseys'], float), cx); T = R[:, 0] / fps
        A, B, near = R[:, 1], R[:, 2], R[:, 3]
        cands = {
            'current: mean of (A+B)/2 over 2 s': smooth(T, (A + B) / 2, 2),
            'min(A,B) mean over 2 s': smooth(T, np.minimum(A, B), 2),
            '(A+B)/2 mean over 1 s': smooth(T, (A + B) / 2, 1),
            '(A+B)/2 median over 3 s': smooth(T, (A + B) / 2, 3, 'median'),
            '(A+B)/2 mean 2 s × (1 − share near line)': smooth(T, (A + B) / 2 * (1 - near), 2),
            'min(A,B) mean 2 s, frames with ≥ 14 players': smooth(T, np.where(R[:, 5] >= 14, np.minimum(A, B), np.nan), 2),
            '(A+B)/2 mean over 4 s': smooth(T, (A + B) / 2, 4),
            'A·B mean over 2 s': smooth(T, A * B, 2),
        }
        for k, S in cands.items():
            r, f = peaks(T, S, REAL[m], START.get(m)); stats.setdefault(k, []).append((m, r, f))
    print(f'{"statistic":48s} ' + ' '.join(f'm{m}: real / false' for m in (1, 2, 3)) + '   margin')
    for k, rows in stats.items():
        real = [v for _, r, _ in rows for v in r]; false = [f for _, _, f in rows]
        print(f'{k:48s} ' + ' '.join(f'{",".join(f"{v:.2f}" for v in r) or "-":10s}/ {f:.2f}  ' for _, r, f in rows) + f' {min(real) - max(false):+.3f}')


if __name__ == '__main__':
    main()


# ---- stillness: at a kick-off everybody stands still for a few seconds; during play the cloud always moves
def stillness(m, fps=25.0):
    """Median displacement (px per player frame) of on-field players between consecutive player frames (nearest match)."""
    det = [json.loads(l) for l in open(f'work/m{m}/live_pre/live_det.jsonl')]
    fmd = cv2.imread(f'work/m{m}/live_pre/fmd.png', 0) > 127; H, W = fmd.shape
    prev = None; T, D = [], []
    for r in det:
        if 'persons' not in r: continue
        pl = np.array([((b[0] + b[2]) / 2, b[3]) for b in r['persons'] if b[4] >= 0.25 and 12 <= b[3] - b[1] <= 260 and fmd[min(int(b[3]), H - 1), min(int((b[0] + b[2]) / 2), W - 1)]])
        if prev is not None and len(pl) >= 6 and len(prev) >= 6:
            d = np.linalg.norm(pl[:, None] - prev[None], axis=2).min(1); T.append(r['frame'] / fps); D.append(np.median(d))
        prev = pl
    return np.array(T), np.array(D)


def main2():
    print('\n-- with stillness (median player displacement per player frame, 0.16 s)')
    stats = {}
    for m in (1, 2, 3):
        rep = json.load(open(f'work/m{m}/live_pre/highlights/live_highlights.json'))
        p = np.load(f'work/m{m}/live_pre/live_B2.npz'); cx = (p['GOALS'][0][0] + p['GOALS'][1][0]) / 2; fps = float(p['FPS'])
        R = per_frame(np.array(rep['jerseys'], float), cx); T = R[:, 0] / fps; A, B = R[:, 1], R[:, 2]
        Ts, Ds = stillness(m); still = np.interp(T, Ts, Ds)
        sep2 = smooth(T, (A + B) / 2, 2)
        for name, S in {'stillness only (−median disp, 2 s)': -smooth(T, still, 2),
                        'sep 2 s − 0.03·disp': sep2 - 0.03 * smooth(T, still, 2),
                        'sep 2 s − 0.05·disp': sep2 - 0.05 * smooth(T, still, 2),
                        'sep 2 s · exp(−disp/6)': sep2 * np.exp(-smooth(T, still, 2) / 6),
                        'sep 2 s · exp(−disp/4)': sep2 * np.exp(-smooth(T, still, 2) / 4),
                        'sep 2 s · (disp 4 s < 5)': sep2 * (smooth(T, still, 4) < 5)}.items():
            r, f = peaks(T, S, REAL[m], START.get(m)); stats.setdefault(name, []).append((m, r, f))
        if m in (1, 3): print(f'  m{m} displacement at kick-off {np.interp(REAL[m][0], Ts, Ds):.1f} px, median over match {np.median(Ds):.1f}, 10th pct {np.percentile(Ds, 10):.1f}')
    for k, rows in stats.items():
        real = [v for _, r, _ in rows for v in r]; false = [f for _, _, f in rows]
        print(f'{k:48s} ' + ' '.join(f'{",".join(f"{v:.2f}" for v in r) or "-":10s}/ {f:.2f}  ' for _, r, f in rows) + f' {min(real) - max(false):+.3f}')


if __name__ == '__main__':
    main2()
