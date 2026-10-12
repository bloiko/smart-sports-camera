"""Evaluate a Swift camera path (follosim camera … → swift_B{B}.json or swiftdet_B{B}.json) like live_sim.py does:
goal checklist, ball of the offline track in crop, players in crop, pan statistics.
Usage: python src/eval_swift_path.py DIR B VIDEO --ref FINAL_DIR --checklist C.json [--swift]
  --swift: the path made from Swift detections (swiftdet_B{B}.json) instead of Python's (swift_B{B}.json)."""
import json, os, subprocess, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live_sim import metrics, arg, ROOT

d, B, video = sys.argv[1], float(sys.argv[2]), sys.argv[3]
name = f'{d}/' + ('swiftdet' if '--swift' in sys.argv else 'swift') + f'_B{B:g}.json'
s = json.load(open(name)); nan = lambda a: np.array([np.nan if v is None else v for v in a], float)
path = dict(X=np.array(s['X']), Y=np.array(s['Y']), CW=np.array(s['CW']), CH=np.array(s['CH']), FPS=25.0, GON=np.array(s['GON']), GI=np.array(s['GI']), BX=nan(s['BX']), BY=nan(s['BY']), GOALS=np.array(s['GOALS']))
npz = name.replace('.json', '.npz'); np.savez(npz, **path)
m = metrics(path, arg('--ref'), video); ck = ''
if arg('--checklist'):
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'src', 'check_goals.py'), npz, arg('--checklist')], capture_output=True, text=True).stdout
    ck = f"checklist {r.count('PASS') - r.count('ALL PASS')}/{r.count('PASS') - r.count('ALL PASS') + r.count('FAIL') - r.count('SOME FAIL')}"
print(f'{os.path.basename(name):22s} ' + ' '.join(f'{k} {v}' for k, v in m.items()) + f' {ck}')
