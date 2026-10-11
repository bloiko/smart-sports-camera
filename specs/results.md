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

With the 3 attacks added to match 2 later: 7 of 7 checklist events are inside a highlight clip.

**Review by Claude (2026-10-11, frames every 2 s of all three reels):** about 10 of 17 clips show a real moment near the goal; the weak ones are mostly "players in the goal zone, no ball": the keeper alone with players far away, or play in midfield with the camera framing the goal. All three clips with danger < 0.3 were weak and none held a checklist event, so the default threshold is now 0.3: 14 clips, 48 / 56 / 98 s, still 7 of 7 events. Other findings: hard cuts between clips with no time label (the viewer loses which goal and when); some clips start at the centre circle; goals on the far side look small in a 16:9 crop.

The danger score does not single out goals yet: the match 3 goal scores 0.50, below three non-goal clips. Clip windows were tuned on these 4 events (first version cut the match 1 goal at the clip start because the peak was the celebration, the second dropped the match 3 chance).

### Goal recognition by kickoff (`src/kickoff.py`, 2026-10-11)

| Match | Goals (checklist) | Kickoffs found | Max team separation | Clips labelled GOAL |
| --- | --- | --- | --- | --- |
| 1 | 2:54.8 | 3:14.8 (20 s after the goal), confirmed on frames | 0.80 | 1, correct |
| 2 | none | none | 0.68 | 0 |
| 3 | 2:04.7 | 2:28.0 (23 s after the goal) | 0.80 (start of video, a kickoff with no goal before it: 0.74) | 1, correct |

Closer highlight camera (2026-10-11): crop height 300–480 source px (median 347 for 16:9, 480 for 9:16). Checked on frames of both goals: goal, keeper, scorer and ball in frame in both formats. In these stitched panoramas the curved top border keeps far-side goals in the upper third of the frame; in match 1 the ball near the goal is mostly undetected, so the camera aims between the goal and the main camera.

Threshold 0.77. The margin is small (0.80 vs 0.74) and rests on 2 goals: re-check on every new video. With goals marked, the reels are 52 / 56 / 103 s; goals-only reels 23 s and 25 s.

## Live simulator (`src/live_sim.py`, 2026-10-11)

Real-time camera with a phone-like budget: players = 2 tiles at 1280 px every 4th frame; ball = 1 tile of 320 px (upscaled 2×) every 2nd frame around the predicted ball, 2 tiles while it is lost, `ball_v02.pt` only; goals from already-seen players only (`LiveGoals`, first estimate after 30 s); the camera for frame f sees data up to f + buffer. Compared with offline v0.3 on the same videos. `ball in crop` = share of the offline ball track inside the live crop; `jerk` = 95th percentile of horizontal acceleration (px/s²); checklist = events passing `check_goals.py`.

| Match | Version | Ball in crop | Players | Pan > 900 px/s | Jerk p95 | Checklist |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | offline v0.3 | 99.7% | 62% | 0.2% | 233 | 1/1 |
| 1 | live, buffer 0 s | 94% | 62% | 1.2% | 1381 | 0/1 |
| 1 | live, buffer 1 s | 95% | 62% | 1.0% | 454 | 1/1 |
| 1 | live, buffer 2 s | 96% | 61% | 1.2% | 284 | 1/1 |
| 1 | live, buffer 5 s | 96% | 62% | 1.3% | 282 | 1/1 |
| 2 | offline v0.3 | 98% | 56% | 0.7% | 266 | 4/4 |
| 2 | live, buffer 0 s | 94% | 57% | 1.7% | 1276 | 3/4 |
| 2 | live, buffer 1 s | 94% | 57% | 1.8% | 565 | 3/4 |
| 2 | live, buffer 2 s | 94% | 57% | 1.5% | 351 | 4/4 |
| 2 | live, buffer 5 s | 94% | 57% | 1.6% | 347 | 4/4 |
| 3 | offline v0.3 | 100% | 63% | 0.2% | 252 | 2/2 |
| 3 | live, buffer 0 s | 72% | 64% | 2.7% | 4153 | 2/2 |
| 3 | live, buffer 1 s | 74% | 64% | 2.2% | 1375 | 2/2 |
| 3 | live, buffer 2 s | 74% | 63% | 2.6% | 337 | 2/2 |
| 3 | live, buffer 5 s | 74% | 63% | 2.6% | 310 | 2/2 |

