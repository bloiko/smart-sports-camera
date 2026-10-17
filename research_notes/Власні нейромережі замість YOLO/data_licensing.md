# Data sources and licensing for a fully own football player/ball detector (commercial iPhone app)

Research date: 2026-10-17. Not legal advice. Each item marks where a lawyer's opinion is needed. Two sites could not be fetched directly in this session: gnu.org (connection refused) and the Kaggle dataset pages (JavaScript only). Any quote from those sources is marked as secondary.

## 1. Which public football datasets may be used to train a commercial model, and on what conditions?

### Takeaway
SoccerTrack v2 is the only football dataset found whose licence for data and annotations is confirmed open for commercial use: CC BY 4.0, with the explicit line "Both permit commercial use". It contains 10 full matches in panoramic 4K, a bounding-box subset, and per-frame pitch positions for every player. Its ball track is interpolated, not measured. SoccerNet video is behind an NDA and secondary sources describe it as research-only. SportsMOT is CC BY-NC 4.0 at the official source. For SoccerTrack v1, TeamTrack and ISSIA-CNR no licence could be confirmed. Roboflow Universe licences are set by each uploader and often sit on top of broadcast frames the uploader does not own.

### Cited Findings
**SoccerTrack v2 (Scott, Uchida, Kuroda, Kim, Fujii; arXiv 2508.01802, Aug 2025)**
- The licence is split. Code (scripts, loaders, baselines) is MIT. The dataset, "videos + GSR / BAS / MOT annotations, distributed via Hugging Face and Google Drive", is CC BY 4.0 (file `LICENSE-DATA`). The README states: "Both permit commercial use." — [GitHub AtomScott/SoccerTrack-v2](https://github.com/AtomScott/SoccerTrack-v2)
- The README asks users to "Please cite the paper if you use the dataset in research" (Scott et al., 2025, arXiv:2508.01802). A journal version for Pattern Analysis and Applications is in preparation. — [GitHub README](https://github.com/AtomScott/SoccerTrack-v2)
- The Hugging Face card lists the licence as `cc-by-4.0` and says "The release is pseudonymised: players are identified by jersey numbers and integer identifiers, and no personal names are included." — [HF atomscott/soccertrack-v2](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Access is gated: "You need to agree to share your contact information to access this dataset." Total size is 145 GB. — [HF card](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- Contents:
  - `videos/`: 20 panoramic half-match videos.
  - `gsr/`: JSON per half with pitch coordinates, jersey numbers, persistent IDs, roles and team sides.
  - `bas/`: 21,428 ball-action events in 12 classes.
  - `ball/`: an "auxiliary ball track", described as a reconstruction interpolated between event anchors, not a per-frame measurement.
  - `mot/`: a curated bounding-box subset for the SoccerTrack Challenge 2025, with per-match ground truth and paired 4-minute clips.
  - `raw/`: calibration with 65 hand-annotated pitch keypoints per match, distortion maps, intrinsics, and raw provider tracking and event exports.
  - Source: [HF card](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- The matches are "10 full-length panoramic 4K" recordings of university-level games, captured with BePro cameras. — [GitHub README](https://github.com/AtomScott/SoccerTrack-v2); [arXiv 2508.01802](https://arxiv.org/abs/2508.01802v1)
- The repo has a script that converts pitch coordinates into bounding boxes. — [GitHub README](https://github.com/AtomScott/SoccerTrack-v2)

**CC BY 4.0 (the licence itself)**
- It allows sharing and adapting "for any purpose, even commercially", on condition of attribution: credit the source, link the licence, and indicate changes. Section 2(b)(1) of the legal code states that publicity, privacy and similar personality rights are not licensed. — [CC BY 4.0 deed](https://creativecommons.org/licenses/by/4.0/); [legal code](https://creativecommons.org/licenses/by/4.0/legalcode). Quoted from the well-known text; these pages were not re-fetched in this session.

**SoccerNet (tracking, game-state reconstruction, ball action spotting, broadcast videos)**
- From the official data page: "Some datasets containing protected video content are gated and require a Hugging Face account and acceptance of the SoccerNet Non-Disclosure Agreement (NDA)."
  - Public datasets "can be downloaded directly".
  - Broadcast videos: 500 + 50 .mkv files, 25 fps, 720p or 224p.
  - The page gives no licence text and no commercial option. Licensing questions go to a contact form.
  - Source: [soccer-net.org/data](https://www.soccer-net.org/data)
- The SoccerNet devkit says that signing an NDA is required to access the LQ and HQ videos. — [SoccerNetv2-DevKit](https://github.com/SilvioGiancola/SoccerNetv2-DevKit); [SoccerNet on PyPI](https://www.pypi.org/project/SoccerNet/0.1.37/)
- Secondary source: a SoccerNet-derived dataset card says its video field is "for research/education purposes only (non-commercial)". It adds that the video "may not be redistributed, publicly hosted, reconstructed, or used for commercial purposes", and that derived annotations must not be used to "commercially exploit the original videos". — [SimulaMet/SoccerChat README](https://huggingface.co/datasets/SimulaMet/SoccerChat/blob/refs%2Fpr%2F2/README.md). This summarises the NDA second-hand; the official NDA text was not retrieved.

**SportsMOT (MCG-NJU, multi-sport including football)**
- The official Hugging Face card lists CC BY-NC 4.0 and gates access on agreeing to non-commercial use. Dataset Ninja also lists CC BY-NC 4.0. — [HF MCG-NJU/SportsMOT README](https://huggingface.co/datasets/MCG-NJU/SportsMOT/blob/1b0b418ea611a8e934f1e773313e719e4fa1265e/README.md?code=true); [Dataset Ninja](https://cdn.datasetninja.com/sports-mot)
- This conflicts with the Roboflow Universe and trackers.roboflow.com mirrors, which show CC BY 4.0. — [Roboflow Universe SportsMOT](https://universe.roboflow.com/cs330/sportsmot); [trackers.roboflow.com](https://trackers.roboflow.com/latest/learn/download/)

**SoccerTrack v1 (CVPRW 2022; fish-eye and drone videos)**
- Hosted on Kaggle (atomscott/soccertrack). The linked GitHub repo is now SportsLabKit, under GPL-3.0 for code. No dataset licence was visible. — [GitHub AtomScott/SoccerTrack](https://github.com/AtomScott/SoccerTrack); [CVPRW 2022 paper](https://openaccess.thecvf.com/content/CVPR2022W/CVSports/html/Scott_SoccerTrack_A_Dataset_and_Tracking_Algorithm_for_Soccer_With_Fish-Eye_CVPRW_2022_paper.html)

**TeamTrack (CVPRW 2024)**
- Full-pitch multi-sport MOT. The soccer part is about 60 min (30 min side-view fisheye, 30 min top-view drone). No licence was found in search results. — [CVPRW 2024](https://openaccess.thecvf.com/content/CVPR2024W/CVsports/html/Scott_TeamTrack_A_Dataset_for_Multi-Sport_Multi-Object_Tracking_in_Full-pitch_Videos_CVPRW_2024_paper.html); [alphaXiv benchmark page](https://www.alphaxiv.org/benchmarks/nagoya-university/teamtrack)

**ISSIA-CNR Soccer**
- About 18,000 high-resolution frames from 6 static cameras, with player boxes. No licence or terms page was found. — [survey arXiv 2307.03353](https://arxiv.org/pdf/2307.03353)

**Roboflow Universe football sets**
- Many sets list CC BY 4.0, for example OTRONTO "Object Detection Football-Player" and SCIArc "FootballPlayerDetection". The licence is chosen by each uploader. — [OTRONTO](https://universe.roboflow.com/otronto/object-detection-football-player); [SCIArc](https://universe.roboflow.com/sciarc/footballplayerdetection-hrz85)
- Popular football sets are built from DFL Bundesliga Data Shootout (Kaggle competition) footage. One project credits that competition as its data source. — [Football_Analytics_CV](https://github.com/NikhilC2209/Football_Analytics_CV)

### Inferences
- **SoccerTrack v2 is the legally cleanest real-football source.**
  - The authors recorded their own matches, so they plausibly hold rights to the video.
  - The licence explicitly permits commercial use.
  - The players are pseudonymised.
  - Conditions: keep attribution (credit in the app's About/Acknowledgements and in repo docs, link to CC BY 4.0, note "modified"), and accept the gate (share contact info).
  - Whether trained weights are "Adapted Material" under CC BY is unsettled. Crediting the dataset in the app is cheap insurance.
- **SoccerTrack v2 is technically good, but has caveats for our camera.**
  - 4K panoramic wide view is close to our static wide shot.
  - Player boxes are available directly (`mot/`) or derivable from pitch coordinates plus calibration.
  - The ball track is interpolated, so it is unreliable as per-frame ball-box ground truth. Ball labels need another source: own labels, own pseudo-labels, or synthetic data.
- **CC BY does not clear privacy.** Privacy and personality rights are excluded from the licence. Training on the data inside the developer's own pipeline and shipping only weights keeps exposure low. Never redistribute frames, for example in marketing material.
- **SoccerNet should be treated as off-limits for a commercial model.** Access is NDA-gated, it is broadcast footage owned by leagues and broadcasters, and secondary descriptions say research-only. Only a commercial agreement with SoccerNet or the rights holders would change this.
- **SportsMOT: the official source says non-commercial.** A mirror cannot relicense it. Do not use it.
- **Roboflow Universe "CC BY 4.0" on Bundesliga or TV frames is unreliable.** An uploader cannot license footage they do not own. Treat such sets as risky unless the uploader filmed the images.
- **SoccerTrack v1, TeamTrack and ISSIA: unknown licence means do not use.** That holds until the licence is confirmed on the Kaggle page or project page. Emailing Atom Scott, who is also the author of v2, is a cheap way to ask.

### Gaps
- The exact text of the SoccerNet NDA and any commercial-licence route (only a contact form was found).
- Licences for SoccerTrack v1 and TeamTrack on Kaggle (pages are JS-rendered and could not be read). ISSIA-CNR terms were not found.
- SoccerTrack v2 details not found:
  - frame rate;
  - exact pixel resolution (only "4K panoramic" is stated);
  - whether `mot/` includes ball boxes;
  - how many frames have boxes.
- The DFL Bundesliga Data Shootout competition rules (Kaggle) were not retrieved.
- Whether SportsMOT annotates the ball (unverified).

## 2. Does using AGPL-3.0 Ultralytics YOLO as a "teacher" (pseudo-labels / distillation) put the labels or the student model under the AGPL?

### Takeaway
The main legal rule is in GPLv3/AGPLv3 Section 2 and the FSF FAQ: output is covered only if it itself contains copyrightable parts of the program. An Ultralytics staff reply (Jan 2025) says auto-annotated labels "are not themselves subject to the AGPL-3.0 license". Ultralytics' licence page makes broad claims about "trained/fine-tuned models" and even "architectures", but it says nothing about a model trained with independent code on YOLO-produced labels. There is no case law. The low-risk path is: run YOLO only on the Mac, keep only box coordinates, train an independently written architecture with own code, and never ship or copy any Ultralytics code, weights or module designs.

### Cited Findings
- **GPLv3 and AGPLv3 Section 2:** "The output from running a covered work is covered by this License only if the output, given its content, constitutes a covered work." — [AGPL-3.0 text](https://www.gnu.org/licenses/agpl-3.0.html). Quoted from the standard licence text; gnu.org refused connections in this session, so it was not re-fetched.
- **The FSF quoting the GPL FAQ** (FSF blog, 25 Jan 2019): "The output of a program is not, in general, covered by the copyright on the code of the program..." The exception is "when the program displays a full screen of text and/or art that comes from the program." — [FSF Licensing & Compliance Lab blog](https://www.fsf.org/blogs/licensing/licensing-and-compliance-lab-the-most-frequently-asked-frequently-asked-questions). The original FAQ entry is "Is there some way that I can GPL the output people get from use of my program?" — [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq) (could not be fetched).
- **Ultralytics licence page** (undated; footer "© 2026 Ultralytics Inc."):
  - "If you use Ultralytics YOLO code, models, architectures, training pipelines, or trained/fine-tuned models, you must either" open-source under AGPL-3.0 or buy an Enterprise licence.
  - It says this applies even if you train from scratch or use YOLO only internally for R&D.
  - "All Ultralytics YOLO trained models fall under the AGPL-3.0 License by default."
  - "The AGPL-3.0 License covers the training code and the models produced by that training code."
  - Compliance means "publicly releasing the complete corresponding source code for the entire derivative work", including model weights "where applicable".
  - The page does not mention model outputs or predictions.
  - Source: [ultralytics.com/license](https://www.ultralytics.com/license)
- **Ultralytics community forum, "Auto_annotate and agpl"** (question 11 Jan 2025; reply by Ultralytics team member pderrenger, 12 Jan 2025): "Generated annotations using the `auto_annotate` feature are not themselves subject to the AGPL-3.0 license", "as they are considered outputs of the software rather than derived works". The reply adds that using or modifying the auto_annotate code itself requires AGPL compliance. It does not address models trained on those labels. — [community.ultralytics.com/t/auto-annotate-and-agpl/676](https://community.ultralytics.com/t/auto-annotate-and-agpl/676)
- **Ultralytics GitHub issue #2129:** Ultralytics states that a downstream solution including YOLOv8 training code or a trained model (pretrained or custom-trained) should be open-sourced. A commenter disputes this for from-scratch models trained on one's own data. — [ultralytics/ultralytics#2129](https://github.com/ultralytics/ultralytics/issues/2129)
- **Roboflow blog, 10 Mar 2026** (Roboflow is a commercial competitor, so possible bias):
  - It asks "Are model weights produced using AGPL-licensed training code themselves covered?" and says engineers and lawyers disagree and very little has been tested in court.
  - It does not discuss outputs or labels.
  - It explains AGPL §13: the network-use clause triggers "If users interact with your modified AGPL program remotely over a network."
  - "This article is general information, not legal advice."
  - Source: [Roboflow blog](https://roboflow.com/blog/why-agpl-3-0-is-a-risk-for-computer-vision-teams)
- **Law-firm explainer** (Dec 2025): no court has squarely held that "a trained model is a derivative of GPL code". — [terms.law](https://terms.law/2025/12/05/training-on-open-source-code-what-gpl-mit-and-other-licenses-actually-say-about-ai/)
- **inno3 (French open-source law consultancy):** proposes an "AI Model Component" exception to copyleft licences. Its argument is that obligations come from the licence contract while the copyright status of weights is still debated. — [inno3](https://inno3.fr/en/blog/an-ai-model-component-exception-for-open-source-licenses/)

### Inferences
- **Hard pseudo-labels (box coordinates and class of players and ball in our own frames)** are output whose content comes from the input video, not from YOLO's code or weights.
  - Under AGPL §2 and the FSF FAQ they are not a covered work.
  - Ultralytics' own staff agree for auto_annotate output.
  - This is the strongest position available short of a court ruling.
- **Soft-target distillation (training on YOLO logits or features)** is a grey zone.
  - The student imitates the teacher's internal function more closely.
  - Ultralytics' broad "models, architectures" wording plus the absence of case law make it riskier than hard labels.
  - Prefer hard boxes, possibly filtered or corrected by our own tracker and geometry.
- **The real AGPL risk lies elsewhere:**
  - copying Ultralytics code or modules (C2f, the detection head, loss implementations) into our trainer;
  - initialising the student from YOLO weights;
  - converting YOLO weights to Core ML and shipping them.
  - Our detector should be written from papers or from scratch, under our own licence, with no weights inherited from YOLO.
- **Keep a provenance record:** which videos were used, which teacher, the pseudo-label files, and the training code commit. If Ultralytics ever objects, this shows the shipped weights contain no Ultralytics material.
- **The cleaner long-term option:** bootstrap labels with tools that have no copyleft. Candidates are Apple system frameworks on the Mac or iPhone (for example Vision human detection), our own classical detection (background subtraction plus the tracker from `live_sim.py`), and SoccerTrack v2 ground truth. Then YOLO is only a dev-time comparison baseline.
- **A lawyer's opinion is needed** before a commercial launch if any YOLO-derived labels make up a large share of the training set. The lawyer would confirm (a) AGPL §2 applies to the labels, and (b) Ultralytics' website claims are not enforceable as contract terms against a user of the AGPL code. The AGPL itself does not restrict use of outputs, but if Ultralytics HUB or Platform was used, its Terms of Service might.

### Gaps
- There is no court decision anywhere on AGPL/GPL and model weights or pseudo-labels.
- There is no official Ultralytics statement on knowledge distillation or on models trained with non-Ultralytics code on YOLO labels.
- The terms of Ultralytics HUB/Platform (as opposed to the AGPL) were not reviewed.
- Apple's terms for using Vision framework outputs as training data were not checked.

## 3. ImageNet- and COCO-pretrained weights: what terms apply, and is training from scratch safer?

### Takeaway
The ImageNet terms of access limit the database to "non-commercial research and educational purposes" and bind for-profit employers. Torchvision explicitly warns that pre-trained weights "may have their own licenses or terms and conditions derived from the dataset used for training". COCO annotations are CC BY 4.0, but COCO images fall under Flickr terms. Whether such weights carry the dataset's restrictions is legally unsettled, so training from scratch or self-supervised pretraining on own or CC BY footage is the safer route for a commercial app.

### Cited Findings
- **ImageNet terms of access:**
  - Clause 1: "Researcher shall use the Database only for non-commercial research and educational purposes."
  - Clause 3: the researcher accepts responsibility, including for "copies of copyrighted images that he or she may create from the Database".
  - Clause 6: "If Researcher is employed by a for-profit, commercial entity, … Researcher's employer shall also be bound by these terms and conditions."
  - The terms do not mention trained models.
  - Source: [image-net.org/download.php](https://image-net.org/download.php)
- **Torchvision**, "General information on pre-trained weights": weights "may have their own licenses or terms and conditions derived from the dataset used for training … It is your responsibility to determine whether you have permission to use the models for your use case." Torchvision code is BSD-licensed, but this caveat applies to the weights. — [docs.pytorch.org/vision/stable/models.html](https://docs.pytorch.org/vision/stable/models.html)
- **Practice is inconsistent.**
  - In the Caffe model zoo, BVLC treated some ImageNet-trained models as non-commercial because of the data licence.
  - It released others unrestricted, arguing that no images are distributed in the weights.
  - Source: [microsoft/caffe mirror commit discussion](https://source-hub.etos-pro.ru/microsoft/caffe/commit/6b84206); community discussion [DrivenData forum](https://community.drivendata.org/t/is-it-allowed-to-train-using-imagenet-database/6389), [fast.ai forum](https://forums.fast.ai/t/rights-to-develop-commercial-products-using-open-dataset/18873)
- **COCO:** "The annotations in this dataset along with this website belong to the COCO Consortium and are licensed under a Creative Commons Attribution 4.0 License." The consortium does not own the image copyrights, and image use "must abide by the Flickr Terms of Use".
  - This is secondary: the cocodataset.org terms are JS-rendered, so they were confirmed via mirrors and papers.
  - Source: [aiwiki COCO](https://aiwiki.ai/wiki/coco_dataset); [arXiv 2403.18819](https://arxiv.org/pdf/2403.18819)
  - Inconsistency: the COCO 2017 JSON metadata lists per-image Flickr CC licences (for example CC BY 2.0). — [AWS Rekognition COCO docs](https://docs.aws.amazon.com/de_de/rekognition/latest/customlabels-dg/md-coco-overview.html)

### Inferences
- **ImageNet-pretrained backbones** (torchvision, timm) are a known grey zone.
  - The weights do not contain images.
  - But the training data was obtained under a non-commercial agreement, and the employer clause shows intent to bind commercial users.
  - For "only own weights", the owner's rule already excludes them. Legally, avoiding them removes a disputable dependency.
- **COCO-pretrained detectors** stack several layers of rights: annotation CC BY 4.0 (attribution), plus per-image Flickr licences, some of which are non-commercial (NC) variants, plus whatever code licence applies. Again, avoid.
- **Training from scratch is feasible for this narrow domain** (fixed wide camera, two classes, small objects).
  - Practical substitutes for ImageNet pretraining: self-supervised pretraining (for example masked-image or contrastive methods) on hours of own unlabelled match video, plus SoccerTrack v2 frames. Both are data we have rights to.
  - Owner's own PyTorch training code means all of the weights' provenance is under our control.
- **A lawyer is needed only if** the owner later decides to use any third-party pretrained weights.

### Gaps
- There is no authoritative ruling, and no ImageNet-team statement, on whether weights trained on ImageNet are bound by the access terms.
- The licence fields on timm/Hugging Face model cards were not reviewed individually.

## 4. Synthetic data: options and the licence status of rendered frames

### Takeaway
Google Research Football is Apache-2.0 (repo archived on 19 Aug 2026) and is built on the open-source Gameplay Football engine. The SoccER generator on the same engine outputs boxes for all 22 players and the ball. SoccerSynth-Detection (Unreal Engine; repo Apache-2.0, dataset licence not stated) shows synthetic pretraining works for player detection. Unreal's EULA treats rendered images as royalty-free products that need no engine code. Rendering our own synthetic frames is therefore a strong licence-clean source, especially for the ball.

### Cited Findings
- **Google Research Football:**
  - The LICENSE file is Apache License 2.0. — [raw LICENSE](https://raw.githubusercontent.com/google-research/football/master/LICENSE)
  - The README says the environment is "based on open-source game Gameplay Football" by Bastiaan Konings Schuiling.
  - The repo "was archived by the owner on Aug 19, 2026", and the README points to research-football.dev.
  - It renders on screen when installed locally, and can save replays with `--render=True`.
  - Source: [github.com/google-research/football](https://github.com/google-research/football)
- **SoccER (Morra et al., SoftwareX 2020):** a synthetic event-recognition generator built on Gameplay Football. It produces positions and bounding boxes of all 22 players and the ball for each frame. Code is MIT; the article is CC BY-NC-ND. Graphics are less realistic than commercial games. — [SoftwareX PDF](https://iris.polito.it/retrieve/e384c432-cbfb-d4b2-e053-9f05fe0a1d67/2020_Morra_SoftwareX.pdf)
- **SoccerSynth-Detection (Qin, Yeung, Umemoto, Fujii; arXiv 2501.09281):**
  - Rendered in Unreal Engine, with randomised lighting, grass textures and motion blur.
  - Boxes come from a purchased Unreal Marketplace plugin, in YOLO format.
  - The repo is Apache-2.0. The dataset (Google Drive) has no stated licence. A Windows generator is offered.
  - Source: [arXiv 2501.09281](https://arxiv.org/pdf/2501.09281); [GitHub open-starlab/SoccerSynth-Detection](https://github.com/open-starlab/SoccerSynth-Detection)
- **Unreal Engine EULA:**
  - Non-Engine Products include "rendered video files (e.g., broadcast or streamed video files, cartoons, movies, or images) created using the Engine Code", and no royalty applies.
  - An Epic moderator called a static rendered image an "Unrestricted Product".
  - Source: [Unreal Engine EULA](https://www.unrealengine.com/en-US/eula); [Unreal answers thread](https://answers.unrealengine.com/questions/896618/view.html)

### Inferences
- **Frames we render ourselves and labels we compute from the scene state are our own output.**
  - Engine licences (Apache-2.0 for GRF; the Unreal EULA's rendered-output rule) do not restrict them.
  - The remaining risk lies in third-party assets (player models, textures, stadium meshes, marketplace plugins) and their individual licence terms.
  - Use self-made or CC0 assets and keep a list.
- **The third-party datasets SoccerSynth-Detection and SoccER outputs** should not be assumed licence-free.
  - The SoccerSynth dataset licence is unstated, and it was made with a paid plugin.
  - It is better to run a generator ourselves (Apache/MIT code) or write our own.
- **The ball is where synthetic data helps most.**
  - SoccerTrack v2's ball is interpolated.
  - Synthetic scenes give exact per-frame ball boxes, including motion blur and occlusion.
  - Combine this with domain randomisation and our own real-footage pseudo-labels to close the sim-to-real gap.
- **A simpler fully own alternative:** composite real crops of the ball and players from own footage onto own empty-pitch backgrounds (copy-paste augmentation). This needs no game engine at all.

### Gaps
- The licence of the original Gameplay Football engine and its bundled art assets was not verified. The GRF repo is Apache-2.0, but bundled third-party assets may differ.
- The current Unreal EULA and Fab marketplace asset terms on AI or ML training use were not checked. Some marketplace content may carry "no AI training" flags.
- Licence status of Blender, Unity or Godot rendered output was not researched.
- Whether SoccerNet offers a synthetic set: not found.

## 5. Training on the developer's own recorded matches: privacy (GDPR / Ukrainian law / minors)

### Takeaway
Video of identifiable players is personal data. Ukraine's current law is No. 2297-VI (in force since 1 Jan 2011). The GDPR-aligned Draft Law No. 8153 passed first reading on 20 Nov 2024 and, per the latest source found, was still not enacted in mid-2026. Under GDPR Recital 51, ordinary photos and video are not "biometric" special-category data unless processed by specific technical means for unique identification. A detector that only finds "a person" and "a ball", without identifying anyone, stays outside the biometric category. Consent or notice, data minimisation and internal-only use are still needed, and youth matches call for parental consent.

### Cited Findings
- **Current Ukrainian law:**
  - The Law of Ukraine "On Personal Data Protection" No. 2297-VI was adopted 1 June 2010 and has been in force since 1 Jan 2011. — [Linklaters, Data Protected – Ukraine](https://www.linklaters.com/en/insights/data-protected/data-protected---ukraine); [Hunton blog, 20 Jul 2010](https://www.hunton.com/privacy-and-cybersecurity-law-blog/ukraine-adopts-a-new-data-protection-law)
  - Processing sensitive data requires "the individual's prior consent" unless a legal exemption applies. — [Hunton blog](https://www.hunton.com/privacy-and-cybersecurity-law-blog/ukraine-adopts-a-new-data-protection-law)
- **Draft Law No. 8153 (GDPR and Convention 108+ alignment):**
  - It passed first reading on 20 Nov 2024 and would create an independent supervisory authority. A mid-2026 legal guide says it is still heading toward second reading.
  - Source: [VoxUkraine](https://voxukraine.org/en/mandatory-informing-control-and-high-penalties-how-the-new-draft-law-changes-the-rules-of-personal-data-protection); [Sayenko Kharenko](https://sk.ua/gdpr-size-penalties-for-personal-data-protection-violations-what-can-individuals-and-businesses-expect-in-ukraine/); [CoE opinion on draft](https://rm.coe.int/opinion-on-the-draft-law-of-ukraine-on-personal-data-protection-/1680ad38c2)
  - Commentators point to GDPR-size penalties under the draft. — [World Law Group / Sayenko Kharenko](https://www.theworldlawgroup.com/membership/news/news-gdpr-size-penalties-for-personal-data-protection-violations-what-can-individuals-and-businesses-expect-in-ukraine)
- **GDPR Recital 51:** "The processing of photographs should not systematically be considered to be processing of special categories of personal data as they are covered by the definition of biometric data only when processed through a specific technical means allowing the unique identification or authentication of a natural person." — [gdpr-text.com Recital 51](https://gdpr-text.com/en/read/recital-51/)
  - Commentary notes the wording mismatch with Art. 4(14), which says "specific technical processing". — [Helbing, Art. 4(14)](https://www.thomashelbing.com/en/wissen/dsgvo-hub/begriffe-und-definitionen/1.2.14-biometrische-daten)
  - Commentary also notes that photographs can still reveal sensitive traits. — [VeraSafe](https://verasafe.com/blog/gdpr-and-photographs-understanding-special-categories-of-personal-data/)
- **Minors in Ukraine:** a 2023 peer-reviewed article compares how Ukraine and the EU protect minors' data and proposes extra safeguards. Specific consent ages were not extracted. — [Safeguarding Minors' Personal Data (ODUVS)](https://dspace.oduvs.edu.ua/handle/123456789/6929)
- **SoccerTrack v2 shows the research norm:** release pseudonymised, with no names and only jersey numbers and integer IDs. — [HF card](https://huggingface.co/datasets/atomscott/soccertrack-v2)

### Inferences
These are practical steps, to be validated by a Ukrainian/EU data-protection lawyer before scale.
1. **Purpose and minimisation.**
   - Use footage only to train a detector of generic classes (person, ball). No face recognition, no identity, no jersey-to-name linking.
   - This keeps processing outside the "biometric" special category under the GDPR Recital 51 logic.
2. **Notice or consent at recording.**
   - For adult amateur matches: get the club's or organiser's permission, put notice in the team chat or on a pitch sign ("filmed to train camera software; not published"), and give a contact for objections.
   - For youth football: written parental consent through the club. This is the conservative default, because minors get extra protection under both regimes.
3. **Internal only.**
   - Keep raw video on the developer's Mac. It is already git-ignored under `work/`, per the project rule "never commit videos".
   - Do not upload raw video to third-party labelling services.
   - Do not publish frames in docs or marketing without consent.
4. **Anonymise training crops where possible.**
   - Blurring faces costs almost nothing for a small-object player/ball detector at wide-shot resolution. It reduces risk if training data ever leaks.
   - Delete raw video after labels and crops are produced, or set a retention period.
5. **The shipped weights** encode statistical patterns, not recognisable images. The privacy risk then sits mostly in the training data store, not in the app.
   - This is an interpretation. Regulators have debated whether models can "contain" personal data, which is a gap below.
6. **Scope.** If the app is offered in the EU, GDPR applies to any user data the app processes on its own servers. On-device processing with nothing uploaded minimises this. Training data collected in Ukraine is governed by Law 2297-VI now, and by Law 8153 if enacted.

### Gaps
- The exact list of legal bases in Law 2297-VI (Art. 11), and whether "legitimate interest" covers ML training on amateur sports video, were not retrieved. A lawyer is needed.
- No Ukrainian guidance specific to filming sports events, to minors' consent age for data processing, or to AI training data was found.
- EU regulator positions on whether trained model weights constitute personal data were not researched (for example the EDPB opinion on AI models).
- The current status of Draft 8153 in October 2026 is not confirmed; the latest source found is mid-2026.
