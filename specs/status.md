# Status by phase

Living document: update it at the end of every work session (see `.claude/skills/project-docs/SKILL.md`). The stable plan for each phase is in `../docs/phases.md`.

Last updated: 2026-10-12 (session 4: Follo app, Core ML camera)

| Phase | Status |
| --- | --- |
| 0. Test footage | Partially done: 3 public panoramic matches; no own iPhone footage yet |
| 1. Offline prototype | Done (v0.1), with caveats |
| 2. Tracking quality and own model | In progress (v0.3 camera done: goal-area framing; model v0.3 next) |
| 3. iOS app (Follo) | In progress: skeleton + Core ML virtual camera in Swift (verified on the Mac), edge-case items 1–6, 8–14 in code, highlights after Stop, onboarding and My matches screens; nothing run on a phone yet |
| 4. Everyday use and beta | Not started |
| 5. YouTube live | Live simulator on the Mac, now strictly causal (buffer 2 s passes all 7 checklist events); Swift port identical |
| 6. Android, full pitch, highlights | Not started |

---

## Phase 0: test footage

**Status:** partially done.

**Done**
- Three 4-minute panoramic videos of university matches (see `datasets.md`): two at one stadium (winter sun, spring overcast) and one at another stadium (evening, different camera and resolution).

**To do**
- The owner's own iPhone 15 footage (ultra-wide, 4K, tripod 2–3 m high).
- Evening game under floodlights.
- A full 40–90 minute recording to measure heat and battery.
- Golden clips with manual ball positions and a goal checklist.

**Difficulties**
- The cloud sandbox cannot download from Hugging Face or Kaggle, so the owner uploads videos; files over ~300 MB from the Mac had to be split into parts and rejoined.
- Public footage is a 3-camera stitched panorama mounted high: cleaner than a single phone, with curved black borders.

**Lessons learned**
- Public panoramic matches are a fast way to start, but results will be worse on a single phone. Do not tune parameters only on them.

---

## Phase 1: offline prototype

**Status:** done (v0.1) with caveats: the exit criterion "ball in frame ≥ 80% of the time" was only measured on frames where the ball was found.

**Done**
- `detect.py`, `follow.py`, `fieldmask.py`: player and ball detection on 3 tiles, virtual camera with dead zone, two-sided smoothing, speed limit, depth-aware zoom, debug render, metrics.
- v0.1 on match 1: ball found in 13% of samples; when found, in frame 94%; 72% of on-field players in frame; max pan speed 363 px/s.

**Difficulties**
- The off-the-shelf COCO "sports ball" class cannot see the ball on the far side (5–8 px).
- A motion-based ball finder (frame differencing) failed: it picked up shadows, grass glare, trees and nets. Kept as `src/ball_motion.py` (experimental, unused).
- The only "balls" found at first were spare balls at the touchline: added a static-ball filter.
- Spectators and people outside the pitch pulled the camera: added the field mask.
- Sandbox restarts killed background jobs: all long steps became resumable chunks (append to output, restart from the last frame).
- CPU only (2 cores): detection takes ~0.5–1 s per sampled frame.
- Chat uploads are limited to 30 MB: outputs are shared as 720p, 2-minute parts.

**Lessons learned**
- Framing by the main group of players already looks acceptable; the ball refines it.
- Offline two-sided smoothing gives a calm camera without lag.
- Look at contact sheets of detections before trusting any metric.

---

## Phase 2: tracking quality and own model

**Status:** in progress. v0.2 done; v0.3 camera (goal-area framing, F7) done on 2026-10-11; model v0.3 not started.

