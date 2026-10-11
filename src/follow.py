"""Крок 2: віртуальна камера.
Читає detections.jsonl, будує траєкторію камери і рендерить:
  out_follow.mp4  — 1920x1080 ролик, що слідує за грою
  out_debug.mp4   — панорама зі зменшенням, рамка камери, гравці, м'яч
  metrics.json    — метрики якості
Використання: python3 follow.py video.mp4 detections.jsonl [out_dir] [--balls FILE] [--goals CHECKLIST.json]
              [--no-render | --debug-only | --no-debug] [--range A-B] [--set key=value ...]
v0.3: режим воріт (ворота знаходить goals.py), м'яч як жорстке обмеження, кращий фільтр запасних м'ячів.
"""
import json, sys, subprocess, math
from venc import video_args
import numpy as np, cv2

SRC, DET = sys.argv[1], sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else '.'
import os; os.makedirs(OUT, exist_ok=True)

# ---------- параметри (усе, що варто крутити) ----------
CFG = dict(
    out_w=1920, out_h=1080,
    depth_y=[150, 700],                 # y дальньої і ближньої бровки в панорамі
    min_crop_w=[800, 1700], max_crop_w=[1600, 2800],  # зум залежно від глибини і розкиду гравців
    spread_k=1.4,
    focus_px=300,                       # радіус «центру гри» навколо медіани гравців                       # crop_w = spread гравців * k
    static_ball_px=25, static_ball_share=0.15,  # м'яч, що стоїть на місці так часто, — запасний біля бровки
    static_window_s=10, static_span_s=2.0,  # або лежить на місці ≥ 2 с (у вікні ±10 с)...
    static_player_rel=1.3,              # ...і найближчий гравець далі за 1.3 його зросту (м'яч на розіграші не відкидаємо)
    static_spot_s=60,                   # або з'являється на тому самому місці ≥ 10 разів упродовж ≥ 60 с
    goal_attack_n=5,                    # атака: у зоні воріт на стільки гравців більше, ніж зазвичай (медіана)
    ball_gate_px=350,                   # макс. стрибок м'яча між відліками (у пікселях панорами)
    ball_weight=0.7,
    ball_bg_min=15,                     # мін. різниця з фоном (ball_bgdiff.py): букви на газоні 6–11, м'ячі ≥ 20
    window_ball_conf=0.4,               # поріг для м'ячів зі збільшеного вікна                    # наскільки м'яч тягне камеру (решта — гравці)
    smooth_sigma_s=0.8,                 # згладжування (с), двостороннє — без запізнення
    max_speed_px_s=900,                 # обмеження швидкості панорамування
    dead_zone_px=60,                    # дрібні рухи цілі ігноруються
    # v0.3: режим воріт (F7) і м'яч як жорстке обмеження
    ball_fill_s=1.5,                    # дірки в треку м'яча до стількох секунд заповнюються інтерполяцією
    ball_margin=0.08,                   # м'яч не ближче за цю частку ширини кадру до його краю
    goal_zone=[0.08, 0.16],             # частка відстані між воротами: ближче — повний режим воріт, далі — вимкнено
    goal_box_k=0.1,                     # півширина «рота» воріт = k * min_crop_w на глибині воріт
    catch_speed_k=2.5,                  # після обмежень швидкість камери не більша за k * max_speed_px_s
    border_push=0.2, border_zoom_min=0.75,  # кадр зсунутий межею панорами вниз > 20% висоти → наближення до 75%
    goal_unc_px=80,                     # запас навколо автоматично знайдених воріт (похибка goals.py)
    goal_crop_k=1.0,                    # у режимі воріт кадр може бути ширшим за max_crop_w у стільки разів
)

# перевизначити параметри з командного рядка: --set ball_weight=0.5 --set goal_zone=[0.1,0.2]
for _k, _a in enumerate(sys.argv):
    if _a == '--set':
        _n, _v = sys.argv[_k + 1].split('=', 1); CFG[_n] = json.loads(_v)

cap = cv2.VideoCapture(SRC)
W, H = int(cap.get(3)), int(cap.get(4))
FPS = cap.get(5); N = int(cap.get(7))
import os
def _bg(path):            # v0.3: якщо є path.bg.jsonl (ball_bgdiff.py) — беремо його: там різниця з фоном
    p = path.rsplit('.', 1)[0] + '.bg.jsonl'
    return p if os.path.exists(p) and os.path.getmtime(p) >= os.path.getmtime(path) else path
