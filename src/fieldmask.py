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

# Дальня бокова лінія (2026-10-23): маска трави захоплювала дерева і сусіднє поле за трибуною (m2: «м'яч» на людях
# з сусіднього поля тримав камеру; на кадрі без ближніх кутів зелень за воротами доходила до країв, і перевірка
# позиції помилково казала «поверни»). Поки ВИМКНЕНО (2026-10-23), лише для дослідів:
#  - FIELD_LINE=1: шукати лінію (env.json, перевірка позиції за її кінцями). Небезпечно: кінці лінії — дальні кути,
#    а ворота стоять далі назовні; на відео з обрізаними лівими воротами (test10) перевірка казала «ok».
#  - FIELD_LINE_CUT=1: ще й обрізати маску над лінією. На m2 це змінювало пошук м'яча в обидва боки
#    (0:13.5 на повному кадрі 100% → 48%); спершу треба трекер (відкидати нерухомі й позаполеві м'ячі).
import os
FIELD_LINE = os.environ.get('FIELD_LINE', '0') == '1'
FIELD_LINE_CUT = FIELD_LINE and os.environ.get('FIELD_LINE_CUT', '0') == '1'
LINE_B = [float(b) for b in range(-300, 301, 10)]        # нахил, px на ширину кадру
LINE_C = [float(c) for c in range(-200, 2001, 20)]       # кривизна (панорама, ширококутний об'єктив), px
LINE_MARGIN = 0.04                                       # запас над лінією, частка висоти кадру

def far_line(med, m):
    """Дальня бокова лінія як y(x) = y0 + b*u + c*u*u, u = x/W - 0.5, або None.
    Кандидати: білі пікселі з травою на 4 px вище й нижче, у верхніх 45% поля в кожному стовпці, до 3 найвищих
    на стовпець. Перебір (b, c) на сітці, y0 — пік гістограми з кроком 1 px (без випадковості: Swift дає те саме).
    Повертає dict(y0, b, c, xl, xr, cover): xl..xr — найдовший відрізок стовпців на лінії (кінці поля)."""
    H, W = m.shape; hsv = cv2.cvtColor(med, cv2.COLOR_BGR2HSV)
    hh, ss, vv = hsv[..., 0].astype(int), hsv[..., 1].astype(int), hsv[..., 2].astype(int)
    white = (ss < 70) & (vv > 150); grass = (hh >= 35) & (hh <= 95) & (ss >= 30) & (vv >= 30)
    up = np.zeros_like(grass); up[4:] = grass[:-4]; dn = np.zeros_like(grass); dn[:-4] = grass[4:]
    cand = white & up & dn & (m > 0)
    has = m.any(axis=0); top = np.argmax(m > 0, axis=0); bot = H - 1 - np.argmax(m[::-1] > 0, axis=0)
    lim = np.where(has, top + 0.45 * (bot - top), -1.0)
    xs, ys = [], []
    for x in range(W):
        col = np.nonzero(cand[:, x])[0]
        col = col[col <= lim[x]][:3]
        xs += [x] * len(col); ys += col.tolist()
    if len(xs) < 50: return None
    xs = np.array(xs, float); ys = np.array(ys, float); u = xs / W - 0.5
    best = (-1, 0.0, 0.0, 0)
    for b in LINE_B:
        for c in LINE_C:
            y0 = np.floor(ys - b * u - c * u * u).astype(int)
            ok = (y0 >= 0) & (y0 < H)
            hist = np.bincount(y0[ok], minlength=H)
            sm = hist[:-2] + hist[1:-1] + hist[2:]                     # ±1 px
            k = int(np.argmax(sm))
            if sm[k] > best[0]: best = (int(sm[k]), b, c, k + 1)
    n, b, c, y0 = best
    r = np.abs(ys - (y0 + b * u + c * u * u))
    cols = np.unique(xs[r <= 2].astype(int))
    if len(cols) < 2: return None
    gap = max(1, int(0.05 * W)); runs = []; s0 = cols[0]; prev = cols[0]
    for x in cols[1:]:
        if x - prev > gap: runs.append((s0, prev)); s0 = x
        prev = x
    runs.append((s0, prev))
    xl, xr = max(runs, key=lambda t: t[1] - t[0])
    cover = float(np.sum((cols >= xl) & (cols <= xr))) / W
    if cover < 0.15 or (xr - xl) < 0.4 * W: return None
    return dict(y0=float(y0), b=b, c=c, xl=int(xl), xr=int(xr), cover=round(cover, 3))

def line_y(L, x, W):
    u = np.asarray(x, float) / W - 0.5
    return L['y0'] + L['b'] * u + L['c'] * u * u

def cut_above(m, L):
    """Маска без усього, що вище дальньої лінії мінус запас."""
    H, W = m.shape; out = m.copy(); lim = line_y(L, np.arange(W), W) - LINE_MARGIN * H
    rows = np.arange(H)[:, None]; out[rows < lim[None, :]] = 0
    return out

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
        return _with_line(m, med), med
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
    return _with_line(_largest(g), med), med

field_mask.line = None          # остання знайдена дальня лінія (для env.json і перевірки позиції)

def _with_line(m, med):
    field_mask.line = far_line(med, m) if FIELD_LINE else None
    return cut_above(m, field_mask.line) if field_mask.line and FIELD_LINE_CUT else m


if __name__ == '__main__':
    # Preview: python src/fieldmask.py game.mp4  ->  fieldmask.jpg (field highlighted) + fieldmask.npy
    import sys
    m, med = field_mask(sys.argv[1])
    vis = med.copy(); vis[m == 0] = (vis[m == 0] * 0.3).astype(np.uint8)
    cv2.imwrite('fieldmask.jpg', cv2.resize(vis, (2048, int(2048 * vis.shape[0] / vis.shape[1]))))
    np.save('fieldmask.npy', m)
    print('field share of frame:', round(float(m.mean()), 3))