Conclusions:
- **Buffer 2 s is the minimum and enough**: all 7 events pass; 0 s fails 2 events and jerks 4–12× more; 1 s fails one event; 3–5 s add nothing measurable (the camera can only use the future up to its smoothing window and the 2 s goal-mode anticipation; anticipating 5 s showed empty goals while play was still in midfield). A 5 s buffer is safe but gives no extra quality with this algorithm.
- Live loses most where the ball is hard to see: match 3 (evening, pale grass) 74% ball in crop vs 100% offline. The live ball search finds the ball on 10% of passes in match 3, 28% in match 1, 47% in match 2; 44% of offline balls in match 3 were inside a live search tile.
- Goals in live: wrong for the first ~60–100 s of a broadcast (one side off by up to 900 px: people near the corner flags), then within 30–130 px. The goal margin (`goal_unc` 80 px; 120 and 150 tested) made no difference.
- What fixed live failures (each verified on the checklist): two player tiles instead of one (one 1280 px pass on a 4096 px panorama lost 40% of far players), ball candidates only on the pitch, blacklisting a "ball" that stays still 3 s with no player near (a person behind the fence in match 2), confirming a ball by a second nearby detection, widening the crop up to 1.35× when the ball is lost (match 3: 63% → 83% ball in crop before later changes), vertical constraints for the goal, border zoom.
- Time on this Mac per call (not a phone measurement): player pass 134–193 ms for 2 tiles, ball tile 19–24 ms. The phone budget (≈ 33 ms per frame at 30 fps) is not verified; a 4K phone frame of a small pitch has larger players than these 4096 px panoramas, so one tile may be enough there.

## Processing speed (2026-10-11, MacBook Air M1 8 GB, MPS)

Match 1, 4:00 of 4096×1080 video, whole pipeline from scratch (`pipeline.py`).

| Mode | Detection | Ball window (2 models) | Background check | Camera + render | Highlights (16:9 + 9:16) | Total | 90-min match (extrapolated) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Before: step 5, full precision, libx264, debug video | 613 s | 411 s | 66 s | ~300 s | — | ~23 min | ~8.5 h |
| Fast: step 15, half precision, VideoToolbox, no debug video | 157 s | 161 s | 37 s | 91 s | 80 s | 8.9 min (7.5 without highlights) | ~2.8 h without highlights |

Quality of the fast mode against step 5 on match 1: checklist PASS, goal labelled, kickoff 3:15.6 (vs 3:14.8), goals within 2 px, ball found 28.7% (26.8%), in crop 100% (99.7%), players 61% (62%), camera |dX| median 24 px; precision 23 of 24.

Sparser sampling simulated on all matches by thinning the step-5/10 detections (`specs/results.md` numbers from `follow.py --no-render`): up to step 20 all 7 checklist events pass, both kickoffs are found and no false goal appears; from step 30 a false kickoff appears at the start of match 3, at step 60 a false goal. Default step chosen: 15.

Other measurements: video decoding 2.7 ms per frame (not a bottleneck); player detection per sampled frame 321 ms (3 tiles at 1280), 266 ms with half precision, 187 ms at 960 px and 87 ms for the whole frame at 1920 px (fewer small players detected; not evaluated yet); batching the 3 tiles was slower (389 ms). Ball models: YOLO11s alone loses a third of the balls (match 1: 17% vs 27%), `ball_v02.pt` alone fails the match 2 attack at 1:02 — both are kept. Render of 60 s: 24 s (libx264 + debug), 14 s (VideoToolbox, no debug).

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

**Summary (2026-10-11): v0.3 passes 7 of 7 events (2 goals, 2 chances, 3 attacks); v0.2 passes 3 of 7.**

Machine-readable lists live in `specs/checklists/matchN.json` (goal mouths measured by hand + events); `src/check_goals.py` checks them. Matches 2 and 3 have one event each from the owner.

| Match | Goal / shot (time) | Visible in output? | Version |
| --- | --- | --- | --- |
| 1 | Goal at 2:54.8, left goal (owner: 2:50–2:57) | **No**: camera ~800 px to the right of the goal | v0.2 |
| 1 | Goal at 2:54.8, left goal | **Yes**: goal mouth in frame 100% of 2:52.8–2:55.8 (automatic goals) | v0.3 |
| 3 | Goal at 2:04.7, right goal (owner: 2:05 ± 10 s; time found on frames) | **No** in v0.2: goal mouth fully in frame 36% of 2:02.7–2:05.7. **Yes** in v0.3: 100% | v0.2, v0.3 |
| 3 | Chance at 1:25, left goal, no goal (owner) | **No** in v0.2: goal mouth fully in frame only 28% of 1:23–1:26, cut by the left edge. **Yes** in v0.3: 100%, keeper and attack visible | v0.2, v0.3 |
| 2 | Attacks at 0:13.5 (right), 1:02.3 (right), 2:59.0 (left), found by Claude on zoomed goal areas | v0.2: 2 of 3 (1:02.3 fails, mouth in frame 33%). v0.3: 3 of 3 | v0.2, v0.3 |
| 2 | Chance at 3:38, left goal, no goal (owner) | **Yes** in both, but in v0.2 the goal is a tiny corner of the frame and a third of the frame is the logo on the near grass; v0.3 shows goal, keeper and players large (frames compared 3:35–3:41) | v0.2, v0.3 |
