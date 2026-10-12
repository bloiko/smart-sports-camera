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


def centre_line(fm, med):
    """Центральна лінія поля: найбільше білих пікселів уздовж майже вертикальної прямої біля середини поля.
    Перебір нахилів −0.6…0.6 (зсув рядків робить пряму вертикальною, далі сума по стовпцях). Повертає
    (x(y), опора в пікселях, нахил). Телефон стоїть біля центральної лінії, тож вона майже вертикальна і довга.
    Перевірка 2026-10-11: ворота, віддзеркалені через лінію з протилежних, — похибка 55–72 px на 3 матчах."""
    s = 2; fm2 = cv2.resize(fm, None, fx=1 / s, fy=1 / s, interpolation=cv2.INTER_NEAREST); m2 = cv2.resize(med, None, fx=1 / s, fy=1 / s)
    hsv = cv2.cvtColor(m2, cv2.COLOR_BGR2HSV)
    th = cv2.morphologyEx(hsv[..., 2], cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_RECT, (9, 1)))
    ridge = ((th > 35) & (hsv[..., 1] < 80) & (cv2.erode(fm2, np.ones((7, 7), np.uint8)) > 0)).astype(np.float32)
    H, W = ridge.shape; ys, xs = np.nonzero(fm2); mid = (xs.min() + xs.max()) / 2; span = xs.max() - xs.min()
    yc = (ys.min() + ys.max()) / 2; best = (0.0, 0, 0.0)
    for sh_k in np.linspace(-0.6, 0.6, 121):
        sh = cv2.warpAffine(ridge, np.float32([[1, sh_k, -sh_k * yc], [0, 1, 0]]), (W, H), flags=cv2.INTER_NEAREST)
        col = cv2.blur(sh.sum(0, keepdims=True), (3, 1))[0]
        lo, hi = int(mid - 0.2 * span), int(mid + 0.2 * span); x0 = lo + int(np.argmax(col[lo:hi]))
        if col[x0] > best[0]: best = (float(col[x0]), x0, sh_k)
    score, x0, sh_k = best
    return (lambda y: (x0 - sh_k * (y / s - yc)) * s), score * s, -sh_k


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


class LiveGoals:
    """Ворота під час трансляції: лише за вже побаченими гравцями, оцінка лише розширюється назовні.

    Теплова карта в секундах присутності (не відносно максимуму, як find_goals): область, де гравці провели
    ≥ thr_s секунд, лише росте, тож оцінка не «стрибає» назад. Великий стрибок назовні (> confirm_px)
    приймається, лише якщо повторився в двох оновленнях поспіль (викиди: люди біля кутового).
    Перевірка на 3 матчах (2026-10-11): див. specs/results.md, розділ live.
    2026-10-12: карта рахується на сітці 1/SCALE з власним (ненормованим) гауссовим ядром і нульовими краями —
    без cv2, щоб Swift-порт (ios/FolloCore LiveGoals.swift) давав ті самі числа; на телефоні це в 16 разів дешевше.
    """
    SCALE = 4

    def __init__(self, fmask, sample_dt, thr_s=3.0, sigma=25, confirm_px=150, centre=None, mirror_px=300, dy_max=60, prior=None):
        """centre: функція x(y) центральної лінії (centre_line). Ворота сторони, до якої гра ще не доходила,
        беруться віддзеркаленням з протилежної, якщо віддзеркалення далі назовні більш ніж на mirror_px.
        dy_max: зсув назовні приймається, лише якщо y кінчика змінився не більше ніж на dy_max px (кутові удари тягнуть
        кінчик до кутового прапорця — стрибок по y; уточнення воріт рухає його по x). 2026-10-12: без цього наприкінці
        матчів 2 і 3 похибка 185–335 px, з ним ≤ 68 px.
        prior: ворота з попереднього матчу на цьому ж полі (пам'ять поля) — оцінка є з першої секунди і далі уточнюється."""
        s = self.SCALE; H, W = fmask.shape
        self.fm, self.dt, self.thr, self.cp, self.dy = fmask, sample_dt, thr_s, confirm_px, dy_max
        self.raw = np.zeros(((H + s - 1) // s, (W + s - 1) // s), np.float64); self.pending = [None, None]
        self.best = np.array(prior, float) if prior is not None else None
        r = int(np.ceil(3 * sigma / s)); self.kernel = np.exp(-0.5 * (np.arange(-r, r + 1) * s / sigma) ** 2)
        self.centre, self.mx = centre, mirror_px

    def add(self, persons):
        H, W = self.fm.shape; s = self.SCALE
        for b in persons:
            fx, fy = (b[0] + b[2]) / 2, b[3]
            if b[4] >= 0.25 and 12 <= b[3] - b[1] <= 260:
                x, y = min(int(fx), W - 1), min(int(fy), H - 1)
                if self.fm[y, x]: self.raw[y // s, x // s] += self.dt

    def heat(self):
        k = self.kernel
        h = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 1, self.raw)
        return np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 0, h)

    def update(self):
        s = self.SCALE
        n, lab, st, _ = cv2.connectedComponentsWithStats((self.heat() > self.thr).astype(np.uint8), connectivity=8)
        if n < 2: return self.best
        ys, xs = np.nonzero(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
        l, r = xs <= xs.min() + 40 // s, xs >= xs.max() - 40 // s
        t = np.array([[xs[l].mean(), ys[l].mean()], [xs[r].mean(), ys[r].mean()]]) * s + (s - 1) / 2
        if self.best is None: self.best = t; return self.mirrored()
        for k, outward in ((0, t[0, 0] < self.best[0, 0]), (1, t[1, 0] > self.best[1, 0])):
            if not outward or abs(t[k, 1] - self.best[k, 1]) > self.dy: self.pending[k] = None; continue
            if abs(t[k, 0] - self.best[k, 0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            elif self.pending[k] is not None and abs(t[k, 0] - self.pending[k][0]) <= self.cp: self.best[k] = t[k]; self.pending[k] = None
            else: self.pending[k] = t[k]
        return self.mirrored()

    def mirrored(self):
        if self.best is None or self.centre is None: return self.best
        # власна оцінка може бути зміщена лише всередину (там, де ще ніхто не грав) → для кожної сторони
        # беремо зовнішнішу з власної та віддзеркаленої з протилежної сторони
        b = self.best.copy(); c = self.centre; o = self.best
        ml = 2 * c(o[1, 1]) - o[1, 0]; mr = 2 * c(o[0, 1]) - o[0, 0]
        if ml < o[0, 0] - self.mx: b[0] = (ml, o[1, 1])
        if mr > o[1, 0] + self.mx: b[1] = (mr, o[0, 1])
        return b
