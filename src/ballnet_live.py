"""FolloNet-B in the live simulator (switch: BALL_NET=NAME for live_sim.py; without it the YOLO ball model runs as before).

Same ROI the live pipeline already chooses (320×320 source pixels around the tracker's prediction or a search spot),
frames t-2, t-1, t of that ROI at native resolution, and — for models trained with it — the prior: a Gaussian at the
ROI's target (the prediction). Output: up to 3 peaks per ROI as (x, y, score) in frame pixels.
"""
import os, sys
import numpy as np, torch, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(__file__))
from ballnet import BallNet, channels, gauss, PRIOR_SIGMA, STRIDE

class BallNetLive:
    def __init__(self, name, dev):
        ck = torch.load(f'work/ballnet/{name}/best.pt', map_location='cpu')
        self.inputs = ck['inputs']
        if 'bg' in self.inputs:
            raise SystemExit(f'{name} needs the background channel; the live simulator feeds only frames and the prior')
        self.model = BallNet(channels(self.inputs)); self.model.load_state_dict(ck['model']); self.model.eval().to(dev)
        self.dev, self.name = dev, name

    @torch.no_grad()
    def detect(self, ring, x0, y0, S, target):
        frames = list(ring)[-3:] if 'f3' in self.inputs else list(ring)[-1:]
        while len(frames) < (3 if 'f3' in self.inputs else 1): frames.insert(0, frames[0])
        x = np.concatenate([fr[y0:y0 + S, x0:x0 + S].astype(np.float32) / 255 for fr in frames], axis=2)
        if 'prior' in self.inputs:
            x = np.concatenate([x, gauss(S, S, target[0] - x0, target[1] - y0, PRIOR_SIGMA)[:, :, None]], axis=2)
        t = torch.from_numpy(x.transpose(2, 0, 1).copy())[None].to(self.dev)
        h, o = self.model(t)
        p = torch.sigmoid(h)[0, 0]
        peak = (p == F.max_pool2d(p[None, None], 3, 1, 1)[0, 0]) & (p >= 0.1)
        ys, xs = torch.nonzero(peak, as_tuple=True)
        sc = p[ys, xs]
        order = torch.argsort(sc, descending=True)[:3]
        out = []
        for i in order.tolist():
            yy, xx = int(ys[i]), int(xs[i])
            ox, oy = float(o[0, 0, yy, xx]), float(o[0, 1, yy, xx])
            out.append(((xx + ox) * STRIDE + x0, (yy + oy) * STRIDE + y0, float(sc[i])))
        return out
