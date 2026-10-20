# Public football datasets from a static wide / panoramic camera (for Follo test footage)

Scope: datasets whose video comes from a fixed camera that sees the whole pitch (or most of it), with ball and/or player annotations. Broadcast-only (moving TV camera) datasets are listed only so they can be excluded or downranked. Research date: 2026-10-21. "UNVERIFIED" marks items not confirmed from a primary source.

## 1. SoccerTrack v1 and v2: what they contain, and are our 4096×1080 clips from v2?

### Takeaway
Yes. Our three test clips are almost certainly the SoccerTrack v2 MOT-subset clips: the Hugging Face repo holds `mot/clips/118575.mp4`, `132831.mp4` and `132877.mp4`, the exact file names in `~/Downloads`. They are also 4-minute, 25 fps panoramas about 4K wide. SoccerTrack v2 is CC BY 4.0, which allows commercial use. Beyond our 12 minutes it has 20 full halves (about 15.5 h) of the same viewpoint. SoccerTrack v1 is a different and much smaller set: 8K fisheye plus drone video, 30 s clips, and a Kaggle licence field of LGPL-3.0.

### Cited Findings
**SoccerTrack v2**
- Hugging Face `atomscott/soccertrack-v2`, dataset card licence `cc-by-4.0`. It is "Ten university-level soccer matches (934 minutes) recorded by fixed panoramic camera systems whose field of view spans the entire pitch". — [HF dataset card / README](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Folders. `videos/` holds 20 panoramic half-match videos. `gsr/` holds per-frame game state: pitch coordinates, jersey numbers, persistent IDs, roles, team sides. `bas/` holds 12-class ball action events with actor IDs and the exact video `frame`. `ball/` holds one ball track per half. `mot/` holds the "Curated bounding-box subset used for the SoccerTrack Challenge at MMSports 2025: per-match ground-truth files and the paired 4-minute clips". `raw/` holds calibration (65 hand-annotated pitch keypoints per match, distortion maps `mapx/mapy`, intrinsics, homography) and the provider's raw tracking and event exports. — [HF README](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- File list from the HF API (repo last modified 2026-09-24, 197 files):
  - `mot/clips/{117092,117093,118575,118576,118577,118578,128057,128058,132831,132877}.mp4` with matching `mot/{id}.txt`.
  - `videos/{id}/{id}_panorama_1st_half.mp4` and `_2nd_half.mp4`.
  - `ball/{id}_1st_ball.npz`, `bas/{id}/{id}_12_class_events.json`.
  - — [HF API](https://huggingface.co/api/datasets/atomscott/soccertrack-v2)
  - The local files `~/Downloads/118575.mp4`, `132831.mp4` and `132877.mp4`, and `specs/datasets.md` (4096×1080 / 4096×1084, 25 fps, 4:00), match these IDs (checked locally).
- Ball track caveat, quoted from the card: "It is a reconstruction rather than a per-frame measurement: it is anchored at the annotated events and interpolated in straight constant-speed lines between anchors". Positions are clamped to the pitch rectangle in matches 132831 and 132877. — [HF README](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Version and split. Release v1.2: "every annotation lines up with the released video frame for frame". 21,428 ball action events. Match 132877 (M10) was resynchronised; it had been about 1 s out of step. Benchmark split: test M7 (128057) + M9 (132831), validation M2 (117093) + M10 (132877), train the rest. — [HF README](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Our clip 132831 is a test-split match and 132877 a validation match in the official split. 118575 (M3) is train. — [HF README](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Access: gated. You must log in and accept the conditions (HF API `gated: "auto"`, i.e. automatic approval). Sub-files such as `mot/README.md` return "Access ... is restricted" without login. — [HF page](https://huggingface.co/datasets/atomscott/soccertrack-v2); [HF API](https://huggingface.co/api/datasets/atomscott/soccertrack-v2)
- Licence in the GitHub repo: code is MIT (`LICENSE`); data (videos plus GSR/BAS/MOT annotations) is CC BY 4.0 (`LICENSE-DATA`). The repo says both permit commercial use. Distributed via Hugging Face and Google Drive. — [GitHub AtomScott/SoccerTrack-v2](https://github.com/AtomScott/SoccerTrack-v2)
- Authors: Atom Scott and Keisuke Fujii (Nagoya University), Ikuma Uchida, Kento Kuroda and Yufi Kim (University of Tsukuba). Capture: "fixed, stitched panoramic camera systems from BePro"; 25 fps; width about 4K (3840 or 4096 px), height 1080 to 1906 px; 932 min; about 1.4 M annotated frames; 30.7 M player-frame records. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)
- Two matches were recorded with a BePro Cerberus system; the other eight used "BePro's standard 3-camera panoramic stitching system". The paper version is v2, dated 5 Oct 2026, titled "A Full-Pitch Panoramic Video Dataset for Game State Reconstruction and Ball Action Spotting" (v1, Aug 2025, said "Multi-View"). — [arXiv abs 2508.01802](https://arxiv.org/abs/2508.01802) (via search-result snippet)
- Conditions: venues, weather and lighting vary, "including night fixtures under floodlights". Pitch modelled as 105×68 m. Match M1 has a misaligned central stitch seam (homography residual 34.5 px versus 2.9 to 6.9 px for the others). Event labels come from BePro event data, hand-mapped to 12 classes and checked against video; the "Out" class is synthesised. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)
- MOT subset: one 4-minute clip per match, all 22 players boxed, 59,842 frames and 1,316,524 boxes. This is the SoccerTrack Challenge 2025 set. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)
- The 12 BAS classes are Pass, Drive, Header, High Pass, Out, Cross, Throw In, Shot, Ball Player Block, Player Successful Tackle, Free Kick and **Goal**. — [GitHub AtomScott/SoccerTrack-v2](https://github.com/AtomScott/SoccerTrack-v2)

**SoccerTrack v1 (CVPRW 2022)**
- Kaggle `atomscott/soccertrack`, about 6.8 GB, licence field "GNU Lesser General Public License 3.0", last updated 2023-02-10.
  - Wide-view camera: Z CAM E2-F8, 8K (7,680×4,320), 30 fps. Top-view: DJI Mavic 3 drone, 4K, 30 fps. GNSS: STATSPORTS APEX at 10 Hz.
  - The table ticks "Ball tracking" for both wide and top view. All games are 11-vs-11 between college-aged athletes (Tsukuba). Annotation is semi-automatic from the GNSS coordinates.
  - — [Kaggle API metadata](https://www.kaggle.com/api/v1/datasets/view/atomscott/soccertrack); [Kaggle page](https://www.kaggle.com/datasets/atomscott/soccertrack)
- The SoccerTrack v2 paper summarises v1 as "Full-pitch fish-eye/drone, 30 s clips ... 63 min of clips", with no events. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)
- Authors: Scott, Uchida, Onishi, Kameda, Fukui and Fujii, CVPR Workshops (CVSports) 2022. — [CVF open access](https://openaccess.thecvf.com/content/CVPR2022W/CVSports/html/Scott_SoccerTrack_A_Dataset_and_Tracking_Algorithm_for_Soccer_With_Fish-Eye_CVPRW_2022_paper.html)
- The GitHub repo `AtomScott/SoccerTrack` now hosts the SportsLabKit software under GPL-3.0, not the dataset. — [GitHub AtomScott/SoccerTrack](https://github.com/AtomScott/SoccerTrack)

### Inferences
- SoccerTrack v2 full halves are the cheapest source of "more footage, same viewpoint": 20 halves × 45 min against the 12 min we use now. All are CC BY 4.0, from the same provider as our clips, with known lighting variety (including floodlit night games). The catch is that they are all university pitches filmed by BePro rigs, so stadium diversity is limited.
- Goal and Shot events in `bas/` carry exact video frames. They can generate automatic goal/shot checklists for `src/check_goals.py` on all 20 halves, which fits the owner's rule that nobody marks anything by hand.
- The `ball/` track is interpolated between events, so it is not a valid per-frame "ball found" ground truth. It is usable only near event frames.
- The `mot/` subset has player boxes only; the paper says "all 22 players boxed". Whether the ball is boxed in `mot/*.txt` was not checked (UNVERIFIED; the file is gated).
- SoccerTrack v1's 8K fisheye side view is optically closer to an iPhone 0.5× ultra-wide at the halfway line than v2's stitched 3-camera panorama. Its total is only about an hour, and the LGPL-3.0 tag is an unusual data licence; take it literally only after reading the Kaggle licence tab.

### Gaps
- No public source gives the BePro camera mount height or exact position (paper: "Not stated").
- The exact resolution of each half video (3840 vs 4096 wide, height up to 1906) is not given per match.
- Whether `mot/*.txt` includes a ball class (gated file, not read).
- SoccerTrack v1 clip count and whether ball tracking covers every frame, beyond the Kaggle table tick.

## 2. Catalogue of the other named datasets (camera, size, annotations, access, licence)

### Takeaway
Besides SoccerTrack v1/v2, only Alfheim, ISSIA-CNR, TeamTrack and Spiideo SynLoc use fixed full-pitch or half-pitch cameras.
- Alfheim: non-commercial research only.
- ISSIA: licence UNVERIFIED.
- TeamTrack: Kaggle field MIT.
- Spiideo SynLoc: still images with synthetic players.

All SoccerNet variants, SportsMOT, SoccerDB, SSET, FOOTPASS, WorldPose and SoccerNet-GAR are broadcast and should be excluded. The SoccerNet video sets also sit behind a research/non-commercial NDA. Metrica and the DFL/Bassek open data have no video. The DFL Kaggle Shootout has video of uncertain camera type with unverified terms.

### Cited Findings
**Fixed-camera datasets**
- **TeamTrack** (Nagoya University, Atom Scott et al., CVPRW 2024).
  - Video: soccer fisheye side view (Z CAM E2-F8, 8K, 30 min, 1,242,000 boxes) and soccer drone top view (DJI Mavic 3, 4K, 30 min), filmed at "University A, outdoor". It also has basketball and handball; 155.5 min and 4,374,900 boxes in total.
  - Ball annotation is not mentioned. fps is not stated on the project page.
  - Download: Kaggle `atomscott/teamtrack` (17.7 GB, Kaggle licence field "MIT") and Google Drive. The website itself is CC BY-SA 4.0.
  - — [TeamTrack project page](https://atomscott.github.io/TeamTrack/); [Kaggle API metadata](https://www.kaggle.com/api/v1/datasets/view/atomscott/teamtrack); [arXiv 2404.13868](https://arxiv.org/abs/2404.13868v1)
- **Alfheim** (Simula / University of Tromsø / University of Oslo, Pettersen, Halvorsen et al., ACM MMSys 2014; the "Bagadus" project).
  - Pro level: Tromsø IL home games at Alfheim Stadium, Norway. Video "is captured from the middle of the field using two camera arrays"; "each camera can be used individually or as a stitched panorama video".
  - Camera setting 1: 2 full games (2013-11-03 vs Strømsgodset, 2013-11-07 vs Anzhi) with 3 single cameras plus a stitched panorama.
  - Camera setting 2: about 40 min of 2013-11-28 vs Tottenham Hotspur with "the five 2K-camera array". This game includes a small manually extracted ball-position set (pixel x, y per frame for 75-frame, 3-second segments).
  - Player positions from the ZXY radio system at 20 Hz. 4 mm lenses with barrel distortion. Total "slightly above 100 GB". Open HTTP download.
  - Licence text: "The data may only be used for non-commercial research purposes"; re-identifying players or building performance profiles is not allowed.
  - — [Simula datasets: Alfheim](https://datasets.simula.no/alfheim/); [download index](https://datasets.simula.no/downloads/alfheim/2013-11-28)
- **ISSIA-CNR Soccer** (D'Orazio et al., AVSS 2009).
  - Six synchronised static 25 fps cameras on both sides of the field, about 18,000 frames (about 2 min per camera); ball annotated as a centre point per frame (semi-automatic).
  - — [SoccerNet-v3D paper](https://arxiv.org/pdf/2504.10106); [FootAndBall paper](https://arxiv.org/pdf/1912.05445)
  - ISSIA-3D (2025) adds calibration and 10,544 images with 3D ball positions; code at github.com/mguti97/SoccerNet-v3D. — [SoccerNet-v3D (CVPRW 2025)](https://arxiv.org/html/2504.10106v1)
  - Official download page and licence: UNVERIFIED (not found).
- **Spiideo SoccerNet SynLoc** (Spiideo + SoccerNet, VISAPP 2025).
  - Synthetic athletes rendered onto images from real fixed pitch-covering camera installations; a "static camera covering half a pitch" with calibration.
  - Images in 4K (plus a Full HD version), COCO boxes plus metric `position_on_pitch`; person class only, no ball.
  - Download: register at research.spiideo.com, or use the SoccerNet pip downloader (`task="SpiideoSynLoc"`).
  - Licence: UNVERIFIED (not stated in the README).
  - — [sskit GitHub](https://github.com/Spiideo/sskit); [VISAPP paper](https://www.scitepress.org/Papers/2025/131082); [SoccerNet 2026 results](https://arxiv.org/html/2607.07320v1)

**Broadcast datasets (exclude or downrank)**
- **SoccerNet (all video sets)**.
  - Broadcast only: "500 + 50 broadcast videos", 25 fps, 720p or 224p. Gated video needs an HF account plus the SoccerNet NDA. — [soccer-net.org/data](https://www.soccer-net.org/data)
  - The HF gate (SoccerNet_raw_HQ, SN-BAS-2025, SoccerNet-Tracking-RAW-Video) has licence "other" (linked NDA) and requires ticking "the use of this dataset is for research and non-commercial use only", "protected by copyright", and "not to share the dataset". — [HF SoccerNet_raw_HQ](https://huggingface.co/datasets/SoccerNet/SoccerNet_raw_HQ); [HF SN-BAS-2025](https://huggingface.co/datasets/SoccerNet/SN-BAS-2025)
  - SoccerNet-Tracking: 200 broadcast clips of 30 s with player, referee and ball boxes. SoccerNet-GSR adds pitch positions for athletes, not the ball. — [SoccerNet-GSR arXiv 2404.11335](https://arxiv.org/pdf/2404.11335)
  - The HF card of SN-GSR-2025 says `gpl-3.0`, not gated. — [HF SN-GSR-2025](https://huggingface.co/datasets/SoccerNet/SN-GSR-2025)
  - The 2026 challenges: Ball Action Anticipation and FOOTPASS PCBAS (broadcast); Novel View Synthesis (synthetic from broadcast); VQA (broadcast); Spiideo SynLoc (the only fixed-camera task). — [SoccerNet 2026 Challenges Results](https://arxiv.org/html/2607.07320v1)
- **SportsMOT** (Nanjing University, ICCV 2023): 240 broadcast clips (basketball, volleyball, football), 150K frames, 1.6M boxes, sourced from MultiSports. HF card licence CC BY-NC 4.0, gated with a non-commercial agreement. — [arXiv 2304.05170](https://arxiv.org/pdf/2304.05170); [HF card](https://huggingface.co/datasets/MCG-NJU/SportsMOT/blob/1b0b418ea611a8e934f1e773313e719e4fa1265e/README.md?code=true)
- **SoccerDB**: 343 matches, 171,191 segments, partly from SoccerNet (broadcast); licence "other". — [Action-recognition survey](https://arxiv.org/pdf/2206.01038); [HyperAI listing](https://vercel.hyper.ai/en/datasets/21125). Exact licence UNVERIFIED.
- **SSET**: 350 broadcast videos, 282 h, shot, event and player boxes; licence UNVERIFIED. — [Action-recognition survey](https://arxiv.org/pdf/2206.01038)
- **SoccerNet-GAR, FOOTPASS (NDA), WorldPose**: broadcast-based, per the SoccerTrack v2 comparison table. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)

**Datasets without (usable) video**
- **DFL - Bundesliga Data Shootout** (Kaggle, DFL + AWS + Sportec, 30 Jul to 13 Oct 2022, US$25,000).
  - Task: detect challenges and passes in Bundesliga video. — [bundesliga.com](https://bundesliga.com/en/aws-bundesliga-data-shootout)
  - Train set: 12 videos of 60 min; test set: 32 unlabeled 30 s videos. Labels: CSV of play / challenge / throw-in (3,586 / 624 / 172) plus start/end. A write-up says the test videos come from "one stationary camera". — [Habr write-up](https://habr.com/en/articles/848468)
  - Camera type, resolution and licence/rules: UNVERIFIED (the Kaggle data and rules tabs could not be read without login).
  - A public HF mirror of clips exists: [ManuD/DFL_video_classification](https://huggingface.co/datasets/ManuD/DFL_video_classification). Its licence is unknown; do not rely on it.
- **DFL / Sportec open data** (Bassek et al., German Sport University Cologne, Scientific Data): 7 matches of 2022/23 (2 Bundesliga, 5 2. Bundesliga) with player and ball positions plus events. No video ("Withheld" in the SoccerTrack v2 table). — [DSHS Köln news](https://www.dshs-koeln.de/en/institut-fuer-trainingswissenschaft-und-sportinformatik/detail/meldung/official-game-data-in-the-journal-scientific-data); [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)
  - No 2024–2025 open DFL release with video was found. Since 2025/26 the DFL has used 3D tracking (ball at 50 Hz), but only commercially. — [SVG Europe](https://www.svgeurope.org/blog/headlines/sportsinnovation-2026-inside-the-bundesligas-new-3d-tracking-system-and-how-it-could-be-used-for-broadcast-analysis/)
- **Metrica Sports sample data**: 3 anonymised games of tracking and events (games 1–2 CSV; game 3 in the EPTS FIFA format); no video. Terms are informal: "be responsible" and acknowledge the source. — [GitHub metrica-sports/sample-data](https://github.com/metrica-sports/sample-data)

**Futsal / small-sided**
- Only Roboflow image projects turned up, for example "futsal-annotations" (CC BY 4.0, players, ball, referees). Camera setup is unknown and they are images, not continuous video. — [Roboflow futsal-annotations](https://universe.roboflow.com/cvfutsal/futsal-annotations); [Roboflow futsal player/ball](https://universe.roboflow.com/masters-program/futsal-player-and-ball-detection-ch025/dataset/)

### Inferences
- For a product model, only SoccerTrack v2 (CC BY 4.0) and maybe TeamTrack (MIT on Kaggle) are licence-clean among the fixed-camera sets.
- Alfheim and SoccerNet are non-commercial. They are fine for internal evaluation only, and even that should be checked against the owner's rule of no third-party material in the product.
- Alfheim is the only fixed panorama at professional level with a different stadium, country, season (Norwegian November) and camera rig. That makes it the best "never seen" cross-domain test for the virtual camera, internal use only.

### Gaps
- ISSIA-CNR original download URL and licence: no primary source found.
- Spiideo SynLoc licence and research.spiideo.com terms: not read.
- DFL Shootout camera type and Kaggle rules: Kaggle pages need login. Treat the terms as competition-only until verified.
- Alfheim panorama resolution and fps: not stated on the dataset page.
- SoccerNet NDA full text: on Google Drive, not opened. The gate checkboxes quoted above are the primary evidence.

## 3. Which datasets match "phone at halfway line" and how many hours?

### Takeaway
Ranked by similarity to Follo's viewpoint (static, side or elevated, whole pitch):
1. SoccerTrack v2 panoramas: about 15.5 h, CC BY 4.0.
2. Alfheim stitched panoramas from midfield: about 3.7 h over 3 pro games, non-commercial.
3. SoccerTrack v1 and TeamTrack 8K fisheye side views: about 1 h and 0.5 h of soccer, closest optically to an ultra-wide lens.
4. ISSIA-CNR: six static cameras, each seeing part of the pitch, about 2 min.
5. Spiideo SynLoc: half-pitch static camera, still images only.

No public 7-a-side, futsal or grassroots video set from a single fixed wide camera was found.

### Cited Findings
- SoccerTrack v2: 932 min of "fixed-camera footage", full matches, the whole pitch in view. — [arXiv 2508.01802](https://arxiv.org/abs/2508.01802)
- Alfheim: about 220 min over 3 matches, "Full-pitch panorama" (per the SoccerTrack v2 table). Cameras are at the middle of the field. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802); [Simula Alfheim](https://datasets.simula.no/alfheim/)
- SoccerTrack v1: 63 min of 30 s clips, 8K fisheye "wide-view" side camera. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802); [Kaggle metadata](https://www.kaggle.com/api/v1/datasets/view/atomscott/soccertrack)
- TeamTrack soccer: 30 min fisheye (side) plus 30 min drone (top). — [TeamTrack page](https://atomscott.github.io/TeamTrack/)
- ISSIA: 6 static cameras, about 18,000 frames. — [SoccerNet-v3D](https://arxiv.org/pdf/2504.10106)
- Spiideo SynLoc: static 4K camera covering half a pitch, images only. — [SoccerNet 2026 results](https://arxiv.org/html/2607.07320v1)
- A Hugging Face search ("soccer", "football", "futsal", "panoram") lists no other fixed-wide football video dataset among the results. The top hits are SoccerNet broadcast sets, SoccerTrack v2, Roboflow-style image sets and synthetic sets such as FootballCameraSynth (CC BY-NC-SA 4.0, simulator images). — [HF datasets search API](https://huggingface.co/api/datasets?search=soccer&limit=60&sort=downloads); [HF FootballCameraSynth](https://huggingface.co/datasets/JediVova/FootballCameraSynth)

### Inferences
- Realistic "different" footage of the same type is roughly 15.5 h (SoccerTrack v2, licence-clean) plus about 3.7 h of Alfheim (pro level, non-commercial), plus about 1.5 h of fisheye side view (SoccerTrack v1 and TeamTrack).
- Everything else public is broadcast. Amateur grass pitches with a single phone-like camera, mixed weather and small-sided games will have to come from the owner's own recordings.

### Gaps
- Camera heights: not published for any of these sets.
- An hour total for SoccerTrack v1 wide view alone (the 63 min may include top-view clips).

## 4. Which datasets have per-frame ball annotations usable for "ball found" and goal/shot checklists?

### Takeaway
No large fixed-camera dataset has true per-frame ball ground truth.
- SoccerTrack v2's ball track is interpolated between events. Its Shot and Goal events with exact frames, however, give automatic shot/goal checklists across 20 halves.
- True per-frame ball points from fixed cameras exist only in small sets: ISSIA-CNR (point per frame, 6 cameras, about 2 min), Alfheim (small manual set, Tottenham game), and SoccerTrack v1 wide view (ball tracking ticked).

### Cited Findings
- SoccerTrack v2 `ball/`: "a reconstruction rather than a per-frame measurement ... interpolated in straight constant-speed lines between anchors". `bas/` events carry `frame` and millisecond `position`; the classes include Shot and Goal. — [HF README](https://huggingface.co/datasets/atomscott/soccertrack-v2); [GitHub](https://github.com/AtomScott/SoccerTrack-v2)
- Alfheim: "a small dataset (manually extracted) of the ball position", lines like `1 1890 660`, i.e. frame 1 ball at pixel (1890, 660), per 75-frame segment. — [Simula Alfheim](https://datasets.simula.no/alfheim/)
- ISSIA: ball "as a single point indicating the ball center in image coordinates". ISSIA-3D adds bounding boxes and 3D positions for 10,544 images. — [SoccerNet-v3D](https://arxiv.org/pdf/2504.10106)
- SoccerTrack v1: Kaggle table ticks "Ball tracking" for the wide-view camera. — [Kaggle metadata](https://www.kaggle.com/api/v1/datasets/view/atomscott/soccertrack)
- SoccerNet-Tracking has ball boxes per frame, but only in broadcast clips. — [SoccerNet-GSR arXiv](https://arxiv.org/pdf/2404.11335)
- The DFL/Bassek data has ball positions at 25 Hz but no video. — [arXiv 2508.01802 (HTML)](https://arxiv.org/html/2508.01802)

### Inferences
- **"Ball found" metric**: measure it on ISSIA (if obtainable) and the Alfheim ball subset, and spot-check on SoccerTrack v1 wide view.
- **Goal/shot checklists**: SoccerTrack v2 BAS `Shot` and `Goal` frames turned into a checklist file per half would multiply the current checklist coverage with no hand marking.
- **Ball truth near events**: SoccerTrack v2 `ball/` positions at event anchors are reliable to within a frame or two; between events they are not.

### Gaps
- Exact count and coverage of Alfheim ball labels (how many 3 s segments).
- Whether SoccerTrack v1 ball tracking covers all frames and whether it is a box or a point.

## 5. New datasets 2024–2026

### Takeaway
The only substantial new public fixed-camera football video dataset of 2024–2026 is SoccerTrack v2 (Aug 2025, v1.2 data and v2 paper by Oct 2026). Other new releases are broadcast (FOOTPASS, SoccerNet-GAR, SN-BAA/PCBAS 2026, SoccerReplay-1988, SoccerHigh, SoccerChat), synthetic (Spiideo SynLoc 2025, FootballCameraSynth, SoccerNet NVS 2026), or multi-sport fixed-camera (TeamTrack 2024).

### Cited Findings
- SoccerTrack v2: paper v1 on 3 Aug 2025, revised (v2) on 5 Oct 2026; data release v1.2 on HF, last modified 2026-09-24. — [arXiv 2508.01802](https://arxiv.org/abs/2508.01802); [HF API](https://huggingface.co/api/datasets/atomscott/soccertrack-v2)
- TeamTrack: CVPRW 2024. — [CVF](https://openaccess.thecvf.com/content/CVPR2024W/CVsports/html/Scott_TeamTrack_A_Dataset_for_Multi-Sport_Multi-Object_Tracking_in_Full-pitch_Videos_CVPRW_2024_paper.html)
- Spiideo SoccerNet SynLoc: VISAPP 2025; used as a SoccerNet 2026 challenge task. — [SciTePress](https://www.scitepress.org/Papers/2025/131082); [SoccerNet 2026 results](https://arxiv.org/html/2607.07320v1)
- SoccerNet 2026 tasks other than SynLoc are broadcast or synthetic. — [SoccerNet 2026 results](https://arxiv.org/html/2607.07320v1)
- Recent HF football video sets and their licences:
  - SoccerReplay-1988: CC BY-NC-SA 4.0.
  - imva-upf/SoccerHigh: CC BY-NC-SA 4.0.
  - SimulaMet/SoccerChat: "other".
  - SoccerNet/SN-PCBAS-2026: "other".
  - All are broadcast-derived by their descriptions. — [HF datasets search API](https://huggingface.co/api/datasets?search=soccer&limit=60&sort=downloads)
- An April 2026 arXiv paper analyses 10 home games of the MSOE men's team (2024 season), but no dataset release was seen. — [arXiv 2604.08722](https://arxiv.org/html/2604.08722v1)
- A GitHub project, "futtraffic", describes per-player data for grassroots football "from one fixed panoramic camera". It appears to be a tool, not a dataset (UNVERIFIED). — [GitHub danrublop/futtraffic](https://github.com/danrublop/futtraffic)

### Inferences
- The public data landscape has not caught up with Follo's viewpoint (single phone, amateur pitch). SoccerTrack v2 is the ceiling of what is openly available.
- The owner's own matches will be the main source of diverse test footage from now on. A self-labelling loop, with our model labelling and our tracker filtering, is the only scalable way to get ball ground truth for that viewpoint.

### Gaps
- No dedicated search of Zenodo, Papers with Code or Kaggle for 2026 grassroots datasets beyond the HF API and web search. A smaller Zenodo or university release could have been missed.
- No public futsal or 7-a-side fixed-camera video dataset was found. This is a negative result from limited searches, not proof that none exists.
- Veo, Pixellot, Spiideo and Trace sample footage: no open-licence sample datasets were found.
