"""FolloNet-B probe (docs/detector-licence-plan.md, 2026-10-17): training samples for our own ball network.

Each sample is a 256×256 crop of the source frame (native resolution, no upscaling) with:
  - frames t-2, t-1, t (motion: the ball is the fastest small thing on the pitch);
  - the background crop from the median frame (live_pre/med.png): logos, lines and adverts vanish in "frame − background";
  - the ball position in crop pixels, or none;
  - a decoy position for negatives (where a wrong prior would point: a YOLO false positive, a spare ball, a player's feet).
The tracker prior channel is simulated at training time from these positions (ballnet.py).

Labels (teacher data on the Mac, never shipped):
  - positives: the offline v0.3 ball track (final_v03/ball_track.json) and linear interpolation between neighbouring
    track points ≤ 10 frames apart (flag interp=1: frames where no detector saw the ball, the "hard" ones);
  - hard negatives: live YOLO ball candidates (live_pre/live_det.jsonl) more than 30 px from the true ball;
  - spare balls: positions where candidates repeat in > 10% of frames;
  - player negatives: crops around players' feet away from the ball.
Split: frames before 80% of the video → train, after → val (held-out minutes, project rule).

Usage: python src/ballnet_data.py work/m2 work/ballds/m2 [--max-pos 3000] [--fast] [--clean-feet] [--more-feet]
Resumable: a finished match leaves OUT/done; delete it to rebuild.
"""
import cv2, json, numpy as np, os, random, sys

MATCH, OUT = sys.argv[1], sys.argv[2]
MAX_POS = int(sys.argv[sys.argv.index('--max-pos') + 1]) if '--max-pos' in sys.argv else 3000
S, OFF = 256, 90                       # crop size; how far from the crop centre the target may be
os.makedirs(OUT, exist_ok=True)
if os.path.exists(f'{OUT}/done'):
    print('already built:', OUT); sys.exit(0)
rng = random.Random(hash(OUT) % 10_000)

track = {int(k): v for k, v in json.load(open(f'{MATCH}/final_v03/ball_track.json')).items()}
live = [json.loads(l) for l in open(f'{MATCH}/live_pre/live_det.jsonl')]
N = len(live)
bg = cv2.imread(f'{MATCH}/live_pre/med.png')
cap = cv2.VideoCapture(f'{MATCH}/game.mp4')
W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
if bg.shape[:2] != (H, W):
    bg = cv2.resize(bg, (W, H), interpolation=cv2.INTER_AREA)
split_at = int(0.8 * N)

# truth per frame: track points and short linear gaps between them
truth, interp = dict(track), set()
ks = sorted(track)
for a, b in zip(ks, ks[1:]):
    pa, pb = np.array(track[a]), np.array(track[b])
    if b - a <= 10 and np.linalg.norm(pb - pa) / (b - a) <= 25:
        for f in range(a + 1, b):
            truth[f] = list(pa + (pb - pa) * (f - a) / (b - a)); interp.add(f)

def at_feet(rec, q):
    """q inside the lower 35% of a person box (boots and socks), a few px of margin."""
    for p in rec.get('persons') or []:
        h = p[3] - p[1]
        if p[0] - 4 <= q[0] <= p[2] + 4 and p[3] - 0.35 * h <= q[1] <= p[3] + 6: return True
    return False

# --fast (v3, 2026-10-18): fast passes were missing (track points 30 frames apart, interpolation only ≤ 10), and the
# network lost a fast far pass at m2 0:10. Inside gaps of up to 60 frames, take the live YOLO tracker's accepted ball
# where it lies within 20 px of the line between the two track points: two independent sources agree.
if '--fast' in sys.argv:
    live_ball = {r['frame']: r['ball'] for r in live if 'ball' in r}
    added = dropped = 0
    for a, b in zip(ks, ks[1:]):
        if b - a <= 10 or b - a > 60: continue
        pa, pb = np.array(track[a]), np.array(track[b])
        for f in range(a + 1, b):
            if f in live_ball:
                q = np.array(live_ball[f]); lin = pa + (pb - pa) * (f - a) / (b - a)
                if np.linalg.norm(q - lin) >= 20: continue
                # --clean-feet (v5, 2026-10-19): v4 learnt "white spot at a player's feet = ball" (m1 2:54.8, m3 1:25.0);
                # 29% of the m2 fast positives sat at a player's feet. Drop those.
                if '--clean-feet' in sys.argv and at_feet(live[f] if f < len(live) else {}, q): dropped += 1; continue
                truth[f] = list(q); interp.add(f); added += 1
    print('fast-pass positives from live YOLO agreeing with the track line:', added, 'dropped at feet:', dropped, flush=True)

