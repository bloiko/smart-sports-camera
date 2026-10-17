# Feasibility of training own player and ball detectors from scratch (M1 Mac + free GPUs, ~1 h/day)

Research date: 2026-10-17. Free-tier limits change often; every number below carries the date it was read by its source. Items marked "inference" are my reasoning from the cited facts, not facts from a source. Hardware peak-FLOPS figures are from general knowledge and were not re-fetched in this session (see Gaps).

Project context used for the estimates (from the repo, not the web): 3 stitched panoramic matches of 4 minutes each at 25 fps (~6,000 frames per match, ~18,000 frames total), 4096×1080 / 3840×1504 resolution; the ball is 5–8 px on the far side; a self-trained YOLO11n ball model on 320 px patches already exists (`models/ball_v02.pt`, AGPL); detection of a 4-minute video takes ~11 min on the M1 with MPS — `specs/datasets.md`, `specs/status.md`.

## 1. PyTorch on Apple Silicon (MPS): throughput and limitations

### Takeaway
MPS training works for small CNNs in float32, but there is no usable mixed precision, no `torch.compile`, and no float64; I found no direct, sourced M1-8-core-GPU vs T4 CNN training benchmark. Best available evidence puts even an M1 Max well behind a T4 on small batches, so a base M1 should be treated as roughly an order of magnitude slower than a T4 in fp16 (inference, wide uncertainty).

