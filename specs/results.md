# Results

Living document. Add a row for every new model or pipeline version, per match. Definitions of the metrics are in `../docs/testing-strategy.md`.

Last updated: 2026-10-12 (session 4: causal live camera, Swift port)

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

| Match | Version | Ball in crop | First 2 min | Players | Pan mean / > 900 px/s | Jerk p95 | Checklist |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | offline v0.3 | 99.7% | 100% | 62% | 64 / 0.2% | 233 | 1/1 |
| 1 | live, buffer 0 s | 97% | 91% | 64% | 143 / 0.7% | 1252 | 0/1 |
| 1 | live, buffer 1 s | 97% | 94% | 64% | 124 / 1.1% | 518 | 1/1 |
| 1 | live, buffer 2 s | 97% | 94% | 64% | 119 / 1.2% | 328 | 1/1 |
| 1 | live, buffer 5 s | 97% | 94% | 64% | 120 / 1.4% | 326 | 1/1 |
| 2 | offline v0.3 | 98% | 100% | 56% | 94 / 0.7% | 266 | 4/4 |
| 2 | live, buffer 0 s | 92% | 91% | 58% | 150 / 1.4% | 1297 | 3/4 |
| 2 | live, buffer 1 s | 92% | 91% | 58% | 130 / 1.4% | 639 | 3/4 |
| 2 | live, buffer 2 s | 92% | 92% | 58% | 126 / 1.4% | 464 | 4/4 |
| 2 | live, buffer 5 s | 92% | 92% | 58% | 126 / 1.4% | 484 | 4/4 |
| 3 | offline v0.3 | 100% | 100% | 63% | 72 / 0.2% | 252 | 2/2 |
| 3 | live, buffer 0 s | 73% | 77% | 63% | 318 / 1.1% | 3908 | 2/2 |
| 3 | live, buffer 1 s | 81% | 77% | 64% | 189 / 2.2% | 1924 | 2/2 |
| 3 | live, buffer 2 s | 81% | 77% | 63% | 196 / 2.7% | 475 | 2/2 |
| 3 | live, buffer 5 s | 81% | 77% | 63% | 202 / 2.9% | 404 | 2/2 |

Final settings of 2026-10-11 (session 3). Changes since the first live run, each checked on the checklist: goals of a side play has not reached yet are mirrored through the halfway line (`centre_line` in `goals.py`, found in the first 10 s); goal mode is held 2 s after an attack (without it the match 1 goal was lost once the goals were right from the start); no border zoom in goal mode (it cut the goal post); when the curved panorama border hides the crossbar the crop shifts up to 150 px towards the centre (match 2, 3:38). The shift adds camera movement in match 3 (pan mean 156 → 196 px/s); phone footage has no curved border, so it should not trigger there.

### Live goals in the first minutes (`LiveGoals`)

Max error (px) of the live goal estimate against hand-measured goals, left / right:

| Match | Method | 30 s | 60 s | 90 s | Worst after 2 min |
| --- | --- | --- | --- | --- | --- |
| 1 | players only | 877 / 420 | 793 / 52 | 745 / 44 | 50 |
| 1 | + mirror through the halfway line | 478 / 420 | 115 / 52 | 108 / 44 | 50 |
| 2 | players only | 900 / 67 | 401 / 67 | 231 / 67 | 186 |
| 2 | + mirror | 54 / 67 | 54 / 67 | 231 / 67 | 186 |
| 3 | players only | 898 / 57 | 897 / 56 | 93 / 56 | 295 |
| 3 | + mirror | 125 / 57 | 124 / 56 | 93 / 56 | 295 |

Why players alone fail early: in matches 1 and 2 nobody (not even the keeper, who plays far out while the ball is in the other half) stood within 120 px of the left goal during the first 60 s, also in the offline detections. The halfway line (found by scanning near-vertical lines for white pixels) mirrors one goal onto the other with 55–72 px error when the other goal is known. Mirroring only replaces a side when the mirror is more than 300 px further out (smaller thresholds overrode good estimates later: match 1 right goal 43 → 124 px). Before 30 s there is no estimate at all; in match 1 both sides are still unknown at 30 s.

Conclusions:
- **Buffer 2 s is the minimum and enough**: all 7 events pass; 0 s fails 2 events and jerks 3–8× more; 1 s fails one event; 3–5 s add nothing measurable (the camera can only use the future up to its smoothing window and the 2 s goal-mode anticipation; anticipating 5 s showed empty goals while play was still in midfield). A 5 s buffer is safe but gives no extra quality with this algorithm.
- Live loses most where the ball is hard to see: match 3 (evening, pale grass) 81% ball in crop vs 100% offline. The live ball search finds the ball on 10% of passes in match 3, 28% in match 1, 47% in match 2; 44% of offline balls in match 3 were inside a live search tile.
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

## Live camera, strictly causal (2026-10-12)

The batch simulator of 2026-10-11 quietly looked further ahead than its buffer (goal-mode anticipation up to B frames beyond f + B, ball confirmation 0.6 s beyond, field depth from the first 64 s before frame 0, border shift 2 s ahead, field mask and image bounds from the whole video). `src/live_cam.py` is the streaming rewrite: frame f is emitted when frame f + B arrives and sees nothing later; the field mask, image bounds and halfway line come from the first 10 s only (the position check on the phone). Detection unchanged except the mask. `LiveGoals` now works on a 1/4 grid with its own Gaussian kernel (no cv2), so the Swift port gives the same numbers. Same inputs as the 2026-10-11 table, buffer 2 s.

| Match | Version | Ball in crop | First 2 min | Players | Pan mean / > 900 px/s | Jerk p95 | Checklist |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | live 2 s, batch (2026-10-11, border shift look-ahead 0) | 97% | 94% | 64% | 115 / 1.1% | 292 | 1/1 |
| 1 | live 2 s, causal, 10 s mask | 93.5% | 88% | 65% | 119 / 1.5% | 347 | 1/1 |
| 2 | live 2 s, batch | 92% | 92% | 58% | 121 / 1.3% | 393 | 4/4 |
| 2 | live 2 s, causal, 10 s mask | 92% | 94% | 59% | 98 / 1.3% | 307 | 4/4 |
| 3 | live 2 s, batch | 81% | 77% | 63% | 193 / 2.7% | 475 | 2/2 |
| 3 | live 2 s, causal, 10 s mask | 78% | 77% | 64% | 123 / 2.7% | 288 | 2/2 |

Notes:
- The border-shift look-ahead (2 s in the batch version) was measured first on its own: 0 gives the same 7/7 and a slightly smoother camera on all matches, so it is 0 now (`shift_la_s`).
- The 10 s mask costs ball in crop in matches 1 and 3 (ball found 28.1% → 24.3% and 9.6% → 8.5% of passes): with the game already running in the first 10 s, the median of 7 frames keeps some players and the mask edge moves. On the phone the position check runs before kick-off, so this is a pessimistic simulation.
- Live goals in match 3: the right goal drifts to (3287, 860) after 150 s (truth (3088, 565)); the estimate only grows outward and players walking to the corner flag pull it. Same in the old code (checked); the checklist still passes because the goal at 2:04 is before the drift. Backlog 3c item 4.

### Swift port vs Python (2026-10-12, `ios/FolloCore`, Mac)

Checked on the same inputs, all three matches, buffer 2 s (`src/compare_swift.py`, `compare_env.py`, `follosim track`):

