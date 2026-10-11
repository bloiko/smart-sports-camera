"""Автоматичні хайлайти (F13): кліпи з моментів біля воріт з готового відео follow.py.

Момент = епізод режиму воріт (м'яч біля воріт або атака: у зоні воріт більше гравців, ніж зазвичай).
Кліп охоплює небезпечну частину епізоду: від першого моменту небезпеки − 8 с до останнього + 4 с,
не довше 20 с (якщо довше — від початку: атака важливіша за святкування). Момент небезпеки: м'яч ближче
за 0.1 відстані між воротами або гравців у зоні ≥ 80% від максимуму епізоду. Небезпека (0–1) = середнє:
  м'яч: 1 − (мін. відстань м'яча до воріт) / 0.15 відстані між воротами (0, якщо м'яча не видно);
  гравці: (гравців у зоні понад звичайне) / 10.

Гол: якщо дано --video і --det, шукаємо розіграш з центру (kickoff.py); епізод біля воріт, що закінчився
не раніше ніж за GOAL_BEFORE_KICKOFF с до кікофу, позначається як гол (небезпека = 1). Кліп голу довший:
до кінця епізоду + 4 с (святкування теж варто показати).
На початку кожного кліпу: вхід з чорного 0.4 с і мітка «2:04 · GOAL · right goal» на 3 с.
З --video кліпи рендеряться з оригіналу ближчою камерою (closeup.py: ~0.65 кадру основної камери, ціль — м'яч);
--vertical додатково робить вертикальні 9:16 (1080×1920) у OUT_DIR/vertical/ для Reels і Shorts.

Використання: python src/highlights.py FINAL_DIR OUT_DIR [--video V --det DETECTIONS.jsonl] [--checklist C.json]
                                       [--top N] [--min-score S] [--goals-only] [--vertical] [--wide]
  --wide: кліпи з основного (широкого) відео, як раніше.
  FINAL_DIR — тека follow.py (camera_path.npz, out_follow.mp4).
  → OUT_DIR/clip_01_2m50s.mp4 ..., OUT_DIR/highlights.mp4 (усі кліпи підряд), OUT_DIR/highlights.json
"""
import json, os, subprocess, sys, numpy as np, cv2

BEFORE, AFTER, MAX_LEN, MIN_EP = 8.0, 4.0, 20.0, 2.5      # секунди
MIN_SCORE = 0.3   # нижче — на перегляді 2026-10-11 жодного небезпечного моменту (гравці в зоні без м'яча)
GOAL_BEFORE_KICKOFF = 45.0   # с від кінця епізоду до кікофу (на тестах 6–10 с; 20–23 с від голу)
GOAL_MAX_LEN = 30.0


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def tsec(t):
    m, s = t.split(':'); return int(m) * 60 + float(s)


def moments(p):
    fps = float(p['FPS']); GON, GI = p['GON'], p['GI']; BX, BY = p['BX'], p['BY']
    G, D = p['GOALS'], float(p['GOAL_DIST']); SF, ZN, ZB = p['S_FRAMES'], p['ZN'], p['ZONE_BASE']
    n = len(GON); ch = np.flatnonzero(np.diff(np.r_[0, GON.astype(int), 0])); out = []
    for a, b in zip(ch[::2], ch[1::2]):
        if (b - a) / fps < MIN_EP: continue
        g = GI[a:b]; g = int(np.bincount(g[g >= 0]).argmax()) if (g >= 0).any() else 0
        fr = np.arange(a, b); seen = ~np.isnan(BX[fr])
        d = np.hypot(BX[fr] - G[g][0], BY[fr] - G[g][1]) / D
        si = np.flatnonzero((SF >= a) & (SF < b)); extra = ZN[si, g] - ZB[g] if len(si) else np.zeros(1)
        ball = float(np.clip(1 - np.nanmin(d) / 0.15, 0, 1)) if seen.any() else 0.0
        players = float(np.clip(extra.max() / 10, 0, 1))
        hot = list(fr[np.nan_to_num(d, nan=9) < 0.1])                                  # м'яч біля воріт
        if len(si) and extra.max() > 0: hot += list(SF[si[extra >= 0.8 * extra.max()]])  # багато гравців
        first, last = (min(hot), max(hot)) if hot else ((a + b) // 2, (a + b) // 2)
        peak = int(first)
        t0 = max(a / fps - 3, first / fps - BEFORE); t1 = min(b / fps + 2, last / fps + AFTER, n / fps)
        t1 = min(t1, t0 + MAX_LEN)
        out.append(dict(start=round(t0, 1), end=round(t1, 1), peak=round(peak / fps, 1), goal=['left', 'right'][g], kind='chance',
                        ep_end=round(b / fps, 1),
                        score=round((ball + players) / 2, 2), ball=round(ball, 2), players=round(players, 2)))
    return out


def mark_goals(ms, kickoffs):
    """Останній епізод перед кожним кікофом (у межах GOAL_BEFORE_KICKOFF) — гол."""
    for t, sep in kickoffs:
        before = [m for m in ms if m['ep_end'] <= t + 1 and t - m['ep_end'] <= GOAL_BEFORE_KICKOFF]
        if before:
            g = max(before, key=lambda m: m['ep_end'])
            g.update(kind='goal', score=1.0, kickoff=t, end=round(min(g['ep_end'] + AFTER, g['start'] + GOAL_MAX_LEN), 1))


def render_clip(src, t0, t1, label, path):
    """Вирізати [t0, t1] з src: вхід з чорного і мітка на початку (ffmpeg тут без drawtext — малюємо OpenCV)."""
    cap = cv2.VideoCapture(src); fps = cap.get(5); W, H = int(cap.get(3)), int(cap.get(4))
    cap.set(cv2.CAP_PROP_POS_FRAMES, int(t0 * fps))
    ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}', '-r', str(fps), '-i', '-',
                           '-ss', str(t0), '-t', str(t1 - t0), '-i', src, '-map', '0:v', '-map', '1:a?', '-c:v', 'libx264', '-preset', 'veryfast',
                           '-crf', '23', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', path], stdin=subprocess.PIPE)
    sc = H / 1080
    for k in range(int((t1 - t0) * fps)):
        ok, im = cap.read()
        if not ok: break
        t = k / fps
        if t < 3.0:
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 1.4 * sc, int(3 * sc))
            x, y = int(40 * sc), int(60 * sc)
            box = im.copy(); cv2.rectangle(box, (x - int(16 * sc), y - th - int(16 * sc)), (x + tw + int(16 * sc), y + int(18 * sc)), (0, 0, 0), -1)
            im = cv2.addWeighted(box, 0.55, im, 0.45, 0)
            cv2.putText(im, label, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.4 * sc, (255, 255, 255), int(3 * sc), cv2.LINE_AA)
        if t < 0.4: im = (im * (t / 0.4)).astype(np.uint8)
        ff.stdin.write(im.tobytes())
    ff.stdin.close(); ff.wait()


