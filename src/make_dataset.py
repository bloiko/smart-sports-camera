"""Автоматична розмітка (pseudo-labels) для дотренування детектора м'яча.
Позитиви: кадри з упевненим м'ячем + проміжні кадри між двома сусідніми детекціями
(позиція обчислена лінійно — модель на них м'яча не бачила, це «складні» приклади).
Негативи: ділянки поля без м'яча.
Патчі 320x320 з панорами, збільшені 2x → 640x640 (той самий масштаб, що й при пошуку у вікні).
Train: кадри < 80% відео, val: останні 20% (щоб не підглядати).
"""
import cv2, json, numpy as np, os, random, sys
random.seed(0)
# Використання: python src/make_dataset.py game.mp4 out/ball_track.json
SRC = sys.argv[1]
track = {int(k): v for k, v in json.load(open(sys.argv[2])).items()}
DS = 'dataset'
for s in ('train', 'val'):
    os.makedirs(f'{DS}/images/{s}', exist_ok=True); os.makedirs(f'{DS}/labels/{s}', exist_ok=True)

def ball_size(y):  # діаметр м'яча в пікселях панорами залежно від глибини
    return float(np.interp(y, [150, 700], [7, 15]))

labels = {}  # frame -> (x, y)
fs = sorted(track)
for f in fs: labels[f] = tuple(track[f])
for a, b in zip(fs, fs[1:]):
    if b - a == 5:
        pa, pb = np.array(track[a]), np.array(track[b])
        if np.linalg.norm(pb - pa) < 120:          # плавний рух — інтерполяція надійна
            for k in range(1, 5): labels[a + k] = tuple(pa + (pb - pa) * k / 5)
print('labeled frames', len(labels), 'of which interpolated', len(labels) - len(fs))

static = [(3742, 641), (3976, 601), (443, 686), (350, 742), (4029, 575), (1794, 692)]  # запасні м'ячі
cap = cv2.VideoCapture(SRC); N = int(cap.get(7)); split = int(N * 0.8)
P, UP = 160, 2
neg_frames = set(random.sample(range(0, N, 7), 250))
todo = sorted(set(labels) | neg_frames)
n_pos = n_neg = 0
todo_set = set(todo)
for f in range(max(todo) + 1):       # послідовне читання швидше за перемотку
    if f not in todo_set:
        cap.grab(); continue
    ok, img = cap.read()
    if not ok: break
    H, W = img.shape[:2]; sub = 'train' if f < split else 'val'
    if f in labels:
        x, y = labels[f]
        x0 = int(np.clip(x - random.randint(20, P - 20), 0, W - P)); y0 = int(np.clip(y - random.randint(20, P - 20), 0, H - P))
        d = ball_size(y)
        lab = f'0 {(x - x0) / P:.5f} {(y - y0) / P:.5f} {d / P:.5f} {d / P:.5f}\n'
        name = f'{sub}_p{f:05d}'; n_pos += 1
    else:
        x0, y0 = random.randint(0, W - P), random.randint(60, 760 - P)
        if any(x0 - 20 < sx < x0 + P + 20 and y0 - 20 < sy < y0 + P + 20 for sx, sy in static): continue
        if any(abs(g - f) < 6 for g in labels): continue
        lab = ''; name = f'{sub}_n{f:05d}'; n_neg += 1
    patch = cv2.resize(img[y0:y0 + P, x0:x0 + P], (P * UP, P * UP), interpolation=cv2.INTER_CUBIC)
    cv2.imwrite(f'{DS}/images/{sub}/{name}.jpg', patch, [cv2.IMWRITE_JPEG_QUALITY, 92])
    open(f'{DS}/labels/{sub}/{name}.txt', 'w').write(lab)
open(f'{DS}/data.yaml', 'w').write(f'path: {os.path.abspath(DS)}\ntrain: images/train\nval: images/val\nnames:\n  0: ball\n')
print('positives', n_pos, 'negatives', n_neg)
