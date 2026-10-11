# Status by phase

Living document: update it at the end of every work session (see `.claude/skills/project-docs/SKILL.md`). The stable plan for each phase is in `../docs/phases.md`.

Last updated: 2026-10-11

| Phase | Status |
| --- | --- |
| 0. Test footage | Partially done: 3 public panoramic matches; no own iPhone footage yet |
| 1. Offline prototype | Done (v0.1), with caveats |
| 2. Tracking quality and own model | In progress (v0.2 done, v0.3 paused) |
| 3. iOS app + cloud | Not started |
| 4. Everyday use and beta | Not started |
| 5. YouTube live | Not started |
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

**Status:** in progress. v0.2 done; v0.3 paused while documentation was added.

**Done**
- `ball_window.py`: ball search in a 2× upscaled window around the camera view (match 1: 13% → 21% of samples with a ball).
- Self-training without manual labels: pseudo-labels from confident detections plus interpolated frames → `models/ball_v02.pt` (YOLO11n, 320 px patches, CPU). Held-out last 20% of match 1: raw detection 40% vs 19% for the base model.
- Cross-match tests: match 2 (same stadium) 66% with both models merged; match 3 (new stadium) 26%.
- `merge_balls.py`: union of models with per-model thresholds.
- Pipeline made stadium-independent: adaptive field mask, detection band from the mask, field depth from player positions, crop kept inside the image content.
- `make_dataset.py` rewritten for multi-match datasets: ball size fitted from real boxes, labels snapped to the ball blob, off-field labels dropped, negatives away from any ball.

**To do** (details and priorities in `backlog.md`)
- Goal-area framing: a goal in match 1 (between 2:00 and 4:00) was not shown.
- Finish v0.3: fix label snapping on pale grass (match 3), train on 3 matches, evaluate on held-out minutes of each.
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

**Lessons learned**
- Always test on a match the model has never seen; one-match results are misleading.
- Different models fail in different places: merging them helps more than tuning one.
- Check pseudo-labels on a contact sheet for every match before training.
- Metrics hide missed goals: the owner spotted it by watching. A goal checklist is needed.

---

## Phases 3–6

**Status:** not started. Next planned: phase 3 iOS app skeleton (4K ultra-wide recording in chunks) in parallel with phase 2.