def _not_bg(b):           # детекція, що збігається з фоном (буква на газоні, лінія), — не м'яч
    return len(b) < 6 or b[5] >= CFG['ball_bg_min']
DET = _bg(DET)
rows = [json.loads(l) for l in open(DET)]
for r in rows: r['balls'] = [b for b in r['balls'] if _not_bg(b)]
# v0.2: додаткові детекції м'яча зі збільшеного вікна (ball_window.py)
if '--balls' in sys.argv:
    extra = {}
    for l in open(_bg(sys.argv[sys.argv.index('--balls') + 1])):
        r = json.loads(l); extra[r['frame']] = [b for b in r['balls'] if b[4] >= CFG['window_ball_conf'] and _not_bg(b)]
    for r in rows: r['balls'] = r['balls'] + extra.get(r['frame'], [])
print('detections:', DET, flush=True)
frames = np.array([r['frame'] for r in rows])
N = min(N, int(frames[-1]) + 1)   # дозволяє тестувати на частково обробленому відео

def center(b): return ((b[0]+b[2])/2, (b[1]+b[3])/2)
def feet(b): return ((b[0]+b[2])/2, b[3])

# ---------- 1. гравці: прибираємо глядачів/людей поза полем ----------
from fieldmask import field_mask
FMASK = cv2.dilate(field_mask(SRC)[0], np.ones((41, 41), np.uint8))

def field_players(persons, with_h=False):
    pts = []
    for b in persons:
        h = b[3]-b[1]
        if b[4] < 0.25 or h < 12 or h > 260: continue
        fx, fy = feet(b)
        if not FMASK[min(int(fy), H-1), min(int(fx), W-1)]: continue   # глядачі, лавки, люди за полем
        pts.append((fx, fy, h) if with_h else (fx, fy))
    return np.array(pts) if pts else np.zeros((0, 3 if with_h else 2))

def player_dist_rel(persons, p):
    """Відстань від точки до найближчого гравця у його зростах (не залежить від глибини)."""
    pl = field_players(persons, with_h=True)
    if not len(pl): return 99.0
    d = np.linalg.norm(pl[:, :2] - np.array(p), axis=1); k = int(np.argmin(d))
    return float(d[k] / pl[k, 2])

# глибина поля з даних: y дальніх і ближніх гравців (замість ручного depth_y)
_feet_y = [feet(b)[1] for r in rows for b in r['persons'] if b[4] >= 0.25 and FMASK[min(int(feet(b)[1]), H-1), min(int(feet(b)[0]), W-1)]]
if len(_feet_y) > 50:
    CFG['depth_y'] = [float(np.percentile(_feet_y, 2)), float(np.percentile(_feet_y, 98))]
print('depth_y', [round(v) for v in CFG['depth_y']], flush=True)

# ---------- 2. м'яч: фільтр нерухомих (запасні м'ячі) + зв'язування в трек ----------
all_balls = [(i, center(b), b[4]) for i, r in enumerate(rows) for b in r['balls']]
static = []
if all_balls:
    P = np.array([p for _, p, _ in all_balls])
    for p in P:
        near = np.linalg.norm(P - p, axis=1) < CFG['static_ball_px']
        if near.sum() > CFG['static_ball_share'] * len(rows): static.append(p)
    # v0.3: «точка» — м'яч знову і знову лежить на тому самому місці впродовж ≥ static_spot_s
    # (запасний біля кутового — так; м'яч у грі через ту саму точку лише пролітає)
    Rf = np.array([frames[i] for i, _, _ in all_balls]); Ri = np.array([i for i, _, _ in all_balls])
    REL = np.array([player_dist_rel(rows[i]['persons'], p) for i, p, _ in all_balls])   # один раз на детекцію
    for p in P:
        near = np.linalg.norm(P - p, axis=1) < CFG['static_ball_px']
        if near.sum() >= 10 and (Rf[near].max() - Rf[near].min()) / FPS >= CFG['static_spot_s']:
            ri = set(Ri[near].tolist())          # лежить, а не пролітає: є і в сусідньому відліку на тому ж місці
            lying = np.mean([(r - 1 in ri) or (r + 1 in ri) for r in Ri[near]]) >= 0.6
            # і поруч немає гравця (повільний м'яч біля дальньої бровки теж «лежить», але біля ніг гравця)
            alone = np.median(REL[near]) > CFG['static_player_rel']
            if lying and alone: static.append(p)