**Done**
- `ball_window.py`: ball search in a 2× upscaled window around the camera view (match 1: 13% → 21% of samples with a ball).
- Self-training without manual labels: pseudo-labels from confident detections plus interpolated frames → `models/ball_v02.pt` (YOLO11n, 320 px patches, CPU). Held-out last 20% of match 1: raw detection 40% vs 19% for the base model.
- Cross-match tests: match 2 (same stadium) 66% with both models merged; match 3 (new stadium) 26%.
- `merge_balls.py`: union of models with per-model thresholds.
- Pipeline made stadium-independent: adaptive field mask, detection band from the mask, field depth from player positions, crop kept inside the image content.
- `make_dataset.py` rewritten for multi-match datasets: ball size fitted from real boxes, labels snapped to the ball blob, off-field labels dropped, negatives away from any ball.
- v0.3 camera (`follow.py`), 2026-10-11:
  - Goal-area mode: on when the ball is near a goal or the goal area holds clearly more players than usual (attack); the crop frames the goal mouth, the ball and the players near the goal. The match 1 goal (2:54.8) is now in frame 100% of the time (v0.2: 0%).
  - Goals found automatically with no user input and no third-party model (`src/goals.py`: tips of the area where players spend the match); error ≤ 62 px in x and ≤ 81 px in y on all 6 goals.
  - Ball as a hard constraint (inside the crop with a margin), short track gaps filled; ball in crop 98–100% (v0.2: 82–90%).
  - Spare-ball filter: a ball lying still for 2 s or returning to the same spot for 60 s with no player within 1.3 player heights. Removed the logo letter "f" and corner-flag balls; precision 22–24 of 24 on all matches.
  - Smooth catch-up instead of jumps when the ball reappears far away (two-sided speed cap 2250 px/s).
  - Background filter (`src/ball_bgdiff.py`): a "ball" that looks the same as the median background is a static look-alike (letters painted on the grass, dummies) and is dropped. Owner spotted the logo letter "O" counted as a ball in match 2.
  - Border zoom: near the pitch ends the crop zooms in (up to 25%) instead of showing empty near-side grass under the curved panorama border.
  - Players in frame fell from 64–71% to 56–62%: the price of keeping the ball and goals in frame.
- `src/pipeline.py`: the whole pipeline in one command with skip and resume (tested by interrupting detection on a 40 s clip; 2.4 min for 40 s of video).
- `src/highlights.py` (F13): clips of goal-area episodes with a time label and fade-in; all 7 checklist events are inside a clip. Goals recognised by the kickoff that follows them (`src/kickoff.py`: teams by jersey colour, each team in its own half): both test goals labelled GOAL, no false goals; goals-only reel available.
- Processing 3× faster with the same results (step 15, half precision, VideoToolbox, no debug video): 7.5 min per 4 minutes on the M1 Air instead of ~23.
- Closer camera for highlights and vertical 9:16 (F6, `src/closeup.py`): ~0.65 of the main crop aimed at the ball, or at the goal when the ball is lost in goal mode; both goals look much larger than in the main video.
- Tools: `src/check_goals.py` (automatic goal checklist), `src/ball_sheet.py` (precision contact sheets), `follow.py --no-render / --range / --set / --goals`, MPS (Apple GPU) in `detect.py` and `ball_window.py`. Pipeline now runs on the owner's M1 Mac (detection of 4 minutes ≈ 11 min).

**To do** (details and priorities in `backlog.md`)
- Keep growing the goal checklist (7 events now: v0.3 passes 7/7, v0.2 3/7).
- Model v0.3: train on 3 matches using the cleaner v0.3 ball tracks, evaluate on held-out minutes of each.
- Switch to an Apache-2.0 detector before any closed release.
- Manual labels for hard cases; golden clips with ground truth; goal checklist.
- Lead the play; widen the crop when uncertain.
- Check Core ML export.

**Difficulties**
- v0.2 overfitted to match 1: alone it was worse than the base model on match 2 (52% vs 59% raw detections).
- Match 3's pale grass broke the fixed-colour field mask (only a strip in the middle was found).
- Interpolated pseudo-labels drift up to ~20 px when the ball curves; some "balls" were people behind a fence.
- Training at 640 px, batch 16 ran out of the 8 GB RAM: switched to 320 px patches with no dataloader workers.
- Every command has a 10-minute limit: training and detection run in resumable chunks.
- With the current detection band the v0.2 tracker accepted logo letters and spare balls at the corner flag as the ball (about 40% of its "found" balls in match 1), so earlier match 1 numbers were optimistic.
- Finding goals by the keeper (extreme player) failed by up to ~800 px: ball boys and substitutes stand by the corner flags all match. White goal posts on the median frame were also unreliable: fences and practice goals look the same, and far-side lines in match 3 are dark.
- In goal-area mode a wide crop in these stitched panoramas becomes tall, and the curved black top border pushes it down, so the goal ended up small in a corner. Fixed by framing only the action near the goal (crop ≈ 980 px instead of 1760).
- Switching the goal constraint on and off made the camera jump (up to 14,000 px/s); fixed with hysteresis, minimum episode length and constraints applied only before smoothing.

