# Backlog

Living document. Ordered by priority; move finished items to `status.md` (Done) and note results in `results.md`.

Last updated: 2026-10-12 (session 4: Core ML camera done)

## P0: now

### 0. Camera on the phone jumps and follows the wrong thing (owner, 2026-10-15): done
- Fixed 2026-10-15: spare balls and ball boys (isolated candidates must fly to count) and the full-resolution environment on the phone; results in `results.md`. Left: the static look-alike at (2974, 201) in match 2 (Core ML, 1:02.3 late goal mode), backlog 3c item 4.

### 1. Goal checklist: keep growing it
- **State:** 7 events (match 1: goal 2:54.8; match 2: chance 3:38 + 3 attacks found by Claude; match 3: chance 1:25, goal 2:04.7). v0.3 passes 7/7, v0.2 3/7.
- **Limit:** Claude's scan covered only zoomed goal areas inside the highlight clips; at 5–8 px the ball is often not visible on those frames, so shots outside the clips (and in match 3, where nothing extra could be confirmed) may be missing.
- **Next:** add every moment the owner reports; on the owner's phone footage, list goals and shots while watching once.
- **Done when:** every goal and shot the owner knows of is listed and passes.

### 2. Finish model v0.3 on three matches
- Depends on the ball-detector experiment (item 5). The dataset and pseudo-labels are needed either way; training stays on YOLO until the owner decides.
- `src/make_dataset.py` builds the multi-match dataset. Snapping now uses brightness relative to the local grass (V above the local median + 45, low saturation); not yet checked on match 3.
- Use the v0.3 ball tracks (`work/mN/final_v03/ball_track.json`): v0.2 tracks contained logo letters and spare balls, which would become false labels.
- Re-check the contact sheet of labels per match, then train (`src/train.py`, start from `ball_v02.pt`), evaluate on the held-out last 20% of each match, add rows to `results.md`.

### 3a. Highlights: next steps (F13)
- **Done 2026-10-11:** goals recognised by the following kickoff (both test goals, no false ones); time label and fade between clips.
- **Problem:** the kickoff threshold rests on 2 goals with a small margin (0.80 vs 0.74); non-goal clips are still ~1 minute per 4 minutes, ~25 minutes for a 90-minute match; a goal in the last ~30 s of a video has no kickoff to confirm it.
- **Ideas:** confirm the kickoff with a still ball at the centre spot; celebration (attacking team clustered, slow); ball speed towards the goal (shot); a "top N" mode for long matches.
- **Done 2026-10-11:** closer camera and vertical 9:16 for highlight clips (`closeup.py`).
- **Open:** sharpness of the closer camera (source crop 300–480 px is upscaled 2–3.6×; phone 4K footage of a small pitch should be better); vertical clips spend the top third on the background; the "players only" trigger alone gives most weak clips, yet the match 3 chance at 1:25 had no ball detected, so it cannot simply be dropped.
- **Done when:** every goal in the checklists is labelled as a goal and ranked above all non-goal clips; a "top N" reel of a 90-minute match is ≤ 3 minutes.

### 3. Goal-area framing: remaining issues
- **Problem:** in goal mode the stitched panorama's curved black border pushes the crop down, so the goal sits at the top edge with empty near-side grass below; players in frame fell by ~6 points; goal mode is on 22–32% of the time, tuned on a single goal event.
- **Ideas:** re-tune `goal_attack_n` and `goal_zone` once more goals are listed; check on the owner's phone footage (no curved borders); refine automatic goals with post detection near the estimate when confident.
- **Done when:** every listed goal and shot passes, and the owner watches the goal moments without irritation.

### 3d. Camera quality on the phone (owner, 2026-10-15)
1. ~~Static ball look-alike next to players (match 2, 1:02.3)~~ Done 2026-10-15: it was a Core ML artefact of frames shifted by one (empty edit) and bilinear resampling; aligned frames + cv2-like bicubic make Core ML = Python, checklist 7/7 (`results.md`).
2. **Smoothness:** twitches 1.5–3.3 per minute, mostly in goal mode while no ball is accepted (goal-mode target swings between goal and players). Next: hold the goal-mode target while the ball is lost; judge on rendered video with the owner; checklist must stay 7/7.
3. ~~Player-model input for the phone's 16:9 4K frame~~ Done 2026-10-15: tiles over the pitch band only (W/H < 2.2), +40–75% players, ball in crop equal or better on 16:9-padded matches 2 and 3. Still to check on real phone footage.

### 3e. Scoreboard on the stream (owner, 2026-10-15)
- **Done 2026-10-15:** score bug burned into the 1080p stream, top left (team colour, name, score, match clock); "Команди" before the game (name, jersey colour from 10 swatches, show/hide); during the game big +/− for each team, hold the clock to restart it at kick-off; state survives a crash. Code: `FolloCore/Scoreboard.swift`, app `ScoreViews.swift`; look on the Mac: `follosim scoreboard OUT.png`. Checked on the phone with the test video.
- **Next:** suggest jersey colours automatically from the colours sampled in the first minutes (`Jersey.samples`), the owner only confirms; propose "Goal for …?" when the camera's goal mode sees a likely goal (one tap to accept, never automatic); the score in the highlight clips; half-time (clock pause, 2nd half from 45:00).