static = np.array(static) if static else np.zeros((0, 2))

# v0.3: локально нерухомі м'ячі — запасний м'яч біля кутового детектор бачить уривками,
# тож глобальний фільтр його пропускає; критерій: лежить на місці ≥ static_span_s і поруч нікого
local_static = set()
if all_balls:
    R = np.array([i for i, _, _ in all_balls]); _step = max(1, int(np.median(np.diff(frames)))) if len(frames) > 1 else 1
    win = int(CFG['static_window_s'] * FPS / _step)
    for k, (i, p, _) in enumerate(all_balls):
        m = (np.abs(R - i) <= win) & (np.linalg.norm(P - np.array(p), axis=1) < CFG['static_ball_px'])
        span = (frames[R[m].max()] - frames[R[m].min()]) / FPS
        if span >= CFG['static_span_s'] and len(np.unique(R[m])) >= 3:
            if REL[k] > CFG['static_player_rel']: local_static.add((i, p))

def is_static(p, i=None):
    if i is not None and (i, p) in local_static: return True
    p = np.array(p)
    return len(static) and np.min(np.linalg.norm(static - p, axis=1)) < CFG['static_ball_px'] * 1.5

ball = [None] * len(rows)
last, last_i = None, -999
for i, r in enumerate(rows):
    cands = [(center(b), b[4]) for b in r['balls'] if not is_static(center(b), i)]
    if not cands: continue
    if last is not None and i - last_i <= 10:
        gate = CFG['ball_gate_px'] * (i - last_i)
        cands = [c for c in cands if math.dist(c[0], last) < gate]
        if not cands: continue
        p = min(cands, key=lambda c: math.dist(c[0], last))[0]
    else:
        p = max(cands, key=lambda c: c[1])[0]
    ball[i] = p; last, last_i = p, i
# одиночні «спалахи» без сусідів — ймовірно хибні
for i in range(len(ball)):
    if ball[i] is not None:
        nb = [j for j in range(max(0, i-3), min(len(ball), i+4)) if j != i and ball[j] is not None]
        if not nb: ball[i] = None

json.dump({str(rows[i]['frame']): ball[i] for i in range(len(rows)) if ball[i] is not None}, open(f'{OUT}/ball_track.json', 'w'))

# короткі дірки треку: лінійна інтерполяція (для обмежень і режиму воріт, не для метрик)
ball_f = list(ball)
_known = [i for i in range(len(ball)) if ball[i] is not None]
for a, b in zip(_known, _known[1:]):
    if 1 < b - a and (frames[b] - frames[a]) / FPS <= CFG['ball_fill_s']:
        for j in range(a + 1, b):
            t = (frames[j] - frames[a]) / (frames[b] - frames[a])
            ball_f[j] = tuple(np.array(ball[a]) + t * (np.array(ball[b]) - np.array(ball[a])))

# ---------- 2b. ворота: автоматично за «хмарою гри» (goals.py) або з файлу (--goals, для тестів) ----------
if '--goals' in sys.argv:
    _g = json.load(open(sys.argv[sys.argv.index('--goals') + 1]))['goals']
    GOALS = [np.array(_g['left'], float), np.array(_g['right'], float)]; GOAL_UNC = 0.0
else:
    from goals import find_goals
    GOALS = find_goals(rows, FMASK)[0]; GOAL_UNC = CFG['goal_unc_px']   # авто — з запасом на похибку
GOAL_DIST = float(np.linalg.norm(GOALS[1] - GOALS[0])) if GOALS else W
print('goals', [[round(v) for v in g] for g in GOALS], flush=True)

def goal_box(g):          # півширина/піввисота зони «роту» воріт з урахуванням глибини і похибки пошуку
    hw = CFG['goal_box_k'] * np.interp(g[1], CFG['depth_y'], CFG['min_crop_w'])
    return hw + GOAL_UNC, hw * 0.6 + GOAL_UNC