**Lessons learned**
- Always test on a match the model has never seen; one-match results are misleading.
- Different models fail in different places: merging them helps more than tuning one.
- Check pseudo-labels on a contact sheet for every match before training.
- Metrics hide missed goals: the owner spotted it by watching. A goal checklist is needed.
- Look at crops, not only metrics: "ball found" rose in v0.2 because of a logo letter; "goal in frame" passed while the goal was a tiny corner of the frame.
- Behaviour of players is a more universal signal than appearance: the play-area tips found all 6 goals; appearance-based ideas failed on at least one stadium.
- Compare camera versions on identical `detections.jsonl` and `balls.jsonl`, otherwise detection changes hide the camera changes.

---

## Phase 5: YouTube live (started early, 2026-10-11)

**Status:** algorithm work on the Mac; no phone code yet. The owner wants live as the main product line: wide recording stays on the phone, the cropped view goes to YouTube in real time.

**Done**
- `src/live_sim.py`: real-time camera with a phone-like detection budget and a delay buffer; `LiveGoals` in `src/goals.py` (goals from already-seen players).
- Buffer study on 3 matches: 2 s is the minimum that passes all 7 checklist events and keeps the camera smooth; 3–5 s add nothing measurable. Results in `results.md`.
- Goals in the first minutes: mirrored through the halfway line (`centre_line`), error at 30–60 s down from ~900 px to 54–125 px in matches 2 and 3; match 1 still unknown at 30 s, fine from 60 s.

**Done 2026-10-12:** strictly causal camera (`src/live_cam.py`), 7/7 with buffer 2 s; numbers in `results.md`.

**To do**
- Measure the detection budget on a real iPhone (Core ML); it may change the number of tiles (Mac Core ML: players 42 ms per 2 tiles, ball 14 ms per ROI).
- Better live ball search in the evening / pale-grass case (match 3: 81% ball in crop vs 100% offline).
- No goal estimate before 30 s, and in match 1 both goals are still wrong at 30 s.

**Difficulties**
- Moving the offline camera to live broke 3 of 7 events at first; each fix was checked against the checklist (see `results.md`).
- Fixing one thing exposed another: correct early goals made the attack trigger weaker (the usual count near the goal now includes the keeper), and the match 1 goal was lost until goal mode got a 2 s hold.
- Nobody stands near one of the goals during the first minute (the keeper plays far out), so players alone cannot find it; the halfway line can.

**Lessons learned**
- A YouTube delay of a few seconds is free look-ahead: 2 s of it removes most of the live penalty.

---

## Phase 3: iOS app (started 2026-10-12)

**Status:** runs on the owner's iPhone 15 (iOS 27). Xcode project `ios/FolloApp`; sources in `ios/Follo/Follo` are copied into it (keep both in sync).

**Done 2026-10-15 (scoreboard):** score bug on the stream (team colours, names, score, clock), +/− on the live screen; checked on the phone (`docs/app-design.md`).

**Done 2026-10-15 (first runs on the phone):** camera, position check and a full live run (no YouTube yet) on the phone. A debug-only test-video source feeds a recorded match instead of the camera (`docs/run-on-iphone.md`). Match 2 on the phone: position check in 0.2 s, live at the full 25 fps in real time, memory flat at ~470 MB, goals found after ~40 s, thermal "ok" over 80 s. Fixed on the way: the position check failed real matches (now only the far quarter of the pitch must keep off the frame sides; m1–m3 pass), a 12 GB stream buffer of raw frames (capped at 2 s), a 1-second timer that never fired, a leak in the file reader. Design mockup of all 10 screens: `docs/app-design.md`.

**Done (code only, not compiled: no Xcode on the Mac yet):** chunked 4K recording, YouTube Live API, RTMPS streamer with 60 s buffer and reconnect to the same broadcast, resume after crash, thermal and battery steps, adaptive bitrate, preflight checks, hold-to-stop. Docs: `docs/app-design.md`, `docs/live-edge-cases.md`, `docs/run-on-iphone.md`, `docs/youtube-live.md`.

**Done 2026-10-12 (Core ML camera, edge-case item 8):**
- `ios/FolloCore`: Swift package with the whole live camera (field mask, halfway line, live goals, ball tracker, Core ML detector, camera with 2 s buffer) and `follosim`, a Mac tool that runs it on recorded matches. Compiles on the Mac with the Command Line Tools (`build_mac.sh`); `LiveCameraRunner.swift` in the app is type-checked the same way.
- Swift gives the same camera path as Python on all 3 matches (0.0000 px), same ROIs and balls, masks IoU ≥ 0.99 (`results.md`).
- Core ML export (`src/export_coreml.py`), detection on the Mac through Core ML: see `results.md`.
- App wiring: position check before Go live (field mask from 7 frames over 10 s; Go live disabled until the pitch is in frame and does not touch the left/right edge), frames → detection → 2 s ring → 1080p crop → streamer; thermal step changes the detection cadence.

