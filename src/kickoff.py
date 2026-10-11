"""Розіграш з центру (кікоф): ознака, що перед ним був гол. Власні обчислення, без моделей.

На розіграші кожна команда стоїть на своїй половині. Під час гри так майже не буває.
1. Команди за кольором форми: медіана кольору торсу кожного гравця (без пікселів трави) у просторі Lab,
   k-means на 2 кластери по каналах a, b (колір без яскравості). 15% найдальших від центрів
   (судді, воротарі, сміття) відкидаються.
2. Центральна лінія: x посередині між воротами (goals.py).
3. Розділення в кадрі = частка гравців команди A по один бік лінії і команди B по інший
   (краща з двох орієнтацій), середнє за 2 с.
4. Кікоф = розділення ≥ KICKOFF_SEP. Пороги з 3 тестових матчів: обидва кікофи після голів 0.80,
   найкращий момент без голу 0.68 (матч 2) і 0.74 (матч 3, розіграш на старті відео). Запас малий —
   перевіряти на кожному новому відео.

Використання: python src/kickoff.py VIDEO DETECTIONS.jsonl CAMERA_PATH.npz → друкує кандидатів.
"""
import json, sys, numpy as np, cv2

KICKOFF_SEP = 0.77
SMOOTH_S = 2.0


def jersey_colours(video, rows, fmask):
    """[(frame, x_ніг, a, b)] для гравців на полі; читає лише кадри з детекцій."""
    H, W = fmask.shape
    want = {r['frame']: r for r in rows}; out = []
    cap = cv2.VideoCapture(video); f = 0; last = max(want)
    while f <= last:
        if f not in want:
            cap.grab(); f += 1; continue
        ok, im = cap.read()
        if not ok: break
        lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB); hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)
        for x0, y0, x1, y1, c in want[f]['persons']:
            h = y1 - y0
            if c < 0.25 or not 12 <= h <= 260 or not fmask[min(int(y1), H - 1), min(int((x0 + x1) / 2), W - 1)]: continue
            ty0, ty1 = int(y0 + 0.2 * h), int(y0 + 0.5 * h); tx0, tx1 = int(x0 + 0.25 * (x1 - x0)), int(x1 - 0.25 * (x1 - x0))
            pl = lab[ty0:max(ty1, ty0 + 1), tx0:max(tx1, tx0 + 1)].reshape(-1, 3)
            ph = hsv[ty0:max(ty1, ty0 + 1), tx0:max(tx1, tx0 + 1)].reshape(-1, 3)
            keep = ~((ph[:, 0] >= 35) & (ph[:, 0] <= 95) & (ph[:, 1] >= 30))      # без трави
            if keep.sum() < 4: continue
            a, b = np.median(pl[keep][:, 1:], axis=0)
            out.append((f, (x0 + x1) / 2, a, b))
        f += 1
    return np.array(out, float)


def separation(F, centre_x, fps):
    """Час (с) і згладжене розділення команд центральною лінією."""
    ab = F[:, 2:4].astype(np.float32)
    _, lab, cent = cv2.kmeans(ab, 2, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.2), 5, cv2.KMEANS_PP_CENTERS)
    lab = lab.ravel(); d = np.linalg.norm(ab - cent[lab], axis=1); ok = d < np.percentile(d, 85)
    frames = np.unique(F[:, 0]); S = []
    for fr in frames:
        s = (F[:, 0] == fr) & ok; x, L = F[s, 1], lab[s]
        a, b = x[L == 0], x[L == 1]
        if len(a) < 4 or len(b) < 4: S.append(np.nan); continue
        S.append(max((np.mean(a < centre_x) + np.mean(b > centre_x)) / 2, (np.mean(a > centre_x) + np.mean(b < centre_x)) / 2))
    T = frames / fps; S = np.array(S)
    k = max(1, int(round(SMOOTH_S / max(np.median(np.diff(T)), 1e-6))))
    return T, np.convolve(np.nan_to_num(S, nan=0.5), np.ones(k) / k, 'same')


def find_kickoffs(T, S, thr=KICKOFF_SEP, gap_s=20):
    """Початки відрізків із S ≥ thr (окремі кікофи — щонайменше gap_s с між ними): [(t, пік)]."""
    out = []
    for i in np.flatnonzero(S >= thr):
        if out and T[i] - out[-1][2] <= gap_s:
            out[-1][1] = max(out[-1][1], S[i]); out[-1][2] = T[i]
        else:
            out.append([T[i], S[i], T[i]])
    return [(round(float(t), 1), round(float(s), 2)) for t, s, _ in out]


if __name__ == '__main__':
    sys.path.insert(0, __file__.rsplit('/', 1)[0])
    from fieldmask import field_mask
    video, det, path = sys.argv[1:4]
    p = np.load(path); G = p['GOALS']; fps = float(p['FPS'])
    fm = cv2.dilate(field_mask(video)[0], np.ones((41, 41), np.uint8))
    F = jersey_colours(video, [json.loads(l) for l in open(det)], fm)
    T, S = separation(F, (G[0][0] + G[1][0]) / 2, fps)
    print('separation median', round(float(np.median(S)), 2), 'max', round(float(S.max()), 2), 'at', round(float(T[np.argmax(S)]), 1), 's')
    print('kickoffs', find_kickoffs(T, S))
