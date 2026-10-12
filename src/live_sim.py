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
  python src/live_sim.py VIDEO OUT_DIR [--buffers 0,1,2,3,5] [--ref FINAL_DIR] [--checklist C.json] [--render B A-C] [--dump]
  --dump: записати оточення камери (env.json, fm.png, fmd.png, med.png) для Swift-порту (follosim).
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
# experiments without editing the file: LIVE_LOST_ROIS=3 LIVE_BALL_CONF=0.3 python src/live_sim.py …
LOST_ROIS, BALL_CONF = int(os.environ.get('LIVE_LOST_ROIS', LOST_ROIS)), float(os.environ.get('LIVE_BALL_CONF', BALL_CONF))
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
           border_shift_max=150,    # ворота під вигнутою межею панорами → кадр до 150 px до центру (матч 2, 3:38)
           shift_la_s=0.0)          # зсув від межі панорами дивиться вперед на min(B, shift_la_s): > 0 означає затримку
                                    # B + shift_la_s на телефоні (потрібен готовий кадр f + la), тому 0 (перевірено: чекліст 7/7 так само)


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


# ---------------------------------------------------------------- етап 1: детекція з бюджетом телефона
def detect(video, out_path):
    import torch
    from ultralytics import YOLO
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    pm, bm = YOLO('yolo11s.pt'), YOLO(BALL_MODEL)
    fm, _ = field_mask(video, until_s=PREROLL_S); fmd = cv2.dilate(fm, np.ones((41, 41), np.uint8))
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
                        if fm[min(int(hy), H - 1), min(int(hx), W - 1)] and bg_diff(img, hx, hy) >= BG_MIN: hints.append((round(hx, 1), round(hy, 1), f)); rec.setdefault('hints', []).append([round(hx, 1), round(hy, 1)])
            rec['persons'] = ps; times['players'] += time.time() - t; last_ps = ps
            pl = np.array([((b[0] + b[2]) / 2, b[3]) for b in ps if b[4] >= 0.25 and fmd[min(int(b[3]), H - 1), min(int((b[0] + b[2]) / 2), W - 1)]])
            if len(pl):
                med = np.median(pl, 0); w = 1 / (1 + (np.linalg.norm(pl - med, axis=1) / 300) ** 2)
                centre = (pl * w[:, None]).sum(0) / w.sum()
                dens = (np.linalg.norm(pl[:, None] - pl[None], axis=2) < 250).sum(1)    # скупчення гравців
                hot = []
                for i in np.argsort(-dens, kind='stable'):   # стабільно: той самий порядок у Swift
                    if all(np.linalg.norm(pl[i] - h) > 300 for h in hot): hot.append(pl[i] - (0, 30))
                    if len(hot) == 3: break
                d = np.linalg.norm(pl - centre, axis=1); feet = [pl[i] - (0, 20) for i in np.argsort(d, kind='stable')[:6]]   # ноги біля центру гри
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
PREROLL_S = 10   # маска поля, межі зображення і центральна лінія — лише з перших секунд (на телефоні: перевірка позиції перед стартом)


def live_env(video):
    """Усе, що камера знає про поле до початку гри: маска (розширена), межі зображення, центральна лінія."""
    from goals import centre_line
    cap = cv2.VideoCapture(video); fps = cap.get(5); W, H = int(cap.get(3)), int(cap.get(4))
    fm, med = field_mask(video, until_s=PREROLL_S); fmd = cv2.dilate(fm, np.ones((41, 41), np.uint8))
    content = med.max(axis=2) > 12
    top = np.array([np.argmax(c) if c.any() else 0 for c in content.T]); bot = np.array([H - np.argmax(c[::-1]) if c.any() else H for c in content.T])
    cline = centre_line(fm, med)[0] if CAM['mirror'] else None
    return dict(W=W, H=H, fps=fps, fm=fm, fmd=fmd, med=med, top=top, bot=bot, cline=cline)


def dump_env(env, out):
    """Для Swift-порту (follosim camera): те саме оточення у файлах, щоб порівнювати лише логіку камери."""
    cl = env['cline']; H = env['H']
    x0, x1 = (float(cl(0)), float(cl(H))) if cl else (float('nan'), float('nan'))
    json.dump(dict(W=env['W'], H=env['H'], fps=env['fps'], top=env['top'].tolist(), bot=env['bot'].tolist(),
                   cline=dict(x0=x0, x1=x1), preroll_s=PREROLL_S), open(os.path.join(out, 'env.json'), 'w'))
    cv2.imwrite(os.path.join(out, 'fm.png'), env['fm'] * 255); cv2.imwrite(os.path.join(out, 'fmd.png'), env['fmd'] * 255)
    cv2.imwrite(os.path.join(out, 'med.png'), env['med'])


def camera(det, video, B_s, env=None):
    """Потокова камера (live_cam.py): кадр f виходить, коли прийшов кадр f + B."""
    from live_cam import LiveCamera
    env = env or live_env(video)
    cam = LiveCamera(env['W'], env['H'], env['fps'], env['fmd'], env['top'], env['bot'], env['cline'], B_s, CAM)
    for f, rec in enumerate(det): cam.push(f, rec)
    return cam.finish()


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
    env = live_env(video)
    if '--dump' in sys.argv: dump_env(env, out)
    for B in [float(b) for b in arg('--buffers', '0,1,2,3,5').split(',')]:
        t = time.time(); path = camera(det, video, B, env)
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
