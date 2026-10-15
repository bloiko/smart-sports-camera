"""Compare live camera paths of one match: jumps, ball in crop (offline v0.3 ball track) and the goal checklist.

Usage: python src/eval_live.py N PATH [PATH ...]
  N: match number (work/mN, specs/checklists/matchN.json); PATH: .npz (live_sim.py) or .json (follosim camera).
Jumps: share of frames whose crop centre moves > 20 px (shaky picture); ball in crop: share of frames of the
offline ball track inside the crop; checklist: goal mouth fully in frame ≥ 90% of each event window.
"""
import json, sys, numpy as np

def load(p):
    d = np.load(p) if p.endswith('.npz') else {k: np.array(v, float) for k, v in json.load(open(p)).items() if k in ('X', 'Y', 'CW', 'CH')}
    return {k: np.asarray(d[k], float) for k in ('X', 'Y', 'CW', 'CH')}

def main():
    n = sys.argv[1]; fps = 25
    tr = {int(k): v for k, v in json.load(open(f'work/m{n}/final_v03/ball_track.json')).items()}
    cl = json.load(open(f'specs/checklists/match{n}.json'))
    print(f'{"path":48} {"jumps>20px":>10} {"accel p95":>9} {"ball in crop":>12} {"zoom cw":>7}  checklist')
    for p in sys.argv[2:]:
        c = load(p); X, Y, CW, CH = c['X'], c['Y'], c['CW'], c['CH']
        d = np.abs(np.diff(X)); acc = np.abs(np.diff(X, 2))
        ins = np.mean([X[f] - CW[f] / 2 <= x <= X[f] + CW[f] / 2 and Y[f] - CH[f] / 2 <= y <= Y[f] + CH[f] / 2 for f, (x, y) in tr.items() if f < len(X)])
        res = []
        for e in cl['events']:
            m, s = e['time'].split(':'); t = int(m) * 60 + float(s)
            fr = np.arange(int((t - 2) * fps), min(int((t + 1) * fps), len(X)))
            x0, y0, x1, y1 = cl['mouths'][e['goal']]
            res.append(((X[fr] - CW[fr] / 2 <= x0) & (X[fr] + CW[fr] / 2 >= x1) & (Y[fr] - CH[fr] / 2 <= y0) & (Y[fr] + CH[fr] / 2 >= y1)).mean() >= 0.9)
        print(f'{p[-48:]:48} {(d > 20).mean() * 100:9.2f}% {np.percentile(acc, 95):9.1f} {ins * 100:11.1f}% {CW.mean():7.0f}  {sum(res)}/{len(res)} ' + ''.join('✓' if r else '✗' for r in res))

if __name__ == '__main__':
    main()
