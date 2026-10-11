# Ball detection/tracking and virtual camera (auto-pan/crop) for amateur football and basketball: technical state of the art (Oct 2026)

Context: solo developer, zero budget, PoC on a MacBook Air M1/M2 with 8 GB RAM, then real time on iPhone 15 / Android. Pipeline: 4K wide static camera → ball detection per frame → trajectory smoothing → 1080p crop that follows play.

## 1. Best models and approaches for detecting a small, fast ball, and how they fail

### Takeaway
No model reliably detects a 4–20 px ball in a full wide frame. Ball recall is the weak point across the literature: about 0.5 with YOLOv8s on broadcast footage, and about 0.24 mAP in an automatic basketball production system. Workable options are: (a) a single-class "ball" detector (YOLO26/YOLO11 nano/small or RF-DETR-N/S) run at higher resolution or on tiles (SAHI), plus temporal tracking; (b) TrackNet-style heatmap networks that take several consecutive frames and use motion. Both need a fallback to player positions when the ball is lost.

### Cited Findings
- **Ball recall is the bottleneck.** In a 2026 study, YOLOv8s fine-tuned at 1280×1280 on broadcast football scored ball precision 0.914, recall 0.511, mAP@0.5 0.616 and mAP@0.5:0.95 0.296. The author calls this "high precision, low recall". The 1280 input helps ball visibility but costs compute. — [Tshiani, arXiv 2602.18504](https://www.arxiv.org/pdf/2602.18504)
- An automatic basketball production system (modified YOLOv3) reached player mAP of about 0.90 at IoU 0.5, but ball mAP of only about 0.24. Raters noted jitter when the ball was missed and lag on long passes. — [Quiroga et al., CVPRW 2020 "As Seen on TV"](https://openaccess.thecvf.com/content_CVPRW_2020/papers/w53/Quiroga_As_Seen_on_TV_Automatic_Basketball_Video_Production_Using_Gaussian-Based_CVPRW_2020_paper.pdf)
- The Roboflow Universe "football-ball-detection" dataset model (YOLOv8x, 1 class) reports mAP@50 89.5%, precision 97.4%, recall 78.0%. That is on its own test set, in-domain (Bundesliga broadcast), and does not represent amateur footage. — [Roboflow Universe](https://universe.roboflow.com/roboflow-jvuqo/football-ball-detection-rejhg)
- **Reference ball pipeline (Roboflow sports):** a separate ball detector runs through `sv.InferenceSlicer` (SAHI-style) with 640×640 tiles at `imgsz=640`, then `with_nms(threshold=0.1)`, then `BallTracker(buffer_size=20)`. The tracker averages the last N positions and keeps the detection closest to that centroid, which filters false positives. The player detector runs at `imgsz=1280`. The README shows a `--device mps` option, so it runs on a Mac. — [roboflow/sports examples/soccer/main.py](https://github.com/roboflow/sports/blob/main/examples/soccer/main.py), [sports/common/ball.py](https://github.com/roboflow/sports/blob/main/sports/common/ball.py)
- **YOLO26** (Ultralytics, released 14 Jan 2026): optional NMS-free head, DFL removed, "up to 43% faster CPU inference". ProgLoss and STAL are aimed at small objects. YOLO26n gets 40.9 mAP with 38.9 ms CPU ONNX, against YOLO11n's 39.5 mAP and 56.1 ms. On a T4 with TensorRT, 1.7 ms vs 1.5 ms. — [Ultralytics YOLO26 vs YOLO11](https://docs.ultralytics.com/compare/yolo26-vs-yolo11)
- **RF-DETR** (Roboflow, DINOv2 backbone): N reaches 48.4 AP COCO at 384×384 in 2.3 ms; S reaches 53.0 AP at 512×512 in 3.5 ms; M 54.7, L 56.5. Latency measured on a T4 with TensorRT FP16. N/S/M/L are Apache 2.0. — [rf-detr README](https://github.com/roboflow/rf-detr), [Roboflow blog](https://roboflow.com/blog/rf-detr-nano-small-medium)
  - Caveat: the default RF-DETR input resolutions (384–512) are low, which is unfavourable for a tiny ball unless tiles are used. The blog post does not discuss small-object performance.
- **DEIM (D-FINE/RT-DETR-based):** N has 4M params, 43.0 AP, 2.12 ms; S has 10M params, 49.0 AP, 3.49 ms. — [DEIM GitHub](https://github.com/Intellindust-AI-Lab/DEIM)
- **TrackNet family (heatmaps over several frames, built for tennis and badminton):** TrackNetV3 adds an estimated background as auxiliary input, mixup augmentation, and inpainting-based trajectory rectification for occlusions. On the shuttlecock dataset, TrackNetV2 scored F1 97.03% at 27.7 FPS, versus YOLOv7 at F1 68.00% and 34.77 FPS. — [TrackNetV3 README](https://github.com/qaz812345/TrackNetV3), [paper ACM MM Asia 2023](https://dl.acm.org/doi/10.1145/3595916.3626370)
- TrackNetV4 (Griffith) adds motion attention maps built from frame differences, and says it improves V2/V3 on tennis and badminton. No figures are published, and the code is listed as "coming soon". — [TrackNetV4 site](https://time.griffith.edu.au/paper-sites/tracknet-v4)
- Original TrackNet: "tracking high-speed and tiny objects" via heatmaps over consecutive frames. — [arXiv 1907.03698](https://arxiv.org/pdf/1907.03698)
- **FootAndBall:** a specialised football detector, fully convolutional with FPN, outputting ball and player heatmaps. It has about 100× fewer parameters than SSD/YOLO and targets real time on high-resolution video. Trained on ISSIA-CNR. MIT licence. The README gives no FPS or accuracy figures. — [jac99/FootAndBall](https://github.com/jac99/footandball), [arXiv 1912.05445](https://arxiv.org/pdf/1912.05445)
- **SAHI cost:** compute grows with the number of tiles. ROI-gated SAHI, where YOLOv8n proposes regions at 416 px and only those regions are tiled, ranges from 6.9× faster (ROI = 2.7% of the frame) to slower than full SAHI in dense scenes. — [ROI-Gated SAHI, arXiv 2608.23923](https://arxiv.org/pdf/2608.23923); SAHI library is MIT ([obss/sahi](https://github.com/obss/sahi))
- Commercial auto-panning (BallerCam) lists these tracking failures: players blocking the ball, a low camera, a camera far from the field, heavy movement near the field, rain on the lens, and visual distractions. — [BallerCam support](https://support.ballercam.com/hc/en-us/articles/37594640211085-How-BallerCam-s-AI-Panning-Works)

### Inferences
- In 4K (3840×2160), an amateur-football ball seen from the touchline is roughly 8–25 px. Downscaling to 640 shrinks it to 1–4 px, so it effectively disappears. Practical options: (1) fixed tiling of 4K into about 6 tiles of 1280×1080, or 640 tiles, only on the PoC; (2) on the phone, a cheap 640–1280 px pass over the whole frame plus a high-resolution crop (ROI tile) around the predicted ball position from the Kalman filter. This is the same idea as ROI-gated SAHI and costs one or two inferences per frame instead of 10 or more.
- TrackNet-style models use temporal information (motion blur turns into a "streak" the network can learn) and suit a static camera well, because the background is constant. TrackNetV3's background estimation works especially well with a static camera. Weakness: they were trained on rackets/shuttlecocks and need retraining on football/basketball.
- Main failure modes: tiny size at distance, motion blur on long passes, occlusion by players or the basket, false positives (heads, shoes, field-line markings, spare balls on the touchline), artificial lighting at night (noise, flicker), and a ball high in the air against a bright sky.

### Gaps
- I did not find a public benchmark comparing YOLO26 / RF-DETR / TrackNet on amateur football filmed with a static 4K camera.
- I found no confirmed figures on how much YOLO26's STAL/ProgLoss improves ball detection specifically.
- No public night-lighting results for ball detection.

## 2. Open-source projects doing similar things (links, licences)

### Takeaway
No ready-made open-source "auto-cameraman" that does all of 4K → ball → smooth crop is maintained and popular. The best starting point is the **roboflow/sports** repo (MIT: detectors, SAHI tiling, BallTracker, Colab training notebooks) combined with your own virtual-camera logic. Many "football analysis" repos on GitHub (YOLO + ByteTrack) are educational and mostly built on AGPL Ultralytics.

### Cited Findings
- **roboflow/sports** (MIT, about 5.4k stars): ball detection and tracking, player tracking, team classification (SigLIP+UMAP+KMeans), pitch keypoints/homography. Models are Ultralytics YOLOv8, so the trained weights fall under AGPL. Data comes from the Kaggle DFL Bundesliga Data Shootout. There are Colab notebooks for training the ball, player and pitch detectors. — [roboflow/sports](https://github.com/roboflow/sports), [examples/soccer README](https://github.com/roboflow/sports/tree/main/examples/soccer)
- **FootAndBall** (MIT): specialised ball + player detector. — [GitHub](https://github.com/jac99/footandball)
- **TrackNetV3** implementation (about 301 stars, last push Sept 2026). No LICENSE file found in the repo (404), so the licence is not defined and legally that means "all rights reserved". — [qaz812345/TrackNetV3](https://github.com/qaz812345/TrackNetV3), [gittrend](https://gittrend.io/repo/qaz812345/TrackNetV3)
- Example YOLO + ByteTrack "football analysis" repos: [AhmedQassemDev2004/computer-vision-football-analysis](https://github.com/AhmedQassemDev2004/computer-vision-football-analysis), [AmmarMohamed0/Football-Analysis-System](https://github.com/AmmarMohamed0/Football-Analysis-System), [BlazeWild/MatchVision-AI](https://github.com/BlazeWild/MatchVision-AI-Sports-Video-Analytics-Tracking-Pipeline), [probablyabdullah/Football-Tracking-with-YOLOv5-Bytetrack](https://github.com/probablyabdullah/Football-Tracking-with-YOLOv5-Bytetrack). Licences not checked individually.
- **HIGOAL 1.0** (Univ. Florence, MICC): an academic project on automatic filming of football matches and highlight detection. — [MICC](https://www.micc.unifi.it/?p=1640)
- **Simula (Bagadus):** an older (2014) system for panoramic football video with a virtual camera. — [ACM MM 2014 demo](https://web-backend.simula.no/sites/default/files/publications/acmmm2014demo.pdf)
- **DeepSportradar** toolkit for basketball (ball 3D localisation challenge). — [gabriel-vanzandycke/deepsport](https://github.com/gabriel-vanzandycke/deepsport), [ball-3d-localization-challenge](https://github.com/DeepSportradar/ball-3d-localization-challenge)
- Commercial reference point: Veo uses AI so that amateur clubs can film matches without an operator. — [TechCrunch](https://techcrunch.com/?p=1532848)

### Inferences
- The most realistic plan is to take the idea and code of `InferenceSlicer` + `BallTracker` from roboflow/sports (MIT) but train the ball model on a permissive architecture (RF-DETR / YOLOX / D-FINE), so you don't inherit AGPL from Ultralytics.

### Gaps
- I found no actively maintained GitHub project specifically for an "auto-pan virtual camera for amateur football from a static camera". GitHub search was limited, so such projects may exist under other names.

## 3. Public datasets and licences

### Takeaway
For football balls: Roboflow Universe (many small datasets, typically CC BY 4.0), SoccerNet (large, but the videos require an NDA and there is no commercial permission), ISSIA-CNR (old, academic). For basketball: DeepSportradar (CC BY-NC-SA, non-commercial). For a commercial product you will need to collect and label your own amateur footage, which also fixes the domain mismatch.

### Cited Findings
- **Roboflow Universe "football-ball-detection"**: 1,237 images (4,948 in v4 after augmentation), 1 class "ball", **CC BY 4.0**. Source: Bundesliga broadcast (DFL Kaggle). — [Universe](https://universe.roboflow.com/roboflow-jvuqo/football-ball-detection-rejhg), [sports README](https://github.com/roboflow/sports/tree/main/examples/soccer)
- Other Universe ball sets include "Ball Detection high school soccer" (amateur domain), soccer-ball03, ball-detector, and more. Check licences individually. — [high school soccer](https://universe.roboflow.com/soccer-onc2e/ball-detection-high-school-socce), [soccer-ball03](https://universe.roboflow.com/sohma/soccer-ball03), [ball-detector](https://universe.roboflow.com/detect-players/ball-detector-44jlk)
- **SoccerNet**: devkit code is MIT, but "signing an NDA is required to access the LQ and HQ videos". — [SoccerNetv2-DevKit](https://github.com/SilvioGiancola/SoccerNetv2-DevKit). SoccerNet-Tracking (MOT, includes the ball as a class) — [arXiv 2204.06918](https://arxiv.org/pdf/2204.06918). The SoccerNet 2025 challenges include Team Ball Action Spotting (event detection, not ball tracking) and Game State Reconstruction (players). — [SoccerNet 2025 results, arXiv 2508.19182](https://arxiv.org/html/2508.19182v1)
- **SoccerTrack v2** (2025): full-pitch multi-view dataset for game state reconstruction. — [arXiv 2508.01802](https://arxiv.org/html/2508.01802v1)
- **ISSIA-CNR Soccer**: used to train FootAndBall. — [FootAndBall](https://github.com/jac99/footandball)
- **DeepSportradar basketball** (LNB Pro A): 1,456 images, classes human and ball. The ball is about 0.01% of the frame area and 3–44 px tall. Licence **CC BY-NC-SA 4.0** (non-commercial). — [DatasetNinja](https://datasetninja.com/deep-sport-radar), [arXiv 2208.08190](https://arxiv.org/abs/2208.08190v1)
- **Kaggle DFL Bundesliga Data Shootout**: the source video for Roboflow's datasets. — [Kaggle](https://www.kaggle.com/competitions/dfl-bundesliga-data-shootout)

### Inferences
- Broadcast data (SoccerNet, DFL) differs from an amateur static wide-angle 4K camera in angle, scale and lighting. Fine-tuning on your own 500–2,000 frames of amateur football/basketball (including night games) will probably matter more than choosing the architecture.

### Gaps
- I did not check the exact text of the SoccerNet NDA (whether commercial training is allowed), the licence of the ISSIA-CNR dataset, or the Kaggle DFL competition rules on reusing the data.

## 4. Licensing: Ultralytics AGPL vs permissive alternatives

### Takeaway
Ultralytics (YOLOv8/11/26) is AGPL-3.0, and **models trained with it are also AGPL**, so a closed-source app needs an Enterprise licence. The price is not published (quote on request). Permissive alternatives that allow commercial use: **RF-DETR N/S/M/L (Apache 2.0)**, **YOLOX (Apache 2.0)**, **RT-DETR (Apache 2.0)**, **D-FINE (Apache 2.0)**, **DEIM (Apache 2.0)**. Avoid for commercial use: **DEIMv2** (non-commercial licence), **YOLO-NAS weights** (Deci licence, non-commercial), **RF-DETR Atto/Femto/Pico/XL/2XL** (PML 1.0).

### Cited Findings
- Ultralytics: AGPL-3.0 requires "publicly releasing the complete corresponding source code for the entire derivative work", including model weights where applicable. "All Ultralytics YOLO trained models fall under the AGPL-3.0 License by default", even when trained from scratch. Closed/SaaS/embedded use requires an Enterprise License. There is no public price; it is quoted to the organisation. — [ultralytics.com/license](https://ultralytics.com/license)
- Roboflow is an authorised licensor of Ultralytics models (a paid Roboflow plan can include commercial rights). — [roboflow.com/ultralytics](https://roboflow.com/ultralytics)
- RF-DETR: "rfdetr package and Apache-designated models are released under Apache 2.0, while Plus components (rfdetr_plus, including RF-DETR-Atto/Femto/Pico/XL/2XL) are licensed under PML 1.0". — [rf-detr README](https://github.com/roboflow/rf-detr)
- Apache 2.0 confirmed from the LICENSE files of [YOLOX](https://github.com/Megvii-BaseDetection/YOLOX), [RT-DETR](https://github.com/lyuwenyu/RT-DETR), [D-FINE](https://github.com/Peterande/D-FINE), [DEIM](https://github.com/Intellindust-AI-Lab/DEIM). SAHI is MIT ([obss/sahi](https://github.com/obss/sahi)).
- DEIMv2 (released 26.09.2025, sizes Atto through X): its own licence says "Commercial Use of the DEIMv2 Materials is not permitted". — [DEIMv2 LICENSE.md](https://github.com/Intellindust-AI-Lab/DEIMv2/blob/main/LICENSE.md)
- YOLO-NAS: LICENSE.YOLONAS.md is quoted as "research and non-commercial use only" for weights and architecture. NVIDIA staff answers are contradictory (non-commercial vs Apache for the architecture), and no new licences are issued. — [NVIDIA forum](https://forums.developer.nvidia.com/t/licensing-and-usage-terms-for-yolo-nas-model/326342)

### Inferences
- For a free PoC, Ultralytics is fine (AGPL allows personal and experimental use). For a closed product, plan from the start to migrate to RF-DETR-N/S or D-FINE/DEIM-N/S, or budget for an Enterprise licence.
- Pretrained COCO weights for permissive models are fine to use, but check the licence of the training dataset (CC BY is OK, NC is not).

### Gaps
- No public price for the Ultralytics Enterprise License.

## 5. Trajectory smoothing and virtual camera logic

### Takeaway
The proven scheme from the literature and practice is: an "action point" = ball (when confidently detected) or weighted player positions (Gaussian heatmap / centroid) as a fallback → filtering (One Euro / Savitzky-Golay / Kalman) → a P-controller with a per-frame speed limit and a dead zone → a 16:9 crop. Add a small "lead" in the direction of motion and widen the frame (zoom out) when tracking confidence is low.

### Cited Findings
- **"As Seen on TV" (basketball, CVPRW 2020):** each player becomes a 2D Gaussian on the court (via homography); the sum gives an "actionness" map, convolved with a window about 1/4 of the court; the peak is the action point. The ball adjusts it: the frame is split into 5 vertical strips, and if the ball leaves the central 3, the point shifts. During transitions: a **One Euro filter**, then a **proportional controller with a per-frame displacement cap**. During half-court play the camera is almost static, and in pauses it zooms out to the whole court. Result: the ball is inside the 720p crop at least 95% of the time; raters gave main-action visibility 4.63/5 and ball enclosure 4.30/5. Weaknesses: jitter when the ball is lost, lag on long passes. — [Quiroga et al. CVPRW 2020](https://openaccess.thecvf.com/content_CVPRW_2020/papers/w53/Quiroga_As_Seen_on_TV_Automatic_Basketball_Video_Production_Using_Gaussian-Based_CVPRW_2020_paper.pdf)
- **Disney Research "Mimicking Human Camera Operators" (basketball):** a regressor (random forest) from player-position features (spherical heatmap) to the human operator's pan angle, ignoring the ball entirely ("player formation implies ball location"). Smoothing is a first-order Savitzky-Golay filter over 33 frames (about 0.5 s). Error after smoothing is about 1.7°, versus 3.0° for the simple centroid. "Smooth motion is critical for aesthetic camera work." — [Disney Research paper](https://la.disneyresearch.com/wp-content/uploads/Mimicking-Human-Camera-Operators-Paper.pdf)
- **Roboflow BallTracker:** a buffer of the last 20 positions, choosing the detection closest to their centroid (outlier rejection without a Kalman filter). — [ball.py](https://github.com/roboflow/sports/blob/main/sports/common/ball.py)
- TrackNetV3 rectifies occlusion gaps by inpainting the trajectory (offline). — [TrackNetV3](https://github.com/qaz812345/TrackNetV3)
- Patents on the virtual camera / mimicking a human operator (useful for checking freedom to operate): [US10003722 "mimicking human camera operation"](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10003722), [US10165157 hybrid robotic/virtual PTZ](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10165157), [US10262692 automatic television production](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10262692), [US12651456 real-time object-focused video](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12651456).
- BallerCam (commercial): pan/tilt/zoom inside a 180° image based on the ball, players and "where the action is heading"; automatic zoom in some cases. — [BallerCam](https://support.ballercam.com/hc/en-us/articles/37594640211085-How-BallerCam-s-AI-Panning-Works)

### Inferences (recommended PoC algorithm)
1. Each frame: ball candidates → gate by the Mahalanobis distance from the Kalman prediction (constant-velocity model, state x, y, vx, vy) → update.
2. If the ball is missing for more than about 0.5–1 s: the target is a weighted centroid / Gaussian peak of players (YOLO "person" is easy to detect even at 640), and the crop widens (zoom out, e.g. 1080p → 1440p window).
3. Camera: a dead zone (for example the central 30–40% of the crop width) inside which the camera does not move; outside it, a P-controller with velocity and acceleration limits (critically damped spring); a lead of 0.3–0.5 s along the ball's velocity vector.
4. Offline mode (post-processing a recording): a two-sided Savitzky-Golay filter or RTS smoother removes lag entirely. This is a strong argument for processing the recording after the match first, rather than live.

### Gaps
- I found no 2024–2026 papers specifically on a virtual camera for amateur football with quantitative metrics; the closest are the 2020 basketball papers and Disney Research.

## 6. On-device performance (iPhone, Android, Mac M1)

### Takeaway
A nano detector at 640 px runs in about 3–11 ms on current flagships' NPUs (burst). A sustained pipeline with camera capture is about 11 ms on iPhone 17 Pro. So 30 fps at one 640 inference per frame is realistic even on an iPhone 15 (A16) or 15 Pro (A17 Pro). Full 4K tiling (6–24 tiles) in real time is not. The 4K frame needs downscaling plus one or two ROI tiles. Encoding 4K and cropping 1080p in real time is a separate load (hardware encoder, thermals).

### Cited Findings
- **iPhone 17 Pro, YOLO26n INT8, CoreML `.cpuAndNeuralEngine`:** detection at 640 takes 3.2 ms (burst average over 15 runs); CPU-only 9.2 ms. A "historical camera measurement" on the same device gave **11.3 ms/frame** for detection in a live camera pipeline. The docs warn that sustained real time is slower because of capture, scaling and thermal throttling. CoreML export options: `quantize=16/8/"w8a16"`, `nms=True` (built-in NMS), `nms=False` (NMS-free head), `imgsz=640`. — [Ultralytics CoreML docs](https://docs.ultralytics.com/es/integrations/coreml)
- **Android, Snapdragon 8 Elite Gen 5 (Xiaomi 17), QNN W8A16 on Hexagon HTP v81:** YOLO26n detect at 640 takes 10.7 ms (about 93 FPS burst). Supported HTP targets: v68 (SD 888), v69 (8 Gen 1), v73 (8 Gen 2), v75 (8 Gen 3), v79 (8 Elite), v81. LiteRT (formerly TFLite) is the CPU/GPU baseline; TFLite export is marked deprecated in favour of LiteRT. — [Ultralytics QNN docs](https://docs.ultralytics.com/es/integrations/qnn)
- **Android SD 8 Gen 2 (Galaxy Tab S9), LiteRT:** NPU INT8 gave the largest speedup (YOLO11n 32× over single-threaded CPU FP32). But INT8 cost YOLO about 6.5–7.2 mAP points (YOLO11n −6.6). YOLO11s FP16 on GPU was named a strong Pareto choice. Dynamic quantisation did not run on the NPU. — [arXiv 2511.13453](https://arxiv.org/html/2511.13453v1)
- Ultralytics has an article on running YOLO11 on Apple devices via CoreML. — [Ultralytics blog](https://www.ultralytics.com/blog/bringing-ultralytics-yolo11-to-apple-devices-via-coreml)
- Photoroom's CoreML benchmark on iPhone 15 (2023) compares compute units (ANE/GPU/CPU). — [Photoroom](https://photoRoom.com/inside-photoroom/core-ml-performance-benchmark-2023-edition)
- **Mac M1:** Ultralytics supports `device='mps'` (maintainer recommendation for M1/M2). — [ultralytics issue 13033](https://github.com/ultralytics/ultralytics/issues/13033). roboflow/sports examples run with `--device mps`. — [README](https://github.com/roboflow/sports/tree/main/examples/soccer)

### Inferences
- iPhone 15 (A16) and 15 Pro (A17 Pro) have older ANEs than the iPhone 17 Pro's; expect roughly 1.5–2× higher latency (an estimate, unconfirmed). A budget of 33 ms/frame still allows about 2 nano inferences at 640 (full frame downscaled + ROI tile around the ball) plus Kalman filtering and cropping.
- An INT8 small-object detector may lose recall; for the ball, FP16 or w8a16 is the safer choice.
- On a MacBook Air with 8 GB, PoC inference via MPS or CoreML is fine (offline on a recording, not necessarily real time). Training is better done in Colab/Kaggle, because 8 GB of unified memory limits batch size and image size (1280).
- 4K at 30 fps capture on the phone, plus parallel NPU inference, plus 1080p encoding is a thermal risk for long matches (90 minutes). An alternative is to record 4K and render the crop afterwards (offline), as many commercial solutions do.

### Gaps
- No direct published measurements for YOLO26n/YOLO11n on an iPhone 15 (A16/A17 Pro) or on a MacBook Air M1 (MPS/CoreML FPS).
- No data on sustained performance or thermal throttling during a 90-minute 4K recording with simultaneous inference.
- RF-DETR: the README lists no CoreML/TFLite export; the 2025 blog listed CoreML as "community-requested". The current state of RF-DETR mobile export needs checking.

## 7. Free training options

### Takeaway
Kaggle Notebooks (T4/P100, about 30 h/week, 12 h sessions) is the most predictable free option. Google Colab free (usually a T4, up to 12 h, unpredictable limits) works for short runs. roboflow/sports has ready-made Colab notebooks for training a ball detector.

### Cited Findings
- **Google Colab free:** GPU type not guaranteed (users report a T4), sessions "at most 12 hours", no published weekly quota, idle timeouts. — [GPUPerHour, Sept 2026](https://gpuperhour.com/blog/free-cloud-gpus-and-credits)
- **Kaggle:** T4/P100, 12 h per GPU session, weekly quota floats (users usually report about 30 h/week). Linking Colab Pro/Pro+ adds 15/30 h. — [GPUPerHour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits)
- **Lightning AI free:** one Studio, 4-hour restarts, 50 GB storage. **Modal Starter:** $30/month free compute. SageMaker Studio Lab is closed to new users. — [GPUPerHour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits)
- Colab notebook for training a ball detector: [train_ball_detector.ipynb](https://colab.research.google.com/github/roboflow/sports/blob/main/examples/soccer/notebooks/train_ball_detector.ipynb)

### Inferences
- A nano/small detector on 1–5k images at imgsz 1280 fits within a few Kaggle sessions on a T4. Save checkpoints to Kaggle Datasets or Google Drive between sessions.

### Gaps
- Official current Kaggle quotas are visible only in account settings and were not confirmed from a primary source.