| Stage | Test | Result |
| --- | --- | --- |
| Camera (`LiveCamera.swift` vs `live_cam.py`) | Same detections and environment | X, Y, crop width and height differ by 0.0000 px on every frame; goal mode, goal index and accepted balls identical; 1–2 s per match |
| Ball tracker (`BallTracker.swift` vs `detect()`) | Python candidates replayed | 0 ROI mismatches and 0 ball mismatches in 2979–3000 ball frames per match |
| Pre-game environment (`FieldMask.swift`, `CentreLine.swift` vs `fieldmask.py`, `centre_line`) | Same 7 frames of the first 10 s | Mask IoU 0.988–0.996; image bounds within 3 px except a few columns; halfway line within 1 px |
| Core ML detection (`Detector.swift`, exported YOLO11s 1280×672 and `ball_v02` 640×640, NMS inside) | Whole video, Mac (ANE/GPU) | see the table below |

Core ML detection on the Mac (`follosim detect`, fp16 models, same tracker and camera as above, buffer 2 s), compared with the Python detection (Ultralytics on MPS) on the same videos. `matched` = Python player boxes (conf ≥ 0.25) with a Swift box of IoU ≥ 0.5; `both` = frames where both accepted a ball, and how many of them agree within 20 px.

| Match | Players matched | Ball found (Python → Core ML) | Both, within 20 px | Ball in crop (Python → Core ML) | Checklist (Python → Core ML) | Detection time, Mac |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 99.1% | 24.3% → 28.8% | 455, 68% | 93.5% → 91.6% | 1/1 → 1/1 | 125 s (players 55 ms per 2 tiles, ball 8 ms per ROI) |
| 2 | 97.5% | 46.3% → 48.1% | 1122, 87% | 91.8% → 93.2% | 4/4 → **3/4** | 113 s (43 ms, 11 ms) |
| 3 | 76.5% | 8.5% → 28.1% | 195, 91% | 77.8% → 92.4% | 2/2 → 2/2 | — |

- Match 2, attack at 1:02.3 (ball rolls into the penalty area): goal mouth in frame 45% (Python 91%, a thin pass). Cause in the Core ML run: a static look-alike at (2974, 201) accepted as the ball for about a second (background difference 15–25, right at the `BG_MIN` = 15 threshold), so goal mode started 1.2 s later. Not a camera-logic difference (the logic is identical); a detector-noise difference. Backlog 3c item 4: make the static filter robust to repeated same-spot detections.
- Match 3 is 3840×1504: the fixed Core ML input 1280×672 letterboxes a 1970×1504 tile to 880×672, while Ultralytics' rectangular inference gave 1280×992, hence fewer players matched (76.5%). The ball model (fixed 640×640 ROI) is unaffected and finds the ball 3× more often than the MPS run, which is unexplained (fp16 vs fp16, different resampling). The player input size must be chosen per frame shape: for the phone's 16:9 4K frame this is still open (backlog).
- An export with `half=False` gives byte-identical detections: Ultralytics 8.4 ignores `half` for Core ML (it warns to use `quantize`), so the models are whatever its default is; precision is not the cause of the differences.
- Core ML speed on the M1 Mac is about 3× faster than Ultralytics on MPS (players 43–55 ms vs 134–223 ms per 2 tiles); the phone will be slower, to be measured.

## Highlights from the live recording (2026-10-12, `src/live_highlights.py`, Swift port `ios/FolloCore/Highlights*.swift`)

What the phone does after Stop: moments from the live camera path (goal-mode episodes, scored as in `highlights.py`), kick-offs by jersey colour from samples taken every 8th frame during the live (every 2nd player frame), the last episode before a kick-off = goal, clips 16:9 and 9:16 with the close-up camera, rendered on the phone (`ClipRenderer.swift`, AVAssetWriter + CoreImage; checked on the Mac).

| Match | Kick-offs (Python / Swift) | Clips | Checklist events in a clip | Goal labelled |
| --- | --- | --- | --- | --- |
| 1 | 195.2 s (0.77) / 194.6 s (0.77) | 3, 55 s, identical in Swift | 1/1 | yes (both) |
| 2 | none / none | 4, 63 s, identical | 3/4: the 0:13.5 attack is before the first goal estimate (30 s), so no goal-mode episode | — |
| 3 | 148.2 s (0.77) / **131.2 s (0.78)** | 5, 82 s | 2/2 | Python: the real goal (2:04.7); Swift: a wrong earlier episode |

- Jersey sampling density: every 20th frame missed the match 3 kick-off (peak 0.75), every 4th misses both (0.76–0.77); every 8th finds both at exactly the 0.77 threshold. The separation peaks of real kick-offs are 0.77–0.78 and the best false ones 0.69–0.75: **no margin**. Python and Swift differ by up to 0.1 in the separation curve (k-means on jersey colours starts at random; own Lab conversion), enough to flip the match 3 result. The kick-off criterion must become more robust before it labels goals on the phone (backlog 3c item 4).
- Clip rendering: Swift and Python frames of the same clip compared visually (`work/m1/live_pre/clip_compare.jpg`); the Swift label is drawn with CoreImage text instead of OpenCV's Hershey font.

## Live algorithms on the simulator (2026-10-12, backlog 3c item 4)

### Live goals: drift to the corner flags, fixed with a y-guard (`LiveGoals(dy_max=60)`)

Error of the live goal estimate vs the hand-measured goals (px, left / right as |Δx|, |Δy|) over time, cached live detections, `src/exp_livegoals.py`. The estimate only grows outward; corner kicks build heat at the corner flags and pull the tips there late in the match (on a 90-minute match always). The y-guard accepts an outward move only when the tip's y changes by ≤ 60 px (a corner pull is a jump in y; a better view of the goal moves the tip in x).

| Match | Rule | 30 s | 60 s | 120 s | end |
| --- | --- | --- | --- | --- | --- |
| 1 | baseline | 480,35 / 421,5 | 119,21 / 55,9 | 18,50 / 45,10 | 35,48 / 45,10 |
| 1 | y-guard 60 | same | same | 109,20 / 45,10 | 109,20 / 45,10 |
| 2 | baseline | 56,38 / 22,68 | same | 187,3 / 22,68 | **185,249 / 335,279** |
| 2 | y-guard 60 | 56,38 / 22,68 | same | same | 56,38 / 22,68 |
| 3 | baseline | 127,123 / 59,10 | 127,121 / 58,12 | 1,93 / 58,12 | **1,93 / 199,295** |
| 3 | y-guard 60 | same | same | 127,121 / 58,12 | 127,121 / 58,12 |

Rejected: tips by column mass (≥ 5–20% of the busiest column), region threshold 6 s, the densest spot near each end (keeper + penalty area: 100–300 px too far inside). With the y-guard the camera checklist stays 7/7 and match 2 gets smoother (pan 98 → 86 px/s, jerk 307 → 261); ball in crop 93.5 → 95.0% (1), 91.8 → 92.3% (2), 77.8 → 75.7% (3). Swift port identical (SAME PATH on all three).

### Goals before 30 s and pitch memory

Without data nothing works: the first estimate at 10–20 s is 300–900 px off (match 2: L 368 / R 313 at 15 s), and `goal_min_data_s` = 15 or 20 drops the match 2 checklist to 1/4; it stays at 30 s. **Pitch memory** instead: matches 1 and 2 are the same stadium on different days with the camera in the same place (hand-measured goals within 13 px, halfway line within 6 px, field mask IoU 0.81 because of shadows). With the final estimate of match 1 as the prior for match 2 (`--set goals_prior=…`, `PitchMemory.swift` in the app), goal mode works from the first second: the 0:13.5 attack gets a highlight clip (before: no episode, since goals were unknown), checklist 4/4, Swift identical. Matching rule in the app: same frame size, mask IoU ≥ 0.75, halfway line ends within 30 px.

### Kick-off (goal) signal: no margin found

`src/exp_kickoff.py` on the jersey samples of all three matches (real kick-offs at 195 s in match 1 and 148 s in match 3; best false peak at least 20 s from them):

