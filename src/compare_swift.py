"""Compare the Swift camera path (follosim camera → swift_B{B}.json) with the Python one (live_sim.py → live_B{B}.npz).
Usage: python src/compare_swift.py work/m2/live 2  → max differences per array and the first frames that differ."""
import json, sys, numpy as np

d, B = sys.argv[1], float(sys.argv[2])
p = np.load(f'{d}/live_B{B:g}.npz'); s = json.load(open(f'{d}/swift_B{B:g}.json'))
n = min(len(p['X']), len(s['X'])); print(f'frames python {len(p["X"])} swift {len(s["X"])}')
ok = True
for k in ('X', 'Y', 'CW', 'CH'):
    a, b = p[k][:n], np.array(s[k][:n], float); dm = np.abs(a - b)
    i = int(np.argmax(dm)); print(f'{k:3} max |diff| {dm.max():.4f} px at frame {i} (python {a[i]:.2f}, swift {b[i]:.2f}); frames with |diff| > 0.5 px: {(dm > 0.5).sum()}')
    ok &= dm.max() < 0.5
for k in ('GON', 'GI'):
    a, b = p[k][:n], np.array(s[k][:n]); bad = np.flatnonzero(a != b)
    print(f'{k:3} mismatches {len(bad)}' + (f' first at {bad[:5].tolist()}' if len(bad) else '')); ok &= len(bad) == 0
bx = np.array([np.nan if v is None else v for v in s['BX'][:n]]); both = ~np.isnan(p['BX'][:n]) & ~np.isnan(bx)
print(f'ball frames python {(~np.isnan(p["BX"][:n])).sum()} swift {(~np.isnan(bx)).sum()} both {both.sum()} max |diff| {np.nanmax(np.abs(p["BX"][:n][both] - bx[both])) if both.any() else 0}')
print('goals python', np.round(p['GOALS']).tolist(), 'swift', [[round(v) for v in g] for g in s['GOALS']])
print('SAME PATH' if ok else 'DIFFERENT')
