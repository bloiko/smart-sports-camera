# Own-code neural detectors for far football players and a 5–8 px ball: architectures and accuracy vs Ultralytics YOLO

Research date: 2026-10-17. Most primary results are from 2019–2025 papers; years are noted inline. Our setting: a fixed, high, wide camera with a 4K panorama, far players 15–30 px tall, a 5–8 px ball that is often blurred or occluded, and the ball searched inside small ROIs.

## Q1. Which architectures fit players-as-points and a 5–8 px ball best, and what accuracy do they report vs YOLO-family baselines?

### Takeaway
The strongest candidates that one person can build are a FootAndBall/CenterNet-style fully convolutional heatmap detector for players (points plus a coarse size) and a WASB/TrackNet-style multi-frame, high-resolution heatmap network for the ball. On the ISSIA-CNR soccer dataset, FootAndBall (199k params) beat Faster R-CNN on both ball AP (0.909 vs 0.866) and player AP (0.921 vs 0.874). On a soccer ball benchmark, WASB (1.5M params, 3 frames) reached F1 88.3 vs 44.5 for the single-frame DeepBall. None of these papers compares directly against YOLOv8 or YOLO11, so any "vs YOLO" verdict is an inference.

### Cited Findings

**FootAndBall (Komorowski, Kurzejamski, Sarwas, 2019/2020): one network for players and ball**
- The design is a small FPN-style fully convolutional network. The bottom-up path has 5 conv blocks (16 filters in Conv1, 32–64 in Conv2–Conv5), each followed by 2×2 max-pooling, and the top-down path uses 1×1 lateral convs. It has three heads: a ball confidence map at stride 4 (each cell covers 4×4 px), a player confidence map at stride 16, and a 4-channel player box regression at stride 16. All layers use BatchNorm and ReLU — [arXiv 1912.05445 (ar5iv)](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Size: about 199k params (Table 2; the introduction says about 120k). Comparisons: SSD300 about 24M, Faster R-CNN R50 about 25.6M, DeepBall 49k. The paper has minor internal inconsistencies in channel counts — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- ISSIA-CNR results (Table 2):
  - FootAndBall: ball AP 0.909, player AP 0.921, mAP 0.915, 37 FPS.
  - Faster R-CNN: ball 0.866, player 0.874, 8 FPS.
  - DeepBall: ball AP 0.877, 87 FPS.
  - Reno et al. 2018: ball 0.834.
  - FootAndBall without the top-down path: ball 0.853, player 0.889.
  - On the separate "Soccer Player Detection" dataset, Faster R-CNN beat FootAndBall on players (0.928 vs 0.885).
  - Note: the paper's text gives Faster R-CNN player AP on ISSIA as 0.774, but the table says 0.874.
  - Source: [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Speed was measured at Full HD (1920×1080) input on a low-end GTX 1060 — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- ISSIA-CNR: 6 Full-HD cameras at 25 fps, about 20,000 annotated frames. Player heights are 63–144 px, so the players are much larger than our 15–30 px far players. The ball is about 8 px far from the camera and about 20 px near it — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Training: Adam with lr 1e-3, reduced 10× after 75 of 100 epochs, batch size 16, 80/20 split. Augmentation: scale 0.8–1.2, random crop, flip and photometric changes. Loss: BCE on both confidence maps plus Smooth-L1 on boxes, with hard-negative mining at 3:1. Ball positives are the ground-truth cell plus its neighbours. The paper does not mention ImageNet pretraining — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Failure cases:
  - Missed balls: severe occlusion, and confusion with white kits or white advertising boards.
  - False positives: white socks and clutter off the pitch.
  - Source: [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Official code: [github.com/jac99/FootAndBall](https://github.com/jac99/FootAndBall) (as linked from the paper).

**CenterNet, "Objects as Points" (Zhou et al., 2019): generic point detector**
- Detects objects as center-point keypoints on a heatmap and regresses size and other properties from the center. COCO results: 28.1% AP at 142 FPS, 37.4% AP at 52 FPS, and 45.1% AP with multi-scale testing at 1.4 FPS — [arXiv 1904.07850](https://arxiv.org/abs/1904.07850)
- Uncertain (from the paper body, not verified in this fetch): the three results correspond to ResNet-18, DLA-34 and Hourglass-104 backbones respectively.

**WASB, Widely Applicable Strong Baseline for sports ball detection and tracking (Tarashima et al., BMVC 2023)**
- Architecture: HRNet-style network with the stem strides removed, so features stay near input resolution. It takes 3 consecutive frames stacked on channels and outputs 3 heatmaps at input resolution. Input is 288×512 and the model has 1.5M params. It is trained from scratch (Adam, 30 epochs, batch size 8) with hard-to-localize sample mining from epoch 20. Positive-label radius d = 2.5 — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
- Soccer results (1920×1080, 25 fps; data re-annotated by the authors), F1 / AP / FPS at tolerance τ = 4 px (Table 2):

  | Method | Params | F1 | AP | FPS |
  |---|---|---|---|---|
  | DeepBall | 0.1M | 44.5 | 26.3 | 44.6 |
  | DeepBall-Large | 1.0M | 44.9 | 34.0 | 42.0 |
  | BallSeg | 12.7M | 36.1 | 20.0 | 64.8 |
  | TrackNetV2 | 11.3M | 86.6 | 77.2 | 66.0 |
  | ResTrackNetV2 | 1.2M | 84.6 | 75.5 | 56.2 |
  | MonoTrack | 2.9M | 85.2 | 78.6 | 58.0 |
  | WASB (step 3) | 1.5M | 88.3 | 83.6 | 55.7 |
  | WASB (step 1) | 1.5M | 88.2 | 86.2 | 23.6 |

  Source: [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
- The paper also reports tennis, badminton, volleyball and basketball. WASB step 1 reaches F1 95.6 on tennis and 93.1 on badminton. The paper claims WASB's AP beats the best prior methods by 7.8–16.8 points. It does not compare against any YOLO model and does not report precision or recall separately — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
- Average ball displacement between frames on the soccer set: 10.4 ± 10.0 px (train) and 15.7 ± 13.0 px (test). So the ball moves 1–3 ball diameters per frame — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)

**TrackNet family (tennis and badminton; heatmap U-Net or VGG-DeconvNet over consecutive frames)**
- TrackNet (2019):
  - Architecture: the first 13 layers of VGG-16 as the encoder, a DeconvNet-style decoder, BN on every conv, and a 256-level softmax heatmap per pixel. Initial weights are random uniform, so there is no pretraining.
  - Input and labels: frames resized from 1280×720 to 640×360. Tennis balls are 2–12 px in diameter, about 5 px on average. Labels are Gaussian with σ² = 10.
  - Source: [arXiv 1907.03698 (ar5iv)](https://ar5iv.labs.arxiv.org/html/1907.03698)
- TrackNet tennis results at ≤5 px tolerance:
  - 3-frame Model II: P 99.8%, R 96.6%, F1 98.2%.
  - Classic image-processing baseline: F1 82.5%.
  - With 10-fold cross-validation (a more realistic split), Model II′ falls to F1 84.3%.
  - Source: [ar5iv 1907.03698](https://ar5iv.labs.arxiv.org/html/1907.03698)
- TrackNetV2 (badminton): reported accuracy 85.2%, precision 97.2% and recall 85.4% on an unseen match. This comes from a search snippet of the paper page, not checked in full text — [TrackNetV2 (paperswithcode mirror)](https://astro.paperswithcode.com/paper/tracknetv2-efficient-shuttlecock-tracking)
- TrackNetV3 (MMAsia 2023) adds trajectory rectification. Its README reports on the shuttlecock dataset:
  - TrackNetV3: accuracy 97.51%, P 97.79%, R 99.33%, F1 98.56%, 25.11 FPS.
  - TrackNetV2 on the same table: accuracy 94.98%, P 99.64%, R 94.56%, F1 97.03%, 27.70 FPS.
  - The paper abstract says accuracy rose from 87.72% to 97.51% against a different baseline.
  - These numbers were seen through search results, not checked against the paper tables — [TrackNetV3 paper PDF](https://people.cs.nycu.edu.tw/~yushuen/data/TrackNetV3.pdf), [TrackNetV3 repo mirror](https://gitee.com/tslnihao/TrackNetV3)
- TrackNetV4 (2024) adds motion attention maps to TrackNetV2 and reports consistent accuracy and F1 gains — [arXiv 2409.14543](https://arxiv.org/pdf/2409.14543)

**TOTNet (Aug 2025): temporal 3D-conv U-Net with occlusion-aware training**
- Architecture: 5 input frames at 288×512, 2D spatial convs followed by 3D temporal convs, 8.65M params, 28 FPS. A variant adds optical flow from a pretrained RAFT model (third-party, so it would not fit our rules).
- Results on tennis vs WASB, at ≤5 px (visible, partial) and ≤10 px (full occlusion):

  | Model | Acc visible | Acc partial | Acc fully occluded | RMSE visible |
  |---|---|---|---|---|
  | TOTNet | 0.95 | 0.61 | 0.67 | 6.07 |
  | WASB | 0.92 | 0.52 | 0.17 | 16.58 |
  | TrackNetV2 | 0.84 | 0.49 | 0.00 | 24.48 |

- Its gains come mainly on occluded balls. Visibility-weighted BCE plus an augmentation that masks the ball in the target frame took fully-occluded accuracy from 0.54 to 0.74 on a table-tennis set. Baselines were re-implemented by the authors, and there is no soccer or YOLO comparison.
- Source: [arXiv 2508.09650](https://arxiv.org/html/2508.09650)

**YOLO-family baselines on sports balls (weak or indirect evidence only)**
- Ultralytics YOLO11 on COCO at 640 px input:

  | Model | mAP50-95 | Params | FLOPs |
  |---|---|---|---|
  | YOLO11n | 39.5 | 2.6M | 6.5B |
  | YOLO11s | 47.0 | 9.4M | 21.6B |

  Licence: AGPL-3.0 or Enterprise — [Ultralytics docs](https://docs.ultralytics.com/models/yolo11/)
- A 2025 PeerJ review of ball detection notes that YOLOv8 fails to detect smaller objects accurately because of lower recall. Improved variants add a small-object head and SE attention — [PeerJ CS 3079](https://peerj.com/articles/cs-3079/)
- Badminton: one study found YOLOv4 beat TrackNetV2 on F1 (TrackNetV2 had more false negatives) and ran at 60 vs 20 FPS on an RTX 3070. Uncertain: seen only in a search summary, and I could not tell whether the source is [arXiv 2306.14492](https://arxiv.org/pdf/2306.14492) or [PMC11244353](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11244353/).
- An informal Medium case study of YOLOv8 on Norwegian Eliteserien footage reports sporadic ball detections and ball precision of only 0.458. This is a blog, so the evidence is weak — [Medium](https://medium.com/@waynemataara/training-yolov8-for-football-object-detection-insights-from-the-norwegian-eliteserien-7f0d00d28be8)

**Panoramic far-player scale reference**
- SoccerTrack v2 (2025): full-pitch panorama about 4K wide (3840 or 4096 px). Median player box is 25×55 px. In panoramic footage the ball spans "only a few pixels", and when the frame is downscaled to a typical backbone input, the ball covers about 1 px. The paper gives no YOLO or detector mAP baseline — [arXiv 2508.01802](https://arxiv.org/html/2508.01802)

### Inferences
- Players as points:
  - A CenterNet/FootAndBall-style heatmap head maps directly onto what the camera logic needs: a center or foot point plus an approximate height. It also avoids anchors and NMS (a 3×3 max-pool peak finder is enough).
  - Our far players (15–30 px) are 2–5× smaller than ISSIA players (63–144 px). A stride-16 player map like FootAndBall's would put a far player in only 1–2 cells. A stride-4 or stride-8 map is the safer choice.
- Ball inside ROIs:
  - A WASB-like 3-frame, near-full-resolution heatmap network is the best-supported choice.
  - Because the ROI is small (for example 256×256 or 288×512 crops), the full-resolution cost that makes WASB slow on whole frames becomes affordable.
  - WASB's key design points — no early downsampling, a high-resolution output, and multiple frames — are the same factors ScratchDet found matter for small objects (see Q2).
- Vs YOLO: no paper directly pits these architectures against YOLOv8 or YOLO11 on a 5–8 px soccer ball, so the comparison below is reasoned, not measured.
  - YOLO's finest standard output is stride 8 (P3), so a 5–8 px ball is under one cell, which fits the reported recall problems on small objects.
  - Multi-frame heatmap models beat single-frame heatmap models by large margins (see Q3).
  - A multi-frame heatmap model inside ROIs is therefore likely to match or beat a fine-tuned single-frame YOLO11n on ball recall at a few pixels' tolerance. This needs to be measured on our checklists.

### Gaps
- No published head-to-head between WASB, TrackNet or FootAndBall and YOLOv8 or YOLO11 on soccer balls of 5–8 px.
- No published per-size (15–30 px) player detection numbers for heatmap detectors vs YOLO on panoramic soccer. SoccerTrack v2 publishes no detector baselines in the part I read.
- Did not verify the WASB soccer ball-size distribution in pixels; the paper does not report it.
- BallTrack and SoccerNet ball-specific challenge numbers were not found within the tool budget.

## Q2. How well do small detectors trained from scratch (no ImageNet) perform on narrow domains?

### Takeaway
Training from scratch works well when there is enough data (roughly 10k images for multi-class COCO) and when BatchNorm or GroupNorm and longer schedules are used. With too little data it breaks down: 3.5k COCO images gave 9.3 AP from scratch vs 16.0 pretrained. All the sports-ball networks above (TrackNet, WASB, and apparently FootAndBall) are trained from scratch on a few thousand to tens of thousands of frames from one domain and still reach high scores.

### Cited Findings
- He, Girshick, Dollár, "Rethinking ImageNet Pre-training" (2018):
  - Mask R-CNN from random initialization is "no worse" than ImageNet-pretrained on COCO, reaching 50.9 AP with no external data. Pretraining mainly speeds convergence and does not necessarily improve final accuracy — [arXiv 1811.08883](https://arxiv.org/abs/1811.08883)
  - Small-data COCO results with R50-FPN and GN (bbox AP):

    | Training images | Pretrained | From scratch |
    |---|---|---|
    | 10k | 26.0 (60k iterations) | 25.9 (220k iterations) |
    | 3.5k | 16.0 | 9.3 |
    | 1k | 9.9 | 3.5 (5.4 after a grid search) |

    The breakdown point lies between 3.5k and 10k images. On PASCAL VOC, scratch training reached 77.6 vs 82.7 mAP with pretraining. Normalization (GN or SyncBN) is required — [ar5iv 1811.08883](https://ar5iv.labs.arxiv.org/html/1811.08883)
- ScratchDet (2018), from scratch:

  | Method | VOC07 mAP | VOC12 mAP | COCO AP | FPS |
  |---|---|---|---|---|
  | ScratchDet300 | 80.4 | 78.5 | 32.7 | 17.8 (Titan X) |
  | DSOD300 | 77.7 | 76.3 | 29.3 | – |
  | GRP-DSOD320 | 78.7 | 77.0 | 30.0 | – |
  | SSD300 (pretrained VGG-16) | 77.2 | 75.8 | 25.1 | – |

  Source: [ar5iv 1810.08425](https://ar5iv.labs.arxiv.org/html/1810.08425)
- ScratchDet ablations:
  - Without BN, SSD from scratch reaches 67.6 mAP and diverges at higher learning rates. BN across the whole network allows lr 0.05 and 78.7 mAP. Removing BN from DSOD drops it from 77.7 to 71.5.
  - Removing first-layer downsampling (Root-ResNet-18) raised mAP from 73.1 to 78.5 but cut FPS from 59.5 to 26.9.
  - COCO small-object AP (APs): 13.0 for ScratchDet vs 6.2 for SSD321.
  - Source: [ar5iv 1810.08425](https://ar5iv.labs.arxiv.org/html/1810.08425)
- DSOD (2017) trains from scratch on the SSD framework with deep supervision through dense connections. It uses about half the parameters of SSD and a tenth of Faster R-CNN, beats SSD on VOC and COCO, and is argued to avoid ImageNet domain bias — [arXiv 1708.01241](https://arxiv.org/abs/1708.01241)
- Sports-specific evidence of scratch training:
  - WASB is explicitly "trained from scratch" (1.5M params, 30 epochs) — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
  - TrackNet uses random uniform initial weights — [ar5iv 1907.03698](https://ar5iv.labs.arxiv.org/html/1907.03698)
  - FootAndBall's paper does not mention any pretraining for its custom 199k-param backbone — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Generalisation warning: TrackNet tennis F1 dropped from 98.2–98.5% on a random split to 84.3% with 10-fold cross-validation. TrackNetV2 reported about 85% accuracy on a "brand-new match". Unseen matches are much harder than random frame splits — [ar5iv 1907.03698](https://ar5iv.labs.arxiv.org/html/1907.03698), [TrackNetV2](https://astro.paperswithcode.com/paper/tracknetv2-efficient-shuttlecock-tracking)

### Inferences
- A fixed sports camera with 1–2 classes and many instances per frame (about 22 players) is a much narrower problem than 80-class COCO. The "≥10k images" threshold should therefore be easier to meet. 20 minutes of video at 25 fps already gives 30k frames, although they are highly correlated.
- The real risk is overfitting to a few matches. Train on many matches and venues and evaluate on an unseen match, as the project rule already requires.
- BN or GN everywhere, longer schedules and no aggressive early downsampling are the practical recipe drawn from these papers.

### Gaps
- No study found that quantifies from-scratch vs pretrained specifically for soccer players at 15–30 px.
- No numbers found for how many labelled frames or matches FootAndBall-style or WASB-style nets need to generalise across stadiums.

## Q3. Does feeding 2–3 consecutive frames materially improve tiny-ball detection?

### Takeaway
Yes. The direct ablation is TrackNet on tennis: 1 frame gave F1 92.5% and 3 frames gave 98.2%, with recall rising from 89.6% to 96.6%. Indirectly, every multi-frame heatmap model on WASB's soccer benchmark (F1 84.6–88.3) far outperforms single-frame DeepBall (F1 44.5–44.9). Temporal models also recover a meaningful share of fully occluded balls where single-frame-style baselines get none.

### Cited Findings
- TrackNet, tennis, ≤5 px tolerance:

  | Model | Precision | Recall | F1 |
  |---|---|---|---|
  | Model I (1 frame) | 95.7% | 89.6% | 92.5% |
  | Model II (3 frames) | 99.8% | 96.6% | 98.2% |

  The 3-frame model also found 2 of the 7 fully occluded balls — [ar5iv 1907.03698](https://ar5iv.labs.arxiv.org/html/1907.03698)
- WASB soccer, τ = 4 px:
  - Single-frame DeepBall: F1 44.5, AP 26.3.
  - Multi-frame TrackNetV2: F1 86.6, AP 77.2.
  - WASB (3 frames): F1 88.3, AP 83.6.
  - This confounds frame count with architecture and resolution. WASB does not ablate 1 vs 3 frames — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
- TOTNet uses 5 frames ("chosen experimentally"); the 1/3/5-frame ablation is only in its supplementary material. On tennis it reached 0.67 accuracy on fully occluded balls, vs 0.17 for WASB and 0.00 for TrackNetV2 — [arXiv 2508.09650](https://arxiv.org/html/2508.09650)
- Kukleva et al. (2019) used ConvLSTM, ConvGRU and TCN over a history of frames, against a single-image encoder-decoder baseline for soccer ball detection. The abstract claims temporal history helps in hard cases; numbers were not retrieved — [arXiv 1909.02406](https://arxiv.org/abs/1909.02406)

### Inferences
- For a 5–8 px, motion-blurred ball against a fixed background, frame stacking gives the network free motion cues similar to background subtraction. This is why the gain is largest for recall and occlusion.
- With our fixed camera this cue should be at least as strong as in broadcast sports footage, where the camera moves.
- Cost: 3 frames stacked on channels only changes the first conv (3 → 9 input channels), so it costs almost nothing.

### Gaps
- No clean 1-vs-3-frame ablation on soccer specifically. TOTNet's supplementary material and the Kukleva et al. full text were not read.

## Q4. Typical model sizes and implementation complexity

### Takeaway
The useful sports-specific networks are tiny compared with YOLO11s. FootAndBall has about 0.2M params, WASB 1.5M, ResTrackNetV2 1.2M, MonoTrack 2.9M, TOTNet 8.65M and TrackNetV2 11.3M, against YOLO11n at 2.6M / 6.5 GFLOPs and YOLO11s at 9.4M / 21.6 GFLOPs. Each has four components: a small conv backbone, an FPN or U-Net or HRNet-style fusion, heatmap (plus optional size and offset) heads, and a focal or BCE loss with peak-finding decoding.

### Cited Findings
- Parameter counts:
  - FootAndBall 199k; DeepBall 49k; Faster R-CNN R50 25.6M; SSD300 about 24M — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
  - DeepBall 0.1M, DeepBall-Large 1.0M, BallSeg 12.7M, TrackNetV2 11.3M, ResTrackNetV2 1.2M, MonoTrack 2.9M, WASB 1.5M — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
  - TOTNet 8.65M — [arXiv 2508.09650](https://arxiv.org/html/2508.09650)
  - YOLO11n 2.6M / 6.5B FLOPs; YOLO11s 9.4M / 21.6B FLOPs — [Ultralytics docs](https://docs.ultralytics.com/models/yolo11/)
- Components as described in the papers:
  - FootAndBall:
    - Model: 5 conv blocks, 1×1 lateral FPN, 3 heads.
    - Loss: BCE plus Smooth-L1 with hard-negative mining.
    - Decoding: thresholding the confidence maps.
    - Source: [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
  - WASB:
    - Model: HRNet-style parallel branches with multi-resolution fusion.
    - Training: heatmap labels with radius 2.5 and hard-sample mining.
    - Decoding: heatmap center plus online tracking.
    - Source: [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
  - TrackNet:
    - Model: VGG-16-like encoder plus DeconvNet decoder.
    - Training: Gaussian labels with σ² = 10.
    - Decoding: threshold at 128 plus Hough circle.
    - Source: [ar5iv 1907.03698](https://ar5iv.labs.arxiv.org/html/1907.03698)
  - CenterNet: center heatmap plus size regression — [arXiv 1904.07850](https://arxiv.org/abs/1904.07850)
- Speed:
  - FootAndBall: 37 FPS at 1920×1080 on a GTX 1060 — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
  - WASB: 55.7 FPS on soccer (step 3; hardware per the paper) — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)

### Inferences
- Estimates, not from sources:
  - A FootAndBall- or CenterNet-style model in PyTorch is about 100–200 lines for the model, about 50–100 for loss and target generation, and about 30–50 for decoding.
  - A WASB-style network is about 200–400 lines.
  - In total, the code for a working detector (model, dataset, augmentation, training loop, evaluation at pixel tolerance) fits in about 1–2k lines. This is far less than porting Ultralytics.
- GFLOPs (estimate): FootAndBall-like nets at Full HD should be a few GFLOPs. WASB at 288×512 without the stem downsampling is likely tens of GFLOPs.

### Gaps
- GFLOPs are not reported for FootAndBall, WASB, TrackNet or TOTNet in the parts I read.
- No official line counts were checked.
- Phone (Core ML/ANE) latency for these architectures was not found.

## Q5. Expected quality vs YOLO11s (players) and a fine-tuned YOLO11n (ball) in our setting

### Takeaway
This is inference, not measured. For players, an own heatmap point detector should be about as good as YOLO11s for foot point and height within a few pixels, provided it runs at native or tiled resolution with a stride-4 or stride-8 output. It will likely be worse on exact box mAP and in crowded clusters, where boxes and NMS-free peaks merge. For the ball inside ROIs, a 3-frame WASB-like heatmap model is likely the same or better than a single-frame fine-tuned YOLO11n on recall at ≤4–5 px tolerance, especially for blurred or partly occluded balls. It may be worse on precision (white socks, lines, adverts) until hard negatives are mined.

### Cited Findings
- Evidence that a custom small heatmap network can match or beat a much larger generic detector in this domain:
  - FootAndBall (199k params) vs Faster R-CNN R50 (25.6M) on ISSIA: player AP 0.921 vs 0.874, ball AP 0.909 vs 0.866 — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
  - The same paper shows the generic detector winning on a different player dataset (0.928 vs 0.885) — [ar5iv 1912.05445](https://ar5iv.labs.arxiv.org/html/1912.05445)
- Evidence that multi-frame high-resolution heatmaps dominate single-frame ball detectors (DeepBall F1 44.5 vs WASB 88.3 on soccer) — [arXiv 2311.05237](https://arxiv.org/html/2311.05237)
- Evidence that YOLO-family recall degrades on small balls, from a review and a blog only — [PeerJ CS 3079](https://peerj.com/articles/cs-3079/), [Medium](https://medium.com/@waynemataara/training-yolov8-for-football-object-detection-insights-from-the-norwegian-eliteserien-7f0d00d28be8)
- Counter-evidence: in a badminton study, YOLOv4 beat TrackNetV2 on F1 and speed (attribution uncertain, see Q1).
- Scale reference: SoccerTrack v2 shows median panoramic player boxes of 25×55 px and a ball of a few pixels at 4K width. Any detector at 640 px input on a downscaled panorama would make the ball sub-pixel — [arXiv 2508.01802](https://arxiv.org/html/2508.01802)

### Inferences
- Conditions under which our own model is likely the same or better:
  - It is trained on our own fixed-camera matches (domain match), from scratch with BN, on more than about 10k varied frames from many matches.
  - It runs at native resolution or on tiles with a stride ≤ 8 player output and a stride-1 or stride-2 ball heatmap.
  - The ball model sees 3 frames.
  - It is evaluated by point distance (foot point within X px, ball within 4–5 px), not box IoU mAP.
- Conditions under which it is likely worse:
  - Little or one-venue training data (He et al. showed a large drop at 3.5k COCO images).
  - Clusters of players at 15 px.
  - Unusual kit or lighting colours.
  - Evaluation on box mAP@0.5:0.95.
- YOLO11s at 640 px on a whole 4K panorama (6× downscale) would see far players at about 2.5–5 px tall and is not a fair baseline. The fair comparison is YOLO on tiles or crops vs our own model on the same tiles, on identical inputs (project rule).
- Training labels: if the current YOLO outputs are used as pseudo-labels to train our own network, the shipped weights contain no third-party code or weights. Whether that is acceptable under the owner's "everything own" rule and the AGPL is a product and licensing question, not one answered by these sources.

### Gaps
- No source measures YOLO11s vs a heatmap player detector at 15–30 px, or YOLO11n vs WASB on a 5–8 px soccer ball. These must be measured on our matches (the held-out last 20% and an unseen match, plus the `specs/checklists/` moments).
- Mobile (A-series ANE) throughput of WASB-like stride-1 networks on ROI crops is unknown.