# атака: скільки гравців у зоні кожних воріт; «зазвичай» (воротар, люди біля кутового) = медіана за відео
def zone_players(pl, g): return pl[np.linalg.norm(pl - g, axis=1) < CFG['goal_zone'][1] * GOAL_DIST] if len(pl) else pl
_zn = np.array([[len(zone_players(field_players(r['persons']), g)) for g in GOALS] for r in rows]) if GOALS else np.zeros((len(rows), 0))
ZONE_BASE = np.median(_zn, axis=0) if len(GOALS) else []
print('players in goal zones, usual:', list(ZONE_BASE), flush=True)

# ---------- 3. ціль камери на кожному відліку ----------
tx, ty, tw, gmode = [], [], [], []
for i, r in enumerate(rows):
    pl = field_players(r['persons'])
    if len(pl):
        # гравці ближче до медіани важать більше (центр «гри», а не крайні)
        med = np.median(pl, axis=0)
        d = np.linalg.norm(pl - med, axis=1)
        w = 1 / (1 + (d / CFG['focus_px']) ** 2)
        pc = (pl * w[:, None]).sum(0) / w.sum()
        spread = 2.5 * np.sqrt((w * (pl[:, 0] - pc[0]) ** 2).sum() / w.sum())   # зважений розкид навколо центру гри
    else:
        pc, spread = np.array([W/2, H/2]), W
    if ball[i] is not None:
        b = np.array(ball[i])
        c = CFG['ball_weight'] * b + (1 - CFG['ball_weight']) * pc
    else:
        c = pc
    # перспектива: далеко (малий y) гравці дрібні → кадр має бути вужчим (сильніший зум)
    lo = np.interp(c[1], CFG['depth_y'], CFG['min_crop_w']); hi = np.interp(c[1], CFG['depth_y'], CFG['max_crop_w'])
    cw = np.clip(spread * CFG['spread_k'], lo, hi)
    # режим воріт: м'яч (або центр гри) близько до воріт → у кадрі і ворота, і м'яч
    g_w, g_i = 0.0, -1
    focus = np.array(ball_f[i]) if ball_f[i] is not None else pc
    zone = (CFG['goal_zone'][1] - CFG['goal_zone'][0])
    for k, g in enumerate(GOALS):
        d = np.linalg.norm(focus - g) / GOAL_DIST
        wk = float(np.clip((CFG['goal_zone'][1] - d) / zone, 0, 1))
        # атака без видимого м'яча: у зоні воріт помітно більше гравців, ніж зазвичай
        wa = float(np.clip((_zn[i, k] - ZONE_BASE[k] - 1) / (CFG['goal_attack_n'] - 1), 0, 1))
        if ball_f[i] is not None and d > CFG['goal_zone'][1]: wa *= 0.3       # м'яч видно, і він далеко — довіряємо м'ячу
        if max(wk, wa) > g_w: g_w, g_i = max(wk, wa), k
    if g_w > 0:
        g = GOALS[g_i]; hw, hh = goal_box(g)
        zp = zone_players(pl, g)
        pts = np.array([g - (hw, hh), g + (hw, hh)] + ([focus] if ball_f[i] is not None else [])
                       + ([zp.mean(0)] if len(zp) else []))
        x0, x1 = pts[:, 0].min(), pts[:, 0].max()
        need = (x1 - x0) * (1 + 2 * CFG['ball_margin']) * 1.1
        gc = np.array([(x0 + x1) / 2, (pts[:, 1].min() + pts[:, 1].max()) / 2])
        c = (1 - g_w) * c + g_w * gc
        # у режимі воріт кадр тісний навколо дії біля воріт, а не навколо розкиду всієї команди
        cw = (1 - g_w) * cw + g_w * np.clip(need, lo, hi * CFG['goal_crop_k'])
    gmode.append((g_w, g_i))
    tx.append(c[0]); ty.append(c[1])
    tw.append(cw)

# ---------- 4. на кожен кадр + згладжування ----------
allf = np.arange(N)
X = np.interp(allf, frames, tx); Y = np.interp(allf, frames, ty); CW = np.interp(allf, frames, tw)

def dead_zone(s, dz):
    out = s.copy(); cur = s[0]
    for k in range(len(s)):
        if abs(s[k] - cur) > dz: cur = s[k] - math.copysign(dz, s[k] - cur)
        out[k] = cur
    return out

