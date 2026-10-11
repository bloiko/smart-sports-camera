# Results

Living document. Add a row for every new model or pipeline version, per match. Definitions of the metrics are in `../docs/testing-strategy.md`.

Last updated: 2026-10-11 (session 2: v0.3 camera)

## Tracker metrics (`follow.py` → `metrics.json`)

`ball found` = share of sampled frames where the tracker accepted a ball. `in crop` = share of those frames where the ball is inside the output crop. `players` = average share of on-field players inside the crop.

| Date | Version | Match | Ball search | Ball found | In crop | Players | Max pan px/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-10 | v0.1 | 1 | Panorama tiles, YOLO11s | 12.7% | 94.1% | 71.6% | 363 |
| 2026-10-10 | v0.2-a | 1 | + 2× window, YOLO11s | 20.7% | 95.2% | 70.8% | 367 |
| 2026-10-10 | v0.2 | 1 | + 2× window, `ball_v02.pt` | 29.6% | 98.3% | 70.2% | 391 |
| 2026-10-10 | v0.2 | 2 | Panorama tiles only | 45.3% | 99.3% | 66.7% | 288 |
| 2026-10-10 | v0.2 | 2 | + window, YOLO11s | 55.5% | 99.7% | 66.0% | — |
| 2026-10-10 | v0.2 | 2 | + window, YOLO11s ∪ `ball_v02.pt` | **65.9%** | 100% | 65.6% | — |
| 2026-10-11 | v0.2 | 3 | Panorama tiles only | 15.3% | 94.6% | 72.5% | 350 |
| 2026-10-11 | v0.2 | 3 | + window, YOLO11s | 16.1% | 94.8% | 72.3% | — |
| 2026-10-11 | v0.2 | 3 | + window, `ball_v02.pt` | 25.3% | 96.1% | 72.4% | — |
| 2026-10-11 | v0.2 | 3 | + window, YOLO11s ∪ `ball_v02.pt` | **25.6%** | 96.1% | 72.3% | — |

### v0.2 vs v0.3 camera on identical inputs (2026-10-11, M1 Mac)

Detection rerun locally (Ultralytics 8.4, MPS), ball window searched along the v0.3 pass-1 path, union YOLO11s (≥ 0.25) ∪ `ball_v02.pt` (≥ 0.4). Both camera versions read the same `detections.jsonl` and `balls.jsonl`; only `follow.py` differs. Goals found automatically (`src/goals.py`). `Goal mode` = share of frames in goal-area mode. Max pan in v0.3 is the catch-up cap (2.5 × 900 px/s), reached when the ball reappears far from the crop.

| Version | Match | Ball found | In crop | Players | Mean / max pan px/s | Goal mode | Goal checklist |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v0.2 | 1 | 41.9% (≈ 40% of it false, see precision) | 87.9% | 69.4% | 87 / 622 | — | **FAIL** (2:54.8) |
| v0.3 | 1 | 27.1% | 99.7% | 62.3% | 65 / 2250 | 21.6% | **PASS** |
| v0.2 | 2 | 64.4% | 90.4% | 63.8% | 72 / 625 | — | no events listed |
| v0.3 | 2 | 59.4% | 98.0% | 55.6% | 96 / 2250 | 28.1% | no events listed |
| v0.2 | 3 | 29.4% | 81.8% | 71.1% | 55 / 358 | — | no events listed |
| v0.3 | 3 | 24.1% | 100% | 62.8% | 72 / 2250 | 31.7% | no events listed |

Notes:
- The v0.2 rows of 2026-10-10 for match 1 (29.6% found, 98.3% in crop) are not comparable: they were measured with an older `detect.py` (fixed detection band). With the current detection the v0.2 tracker also accepts the letter "f" of the "University of Tsukuba" logo and spare balls at the right corner flag.
- v0.3 trades some players in frame (−7 to −8 points) for the ball (+8 to +18 points) and goals. The pan speed exceeds 900 px/s in 0.2–0.8% of frames (catch-up moves).
- Background filter (`ball_bgdiff.py`, `ball_bg_min=15`) changes the v0.3 rows by at most 0.3 points (match 1: found 26.8%, match 2: 59.1%, in crop 98.3%); it removes static look-alikes such as logo letters on the grass (owner feedback on match 2, 0:46.8).
- v0.3 includes the "border zoom": near the pitch ends the curved black top border of these stitched panoramas pushed the crop down (empty near-side grass); when pushed by more than 20% of its height, the crop now zooms in up to 25%. Raw metrics: `specs/metrics/matchN_v03.json`.