| Statistic | Real kick-offs | Best false | Margin |
| --- | --- | --- | --- |
| current: mean of team separation over 2 s | 0.77, 0.77 | 0.75 | +0.02 |
| min of the two teams' shares, 2 s | 0.74, 0.66 | 0.65 | +0.02 |
| 1 s / 3 s median / 4 s windows | — | — | −0.01 / −0.02 / +0.00 |
| product of the shares, 2 s | 0.59, 0.58 | 0.53 | +0.05 |
| separation × player stillness (median displacement between player frames) | — | — | ≤ +0.02 (players also stand still at throw-ins and fouls; detection jitter 3–5 px) |

Conclusion: team separation from live detections cannot label goals reliably; the GOAL label needs another cue (owner question: the crowd/bench noise after a goal from the phone's microphone, the ball at the centre spot after a goal-area episode, or the user confirming the goal in the result screen).

### Ball search in the evening match (match 3), detection rerun with phone budget

| Variant | Ball found (passes) | Ball in crop | Checklist | Cost |
| --- | --- | --- | --- | --- |
| baseline (2 ROIs while lost, conf 0.4) | 8.5% | 75.7% | 2/2 | — |
| 3 ROIs while lost | 11.4% | 77.1% | 2/2 | +1 ball pass (≈ 14 ms on the Mac) per lost frame |
| conf 0.3 while searching | 11.7% | 75.7% | 2/2 | more false candidates, no gain in crop |

Neither is switched on: the evening match needs a better ball detector (model v0.3 on the three matches, backlog P1), not a wider search.

## Spare balls and the phone environment (2026-10-15, owner: "the camera jumps and shows someone else")

Found on the phone (test-video source, match 2): the Core ML models see real spare balls lying beyond the touchline (match 2 at 0:42, a ball boy at 2:14–2:17) and the camera drove there; the phone also built the field mask on 1/4-resolution frames with full-resolution kernels (crop ~20% wider). Fixes: re-acquiring a lost ball, a candidate far from players (3 heights) or from the play centre (800 px) is taken only when it flies (4–60 px per frame since the first look); three looks within 15 px over ≥ 0.5 s put it on the black list; the phone environment is built at full resolution (3.2 s on the iPhone 15). Swift and Python: SAME TRACK and SAME PATH on all 3 matches.

`python src/eval_live.py N PATHS…`, buffer 2 s. Jumps = frames whose crop centre moves > 20 px.

| Match | Path | Jumps | Ball in crop | Checklist |
| --- | --- | --- | --- | --- |
| 1 | Python before → after | 2.87% → 1.37% | 95.0% → 96.6% | 1/1 → 1/1 |
| 1 | Core ML before → after | 3.88% → 1.62% | 91.6% → 91.3% | 1/1 → 1/1 |
| 2 | Python before → after | 1.18% → 1.39% | 92.3% → 96.6% | 4/4 → 4/4 |
| 2 | Core ML before → after | 3.47% → 1.59% | 93.2% → 92.9% | 3/4 → 3/4 (1:02.3, known static look-alike at (2974, 201)) |
| 3 | Python before → after | 3.13% → 3.25% | 75.7% → 79.9% | 2/2 → 2/2 |
| 3 | Core ML before → after | 2.83% → 1.54% | 92.4% → 90.3% (3 track points) | 2/2 → 2/2 |

On the phone (match 2 from 0:14, 160 s): jumps 2.4–5.4% → 2.0%, crop width 1284 → 1062 px (Mac 1030–1044), memory ~590 MB, 25 fps in real time. Frames old vs new at 0:41–0:46 and 2:13–2:18: the old camera showed empty grass by the spare balls and the ball boy, the new one stays on the play.

## Core ML aligned with Python; player tiles for the phone's 16:9 frame (2026-10-15)

**Frame alignment.** Matches 2 and 3 start with an empty edit (video after audio: 1.68 s, 0.98 s). AVAssetReader then decodes the first picture once more at time 0, cv2 does not: Swift frame f was Python frame f − 1. Every earlier Core ML vs Python comparison (players matched, "Core ML finds the ball 3× more often in match 3", the static look-alike at 1:02.3) was made one frame apart, and the tracker amplified it. `VideoReader` now skips that picture (also the test-video source on the phone).

**Resampling.** `follosim ballroi VIDEO DIR` runs the Core ML ball model on Python's own ROIs (match 2, aligned): bilinear in linear light finds 99% of Python's balls ≥ 0.4 and 95% of its own are Python's; bicubic a = −0.75 without colour management (as `cv2.resize(..., INTER_CUBIC)`) gives 100% / 99%. Now the default (`Detector.cvLike`).

| Match | Core ML before → after: ball in crop | Checklist | Jumps | Python (same tracker) |
| --- | --- | --- | --- | --- |
| 1 | 91.3% → 97.8% | 1/1 → 1/1 | 1.62% → 2.00% | 96.6%, 1/1, 1.37% |
| 2 | 92.9% → 93.8% | 3/4 → **4/4** | 1.59% → 1.46% | 96.6%, 4/4, 1.39% |
| 3 | 90.3% → 78.5% | 2/2 → 2/2 | 1.54% → 3.21% | 79.9%, 2/2, 3.25% |

Core ML now behaves like Python; the 1:02.3 failure is gone (it was a resampling artefact, not a static object). Match 3 (evening) is weak for both; its earlier 90% was an accident of the shifted frames.

**Player tiles on a 16:9 frame.** Core ML has a fixed 1280×672 input; two full-height tiles of a 3840×2160 frame are shrunk to 0.31 (panoramas: 0.62). New: on frames with W/H < 2.2 the tiles cover only the pitch band (field-mask rows + 120 px above) at the model's aspect ratio, at most 3 tiles (panoramas unchanged, detections identical). Test: matches 2 and 3 padded to 16:9 (4096×2304, 3840×2160), whole matches, same detection time:

| Match | Tiles | Players per frame | Ball in crop | Jumps | Checklist |
| --- | --- | --- | --- | --- | --- |
| 2 | full height → pitch band | 31.8 → 45.4 | 92.6% → 92.9% | 1.34% → 1.23% | 4/4 → 4/4 |
| 3 | full height → pitch band | 22.1 → 39.0 | 72.2% → 78.5% | 2.93% → 1.94% | 2/2 → 2/2 |

**On the phone** (iPhone 15, test video match 2, 0:40–2:47, real time 25 fps, memory ~600 MB, thermal ok): mean distance to the Mac Core ML path 39 px (before today 150–300 px); jumps 1.20% (before 2.4–5.4%); twitches 1.4 per minute (Mac Core ML before: 3.3); ball in crop 94.3%; scoreboard in the stream frame.

**Twitches** (a pan > 8 px/frame reversed within 0.5 s): 1.5–3.3 per minute for Core ML, Python 1.0–2.5. Most happen in goal mode while no ball is accepted (match 3 at 2:20–2:23: three 200 px swings without a ball): the goal-mode target moves between goal and players. Next: hold the goal-mode target while the ball is lost.

## Goal mode without swinging (2026-10-16, owner: "the camera swings between the goal and the players")

Cause (camera internals, match 3 at 2:20–2:25): the goal weight follows the number of players in the goal zone, an integer that jumps 1–5 from frame to frame; each player moved the target ~225 px, and equal counts at both ends flipped the target to the other goal for a moment. Fixes in `live_cam.py` / `LiveCamera.swift` (Python = Swift, SAME PATH on 3 matches): the count is averaged over `zn_avg_s` = 1 s; the chosen goal is sticky (the other one only when its weight is higher by more than `gi_keep` = 0.25); the ball weight fades over `ball_fade_s` = 1 s after the 0.6 s hold instead of dropping to zero (alone it changed nothing measurable). All three set to 0 give the old path exactly.

| Match | Twitches per minute, Python old → new | Core ML old → new | Jumps, Core ML | Ball in crop, Core ML | Checklist |
| --- | --- | --- | --- | --- | --- |
| 1 | 1.5 → 1.0 | 2.2 → 1.8 | 2.00% → 1.70% | 97.8% → 97.8% | 1/1 (goal mouth in frame 97% → 100% in Python) |
| 2 | 1.0 → 1.0 | 1.5 → 1.5 | 1.46% → 1.36% | 93.8% → 93.8% | 4/4 |
| 3 | 2.5 → 0.3 | 3.3 → 0.8 | 3.21% → 2.28% | 78.5% → 78.5% | 2/2 |

Before/after videos (match 3 2:18–2:28, match 1 goal 2:50–2:58) rendered side by side: before, the camera drifts left at 2:21.8–2:23.4 and cuts the right goal during the attack; after, it holds the attack with the goal.

## Own stack, stage 1a: own H.264 encoder (2026-10-16, Mac)

`FolloCore/VideoEncoder.swift` (VideoToolbox, system framework): H.264 High, no B-frames, a keyframe every 2 s, average
bitrate with a 1.5× one-second cap, BT.709 colour conversion and tags. Test: `follosim encode VIDEO PATH.json OUT.mp4`
takes the stream frames (1080p crops of the camera path, as `LiveCameraRunner.emit`). "Before" is the same Apple hardware
encoder driven by ffmpeg with HaishinKit-like settings (`h264_videotoolbox`, 4.5 Mbit/s, High, GOP 50, no B-frames) on
the same frames (`--raw-stdout`). PSNR is measured against the uncompressed crops.

| Test | Result |
| --- | --- |
| Validity (match 2, 10 s) | 250/250 frames, 0 dropped, High profile, no B-frames, decodes without errors |
| Quality, 4.5 Mbit/s | ours 39.98 dB average (worst frame 36.4), before 40.04 dB (worst 35.2): equal |
| Colour | Untagged, VideoToolbox and ffmpeg used different RGB→YUV matrices (looked like 6 dB worse). Now BT.709 conversion and tags; HaishinKit's stream today is untagged |
| 60 s, matches 2 and 3 | 1500/1500 frames each, average 4495 / 4497 kbit/s, per-second peak 5391 / 5148 (cap 6750), keyframes every 50 frames |
| Bitrate steps 4500 → 3000 → 2000 | Followed within the same second; a forced keyframe lands on its frame and the 2 s rhythm continues from it |
| 1080p vs 720p at 2 Mbit/s | 36.5 vs 36.3 dB (720p upscaled): equal, so the low step keeps 1080p (no new session, no new stream header) |
| Speed (M1) | ~150 fps, 6× real time; encoder latency 62–70 ms when frames arrive faster than real time |
| Frames | Ours at 4.5 Mbit/s and the reference look the same; 2 Mbit/s softens the grass texture |

## Own stack, stage 1b: own FLV packaging (2026-10-16, Mac)

`FolloCore/FLV.swift`: FLV tag bodies (AVC sequence header from VideoToolbox's own avcC, AVC NALU packets, end of
sequence; AAC bodies for stage 1e), AMF0 encoding, onMetaData, and `FLVWriter`. The tag bodies are exactly the RTMP
message payloads, so stage 1c reuses them. Test: `follosim encode … --flv OUT.flv` writes our FLV next to the MP4 of the
same encoded frames. The reference is ffmpeg's FLV of that MP4 (`ffmpeg -i x.mp4 -c copy ref.flv`). `flvcmp` parses
both files tag by tag and checks PreviousTagSize and that no bytes trail.

| Run | Result |
| --- | --- |
| Match 2, 10 s | Packet tables (pts, dts, size, flags) identical; H.264 elementary streams identical (5,594,011 bytes); 252/252 video tags identical (body and timestamp) |
| Match 3, 60 s | 1502/1502 video tags identical |
| Match 2, 12 s with bitrate steps and a forced keyframe | 302/302 identical |
| Decoding | ffmpeg decodes our FLV without errors; onMetaData (AMF0) is parsed (`encoder=Follo`) without warnings |

Difference found and fixed: ffmpeg ends the stream with an AVC end-of-sequence tag; ours now does too.

## Own stack, stage 1c: own RTMP(S) client (2026-10-16, Mac)

`FolloCore/RTMPClient.swift` on Network.framework does the whole publishing side:
- the simple handshake (C0/C1/C2);
- the commands: set chunk size 4096, then connect → releaseStream, FCPublish, createStream → publish;
- @setDataFrame onMetaData, and audio and video messages split into chunks, with extended timestamps;
- the server's control messages: chunk size, window ack, set peer bandwidth, ping, and acknowledgements;
- FCUnpublish and deleteStream when closing, and TLS for rtmps.

Test: `follosim encode … --rtmp URL --key KEY` publishes the same packets it writes to `--flv`. The server is ffmpeg on
the Mac (`ffmpeg -listen 1 -i rtmp://127.0.0.1:1935/live/test -c copy recv.flv`). "Before" is ffmpeg itself as the
client, sending the same FLV.

| Test | Result |
| --- | --- |
| Protocol | Connect.Success → createStream → Publish.Start, clean close; the server sees H.264 High 1920×1080 25 fps BT.709 |
| Match 2, 10 s | 252/252 video tags received identical to the ones sent (body + timestamp); same as with ffmpeg as the client |
| Match 3, 60 s, real time | 1502/1502 identical, 0 dropped, 4497 kbit/s |
| Extended timestamps (start at 16,777,000 ms, crossing 0xFFFFFF) | Bodies 252/252 identical; ffmpeg's server shifts the timeline to start at 0, exactly as it does for ffmpeg as the client (our and ffmpeg's received files are identical) |
| RTMPS through a local TLS proxy (self-signed, test flag) | TLS 1.2, Publish.Start, 252/252 identical |
| RTMPS without the test flag | Refused: "bad certificate" (certificate checks are on by default, as needed for YouTube) |
| No server / wrong URL | Fails in under a second with a clear reason, no hang |

