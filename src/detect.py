"""Крок 1: детекція гравців і м'яча на кожному N-му кадрі панорами. Результат: detections.jsonl"""
import cv2, json, sys, time
from ultralytics import YOLO
src, out, step = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv)>3 else 5
start = int(sys.argv[4]) if len(sys.argv)>4 else 0   # продовжити з кадру (дописує у файл)
m = YOLO('yolo11s.pt')
import os, torch
DEVICE = os.environ.get('DEVICE', 'mps' if torch.backends.mps.is_available() else 'cpu')   # Apple GPU, якщо є
cap = cv2.VideoCapture(src); W=int(cap.get(3)); n=int(cap.get(7))
# смуга і плитки — з маски поля (працює для будь-якого стадіону і роздільності)
from fieldmask import field_mask
import numpy as np
_fm = field_mask(src)[0]; _ys, _xs = np.where(_fm > 0)
Y0, Y1 = max(0, int(_ys.min()) - 60), min(int(cap.get(4)), int(_ys.max()) + 20)
X0, X1 = int(_xs.min()), int(_xs.max()) + 1
tw = (X1 - X0 + 100) // 3
tiles = [(X0 + k * (tw - 50), min(X1, X0 + k * (tw - 50) + tw)) for k in range(3)]
print('band', Y0, Y1, 'tiles', tiles, flush=True)
f = open(out,'a' if start else 'w'); t0=time.time(); i=start
if start: cap.set(cv2.CAP_PROP_POS_FRAMES, start)
while True:
    if i % step:
        if not cap.grab(): break
        i += 1; continue
    ok, img = cap.read()
    if not ok: break
    persons, balls = [], []
    for x0,x1 in tiles:
        r = m.predict(img[Y0:Y1,x0:x1], imgsz=1280, conf=0.12, classes=[0,32], device=DEVICE, verbose=False)[0]
        for b,c,s in zip(r.boxes.xyxy.tolist(), r.boxes.cls.tolist(), r.boxes.conf.tolist()):
            box=[b[0]+x0,b[1]+Y0,b[2]+x0,b[3]+Y0]
            (balls if c==32 else persons).append([round(v,1) for v in box]+[round(s,3)])
    f.write(json.dumps({'frame':i,'persons':persons,'balls':balls})+'\n'); f.flush()
    if i % 250 == 0: print(i, n, round(time.time()-t0), flush=True)
    i += 1
print('done', round(time.time()-t0))