def gauss(s, sigma_frames):
    r = int(sigma_frames * 3); k = np.exp(-0.5 * (np.arange(-r, r+1) / sigma_frames) ** 2); k /= k.sum()
    return np.convolve(np.pad(s, r, mode='edge'), k, mode='valid')

def speed_limit(s, vmax):
    f = s.copy()
    for k in range(1, len(f)): f[k] = f[k-1] + np.clip(f[k] - f[k-1], -vmax, vmax)
    b = f.copy()
    for k in range(len(b)-2, -1, -1): b[k] = b[k+1] + np.clip(b[k] - b[k+1], -vmax, vmax)
    return (f + b) / 2

sig = CFG['smooth_sigma_s'] * FPS
X = speed_limit(gauss(dead_zone(X, CFG['dead_zone_px']), sig), CFG['max_speed_px_s'] / FPS)
Y = gauss(Y, sig * 2)
CW = gauss(CW, sig * 3)

CH = CW * CFG['out_h'] / CFG['out_w']
CH = np.minimum(CH, H); CW = CH * CFG['out_w'] / CFG['out_h']
X = np.clip(X, CW/2, W - CW/2); Y = np.clip(Y - CH*0.08, CH/2, H - CH/2)  # гравці трохи вище центру кадру

# ---------- 4b. жорсткі обмеження: м'яч (і ворота в режимі воріт) завжди в кадрі ----------
BX = np.full(N, np.nan); BY = np.full(N, np.nan)
for i in range(len(rows)):
    if ball_f[i] is None: continue
    nxt = i + 1 if i + 1 < len(rows) and ball_f[i + 1] is not None else None
    if nxt is None:
        BX[frames[i]], BY[frames[i]] = ball_f[i]
    else:
        fr = np.arange(frames[i], frames[nxt] + 1)
        BX[fr] = np.interp(fr, [frames[i], frames[nxt]], [ball_f[i][0], ball_f[nxt][0]])
        BY[fr] = np.interp(fr, [frames[i], frames[nxt]], [ball_f[i][1], ball_f[nxt][1]])
GW = gauss(np.interp(allf, frames, [g for g, _ in gmode]), 1.0 * FPS)
GI = np.array([gmode[min(np.searchsorted(frames, f), len(frames) - 1)][1] for f in allf])
# гістерезис: режим воріт вмикається при > 0.5, вимикається при < 0.25; епізоди коротші за 1.5 с ігноруються
GON = np.zeros(N, bool); on = False
for f in range(N):
    on = GW[f] > 0.5 if not on else GW[f] > 0.25
    GON[f] = on
_ch = np.flatnonzero(np.diff(np.r_[0, GON.astype(int), 0]))
for a, b in zip(_ch[::2], _ch[1::2]):
    if b - a < 1.5 * FPS: GON[a:b] = False
    else: GI[a:b] = np.bincount(GI[a:b][GI[a:b] >= 0]).argmax() if (GI[a:b] >= 0).any() else -1   # одні ворота на епізод

def bounds(f):
    """Мінімальний прямокутник, який мусить бути в кадрі на кадрі f (або None)."""
    pts = []
    if not np.isnan(BX[f]): pts.append((BX[f], BY[f], 0, 0))
    if goals_on and GON[f] and GI[f] >= 0:
        g = GOALS[GI[f]]; hw, hh = goal_box(g); pts.append((g[0], g[1], hw, hh))
    if not pts: return None
    p = np.array(pts)
    return (p[:, 0] - p[:, 2]).min(), (p[:, 0] + p[:, 2]).max(), (p[:, 1] - p[:, 3]).min(), (p[:, 1] + p[:, 3]).max()

