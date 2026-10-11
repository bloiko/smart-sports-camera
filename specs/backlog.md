# Backlog

Living document. Ordered by priority; move finished items to `status.md` (Done) and note results in `results.md`.

Last updated: 2026-10-11 (session 2, docs synced)

## P0: now

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

## P1: next

4. **Own iPhone footage** (phase 0): 10–15 minutes, ultra-wide 0.5×, 4K 30 fps, tripod 2–3 m. Run the whole pipeline on it.
5. **Experiment: ball detector licence and ownership** (owner decision pending; change nothing until then).
   - **Question:** does the owner's rule "own computation, no third-party models with their own licences" also cover the ball detector? Today it is Ultralytics YOLO11 (AGPL-3.0, trained weights included).
   - **Options:** (a) keep YOLO for the prototype, replace before any closed release; (b) an Apache-2.0 model (RF-DETR, D-FINE, YOLOX); (c) our own small network: architecture in our code on PyTorch (BSD), trained from scratch on our pseudo-labels (`make_dataset.py`) — fully owned, no third-party weights.
   - **Experiment for (c):** a tiny detector or heatmap network on 320 px patches, trained on the 3 matches; compare raw recall and precision with YOLO on held-out minutes (same table as `results.md`).
   - **Decides:** whether model v0.3 (item 2) is trained further on YOLO or on our own network.
5a. **Processing speed** (requirement: a 90-minute match in ≤ 30 min). Measured on the M1 Mac, match 1 (4:00, step 5): detection 10.2 min, ball window 2 models 6.9 min, background check 1.1 min, render ~5 min → ~23 min per 4 minutes, ~8.5 hours per 90 minutes (17× over). Ideas: sample every 10th–15th frame and measure the quality loss; detect players once on a downscaled frame instead of three 1280 px tiles; one ball model; hardware encoding (VideoToolbox). Done when: a speed/quality table in `results.md` and a mode with 4 minutes processed in ≤ 1.5 min with the checklists still passing.
6. **Ground truth:** golden clips with manual ball positions every 10 frames, so `ball_found_share` can be replaced by true recall.

## P2: later

7. **Pitch registration:** detect the pitch markings and map the image to pitch coordinates (metres). Would give exact goals, zoom by real distance, top-down positions for highlights and stats. Own computation only (owner's requirement: no third-party models or services).
8. iOS app skeleton (phase 3): 4K ultra-wide recording in 2–5 minute chunks and the setup screen.
9. Lead the play and widen the crop when tracking is uncertain.
11. Translate code comments and docstrings to English.