### Cited Findings
- mrdbourke's `mac-ml-speed-test` (PyTorch/TensorFlow/MLX, ResNet50 and others on M1 Pro, M3, M3 Pro, M3 Max vs NVIDIA TITAN RTX and Colab): float16 mixed-precision training does not work on MPS, so all tests ran in float32; `torch.compile()` is not supported on MPS; larger experiments needed `ulimit -n` raised from 256 to 2560; the base M3 matched or beat M3 Pro/Max on small experiments, which the author suspects is CPU→GPU data-copy overhead (unconfirmed). Numeric results are only in chart images; no T4 and no dates in the text — [mrdbourke/mac-ml-speed-test](https://github.com/mrdbourke/mac-ml-speed-test)
- Closest same-workload M1-vs-T4 numbers (BERT, not a CNN, older PyTorch nightlies, float32): M1 Max 32-core GPU ~1 m 3 s vs T4 31 s at batch 16; at batch 64 M1 Max 2 m 57 s vs T4 2 m — [lucadiliello/pytorch-apple-silicon-benchmarks](https://github.com/lucadiliello/pytorch-apple-silicon-benchmarks)
- Users report cases where MPS is slower than CPU on an M1 for small models (dispatch overhead dominates tiny workloads) — [PyTorch forums: "Mps seems much slower than cpu on an M1 Mac"](https://discuss.pytorch.org/t/mps-seems-much-slower-than-cpu-on-an-m1-mac/225242)
- Reports of training that does not converge on MPS while it does on CPU (older PyTorch; correctness bugs in specific ops) — [PyTorch forums: training doesn't converge on M1 Pro MPS](https://discuss.pytorch.org/t/training-doesnt-converge-when-running-on-m1-pro-gpu-mps-device/157918)
- float64 is not supported by Metal, so any float64 tensor fails on MPS; an example `TypeError` on PyTorch 2.8 with Lightning — [Lightning issue #21261](https://github.com/Lightning-AI/pytorch-lightning/issues/21261); [Apple developer forums thread 797778](https://developer.apple.com/forums/thread/797778)
- On PyTorch 2.5, `GradScaler.unscale_` cast to float64 internally, so AMP training crashed on MPS even with autocast enabled — [PyTorch forums: GradScaler TypeError on MPS](https://discuss.pytorch.org/t/gradscaler-typeerror-cannot-convert-a-mps-tensor-to-float64-dtype-as-the-mps-framework-doesnt-support-float64-please-use-float32-instead/213206)
- bfloat16 on MPS: conflicting sources — an error "BFloat16 is not supported on MPS" on older macOS ([pytorch#141864](https://github.com/pytorch/pytorch/issues/141864)) vs a PR enabling bf16/fp16 for some workloads ([pytorch#133430](https://github.com/pytorch/pytorch/pull/133430))
- `PYTORCH_ENABLE_MPS_FALLBACK=1` sends unsupported ops to the CPU (slower) — [mljourney guide (low-authority)](https://mljourney.com/?p=6780)
- Apple's early "8× faster than CPU for VGG16 training" claim was measured on an M1 Ultra, not a base M1; Sebastian Raschka (pre-MPS era) judged training modern deep networks on the base M1 "not really feasible" — [Raschka, Running PyTorch on the M1 GPU (2022)](https://sebastianraschka.com/blog/2022/pytorch-m1-gpu.html)

### Inferences
- Plan for float32 only on the M1. A T4 with AMP (fp16 tensor cores) will likely be ~5–15× faster than the 8-core M1 GPU for a small conv detector (inference from: M1 Max being 1.5–2× slower than a T4 in fp32 BERT; the base M1 has 1/4 of the M1 Max GPU cores; T4 gains a further large factor from fp16 tensor cores). Treat this range as uncertain until measured with a 5-minute micro-benchmark on both machines (synchronise with `torch.mps.synchronize()` before timing).
- Tiny networks (FootAndBall-sized, ~0.2 M params) are dispatch-bound on MPS: use larger batches of small crops (e.g., 64–256 crops of 256–320 px) rather than few full frames, and pre-decode frames to JPEG/NPY so the data loader is not the bottleneck.
- Avoid `float64` anywhere in the data/target pipeline (NumPy defaults to float64 — cast heatmaps and boxes to float32 before `.to("mps")`).
- An overnight run (8–10 h) on the M1 is therefore worth roughly 1 h of T4 time (inference); its value is that it is unlimited and unattended.

### Gaps
- No sourced, same-script CNN training benchmark of a base M1 (8-core GPU) vs T4/P100 was found. Peak specs (M1 GPU ≈2.6 TFLOPS fp32; T4 ≈8.1 TFLOPS fp32 / 65 TFLOPS fp16 tensor; P100 ≈9.3 TFLOPS fp32) are from vendor specs in general knowledge, not fetched here.
- No authoritative 2025–2026 MPS op-support matrix was found; check the release notes of the installed PyTorch version.

## 2. Free GPU options in 2026 and their limits

### Takeaway
Kaggle is the most usable free GPU for this project (T4/P100, 12 h sessions, ~30 GPU-h/week as commonly reported, floating); Colab free gives an unpredictable T4 for at most 12 h with idle timeouts; the rest are either tiny (HF ZeroGPU 5 min/day), closed to new users (SageMaker Studio Lab), or unclear (Lightning AI, Paperspace).

### Cited Findings
Snapshot from a source that read official docs on 21 Sep 2026 (Paperspace row verified 13 Jul 2026) — [gpuperhour.com: Free Cloud GPUs in 2026](https://gpuperhour.com/blog/free-cloud-gpus-and-credits):
- **Kaggle Notebooks:** T4 and P100 class GPUs; 12 h per GPU/CPU session, 9 h for TPU; weekly GPU quota shown in account settings and floats — "about 30 h/week" is user-reported, not stated in Kaggle docs. Colab Pro / Pro+ subscribers who link accounts get +15 / +30 Kaggle GPU h/week (may change).
- **Google Colab free:** GPU type not named by Google (users report T4); sessions at most 12 h depending on availability; no published limits.
- **Hugging Face ZeroGPU:** 5 min GPU/day for a free account (2 min unauthenticated), 60 s default function limit; meant for demos, not training.
- **Lightning AI free plan:** 1 active Studio, restarts every 4 h, 50 GB storage; monthly credit amount not confirmed.
- **Paperspace Gradient free:** Quadro M4000, auto-shutdown after ≤6 h, 5 GB storage; free capacity not tested.
- **Modal Starter:** $30/month free compute (serverless, not a notebook).
- **Amazon SageMaker Studio Lab:** closed to new users; existing users 4 h at a time, 4 h per 24 h.
- **Student/education:** Colab Pro for Education (free year, US students, launched 18 Jul 2025) closed to new signups; GitHub Student Pack: $100 Azure credit + Camber 5 GPU h; Azure for Students $100/12 months (GPU eligibility unclear); Modal academic grants up to $10k (application). Google Cloud $300 trial does not allow GPUs.
- Blog posts claiming a "guaranteed 30 h/week with 9 h sessions" on Kaggle contradict Kaggle's docs (12 h sessions, floating quota) — [gmicloud.ai blog](https://www.gmicloud.ai/en/blog/best-free-gpu-cloud-options-for-ai-startups-and-researchers) contradicted by [gpuperhour.com](https://gpuperhour.com/blog/free-cloud-gpus-and-credits)
- Colab official FAQ: free resources are not guaranteed; usage limits are dynamic and not published; free notebooks run at most 12 h; runtimes time out when idle; idle timeouts, VM lifetime and GPU types vary over time; background execution is a paid-plan feature — [Colab FAQ](https://research.google.com/colaboratory/faq.html)

### Inferences
- Realistic free budget: Kaggle ~20–30 T4/P100 h/week (assume the low end), Colab free a few unreliable hours/week (needs the browser tab active — poor fit for unattended runs), plus ~8–10 h/night on the M1 (unlimited, slow). Kaggle's "Save & Run All" (commit) mode runs in the background without an open tab, which fits the "1 h attention a day" constraint (Kaggle behaviour from general knowledge; verify).
- Data upload is the hidden cost: put pre-cut crops (not 4K videos) into a private Kaggle Dataset once; checkpoints written to `/kaggle/working` become the run's output that the next run can attach as input.
- Licensing note for the product rule "everything own": training on free cloud GPUs does not affect licence of the resulting weights, but datasets do (SoccerTrack v2 is CC BY 4.0 per `specs/datasets.md`; SoccerNet/DeepSportradar must not be used).

### Gaps
- Kaggle does not publish the weekly quota number; the 30 h figure is user-reported.
- Lightning AI monthly free-credit amount (historically ~15–22 credits/month) is not confirmed for 2026.
- Whether Colab free still reliably grants a T4 in Ukraine/EU in late 2026 is not documented.

## 3. GPU-hours for small detectors from scratch; narrow domains

### Takeaway
Generic from-scratch training is expensive (YOLOv5n on COCO: ~1 V100-day for 300 epochs) and from-scratch needs longer schedules than fine-tuning, but the compute scales with images × epochs × pixels, and a single-scene football domain with ~10–20k crops needs roughly 1–3% of a COCO run. FootAndBall (0.2 M params) reached 0.91 ball AP / 0.92 player AP on ISSIA-CNR from scratch with 100 epochs on ~16k frames.

### Cited Findings
- YOLOv5 official estimate: 300 epochs on COCO (118k images) on one V100 take ~1/2/4/6/8 days for n/s/m/l/x; reference batch 128 for n, 64 for s (V100-16 GB); the from-scratch command uses `--weights ''` — [Ultralytics YOLOv5 quickstart](https://docs.ultralytics.com/yolov5/quickstart_tutorial/)
- He et al., "Rethinking ImageNet Pre-training" (ICCV 2019): detectors trained from random initialisation with the same hyperparameters converge to accuracy no worse than ImageNet fine-tuning, but need more iterations; this held with only 10% of COCO; pre-training mainly speeds up early convergence — [arXiv 1811.08883](https://arxiv.org/abs/1811.08883)
- Follow-up: catching up with ImageNet pre-training from scratch needs about a 6× schedule (72 epochs) in that setting — [Rethinking Training from Scratch for Object Detection, arXiv 2106.03112](https://arxiv.org/abs/2106.03112)
- **FootAndBall** (VISAPP 2020): integrated player + ball detector, ~199k parameters (the intro says 120k — inconsistent in the paper), trained on ISSIA-CNR (~20k annotated frames, 80/20 split) and Soccer Player Detection (2,019 images); 100 epochs, Adam, lr 1e-3 divided by 10 after 75 epochs, batch 16; augmentation: random scale 0.8–1.2, random crop, horizontal flip, photometric distortions; results: ISSIA-CNR ball AP 0.909, player AP 0.921; SPD player AP 0.885; inference 37 FPS at 1920×1080 on a GTX 1060; training time and training hardware not stated — [arXiv 1912.05445](https://arxiv.org/abs/1912.05445) (HTML: [arxiv.org/html/1912.05445](https://arxiv.org/html/1912.05445)); MIT-licensed code — [jac99/footandball](https://github.com/jac99/footandball)
- **TrackNetV2** (badminton shuttlecock heatmap net): dataset 55,563 frames from 18 videos in the paper (dataset page: 78,200 frames / 26 videos — sources disagree); heatmap changed to a real-valued 2D map and weighted cross-entropy loss to cut GPU memory; speed 2.6 → 31.8 FPS; test on an unseen match: accuracy 85.2%, precision 97.2%, recall 85.4% (vs 96.3/97.0/98.7% on training) — [TrackNetV2 (paperswithcode)](https://paperswithcode.com/paper/tracknetv2-efficient-shuttlecock-tracking); MonoTrack used 77k frames / 26 matches, 12k frames from 3 matches for test — [MonoTrack, arXiv 2204.01899](https://arxiv.org/abs/2204.01899)
- A 2026 soccer broadcast tracking paper fine-tuned YOLOv8 for only 25 epochs at 1280 px, batch 6, explicitly due to compute/time limits — [arXiv 2602.18504](https://arxiv.org/abs/2602.18504)

### Inferences
- Compute scaling (rough, inference): YOLOv5n COCO = 118k imgs × 300 epochs ≈ 35 M image-steps at 640 px ≈ 1 V100-day. A narrow domain run of, e.g., 15k crops at 320 px (¼ the pixels of 640) × 150 epochs ≈ 2.25 M crop-steps ≈ 0.56 M "640-equivalents" ≈ 1.6% of COCO ≈ 25 V100-minutes ≈ 40–80 T4-minutes with AMP ≈ 6–12 h on the M1 in fp32 (one night). A FootAndBall-sized net is ~10× fewer parameters than YOLOv5n (1.9 M), so it is cheaper still, but MPS overhead will eat part of that saving.
- Narrow domain helps in two ways: (a) only 2 classes and one viewpoint type, so far fewer images suffice than for COCO; (b) FootAndBall shows that ~16k frames from a handful of fixed cameras are enough for 0.9+ AP from scratch. Our 3 × 6,000 frames are highly correlated (25 fps, same scene), so the *effective* dataset is much smaller — the main risk is overfitting to 3 stadiums, not compute.
- The TrackNetV2 generalisation drop on an unseen match (recall 98.7% → 85.4%) is the expected pattern for our ball model too: plan evaluation on an unseen match from day one (as the project rules already require).
- From-scratch needs ~2–6× the epochs of fine-tuning (He et al.; Li et al.); budget 150–300 epochs on crops rather than the usual 50–100 for fine-tuning.
- Ball as a heatmap/centre-point head (FootAndBall, TrackNet, CenterNet style) rather than box regression suits a 5–8 px object; input at native resolution in tiles, never downscaled below the ball size.

### Gaps
- FootAndBall training wall-clock time and hardware are not stated in the paper or repo.
- TrackNetV2/V3 training epochs and GPU-hours were not found.
- He et al. also report that from scratch overfits with very small data (I recall ~1k COCO images / VOC); not re-read in this session — verify Section 5 of arXiv 1811.08883 before relying on it.
- No source quantifies "images needed" for single-scene sports detectors trained from scratch beyond FootAndBall's own dataset size.

## 4. Self-training / pseudo-labelling and distillation (teacher → small student)

### Takeaway
Teacher–student pseudo-labelling is the proven way to avoid hand labelling: Unbiased Teacher gains ~10 mAP over a supervised baseline at 0.5–2% labelled COCO; plain logit distillation gives little for detectors, but feature imitation near objects gives up to ~15% relative mAP. For video, tracking-based filtering (drop boxes on short tracks, add tracker-only boxes for detector misses) is an established recipe — and is exactly what the project already does with interpolated ball tracks.

### Cited Findings
- **Unbiased Teacher** (ICLR 2021): student + slowly updated (EMA) teacher; focal-style loss to counter class imbalance and down-weight overconfident pseudo-labels; ~+10 mAP over the supervised baseline at 0.5%, 1%, 2% labelled COCO and +6.8 mAP over the previous state of the art at 1% — [arXiv 2102.09480](https://arxiv.org/abs/2102.09480)
- **Soft Teacher** (ICCV 2021): weights each pseudo-box's classification loss by the teacher's score and uses box jittering to select reliable boxes for regression; beats prior methods at 1/5/10% labelled COCO (exact numbers not retrieved) — [deepai: Soft Teacher](https://deepai.org/publication/end-to-end-semi-supervised-object-detection-with-soft-teacher)
- **Fine-grained feature imitation** (CVPR 2019): vanilla knowledge distillation applied to detection gives only minor gain (~+0.9 mAP on their toy detector); full-feature-map hint learning even hurt a 0.25× student by 8.9 mAP; imitating the teacher only at near-object anchor locations gave up to 15% relative mAP boost on KITTI (+6.6 mAP for the 0.25× model) and closed up to 74% of the student–teacher gap on VOC/COCO Faster R-CNN — [arXiv 1906.03609](https://arxiv.org/abs/1906.03609)
- GAN-based distillation for one-stage detectors: ResNet50 student 67.0 → 73.8 mAP on VOC07 with a ResNet101 teacher — [arXiv 1906.08467](https://arxiv.org/abs/1906.08467); gradient-guided KD reports +5.1 / +3.8 mAP average for one-/two-stage detectors — [arXiv 2303.04240](https://arxiv.org/abs/2303.04240)
- **Tracker-filtered pseudo-labels:** Roychowdhury et al. adapt detectors to new domains with high-confidence detections plus tracker-based refinement; "tracker-only" boxes (where the detector missed the object) are added as hard positives — [arXiv 1904.07305](https://arxiv.org/abs/1904.07305). LEOD runs forward + backward tracking and removes a pseudo-box only if its track is short in both directions, ignores loss on low-confidence boxes, and repeats the cycle — [arXiv 2311.17286](https://arxiv.org/abs/2311.17286). The LiDAR "track, refine, retrain, repeat" work scores tracklets for temporal consistency and ignores short tracklets in the next round — [arXiv 2311.02007](https://arxiv.org/abs/2311.02007)
- Survey caution: training directly on pseudo-labels reinforces errors; confidence filtering is used to remove unreliable ones — [UDA for detectors survey, arXiv 2105.13502](https://arxiv.org/abs/2105.13502)

### Inferences
- Recommended recipe for this project (inference): (1) Teacher = the existing pipeline (YOLO11s players + `ball_v02` + `ball_window` + spare-ball/background filters + track interpolation) run offline on all frames — it is allowed to be slow and AGPL because it never ships; (2) keep pseudo-labels only on tracks ≥ N frames in both directions, add interpolated/tracker-only boxes as hard positives, mark low-confidence regions as "ignore" instead of negative; (3) train the own small student from scratch on these labels with heavy augmentation; (4) use the student itself as the next teacher (Noisy-Student-style rounds, 2–3 iterations), each time evaluating on held-out minutes and an unseen match.
- Licence caveat: labels produced by an AGPL/COCO-trained teacher are data, not code; training an own-architecture student on them is the usual way to get an own model, but whether pseudo-labels from Ultralytics models create obligations is a legal question, not a technical one (not researched here). The owner's "everything own" rule may prefer bootstrapping the final rounds from the own model only.
- For distillation, the cheapest win is output-level: train the student on the teacher's soft heatmaps/scores (not only hard boxes); feature imitation needs matching feature maps and is more work — only worth it if the student plateaus.
- Heavy augmentation that matches the domain: random scale 0.8–1.2, crops, flips, photometric jitter (FootAndBall's set), plus copy-paste of ball crops onto grass, motion blur, JPEG/compression noise, and shadows — these fight overfitting to 3 stadiums.
- Curriculum on crops/tiles: start on crops centred on balls/players (high positive density, cheap), then add random tiles and hard negatives (logo letters, spare balls, corner flags already identified in `specs/status.md`), finally full-resolution tiles for calibration.

### Gaps
- Noisy Student (classification) and STAC numbers were not retrieved in this session; STAC search returned nothing.
- No source found that reports self-training specifically for tiny sports balls with a tracker filter; gains for our case are unknown until measured.

## 5. Resumable training and a realistic timeline

### Takeaway
Run training as a detached process (not inside a 10-minute command), checkpoint at least every epoch (or every ~5 min) with model + optimizer + scheduler + EMA + RNG + epoch/step, and resume automatically; with that, a first own player model and ball model are realistic in ~6–10 weeks at 1 h/day, and on-phone A/B in ~10–14 weeks.

### Cited Findings
- Colab free sessions time out on idle and are capped at 12 h; Kaggle sessions are capped at 12 h — [Colab FAQ](https://research.google.com/colaboratory/faq.html); [gpuperhour.com](https://gpuperhour.com/blog/free-cloud-gpus-and-credits)
- Project rule: long steps must be resumable because commands can be killed after ~10 minutes and sessions restart — `CLAUDE.md` in the repo.
- FootAndBall's schedule (100 epochs, step LR at epoch 75) is a simple, resumable schedule — [arXiv 1912.05445](https://arxiv.org/abs/1912.05445)

### Inferences
Resumable-training practice (engineering inference, no single source):
- Start with `nohup caffeinate -i python train.py ... >> log &` (or a `launchd` job) so a killed Claude command does not kill training; the Mac must not sleep.
- Save `last.pt` atomically (write `tmp`, then `os.replace`) every epoch and every ~5–10 min mid-epoch: model, optimizer, LR scheduler, EMA weights, GradScaler (on CUDA), epoch, step, best metric, `torch`/`numpy`/`random` RNG states. On start, if `last.pt` exists, resume.
- Deterministic data: a fixed list of crop files with a per-epoch seed (`seed + epoch`) for shuffling and augmentation, so a resumed epoch sees the same order; skip the first `step` batches on resume.
- Same code on M1 and Kaggle: device auto-detect (`cuda` → AMP on; `mps` → fp32); Kaggle writes `last.pt` to `/kaggle/working`, next session attaches it as an input dataset.
- Log metrics to an append-only JSONL; evaluate on fixed held-out crops every N epochs; keep `best.pt`.

Realistic timeline at ~1 h/day of attention (training runs unattended overnight on the M1 and in Kaggle background runs; all ranges are inference with high uncertainty):

| Phase | Work | Weeks |
| --- | --- | --- |
| 0. Micro-benchmark | Same tiny detector script on M1 (fp32) and Kaggle T4 (AMP): img/s, check MPS correctness | 0.5 |
| 1. Data preparation | Run teacher on all frames of 3 matches; tracker filtering; export player/ball crops + ignore masks + hard negatives; held-out last 20% + one unseen match; upload crops to a private Kaggle dataset | 1.5–2 |
| 2. First player model | FootAndBall/CenterNet-style tiny net from scratch, 150–300 epochs on crops; 3–5 overnight runs to tune | 1.5–2 |
| 3. First ball model | Heatmap head on native-res tiles, curriculum crops → tiles → hard negatives; 1–2 self-training rounds | 2–3 |
| 4. Evaluation vs existing YOLO | Same `detections.jsonl` format, `follow.py --no-render`, `check_goals.py`, `compare_crops.py`, `live_sim.py` on 3 matches; contact sheets | 1–1.5 |
| 5. Core ML export | `coremltools` conversion, fp16, check outputs match PyTorch, speed on iPhone; Swift post-processing | 1–1.5 |
| 6. On-phone A/B | Old vs new detector in Follo on recorded and live games | 1–2 |
| **Total** | | **~9–14 weeks** (first usable player model ~4 weeks in; ball is the riskiest part) |

- Biggest risks (inference): the ball generalising to a new stadium (TrackNetV2-like drop on unseen matches); only 3 matches of data (add more SoccerTrack v2 matches if licence allows); MPS bugs/slowness forcing more work onto the Kaggle quota; time spent on data plumbing rather than training.
- Compute is not the bottleneck: one training run of a tiny detector on ~15k crops is ~1 night on the M1 or ~1 h on a Kaggle T4 (inference from Section 3), so ~20–30 Kaggle h/week allows ~10–20 experiments per week — far more than 1 h/day of attention can review.

### Gaps
- No public measurement of Core ML export effort/time for FootAndBall-like nets was researched here.
- The timeline assumes no major MPS correctness problem; this must be checked in phase 0.
