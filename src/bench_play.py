"""Домашній стенд для тестів застосунку без поля: відтворює матч на весь екран Mac, телефон на штативі
знімає екран. Ліцензійно і за якістю це лише для розробки; для справжніх користувачів не потрібен.

Використання: python src/bench_play.py VIDEO [--from 0] [--loop]
  Пробіл — пауза, ← → — ±10 с, q — вихід. Відео масштабується по ширині екрана, решта чорна.
Порада: яскравість Mac на максимум, телефон на 60–80 см від екрана, так, щоб екран займав ~80% ширини
кадру ультраширокої камери (0.5×). Лінії поля і зелень тоді розпізнаються як на справжньому полі.
"""
import sys, time, cv2
src = sys.argv[1]; t0 = float(sys.argv[sys.argv.index('--from') + 1]) if '--from' in sys.argv else 0
cap = cv2.VideoCapture(src); fps = cap.get(5); cap.set(cv2.CAP_PROP_POS_FRAMES, int(t0 * fps))
cv2.namedWindow('follo', cv2.WND_PROP_FULLSCREEN); cv2.setWindowProperty('follo', cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
paused = False; start = time.time(); f0 = int(t0 * fps)
while True:
    if not paused:
        ok, im = cap.read()
        if not ok:
            if '--loop' in sys.argv: cap.set(cv2.CAP_PROP_POS_FRAMES, 0); start = time.time(); f0 = 0; continue
            break
        cv2.imshow('follo', im)
        f = int(cap.get(cv2.CAP_PROP_POS_FRAMES)); due = start + (f - f0) / fps; d = due - time.time()
    k = cv2.waitKey(max(1, int(d * 1000)) if not paused else 50) & 0xFF
    if k == ord('q'): break
    if k == ord(' '): paused = not paused; start = time.time(); f0 = int(cap.get(cv2.CAP_PROP_POS_FRAMES))
    if k in (2, 3, 81, 83):   # стрілки
        f = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) + (10 if k in (3, 83) else -10) * int(fps); cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, f)); start = time.time(); f0 = max(0, f)
cv2.destroyAllWindows()