The ffmpeg server logs "Error during demuxing: Input/output error" at the end for both clients: it is how it reports
the publisher leaving. Still to test: a real YouTube RTMPS ingest (possible from the Mac once the stream key exists).

## Own stack, stage 1d: network-drop buffer and reconnect (2026-10-16, Mac)

`FolloCore/FolloStreamer.swift` keeps a ring of encoded frames, 180 s by default (~100 MB at 4.5 Mbit/s). A sender paces
the frames to `RTMPClient` and handles drops:
- **Detection.** A drop is: the server closes the connection; an error; no acknowledgement for long enough while data is
  waiting; or a stall of the send buffer.
- **Reconnect.** Every 2 s.
- **Resend.** On a new connection it sends the headers first, then frames from the last keyframe before the first
  unacknowledged frame.
- **Pacing.** Frames are paced in real time by default (a delay line), or with `catchUp` > 1 to win the delay back.
  `jumpToLive()` drops the backlog.

`RTMPClient` asks the server for an acknowledgement every 256 KB (Window Acknowledgement Size) and maps the acknowledged
byte count to message numbers.

**Test setup.**
- `follosim stream` encodes match 2 in real time into the streamer and writes every frame it produced to `sent.flv`.
- `src/netfault.py` is a local proxy that cuts the link on a schedule: `reset` closes the connection and refuses new
  ones; `blackhole` silently stops passing bytes (mobile data that just stops).
- ffmpeg `-copyts -listen 1` records every connection, restarted in a loop.
- `src/stream_check.py` matches every produced frame with everything received, by content.

