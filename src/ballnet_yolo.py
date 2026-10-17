"""Baseline for the FolloNet-B probe: today's ball model (models/ball_v02.pt, YOLO fine-tuned, AGPL, Mac only) on exactly
the same crops, as the live pipeline runs it: frame t, upscaled 2× (live_sim.py: ROI 320 → 640), best box by confidence.
Same metrics as ballnet.py (recall within 4 px, false alarms on ball-less crops) at the live thresholds 0.4 and 0.25.
Usage: python src/ballnet_yolo.py [--on m1,m2,m3]  → work/ballnet/yolo/eval.json
"""
import cv2, json, math, os, sys
import numpy as np
from ultralytics import YOLO
sys.path.insert(0, os.path.dirname(__file__))
from ballnet import Samples, score, opt

model = YOLO('models/ball_v02.pt')
os.makedirs('work/ballnet/yolo', exist_ok=True)
res = {}
for m in opt('--on', 'm1,m2,m3').split(','):
    for split in ('val', None):
        ds = Samples([m], split, ['f1'], False)
        rows = []
        for f in ds.files:
            z = np.load(f)
            img = cv2.imdecode(z['f2'], cv2.IMREAD_COLOR)
            r = model.predict(cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC), imgsz=img.shape[0] * 2, conf=0.05, device='cpu', verbose=False)[0]
            b = z['ball']; has = b[0] >= 0
            if len(r.boxes):
                i = int(r.boxes.conf.argmax()); x0, y0, x1, y1 = r.boxes.xyxy[i].tolist(); sc = float(r.boxes.conf[i])
                px, py = (x0 + x1) / 4, (y0 + y1) / 4
            else:
                sc, px, py = 0.0, -1e9, -1e9
            err = math.hypot(px - b[0], py - b[1]) if has else 1e9
            rows.append((bool(has), int(z['interp']), str(z['kind']), sc, err))
        for thr in (0.4, 0.25):
            r = score(rows, thr=thr)
            res[f'{m}_{split or "all"}_thr{thr}'] = r
            print('yolo', m, split or 'all', thr, json.dumps({k: round(v, 3) if isinstance(v, float) else v for k, v in r.items()}), flush=True)
json.dump(res, open('work/ballnet/yolo/eval.json', 'w'), indent=1)
