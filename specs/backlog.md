# Backlog

Living document. Ordered by priority; move finished items to `status.md` (Done) and note results in `results.md`.

Last updated: 2026-10-11

## P0: now

### 1. Goal-area framing (requirement F7)
- **Problem:** when the ball is close to a goal it leaves the crop; a goal in match 1 between 2:00 and 4:00 was not shown (owner feedback on the v0.2 render, part 2).
- **Likely causes:** the camera target is a weighted average of the player group and the ball, so a ball near the goal is pulled back towards the group; speed limit and 0.8 s smoothing lag on fast attacks; the ball is rarely detected near the panorama edges, where the goals are.
- **Ideas:**
  - Find the goals automatically (left and right ends of the field mask, or detect goal posts) and define penalty areas.
  - When the ball or a cluster of attackers is inside a penalty area, frame the goal mouth plus the ball, widening the crop if needed.
  - Treat the ball as a hard constraint (inside the crop with a margin) instead of only a weight.
  - Fill short gaps in the ball track by interpolation before applying constraints.
  - Allow faster panning towards a goal.
- **Done when:** the match 1 goal is visible; a goal checklist exists for all test videos and every item passes.

### 2. Finish model v0.3 on three matches
- `src/make_dataset.py` builds the multi-match dataset. Remaining issue: on match 3's pale grass, snapping to the brightest blob uses an absolute threshold and sometimes picks the wrong spot. Use brightness relative to the local grass (e.g. V above the local median + 45 and low saturation).
- Re-check the contact sheet of labels per match, then train (`src/train.py`, start from `ball_v02.pt`), evaluate on the held-out last 20% of each match, add rows to `results.md`.

## P1: next

3. **Own iPhone footage** (phase 0): 10–15 minutes, ultra-wide 0.5×, 4K 30 fps, tripod 2–3 m. Run the whole pipeline on it.
4. **Apache-2.0 detector:** replace Ultralytics (AGPL) with RF-DETR, D-FINE or YOLOX; compare on the same matches.
5. **Ground truth:** golden clips with manual ball positions every 10 frames, so `ball_found_share` can be replaced by true recall.

## P2: later

6. iOS app skeleton (phase 3): 4K ultra-wide recording in 2–5 minute chunks and the setup screen.
7. Lead the play and widen the crop when tracking is uncertain.
8. Vertical 9:16 output (F6).
9. Translate code comments and docstrings to English.
10. A single `pipeline.py` that runs all steps with resume, instead of separate commands.
