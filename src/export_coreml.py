"""Export the player model (YOLO11s) and the ball model (models/ball_v02.pt) to Core ML for the Follo app.

Player model: input 1280×672 (w×h, the letterboxed size of one live_sim.py tile on a 4096×1084 panorama).
Ball model: input 640×640 (a 320 px ROI upscaled 2×, as in live_sim.py). NMS is built into the models
(inputs confidenceThreshold, iouThreshold; outputs confidence[N×classes], coordinates[N×4] normalised xywh).
Usage: python src/export_coreml.py [--player-size H,W] [--fp32] [--out DIR]  →  models/coreml/players.mlpackage, ball.mlpackage
"""
import os, shutil, sys
from ultralytics import YOLO

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'models', 'coreml')
size = [int(v) for v in sys.argv[sys.argv.index('--player-size') + 1].split(',')] if '--player-size' in sys.argv else [672, 1280]
if '--out' in sys.argv: OUT = sys.argv[sys.argv.index('--out') + 1]
os.makedirs(OUT, exist_ok=True)
for name, src, imgsz in (('players', os.path.join(ROOT, 'yolo11s.pt'), size), ('ball', os.path.join(ROOT, 'models', 'ball_v02.pt'), 640)):
    path = YOLO(src).export(format='coreml', imgsz=imgsz, nms=True, half='--fp32' not in sys.argv)   # Ultralytics 8.4 ignores half for Core ML (identical output; use quantize=…)
    dst = os.path.join(OUT, name + '.mlpackage')
    shutil.rmtree(dst, ignore_errors=True); shutil.move(path, dst); print(name, '->', dst)
