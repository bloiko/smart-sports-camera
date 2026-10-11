"""Ближча камера для хайлайтів і вертикальне відео 9:16 (F6) з уже порахованої траєкторії follow.py.

Основне відео лишається широким (контекст гри); у кліпах хайлайтів камера ближче до м'яча.
- Ціль: м'яч, якщо видно (дірки до FILL_S заповнюються інтерполяцією); інакше в режимі воріт — між воротами
  і центром основної камери; інакше центр основної камери.
- Розмір: ZOOM × кадр основної камери (16:9) або висота × V_ZOOM з шириною 9/16 (вертикальне), але не менше
  MIN_SRC_H пікселів джерела по висоті (сильніше збільшення — каша з пікселів).
- Згладжування в обидва боки + обмеження швидкості, м'яч у кадрі з запасом, кадр не виходить за зображення.

Функція: close_path(npz, W, H, content_top, content_bot, vertical=False) → X, Y, CW, CH для кожного кадру.
Використання (перевірка): python src/closeup.py VIDEO CAMERA_PATH.npz OUT.mp4 T0 T1 [--vertical]
"""
import subprocess, sys, numpy as np, cv2

ZOOM, V_ZOOM, MIN_SRC_H = 0.65, 0.9, 300
FILL_S, SMOOTH_S, MAX_SPEED_K, MARGIN = 2.0, 0.6, 1.5, 0.12


def gauss(s, sig):
    r = int(sig * 3) or 1; k = np.exp(-0.5 * (np.arange(-r, r + 1) / max(sig, 1e-6)) ** 2); k /= k.sum()
    return np.convolve(np.pad(s, r, mode='edge'), k, mode='valid')


def speed_limit(s, v):
    f = s.copy()
    for i in range(1, len(f)): f[i] = f[i - 1] + np.clip(f[i] - f[i - 1], -v, v)
    b = f.copy()
    for i in range(len(b) - 2, -1, -1): b[i] = b[i + 1] + np.clip(b[i] - b[i + 1], -v, v)
    return (f + b) / 2


def fill(v, fps):
    """Лінійна інтерполяція дірок NaN до FILL_S; довші дірки лишаються NaN."""
    v = v.copy(); ok = np.flatnonzero(~np.isnan(v))
    for a, b in zip(ok, ok[1:]):
        if 1 < b - a <= FILL_S * fps: v[a:b + 1] = np.linspace(v[a], v[b], b - a + 1)
    return v


def content_bounds(med):
    c = med.max(axis=2) > 12
    top = np.array([np.argmax(col) if col.any() else 0 for col in c.T])
    bot = np.array([len(col) - np.argmax(col[::-1]) if col.any() else len(col) for col in c.T])
    return top, bot


