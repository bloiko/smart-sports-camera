# Datasets and test videos

Living document. Videos are never committed (see `.gitignore`); keep them next to the repo on the owner's Mac.

Last updated: 2026-10-11 (session 2)

| Match | File | Venue and conditions | Resolution, fps, length | Used for |
| --- | --- | --- | --- | --- |
| 1 | `118575.mp4` | University of Tsukuba pitch, winter, low sun, strong shadows | 4096×1080, 25 fps, 4:00 | v0.1, v0.2 training (first 80%) and validation (last 20%) |
| 2 | `132877.mp4` | Same stadium, spring, overcast | 4096×1084, 25 fps, 4:00 | Cross-match test of v0.2; v0.3 dataset |
| 3 | `132831.mp4` | Chuo Gakuin University pitch, evening, pale artificial grass, different stitched camera | 3840×1504, 25 fps, 4:00 | Stadium-independence test; v0.3 dataset |

On the owner's Mac the videos are in `~/Downloads/`; `work/mN/game.mp4` are symlinks to them.

Hand-measured goal mouths and the goal checklist for each match: `specs/checklists/match1.json`, `match2.json`, `match3.json`.

## Source and licence

The three videos are stitched panoramas of university-level matches and appear to come from the **SoccerTrack v2** dataset (Hugging Face `atomscott/soccertrack-v2`, CC BY 4.0, access gated). Confirm the source; if confirmed, any published model or video must credit the dataset authors. SoccerNet (NDA) and DeepSportradar (non-commercial) must not be used for the product model.

## Generated data (not committed)

| Name | Produced by | Notes |
| --- | --- | --- |
| `detections.jsonl` | `detect.py` | Players and balls per sampled frame (every 5th frame for match 1, every 10th for matches 2–3). Rerun on 2026-10-11 on the M1 Mac in `work/m1..m3/` |
| `camera_path.npz`, `ball_track.json`, `metrics.json` | `follow.py` | Per run |
| `ball_*.jsonl` | `ball_window.py` | One file per model |
| `dataset/` | `make_dataset.py` | 160 px patches upscaled to 320 px; names `m<match>_<split>_<p|n><frame>.jpg` |

## Models

| File | Trained on | Notes |
| --- | --- | --- |
| `yolo11s.pt` (stock) | COCO | Used for players and as the base ball detector; AGPL |
| `models/ball_v02.pt` | Match 1, first 80%, pseudo-labels (249 detections + 652 interpolated) | YOLO11n fine-tuned at 320 px; AGPL (Ultralytics) |
