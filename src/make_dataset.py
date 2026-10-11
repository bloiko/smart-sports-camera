"""Автоматична розмітка (pseudo-labels) м'яча для дотренування детектора. Працює для будь-якого матчу.

Позитиви: кадри з прийнятим трекером м'ячем (ball_track.json з follow.py) + проміжні кадри між двома
сусідніми детекціями (позиція обчислена лінійно — модель на них м'яча не бачила, це «складні» приклади).
Негативи: ділянки поля, де жодна модель нічого не знаходила.
Розмір м'яча залежно від глибини оцінюється з реальних рамок детекцій (balls.jsonl).
Патчі 160x160 з панорами, збільшені 2x → 320x320 (той самий масштаб, що й при пошуку у вікні).
Train: перші 80% відео, val: останні 20% (щоб перевірка була на хвилинах, яких модель не бачила).

Використання (кілька матчів дописуються в один датасет):
  python src/make_dataset.py dataset game1.mp4 out1/ball_track.json balls1.jsonl m1 [max_pos]
  python src/make_dataset.py dataset game2.mp4 out2/ball_track.json balls2.jsonl m2 [max_pos]
"""
import cv2, json, numpy as np, os, random, sys
from fieldmask import field_mask

DS, SRC, TRACK, BALLS, PREFIX = sys.argv[1:6]
MAX_POS = int(sys.argv[6]) if len(sys.argv) > 6 else 700
P, UP = 160, 2
random.seed(hash(PREFIX) % 1000)
for s in ('train', 'val'):
    os.makedirs(f'{DS}/images/{s}', exist_ok=True); os.makedirs(f'{DS}/labels/{s}', exist_ok=True)

track = {int(k): v for k, v in json.load(open(TRACK)).items()}
dets = {}
for l in open(BALLS):
    r = json.loads(l); dets[r['frame']] = r['balls']
fs = sorted(track)
step = int(np.median(np.diff(sorted(dets)))) if len(dets) > 2 else 5

# запасні м'ячі біля бровки: позиції, що повторюються в >10% відліків
cent = np.array([((b[0] + b[2]) / 2, (b[1] + b[3]) / 2, ((b[2] - b[0]) + (b[3] - b[1])) / 2, b[4])
                 for v in dets.values() for b in v] or [(-1e4, -1e4, 0, 0)])
static = np.array([p[:2] for p in cent if (np.linalg.norm(cent[:, :2] - p[:2], axis=1) < 25).sum() > 0.1 * len(dets)]
                  or [(-1e4, -1e4)])
def near_static(x, y, r=40): return np.min(np.linalg.norm(static - (x, y), axis=1)) < r

# розмір м'яча від глибини: медіани по смугах y (без запасних м'ячів), лінійна апроксимація
good = np.array([p for p in cent if p[3] >= 0.3 and not near_static(p[0], p[1])] or [(0, 0, 10, 1)])
bins = [(lo, lo + 150) for lo in range(0, 2000, 150)]
bx, by = [], []
for lo, hi in bins:
    m = (good[:, 1] >= lo) & (good[:, 1] < hi)
    if m.sum() >= 5: bx.append(good[m, 1].mean()); by.append(np.median(good[m, 2]))
k, c = np.polyfit(bx, by, 1) if len(bx) >= 2 else (0.0, float(np.median(good[:, 2])))
k = max(k, 0.0)                                       # ближче до камери м'яч не може бути меншим
def ball_size(y): return float(np.clip(k * y + c, 5, 30))
print(PREFIX, 'step', step, 'static', len(static), 'ball size by y:', [(int(y), round(ball_size(y), 1)) for y in (bx[:1] + bx[-1:])])

# позитиви: прийняті трекером точки + лінійна інтерполяція між сусідніми
labels = {f: tuple(track[f]) for f in fs}
for a, b in zip(fs, fs[1:]):
    if b - a == step:
        pa, pb = np.array(track[a]), np.array(track[b])
        if np.linalg.norm(pb - pa) < 24 * step:          # плавний рух — інтерполяція надійна
            for j in range(1, step): labels[a + j] = tuple(pa + (pb - pa) * j / step)
pos = sorted(labels)
if len(pos) > MAX_POS: pos = sorted(random.sample(pos, MAX_POS))
print(PREFIX, 'labels', len(labels), 'used', len(pos))

