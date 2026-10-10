"""Крок 2: віртуальна камера.
Читає detections.jsonl, будує траєкторію камери і рендерить:
  out_follow.mp4  — 1920x1080 ролик, що слідує за грою
  out_debug.mp4   — панорама зі зменшенням, рамка камери, гравці, м'яч
  metrics.json    — метрики якості
Використання: python3 follow.py video.mp4 detections.jsonl [out_dir]
"""
import json, sys, subprocess, math
import numpy as np, cv2

SRC, DET = sys.argv[1], sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else '.'

# ---------- параметри (усе, що варто крутити) ----------
CFG = dict(
    out_w=1920, out_h=1080,
    depth_y=[150, 700],                 # y дальньої і ближньої бровки в панорамі
    min_crop_w=[800, 1700], max_crop_w=[1600, 2800],  # зум залежно від глибини і розкиду гравців
    spread_k=1.4,
    focus_px=300,                       # радіус «центру гри» навколо медіани гравців                       # crop_w = spread гравців * k
    static_ball_px=25, static_ball_share=0.15,  # м'яч, що стоїть на місці так часто, — запасний біля бровки
    ball_gate_px=350,                   # макс. стрибок м'яча між відліками (у пікселях панорами)
    ball_weight=0.7,
    window_ball_conf=0.4,               # поріг для м'ячів зі збільшеного вікна                    # наскільки м'яч тягне камеру (решта — гравці)
    smooth_sigma_s=0.8,                 # згладжування (с), двостороннє — без запізнення
    max_speed_px_s=900,                 # обмеження швидкості панорамування
    dead_zone_px=60,                    # дрібні рухи цілі ігноруються
)

cap = cv2.VideoCapture(SRC)
W, H = int(cap.get(3)), int(cap.get(4))
FPS = cap.get(5); N = int(cap.get(7))
rows = [json.loads(l) for l in open(DET)]
# v0.2: додаткові детекції м'яча зі збільшеного вікна (ball_window.py)
if '--balls' in sys.argv:
    extra = {}
    for l in open(sys.argv[sys.argv.index('--balls') + 1]):
        r = json.loads(l); extra[r['frame']] = [b for b in r['balls'] if b[4] >= CFG['window_ball_conf']]
    for r in rows: r['balls'] = r['balls'] + extra.get(r['frame'], [])
frames = np.array([r['frame'] for r in rows])
N = min(N, int(frames[-1]) + 1)   # дозволяє тестувати на частково обробленому відео

def center(b): return ((b[0]+b[2])/2, (b[1]+b[3])/2)
def feet(b): return ((b[0]+b[2])/2, b[3])

# ---------- 1. гравці: прибираємо глядачів/людей поза полем ----------
from fieldmask import field_mask
FMASK = cv2.dilate(field_mask(SRC)[0], np.ones((41, 41), np.uint8))

def field_players(persons):
    pts = []
    for b in persons:
        h = b[3]-b[1]
        if b[4] < 0.25 or h < 12 or h > 260: continue
        fx, fy = feet(b)
        if not FMASK[min(int(fy), H-1), min(int(fx), W-1)]: continue   # глядачі, лавки, люди за полем
        pts.append((fx, fy))
    return np.array(pts) if pts else np.zeros((0, 2))

# ---------- 2. м'яч: фільтр нерухомих (запасні м'ячі) + зв'язування в трек ----------
all_balls = [(i, center(b), b[4]) for i, r in enumerate(rows) for b in r['balls']]
static = []
if all_balls:
    P = np.array([p for _, p, _ in all_balls])
    for p in P:
        near = np.linalg.norm(P - p, axis=1) < CFG['static_ball_px']
        if near.sum() > CFG['static_ball_share'] * len(rows): static.append(p)
static = np.array(static) if static else np.zeros((0, 2))

def is_static(p):
    return len(static) and np.min(np.linalg.norm(static - p, axis=1)) < CFG['static_ball_px'] * 1.5

ball = [None] * len(rows)
last, last_i = None, -999
for i, r in enumerate(rows):
    cands = [(center(b), b[4]) for b in r['balls'] if not is_static(np.array(center(b)))]
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

# ---------- 3. ціль камери на кожному відліку ----------
tx, ty, tw = [], [], []
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
    tx.append(c[0]); ty.append(c[1])
    # перспектива: далеко (малий y) гравці дрібні → кадр має бути вужчим (сильніший зум)
    lo = np.interp(c[1], CFG['depth_y'], CFG['min_crop_w']); hi = np.interp(c[1], CFG['depth_y'], CFG['max_crop_w'])
    tw.append(np.clip(spread * CFG['spread_k'], lo, hi))

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
    cam_speed_max_px_s=round(float(vel.max()), 1), crop_w_min=int(CW.min()), crop_w_max=int(CW.max()), cfg=CFG)
json.dump(metrics, open(f'{OUT}/metrics.json', 'w'), indent=2, ensure_ascii=False)
print(json.dumps({k: v for k, v in metrics.items() if k != 'cfg'}, indent=1))
np.savez(f'{OUT}/camera_path.npz', X=X, Y=Y, CW=CW, CH=CH)

# ---------- 6. рендер ----------
def ff(path, w, h):
    return subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{w}x{h}',
        '-r', str(FPS), '-i', '-', '-i', SRC, '-map', '0:v', '-map', '1:a?', '-c:v', 'libx264', '-preset', 'veryfast',
        '-crf', '23', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', path], stdin=subprocess.PIPE)

do_debug = '--no-debug' not in sys.argv
p1 = None if '--debug-only' in sys.argv else ff(f'{OUT}/out_follow.mp4', CFG['out_w'], CFG['out_h'])
DW, DH = W // 2, H // 2
p2 = ff(f'{OUT}/out_debug.mp4', DW, DH) if do_debug else None
by_frame = {r['frame']: (i, r) for i, r in enumerate(rows)}
cap.set(cv2.CAP_PROP_POS_FRAMES, 0); last_det = None
for f in range(N):
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
        cv2.rectangle(d, (x0//2, y0//2), (x1//2, y1//2), (0, 255, 255), 2)
        p2.stdin.write(d.tobytes())
for p in (p1, p2):
    if p: p.stdin.close(); p.wait()
print('rendered')