### 3b. Live: next steps
- Measure YOLO11n/s Core ML on the iPhone 15 (1 vs 2 tiles at 1280, ball tile at 640) — decides the real detection budget.
- Live ball search for evening / pale grass (match 3 ball in crop 74%): ball candidates from player motion, a second ball model pass when lost.
- Goals in the first 30–60 s: done partly (mirror through the halfway line). Open: an estimate before 30 s (halfway line + field mask ends?), and remembering goals of a pitch the owner plays on every week.

### 3c. Phase 3 (Follo app): work that needs no owner input (next session starts here)
Status of the 21 edge-case items lives in `docs/live-edge-cases.md`. Done in code (untested on a phone): 1–6, 8–14; partly 7.
1. ~~Core ML camera on the phone (item 8)~~ Done 2026-10-12 (`ios/FolloCore`, `follosim`, results in `results.md`). Left for the phone: measure the real detection budget (Mac: players 43–55 ms per tile pair, ball 8–14 ms); choose the player-model input size for the phone's 16:9 4K frame (the export is 1280×672 for the 4096×1084 panoramas; on 3840×1504 it already loses 24% of players, see `results.md`); the 2 s frame ring holds ~60 4K frames (~750 MB) — if the phone runs out of memory, keep the ring at 2560 px wide or shorten the buffer; the streamer's 60 s buffer of raw 1080p frames (~5 GB) must become a buffer of encoded frames (VideoToolbox) before a real test.
2. ~~UI items 9, 10, 11, 13, 14~~ Done in code 2026-10-12 (`Overlays.swift`, `Advice.swift`, `LiveSession.tick`), untested on a phone.
3. ~~Highlights on the phone after Stop~~ Done in code 2026-10-12 (`live_highlights.py` as the reference, Swift `Highlights.swift`, `Kickoff.swift`, `ClosePath.swift`, `ClipRenderer.swift`, app `HighlightsRunner.swift` + `ResultView.swift`); clips identical to Python on matches 1 and 2; the kick-off criterion has no margin (see item 4).
4. ~~Algorithms on the simulator~~ Done 2026-10-12 (`results.md`, "Live algorithms on the simulator"): live goals no longer drift to the corner flags (y-guard), pitch memory gives goals from the first second on a known pitch, 30 s stays the minimum without memory. Open: **GOAL label** (kick-off separation has no margin: needs another cue, see owner questions), **evening ball search** (match 3 still 76% ball in crop; 3 ROIs while lost gives +1.5 points for +14 ms), far-side mirrored goal y error 120 px in match 3, the player-model input size for 16:9.
5. ~~Onboarding and "My matches" screens~~ Done in code 2026-10-12 (`OnboardingView.swift`: sign-in placeholder, 3 cards, permissions; `MyMatchesView.swift` + `MatchStore.swift`: list, new match, free space, delete the 4K recording). Google Sign-In itself still needs the SDK and a Google Cloud project (owner).
Needs the owner: Xcode install and first run (`docs/run-on-iphone.md`), own iPhone footage, Google Cloud project for YouTube (`docs/youtube-live.md`).

## P1: next

4. **Own iPhone footage** (phase 0): 10–15 minutes, ultra-wide 0.5×, 4K 30 fps, tripod 2–3 m. Run the whole pipeline on it.
5. **Experiment: ball detector licence and ownership** (owner decision pending; change nothing until then).
   - **Question:** does the owner's rule "own computation, no third-party models with their own licences" also cover the ball detector? Today it is Ultralytics YOLO11 (AGPL-3.0, trained weights included).
   - **Options:** (a) keep YOLO for the prototype, replace before any closed release; (b) an Apache-2.0 model (RF-DETR, D-FINE, YOLOX); (c) our own small network: architecture in our code on PyTorch (BSD), trained from scratch on our pseudo-labels (`make_dataset.py`) — fully owned, no third-party weights.
   - **Experiment for (c):** a tiny detector or heatmap network on 320 px patches, trained on the 3 matches; compare raw recall and precision with YOLO on held-out minutes (same table as `results.md`).
   - **Decides:** whether model v0.3 (item 2) is trained further on YOLO or on our own network.
5a. **Processing speed, part 2** (requirement: a 90-minute match in ≤ 30 min). Done 2026-10-11: ~23 → 7.5 min per 4 minutes on the M1 Air with identical checklist results (step 15, half precision, VideoToolbox, no debug video; table in `results.md`). Still ~2.8 h per 90-minute match on the Air. Next: (a) measure on a cloud GPU (the requirement is meant for cloud processing in phase 3); (b) player detection at 960 px or one whole-frame pass (2–4× faster) — evaluate on the checklists; (c) ball window at a smaller input size; (d) one decode pass shared by all steps. Done when: a 90-minute match ≤ 30 min on the target hardware with all checklists passing.
6. **Ground truth:** golden clips with manual ball positions every 10 frames, so `ball_found_share` can be replaced by true recall.

## P2: later

7. **Pitch registration:** detect the pitch markings and map the image to pitch coordinates (metres). Would give exact goals, zoom by real distance, top-down positions for highlights and stats. Own computation only (owner's requirement: no third-party models or services).
8. iOS app skeleton (phase 3): 4K ultra-wide recording in 2–5 minute chunks and the setup screen.
9. Lead the play and widen the crop when tracking is uncertain.
10. Translate code comments and docstrings to English.
