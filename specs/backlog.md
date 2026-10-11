# Backlog

Living document. Ordered by priority; move finished items to `status.md` (Done) and note results in `results.md`.

Last updated: 2026-10-11 (session 2, docs synced)

## P0: now

### 1. Goal checklist for matches 2 and 3
- **Problem:** only two events are checked automatically (match 1 goal at 2:54.8, match 2 chance at 3:38, match 3 chance at 1:25); the rest of matches 2 and 3 is not reviewed, so a regression there would go unnoticed.
- **Ideas:** ask the owner; otherwise scan zoomed goal areas around the attack episodes found from player counts near each goal (match 2: left 2:03–3:53, right 0:04–1:09; match 3: many).
- **Done when:** `specs/checklists/match2.json` and `match3.json` list every goal and shot on target, and `check_goals.py` passes on v0.3.

### 2. Finish model v0.3 on three matches
- Depends on the ball-detector experiment (item 5). The dataset and pseudo-labels are needed either way; training stays on YOLO until the owner decides.
- `src/make_dataset.py` builds the multi-match dataset. Snapping now uses brightness relative to the local grass (V above the local median + 45, low saturation); not yet checked on match 3.
- Use the v0.3 ball tracks (`work/mN/final_v03/ball_track.json`): v0.2 tracks contained logo letters and spare balls, which would become false labels.
- Re-check the contact sheet of labels per match, then train (`src/train.py`, start from `ball_v02.pt`), evaluate on the held-out last 20% of each match, add rows to `results.md`.

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
6. **Ground truth:** golden clips with manual ball positions every 10 frames, so `ball_found_share` can be replaced by true recall.

## P2: later

7. **Pitch registration:** detect the pitch markings and map the image to pitch coordinates (metres). Would give exact goals, zoom by real distance, top-down positions for highlights and stats. Own computation only (owner's requirement: no third-party models or services).
8. iOS app skeleton (phase 3): 4K ultra-wide recording in 2–5 minute chunks and the setup screen.
9. Lead the play and widen the crop when tracking is uncertain.
10. Vertical 9:16 output (F6).
11. Translate code comments and docstrings to English.
12. A single `pipeline.py` that runs all steps with resume, instead of separate commands.