| Scenario (stream 90–120 s, drop at 30 s) | Result |
| --- | --- |
| No drop, 30 s | 750/750 delivered, 1 connection, delay 0 |
| Reset 10 s / 30 s | 0 missing; 45–48 duplicates (≤ 1 GOP: the new connection must start at a keyframe) |
| Blackhole 60 s | 0 missing; 45 duplicates; drop noticed 4.2 s after the link stopped (8.0 s before acknowledgements) |
| Blackhole 60 s, ring only 30 s | 804 frames (32 s) lost by design: the ring kept the last 30 s; recovered at a keyframe, 0 duplicates |
| Reset 30 s, catch-up 1.5× | 0 missing; delay at 105 s: 9.5 s (32 s without catch-up) |
| Server acknowledging on its own cadence (2.5 MB), no drop, 90 s | 0 false reconnects, 2250/2250 |
| The same server, blackhole 60 s | Noticed after 4.3 s, 0 missing |
| Jump to live after reset 30 s | Delay 31.9 s → 2.0 s; the 749 skipped frames are the intended skip; continues at a keyframe |
| Decoding after reconnect and jump | ffmpeg decodes every received stream without errors |

**Bugs found and fixed on the way.**
- Frames went out before the AVC header when the connection was ready before the first frame: the server could not read
  the stream and closed it.
- A failed reconnect attempt reset the position and re-sent the whole ring: 746 duplicates, which would have meant 30 s
  shown twice.
- "Handed to the system" was taken as "received by the server": 5 frames would have been lost. It is replaced by the
  server's acknowledgements.

**Still to test on YouTube.** Whether it honours our acknowledgement window, and how it treats a re-sent GOP with
earlier timestamps on a new connection.

## Own stack, stage 1e: own AAC audio (2026-10-16, Mac)

`FolloCore/AudioEncoder.swift` encodes AAC-LC on AVAudioConverter (system framework): PCM in, 1024-sample packets out,
plus its own AudioSpecificConfig. Tests use `follosim aacenc VIDEO OUT.flv` and `follosim stream … --audio`, which adds
the match audio in step with the video. "Before" is the same Apple encoder through ffmpeg (`aac_at`, 128 kbit/s) on
the same audio.

| Test | Result |
| --- | --- |
| Match 2, 20 s, 48 kHz mono | 937 packets for 959,872 samples, 125 kbit/s, AAC LC, decodes without errors |
| Quality vs the source | ours SNR 41.6 dB, before (ffmpeg `aac_at`) 34.8 dB |
| Loudness | Equal to the source (−49.4 dB); the match 3 track is digital silence in the source itself (−91 dB) |
| Stereo, 440 Hz left / 880 Hz right | Channels correct |
| Stream with audio, 30 s, no drop | Video 750/750, audio 1413/1413; the server sees H.264 1080p + AAC 48 kHz; decodes cleanly |
| Stream with audio, reset 30 s | Video 0 missing, 46 duplicates; audio 0 missing, 78 duplicates (the same 1.7 s resent from the keyframe) |

Audio leads video by the AAC encoder delay (2112 samples, 44 ms at 48 kHz), the same as ffmpeg. Lip-sync on the phone
uses the capture timestamps of the camera and the microphone, so it is checked in stage 1f on the device.

## Own stack, stage 1f: in the app behind a switch (2026-10-16, Mac build)

`Streamer` keeps HaishinKit as the default and gains `Streamer.engine`. A debug build switches it from the setup screen or
`--streamer follo|haishinkit`; release builds always use HaishinKit. `FolloEngine` (app) holds three parts:
- the encoders;
- the microphone (AVAudioEngine) with lip-sync: camera frames carry host-clock capture times, the same clock as the microphone;
- `MediaInterleaver` (FolloCore): audio waits until the 2 s-delayed video reaches its time.

The live screen shows "Ефір відстає на N с" and a "Наздогнати ефір" button when the stream runs behind after a drop.
For phone tests, `Documents/debug/rtmp_target.txt` streams to a local server instead of YouTube.

| Check (Mac) | Result |
| --- | --- |
| `follosim interleave` (60 s, audio 2 s ahead of video) | 1800/1800 video, 2811 audio out, 94 waiting for later video (the last 2 s), 0 dropped, strictly time-ordered |
| iOS build Debug and Release (`generic/platform=iOS`) | Succeeded. Swift 6 concurrency: the new classes run on their own serial queues, marked `@unchecked Sendable` |
| Rollback | Tag `before-own-streamer`, debug switch, release default HaishinKit |

Not yet run on the phone. The checks are in `docs/run-on-iphone.md`: before/after against a local server, Wi-Fi drops,
90 minutes, YouTube.

## Own stack, stage 1f on the phone: before/after (2026-10-16, iPhone 15)

**Setup.**
- The phone streams the test video (match 2) to ffmpeg on the Mac over home Wi-Fi.
- The Mac firewall blocks ffmpeg, so a relay listens on 1935. It runs on Apple's own python, which the firewall lets
  through, and forwards to ffmpeg on 127.0.0.1:19350.
- **Before:** `--streamer haishinkit`. **After:** `--streamer follo`.

**Same length, clean runs (86 s each):**

| | HaishinKit (before) | Follo (after) |
| --- | --- | --- |
| Frames | 2148, 24.98 fps | 2162, 24.98 fps |
| Bitrate | 4511 kbit/s | 4503 kbit/s |
| Frame intervals > 100 ms (judder) | **541** (timestamps in 0.12/0.2 s steps) | **0** (capture timestamps) |
| Colour tag | none | BT.709 |
| Audio | AAC 48 kHz | AAC 48 kHz |
| Decode errors | 0 | 0 |
| Phone memory (max) | 582 MB | 634 MB |

**Other runs.**
- **Two earlier HaishinKit runs** stopped by themselves at about 45–50 s: the server got no frames after a reconnect
  while the phone showed "live", and the test video reader ended early.
- **The third HaishinKit run** was clean for 80 s. The earlier failures may partly come from the app going to the
  background, so they do not count as proof against HaishinKit.

**Follo for 5 minutes.**
- 7368 frames at 4499 kbit/s, no decode errors.
- Memory rises while the 180 s drop buffer fills, then stays at 713–727 MB from 3 minutes on. This is not a leak.
- Thermal state "ok" all the time.
- The only 1.7 s gap is the test video looping back to its start, not the stream.

**Follo with drops on the phone.** The relay on the Mac is paused for 30 s (a silent drop) and later killed for 15 s
(a hard drop).

| | Result |
| --- | --- |
| Silent drop | Noticed after 4.4 s (no acknowledgement); reconnected 1 s after the network returned, 32.7 s behind live |
| Hard drop | Noticed at once; reconnect every 2 s, back 1 s after the network returned, 52.6 s behind live |
| Delivery over 3 connections | Video 0.00–130.80 s: 3266 unique frames, 0 gaps > 0.1 s, 167 duplicates (~3 s per reconnect); audio 0 gaps; 0 decode errors |

A harness bug cost one run: `pkill -f relay.py` also killed the shell loop that restarted ffmpeg. Drops are now done by
process ID (`phonedrops.sh`).

**Still to do:**
- a private YouTube broadcast: does it honour the acknowledgement window, and how does it take a re-sent GOP;
- 90 minutes with Follo;
- lip-sync with the real camera (a clap);
- the owner's decision to make Follo the default.

## Own stream: 90 minutes on the phone (2026-10-16)

The first attempt found a real gap: after iOS briefly suspended the app, the hardware encoder session became invalid
(−12903) and silently produced nothing, while the phone still showed "live". Fixed with self-healing in
`VideoEncoder`: recreate on an error status (same frame, forced keyframe), on return to the foreground, and by a 2 s
no-output watchdog. Checked on the Mac (invalidated mid-stream: 1000/1000 frames) and on the phone (sent to the
background via Settings for 10 s: new session, reconnect in 2 s). The live log now prints encoder and streamer counters
every 10 s.

