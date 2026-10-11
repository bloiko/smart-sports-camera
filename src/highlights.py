"""Автоматичні хайлайти (F13): кліпи з моментів біля воріт з готового відео follow.py.

Момент = епізод режиму воріт (м'яч біля воріт або атака: у зоні воріт більше гравців, ніж зазвичай).
Кліп охоплює небезпечну частину епізоду: від першого моменту небезпеки − 8 с до останнього + 4 с,
не довше 20 с (якщо довше — від початку: атака важливіша за святкування). Момент небезпеки: м'яч ближче
за 0.1 відстані між воротами або гравців у зоні ≥ 80% від максимуму епізоду. Небезпека (0–1) = середнє:
  м'яч: 1 − (мін. відстань м'яча до воріт) / 0.15 відстані між воротами (0, якщо м'яча не видно);
  гравці: (гравців у зоні понад звичайне) / 10.

Використання: python src/highlights.py FINAL_DIR OUT_DIR [--checklist CHECKLIST.json] [--top N] [--min-score S]
  FINAL_DIR — тека follow.py (camera_path.npz, out_follow.mp4).
  → OUT_DIR/clip_01_2m50s.mp4 ..., OUT_DIR/highlights.mp4 (усі кліпи підряд), OUT_DIR/highlights.json
"""
import json, os, subprocess, sys, numpy as np

BEFORE, AFTER, MAX_LEN, MIN_EP = 8.0, 4.0, 20.0, 2.5      # секунди


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def tsec(t):
    m, s = t.split(':'); return int(m) * 60 + float(s)


def moments(p):
    fps = float(p['FPS']); GON, GI = p['GON'], p['GI']; BX, BY = p['BX'], p['BY']
    G, D = p['GOALS'], float(p['GOAL_DIST']); SF, ZN, ZB = p['S_FRAMES'], p['ZN'], p['ZONE_BASE']
    n = len(GON); ch = np.flatnonzero(np.diff(np.r_[0, GON.astype(int), 0])); out = []
    for a, b in zip(ch[::2], ch[1::2]):
        if (b - a) / fps < MIN_EP: continue
        g = GI[a:b]; g = int(np.bincount(g[g >= 0]).argmax()) if (g >= 0).any() else 0
        fr = np.arange(a, b); seen = ~np.isnan(BX[fr])
        d = np.hypot(BX[fr] - G[g][0], BY[fr] - G[g][1]) / D
        si = np.flatnonzero((SF >= a) & (SF < b)); extra = ZN[si, g] - ZB[g] if len(si) else np.zeros(1)
        ball = float(np.clip(1 - np.nanmin(d) / 0.15, 0, 1)) if seen.any() else 0.0
        players = float(np.clip(extra.max() / 10, 0, 1))
        hot = list(fr[np.nan_to_num(d, nan=9) < 0.1])                                  # м'яч біля воріт
        if len(si) and extra.max() > 0: hot += list(SF[si[extra >= 0.8 * extra.max()]])  # багато гравців
        first, last = (min(hot), max(hot)) if hot else ((a + b) // 2, (a + b) // 2)
        peak = int(first)
        t0 = max(a / fps - 3, first / fps - BEFORE); t1 = min(b / fps + 2, last / fps + AFTER, n / fps)
        t1 = min(t1, t0 + MAX_LEN)
        out.append(dict(start=round(t0, 1), end=round(t1, 1), peak=round(peak / fps, 1), goal=['left', 'right'][g],
                        score=round((ball + players) / 2, 2), ball=round(ball, 2), players=round(players, 2)))
    return out


def main():
    final, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):                         # кліпи попереднього запуску
        if f.startswith('clip_') and f.endswith('.mp4'): os.remove(os.path.join(out, f))
    ms = moments(np.load(os.path.join(final, 'camera_path.npz')))
    ms = [m for m in ms if m['score'] >= float(arg('--min-score', 0))]
    if arg('--top'): ms = sorted(sorted(ms, key=lambda m: -m['score'])[:int(arg('--top'))], key=lambda m: m['start'])
    video = os.path.join(final, 'out_follow.mp4'); files = []
    for k, m in enumerate(ms, 1):
        name = f"clip_{k:02d}_{int(m['peak'] // 60)}m{int(m['peak'] % 60):02d}s.mp4"; m['file'] = name
        if os.path.exists(video):
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(m['start']), '-i', video, '-t', str(m['end'] - m['start']),
                            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-c:a', 'aac', os.path.join(out, name)], check=True)
            files.append(name)
    if files:
        with open(os.path.join(out, 'list.txt'), 'w') as f:
            for name in files: f.write(f"file '{name}'\n")
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', os.path.join(out, 'list.txt'), '-c', 'copy',
                        os.path.join(out, 'highlights.mp4')], check=True)
    total = sum(m['end'] - m['start'] for m in ms)
    for m in ms: print(f"{m['start']:6.1f}-{m['end']:6.1f}s  {m['goal']:5}  danger {m['score']:.2f} (ball {m['ball']:.2f}, players {m['players']:.2f})")
    print(f'{len(ms)} clips, {total:.0f} s in total')
    report = dict(clips=ms, total_s=round(total, 1))
    if arg('--checklist'):
        ev = json.load(open(arg('--checklist')))['events']; miss = 0
        for e in ev:
            hit = [m['file'] if 'file' in m else m['start'] for m in ms if m['start'] <= tsec(e['time']) <= m['end']]
            miss += not hit; print(f"checklist {e['time']} {e['goal']} {e['type']}: {'in ' + str(hit[0]) if hit else 'MISSING'}")
        report['checklist_missing'] = miss
    json.dump(report, open(os.path.join(out, 'highlights.json'), 'w'), indent=2)


if __name__ == '__main__':
    main()