ASP = CFG['out_h'] / CFG['out_w']
for it in range(5):
    goals_on = it < 4          # ворота — лише в ітераціях зі згладжуванням (інакше ривок на межі епізоду)
    LOX, HIX, LOY, HIY = (np.full(N, -np.inf), np.full(N, np.inf), np.full(N, -np.inf), np.full(N, np.inf))
    for f in range(N):
        bb = bounds(f)
        if bb is None: continue
        m = CFG['ball_margin'] * CW[f]
        need_w = max(bb[1] - bb[0] + 2 * m, (bb[3] - bb[2] + 2 * m) / ASP)
        if need_w > CW[f]: CW[f] = min(need_w, W, H / ASP); CH[f] = CW[f] * ASP
        LOX[f], HIX[f] = bb[1] + m - CW[f] / 2, bb[0] - m + CW[f] / 2
        LOY[f], HIY[f] = bb[3] + m * ASP - CH[f] / 2, bb[2] - m * ASP + CH[f] / 2
    X = np.clip(X, LOX, np.maximum(LOX, HIX)); Y = np.clip(Y, LOY, np.maximum(LOY, HIY))
    if it < 4:   # згладити ривки від обмежень і перевірити знову
        X = gauss(X, 0.3 * FPS); Y = gauss(Y, 0.3 * FPS); CW = gauss(CW, 0.6 * FPS); CH = CW * ASP
# м'яч, що з'явився далеко, не телепортує камеру: швидкий, але плавний (і офлайн — завчасний) рух
X = speed_limit(X, CFG['catch_speed_k'] * CFG['max_speed_px_s'] / FPS); Y = speed_limit(Y, CFG['catch_speed_k'] * CFG['max_speed_px_s'] / FPS)
CW = speed_limit(CW, CFG['catch_speed_k'] * CFG['max_speed_px_s'] / FPS); CH = CW * ASP
X = np.clip(X, CW/2, W - CW/2); Y = np.clip(Y, CH/2, H - CH/2)

# не захоплювати чорні поля панорами (склейка камер дає вигнуті межі зображення)
_med = field_mask(SRC)[1]
_content = (_med.max(axis=2) > 12)
_top = np.array([np.argmax(c) if c.any() else 0 for c in _content.T])               # перший непорожній рядок у кожному стовпці
_bot = np.array([H - np.argmax(c[::-1]) if c.any() else H for c in _content.T])
# біля кінців поля вигнута верхня межа штовхає кадр униз → знизу порожня трава.
# Якщо зсув більший за border_push частки висоти — плавно наближаємо (до border_zoom_min).
ZF = np.ones(N)
for f in range(N):
    a, b = int(max(0, X[f] - CW[f]/2)), int(min(W, X[f] + CW[f]/2))
    push = (_top[a:b].max() - (Y[f] - CH[f]/2)) / CH[f]
    if push > CFG['border_push']: ZF[f] = max(CFG['border_zoom_min'], 1 - (push - CFG['border_push']))
ZF = gauss(ZF, 1.0 * FPS); CW = CW * ZF; CH = CH * ZF

for f in range(len(X)):
    # біля країв панорами смуга зображення вузька: спершу зсуваємо кадр до центру, а не стискаємо його
    for _ in range(100):
        a, b = int(X[f] - CW[f]/2), int(X[f] + CW[f]/2)
        if _bot[a:b].min() - _top[a:b].max() >= CH[f] * 0.85 or abs(X[f] - W/2) < 50: break
        X[f] -= math.copysign(20, X[f] - W/2)
    a, b = int(X[f] - CW[f]/2), int(X[f] + CW[f]/2)
    t, bt = _top[a:b].max(), _bot[a:b].min()
    y0 = max(Y[f] - CH[f]/2, t)
    if y0 + CH[f] > bt: y0 = max(t, bt - CH[f])
    if bt - t < CH[f]:                     # місця не вистачає — зменшуємо кадр (сильніший зум)
        CH[f] = bt - t; CW[f] = CH[f] * CFG['out_w'] / CFG['out_h']; y0 = t
        X[f] = np.clip(X[f], CW[f]/2, W - CW[f]/2)
    Y[f] = y0 + CH[f]/2

# ---------- 5. метрики ----------
inside = tot = 0; pin = []
for i, r in enumerate(rows):
    f = r['frame']; x0, x1 = X[f]-CW[f]/2, X[f]+CW[f]/2; y0, y1 = Y[f]-CH[f]/2, Y[f]+CH[f]/2
    if ball[i] is not None:
        tot += 1; bx, by = ball[i]; inside += (x0 <= bx <= x1 and y0 <= by <= y1)
    pl = field_players(r['persons'])
    if len(pl): pin.append(np.mean((pl[:, 0] >= x0) & (pl[:, 0] <= x1)))