**Second attempt: 91 min**, test video in a loop, Follo, charging, 4K recording on.

| | |
| --- | --- |
| Received | 129,816 frames over 5475 s; the only gaps are the test video looping (1.7 s every 240 s) and 236 s while the app was in the background |
| Lost by the stream | 0; 99 duplicates after the reconnect |
| Encoder | 129,645 in / 129,642 out, 2 recreations (background and return) |
| Memory | 344–803 MB, flat |
| Thermal | "serious" from 65 min, never "critical"; bitrate stepped to 3000 kbit/s; the stream went on |
| 4K chunks | 28 completed; the one interrupted by the background opens with 170 of 180 s (10 s fragments) |
| Storage | The test recording used 10.7 GB (deleted afterwards; 13.8 GB free) |

**Open issues.**
- The app went to the background at 33 min without any action from the Mac; the cause is unknown. The app should warn
  loudly when it leaves the screen.
- Heat after one hour while charging indoors.
- A real match needs about 20 GB at the 30 Mbit/s 4K recording rate.

## Field of view and per-match storage (2026-10-16)

**Field of view.** Formats of the iPhone 15 ultra-wide, measured on the phone:
- every 16:9 format is 107.8° horizontal, and Follo already records 3840×2160 at 107.8°;
- the 4:3 formats are 105.2° horizontal, but cover about 89° vertical against about 75°;
- turning off geometric distortion correction changed the view by about 1% in a side-by-side test. Not worth the curved lines.

The owner's native Camera clip was 1080p60 with stabilisation, which crops the edges, so it looks narrower than the same
spot in Follo. The view that looked much wider in the app was the test video (a stitched panorama of match 2): the
test-video source had been left on after the test runs.

**Per-match folders**, checked on the phone with `--stop-after`:
- every recording went into its own folder, and no `chunk_001` was overwritten;
- recordings killed mid-way stay listed as "recording" and their chunk opens up to the last fragment (20 s);
- highlights are saved per match.

`follosim join`: 3 real phone chunks (180 s + 170 s interrupted + 60 s) became one 410 s file in 1.3 s without
re-encoding; the joins decode cleanly. Saving to Photos confirmed on the phone by the owner (2026-10-16): the video appears in Photos.

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

## Private YouTube broadcast on the own stream (2026-10-16)

- m2 test video from the iPhone 15 with `--streamer follo` to `rtmps://a.rtmps.youtube.com/live2` (Studio stream key): YouTube answered `NetStream.Publish.Start` on the first connection; 200 s with encoder in = out, 0 drops, 0 errors, nothing in flight (YouTube acknowledges everything), memory ~760 MB, thermal ok.
- Restarted twice (relaunch, new build): publishes again within 1 s of GO LIVE.

## Bitrate from what the server acknowledges (2026-10-17, Mac)

`follosim stream … --adaptive` through `src/netfault.py` limited to 2.5 Mbit/s (`0:throttle2500:900`), match 2 from 20 s:

| Run | Bitrate | Delay behind live | Frames |
| --- | --- | --- | --- |
| Before (fixed 4.5 Mbit/s), 120 s | 4500 | 4.7 s at 30 s, 18.8 at 60 s, 56 at 115 s, growing | 62 lost at the end (drain ran out) |
| After, first version (steps 4500/3000/2000/1200, 80% of a 10 s window) | 4500 → 1200 at 10 s → 2000 at 150 s | 0.1 s from 45 s | all 5458 delivered |
| After, measurement between acknowledgement arrivals, steps 4500/3500/2500/1800/1200 | 4500 → 1200 at 15 s → 1800 at 155 s | 1.0 s (the catch-up floor) from 60 s | all delivered |
| Control: no throttle, advisor on, 120 s | 4500, no change | 0.0 s | all delivered |

Found on the way: the server acknowledges in large windows (ffmpeg: several MB), so a 10 s window sometimes held
no acknowledgement and "measured" 1 Mbit/s on a 2.5 Mbit/s link. The rate is now taken between acknowledgement
arrivals over up to 30 s. "Steady" is a delay under 1.5 s, because automatic catch-up stops at 1 s.

## Catching up small delays and short trips to the background (2026-10-17)

**Catch-up threshold 5 s → 1.5 s** (`FolloStreamer.Config.autoCatchUpAboveS`). Mac, match 2 from 20 s, one reset of
1 s at 30 s (`30:reset:1`), as on the phone after a one-second trip to the background:

| Run | Delay after the reconnect | Later | Frames |
| --- | --- | --- | --- |
| Before (5 s) | 3.9 s | 3.9 s until the end (115 s) | all delivered |
| After (1.5 s) | 3.9 s | catch-up at 1.25× from 52 s, 1.9 s at 60 s, 1.0 s from 70 s | all delivered |
| Regression: 2.5 Mbit/s link with the bitrate advisor | 2.2 s at the step down | 1.0 s from 60 s, step up to 1800 at 155 s | all delivered |

**Background task during the match.** The app asks iOS for background time when it leaves the screen during a match,
so the socket to YouTube stays open; `--no-bg-task` switches it off for before/after.
- The simulator does not reproduce the problem: without the task, 5 s in the background cost no reconnect either.
- The UI test (`test8b`) found a crash in the first version: `Int(backgroundTimeRemaining)` of iOS's "infinite" value.
  It is fixed.
- Before/after needs the phone: a 1–5 s swipe out during a match, with and without `--no-bg-task`.

## FolloNet-B probe: own ball network vs today's YOLO ball model (started 2026-10-17)

**Setup.**
- Samples (`src/ballnet_data.py`): 256×256 native crops from m1–m3, as 3 frames + background + ball position.
  - Positives: the v0.3 offline track plus linear interpolation between track points (interpolated frames are where no
    detector looked).
  - Negatives: live YOLO false positives, spare balls, players' feet.
  - Sizes: m1 2434, m2 3174, m3 1470 crops.
- Labels checked on contact sheets (`src/ballnet_sheet.py`):
  - interpolated positives sit on the ball;
  - YOLO false positives are logo letters ("of"), bottles, cones and many spare balls by the touchline.