def close_path(p, W, H, top, bot, vertical=False):
    fps = float(p['FPS']); X, Y, CW, CH = p['X'], p['Y'], p['CW'], p['CH']
    bx, by = fill(p['BX'], fps), fill(p['BY'], fps); seen = ~np.isnan(bx)
    # м'яча не видно, але камера в режимі воріт → ціль ближче до воріт (атака біля воріт, м'яч загубився)
    gx, gy = X.copy(), Y.copy()
    if 'GON' in p and len(p['GOALS']):
        on = p['GON'] & (p['GI'] >= 0); gi = np.clip(p['GI'], 0, len(p['GOALS']) - 1)
        gx = np.where(on, 0.6 * p['GOALS'][gi, 0] + 0.4 * X, X); gy = np.where(on, 0.6 * p['GOALS'][gi, 1] + 0.4 * Y, Y)
    tx = np.where(seen, 0.7 * np.nan_to_num(bx) + 0.3 * X, gx); ty = np.where(seen, 0.7 * np.nan_to_num(by) + 0.3 * Y, gy)
    ch = np.maximum((V_ZOOM if vertical else ZOOM) * CH, MIN_SRC_H)
    cw = ch * (9 / 16 if vertical else 16 / 9)
    v = MAX_SPEED_K * 900 / fps
    tx = speed_limit(gauss(tx, SMOOTH_S * fps), v); ty = speed_limit(gauss(ty, SMOOTH_S * fps), v); ch = gauss(ch, fps); cw = gauss(cw, fps)
    for i in range(len(tx)):                    # м'яч у кадрі з запасом
        if seen[i]:
            mx, my = (0.5 - MARGIN) * cw[i], (0.5 - MARGIN) * ch[i]
            tx[i] = np.clip(tx[i], bx[i] - mx, bx[i] + mx); ty[i] = np.clip(ty[i], by[i] - my, by[i] + my)
    tx = gauss(tx, 0.2 * fps); ty = gauss(ty, 0.2 * fps)
    tx = np.clip(tx, cw / 2, W - cw / 2)
    for i in range(len(tx)):                    # усередині зображення (вигнуті чорні межі панорами)
        a, b = int(tx[i] - cw[i] / 2), int(tx[i] + cw[i] / 2)
        t, bt = top[max(a, 0):b].max(), bot[max(a, 0):b].min()
        if bt - t < ch[i]: ch[i] = bt - t; cw[i] = ch[i] * (9 / 16 if vertical else 16 / 9)
        ty[i] = np.clip(ty[i], t + ch[i] / 2, bt - ch[i] / 2)
    return tx, ty, cw, ch


def render(video, path, out, t0, t1, size, label=None, fade=0.4):
    """Рендер [t0, t1] з джерела за траєкторією path=(X, Y, CW, CH); мітка на 3 с і вхід з чорного."""
    X, Y, CW, CH = path; ow, oh = size
    cap = cv2.VideoCapture(video); fps = cap.get(5); cap.set(cv2.CAP_PROP_POS_FRAMES, int(t0 * fps))
    ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{ow}x{oh}', '-r', str(fps), '-i', '-',
                           '-ss', str(t0), '-t', str(t1 - t0), '-i', video, '-map', '0:v', '-map', '1:a?', '-c:v', 'libx264', '-preset', 'veryfast',
                           '-crf', '21', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', out], stdin=subprocess.PIPE)
    sc = min(ow, oh) / 1080
    for k in range(int((t1 - t0) * fps)):
        ok, im = cap.read()
        if not ok: break
        f = int(t0 * fps) + k; f = min(f, len(X) - 1)
        x0, y0 = int(X[f] - CW[f] / 2), int(Y[f] - CH[f] / 2)
        fr = cv2.resize(im[max(y0, 0):y0 + int(CH[f]), max(x0, 0):x0 + int(CW[f])], (ow, oh), interpolation=cv2.INTER_CUBIC)
        t = k / fps
        if label and t < 3.0:
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 1.4 * sc, max(1, int(3 * sc)))
            x, y = int(40 * sc), int(80 * sc)
            box = fr.copy(); cv2.rectangle(box, (x - int(16 * sc), y - th - int(16 * sc)), (x + tw + int(16 * sc), y + int(18 * sc)), (0, 0, 0), -1)
            fr = cv2.addWeighted(box, 0.55, fr, 0.45, 0)
            cv2.putText(fr, label, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.4 * sc, (255, 255, 255), max(1, int(3 * sc)), cv2.LINE_AA)
        if t < fade: fr = (fr * (t / fade)).astype(np.uint8)
        ff.stdin.write(fr.tobytes())
    ff.stdin.close(); ff.wait()


if __name__ == '__main__':
    sys.path.insert(0, __file__.rsplit('/', 1)[0])
    from fieldmask import field_mask
    video, npz, out, t0, t1 = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
    vert = '--vertical' in sys.argv
    med = field_mask(video)[1]; H, W = med.shape[:2]; top, bot = content_bounds(med)
    path = close_path(np.load(npz), W, H, top, bot, vertical=vert)
    render(video, path, out, t0, t1, (1080, 1920) if vert else (1920, 1080))
    print('crop height in source px: min', int(path[3].min()), 'median', int(np.median(path[3])))