def main():
    final, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):                         # кліпи попереднього запуску
        if f.startswith('clip_') and f.endswith('.mp4'): os.remove(os.path.join(out, f))
    p = np.load(os.path.join(final, 'camera_path.npz'))
    ms = moments(p); kicks = []
    if arg('--video') and arg('--det'):
        cache = os.path.join(out, 'kickoffs.json')
        if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(arg('--det')):
            kicks = json.load(open(cache))
        else:
            from kickoff import jersey_colours, separation, find_kickoffs
            from fieldmask import field_mask
            fm = cv2.dilate(field_mask(arg('--video'))[0], np.ones((41, 41), np.uint8))
            F = jersey_colours(arg('--video'), [json.loads(l) for l in open(arg('--det'))], fm)
            kicks = find_kickoffs(*separation(F, (p['GOALS'][0][0] + p['GOALS'][1][0]) / 2, float(p['FPS'])))
            json.dump(kicks, open(cache, 'w'))
        print('kickoffs (s, separation):', kicks)
        mark_goals(ms, kicks)
    ms = [m for m in ms if m['score'] >= float(arg('--min-score', MIN_SCORE))]
    if '--goals-only' in sys.argv: ms = [m for m in ms if m['kind'] == 'goal']
    if arg('--top'): ms = sorted(sorted(ms, key=lambda m: -m['score'])[:int(arg('--top'))], key=lambda m: m['start'])
    video = os.path.join(final, 'out_follow.mp4'); files = []
    close = arg('--video') and '--wide' not in sys.argv
    if close or '--vertical' in sys.argv:
        from closeup import close_path, content_bounds, render
        from fieldmask import field_mask
        med = field_mask(arg('--video'))[1]; Hs, Ws = med.shape[:2]; top, bot = content_bounds(med)
        paths = {False: close_path(p, Ws, Hs, top, bot)}
        if '--vertical' in sys.argv:
            paths[True] = close_path(p, Ws, Hs, top, bot, vertical=True); os.makedirs(os.path.join(out, 'vertical'), exist_ok=True)
            for f in os.listdir(os.path.join(out, 'vertical')):
                if f.endswith('.mp4'): os.remove(os.path.join(out, 'vertical', f))
    for k, m in enumerate(ms, 1):
        name = f"clip_{k:02d}_{int(m['peak'] // 60)}m{int(m['peak'] % 60):02d}s.mp4"; m['file'] = name
        if os.path.exists(video):
            t = m['peak']; side = f"{m['goal']} goal"
            label = f"{int(t // 60)}:{int(t % 60):02d}  " + (f"GOAL  {side}" if m['kind'] == 'goal' else f"chance  {side}")
            if close: render(arg('--video'), paths[False], os.path.join(out, name), m['start'], m['end'], (1920, 1080), label)
            else: render_clip(video, m['start'], m['end'], label, os.path.join(out, name))
            if '--vertical' in sys.argv:
                render(arg('--video'), paths[True], os.path.join(out, 'vertical', name), m['start'], m['end'], (1080, 1920), label)
            files.append(name)
    if files:
        with open(os.path.join(out, 'list.txt'), 'w') as f:
            for name in files: f.write(f"file '{name}'\n")
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', os.path.join(out, 'list.txt'), '-c', 'copy',
                        os.path.join(out, 'highlights.mp4')], check=True)
    total = sum(m['end'] - m['start'] for m in ms)
    for m in ms: print(f"{m['start']:6.1f}-{m['end']:6.1f}s  {m['goal']:5}  {m['kind']:6} danger {m['score']:.2f} (ball {m['ball']:.2f}, players {m['players']:.2f})")
    print(f'{len(ms)} clips, {total:.0f} s in total')
    report = dict(clips=ms, total_s=round(total, 1))
    if arg('--checklist'):
        ev = json.load(open(arg('--checklist')))['events']; miss = 0
        for e in ev:
            hit = [m['file'] if 'file' in m else m['start'] for m in ms if m['start'] <= tsec(e['time']) <= m['end']]
            miss += not hit; print(f"checklist {e['time']} {e['goal']} {e['type']}: {'in ' + str(hit[0]) if hit else 'MISSING'}")
        report['checklist_missing'] = miss
    json.dump(report, open(os.path.join(out, 'highlights.json'), 'w'), indent=2)


if __name__ == '__main__':
    main()