- Our network (`src/ballnet.py`): 0.50 M params, own code, from scratch, stride-2 heatmap plus offset.
- Training: m1+m2 (first 80%), 25 epochs on the M1 (≈6.5 min per epoch).
- m3 is never seen in training: it is the "unseen match".
- Ablations: full (3 frames + background + tracker prior), nobg, noprior, f1 (a single frame, like YOLO's input).

**Baseline: `models/ball_v02.pt` on the same crops** (frame t upscaled 2×, as live; `src/ballnet_yolo.py`),
threshold 0.4:

| Match / part | Recall ≤ 4 px | on interpolated frames | false alarms: player feet | false alarms: spare balls |
| --- | --- | --- | --- | --- |
| m1 last 20% | 0.79 | 0.76 | 0.08 | 0.90 |
| m2 last 20% | 0.71 | 0.69 | 0.10 | — |
| m3 (all; the unseen stadium) | 0.23 | 0.21 | 0.06 | 0.43 |

Caveats:
- False alarms on the "fp" crops are high for YOLO by construction: those crops are YOLO's own false positives.
- The labels come from the offline pipeline, which itself uses this YOLO model, so the comparison favours YOLO on track
  frames.
- Our network after 1 epoch (m1+m2 last 20%): recall 0.54, false alarms 0.035.

**First result (2026-10-17): full model, 25 epochs on m1+m2** (`work/ballnet/full/eval.json`). The fair parts are the
last 20% of m1/m2 and the whole of m3 (never seen). YOLO at 0.4, ours at 0.3:

| Part | Recall: YOLO → ours | Interpolated frames | Spare balls taken for the ball | Player feet false alarms | Ball found but > 4 px off |
| --- | --- | --- | --- | --- | --- |
| m1 last 20% | 0.79 → **0.84** | 0.76 → 0.81 | 0.90 → **0.00** | 0.08 → 0.08 | 0.07 → 0.07 |
| m2 last 20% | 0.71 → 0.72 | 0.69 → 0.69 | — | 0.10 → 0.03 | 0.12 → 0.13 |
| m3, unseen stadium | 0.23 → **0.46** | 0.21 → 0.44 | 0.43 → **0.03** | 0.06 → 0.07 | 0.10 → **0.20** (worse) |

Open questions:
- Our network sees the tracker prior and YOLO does not (in the live pipeline YOLO gets it only as the ROI centre); the
  noprior ablation will say how much of the gain is the prior.
- On m3 the network more often marks a wrong spot, maybe by trusting a wrong prior.
- The training queue was killed when the Claude app quit. It now runs in `screen -S ballnet`
  (`work/ballnet/run_all.sh`, resumable).

**Phone budget (2026-10-17, `src/ballnet_coreml.py`).** Core ML FP16, iOS 17 target, timed on the Mac's M1 Neural Engine
next to today's ball model:

| | FolloNet-B full (ROI 320×320, 13 channels) | Today's YOLO ball model (640×640) |
| --- | --- | --- |
| Params | 0.50 M | 2.6 M |
| Compute | 3.37 GMAC (6.7 GFLOPs) | ≈ 6.5 GFLOPs |
| Time per ROI, CPU + Neural Engine | **2.25 ms** | 5.88 ms |
| Time per ROI, CPU only | 14.5 ms | — |

- **Compute plan.** Every operation runs on the Neural Engine (14 conv, 12 relu, 2 nearest upsample, 2 concat,
  1 sigmoid). Peak picking stays in Swift.
- **Phone budget.** The live pipeline runs ≤ 2 ROIs every 2nd frame, so ≈ 4.5 ms per 66 ms on the M1. The A16 Neural
  Engine is faster than the M1's, so the iPhone 15 carries it with room to spare, and with less heat than today's
  model.
- **Still to solve on the phone.** The input needs crops of frames t-1 and t-2: keep the last two ROI-sized crops (or
  two frames) and build the 13-channel input with Accelerate. That is a few ms of CPU, to be measured in Swift.

**Ablation: no background channel (2026-10-17).** Same training (m1+m2, 25 epochs); YOLO at 0.4:

| Part | Recall: YOLO / full / **nobg** | Interpolated | Wrong spot | Spare-ball false alarms | Player false alarms |
| --- | --- | --- | --- | --- | --- |
| m1 last 20% | 0.79 / 0.84 / 0.81 | 0.76 / 0.81 / 0.77 | 0.07 / 0.07 / 0.08 | 0.90 / 0.00 / 0.00 | 0.08 / 0.08 / — |
| m2 last 20% | 0.71 / 0.72 / **0.75** | 0.69 / 0.69 / 0.73 | 0.12 / 0.13 / 0.12 | — | 0.10 / 0.03 / 0.00 |
| m3 last 20% | 0.13 / 0.41 / **0.50** | 0.11 / 0.39 / 0.46 | 0.07 / 0.27 / 0.25 | 0.40 / 0.04 / 0.02 | 0.09 / 0.06 / 0.00 |
| m3 all (unseen) | 0.23 / 0.46 / **0.54** | 0.21 / 0.44 / 0.51 | 0.10 / 0.20 / 0.21 | 0.43 / 0.03 / 0.01 | 0.06 / 0.07 / 0.03 |

- The background channel does not help, not even on the unseen stadium; without it the network is equal or better.
- Spare balls are rejected by the 3 frames alone: a still ball does not move.
- For the phone this is simpler: 10 input channels instead of 13, and no median frame to keep.
- Still open: about a fifth of the hits on m3 are more than 4 px off. The noprior run tells whether a wrong tracker
  prior causes it.

## FolloNet-B in the live simulator (2026-10-18)

**Setup.**
- `BALL_NET=nobg python src/live_sim.py …`: our network replaces the YOLO ball model on the same ROIs.
  - Input: 3 native frames plus the prediction as prior.
  - Thresholds: 0.3 and 0.2.
  - Code: `src/ballnet_live.py`. The players model is unchanged.
- Baseline: the same YOLO detections (`live_pre/live_det.jsonl`) rerun through the **current** camera code
  (`work/mN/live_yolo_now`). The old `live_pre/run.log` numbers came from older camera code and overstated the
  smoothness gap.

| m3, unseen stadium, buffer 2 s | YOLO | FolloNet-B nobg |
| --- | --- | --- |
| Ball found on ball passes | 8.5% | **31.0%** |
| Reference ball in crop | 0.722 | **0.847** |
| first 2 min | 0.771 | 0.800 |
| pan_mean / pan_over_900 / acc_p95 | 80.2 / 1.36 / 188 | 85.8 / 1.22 / 204 |
| Checklist | 2/2 | 2/2 |

- **Gain: the camera shows the ball more often**, +12.5 points on the unseen stadium. Smoothness is about the same.
- **Frames:** the goal at 2:04 has the goal mouth in frame in both versions (`work/ballnet/frames/m3_goal_2m04.jpg`).
- **Speed:** on the Mac, PyTorch MPS takes 56 ms per ROI (while training runs). That is not the phone number: Core ML
  on the Neural Engine is 2.25 ms.
- **m1/m2** (seen in training except the last 20%) — YOLO with the current code:
  - m1: ball in crop 0.941, checklist 1/1;
  - m2: ball in crop 0.923, checklist 4/4.
  - Own-network runs are in progress.

**m1/m2 with FolloNet-B nobg, and a regression (2026-10-18).**

| Match | Ball in crop: YOLO → ours | Checklist |
| --- | --- | --- |
| m1 | 0.941 → 0.953 | 1/1 |
| m2 | 0.923 → 0.960 | **3/4** |
| m3 (unseen) | 0.722 → 0.847 | 2/2 |

**The failure: m2 0:13.5 right attack**, goal mouth in frame 73%.
- The network lost a fast far pass (frames 218–326, ball at about 2800–3260 px, y 210–380): no peak even inside the
  right ROI. It found the ball again only once it stopped (0.96).
- Version 2 (prior only while tracking) did not change it: still 3/4, m3 0.833.
- **Cause: missing training data.** The offline track has points 30 frames apart there, and interpolation took only
  gaps ≤ 10 frames, so fast far passes were nearly absent from training.
- **Not ready to replace YOLO yet** (project rule: every checklist event passes).

**v3, running overnight** (`work/ballnet/night_v3.sh`):
- **Dataset `work/ballds_v3`.** Adds fast-pass positives where the live YOLO tracker agrees with the track line in
  gaps ≤ 60 frames (+191 samples).
- **Synthetic fast passes (`--synth`).** On 40% of ball-less crops, a real ball sprite (only pixels brighter than the
  grass) flies over the grass at 3–15 px per frame, with motion blur. Checked on a contact sheet
  (`work/ballnet/synth_sheet.jpg`).
- **Then:** crop evaluation, then the live simulator on m3, m2, m1 with the checklists.

## Match-day check before the first real match (2026-10-18)

- UI tests on the iPhone 17 simulator, foreground, one group at a time: 1, 2, 3, 4, 5, 6, 7, 8b, 9 all passed
  (8a is the reference run without the background task). 8b: 0 reconnects on a 5 s trip to the background.
- Fixed: the half-pitch mode could not be switched back to the whole pitch (segmented Picker, then Toggle). Now a
  button; log shows `mode: half pitch, 1×` → `mode: whole pitch, 0.5×`.
- xcodebuild sometimes hangs for minutes after "Selected tests passed" under load; the results are already final.
- Debug build installed on the owner's iPhone 15. Default stays: whole pitch 0.5×, HaishinKit/Follo switch unchanged.

## First real match, 2026-10-18: what came back from the phone

- Pulled to `work/phone_2026-10-18/` (git-ignored): one match only, `match_2026-10-18_14-09-08`, 100 s of 4K HEVC
  (3840×2160, 30 fps, 351 MB), YouTube link youtu.be/dSOqoZm0UC4; camera path 93 s, ball found in 205 of 1990 rows.
- The log of that broadcast is lost: `DebugLog.reset()` deleted log.txt on every app start, and the app was opened
  again at 14:15. That launch: position check in 14 s, "left goal may be out of frame", app sent to the background at
  14:15:50, not opened again until 18:41.
- Fix: the 5 previous logs are kept as log_1…log_5.txt (built, not yet installed on the phone).

## FolloNet-B v3 and v4 (2026-10-18/19): fast passes help the crops, not yet the camera

Crops (held-out last 20%), ball found / false alarms:

| | nobg (current live net) | v3 (fast passes + synthetic balls) | v4 (fast passes only) |
| --- | --- | --- | --- |
| m1 | 0.806 / 0.004 | 0.814 / 0.034 | 0.805 / 0.004 |
| m2 | 0.745 / 0.108 | 0.775 / 0.222 | 0.761 / 0.089 |
| m3 unseen | 0.495 / 0.036 | 0.425 / 0.180 | **0.522 / 0.040** |

Live simulator (buffer 2 s), ball in crop / pan_mean / checklist (v3 ran with BALL_NET_PRIOR=always, v4 and nobg in
the normal prior mode):

| | nobg | v3 | v4 |
| --- | --- | --- | --- |
| m1 | 0.953 / 84 / 1/1 | 0.944 / 103 / 0/1 | 0.907 / 77 / **0/1** (goal 2:54.8 89% in frame) |
| m2 | 0.969 / 89 / 3/4 | 0.764 / 81 / 3/4 | 0.943 / 115 / 3/4 (0:13.5 fast pass 0% → 48%) |
| m3 | 0.833 / 89 / 2/2 | 0.729 / 110 / 2/2 | 0.833 / 102 / **1/2** (chance 1:25.0 69% in frame) |

- Synthetic fast balls (v3) taught the net to fire on small blobs: 2–5× more false alarms, worse on unseen m3. Dropped.
- v4 is the best net on crops and the first one that moves the m2 fast pass, but it loses two checklist moments in the
  camera. Not adopted: nobg stays the BALL_NET candidate; YOLO stays the default.
- Frames (2026-10-19): both lost moments are v4 firing on **players' feet** with score 0.5–0.66. m1 2:54.8: the legs of
  a far player at the touchline (1670, 177) pull the camera 240 px right for 0.3 s exactly at the goal. m3 1:25.0: the
  current net sees the real ball (1211, 422) going to the left goal; v4 misses it and takes the white socks of a player
  at the centre circle (1850, 350). Training data: 29% of the m2 fast-pass positives sit at a player's feet (ordinary
  track points: 16%); m1 10% vs 4%. One run per version, so part of the nobg/v4 difference may be training noise.

