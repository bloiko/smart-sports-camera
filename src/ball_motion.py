"""Крок 1б: пошук м'яча за рухом (камера нерухома, тож рухаються лише гравці і м'яч).
Трикадрова різниця → маленькі круглі плями → прибираємо плями на гравцях → зв'язуємо в треки.
Результат: ball_motion.json  {frame: [x, y]}
Використання: python3 ball_motion.py video.mp4 detections.jsonl out.json [max_frames]
"""
import cv2, json, sys, numpy as np, math

SRC, DET, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
MAXF = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
Y0, Y1 = 60, 800
K = 2                 # крок різниці кадрів
TH = 28               # поріг зміни яскравості
AREA = (3, 120)       # площа плями м'яча (пікселі)
PAD = 12              # розширення рамок гравців

from fieldmask import field_mask
FM = cv2.erode(field_mask(SRC)[0], np.ones((15, 15), np.uint8))[Y0:Y1]
dets = {}
for l in open(DET):
    r = json.loads(l); dets[r['frame']] = r['persons']
det_frames = np.array(sorted(dets))

def persons_at(f):
    j = det_frames[np.argmin(np.abs(det_frames - f))]
    return dets[j]

cap = cv2.VideoCapture(SRC)
N = min(int(cap.get(7)), MAXF, int(det_frames[-1]) + 3)
buf = []
cands = {}  # frame -> list of (x, y, area)
for f in range(N):
    ok, img = cap.read()
    if not ok: break
    band = img[Y0:Y1]
    g = band.max(axis=2).astype(np.int16)   # білий м'яч яскравий у всіх каналах
    hsv = cv2.cvtColor(band, cv2.COLOR_BGR2HSV)
    white = ((hsv[..., 1] < 110) & (hsv[..., 2] > 140)).astype(np.uint8)  # м'яч світлий і ненасичений
    buf.append((g, white))
    if len(buf) < 2 * K + 1: continue
    a, (b, wb), c = buf[0][0], buf[K], buf[2 * K][0]; t = f - K
    m = ((np.abs(b - a) > TH) & (np.abs(b - c) > TH) & (b > a) & (b > c)).astype(np.uint8)  # з'явилось щось яскраве
    m &= FM   # лише всередині поля
    m &= cv2.dilate(wb, np.ones((3, 3), np.uint8))
    # прибрати гравців
    for p in persons_at(t):
        x0, y0, x1, y1 = int(p[0]) - PAD, int(p[1]) - Y0 - PAD, int(p[2]) + PAD, int(p[3]) - Y0 + PAD
        m[max(y0, 0):max(y1, 0), max(x0, 0):max(x1, 0)] = 0
    n, lab, st, cen = cv2.connectedComponentsWithStats(m, 8)
    out = []
    for i in range(1, n):
        x, y, w, h, ar = st[i]
        if AREA[0] <= ar <= AREA[1] and max(w, h) <= 3 * min(w, h) + 2:
            out.append((float(cen[i][0]), float(cen[i][1] + Y0), int(ar)))
    if len(out) < 25:   # якщо плям сотні — це шум (тінь хмари, спалах)
        cands[t] = out
    buf.pop(0)
    if f % 500 == 0: print(f, N, flush=True)

# ---- зв'язування в треки: м'яч рухається плавно і часто ----
frames = sorted(cands)
tracks = []   # list of dict(pts={f:(x,y)}, last_f, last_p, vel)
for f in frames:
    used = set()
    for tr in sorted(tracks, key=lambda t: -len(t['pts'])):
        if f - tr['last_f'] > 6: continue
        dt = f - tr['last_f']
        pred = (tr['last_p'][0] + tr['vel'][0] * dt, tr['last_p'][1] + tr['vel'][1] * dt)
        best, bd = None, 25 + 12 * dt
        for k, (x, y, ar) in enumerate(cands[f]):
            if k in used: continue
            d = math.dist((x, y), pred)
            if d < bd: best, bd = k, d
        if best is not None:
            used.add(best); x, y, _ = cands[f][best]
            tr['vel'] = ((x - tr['last_p'][0]) / dt, (y - tr['last_p'][1]) / dt)
            tr['pts'][f] = (x, y); tr['last_f'], tr['last_p'] = f, (x, y)
    for k, (x, y, ar) in enumerate(cands[f]):
        if k not in used:
            tracks.append(dict(pts={f: (x, y)}, last_f=f, last_p=(x, y), vel=(0.0, 0.0)))

def score(tr):
    pts = np.array(list(tr['pts'].values()))
    travel = np.linalg.norm(np.diff(pts, axis=0), axis=1).sum() if len(pts) > 1 else 0
    return len(pts), travel

good = []
for tr in tracks:
    n, travel = score(tr)
    if n >= 6 and travel >= 40: good.append(tr)
ball = {}
for tr in sorted(good, key=lambda t: len(t['pts'])):   # довші треки перезаписують коротші
    for f, p in tr['pts'].items(): ball[f] = p
json.dump({str(k): v for k, v in sorted(ball.items())}, open(OUT, 'w'))
print('frames', N, 'cand frames', len(cands), 'tracks', len(tracks), 'good', len(good), 'ball frames', len(ball),
      'share', round(len(ball) / max(N, 1), 3))
