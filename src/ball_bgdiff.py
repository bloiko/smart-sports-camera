"""Перевірка «м'яч чи фон»: для кожної детекції м'яча — наскільки ця ділянка кадру відрізняється від фону.

Фон = медіана кадрів по всьому відео (fieldmask.field_mask): усе, що рухається (гравці, м'яч), зникає,
а нерухоме — букви на газоні, лінії, стійки, запасні м'ячі — лишається. Справжній м'яч у грі на фоні
відсутній, тож різниця велика; буква логотипа на газоні збігається з фоном — різниця мала.

До кожної детекції дописується 6-те число: різниця з фоном (0–255, 75-й перцентиль по рамці м'яча).
Використання: python src/ball_bgdiff.py VIDEO FILE.jsonl [FILE2.jsonl ...]
  → FILE.bg.jsonl поруч (вхідний файл не змінюється); follow.py бере *.bg.jsonl, якщо він є.
"""
import cv2, json, sys, time, numpy as np
from fieldmask import field_mask


def bg_diff(img, med, b):
    """75-й перцентиль |кадр − фон| (сірий) у рамці м'яча, розширеній до ≥ 6 px."""
    H, W = img.shape[:2]
    cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2; r = max(3.0, (b[2] - b[0] + b[3] - b[1]) / 4)
    x0, x1 = int(max(0, cx - r)), int(min(W, cx + r + 1)); y0, y1 = int(max(0, cy - r)), int(min(H, cy + r + 1))
    if x1 <= x0 or y1 <= y0: return 0.0
    a = cv2.cvtColor(img[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY).astype(np.int16)
    m = cv2.cvtColor(med[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY).astype(np.int16)
    return float(np.percentile(np.abs(a - m), 75))


if __name__ == '__main__':
    src, files = sys.argv[1], sys.argv[2:]
    med = field_mask(src, n=15)[1]
    data = [[json.loads(l) for l in open(p)] for p in files]
    by_frame = {}
    for d in data:
        for r in d:
            if r['balls']: by_frame.setdefault(r['frame'], []).append(r)
    need = sorted(by_frame)
    cap = cv2.VideoCapture(src); f = 0; t0 = time.time(); want = set(need)
    while need and f <= need[-1]:
        if f not in want:
            cap.grab(); f += 1; continue
        ok, img = cap.read()
        if not ok: break
        for r in by_frame[f]:
            r['balls'] = [b[:5] + [round(bg_diff(img, med, b), 1)] for b in r['balls']]
        f += 1
        if f % 1000 < 1: print(f, round(time.time() - t0), flush=True)
    for p, d in zip(files, data):
        with open(p.rsplit('.', 1)[0] + '.bg.jsonl', 'w') as out:
            for r in d: out.write(json.dumps(r) + '\n')
    print('done', round(time.time() - t0))
