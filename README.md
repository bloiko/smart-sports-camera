# Smart Sports Camera

Turns a wide video of a game from a static camera into a broadcast-style 1920×1080 video that follows play. Long-term goal: a phone on a tripod as an automatic camera operator, with recorded and live (YouTube) modes, on iOS and Android.

**Status:** research prototype (phase 2 of 7). See [`specs/status.md`](specs/status.md) for progress and [`specs/results.md`](specs/results.md) for numbers.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/` | Python pipeline (detection, virtual camera, ball model training) |
| `models/` | Trained ball detectors (`ball_v02.pt`) |
| `docs/` | Stable documents: vision, requirements, architecture, phases, testing, risks, business plan, decisions, research |
| `specs/` | Frequently changing documents: status by phase, results, backlog, datasets, metrics |
| `.claude/skills/project-docs/` | Skill that tells Claude how to keep `docs/` and `specs/` up to date |
| `CLAUDE.md` | Entry point for Claude in a new chat |

## Setup (Mac)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
brew install ffmpeg
```

Stock YOLO weights (`yolo11s.pt`, `yolo11n.pt`) download automatically on first use. Videos and intermediate files are git-ignored; keep them outside the repo or in `work/`.

On Apple Silicon, `detect.py` and `ball_window.py` use the GPU (MPS) automatically; set `DEVICE=cpu` to force the CPU. On an M1 MacBook Air, detection of a 4-minute video at step 5 takes about 11 minutes and the ball window search about 2–5 minutes per model.

## Full pipeline

Run from the repository root. `game.mp4` is a wide static video of the whole pitch; `work/` holds all intermediate files.

```bash
mkdir -p work

# 1. Detect players and the ball on every 5th frame.
python src/detect.py game.mp4 work/detections.jsonl 5

# 2. First camera pass: computes where the camera should look (and a debug video).
python src/follow.py game.mp4 work/detections.jsonl work/pass1 --debug-only

# 3. Search for the ball in a 2x zoomed window around the camera view, with two models.
BALL_MODEL=yolo11s.pt          python src/ball_window.py game.mp4 work/pass1/camera_path.npz work/ball_base.jsonl 5
BALL_MODEL=models/ball_v02.pt  python src/ball_window.py game.mp4 work/pass1/camera_path.npz work/ball_v02.jsonl 5

# 4. Merge both models (each with its own confidence threshold).
python src/merge_balls.py work/balls.jsonl work/ball_base.jsonl:0.25 work/ball_v02.jsonl:0.4

# 5. Final camera pass and render (goals are found automatically, see src/goals.py).
python src/follow.py game.mp4 work/detections.jsonl work/final --balls work/balls.jsonl

# 6. Checks: goal checklist and a contact sheet of accepted balls (count real balls by eye).
python src/check_goals.py work/final/camera_path.npz specs/checklists/match1.json
python src/ball_sheet.py game.mp4 work/final/ball_track.json work/ball_sheet.jpg 24
```

Outputs in `work/final/`: `out_follow.mp4` (the result), `out_debug.mp4` (panorama with the camera window, players and ball), `metrics.json`, `camera_path.npz`, `ball_track.json`.

## Commands reference

