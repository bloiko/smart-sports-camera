"""Домашній стенд для тестів застосунку без поля: відтворює матч на весь екран Mac, телефон на штативі
знімає екран. Ліцензійно і за якістю це лише для розробки; для справжніх користувачів не потрібен.

Використання: python src/bench_play.py VIDEO [--from 0] [--loop] [--keep]
  Пробіл — пауза, ← → — ±10 с, q — вихід. Показується лише поле (обрізано за маскою трави), розтягнуте на весь екран.
Порада: яскравість Mac на максимум, телефон на 60–80 см від екрана, так, щоб екран займав ~80% ширини
кадру ультраширокої камери (0.5×). Лінії поля і зелень тоді розпізнаються як на справжньому полі.
"""
import sys, time, cv2, numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from fieldmask import field_mask
src = sys.argv[1]; t0 = float(sys.argv[sys.argv.index('--from') + 1]) if '--from' in sys.argv else 0
cap = cv2.VideoCapture(src); fps = cap.get(5); cap.set(cv2.CAP_PROP_POS_FRAMES, int(t0 * fps))
# лише поле: рядки з травою (+ трохи запасу), без неба і чорних країв панорами — так поле на екрані найбільше
fm = field_mask(src)[0]; ys = np.where(fm.any(1))[0]; xs = np.where(fm.any(0))[0]
Y0, Y1 = max(0, ys.min() - 40), min(fm.shape[0], ys.max() + 20); X0, X1 = xs.min(), xs.max() + 1
# за замовчуванням поле розтягнуто на весь екран (панорама ~3.8:1 на екрані 16:10 — інакше вузька смуга);
# --keep зберігає пропорції
cv2.namedWindow('follo', cv2.WINDOW_NORMAL | (cv2.WINDOW_KEEPRATIO if '--keep' in sys.argv else cv2.WINDOW_FREERATIO)); cv2.setWindowProperty('follo', cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
paused = False; start = time.time(); f0 = int(t0 * fps)
while True:
    if not paused:
        ok, im = cap.read()
        if not ok:
            if '--loop' in sys.argv: cap.set(cv2.CAP_PROP_POS_FRAMES, 0); start = time.time(); f0 = 0; continue
            break
        fr = im[Y0:Y1, X0:X1]
        if '--keep' not in sys.argv:   # macOS тримає пропорції навіть з FREERATIO — розтягуємо самі під розмір вікна
            _, _, ww, wh = cv2.getWindowImageRect('follo')
            if ww > 0 and wh > 0: fr = cv2.resize(fr, (ww, wh), interpolation=cv2.INTER_LINEAR)
        cv2.imshow('follo', fr)
        f = int(cap.get(cv2.CAP_PROP_POS_FRAMES)); due = start + (f - f0) / fps; d = due - time.time()
    k = cv2.waitKey(max(1, int(d * 1000)) if not paused else 50) & 0xFF
    if k == ord('q'): break
    if k == ord(' '): paused = not paused; start = time.time(); f0 = int(cap.get(cv2.CAP_PROP_POS_FRAMES))
    if k in (2, 3, 81, 83):   # стрілки
        f = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) + (10 if k in (3, 83) else -10) * int(fps); cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, f)); start = time.time(); f0 = max(0, f)
cv2.destroyAllWindows()
