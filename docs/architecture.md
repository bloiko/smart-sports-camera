# Architecture

Two modes share one tracking core. Recorded mode is built first; live mode comes later.

## Recorded mode (cloud processing)

1. The phone records 4K in 1–5 minute chunks.
2. Each chunk uploads to object storage (S3 or Cloudflare R2) as soon as it is closed and is deleted from the phone.
3. The backend queues a processing job.
4. A GPU worker runs the pipeline: player detection → ball detection → goal finding → virtual camera → render → highlights.
5. The finished video lands in storage; the user gets a notification and a link.

## Live mode (v2)

1. The phone captures 4K.
2. An on-device model (Core ML on the Neural Engine / LiteRT on Android) finds the ball; the app crops a 1080p window.
3. The hardware encoder compresses H.264; the stream goes to YouTube over RTMPS.
4. YouTube stores the broadcast archive, so nothing stays on the phone.

On-device budget: one or two 640 px passes per frame (the whole frame downscaled plus one tile around the predicted ball). Tiling the full 4K frame in real time is not feasible.

## Processing pipeline (current prototype)

| Step | Script | Input → output |
| --- | --- | --- |
| Field mask | `src/fieldmask.py` | video → mask of the pitch (rejects spectators, benches, sky, black panorama borders) |
| Detection | `src/detect.py` | video → `detections.jsonl` (players + ball per sampled frame, panorama split into 3 tiles) |
| Virtual camera, pass 1 | `src/follow.py` | detections → `camera_path.npz` (where the camera looks) |
| Ball in zoomed window | `src/ball_window.py` | video + camera path → ball detections in a 2× upscaled window around the camera view |
| Merge models | `src/merge_balls.py` | several ball files → one (models fail in different places) |
| Background check | `src/ball_bgdiff.py` | video + ball files → `*.bg.jsonl`: how much each ball detection differs from the static background |
| Goal finding | `src/goals.py` (called by `follow.py`) | detections → left and right goal positions |
| Virtual camera, final | `src/follow.py --balls` | detections + balls → `out_follow.mp4`, `out_debug.mp4`, `metrics.json`, `ball_track.json` |
| Highlights | `src/highlights.py` (+ `src/kickoff.py`) | camera path + rendered video → clips of goal-area episodes; the episode before a kickoff is a goal |
| Checks | `src/check_goals.py`, `src/ball_sheet.py`, `src/compare_crops.py` | camera path / ball track → goal checklist, precision contact sheet, side-by-side frames of two versions |
| Pseudo-labels | `src/make_dataset.py` | video + accepted ball track → training patches |
| Training | `src/train.py` | patches → ball detector weights |

### Virtual camera logic (`follow.py`, v0.3)

- **Target:** weighted centre of the players nearest the main group, pulled towards the ball when the ball is found (`ball_weight`).
- **Zoom:** crop width from the spread of the main group, narrower on the far side of the pitch (depth estimated from player positions).
- **Ball tracking:** look-alikes are filtered out before tracking:
  - spare balls: the same spot during ≥ 15% of the match, or lying still ≥ 2 s / returning to the same spot over ≥ 60 s with no player within 1.3 player heights;
  - static look-alikes (letters painted on the grass, dummies, lines): the spot looks the same as the median background (`ball_bgdiff.py`).
  Detections are linked into a track with a distance gate; isolated single detections are dropped; gaps up to 1.5 s are filled by interpolation.
- **Goals:** found automatically (`goals.py`) as the left and right tips of the play area, the region where players spend the match (players almost never go beyond the goal line, the keeper stays near the goal). No user input and no third-party model. Error ≤ ~60–80 px on test panoramas, so the goal zone gets an 80 px margin.
- **Goal-area mode (F7):** on when the ball is near a goal, or the goal area holds clearly more players than usual for that goal (an attack, even when the ball is not detected). The crop then frames the goal mouth, the ball and the players near the goal. Hysteresis and a minimum episode length of 1.5 s prevent flicker.
- **Smoothing:** dead zone → two-sided Gaussian smoothing (no lag, because processing is offline) → speed limit applied forward and backward.
- **Hard constraints:** after smoothing, the ball (and, in goal mode, the goal mouth) must be inside the crop with a margin; constraint, smooth and re-check alternate; a final two-sided speed cap (2.5× the normal one) turns a jump to a reappearing ball into a fast, early pan.
- **Bounds:** the crop never leaves the image content (panoramas from stitched cameras have curved black borders). Near the pitch ends the curved top border pushes the crop down; the crop then zooms in up to 25% instead of showing empty near-side grass.

## Technology stack

| Layer | Technology | Why |
| --- | --- | --- |
| Tracking prototype | Python, OpenCV, Ultralytics YOLO11, FFmpeg | Fastest way to test the main risk |
| Mobile app | Kotlin Multiplatform + Compose for shared logic; native camera, ML and encoder modules (AVFoundation/Core ML on iOS, CameraX/LiteRT/MediaCodec on Android) | Owner wants iOS and Android; no cross-platform framework can run camera → ML → encode → RTMP from shared code |
| Streaming | HaishinKit (iOS, BSD-3), RootEncoder (Android, Apache-2.0) | Maintained RTMP/RTMPS libraries; FFmpegKit was retired in 2025 |
| Backend | Java 21, Spring Boot, PostgreSQL | Owner's strength |
| Queue and workers | SQS / RabbitMQ; Python GPU worker | Models live in the Python ecosystem |
| Storage | Cloudflare R2 or Backblaze B2 + CDN | Cheap storage, free or cheap egress |
| GPU | Kaggle / Colab for training; hourly rental (RunPod, Vast.ai, Modal) for processing | Pay only for processing time |
| Backend hosting (PoC) | Oracle Cloud Always Free ARM VM | Free and large enough for Spring Boot |

## Own computation first

Owner's principle (2026-10-11): product logic such as goal finding is our own computation on our own data, not a third-party model or service with its own licence. Whether this also applies to the ball detector is an open question (see `specs/backlog.md`).

## Licensing constraint

Ultralytics YOLO (used in the prototype) is AGPL-3.0, and Ultralytics treats trained weights as AGPL too. Before any closed-source release, replace it with an Apache-2.0 detector (RF-DETR N/S/M/L, D-FINE, DEIM, YOLOX) or buy an Ultralytics Enterprise licence.
