"""Маска поля: трава, найбільша зв'язна область, заповнені дірки.
Спершу фіксований зелений діапазон (яскрава штучна трава). Якщо поле вийшло замалим
(бліда трава, вечір, склейка камер з різною експозицією) — адаптивний режим:
колір трави береться з кількох точок уздовж нижньої половини кадру."""
import cv2, numpy as np

def _largest(g):
    n_, lab, st, _ = cv2.connectedComponentsWithStats(g)
    if n_ < 2: return np.zeros_like(g)
    comp = (lab == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    m = np.zeros_like(comp); cv2.drawContours(m, [max(cnts, key=cv2.contourArea)], -1, 1, -1)
    return m

def field_mask(src, n=7, until_s=None):
    """until_s: брати кадри лише з перших until_s секунд (live: майбутнього ще немає)."""
    cap = cv2.VideoCapture(src); N = int(cap.get(7)); fr = []
    if until_s: N = min(N, int(until_s * cap.get(5)))
    for k in range(n):
        cap.set(1, int(N * (k + 0.5) / n)); ok, im = cap.read(); fr.append(im)
    med = np.median(np.stack(fr), axis=0).astype(np.uint8)
    hsv_raw = cv2.cvtColor(med, cv2.COLOR_BGR2HSV)
    g = cv2.inRange(hsv_raw, (35, 50, 40), (90, 255, 255))
    m = _largest(cv2.morphologyEx(g, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8)))
    if m.mean() > 0.25:
        return m, med
    # адаптивний режим
    hsv = cv2.cvtColor(cv2.medianBlur(med, 9), cv2.COLOR_BGR2HSV)
    Hh, Ww = hsv.shape[:2]; g = np.zeros((Hh, Ww), np.uint8)
    for fx in (0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8):
        for fy in (0.45, 0.55):
            p = hsv[int(Hh * fy) - 30:int(Hh * fy) + 30, int(Ww * fx) - 30:int(Ww * fx) + 30].reshape(-1, 3)
            h0, s0, v0 = np.median(p, axis=0)
            if not (35 <= h0 <= 95 and s0 >= 15): continue      # точка не на траві
            dh = np.abs(hsv[..., 0].astype(int) - int(h0)); dh = np.minimum(dh, 180 - dh)
            g |= ((dh < 10) & (np.abs(hsv[..., 1].astype(int) - s0) < 25) & (np.abs(hsv[..., 2].astype(int) - v0) < 60)).astype(np.uint8)
    g = cv2.morphologyEx(g * 255, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    g = cv2.morphologyEx(g, cv2.MORPH_CLOSE, np.ones((41, 41), np.uint8))
    return _largest(g), med


if __name__ == '__main__':
    # Preview: python src/fieldmask.py game.mp4  ->  fieldmask.jpg (field highlighted) + fieldmask.npy
    import sys
    m, med = field_mask(sys.argv[1])
    vis = med.copy(); vis[m == 0] = (vis[m == 0] * 0.3).astype(np.uint8)
    cv2.imwrite('fieldmask.jpg', cv2.resize(vis, (2048, int(2048 * vis.shape[0] / vis.shape[1]))))
    np.save('fieldmask.npy', m)
    print('field share of frame:', round(float(m.mean()), 3))
