"""FolloNet-B probe: our own ball network, written and trained from scratch (no third-party model code or weights).

Input (channels switchable for the ablation, `--inputs`):
  f3    frames t-2, t-1, t (9 ch)        f1  frame t only (3 ch)
  bg    background crop from the median frame (3 ch): logos, lines and spare balls vanish in "frame − background"
  prior the tracker's guess as a Gaussian blob (1 ch), simulated at training time from the true ball or a decoy
Output: ball heatmap at stride 2 (CenterNet-style focal loss) + sub-pixel offset. ReLU, BatchNorm, 3×3 convs,
nearest upsampling: all Neural Engine friendly. Fully convolutional: trains on 256 crops, runs on the 320 live ROI.

Usage:
  python src/ballnet.py train NAME --inputs f3,bg,prior --train m1,m2 [--epochs 40] [--batch 32]
  python src/ballnet.py eval NAME [--on m1,m2,m3]
Checkpoints in work/ballnet/NAME/{last,best}.pt (resumable: rerun the same command), metrics in log.jsonl.
"""
import cv2, glob, json, math, numpy as np, os, random, sys, time
import torch, torch.nn as nn, torch.nn.functional as F

DS, OUT_ROOT = 'work/ballds', 'work/ballnet'
if '--ds' in sys.argv: DS = sys.argv[sys.argv.index('--ds') + 1]           # e.g. work/ballds_v3 (fast-pass positives)
STRIDE, SIGMA_OUT, PRIOR_SIGMA = 2, 1.5, 10.0

def opt(k, d):
    return sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d

# ---------------------------------------------------------------- data

def channels(inputs):
    return (9 if 'f3' in inputs else 3) + (3 if 'bg' in inputs else 0) + (1 if 'prior' in inputs else 0)

def gauss(h, w, x, y, s):
    yy, xx = np.mgrid[0:h, 0:w]
    return np.exp(-((xx - x) ** 2 + (yy - y) ** 2) / (2 * s * s)).astype(np.float32)

