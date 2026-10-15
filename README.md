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

On Apple Silicon, `detect.py` and `ball_window.py` use the GPU (MPS) with half precision automatically (`DEVICE=cpu`, `HALF=0` to change), and videos are encoded with the hardware encoder (VideoToolbox; `VENC=sw` forces libx264). On an M1 MacBook Air the whole pipeline takes about 7.5 minutes per 4 minutes of video at the default step 15 (see `specs/results.md`).

## Full pipeline

One command runs every step, skips steps that are already done and resumes interrupted ones (just run it again):

```bash
python src/pipeline.py game.mp4 work/game --checklist specs/checklists/match1.json --highlights
```

Outputs: `work/game/final/out_follow.mp4` (the result), `out_debug.mp4` (only with `--debug`), `metrics.json`, `ball_sheet.jpg` (precision check) and `work/game/highlights/` (clips, `highlights.mp4`, `highlights.json`). `--from final` recomputes from that step (for example after changing `follow.py`); `--no-render` skips video rendering; `--step N` samples every N-th frame (default 15: same results as 5, 3× faster); `--debug` also renders the panorama with the camera window.

The individual steps, for debugging. Run from the repository root; `work/` holds all intermediate files.

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

# 5. Mark detections that look like the static background (letters painted on the grass, lines, dummies).
python src/ball_bgdiff.py game.mp4 work/detections.jsonl work/balls.jsonl

# 6. Final camera pass and render (goals are found automatically, see src/goals.py; *.bg.jsonl are used when present).
python src/follow.py game.mp4 work/detections.jsonl work/final --balls work/balls.jsonl

