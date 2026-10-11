"""Live-симулятор: віртуальна камера в реальному часі з бюджетом телефона і буфером затримки.

Як на телефоні під час трансляції:
- Детекція (етап 1, кешується в OUT/live_det.jsonl):
  * гравці — PLAYER_TILES плиток YOLO (PLAYER_IMGSZ) кожен PLAYER_EVERY-й кадр;
  * м'яч — одна плитка ROI×ROI пікселів джерела, збільшена в ROI_UP раза, моделлю BALL_MODEL кожен
    BALL_EVERY-й кадр. Плитка — навколо прогнозу м'яча (остання позиція + швидкість); якщо м'яч загублено —
    по черзі біля скупчень гравців і центру гри. М'яч поза полем або схожий на фон (медіана останніх кадрів)
    відкидається.
  Детекція не залежить від буфера, тому рахується один раз.
- Камера (етап 2) для кадру f бачить лише дані до кадру f + B (B — буфер затримки, глядач бачить
  трансляцію на B секунд пізніше). Ворота — goals.py лише за вже побаченими гравцями (перерахунок кожні
  10 с, до 30 с даних — без режиму воріт). Згладжування — гаусове, обрізане на майбутньому B.
  Жорсткі обмеження (м'яч, ворота в режимі воріт) з урахуванням досяжності: позиція кадру f має дозволяти
  виконати обмеження кадрів f..f+B з максимальною швидкістю.

Використання:
  python src/live_sim.py VIDEO OUT_DIR [--buffers 0,1,2,3,5] [--ref FINAL_DIR] [--checklist C.json] [--render B A-C]
  --ref: тека офлайн-версії (final_v03) для порівняння: м'яч з офлайн-треку в кадрі, гравці в кадрі.
  --render B A-C: відрендерити відрізок A–C (с) для буфера B → OUT/live_B{B}_{A}-{C}.mp4
"""
import json, math, os, sys, time, collections
import numpy as np, cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fieldmask import field_mask

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYER_EVERY, PLAYER_IMGSZ, PLAYER_TILES = 4, 1280, 2   # 2 плитки: на склеєній панорамі 4096 px далекі гравці
# удвічі дрібніші, ніж буде на 4K з телефона; одна плитка губила 40% далеких гравців (матч 2)
BALL_EVERY, ROI, ROI_UP, BALL_CONF, BALL_CONF_NEAR, LOST_ROIS = 2, 320, 2, 0.4, 0.25, 2
BALL_MODEL = os.path.join(ROOT, 'models', 'ball_v02.pt')
BG_EVERY_S, BG_N, BG_MIN = 3.0, 9, 15
CAM = dict(out_w=1920, out_h=1080, spread_k=1.4, focus_px=300, min_crop_w=[800, 1700], max_crop_w=[1600, 2800],
           ball_weight=0.7, ball_hold_s=0.6, smooth_s=0.8, max_speed=900, catch_k=2.5, margin=0.08,
           goal_zone=[0.08, 0.16], goal_attack_n=5, goal_box_k=0.1, goal_unc=80, goal_min_data_s=30, goal_every_s=10,
           # режим воріт вмикається не раніше ніж за 2 с: з 5 с камера показувала порожні ворота, поки гра в центрі (матч 2, 0:58)
           anticipate_s=2.0,
           lost_zoom=1.35,          # м'яч загублено → кадр ширше (матч 3: м'яч у кадрі 63% → 83%)
           confirm_s=0.6, confirm_px=200,   # м'яч приймається лише з другою детекцією поруч (спалахи смикали камеру)
           mirror=1,                # ворота ще не відвіданої сторони — віддзеркаленням через центральну лінію
           goal_hold_s=2.0,         # режим воріт тримається ще 2 с після атаки (гол матчу 1 без цього губився)
           border_shift_max=150)    # ворота під вигнутою межею панорами → кадр до 150 px до центру (матч 2, 3:38)


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