**Done 2026-10-12 (UI, edge-case items 9, 10, 11, 13, 14):** advice sheet before the first live (Do Not Disturb, Guided Access, power bank), call detection, viewer view of the real 1080p output, screen dimming after 10 s, stream over recording when storage is low. Code only.

**Done 2026-10-12 (highlights after Stop):** `HighlightsRunner.swift` joins the 4K chunks, finds kick-offs from jersey colours sampled during the live, cuts goal-area episodes with the close-up camera into 16:9 and 9:16 clips (AVAssetWriter), `ResultView.swift` lists them with play and share. Checked on the Mac through `follosim highlights`: clips identical to the Python reference on matches 1 and 2; on match 3 the kick-off (and so the GOAL label) differs because the criterion has no margin (`results.md`).

**Done 2026-10-12 (algorithms, 3c item 4):** y-guard against goal drift (`goals.py`, `LiveGoals.swift`), pitch memory (`PitchMemory.swift`: goals of the last match on the same pitch as the prior), experiments on kick-off statistics, early goals and the evening ball search in `results.md`.

**Done 2026-10-12 (screens 1–4):** onboarding with 3 cards and the permission requests, "My matches" with the match list (date, link, clips, goals, 4K kept or deleted), routing in `FolloApp.swift`; the result screen writes the match record. Google Sign-In is a placeholder until the SDK is added.

**Done 2026-10-16:**
- First private YouTube broadcast from the phone on the own stream engine (Studio key).
- Live screen:
  - scrolls, with STOP pinned at the bottom;
  - a mute button;
  - STOP is a hold-only control (the old button restarted the broadcast).
- Owner's rules: GO LIVE is refused inside `go()` until the position check passes, and test runs start muted.
- Matches can be deleted whole.
- UI tests on the simulator (`ios/ui_test.sh`, stage 0 of `docs/youtube-signin-and-ui-test-plan.md`).
- Next: stage 1 of that plan, own Google sign-in with unlisted broadcasts and a stable link.

**Done 2026-10-17 (overnight, Mac and simulator only):**
- GO LIVE records first; the stream connects with retries.
- Sign-in check on launch, and real sign-in in onboarding.
- Broadcast titles from the teams.
- Landscape layout.
- Position overlay "Що бачить застосунок", with Ukrainian hints.
- Viewer count.
- Bitrate advisor from server acknowledgements.
- Half-time card with camera, detection and recording off.
- Build time and MetricKit reports.
- UI tests 1–7 (`ios/ui_test.sh`).
- **Phone check of all of it still to do.**

**To do:** live run with YouTube on the phone; a long test-video run (thermal, battery over 90 min); compare the phone camera path with `live_sim.py` on the same file; then the streamer buffer of encoded frames, Google Sign-In, settings screen (10), edge-case items 15–21. Blocked on the owner: Xcode, first run, own footage, Google Cloud project.

**Difficulties**
- Swift on this Mac: the Command Line Tools 16.2 cannot build any Swift (stale `module.modulemap`; SwiftPM manifests do not link). `build_mac.sh` calls swiftc with a VFS overlay instead.
- Core ML export failed with torch 2.14 (coremltools 9.0 bug): separate `.venv-export` with torch 2.7.
- A Swift command-line loop without `autoreleasepool` leaked 1.5 MB per frame and was killed at 3000 frames (exit 137).
- Swift traps (exit 133) print nothing in an optimised build: `OPT="-O -g" build_mac.sh` and `lldb --batch -o run -o bt` give the line.
- Parity hunting: the batch simulator looked ahead further than the buffer in four places; the recorded ball hints were rounded while the computation used the unrounded ones (74 ROI mismatches until fixed); `numpy.argsort` is not stable by default.

**Lessons learned**
- Write the Python reference in the same streaming form as the port (one object, `push(frame)`), with no numpy look-ahead; then a port can be checked to the last digit instead of "close enough".
- Keep the recorded data exactly what the algorithm used (round before use, not only before writing).

---

## Phases 3–6

**Status:** not started. Next planned: phase 3 iOS app skeleton (4K ultra-wide recording in chunks) in parallel with phase 2.
