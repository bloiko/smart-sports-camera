# Plan: replace the AGPL detectors with permissively licensed ones, same results

Status: proposal, 2026-10-16. Owner asked: is it realistic to keep today's results, and how exactly.

## Why

| What ships in the app today | Built with | Licence |
| --- | --- | --- |
| `players.mlpackage` (people + "sports ball" hints) | stock `yolo11s.pt`, exported by Ultralytics | AGPL-3.0 |
| `ball.mlpackage` (ball in a 320 px ROI, 2× up) | `ball_v02.pt`: YOLO11n fine-tuned with Ultralytics on our pseudo-labels | AGPL-3.0 (Ultralytics treats weights trained with its package as AGPL) |

A closed, paid iOS app that bundles these models would have to publish its full source under AGPL, or buy an
Ultralytics Enterprise licence. Our own code (camera, tracker, goals, scoreboard, `Detector.swift`) does not depend on
Ultralytics. Only the two models and the Python scripts that make them do (`export_coreml.py`, `detect.py`, `live_sim.py`, training).

Data: the three test matches appear to be from SoccerTrack v2 (CC BY 4.0, gated on Hugging Face), which allows
commercial use with attribution. To confirm (Phase 0). SoccerTrack v2 labels are pitch coordinates, teams and
ball actions (Pass, Shot…), not image boxes. The ball actions can extend our goal/shot checklists for free.

## Is the same result realistic?

Yes, with one open question: speed on the phone.

- **Players.** We use a stock COCO model with no fine-tuning. Several Apache-2.0 detectors are as accurate or more
  accurate on COCO (RF-DETR N/S/M/L, D-FINE, DEIM, RT-DETR v1–v2, YOLOX, DAMO-YOLO). After fine-tuning on football frames
  they should beat today's model on far, small players, because domain data matters more than COCO points.
- **Ball.** Today's model is tiny and trained on 249 pseudo-labels plus interpolations. That is easy to reproduce with
  any small detector. A small heatmap network written by us is also possible; it would be fully our own computation,
  which matches the owner's rule.
- **Speed (the risk).** The phone budget, measured on the M1 Mac:

  | Pass | When | Mac time |
  | --- | --- | --- |
  | Players, 2 tiles at 1280×672 | every 4th frame | 36–55 ms |
  | Ball ROIs at 640×640 | every 2nd frame, 1–2 ROIs | 8–14 ms each |

  CNN detectors (YOLOX, DAMO-YOLO) run well on the Neural Engine. DETR detectors use deformable attention
  (`grid_sample`), which may fall back to the GPU or CPU: one report has RF-DETR nano at 384×384 at about 15 fps on an
  iPhone 14 Pro without the Neural Engine, which would be too slow for 1280×672 tiles. RF-DETR has an official Core ML
  export, so this is a measurement, not guesswork.

## Rules for the new chain (licence hygiene)

- **Shipped artefacts** must be Apache-2.0, MIT or BSD code and weights, or our own: the models, the export and the runtime.
- **Training stack:** PyTorch (BSD) and the candidate's own Apache/MIT repository. Never the `ultralytics` package.
- **Labels.** Labels from the old model are model outputs, generally not covered by AGPL when the new model is trained
  outside Ultralytics. To stay clean anyway, the training labels come from a large Apache model run offline on the Mac
  (teacher), checked by our tracker; the old model is kept only as a measuring stick in evaluation.
- **COCO-pretrained weights** are the industry norm, but the images have mixed Flickr licences. Note this for the
  lawyer check before release; the fallback is pretraining on our own and SoccerTrack frames only.
- **Before the paid release:** a NOTICE file (Apache attributions, SoccerTrack CC BY attribution), a short one-off check
  by a lawyer, and a CI check that `ultralytics` is not in any shipped artefact.

## Candidates

| Model | Licence (code / weights, to re-check in the repo) | Type | Core ML | Expected phone speed | Role |
| --- | --- | --- | --- | --- | --- |
| YOLOX-s / tiny / nano | Apache-2.0 | CNN, anchor-free | Plain conv net, converts with coremltools | Fast, Neural Engine | **Safe default** for players and ball |
| D-FINE-S / DEIM-S | Apache-2.0 | DETR (CNN backbone, deformable decoder) | `grid_sample` risk | Unknown | Accuracy candidate |
| RF-DETR N/S | Apache-2.0 (N–L; XL/2XL are not) | DETR (DINOv2 backbone) | Official native export | Possibly slow at 1280 | Accuracy candidate, and offline teacher (M/L on the Mac) |
| DAMO-YOLO-T/S | Apache-2.0 | CNN | Converts | Fast | Second CNN option |
| Apple Vision human detection | System framework, free | Unknown | Built in | Fast | Zero-training baseline for players |
| Own ball heatmap CNN | Ours | Small U-Net on ROI patches | Trivial | Very fast | Ball, "own computation" |

