"""Goal checklist: чи був «рот» воріт у кадрі навколо кожного гола/удару зі списку.
Використання: python src/check_goals.py OUT_DIR/camera_path.npz specs/checklists/match1.json [fps]
Вікно перевірки: від 2 с до події до 1 с після. PASS, якщо ворота повністю в кадрі ≥ 90% кадрів вікна.
"""
import json, sys, numpy as np
p = np.load(sys.argv[1]); X, Y, CW, CH = p['X'], p['Y'], p['CW'], p['CH']
cl = json.load(open(sys.argv[2])); fps = float(sys.argv[3]) if len(sys.argv) > 3 else 25
ok_all = True
for e in cl['events']:
    m, s = e['time'].split(':'); t = int(m) * 60 + float(s)
    fr = np.arange(int((t - 2) * fps), min(int((t + 1) * fps), len(X)))
    x0, y0, x1, y1 = cl['mouths'][e['goal']]
    inside = (X[fr] - CW[fr] / 2 <= x0) & (X[fr] + CW[fr] / 2 >= x1) & (Y[fr] - CH[fr] / 2 <= y0) & (Y[fr] + CH[fr] / 2 >= y1)
    centre = (np.abs(X[fr] - (x0 + x1) / 2) <= CW[fr] / 2) & (np.abs(Y[fr] - (y0 + y1) / 2) <= CH[fr] / 2)
    ok = inside.mean() >= 0.9; ok_all &= ok
    print(f"{e['time']:>7} {e['goal']:5} {e['type']:5} mouth in frame {inside.mean():5.0%}  centre {centre.mean():5.0%}  {'PASS' if ok else 'FAIL'}")
print('ALL PASS' if ok_all else 'SOME FAIL')