def cands(rec):
    return [((b[0] + b[2]) / 2, (b[1] + b[3]) / 2, b[4] if len(b) > 4 else 1.0) for b in rec.get('balls') or []]

# spare balls next to the pitch: candidate positions repeating in > 10% of frames
allc = np.array([c[:2] for r in live for c in cands(r)] or [(-1e4, -1e4)])
static = [p for p in allc if (np.linalg.norm(allc - p, axis=1) < 25).sum() > 0.1 * N]
static = np.array(static or [(-1e4, -1e4)])

jobs = {}                              # frame -> list of (kind, target(x, y), ball or None)
pos_frames = sorted(f for f in truth if f >= 2)
rng.shuffle(pos_frames)
for f in sorted(pos_frames[:MAX_POS]):
    jobs.setdefault(f, []).append(('pos', truth[f], truth[f]))
for r in live:
    f = r['frame']
    if f < 2 or f not in truth: continue                       # unknown truth: cannot call it a false positive
    t = np.array(truth[f])
    for x, y, c in cands(r):
        if c >= 0.25 and np.linalg.norm(t - (x, y)) > 30:
            jobs.setdefault(f, []).append(('fp', (x, y), t if np.max(np.abs(t - (x, y))) < S / 2 - 8 else None))
    if '--more-feet' in sys.argv and r.get('persons'):         # v5: up to 3 players per frame, far (small) ones first,
        if rng.random() < 0.6:                                    # boots or socks
            ps = sorted(r['persons'], key=lambda p: (p[3] - p[1]) * rng.uniform(0.7, 1.3))[:3]
            for p in ps:
                h = p[3] - p[1]; foot = ((p[0] + p[2]) / 2 + rng.uniform(-0.2, 0.2) * (p[2] - p[0]), p[3] - rng.uniform(0, 0.2) * h)
                if np.linalg.norm(t - foot) > 60: jobs.setdefault(f, []).append(('player', foot, t if np.max(np.abs(t - foot)) < S / 2 - 8 else None))
    elif rng.random() < 0.25 and r.get('persons'):             # a player's feet away from the ball
        p = rng.choice(r['persons']); foot = ((p[0] + p[2]) / 2, p[3])
        if np.linalg.norm(t - foot) > 60:
            jobs.setdefault(f, []).append(('player', foot, None))
for f in rng.sample(sorted(truth), min(300, len(truth))):        # spare balls
    if f < 2: continue
    s = static[rng.randrange(len(static))]
    if s[0] > -1e3: jobs.setdefault(f, []).append(('spare', tuple(s), None))

def enc(img):
    return np.frombuffer(cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 95])[1].tobytes(), np.uint8)

ring, n_out, last = [], 0, max(jobs) if jobs else -1
counts = {}
for f in range(last + 1):
    ok, img = cap.read()
    if not ok: break
    ring = (ring + [img])[-3:]
    if f not in jobs or len(ring) < 3: continue
    for i, (kind, tgt, ball) in enumerate(jobs[f]):
        cx = tgt[0] + rng.uniform(-OFF, OFF); cy = tgt[1] + rng.uniform(-OFF, OFF)
        x0 = int(np.clip(cx - S / 2, 0, W - S)); y0 = int(np.clip(cy - S / 2, 0, H - S))
        b = None
        if ball is not None:
            bx, by = ball[0] - x0, ball[1] - y0
            if 4 <= bx < S - 4 and 4 <= by < S - 4: b = (bx, by)
        if kind == 'pos' and b is None: continue
        crop = lambda im: im[y0:y0 + S, x0:x0 + S]
        np.savez(f'{OUT}/{f:05d}_{i}_{kind}.npz', f0=enc(crop(ring[0])), f1=enc(crop(ring[1])), f2=enc(crop(ring[2])), bg=enc(crop(bg)),
                 ball=np.array(b if b else (-1, -1), np.float32), decoy=np.array((tgt[0] - x0, tgt[1] - y0), np.float32),
                 interp=int(f in interp), frame=f, x0=x0, y0=y0, split='train' if f < split_at else 'val', kind=kind)
        n_out += 1; counts[kind] = counts.get(kind, 0) + 1
open(f'{OUT}/done', 'w').write(json.dumps(counts))
print(OUT, n_out, counts, f'interp positives {sum(1 for f in interp if f in jobs)}')
