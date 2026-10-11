"""Contact sheet перевірки м'яча: вирізки навколо точок треку, щоб очима порахувати «N з M — справжній м'яч».
Використання: python src/ball_sheet.py VIDEO TRACK.json OUT.jpg [N=24] [--minus OTHER_TRACK.json] [--seed 0]
  --minus: лише точки, яких немає в OTHER_TRACK (наприклад, що прийняла стара версія, а нова відкинула).
"""
import cv2, json, sys, random, numpy as np
SRC, TRACK, OUT = sys.argv[1:4]
N = int(sys.argv[4]) if len(sys.argv) > 4 and not sys.argv[4].startswith('--') else 24
random.seed(int(sys.argv[sys.argv.index('--seed') + 1]) if '--seed' in sys.argv else 0)
tr = {int(k): v for k, v in json.load(open(TRACK)).items()}
if '--minus' in sys.argv:
    other = {int(k): v for k, v in json.load(open(sys.argv[sys.argv.index('--minus') + 1])).items()}
    tr = {f: p for f, p in tr.items() if f not in other or np.hypot(p[0] - other[f][0], p[1] - other[f][1]) > 30}
pick = sorted(random.sample(sorted(tr), min(N, len(tr))))
cap = cv2.VideoCapture(SRC); fps = cap.get(5); R = 60; tiles = []
for f in pick:
    cap.set(1, f); ok, im = cap.read()
    if not ok: continue
    x, y = map(int, tr[f]); H, W = im.shape[:2]
    x0, y0 = int(np.clip(x - R, 0, W - 2 * R)), int(np.clip(y - R, 0, H - 2 * R))
    t = cv2.resize(im[y0:y0 + 2 * R, x0:x0 + 2 * R], (240, 240), interpolation=cv2.INTER_CUBIC)
    cv2.circle(t, ((x - x0) * 2, (y - y0) * 2), 14, (0, 0, 255), 1)
    cv2.putText(t, f'{f / fps:.1f}s {x},{y}', (4, 16), 0, 0.45, (0, 255, 255), 1)
    tiles.append(t)
while len(tiles) % 6: tiles.append(np.zeros((240, 240, 3), np.uint8))
cv2.imwrite(OUT, np.vstack([np.hstack(tiles[i:i + 6]) for i in range(0, len(tiles), 6)]))
print(OUT, 'points in pool', len(tr), 'shown', len(pick))
