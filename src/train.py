"""Дотренування детектора м'яча на автоматичній розмітці. Запускати повторно — продовжує з last.pt."""
import os, sys
from ultralytics import YOLO
last = 'runs/detect/runs/ball/weights/last.pt'
if os.path.exists(last):
    YOLO(last).train(resume=True)
else:
    YOLO('yolo11n.pt').train(data='dataset/data.yaml', epochs=15, imgsz=320, batch=16, workers=0, cache=False,
        device='cpu', project='runs', name='ball', exist_ok=True, patience=8, plots=False,
        mosaic=0.5, degrees=0, fliplr=0.5, hsv_v=0.3, scale=0.3, verbose=False)