class Samples(torch.utils.data.Dataset):
    def __init__(self, matches, split, inputs, train):
        self.files = sorted(f for m in matches for f in glob.glob(f'{DS}/{m}/*.npz'))
        self.files = [f for f in self.files if (split is None) or self._split(f) == split]
        self.inputs, self.train = inputs, train
        self.synth = train and '--synth' in sys.argv
        self.sprites = self._sprites() if self.synth else []

    def _sprites(self, n=600):
        """Real balls cut from track (not interpolated) training crops: 14×14 patches for synthetic fast passes."""
        out = []
        for f in random.Random(0).sample(self.files, len(self.files)):
            z = np.load(f)
            if z['ball'][0] < 0 or int(z['interp']): continue
            img = cv2.imdecode(z['f2'], cv2.IMREAD_COLOR); bx, by = int(z['ball'][0]), int(z['ball'][1])
            if not (6 <= bx < img.shape[1] - 6 and 6 <= by < img.shape[0] - 6): continue
            spr = img[by - 6:by + 6, bx - 6:bx + 6].astype(np.float32)
            lum = spr.mean(2); border = np.concatenate([lum[0], lum[-1], lum[:, 0], lum[:, -1]])
            alpha = np.clip((lum - np.median(border) - 10) / 40, 0, 1)        # only the ball: brighter than the grass
            if alpha.sum() >= 5: out.append(np.dstack([spr, alpha]))
            if len(out) >= n: break
        print(f'synthetic fast passes: {len(out)} ball sprites', flush=True)
        return out

    def _paste(self, frames, rng):
        """A real ball flying across the 3 frames at up to 15 px per frame, blurred along its motion (2026-10-18: the
        network lost a fast far pass at m2 0:10; the labels had almost no fast passes). Returns the ball in frame t."""
        S = frames[0].shape[0]; sa = self.sprites[rng.randrange(len(self.sprites))]
        k = rng.uniform(0.8, 1.3); size = max(6, int(12 * k)); sa = cv2.resize(sa, (size, size), interpolation=cv2.INTER_LINEAR)
        spr, mask = sa[:, :, :3], sa[:, :, 3]
        sp = rng.uniform(3, 15); ang = rng.uniform(0, 2 * math.pi); v = np.array([math.cos(ang), math.sin(ang)]) * sp
        grass = lambda p: (lambda c: c[1] > c[2] + 8 and c[1] > c[0] + 8)(frames[2][int(p[1]), int(p[0])].astype(int))   # BGR
        for _ in range(12):                                                      # the pass runs on the grass
            end = np.array([rng.uniform(24, S - 24), rng.uniform(24, S - 24)]); starts = [end - v * (2 - i) for i in range(3)]
            if all(0 <= q[0] < S and 0 <= q[1] < S and grass(q) for q in starts): break
        else:
            return None
        L = max(1, int(round(sp)))
        kern = np.zeros((L * 2 + 1, L * 2 + 1), np.float32); cv2.line(kern, (L - int(v[0] / 2), L - int(v[1] / 2)), (L + int(v[0] / 2), L + int(v[1] / 2)), 1, 1); kern /= kern.sum()
        for fr, p in zip(frames, starts):
            x0, y0 = int(p[0] - size / 2), int(p[1] - size / 2)
            if x0 < 0 or y0 < 0 or x0 + size > S or y0 + size > S: return None
            layer = np.zeros_like(fr, dtype=np.float32); alpha = np.zeros(fr.shape[:2], np.float32)
            layer[y0:y0 + size, x0:x0 + size] = spr; alpha[y0:y0 + size, x0:x0 + size] = mask
            layer = cv2.filter2D(layer, -1, kern); alpha = cv2.filter2D(alpha, -1, kern)[:, :, None]
            fr[:] = np.clip(fr.astype(np.float32) * (1 - alpha) + layer * alpha, 0, 255).astype(np.uint8)
        return end

    @staticmethod
    def _split(f):
        return str(np.load(f)['split'])

    def __len__(self):
        return len(self.files)

    def __getitem__(self, i):
        z = np.load(self.files[i])
        rng = random.Random() if self.train else random.Random(i)              # val: the same prior every epoch
        dec = lambda k: cv2.imdecode(z[k], cv2.IMREAD_COLOR)
        frames = [dec('f0'), dec('f1'), dec('f2')] if 'f3' in self.inputs else [dec('f2')]
        ball = z['ball'].astype(np.float32); has = ball[0] >= 0; decoy = z['decoy'].astype(np.float32)
        if self.synth and not has and len(frames) == 3 and rng.random() < 0.4:   # ball-less crop → a synthetic fast pass
            e = self._paste(frames, rng)
            if e is not None: ball = e.astype(np.float32); has = True
        imgs = frames + ([dec('bg')] if 'bg' in self.inputs else [])
        S = imgs[0].shape[0]
        x = np.concatenate([im.astype(np.float32) / 255 for im in imgs], axis=2)            # H W C (BGR)
        if self.train:
            if rng.random() < 0.5:                                                          # horizontal flip
                x = x[:, ::-1].copy(); ball[0] = S - 1 - ball[0] if has else ball[0]; decoy[0] = S - 1 - decoy[0]
            g = rng.uniform(0.7, 1.3); b = rng.uniform(-0.12, 0.12)                          # light, same for all inputs
            x = np.clip(x * g + b, 0, 1)
            x += np.random.normal(0, rng.uniform(0, 0.03), x.shape).astype(np.float32)
        if 'prior' in self.inputs:
            r = rng.random(); kind = str(z['kind'])
            if has and r < 0.6:   p = gauss(S, S, ball[0] + rng.gauss(0, 6), ball[1] + rng.gauss(0, 6), PRIOR_SIGMA)
            elif has and r < 0.75: p = gauss(S, S, rng.uniform(0, S), rng.uniform(0, S), PRIOR_SIGMA)          # wrong guess
            elif not has and r < 0.5: p = gauss(S, S, decoy[0] + rng.gauss(0, 6), decoy[1] + rng.gauss(0, 6), PRIOR_SIGMA)  # fooled tracker
            else: p = np.zeros((S, S), np.float32)
            x = np.concatenate([x, p[:, :, None]], axis=2)
        Ho = S // STRIDE
        hm = gauss(Ho, Ho, ball[0] / STRIDE, ball[1] / STRIDE, SIGMA_OUT) if has else np.zeros((Ho, Ho), np.float32)
        cx, cy = (int(ball[0] / STRIDE), int(ball[1] / STRIDE)) if has else (0, 0)
        if has: hm[cy, cx] = 1.0
        off = np.array([ball[0] / STRIDE - cx, ball[1] / STRIDE - cy], np.float32) if has else np.zeros(2, np.float32)
        meta = dict(has=float(has), bx=float(ball[0]), by=float(ball[1]), cx=cx, cy=cy, interp=int(z['interp']), kind=str(z['kind']))
        return torch.from_numpy(x.transpose(2, 0, 1).copy()), torch.from_numpy(hm[None]), torch.from_numpy(off), meta