| Command | What it does | Notes |
| --- | --- | --- |
| `python src/fieldmask.py game.mp4` | Finds the pitch (grass) and writes `fieldmask.jpg` (pitch highlighted) and `fieldmask.npy` | Check this first on a new stadium; prints the pitch share of the frame |
| `python src/detect.py VIDEO OUT.jsonl [STEP] [START]` | Detects players and balls (YOLO11s) on every STEP-th frame; the pitch band is split into 3 overlapping tiles | `START` resumes from a frame and appends to `OUT.jsonl` |
| `python src/follow.py VIDEO DETECTIONS OUT_DIR [--balls FILE] [--no-debug \| --debug-only] [--no-render] [--range A-B] [--goals CHECKLIST.json] [--set key=value ...]` | Builds the virtual camera path and renders it | Without flags renders both videos. `--no-render`: only `camera_path.npz` and `metrics.json` (seconds instead of minutes). `--range 168-180`: render only that segment (seconds) to `out_*_168-180.mp4`. `--goals`: use hand-measured goals from a checklist instead of automatic ones (tests only). `--set`: override a `CFG` parameter, value in JSON (`--set goal_zone=[0.08,0.16]`). Tunable parameters are in the `CFG` dict at the top of the file |
| `python src/goals.py VIDEO DETECTIONS [CHECKLIST.json] [--vis OUT.jpg]` | Finds both goals automatically: the left and right tips of the area where players spend the match | With a checklist prints the error against hand-measured goals; `--vis` draws the play area and goals on the median frame |
| `python src/check_goals.py CAMERA_PATH.npz CHECKLIST.json [FPS]` | Goal checklist: for each goal or shot listed in `specs/checklists/matchN.json`, the share of frames from 2 s before to 1 s after where the goal mouth is fully inside the crop | PASS at ≥ 90%. Add every goal you see in a test video to its checklist |
| `python src/ball_sheet.py VIDEO TRACK.json OUT.jpg [N] [--minus OTHER_TRACK.json] [--seed S]` | Contact sheet of N random accepted ball positions (240 px crops, red circle) for counting precision by eye | `--minus`: only points that another version accepted and this one did not (or vice versa) |
| `BALL_MODEL=M python src/ball_window.py VIDEO CAMERA_PATH.npz OUT.jsonl [STEP] [START]` | Looks for the ball in the camera view (plus 15% margin) upscaled 2x, so a 5–8 px far-side ball becomes visible | `M` is a stock YOLO name (uses the COCO ball class) or a custom ball model. `START` resumes from a frame and appends (use the last frame in `OUT.jsonl` + STEP) |
| `python src/merge_balls.py OUT.jsonl FILE:THR [FILE:THR ...]` | Union of ball detections from several models, each filtered by its own threshold | Models fail in different places; the union finds the ball more often |
| `python src/make_dataset.py DS VIDEO TRACK.json BALLS.jsonl PREFIX [MAX_POS]` | Builds pseudo-labelled training patches from an accepted ball track; first 80% of the video → train, last 20% → val | Run once per match into the same `DS` folder. Look at a contact sheet of labels before training |
| `python src/train.py` | Fine-tunes a YOLO11n ball detector on `dataset/data.yaml` (320 px, CPU) | Rerun to resume from `runs/detect/runs/ball/weights/last.pt`; copy `best.pt` to `models/` |
| `VIDEO=game.mp4 OUT=work/ball.jsonl ./src/resume_ball.sh` | Runs `ball_window.py` for at most 9 minutes and resumes from the last processed frame on the next call | For environments that kill long commands |
| `python src/ball_motion.py ...` | Experimental motion-based ball finder | Did not work (shadows, grass glare); kept for reference |

### Training a new ball model

```bash
# one call per match (video + accepted ball track from step 5 + raw base detections for ball sizes)
python src/make_dataset.py dataset game1.mp4 work1/final/ball_track.json work1/ball_base.jsonl m1 700
python src/make_dataset.py dataset game2.mp4 work2/final/ball_track.json work2/ball_base.jsonl m2 700
python src/train.py                      # rerun until 15 epochs are done
cp runs/detect/runs/ball/weights/best.pt models/ball_v03.pt
```

### Video utilities (ffmpeg)

```bash
# Frame at 20 s, scaled for a quick look
ffmpeg -ss 20 -i game.mp4 -frames:v 1 -vf scale=2000:-1 frame.jpg

# Split a large file into two halves without re-encoding (for transfer limits), and join back
ffmpeg -i game.mp4 -t 120 -c copy part_a.mp4
ffmpeg -ss 120 -i game.mp4 -c copy part_b.mp4
printf "file 'part_a.mp4'\nfile 'part_b.mp4'\n" > list.txt && ffmpeg -f concat -safe 0 -i list.txt -c copy joined.mp4

# Compress a 2-minute part to 720p (~23 MB) for sharing in chat
ffmpeg -i out_follow.mp4 -t 120 -vf scale=1280:720 -c:v libx264 -preset veryfast \
  -b:v 1500k -maxrate 1700k -bufsize 3000k -c:a aac -b:a 64k share_part1.mp4
```

## Performance (cloud sandbox: 2-core CPU, no GPU)

- `detect.py`: about 0.5–1 s per sampled frame (4-minute video at step 5 ≈ 25–30 min).
- `ball_window.py`: about 0.4–1 s per sampled frame.
- `follow.py` render: about 5 minutes for a 4-minute video.
- `train.py`: about 3 minutes per epoch for ~800 patches.

## Licences

- Ultralytics YOLO is AGPL-3.0, and so are models trained with it (`models/ball_v02.pt`). Fine for this prototype; a closed product needs an Apache-2.0 detector (see `docs/architecture.md`).
- Test videos appear to come from SoccerTrack v2 (CC BY 4.0); see `specs/datasets.md`.

## Documentation

- Stable: [`docs/`](docs/README.md)
- Changing: [`specs/`](specs/README.md)