## FolloNet-B v5 (2026-10-19): first net that keeps every checklist moment

Data v5 = v3 fast passes minus those at a player's feet (`--clean-feet`: m1 5 of 44, m2 34 of 85, m3 1 of 22) plus
boots/socks negatives, far players first (`--more-feet`: m1 94 → 685). Two seeds (v5a seed 1, v5b seed 2).

Crops, all nets on the same v5 val crops (ball found / false alarms / false alarms at feet):

| | nobg | v4 | v5a | v5b |
| --- | --- | --- | --- | --- |
| m1 | 0.790 / 0.014 / 0.026 | 0.780 / 0.016 / 0.031 | 0.810 / 0.016 / 0.031 | 0.799 / 0.019 / 0.031 |
| m2 | 0.739 / 0.041 / 0.024 | 0.776 / 0.023 / 0.005 | 0.756 / 0.028 / 0.010 | 0.790 / 0.032 / 0.014 |
| m3 unseen | 0.464 / 0.019 / 0.019 | 0.536 / 0.042 / 0.038 | 0.510 / 0.032 / 0.031 | 0.495 / **0.396** / 0.371 |

Live simulator (buffer 2 s, normal prior mode), ball in crop / pan_mean / checklist:

| | nobg | v4 | v5a | v5b |
| --- | --- | --- | --- | --- |
| m1 | 0.953 / 84 / 1/1 | 0.907 / 77 / 0/1 | 0.931 / 84 / **1/1** | 0.947 / 72 / 1/1 |
| m2 | 0.969 / 89 / 3/4 | 0.943 / 115 / 3/4 | 0.966 / 95 / **4/4** | 0.926 / 96 / 4/4 |
| m3 | 0.833 / 89 / 2/2 | 0.833 / 102 / 1/2 | **0.854** / 95 / **2/2** | 0.708 / 116 / 1/2 (1:25.0 17%) |

- v5a: 7/7 checklist moments, the first net that keeps the m2 0:13.5 fast pass (0% with nobg). Frames
  (compare_crops m2 0:11–0:15): v5a is at the right goal from 0:11, nobg only from 0:13.
- v5b, same data, other seed: 40% false alarms on unseen m3 and loses m3 1:25.0. Training is not stable yet; v5a may be
  a lucky seed. Needs a third seed and a match none of them has seen before v5a can replace nobg as the candidate.

## The owner's own footage (18.10, iPhone 15, 4K 0.5×, 97 s) in the live simulator (2026-10-19)

`work/m4phone/` (git-ignored). Unseen by every net, no ground truth: judged by eye. About 65 s of the 97 s is an
injury stoppage; real play only from ~1:06.

| | ball found on ball passes | pan_mean | pan_over_900 |
| --- | --- | --- | --- |
| YOLO (today's default) | 49.2% | 66 | 0.49 |
| nobg (current candidate) | **4.2%** | 38 | 0.78 |
| v5a | 41.4% | **136** | **2.84** |

- nobg is almost blind on the owner's camera. v5a finds the ball often but also fires on players' feet and on grass and
  fence spots (frames at 33, 60, 75, 82, 94 s), so the camera is twice as jumpy as with YOLO. YOLO is the steadiest here.
- Conclusion: trained on two panorama matches only, our nets do not yet generalise to the owner's phone. The next real
  gain is training data from the owner's own full matches (auto-labelled offline by the teacher + v0.3 tracker).
- Separate finding: the recording has 2044 frames in 97 s = **21 fps on average instead of 30**: the phone dropped
  frames during the broadcast. To investigate before the next match.

## Why the 18.10 recording had 21 fps, and the fix (2026-10-19)

- Frame gaps in chunk_001.mp4: 1540 single steps, 247 double, 236 triple, ~5 drops every second for the whole
  recording; the phone's path.csv also has ~21 rows a second. So frames were lost before the recorder: detection,
  the live camera and the output crop all ran on the camera queue (~47 ms a frame), and AVCaptureVideoDataOutput
  (alwaysDiscardsLateVideoFrames) threw away the late camera frames.
- Fix: the camera queue only records and copies the frame; LiveCameraRunner processes on its own queue
  (`follo.pipeline`) with at most 2 frames waiting; a frame it cannot take is skipped for the stream only, the file
  keeps it. `--sync-pipeline` (debug) restores the old way for a before/after on the phone.
- New log lines every 10 s: `frames …: delivered N (fps), dropped late / out of buffers / other, recorder busy,
  handler ms`, and every 300 frames `pipeline: avg / max ms, skipped for the stream`.
- Simulator: UI tests 1, 7, 8b pass. Not yet measured on the phone.