# ---------------------------------------------------------------- етап 1: детекція з бюджетом телефона
def detect(video, out_path):
    import torch
    from ultralytics import YOLO
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    pm, bm = YOLO('yolo11s.pt'), YOLO(BALL_MODEL)
    fm, _ = field_mask(video); fmd = cv2.dilate(fm, np.ones((41, 41), np.uint8))
    cap = cv2.VideoCapture(video); fps = cap.get(5); N = int(cap.get(7)); H, W = int(cap.get(4)), int(cap.get(3))
    bg_frames = collections.deque(maxlen=BG_N); last_bg = -1e9
    ball, ball_v, ball_f = None, np.zeros(2), -10 ** 9; centre = np.array([W / 2, H / 2]); scan = 0; hot = []
    black, last_ps = [], []; hist = collections.deque(maxlen=200); feet = []; hints = collections.deque(maxlen=20)

    def bg_diff(img, cx, cy):
        """Різниця з фоном (медіана останніх кадрів, зменшених удвічі) у точці; 99, якщо фону ще немає."""
        if len(bg_frames) < 3: return 99.0
        bgp = np.median(np.stack([fr[max(int(cy / 2) - 3, 0):int(cy / 2) + 4, max(int(cx / 2) - 3, 0):int(cx / 2) + 4] for fr in bg_frames]), 0)
        cur = img[max(int(cy) - 6, 0):int(cy) + 8, max(int(cx) - 6, 0):int(cx) + 8]
        if not bgp.size or not cur.size: return 99.0
        cur = cv2.resize(cur, (bgp.shape[1], bgp.shape[0]))
        return round(float(np.percentile(np.abs(cv2.cvtColor(cur, cv2.COLOR_BGR2GRAY).astype(int) - cv2.cvtColor(bgp.astype(np.uint8), cv2.COLOR_BGR2GRAY).astype(int)), 75)), 1)
    out = open(out_path, 'w'); t0 = time.time(); times = collections.defaultdict(float)
    for f in range(N):
        ok, img = cap.read()
        if not ok: break
        rec = {'frame': f}
        if f / fps - last_bg >= BG_EVERY_S:                       # фон: медіана останніх кадрів (зменшених)
            bg_frames.append(cv2.resize(img, (W // 2, H // 2))); last_bg = f / fps
        if f % PLAYER_EVERY == 0:
            t = time.time()
            tw = (W + 100) // PLAYER_TILES; ps = []
            for k in range(PLAYER_TILES):
                a = max(0, min(k * (tw - 100 // PLAYER_TILES), W - tw)) if PLAYER_TILES > 1 else 0; b_ = a + tw if PLAYER_TILES > 1 else W
                r = pm.predict(img[:, a:b_], imgsz=PLAYER_IMGSZ, conf=0.12, classes=[0, 32], device=dev, half=dev != 'cpu', verbose=False)[0]
                for bb, sc, cl in zip(r.boxes.xyxy.tolist(), r.boxes.conf.tolist(), r.boxes.cls.tolist()):
                    box = [round(v + (a if i % 2 == 0 else 0), 1) for i, v in enumerate(bb)] + [round(sc, 3)]
                    if cl == 0: ps.append(box)
                    elif sc >= 0.2:                               # підказка, де м'яч (той самий прохід, безкоштовно)
                        hx, hy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
                        if fm[min(int(hy), H - 1), min(int(hx), W - 1)] and bg_diff(img, hx, hy) >= BG_MIN: hints.append((hx, hy, f))
            rec['persons'] = ps; times['players'] += time.time() - t; last_ps = ps
            pl = np.array([((b[0] + b[2]) / 2, b[3]) for b in ps if b[4] >= 0.25 and fmd[min(int(b[3]), H - 1), min(int((b[0] + b[2]) / 2), W - 1)]])
            if len(pl):
                med = np.median(pl, 0); w = 1 / (1 + (np.linalg.norm(pl - med, axis=1) / 300) ** 2)
                centre = (pl * w[:, None]).sum(0) / w.sum()
                dens = (np.linalg.norm(pl[:, None] - pl[None], axis=2) < 250).sum(1)    # скупчення гравців
                hot = []
                for i in np.argsort(-dens):
                    if all(np.linalg.norm(pl[i] - h) > 300 for h in hot): hot.append(pl[i] - (0, 30))
                    if len(hot) == 3: break
                d = np.linalg.norm(pl - centre, axis=1); feet = [pl[i] - (0, 20) for i in np.argsort(d)[:6]]   # ноги біля центру гри
        if f % BALL_EVERY == 0:
            t = time.time()
            lost = (f - ball_f) / fps > 0.5
            if not lost: rois = [ball + ball_v * (f - ball_f)]
            else:
                # пошук: підказка з проходу гравців (клас «м'яч») → ноги гравців біля центру гри → скупчення;
                # 2 плитки за прохід, поки м'яч загублено
                cands = [np.array(h[:2]) for h in hints if f - h[2] <= PLAYER_EVERY * 2] + feet + hot + [centre]
                rois = []
                for _ in range(LOST_ROIS):
                    rois.append(np.array(cands[scan % len(cands)], float)); scan += 1
            bs = []; rec['roi'] = []
            for c in rois:
                x0 = int(np.clip(c[0] - ROI / 2, 0, W - ROI)); y0 = int(np.clip(c[1] - ROI / 2, 0, H - ROI)); rec['roi'].append([x0, y0])
                patch = cv2.resize(img[y0:y0 + ROI, x0:x0 + ROI], None, fx=ROI_UP, fy=ROI_UP, interpolation=cv2.INTER_CUBIC)
                r = bm.predict(patch, imgsz=ROI * ROI_UP, conf=0.1, device=dev, half=dev != 'cpu', verbose=False)[0]
                for bb, sc in zip(r.boxes.xyxy.tolist(), r.boxes.conf.tolist()):
                    bx0, by0, bx1, by1 = bb[0] / ROI_UP + x0, bb[1] / ROI_UP + y0, bb[2] / ROI_UP + x0, bb[3] / ROI_UP + y0
                    bs.append([round(bx0, 1), round(by0, 1), round(bx1, 1), round(by1, 1), round(sc, 3), bg_diff(img, (bx0 + bx1) / 2, (by0 + by1) / 2)])
            rec['balls'] = bs; times['ball'] += time.time() - t; times['ball_calls'] += len(rois)
            c = rois[0]
            # біля прогнозу достатньо меншої впевненості
            good = [bb for bb in bs if bb[4] >= (BALL_CONF_NEAR if not lost and np.hypot((bb[0] + bb[2]) / 2 - c[0], (bb[1] + bb[3]) / 2 - c[1]) < 60 else BALL_CONF)
                    and bb[5] >= BG_MIN and fm[min(int((bb[1] + bb[3]) / 2), H - 1), min(int((bb[0] + bb[2]) / 2), W - 1)]
                    and all(np.hypot((bb[0] + bb[2]) / 2 - q[0], (bb[1] + bb[3]) / 2 - q[1]) > 30 for q in black)]
            if good:
                pts = np.array([((bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2) for bb in good])
                ref = c if not lost else pts[np.argmax([bb[4] for bb in good])]
                k = int(np.argmin(np.linalg.norm(pts - ref, axis=1)))
                if lost or np.linalg.norm(pts[k] - c) < 350 * (f - ball_f) / BALL_EVERY:
                    if not lost: ball_v = 0.5 * ball_v + 0.5 * (pts[k] - ball) / max(1, f - ball_f)
                    else: ball_v = np.zeros(2)
                    ball, ball_f = pts[k], f; rec['ball'] = [round(float(v), 1) for v in ball]
                    hist.append((f, ball.copy()))
                    # «м'яч» 3 с на місці і поруч жодного гравця → нерухомий двійник (людина за полем, запасний м'яч)
                    old = [q for g, q in hist if f - g >= 3 * fps]
                    if old and all(np.linalg.norm(q - ball) < 25 for g, q in hist if f - g <= 3 * fps):
                        near = min((np.hypot(ball[0] - (bb[0] + bb[2]) / 2, ball[1] - bb[3]) / max(bb[3] - bb[1], 1) for bb in last_ps), default=99)
                        if near > 1.3:
                            black.append(ball.copy()); ball_f = -10 ** 9; hist.clear(); rec['black'] = rec.pop('ball')
        out.write(json.dumps(rec) + '\n')
        if f % 1000 == 0: print(f'  {f}/{N} {time.time() - t0:.0f} s', flush=True)
    out.close()
    n = f + 1
    print(f'detection: {time.time() - t0:.0f} s for {n} frames; players pass {times["players"] / (n / PLAYER_EVERY) * 1000:.0f} ms '
          f'every {PLAYER_EVERY} frames, ball ROI {times["ball"] / max(times["ball_calls"], 1) * 1000:.0f} ms x {times["ball_calls"] / (n / BALL_EVERY):.2f} '
          f'per pass every {BALL_EVERY} frames (on this Mac)')


# ---------------------------------------------------------------- етап 2: камера з буфером
def gaussw(n_past, n_future, sig):
    k = np.arange(-n_past, n_future + 1); return np.exp(-0.5 * (k / sig) ** 2)


def gauss_causal(v, r):
    """Згладжування рухомим середнім лише по минулому (r кадрів) — без заглядання вперед."""
    if r < 2: return v
    c = np.cumsum(np.r_[np.zeros(r), v]); out = (c[r:] - c[:-r]) / r
    out[:r] = [v[:i + 1].mean() for i in range(min(r, len(v)))]
    return out


def camera(det, video, B_s):
    cap = cv2.VideoCapture(video); fps = cap.get(5); W, H = int(cap.get(3)), int(cap.get(4))
    fm, med = field_mask(video); fmd = cv2.dilate(fm, np.ones((41, 41), np.uint8))
    content = med.max(axis=2) > 12
    top = np.array([np.argmax(c) if c.any() else 0 for c in content.T]); bot = np.array([H - np.argmax(c[::-1]) if c.any() else H for c in content.T])
    N = len(det); B = int(round(B_s * fps)); C = CAM

    def field_players(ps):
        o = [((b[0] + b[2]) / 2, b[3]) for b in ps if b[4] >= 0.25 and 12 <= b[3] - b[1] <= 260 and fmd[min(int(b[3]), H - 1), min(int((b[0] + b[2]) / 2), W - 1)]]
        return np.array(o) if o else np.zeros((0, 2))

    # ворота — лише за вже побаченими гравцями (LiveGoals: оцінка лише розширюється назовні), оновлення кожні goal_every_s
    from goals import LiveGoals, centre_line
    cline = None
    if C['mirror']:
        fm10, med10 = field_mask(video, until_s=10)             # лише перші 10 с трансляції
        cline = centre_line(fm10, med10)[0]
    lg = LiveGoals(fmd, PLAYER_EVERY / fps, centre=cline); goals_at = np.full((N, 2, 2), np.nan); seen_rows = []; G = None
    next_g = C['goal_min_data_s'] * fps
    for f in range(N):
        if 'persons' in det[f]: seen_rows.append({'frame': f, 'persons': det[f]['persons']}); lg.add(det[f]['persons'])
        if f >= next_g:
            g = lg.update()
            if g is not None: G = g.copy()
            next_g += C['goal_every_s'] * fps
        if G is not None: goals_at[f] = G

    # ціль камери на кожен кадр (лише з даних до цього кадру)
    depth = [150, 700]; ys = [b[3] for r in seen_rows[:400] for b in r['persons'] if b[4] >= 0.25]
    if len(ys) > 50: depth = [float(np.percentile(ys, 2)), float(np.percentile(ys, 98))]
    TX, TY, TW = np.zeros(N), np.zeros(N), np.zeros(N); GW = np.zeros(N); GI = np.full(N, -1)
    BX, BY = np.full(N, np.nan), np.full(N, np.nan)
    pc, spread = np.array([W / 2, H / 2]), W / 2; last_ball, last_ball_f = None, -10 ** 9; zone_hist = [[], []]; zn = [0, 0]
    # підтвердження м'яча: ще одна детекція в межах confirm_s до (або, з буфером, після) і поруч — інакше спалах
    balls = [(f, np.array(det[f]['ball'])) for f in range(N) if 'ball' in det[f]]; okb = set()
    win = int(C['confirm_s'] * fps); fut = min(B, win)
    for i, (f, p_) in enumerate(balls):
        for j in range(max(0, i - 6), min(len(balls), i + 7)):
            g, q = balls[j]
            if j != i and -win <= g - f <= fut and np.linalg.norm(q - p_) < C['confirm_px']: okb.add(f); break
    for f in range(N):
        r = det[f]
        if 'ball' in r and f in okb: last_ball, last_ball_f = np.array(r['ball']), f; BX[f], BY[f] = r['ball']
        if 'persons' in r:
            pl = field_players(r['persons'])
            if len(pl):
                m = np.median(pl, 0); w = 1 / (1 + (np.linalg.norm(pl - m, axis=1) / C['focus_px']) ** 2)
                pc = (pl * w[:, None]).sum(0) / w.sum(); spread = 2.5 * np.sqrt((w * (pl[:, 0] - pc[0]) ** 2).sum() / w.sum())
            G = goals_at[f]
            if not np.isnan(G).any():
                D = np.linalg.norm(G[1] - G[0])
                zn = [int((np.linalg.norm(pl - G[k], axis=1) < C['goal_zone'][1] * D).sum()) if len(pl) else 0 for k in range(2)]
                for k in range(2): zone_hist[k].append(zn[k])
        ball_ok = last_ball is not None and (f - last_ball_f) / fps <= C['ball_hold_s']
        c = C['ball_weight'] * last_ball + (1 - C['ball_weight']) * pc if ball_ok else pc
        lo = np.interp(c[1], depth, C['min_crop_w']); hi = np.interp(c[1], depth, C['max_crop_w'])
        cw = np.clip(spread * C['spread_k'], lo, hi)
        if not ball_ok:                                           # м'яч загублено → ширше (м'яч, найімовірніше, поруч)
            lost_s = (f - last_ball_f) / fps
            cw = min(cw * (1 + (C['lost_zoom'] - 1) * min(1.0, (lost_s - C['ball_hold_s']) / 1.0)), hi * C['lost_zoom'])
        G = goals_at[f]
        if not np.isnan(G).any():
            D = np.linalg.norm(G[1] - G[0]); focus = last_ball if ball_ok else pc; best = (0.0, -1)
            for k in range(2):
                d = np.linalg.norm(focus - G[k]) / D
                wk = float(np.clip((C['goal_zone'][1] - d) / (C['goal_zone'][1] - C['goal_zone'][0]), 0, 1))
                base = np.median(zone_hist[k]) if zone_hist[k] else 0
                wa = float(np.clip((zn[k] - base - 1) / (C['goal_attack_n'] - 1), 0, 1))
                if ball_ok and d > C['goal_zone'][1]: wa *= 0.3
                if max(wk, wa) > best[0]: best = (max(wk, wa), k)
            GW[f], GI[f] = best
            if best[0] > 0:
                g = G[best[1]]; hw = C['goal_box_k'] * np.interp(g[1], depth, C['min_crop_w']) + C['goal_unc']
                pts = np.array([g - (hw, hw * 0.6), g + (hw, hw * 0.6)] + ([focus] if ball_ok else []))
                need = (pts[:, 0].max() - pts[:, 0].min()) * (1 + 2 * C['margin']) * 1.1
                gc = np.array([(pts[:, 0].min() + pts[:, 0].max()) / 2, (pts[:, 1].min() + pts[:, 1].max()) / 2])
                c = (1 - best[0]) * c + best[0] * gc; cw = (1 - best[0]) * cw + best[0] * np.clip(need, lo, hi)
        TX[f], TY[f], TW[f] = c[0], c[1], cw

    # режим воріт з гістерезисом (вмикання видно лише після B кадрів затримки — це нормально)
    GON = np.zeros(N, bool); on = False; low = 0
    for f in range(N):
        if not on: on = GW[f] > 0.5; low = 0
        else:                                                     # вимикаємо, лише якщо сигнал слабкий goal_hold_s поспіль
            low = low + 1 if GW[f] <= 0.25 else 0
            on = low < C['goal_hold_s'] * fps
        GON[f] = on
    # випередження: з буфером B режим воріт, що ввімкнеться в межах min(B, anticipate_s), вмикаємо вже зараз (камера повертає до воріт
    # до удару, а не після); ворота епізоду — ті, що будуть
    if B > 0:
        GON2, GI2 = GON.copy(), GI.copy(); nxt = -1
        for f in range(N - 1, -1, -1):
            if GON[f]: nxt = f
            elif nxt >= 0 and nxt - f <= min(B, C['anticipate_s'] * fps): GON2[f] = True; GI2[f] = GI[nxt]
        GON, GI = GON2, GI2

    # вихід: для кадру f — лише цілі до f + B
    asp = C['out_h'] / C['out_w']; sig = C['smooth_s'] * fps; P = int(3 * sig)
    X, Y, CW = np.zeros(N), np.zeros(N), np.zeros(N); YLO, YHI = np.full(N, np.inf), np.full(N, -np.inf)
    LOX, HIX = np.full(N, -np.inf), np.full(N, np.inf)            # допустимі межі центру кадру по x (м'яч, ворота)
    vmax, vcatch = C['max_speed'] / fps, C['catch_k'] * C['max_speed'] / fps
    for f in range(N):
        a, b = max(0, f - P), min(N - 1, f + min(B, P))
        w = gaussw(f - a, b - f, sig)
        x, y, cw = (TX[a:b + 1] * w).sum() / w.sum(), (TY[a:b + 1] * w).sum() / w.sum(), (TW[a:b + 1] * w).sum() / w.sum()
        # обмеження кадрів f..f+B з урахуванням досяжності (м'яч і ворота мають бути в кадрі)
        lo_x, hi_x, need_w = -np.inf, np.inf, 0.0; ylo, yhi = np.inf, -np.inf     # ylo/yhi: що має бути в кадрі по y
        for k in range(0, B + 1, 2):
            g = f + k
            if g >= N: break
            pts = []
            j = g
            while j >= max(0, g - int(0.3 * fps)) and np.isnan(BX[j]): j -= 1
            if j >= 0 and not np.isnan(BX[j]): pts.append((BX[j], BY[j], 0))
            if GON[g] and GI[g] >= 0 and not np.isnan(goals_at[g]).any():
                gg = goals_at[g][GI[g]]; hw = C['goal_box_k'] * np.interp(gg[1], depth, C['min_crop_w']) + C['goal_unc']; pts.append((gg[0], gg[1], hw))
            for px, py, hw in pts:
                m = C['margin'] * cw
                l, h = px + hw + m - cw / 2 - vcatch * k, px - hw - m + cw / 2 + vcatch * k
                if l <= h: lo_x, hi_x = max(lo_x, l), min(hi_x, h)
                need_w = max(need_w, 2 * hw + 2 * m)
                if k == 0:                                        # по вертикалі: верх і низ точки (воріт) з запасом
                    hh = hw * 0.6 + (C['goal_unc'] * 0.4 if hw else 0)
                    ylo, yhi = min(ylo, py - hh - m * asp), max(yhi, py + hh + m * asp)
        cw = max(cw, need_w)
        if lo_x <= hi_x: x = float(np.clip(x, lo_x, hi_x))
        if f:                                                     # плавність: обмеження швидкості відносно попереднього кадру
            lim = vcatch if (lo_x > -np.inf) else vmax
            x = X[f - 1] + np.clip(x - X[f - 1], -lim, lim); y = Y[f - 1] + np.clip(y - Y[f - 1], -vmax, vmax)
            cw = CW[f - 1] + np.clip(cw - CW[f - 1], -vmax, vmax)
        X[f], Y[f], CW[f] = x, y, cw; YLO[f], YHI[f] = ylo, yhi
        if lo_x <= hi_x: LOX[f], HIX[f] = lo_x, hi_x
    CW = np.minimum(CW, H / asp); CH = CW * asp
    X = np.clip(X, CW / 2, W - CW / 2); Y = Y - CH * 0.08
    for f in range(N):                                            # вертикальні обмеження (м'яч, ворота)
        if YLO[f] < np.inf:
            if YHI[f] - YLO[f] > CH[f]: CH[f] = YHI[f] - YLO[f]; CW[f] = CH[f] / asp
            Y[f] = np.clip(Y[f], YHI[f] - CH[f] / 2, YLO[f] + CH[f] / 2)
    Y = gauss_causal(Y, int(0.2 * fps)); CW = np.minimum(CW, H / asp); CH = CW * asp
    # біля кінців поля вигнута межа панорами штовхає кадр униз → наближаємо (як border zoom у follow.py), лише по минулому
    ZF = np.ones(N)
    for f in range(N):
        a, b = int(max(0, X[f] - CW[f] / 2)), int(min(W, X[f] + CW[f] / 2))
        push = (top[a:b].max() - (Y[f] - CH[f] / 2)) / CH[f]
        if push > 0.2 and not GON[f]: ZF[f] = max(0.75, 1 - (push - 0.2))   # у режимі воріт не звужуємо: обріже ворота
    ZF = gauss_causal(ZF, int(0.6 * fps)); CW = CW * ZF; CH = CW * asp
    # верх воріт вище за вигнуту чорну межу над краєм кадру → зсуваємо кадр до центру панорами (там межа нижча).
    # Потрібний зсув рахуємо для кожного кадру, далі максимум у вікні [f − 0.5 с, f + буфер] і середнє по минулих
    # 0.5 с: плавно і не менше потрібного. Горизонтальні обмеження (м'яч, ворота) не порушуємо.
    NS = np.zeros(N)
    for f in range(N):
        if YLO[f] < np.inf and GON[f] and GI[f] >= 0:             # лише ворота біля краю панорами
            step = 10 if GI[f] == 0 else -10; sh = 0
            for _ in range(C['border_shift_max'] // 10):
                a, b = int(max(0, X[f] + sh - CW[f] / 2)), int(min(W, X[f] + sh + CW[f] / 2))
                if top[a:b].max() <= YLO[f]: break
                sh += step
            NS[f] = sh
    if NS.any():
        h = int(0.5 * fps); la = min(B, int(2 * fps)); mag = np.abs(NS); M = np.zeros(N)
        for f in range(N): M[f] = mag[max(0, f - h):f + la + 1].max()
        sgn = np.where(GI == 1, -1.0, 1.0); X = np.clip(X + sgn * gauss_causal(M, h), LOX, HIX)
    for f in range(N):                                            # усередині зображення
        a, b = int(X[f] - CW[f] / 2), int(X[f] + CW[f] / 2); t, bt = top[max(a, 0):b].max(), bot[max(a, 0):b].min()
        if bt - t < CH[f]: CH[f] = bt - t; CW[f] = CH[f] / asp; X[f] = np.clip(X[f], CW[f] / 2, W - CW[f] / 2)
        Y[f] = np.clip(Y[f], t + CH[f] / 2, bt - CH[f] / 2)
    G = goals_at[-1]
    return dict(X=X, Y=Y, CW=CW, CH=CH, FPS=fps, GON=GON, GI=GI, BX=BX, BY=BY, GOALS=G, GOAL_DIST=float(np.linalg.norm(G[1] - G[0])),
                goals_first_s=float(np.argmax(~np.isnan(goals_at[:, 0, 0])) / fps))


# ---------------------------------------------------------------- метрики
def metrics(path, ref_dir, video):
    X, Y, CW, CH, fps = path['X'], path['Y'], path['CW'], path['CH'], float(path['FPS'])
    out = {}
    v = np.abs(np.diff(X)) * fps; acc = np.abs(np.diff(X, 2)) * fps * fps
    out.update(pan_mean=round(float(v.mean()), 1), pan_over_900=round(float((v > 900).mean() * 100), 2), acc_p95=round(float(np.percentile(acc, 95))))
    if ref_dir:
        tr = {int(k): v for k, v in json.load(open(os.path.join(ref_dir, 'ball_track.json'))).items()}
        ins = [X[f] - CW[f] / 2 <= x <= X[f] + CW[f] / 2 and Y[f] - CH[f] / 2 <= y <= Y[f] + CH[f] / 2 for f, (x, y) in tr.items() if f < len(X)]
        out['ref_ball_in_crop'] = round(float(np.mean(ins)), 3)
        early = [v for (f, _), v in zip([(f, 0) for f in tr if f < len(X)], ins) if f < 120 * fps]
        out['first2min_ball_in_crop'] = round(float(np.mean(early)), 3) if early else None
        det = os.path.join(os.path.dirname(ref_dir.rstrip('/')), 'detections.jsonl')
        fm = cv2.dilate(field_mask(video)[0], np.ones((41, 41), np.uint8)); H, W = fm.shape; pin = []
        for l in open(det):
            r = json.loads(l); f = r['frame']
            if f >= len(X): continue
            pl = [((b[0] + b[2]) / 2) for b in r['persons'] if b[4] >= 0.25 and 12 <= b[3] - b[1] <= 260 and fm[min(int(b[3]), H - 1), min(int((b[0] + b[2]) / 2), W - 1)]]
            if pl: pin.append(np.mean([(X[f] - CW[f] / 2 <= x <= X[f] + CW[f] / 2) for x in pl]))
        out['players_in_crop'] = round(float(np.mean(pin)), 3)
    return out


def main():
    video, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
    det_path = os.path.join(out, 'live_det.jsonl')
    if not os.path.exists(det_path + '.done'):
        detect(video, det_path); open(det_path + '.done', 'w').close()
    det = [json.loads(l) for l in open(det_path)]
    print(f'live ball found on {np.mean(["ball" in r for r in det if r["frame"] % BALL_EVERY == 0]) * 100:.1f}% of ball passes')
    ref = arg('--ref'); rows = []
    if ref:
        p = np.load(os.path.join(ref, 'camera_path.npz'))
        rows.append(('offline v0.3', dict(X=p['X'], Y=p['Y'], CW=p['CW'], CH=p['CH'], FPS=p['FPS']), os.path.join(ref, 'camera_path.npz')))
    for i, a_ in enumerate(sys.argv):
        if a_ == '--set': k_, v_ = sys.argv[i + 1].split('=', 1); CAM[k_] = json.loads(v_)
    for B in [float(b) for b in arg('--buffers', '0,1,2,3,5').split(',')]:
        t = time.time(); path = camera(det, video, B)
        npz = os.path.join(out, f'live_B{B:g}.npz'); np.savez(npz, **{k: v for k, v in path.items()})
        rows.append((f'live, buffer {B:g} s', path, npz)); print(f'  camera B={B:g}s in {time.time() - t:.0f} s; goals known after {path["goals_first_s"]:.0f} s: {np.round(path["GOALS"]).tolist()}')
    import subprocess
    for name, path, npz in rows:
        m = metrics(path, ref, video)
        ck = ''
        if arg('--checklist'):
            r = subprocess.run([sys.executable, os.path.join(ROOT, 'src', 'check_goals.py'), npz, arg('--checklist')], capture_output=True, text=True).stdout
            ck = f"checklist {r.count('PASS') - r.count('ALL PASS')}/{r.count('PASS') - r.count('ALL PASS') + r.count('FAIL') - r.count('SOME FAIL')}"
        print(f'{name:20s} ' + ' '.join(f'{k} {v}' for k, v in m.items()) + f' {ck}', flush=True)
    if '--render' in sys.argv:
        from closeup import render
        i = sys.argv.index('--render'); B = float(sys.argv[i + 1]); a, c = map(float, sys.argv[i + 2].split('-'))
        p = np.load(os.path.join(out, f'live_B{B:g}.npz'))
        render(video, (p['X'], p['Y'], p['CW'], p['CH']), os.path.join(out, f'live_B{B:g}_{a:g}-{c:g}.mp4'), a, c, (1920, 1080), f'LIVE buffer {B:g}s')


if __name__ == '__main__':
    main()
