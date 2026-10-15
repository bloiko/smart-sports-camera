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

**Twitches** (a pan > 8 px/frame reversed within 0.5 s): 1.5–3.3 per minute for Core ML, Python 1.0–2.5. Most happen in goal mode while no ball is accepted (match 3 at 2:20–2:23: three 200 px swings without a ball): the goal-mode target moves between goal and players. Next: hold the goal-mode target while the ball is lost.

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