# 7. Checks: goal checklist and a contact sheet of accepted balls (count real balls by eye).
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
| `python src/ball_bgdiff.py VIDEO FILE.jsonl [FILE2.jsonl ...]` | For every ball detection, how much the spot differs from the background (median of 15 frames); writes `FILE.bg.jsonl` with a 6th value per box | `follow.py` picks up `*.bg.jsonl` automatically and drops boxes below `ball_bg_min` (15): letters on the grass score 6–11, real balls 20+. About 1–1.5 min per 4-minute match |
| `python src/pipeline.py VIDEO OUT_DIR [--step N] [--checklist C.json] [--highlights] [--from STEP] [--no-render] [--range A-B]` | Runs the whole pipeline with skip and resume | Steps: detect, pass1, window, merge, bgdiff, final, checks, highlights. `--from` recomputes that step and all later ones |
| `python src/highlights.py FINAL_DIR OUT_DIR [--video V --det DETECTIONS.jsonl] [--checklist C.json] [--top N] [--min-score S] [--goals-only]` | Cuts highlight clips from `out_follow.mp4`: goal-area episodes, each from 8 s before the first dangerous moment to 4 s after the last (≤ 20 s), danger score from ball distance to goal and extra players near goal (clips below 0.3 dropped). With `--video` and `--det`, the episode before a kickoff is marked as a GOAL (clip up to 30 s, with the celebration). Each clip starts with a 0.4 s fade from black and a 3 s label such as "2:06 GOAL right goal" | With a checklist, reports which events are inside a clip. `--goals-only`: a reel of goals only. Kickoffs are cached in `OUT_DIR/kickoffs.json`. With `--video`, clips are rendered from the source with the closer camera (`--wide` keeps the main crop); `--vertical` also writes 9:16 clips to `OUT_DIR/vertical/` |
| `python src/closeup.py VIDEO CAMERA_PATH.npz OUT.mp4 T0 T1 [--vertical]` | Renders [T0, T1] s from the source with a closer camera: ~0.65 of the main crop, aimed at the ball (or at the goal in goal mode when the ball is lost), never smaller than 300 source px in height; `--vertical` makes 1080×1920 for Reels and Shorts | Used by `highlights.py`; prints the crop height in source pixels (below ~300 px the image turns to mush) |
| `python src/live_sim.py VIDEO OUT_DIR [--ref FINAL_DIR] [--checklist C.json] [--buffers 0,1,2,3,5] [--set key=value] [--render B A-C] [--dump]` | Live simulator: phone-budget detection (cached in `OUT_DIR/live_det.jsonl`, ~5–7 min per 4-minute match) and a real-time camera for each look-ahead buffer; compares with the offline version and the checklist | `--render 2 160-200` renders that segment for buffer 2 s |
| `.venv-export/bin/python src/export_coreml.py [--player-size H,W]` | Exports YOLO11s (players, input 1280×672) and `models/ball_v02.pt` (ball, 640×640) to Core ML with NMS inside → `models/coreml/*.mlpackage` (not committed) | Needs a separate venv with torch 2.7 (`python3 -m venv .venv-export && .venv-export/bin/pip install torch==2.7.0 torchvision==0.22.0 ultralytics coremltools==9.0 "numpy<2.3"`): torch 2.14 + coremltools 9 fail with "only 0-dimensional arrays" |
| `ios/FolloCore/build_mac.sh` | Builds the Swift live camera (`ios/FolloCore`) and the Mac simulator `follosim` with the Command Line Tools only; type-checks `LiveCameraRunner.swift` | Works around a stale `module.modulemap` in CLT 16.2 with a VFS overlay |
| `ios/FolloCore/.build-mac/follosim camera DIR B [--swift]` | Swift camera on the Python detections of `DIR` (`live_det.jsonl` + files from `live_sim.py --dump`) → `DIR/swift_B{B}.json`; `--swift` uses the Swift detections instead | `python src/compare_swift.py DIR B` then prints the differences (expected: 0.0000 px) |
| `ios/FolloCore/.build-mac/follosim env VIDEO DIR` / `detect VIDEO DIR [--models models/coreml]` | Field mask, bounds and halfway line from the first 10 s (`env`), or the full Core ML detection + ball tracker (`detect`) → `DIR/swift_env.json`, `swift_det.jsonl` | Compare with `python src/compare_env.py DIR`, `python src/compare_det.py DIR [PYTHON_DIR]`; evaluate a path with `python src/eval_swift_path.py DIR B VIDEO --ref … --checklist … [--swift]` |
| `python src/live_highlights.py OUT_DIR VIDEO [--buffer 2] [--checklist C.json] [--no-render] [--clips DIR]` | Highlights as the phone does them after Stop: moments from the live path (`live_B{B}.npz`), kick-offs from jersey colours sampled every 8th frame, clips 16:9 + 9:16 → `OUT_DIR/highlights/` and `live_highlights.json` | Needs `live_sim.py … --dump` first (uses `fmd.png`, `med.png`) |
| `ios/FolloCore/.build-mac/follosim highlights DIR VIDEO [--swift] [--no-render]` | The same in Swift → `DIR/swift_highlights/`; `python src/compare_highlights.py DIR` compares kick-offs, separation curves and clip lists | `OPT="-O -g" ios/FolloCore/build_mac.sh` for a build with line numbers in lldb |
| `ios/FolloCore/.build-mac/follosim track DIR` | Replays the Python ball candidates through the Swift tracker: ROIs and accepted balls must match | — |
| `python src/exp_kickoff.py`, `python src/exp_livegoals.py` | Experiments of 2026-10-12 on the cached live data: kick-off statistics (margin between real and false peaks) and live goal rules over time | Need `work/mN/live_pre` with `--dump` and `live_highlights.py` outputs |
| `python src/eval_live.py N PATH [PATH ...]` | Compare live camera paths of match N (`.npz` from `live_sim.py` or `.json` from `follosim camera`): jumps > 20 px per frame, ball in crop (offline v0.3 track), goal checklist | `python src/eval_live.py 2 work/m2/live_pre/live_B2.npz work/m2/live_iso/live_B2.npz` |
| `ios/FolloCore/.build-mac/follosim envq VIDEO DIR K` / `camera DIR B --env PREFIX` / `position DIR` / `scoreboard OUT.png` | Environment built as from K× downscaled frames (`qK_` files); camera on a chosen environment; the Go live position check on a saved environment; the score bug as the stream shows it | — |
| `LIVE_LOST_ROIS=3 LIVE_BALL_CONF=0.3 python src/live_sim.py …` | Environment overrides of the ball search constants for experiments (detection reruns) | — |
| `python src/bench_play.py VIDEO [--from S] [--loop]` | Home test bench: plays a match full screen on the Mac so the phone on a tripod can film the screen (space pause, arrows ±10 s, q quit) | Development only; see `docs/run-on-iphone.md` |
| `python src/golive.py VIDEO CAMERA_PATH.npz [--title T] [--from S] [--privacy P]` | Streams the live-camera crop of a recorded video to YouTube: Google sign-in, broadcast created through the API, RTMPS via ffmpeg | Setup in `docs/youtube-live.md`; needs `secrets/client_secret.json` |
| `python src/kickoff.py VIDEO DETECTIONS.jsonl CAMERA_PATH.npz` | Finds kickoffs: teams split by jersey colour (k-means on Lab a, b of the torso, grass pixels excluded), kickoff = each team on its own side of the halfway line (separation ≥ 0.77, 2 s average) | Prints the separation maximum and the kickoffs. About 1 min per 4-minute match |
| `python src/goals.py VIDEO DETECTIONS [CHECKLIST.json] [--vis OUT.jpg]` | Finds both goals automatically: the left and right tips of the area where players spend the match | With a checklist prints the error against hand-measured goals; `--vis` draws the play area and goals on the median frame |
| `python src/check_goals.py CAMERA_PATH.npz CHECKLIST.json [FPS]` | Goal checklist: for each goal or shot listed in `specs/checklists/matchN.json`, the share of frames from 2 s before to 1 s after where the goal mouth is fully inside the crop | PASS at ≥ 90%. Add every goal you see in a test video to its checklist |
| `python src/compare_crops.py VIDEO OUT.jpg T0 T1 STEP NAME=PATH.npz [NAME=PATH.npz ...]` | Frames of several camera versions side by side, one row per moment from T0 to T1 seconds | Use for every checklist event: metrics do not show how big the goal is in the frame |
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

## Performance

M1 MacBook Air, defaults: about 7.5 minutes per 4 minutes of video (detection 2.6 min, ball window 2.7 min, background check 0.6 min, camera and render 1.5 min) plus 1.3 min for highlights. Details in `specs/results.md`.

### Earlier: cloud sandbox, 2-core CPU, no GPU, step 5

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