# ---------------------------------------------------------------- model

def cbr(i, o, s=1, d=1):
    return nn.Sequential(nn.Conv2d(i, o, 3, s, padding=d, dilation=d, bias=False), nn.BatchNorm2d(o), nn.ReLU(inplace=True))

class BallNet(nn.Module):
    """~0.4M params. Full-res stem (no early downsampling: a 5 px ball must survive), encoder to stride 8 with dilated
    context, decoder back to stride 2 with skips."""
    def __init__(self, cin):
        super().__init__()
        self.stem = nn.Sequential(cbr(cin, 24), cbr(24, 24))
        self.d2 = nn.Sequential(cbr(24, 32, 2), cbr(32, 32))
        self.d4 = nn.Sequential(cbr(32, 64, 2), cbr(64, 64))
        self.d8 = nn.Sequential(cbr(64, 96, 2), cbr(96, 96), cbr(96, 96, d=2), cbr(96, 96, d=4))
        self.u4 = cbr(96 + 64, 64)
        self.u2 = cbr(64 + 32, 32)
        self.hm = nn.Conv2d(32, 1, 1); self.off = nn.Conv2d(32, 2, 1)
        nn.init.constant_(self.hm.bias, -4.6)                                  # start at p≈0.01 (CenterNet)

    def forward(self, x):
        s0 = self.stem(x); s2 = self.d2(s0); s4 = self.d4(s2); s8 = self.d8(s4)
        u4 = self.u4(torch.cat([F.interpolate(s8, scale_factor=2, mode='nearest'), s4], 1))
        u2 = self.u2(torch.cat([F.interpolate(u4, scale_factor=2, mode='nearest'), s2], 1))
        return self.hm(u2), self.off(u2)

def focal(pred_logit, gt):
    p = torch.sigmoid(pred_logit).clamp(1e-4, 1 - 1e-4)
    pos = gt.eq(1).float(); neg = 1 - pos
    pl = -(torch.log(p) * (1 - p) ** 2 * pos).sum()
    nl = -(torch.log(1 - p) * p ** 2 * (1 - gt) ** 4 * neg).sum()
    return (pl + nl) / pos.sum().clamp(min=1)

# ---------------------------------------------------------------- evaluation