Not usable: YOLOv5/v8/11 and YOLOv10 (AGPL), YOLOv6/v7/v9 originals (GPL-3.0), YOLO-NAS weights (restrictive).
MIT re-releases (MultimediaTechLab YOLO, LibreYOLO) exist, but the weight licences need checking; keep them as
reserve options.

## Acceptance criteria ("same result")

Measured exactly as today (Core ML on the Mac, aligned frames, `follosim`, `eval_live.py`, checklists), on the 3 matches,
the 16:9-padded versions, and the owner's own footage when it exists:

| Metric | Today (Core ML) | Required |
| --- | --- | --- |
| Goal checklist | 7/7 | 7/7 |
| Ball in crop | 97.8% / 93.8% / 78.5% | Not lower by more than 1 point on any match |
| Jumps, twitches | 1.4–2.3%, 0.8–1.8 per min | Not worse |
| Player recall vs today's model (IoU ≥ 0.5), far half | — | ≥ 97% (more is fine) |
| iPhone 15: players pass (2 tiles) | to measure | ≤ 60 ms |
| iPhone 15: ball ROI | to measure | ≤ 15 ms |
| Live run on the phone, 30 min | 25–30 fps, ~600 MB, thermal ok | Same |

## Phases

| Phase | Work (Claude) | Owner | Effort |
| --- | --- | --- | --- |
| 0. Inventory | List every Ultralytics touch point; confirm the SoccerTrack v2 source and licence on its page; write the rules above into `docs/decisions.md` | Accept the dataset terms on Hugging Face if gated | 0.5 day |
| 1. Benchmark harness | Make `Detector.swift` take any Core ML model with the same outputs (boxes + scores via an NMS pipeline built in coremltools). Freeze a benchmark: the players and ball ROIs of the 3 matches plus the 16:9 versions, scored against today's model. Add a phone model-speed mode (`--bench-models`: ms per tile on the device) | Phone connected for 10 min | 2 days |
| 2. Players, zero-shot | Export COCO-pretrained YOLOX-s, D-FINE-S (or DEIM-S), RF-DETR-N and Apple Vision to Core ML; measure recall and phone speed; keep 1–2 | — | 3 days |
| 3. Player data | Frames from all 10 SoccerTrack v2 matches (today we use 3), labelled by the offline teacher (RF-DETR-M/L or D-FINE-L on the Mac), cleaned by tracking consistency; hold out matches 1–3 and the last 20% of each video (project rule) | — | 2–3 days of Mac compute, resumable |
| 4. Fine-tune players | Fine-tune the chosen small model; training on the M1 (MPS), resumable after every epoch; if too slow, a free Kaggle/Colab GPU on the owner's account | Kaggle/Colab account if needed | 3–4 days |
| 5. Ball | Patch dataset from the tracker-confirmed balls (positives) and look-alikes: spare balls, heads, line crossings (negatives). Train YOLOX-nano at 640 and our own heatmap CNN; compare with `follosim ballroi`-style agreement and end to end; keep the better | — | 3–4 days |
| 6. Integration | `src/export_coreml_*.py` for the new models; Python reference detection with the same models; Swift = Python parity (SAME TRACK / SAME PATH); all acceptance metrics; 30-min phone run | Phone for 30–40 min | 2 days |
| 7. Switch and clean | Replace the bundled models; remove `ultralytics` from every shipped path (keep it only as an optional measuring stick in dev scripts, or drop it); NOTICE file; CI licence check; update `architecture.md` and `datasets.md` | Lawyer check before the paid release (one-off) | 1 day |

Total: about 3 weeks at the current pace. Nothing here blocks the first test matches. The work can run in parallel with
the app, and the switch happens only when every acceptance criterion holds.

## Fallbacks

- **No Apache model is fast enough at 1280×672.** Use YOLOX-tiny on smaller band tiles (3 tiles at 960 px), or run the
  players pass every 6th frame instead of every 4th; the tracker tolerates it, but this must be checked on the checklists.
- **The ball model is worse than today.** Add temporal input (3 consecutive ROI frames) to our own heatmap CNN, which is
  a known strong approach for small fast balls; or keep a bigger ROI model at 2 ROIs only while the ball is lost.
- **The legal check says COCO-pretrained weights are a problem.** Pretrain only on SoccerTrack and our own footage; this
  needs more data, so collect the owner's matches from now on.
- **Last resort:** an Ultralytics Enterprise licence (paid), only if the product already earns.
