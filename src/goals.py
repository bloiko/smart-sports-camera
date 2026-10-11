"""Автоматичний пошук воріт без ручних кроків і без сторонніх моделей.

Ідея: гравці майже ніколи не заходять за лінію воріт, а воротар весь матч стоїть біля них,
тож ворота — це лівий і правий «кінчики» області, де гравці проводять час.
1. Теплова карта ніг гравців на полі за весь матч (детекції detect.py), розмита.
2. Поріг → найбільша зв'язна область («хмара гри»); люди біля кутових і асистент на бровці
   дають окремі острівці, які відкидаються.
3. Ворота = центр крайніх 40 px області зліва і справа.
Точність на 3 тестових матчах: ≤ ~60 px по x, ≤ ~80 px по y (див. specs/results.md), тому
follow.py розширює зону воріт на goal_unc_px, коли ворота знайдені автоматично.

Використання (перевірка): python src/goals.py VIDEO DETECTIONS.jsonl [CHECKLIST.json] [--vis out.jpg]
"""
import json, sys, numpy as np, cv2


def find_goals(rows, fmask, thr=0.1, blur=25, tip_px=40):
    """rows: рядки detections.jsonl; fmask: маска поля (H×W, 0/1). Повертає ([left, right], область)."""
    H, W = fmask.shape
    heat = np.zeros((H, W), np.float32)
    for r in rows:
        for b in r['persons']:
            fx, fy = (b[0] + b[2]) / 2, b[3]
            if b[4] < 0.25 or not 12 <= b[3] - b[1] <= 260: continue
            x, y = min(int(fx), W - 1), min(int(fy), H - 1)
            if fmask[y, x]: heat[y, x] += 1
    if heat.max() == 0: return [], None
    heat = cv2.GaussianBlur(heat, (0, 0), blur)
    heat /= np.percentile(heat[heat > 0], 99)
    n, lab, st, _ = cv2.connectedComponentsWithStats((heat > thr).astype(np.uint8))
    if n < 2: return [], None
    region = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    ys, xs = np.nonzero(region)
    left = xs <= xs.min() + tip_px; right = xs >= xs.max() - tip_px
    return [np.array([xs[left].mean(), ys[left].mean()]), np.array([xs[right].mean(), ys[right].mean()])], region


if __name__ == '__main__':
    sys.path.insert(0, __file__.rsplit('/', 1)[0])
    from fieldmask import field_mask
    video, det = sys.argv[1], sys.argv[2]
    fm, med = field_mask(video)
    fm = cv2.dilate(fm, np.ones((41, 41), np.uint8))
    goals, region = find_goals([json.loads(l) for l in open(det)], fm)
    print('goals', [[round(float(v)) for v in g] for g in goals])
    cl = json.load(open(sys.argv[3])) if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else None
    if cl:
        for side, g in zip(('left', 'right'), goals):
            t = cl['goals'][side]; print(f'{side}: error x {g[0] - t[0]:+.0f} px, y {g[1] - t[1]:+.0f} px')
    if '--vis' in sys.argv:
        vis = med.copy(); vis[region] = (vis[region] * 0.6 + np.array([0, 90, 160]) * 0.4).astype(np.uint8)
        for g in goals: cv2.circle(vis, (int(g[0]), int(g[1])), 18, (0, 0, 255), 3)
        if cl:
            for x0, y0, x1, y1 in cl['mouths'].values(): cv2.rectangle(vis, (x0, y0), (x1, y1), (255, 255, 255), 2)
        cv2.imwrite(sys.argv[sys.argv.index('--vis') + 1], vis)