def peaks(hm_logit, off):
    """Best peak per sample: (score, x, y) in input pixels."""
    p = torch.sigmoid(hm_logit)[:, 0]
    B, H, W = p.shape
    idx = p.view(B, -1).argmax(1)
    ys, xs = (idx // W), (idx % W)
    sc = p.view(B, -1).gather(1, idx[:, None])[:, 0]
    ox = off[torch.arange(B), 0, ys, xs]; oy = off[torch.arange(B), 1, ys, xs]
    return sc, (xs.float() + ox) * STRIDE, (ys.float() + oy) * STRIDE

def score(rows, thr=0.3, tol=4.0):
    """rows: (has, interp, kind, score, err) → recall within tol px, false alarms on ball-less crops, wrong spot."""
    pos = [r for r in rows if r[0]]; neg = [r for r in rows if not r[0]]
    hit = lambda r: r[3] >= thr and r[4] <= tol
    out = dict(n_pos=len(pos), n_neg=len(neg),
               recall=sum(map(hit, pos)) / max(1, len(pos)),
               recall_interp=sum(hit(r) for r in pos if r[1]) / max(1, sum(1 for r in pos if r[1])),
               recall_track=sum(hit(r) for r in pos if not r[1]) / max(1, sum(1 for r in pos if not r[1])),
               wrong_spot=sum(1 for r in pos if r[3] >= thr and r[4] > tol) / max(1, len(pos)),
               false_alarm=sum(1 for r in neg if r[3] >= thr) / max(1, len(neg)))
    for k in ('fp', 'spare', 'player'):
        ks = [r for r in neg if r[2] == k]
        if ks: out[f'false_alarm_{k}'] = sum(1 for r in ks if r[3] >= thr) / len(ks)
    return out

@torch.no_grad()
def evaluate(model, loader, dev):
    model.eval(); rows = []
    for x, hm, off, meta in loader:
        h, o = model(x.to(dev)); sc, px, py = peaks(h.float().cpu(), o.float().cpu())
        for i in range(len(sc)):
            err = math.hypot(px[i] - meta['bx'][i], py[i] - meta['by'][i]) if meta['has'][i] else 1e9
            rows.append((bool(meta['has'][i]), int(meta['interp'][i]), meta['kind'][i], float(sc[i]), float(err)))
    model.train()
    return rows

# ---------------------------------------------------------------- train

def train(name):
    inputs = opt('--inputs', 'f3,bg,prior').split(','); matches = opt('--train', 'm1,m2').split(',')
    epochs, bs = int(opt('--epochs', 40)), int(opt('--batch', 32))
    out = f'{OUT_ROOT}/{name}'; os.makedirs(out, exist_ok=True)
    json.dump(dict(inputs=inputs, train=matches, epochs=epochs), open(f'{out}/config.json', 'w'))
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    tr = Samples(matches, 'train', inputs, True); va = Samples(matches, 'val', inputs, False)
    # balance: about 40% ball-less crops per batch
    has = np.array([float(np.load(f)['ball'][0] >= 0) for f in tr.files])
    w = np.where(has > 0, 0.6 / max(1, has.sum()), 0.4 / max(1, (1 - has).sum()))
    sampler = torch.utils.data.WeightedRandomSampler(w, num_samples=len(tr), replacement=True)
    dl = torch.utils.data.DataLoader(tr, batch_size=bs, sampler=sampler, num_workers=4, persistent_workers=True, drop_last=True)
    vl = torch.utils.data.DataLoader(va, batch_size=64, num_workers=4)
    model = BallNet(channels(inputs)).to(dev)
    optim = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(optim, max_lr=2e-3, total_steps=epochs * len(dl), pct_start=0.1)
    start, best = 0, -1.0
    if os.path.exists(f'{out}/last.pt'):                                          # resume
        ck = torch.load(f'{out}/last.pt', map_location=dev)
        model.load_state_dict(ck['model']); optim.load_state_dict(ck['optim']); sched.load_state_dict(ck['sched'])
        start, best = ck['epoch'] + 1, ck['best']
        print(f'resumed {name} at epoch {start}', flush=True)
    print(f'{name}: inputs {inputs}, train {matches}: {len(tr)} train / {len(va)} val crops, '
          f'{sum(p.numel() for p in model.parameters()) / 1e6:.2f} M params, device {dev}', flush=True)
    for ep in range(start, epochs):
        t0, tot = time.time(), 0.0
        for x, hm, off, meta in dl:
            x, hm, off = x.to(dev), hm.to(dev), off.to(dev)
            h, o = model(x)
            lf = focal(h, hm)
            idx = torch.stack([meta['cy'], meta['cx']], 1).to(dev); hasb = meta['has'].float().to(dev)
            po = o[torch.arange(len(o)), :, idx[:, 0], idx[:, 1]]
            lo = (F.l1_loss(po, off, reduction='none').sum(1) * hasb).sum() / hasb.sum().clamp(min=1)
            loss = lf + lo
            optim.zero_grad(); loss.backward(); optim.step(); sched.step(); tot += float(loss)
        m = score(evaluate(model, vl, dev))
        rec = dict(epoch=ep, loss=tot / len(dl), sec=round(time.time() - t0), **{k: round(v, 4) if isinstance(v, float) else v for k, v in m.items()})
        print(json.dumps(rec), flush=True); open(f'{out}/log.jsonl', 'a').write(json.dumps(rec) + '\n')
        key = m['recall'] - m['false_alarm']
        ck = dict(model=model.state_dict(), optim=optim.state_dict(), sched=sched.state_dict(), epoch=ep, best=max(best, key), inputs=inputs)
        torch.save(ck, f'{out}/last.tmp'); os.replace(f'{out}/last.tmp', f'{out}/last.pt')     # atomic
        if key > best: best = key; torch.save(dict(model=model.state_dict(), inputs=inputs, epoch=ep), f'{out}/best.pt')

def eval_cmd(name):
    out = f'{OUT_ROOT}/{name}'; ck = torch.load(f'{out}/best.pt', map_location='cpu')
    model = BallNet(channels(ck['inputs'])); model.load_state_dict(ck['model'])
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'; model.to(dev)
    res = {}
    for m in opt('--on', 'm1,m2,m3').split(','):
        for split in ('val', None):
            ds = Samples([m], split, ck['inputs'], False)
            r = score(evaluate(model, torch.utils.data.DataLoader(ds, batch_size=64, num_workers=4), dev))
            res[f'{m}_{split or "all"}'] = r
            print(name, m, split or 'all', json.dumps({k: round(v, 3) if isinstance(v, float) else v for k, v in r.items()}), flush=True)
    json.dump(res, open(f'{out}/eval.json', 'w'), indent=1)

if __name__ == '__main__':
    {'train': train, 'eval': eval_cmd}[sys.argv[1]](sys.argv[2])