vel = np.abs(np.diff(X)) * FPS
metrics = dict(
    sampled_frames=len(rows), ball_found_share=round(sum(b is not None for b in ball)/len(rows), 3),
    ball_in_crop_share=round(inside/max(tot, 1), 3), players_in_crop_share=round(float(np.mean(pin)), 3),
    static_balls_filtered=len(static), cam_speed_mean_px_s=round(float(vel.mean()), 1),
    cam_speed_max_px_s=round(float(vel.max()), 1), crop_w_min=int(CW.min()), crop_w_max=int(CW.max()),
    goal_mode_share=round(float(GON.mean()), 3), goals=[[round(float(v)) for v in g] for g in GOALS], cfg=CFG)
json.dump(metrics, open(f'{OUT}/metrics.json', 'w'), indent=2, ensure_ascii=False)
print(json.dumps({k: v for k, v in metrics.items() if k != 'cfg'}, indent=1))
np.savez(f'{OUT}/camera_path.npz', X=X, Y=Y, CW=CW, CH=CH, GW=GW, GON=GON, GI=GI, FPS=FPS,
         BX=BX, BY=BY, GOALS=np.array(GOALS), GOAL_DIST=GOAL_DIST,          # для highlights.py
         S_FRAMES=frames, ZN=_zn, ZONE_BASE=np.array(ZONE_BASE))

# ---------- 6. рендер ----------
# --range 165-185: рендерити лише цей відрізок (секунди) у out_*_165-185.mp4 — для швидкої перевірки
R0, R1, SUF = 0, N, ''
if '--range' in sys.argv:
    _a, _b = sys.argv[sys.argv.index('--range') + 1].split('-')
    R0, R1, SUF = int(float(_a) * FPS), min(N, int(float(_b) * FPS)), f'_{_a}-{_b}'

def ff(path, w, h):
    return subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{w}x{h}',
        '-r', str(FPS), '-i', '-', '-ss', str(R0 / FPS), '-i', SRC, '-map', '0:v', '-map', '1:a?'] + video_args(h) + [
        '-c:a', 'aac', '-shortest', path], stdin=subprocess.PIPE)

if '--no-render' in sys.argv: sys.exit(0)   # лише траєкторія і метрики
do_debug = '--no-debug' not in sys.argv
p1 = None if '--debug-only' in sys.argv else ff(f'{OUT}/out_follow{SUF}.mp4', CFG['out_w'], CFG['out_h'])
DW, DH = W // 2, H // 2
p2 = ff(f'{OUT}/out_debug{SUF}.mp4', DW, DH) if do_debug else None
by_frame = {r['frame']: (i, r) for i, r in enumerate(rows)}
cap.set(cv2.CAP_PROP_POS_FRAMES, R0); last_det = None
for f in range(R0, R1):
    ok, img = cap.read()
    if not ok: break
    x0, y0 = int(X[f]-CW[f]/2), int(Y[f]-CH[f]/2); x1, y1 = x0+int(CW[f]), y0+int(CH[f])
    if p1:
        crop = cv2.resize(img[y0:y1, x0:x1], (CFG['out_w'], CFG['out_h']), interpolation=cv2.INTER_LINEAR)
        p1.stdin.write(crop.tobytes())
    if p2:
        if f in by_frame: last_det = by_frame[f]
        d = cv2.resize(img, (DW, DH))
        if last_det:
            i, r = last_det
            for (fx, fy) in field_players(r['persons']):
                cv2.circle(d, (int(fx/2), int(fy/2)), 3, (255, 200, 0), -1)
            for s in static: cv2.circle(d, (int(s[0]/2), int(s[1]/2)), 8, (128, 128, 128), 1)
            if ball[i] is not None:
                cv2.circle(d, (int(ball[i][0]/2), int(ball[i][1]/2)), 9, (0, 0, 255), 2)
        for k, g in enumerate(GOALS):          # ворота: червоні в режимі воріт
            hw, hh = goal_box(g); col = (0, 0, 255) if GON[f] and GI[f] == k else (255, 255, 255)
            cv2.rectangle(d, (int((g[0]-hw)/2), int((g[1]-hh)/2)), (int((g[0]+hw)/2), int((g[1]+hh)/2)), col, 1)
        cv2.rectangle(d, (x0//2, y0//2), (x1//2, y1//2), (0, 255, 255), 2)
        p2.stdin.write(d.tobytes())
for p in (p1, p2):
    if p: p.stdin.close(); p.wait()
print('rendered')