## Highlights (`src/highlights.py`, 2026-10-11)

Clips = goal-area episodes of v0.3, each from 8 s before the first dangerous moment to 4 s after the last, at most 20 s. Danger = mean of ball proximity to the goal and extra players near the goal.

| Match | Clips | Total length | Checklist events inside a clip |
| --- | --- | --- | --- |
| 1 | 4 | 64 s of 4:00 | 1 of 1 (goal 2:54.8) |
| 2 | 6 | 76 s | 1 of 1 (chance 3:38) |
| 3 | 7 | 98 s | 2 of 2 (chance 1:25, goal 2:04.7) |

The danger score does not single out goals yet: the match 3 goal scores 0.50, below three non-goal clips. Clip windows were tuned on these 4 events (first version cut the match 1 goal at the clip start because the peak was the celebration, the second dropped the match 3 chance).

## Automatic goal finding (`src/goals.py`)

Error of the automatic goal position against hand-measured goal mouths (`specs/checklists/`). A goal mouth is about 120–145 px wide in these panoramas; `follow.py` adds an 80 px margin around automatic goals.

| Date | Method | Match 1 L / R | Match 2 L / R | Match 3 L / R |
| --- | --- | --- | --- | --- |
| 2026-10-11 | Keeper heuristic (median of leftmost / rightmost player) | (+312, −16) / (+788, +383) | — | — |
| 2026-10-11 | Tips of the play area (player heat map, threshold 0.1) | (+25, +29) / (−57, +11) | (−43, +56) / (−45, +27) | (+62, −46) / (+22, +81) |

## Raw detector comparison (ball in window, excluding static spare balls)

| Match | Frames | YOLO11s (conf ≥ 0.25) | `ball_v02.pt` (conf ≥ 0.4) | Note |
| --- | --- | --- | --- | --- |
| 1, held-out last 20% | 240 | 19.2% | 40.4% | v0.2 trained on the first 80% of this match |
| 2 | 596 | 58.7% | 51.7% | v0.2 overfitted to match 1 |

## Precision spot-checks

| Date | Match | Version | Result |
| --- | --- | --- | --- |
| 2026-10-10 | 2 | union | 12 of 12 accepted detections were the real ball |
| 2026-10-11 | 3 | union | 11 of 12 (one false detection on a fence) |
| 2026-10-11 | 1 | v0.2 tracker, points that v0.3 rejects | 4 of 24 real; the rest: logo letter "f" (15), spare balls at the corner flag (4), other (1) |
| 2026-10-11 | 1 | v0.3 | 24 of 24 (random sample); an earlier sample 23 of 24 (white mark on the kerb) |
| 2026-10-11 | 2 | v0.3 | 23 of 24 (one on the "SOO" logo letters) |
| 2026-10-11 | 3 | v0.3 | 22 of 24 (a spare ball off the pitch, one unclear dark dot) |
| 2026-10-11 | 2 | v0.3 + background filter, points removed by the filter | 3 of 3 false: letter "O" of the logo on the grass (2), yellow training dummies (1) |
| 2026-10-11 | 1 / 3 | v0.3 + background filter | 24 of 24 / 23 of 24 (a player's head) |

## Goal checklist

Machine-readable lists live in `specs/checklists/matchN.json` (goal mouths measured by hand + events); `src/check_goals.py` checks them. Matches 2 and 3 have one event each from the owner.

| Match | Goal / shot (time) | Visible in output? | Version |
| --- | --- | --- | --- |
| 1 | Goal at 2:54.8, left goal (owner: 2:50–2:57) | **No**: camera ~800 px to the right of the goal | v0.2 |
| 1 | Goal at 2:54.8, left goal | **Yes**: goal mouth in frame 100% of 2:52.8–2:55.8 (automatic goals) | v0.3 |
| 3 | Goal at 2:04.7, right goal (owner: 2:05 ± 10 s; time found on frames) | **No** in v0.2: goal mouth fully in frame 36% of 2:02.7–2:05.7. **Yes** in v0.3: 100% | v0.2, v0.3 |
| 3 | Chance at 1:25, left goal, no goal (owner) | **No** in v0.2: goal mouth fully in frame only 28% of 1:23–1:26, cut by the left edge. **Yes** in v0.3: 100%, keeper and attack visible | v0.2, v0.3 |
| 2 | Chance at 3:38, left goal, no goal (owner) | **Yes** in both, but in v0.2 the goal is a tiny corner of the frame and a third of the frame is the logo on the near grass; v0.3 shows goal, keeper and players large (frames compared 3:35–3:41) | v0.2, v0.3 |