# негативи: точки поля далеко від будь-якої детекції м'яча (включно з запасними біля бровки)
fmask = field_mask(SRC)[0]
fy, fx = np.where(fmask > 0)
fmask_d = cv2.dilate(fmask, np.ones((61, 61), np.uint8))
det_frames = np.array(sorted(dets))
def dets_near(f, win=15):       # детекції м'яча в сусідніх кадрах + запасні м'ячі
    pts = [((b[0] + b[2]) / 2, (b[1] + b[3]) / 2) for g in det_frames[np.abs(det_frames - f) <= win] for b in dets[g]]
    pts += [labels[g] for g in range(f - win, f + win + 1) if g in labels]
    return np.array(pts + [tuple(p) for p in static] or [(-1e4, -1e4)])
cap = cv2.VideoCapture(SRC); N = int(cap.get(7)); W, H = int(cap.get(3)), int(cap.get(4)); split = int(N * 0.8)
neg = sorted(random.sample(range(0, N), max(1, len(pos) // 3)))

todo = {f: 'p' for f in pos}
for f in neg: todo.setdefault(f, 'n')
n_pos = n_neg = 0
for f in range(max(todo) + 1):                      # послідовне читання швидше за перемотку
    if f not in todo:
        if not cap.grab(): break
        continue
    ok, img = cap.read()
    if not ok: break
    sub = 'train' if f < split else 'val'
    if todo[f] == 'p':
        x, y = labels[f]
        if not fmask_d[min(int(y), H - 1), min(int(x), W - 1)]: continue        # не на полі (людина за сіткою тощо)
        # уточнення позиції: м'яч — найсвітліша ненасичена пляма поруч (інтерполяція між кадрами неточна)
        r = int(max(12, ball_size(y) * 1.5)) if f not in track else int(ball_size(y) * 0.6) + 3
        ax0, ay0 = int(max(0, x - r)), int(max(0, y - r))
        hsv = cv2.cvtColor(img[ay0:int(y + r) + 1, ax0:int(x + r) + 1], cv2.COLOR_BGR2HSV)
        v = hsv[..., 2].astype(int)    # м'яч помітно світліший за траву навколо (працює і для блідої трави)
        white = ((v > np.median(v) + 45) & (hsv[..., 1] < 90)).astype(np.uint8)
        n_, lab_, st_, cen_ = cv2.connectedComponentsWithStats(white)
        best = [cen_[i] for i in range(1, n_) if 2 <= st_[i, 4] <= 4 * ball_size(y) ** 2]
        if best:
            bx_, by_ = min(best, key=lambda p: (p[0] + ax0 - x) ** 2 + (p[1] + ay0 - y) ** 2)
            x, y = bx_ + ax0, by_ + ay0
        elif f not in track:
            continue                                                             # інтерпольований кадр без м'яча — пропускаємо
        x0 = int(np.clip(x - random.randint(20, P - 20), 0, W - P)); y0 = int(np.clip(y - random.randint(20, P - 20), 0, H - P))
        d = ball_size(y)
        lab = f'0 {(x - x0) / P:.5f} {(y - y0) / P:.5f} {d / P:.5f} {d / P:.5f}\n'
        name = f'{PREFIX}_{sub}_p{f:05d}'; n_pos += 1
    else:
        i = random.randrange(len(fx)); cx, cy = fx[i], fy[i]
        x0 = int(np.clip(cx - P // 2, 0, W - P)); y0 = int(np.clip(cy - P // 2, 0, H - P))
        all_det = dets_near(f)
        inside = (all_det[:, 0] > x0 - 15) & (all_det[:, 0] < x0 + P + 15) & (all_det[:, 1] > y0 - 15) & (all_det[:, 1] < y0 + P + 15)
        if inside.any(): continue
        lab = ''; name = f'{PREFIX}_{sub}_n{f:05d}'; n_neg += 1
    patch = cv2.resize(img[y0:y0 + P, x0:x0 + P], (P * UP, P * UP), interpolation=cv2.INTER_CUBIC)
    cv2.imwrite(f'{DS}/images/{sub}/{name}.jpg', patch, [cv2.IMWRITE_JPEG_QUALITY, 92])
    open(f'{DS}/labels/{sub}/{name}.txt', 'w').write(lab)
open(f'{DS}/data.yaml', 'w').write(f'path: {os.path.abspath(DS)}\ntrain: images/train\nval: images/val\nnames:\n  0: ball\n')
print(PREFIX, 'positives', n_pos, 'negatives', n_neg)
