"""Compare the Swift pre-game environment (follosim env → swift_env.json, swift_fm.png) with Python's (live_sim.py --dump).
Usage: python src/compare_env.py work/m2/live"""
import json, sys, numpy as np, cv2
d = sys.argv[1]
p, s = json.load(open(f'{d}/env.json')), json.load(open(f'{d}/swift_env.json'))
for k in ('fm', 'fmd'):
    a, b = cv2.imread(f'{d}/{k}.png', 0) > 127, cv2.imread(f'{d}/swift_{k}.png', 0) > 127
    print(f'{k}: IoU {(a & b).sum() / (a | b).sum():.4f}  python share {a.mean():.3f} swift {b.mean():.3f}')
for k in ('top', 'bot'):
    dm = np.abs(np.array(p[k]) - np.array(s[k])); print(f'{k}: max |diff| {dm.max():.0f} px, mean {dm.mean():.2f}, columns > 2 px: {(dm > 2).sum()}')
print('halfway line x at top/bottom: python', [round(p['cline'][k]) for k in ('x0', 'x1')], 'swift', [round(s['cline'][k]) for k in ('x0', 'x1')])
