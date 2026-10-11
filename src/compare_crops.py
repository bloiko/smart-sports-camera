"""Порівняння версій камери: кадри з кількох траєкторій (camera_path.npz) поруч, по рядку на момент часу.
Використання: python src/compare_crops.py VIDEO OUT.jpg T0 T1 STEP v0.2=old/camera_path.npz v0.3=new/camera_path.npz
T0, T1, STEP — у секундах. Метрики не показують, наскільки великі ворота в кадрі; ця картинка показує.
"""
import cv2, sys, numpy as np
src, out, t0, t1, st = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:6])
paths = [(a.split('=')[0], np.load(a.split('=')[1])) for a in sys.argv[6:]]
cap = cv2.VideoCapture(src); fps = cap.get(5); rows = []
t = t0
while t <= t1 + 1e-6:
    f = int(t * fps); cap.set(1, f); ok, im = cap.read()
    if not ok: break
    row = []
    for lab, p in paths:
        X, Y, CW, CH = p['X'][f], p['Y'][f], p['CW'][f], p['CH'][f]
        c = cv2.resize(im[int(Y - CH / 2):int(Y + CH / 2), int(X - CW / 2):int(X + CW / 2)], (560, 315))
        cv2.putText(c, f'{lab} {int(t // 60)}:{t % 60:04.1f}', (8, 30), 0, 0.9, (0, 255, 255), 2); row.append(c)
    rows.append(np.hstack(row)); t += st
cv2.imwrite(out, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
print(out, len(rows), 'rows')
