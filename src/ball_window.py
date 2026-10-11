"""Крок 3 (v0.2): пошук м'яча у збільшеному вікні навколо кадру камери з першого проходу.
Дальній м'яч (5–8 px) після 2x збільшення стає 10–16 px — готова модель його бачить.
Результат дописується в ball_window.jsonl: {frame, balls:[[x1,y1,x2,y2,conf], ...]} у координатах панорами.
Використання: python3 ball_window.py video.mp4 camera_path.npz out.jsonl [step] [start_frame]
"""
import cv2, json, sys, numpy as np, time
from ultralytics import YOLO

SRC, PATH, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
STEP = int(sys.argv[4]) if len(sys.argv) > 4 else 5
START = int(sys.argv[5]) if len(sys.argv) > 5 else 0
UP = 2.0          # збільшення вікна
MARGIN = 0.15     # вікно трохи ширше за кадр камери, щоб не загубити м'яч на краю

import os
MODEL = os.environ.get('BALL_MODEL', 'yolo11s.pt')   # ball_v02.pt — дотренована модель
import torch
DEVICE = os.environ.get('DEVICE', 'mps' if torch.backends.mps.is_available() else 'cpu')   # Apple GPU, якщо є
m = YOLO(MODEL); CLASSES = [32] if MODEL.startswith('yolo') else None
p = np.load(PATH); X, Y, CW, CH = p['X'], p['Y'], p['CW'], p['CH']
cap = cv2.VideoCapture(SRC); N = int(cap.get(7))
if START: cap.set(cv2.CAP_PROP_POS_FRAMES, START)
f_out = open(OUT, 'a' if START else 'w'); t0 = time.time()
for f in range(START, min(N, len(X))):
    if f % STEP:
        cap.grab(); continue
    ok, img = cap.read()
    if not ok: break
    H, W = img.shape[:2]
    cw, ch = int(CW[f] * (1 + MARGIN)), int(CH[f] * (1 + MARGIN))
    x0 = int(np.clip(X[f] - cw / 2, 0, W - cw)); y0 = int(np.clip(Y[f] - ch / 2, 0, H - ch))
    up = cv2.resize(img[y0:y0 + ch, x0:x0 + cw], None, fx=UP, fy=UP, interpolation=cv2.INTER_CUBIC)
    r = m.predict(up, imgsz=1920, conf=0.1, classes=CLASSES, device=DEVICE, verbose=False)[0]
    balls = [[round(b[0] / UP + x0, 1), round(b[1] / UP + y0, 1), round(b[2] / UP + x0, 1), round(b[3] / UP + y0, 1), round(s, 3)]
             for b, s in zip(r.boxes.xyxy.tolist(), r.boxes.conf.tolist())]
    f_out.write(json.dumps({'frame': f, 'balls': balls}) + '\n'); f_out.flush()
    if f % 500 == 0: print(f, N, round(time.time() - t0), flush=True)
print('done', round(time.time() - t0))
