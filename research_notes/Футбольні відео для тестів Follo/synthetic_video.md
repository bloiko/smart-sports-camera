# Synthetic football video and data for testing/training Follo's ball and player detectors

Scope: rendered, simulated or generated football imagery that could test or train a small ball detector (0.5 M params, 3 frames + prior, heatmap) and a player detector for one static ultra-wide phone at the halfway line; plus the option of building our own generator. Research date: 21 Oct 2026. Tool budget was limited, so several items are marked as gaps.

## 1. Existing synthetic football datasets and simulators: licence and available views

### Takeaway
Only one recent dataset (SoccerSynth-Detection, Unreal Engine, permissive licence) labels the ball, and it renders broadcast-style main-camera views, not a static wide phone view. Google Research Football is permissively licensed and modifiable, but its graphics are old and its default camera follows the ball. Nothing found offers a fixed ultra-wide view from the stands, so for our geometry we would have to make our own data.

### Cited Findings
**SoccerSynth-Detection (open-starlab, 2025; data released 2026)**
- Built in Unreal Engine on an earlier stadium simulator (Qin et al., 2022). Characters, animations, spectators and the "2D Bounding Box for Deep Learning Image Detection" plugin were bought on the Unreal Marketplace. Players are driven by Behavior Trees and an AI Controller, and the physics engine handles passes, dribbles and shots — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Two YOLO-format classes: 0 = player, 1 = soccer ball. 37,621 normal images (1920×1080) plus 17,052 motion-blurred images (800×600), split 4:1 into train/val — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Views: the simulator has drone, corner and centre cameras, but the dataset uses only the centre camera. Its position, angle and focal length were modelled on SoccerNet-Tracking and SportsMOT, which are broadcast footage — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Motion blur comes from random camera shake. Ball motion blur is not described — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Domain randomization covers grass colour and texture, lighting and player textures — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2); [Zenodo record](https://zenodo.org/records/20839314)
- Stated limitations: centre camera only; frames are not temporally continuous (chosen for diversity); head models lack variety, so heads are sometimes missed — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Licences:
  - The Zenodo dataset record is CC BY 4.0, v1.0.0, published 25 June 2026, archives 90.4 GB in 9 parts, "broadcast-style main-camera views" — [Zenodo](https://zenodo.org/records/20839314)
  - The GitHub repo is Apache-2.0 (checked via the GitHub API) — [github.com/open-starlab/SoccerSynth-Detection](https://github.com/open-starlab/SoccerSynth-Detection)
  - Both licences are permissive. Whether the bought Marketplace assets limit how the renders can be used is not stated (see Gaps).
- SoccerSynth-Field (same group) is a synthetic pitch/field-detection dataset made with Unreal Engine 5 for pretraining. It lets you change lighting, camera angles and field elements. Repo licence is Apache-2.0 — [arXiv 2503.13969](https://arxiv.org/abs/2503.13969); [GitHub API: open-starlab/SoccerSynth-Field](https://github.com/open-starlab/SoccerSynth-Field)

**Google Research Football (GRF) / Gameplay Football**
- The GRF wrapper is Apache-2.0 (GitHub API). The repo was archived on 19 Aug 2026; last push 17 Jun 2025. The README points to a new game server at research-football.dev — [github.com/google-research/football](https://github.com/google-research/football)
- The bundled C++ engine (`third_party/gfootball_engine`) is released into the public domain (Unlicense text). It is "a heavily modified version" of BazkieBumpercar/GameplayFootball — [engine LICENSE](https://github.com/google-research/football/blob/master/third_party/gfootball_engine/LICENSE)
- Rendering is optional. Rendered frames are 1280×720 by default and appear in the observation only when `render=True` — [observation.md](https://github.com/google-research/football/blob/master/gfootball/doc/observation.md); [api.md](https://github.com/google-research/football/blob/master/gfootball/doc/api.md)
- SoccER (2020) used the Gameplay Football engine to produce 8 synthetic matches (500 min, 1920×1080, 30 fps) with per-frame positions and bounding boxes of all 22 players and the ball. The authors say the graphics are not as photorealistic as commercial products and the physics is "reasonably accurate". No dataset licence is given; code is at gitlab.com/grains2/slicing-and-dicing-soccer — [arXiv 2004.04147](https://ar5iv.labs.arxiv.org/html/2004.04147)

**Unity Perception**
- The Unity Perception package (synthetic-data tooling) is discontinued and no longer supported by Unity. The SynthDet sample was archived on 5 Dec 2024. The GitHub API shows the package licence as "NOASSERTION", meaning a custom Unity licence — [com.unity.perception](https://github.com/Unity-Technologies/com.unity.perception); [SynthDet](https://github.com/Unity-Technologies/SynthDet)
- No Unity Perception sports dataset was found.

**Commercial games (EA FC / FIFA, PES/eFootball)**
- "Soccer on Your Tabletop" (CVPR 2018) captured colour and depth buffers from FIFA with RenderDoc to train player depth estimation. This shows such capture works technically — [arXiv 1806.00890](https://arxiv.org/pdf/1806.00890)
- No paper was found that measures a FIFA-to-real detection domain gap.

### Inferences
- None of the found datasets matches our view: one static phone, ultra-wide lens, low on the halfway line, whole pitch in frame, players about 30–150 px tall and the ball about 3–8 px in 4K. SoccerSynth targets broadcast framing, where the ball is larger and often in the middle of the frame.
  - SoccerSynth could still be a Mac-side pretraining or teacher source for the player detector: CC BY 4.0 / Apache-2.0 allow commercial use with attribution.
  - It is weak for our ball problem: no ball motion blur, broadcast scale, and frames are not consecutive, so it cannot feed a 3-frame model.
- GRF's public-domain engine could in principle get a fixed camera at the stands, and its ball physics gives consistent 3D trajectories. Its 2010-era rendering is far from phone footage, though. At best it could be a trajectory source, not an image source.
- Footage from EA FC or eFootball is copyrighted game output under those publishers' EULAs. Even on the Mac it is a legal grey zone, and a model trained on it would carry that risk into the app. Avoid it. This is inference: I did not check the EULA text.

### Gaps
- No "SoccerNet synthetic" dataset was found. As far as I could see, SoccerNet releases are real broadcast footage, but this was not checked in this session.
- No GTA-based football or sports dataset was found. GTA-based datasets in general, such as JTA for pedestrians, are known to carry non-commercial licences, but I did not verify this here.
- Whether Unreal Marketplace (now Fab) asset licences restrict using renders of those assets as ML training data was not verified. This matters for SoccerSynth, and for us if we were to buy assets.
- GRF camera options (can the camera be fixed, field of view) were not checked in source code. The docs only mention `render`.

## 2. Evidence that synthetic data helps small-object / ball detection, and the tricks that make it work

### Takeaway
Published evidence for synthetic data in sports is real but modest. It helps most when real data is scarce or when the synthetic data covers a condition the real data lacks, such as motion blur. Fully synthetic ball-image detection in football has no strong published result. The best-documented successes either simulate only trajectories (table tennis) or composite a rendered ball over real frames. The copy-paste literature shows that placing objects without context or with visible seams can hurt, which matches Follo's 2–5× rise in false alarms.

### Cited Findings
**Sports results**
- SoccerSynth-Detection, YOLOv8n, results given as AP50 / AP50:95:
  - Synthetic-only training transferred to SoccerNet-Tracking at 89.4 / 48.4, against 82.8 / 43.9 when trained on SportsMOT.
  - Tested on SportsMOT, synthetic-only scored 88.1 / 63.3, against 90.3 / 62.3 when trained on SoccerNet.
  - So synthetic is roughly equal to cross-dataset real data and better on blurred images — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- SoccerSynth pretraining followed by real fine-tuning:
  - The largest gain was with little real data: SportsMOT at 1/8 subsampling went from 92.6 / 73.1 to 95.3 / 75.8.
  - With full real data there was no gain: 93.2 / 78.0 unchanged.
  - At 1/2 subsampling on SportsMOT, AP50 fell slightly (93.6 → 92.6). On SoccerNet the gains were only 0.1–0.5 AP50.
  - No ball-only AP is reported — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v2)
- Table tennis (Kienzle et al., CVPRW CVsports 2025):
  - A network trained only on physically simulated data (MuJoCo trajectories with realistic bounces) infers spin and 3D trajectory from broadcast video, using 2D ball trajectories as input.
  - Results: 92.0% spin-classification accuracy and 0.19% of the image diagonal 2D reprojection error, with no real training data.
  - The authors credit three things: the input representation, physically correct synthetic data, and targeted augmentations — [arXiv 2504.19863](https://arxiv.org/abs/2504.19863); [CVF PDF](https://openaccess.thecvf.com/content/CVPR2025W/CVSPORTS/papers/Kienzle_Towards_Ball_Spin_and_Trajectory_Analysis_in_Table_Tennis_Broadcast_CVPRW_2025_paper.pdf)
  - A follow-up scales to 140,000 synthetic trajectories (over 4.7 M 2D ball positions) — [arXiv 2511.20250](https://arxiv.org/pdf/2511.20250)
- Football ball tracking, master's thesis (Lhoest, ULiège): training images were "a modeled ball in front of a real frame from a football match video". It reports 96.1% ball detection accuracy on moving-camera sequences — [ULiège MatheO thesis](https://matheo.uliege.be/bitstream/2268.2/9074/6/Alexandre_Lhoest_s153184_Master_Thesis.pdf). The server refused the connection, so these figures come from the search snippet only and are unverified.
- BlurBall (Gossard et al., Tübingen; arXiv Sep 2025, CVPRW CVsports 2026), real data, table tennis: labelling the ball at the centre of the blur streak, rather than its leading edge, and predicting blur orientation and length "consistently enhances detection performance across various models". It also makes trajectory prediction more reliable — [arXiv 2509.18387](https://arxiv.org/abs/2509.18387); [CVPRW 2026 supplement](https://openaccess.thecvf.com/content/CVPR2026W/CVsports/supplemental/Gossard_BlurBall_Joint_Ball_CVPRW_2026_supplemental.pdf)
- DeFMO (CVPR 2021) recovers sharp sub-frame appearance and trajectory of fast-moving objects from one blurred frame plus an estimated background. It is trained only on a synthetic dataset, built on the fast-moving-object image formation model, and works on real data from several datasets — [CVF](https://openaccess.thecvf.com/content/CVPR2021/html/Rozumnyi_DeFMO_Deblurring_and_Shape_Recovery_of_Fast_Moving_Objects_CVPR_2021_paper.html)

**General copy-paste and synthetic-data tricks**
- Kisantal et al. 2019, small objects on COCO with Mask R-CNN:
  - Oversampling images with small objects and copy-pasting small objects gave +7.1% relative on small-object detection (+9.7% on small-object segmentation).
  - Gains plateau after 1–2 pastes per object, and pasting several different small objects (about 3 per image) beats pasting one — [arXiv 1902.07296](https://arxiv.org/abs/1902.07296)
  - The ablation numbers come from search snippets, not the full text.
- Dwibedi et al. (ICCV 2017), "Cut, Paste and Learn":
  - Seams from pasting hurt detectors, because detectors rely on local region features.
  - Fix: render the same object with several blending modes (none, Gaussian, Poisson), so seams stop being a cue. "Patch-level realism" is enough.
  - Combined with real images, relative gain was over 21% — [arXiv 1708.01642](https://arxiv.org/abs/1708.01642)
- Dvornik et al. (ECCV 2018): naive random placement of pasted objects hurts. A context model that chooses plausible locations gives significant mAP gains when labelled data is scarce (VOC'12) — [arXiv 1807.07428](https://arxiv.org/abs/1807.07428)
- The follow-up study: random placement gave 48.3 against a 48.7 baseline (no gain), and removing context entirely gave 33.9. The authors conclude that missing context is the key factor, while illumination differences and blending artifacts are "not critical" in their setting — [arXiv 1809.02492](https://arxiv.org/pdf/1809.02492)
  - This partly contradicts Dwibedi's emphasis on blending. Both are on large VOC-type objects, not 4-px balls.
- Tremblay et al. (NVIDIA, CVPRW 2018), domain randomization for car detection on KITTI: training on randomized synthetic data (about 100k images: random lighting, pose, textures, distractors) and then fine-tuning on real data beats training on real data alone — [arXiv 1804.06516](https://arxiv.org/abs/1804.06516); review: [arXiv 2007.08781](https://arxiv.org/pdf/2007.08781)

### Inferences
- The pattern across sources: synthetic data helps when it supplies something the real set lacks (blur, rare views, far small objects) and when a real fine-tune or real mix follows. It does not replace real data from the target camera. For Follo, the owner's own phone footage stays the main training and test domain.
- Likely causes of our false-alarm rise, from Dvornik, Dwibedi and Kisantal combined. These are inference, not tested:
  - (a) Sprites were pasted at random, out-of-context places, so the network learned "any small bright blob is a ball" instead of "a ball in a plausible place with plausible motion".
  - (b) Paste seams or a sharpness/colour mismatch gave the network an easy shortcut, so the real-ball features got weaker.
  - (c) Too many synthetic positives relative to real hard negatives (socks, heads, line junctions, white shoes) moved the decision threshold.
- Table tennis suggests the most robust use of simulation for us may be trajectories (the motion prior, the "3 frames + prior" part, and the tracker), not pixels. That is cheap, has no licence problems, and is fully our own computation.

### Gaps
- I found no published paper with measured gains from synthetic data for football ball detection specifically, and none for basketball, cricket or volleyball ball detection with a sim-to-real comparison. The Lhoest thesis is the closest and could not be read.
- No source gave a measured best synthetic:real mixing ratio for small balls. Tremblay's fine-tuning ratio was not in the retrieved text.

## 3. Video generation models (2025–2026) as a source of football test clips

### Takeaway
Not suitable as ground truth for ball detection. Independent benchmarks show that current generators break basic ball physics, most clearly gravity and timing, and the clips come with no labels. At most they could stress-test visual robustness (light, kits, pitches), with labels made by hand or by a teacher model, which goes against the product rule of never marking anything by hand.

### Cited Findings
- Physics-IQ (INSAIT + Google DeepMind, ICCV 2025): Sora, Runway, VideoPoet and others produce visually convincing videos but fail to capture the underlying physical dynamics — [INSAIT](https://insait.ai/new-benchmark-physics-iq-challenges-ai-video-models-understanding-of-the-physical-world/); [arXiv 2501.09038](https://arxiv.org/html/2501.09038v1)
- "Objects in Generated Videos Are Slower Than They Appear" (arXiv Dec 2025):
  - Generated falling objects show an effective gravity of only about 1.81 m/s², and changing the time scale does not fix the high-variance error. Galileo's equivalence principle is also violated.
  - A LoRA fine-tuned on 100 single-ball clips raises it only to 6.43 m/s², about 65% of Earth's gravity — [arXiv 2512.02016](https://arxiv.org/abs/2512.02016)
- VideoScience-Bench (Dec 2025): Sora-2 and Veo-3 rank highest, yet still "struggle significantly" on simple physical scenarios, for example balls in rotating cups — [arXiv 2512.02942](https://arxiv.org/html/2512.02942)
- Search results for AI football video generators were only marketing pages, with no measurements. One guide mentions the ball "teleporting" and fake-looking goals as common failure modes, which is anecdotal — [search summary, e.g. getstarrd.app](https://www.getstarrd.app/blog/how-to-make-world-cup-ai-video)

### Inferences
- A ball with wrong gravity and teleport jumps would train or validate the wrong motion prior for our 3-frame model and tracker. Using such clips for evaluation would give misleading recall numbers.
- Generated clips also do not reproduce our exact optics: a fixed tripod, the ultra-wide distortion of one phone, and HEVC artefacts.

### Gaps
- Terms of service of Veo 3 / Sora 2 / Kling etc. on using outputs as training data were not checked in this session. Even if allowed, the product rule ("prefer own computation") argues against it.
- No benchmark exists for football-specific generated ball physics.

## 4. Building our own minimal generator: recipe, engine licences, how to avoid false alarms

### Takeaway
The cheapest option that best matches our domain and licence rules is a 2D compositor written by us, in Python/numpy on the Mac. Its main parts:
- background plates from our own footage (median empty pitch, plus real frames with players)
- 3D ball trajectories from physics, projected through our own calibrated camera model with ultra-wide distortion
- motion blur from the fast-moving-object formation model integrated over the real exposure time
- the full camera degradation chain applied to the whole frame
- context-aware placement and hard negatives

Engine licences do not block any option:
- Blender output belongs to the user.
- Unreal linear renders are royalty-free; seats are needed only above $1 M revenue.
- Unity Personal is free under $200k total finances.
- Godot is MIT.

A 3D engine is only worth it later, for player bodies and occlusions.

### Cited Findings
**Licences**
- Blender (GPL): "What you create with Blender is your sole property" and the output is free to use as you like, including commercially — [blender.org/about/license](https://www.blender.org/about/license/)
- Unreal Engine:
  - Linear content (films, videos, still images) under the standard EULA has no fees or royalties.
  - Companies making linear content with over $1 M annual gross revenue must buy Unreal Subscription seats.
  - The 5% royalty applies to interactive products using engine code above $1 M lifetime revenue — [Epic FAQ](https://gateway.unrealengine.com/en-US/faq); [Twinmotion licence page](https://map.twinmotion.com/license); [older EULA PDF](https://cdn1.epicgames.com/eulatracking-download/ue_games/en/v1/r4/cf33c801ba52b566dcf201a862da65a9.pdf)
  - The current EULA page returned 403, so the exact 2026 wording is unverified.
- Unity Personal:
  - Free if Total Finances (revenue and/or funding) are at most $200,000 over the last 12 months. The ceiling was raised from $100k in 2024.
  - Users own content they create. A separate $1 M threshold applies to Unity Industry for non-game applications — [Unity licence compliance](https://unity.com/en/pages/license-compliance); [Unity support](https://support.unity.com/hc/en-us/articles/28114350573460)
  - The Perception package is discontinued (see §1).
- Godot: MIT licence (GitHub API on godotengine/godot) — [github.com/godotengine/godot](https://github.com/godotengine/godot)
- GRF wrapper is Apache-2.0 and its engine is public domain (see §1).

**Image-formation and placement building blocks**
- Fast-moving-object image formation: the blurred frame is the background mixed with the object's appearance and mask, both integrated along the trajectory during the exposure. DeFMO and the earlier FMO work train on synthetic data built this way and transfer to real footage — [DeFMO CVPR 2021](https://openaccess.thecvf.com/content/CVPR2021/papers/Rozumnyi_DeFMO_Deblurring_and_Shape_Recovery_of_Fast_Moving_Objects_CVPR_2021_paper.pdf)
- Label at the centre of the blur streak and store blur length and orientation — [BlurBall](https://arxiv.org/abs/2509.18387)
- Place objects where context makes them plausible — [Dvornik 2018](https://arxiv.org/abs/1807.07428)
- Vary blending so seams carry no signal — [Dwibedi 2017](https://arxiv.org/abs/1708.01642)
- 1–2 pastes per object and several objects per image — [Kisantal 2019](https://arxiv.org/abs/1902.07296)
- Randomize nuisance factors and add distractors, then fine-tune on real — [Tremblay 2018](https://arxiv.org/abs/1804.06516)
- Pretraining gains disappear once enough real data exists — [SoccerSynth](https://arxiv.org/html/2501.09281v2)

### Inferences (proposed recipe for Follo; my own engineering reasoning, not published results)

**1. Geometry first.**
- Use the camera calibration that `src/` already estimates from pitch lines, or estimate one, including the ultra-wide radial distortion.
- Generate 3D ball trajectories with gravity, drag and bounce from a player's foot position taken from real player tracks:
  - ground passes 8–20 m/s
  - lofted passes and shots 15–30 m/s
  - rolling with friction
- Project them into the distorted image.
- This gives correct apparent size and speed at every pitch depth, which random pasting lacks.

**2. Scale check** (computed, approximate):
- An ultra-wide of about 120° horizontal field of view over 3840 px, looking at the far touchline about 60 m away, covers about 208 m of width → about 18 px/m. A 0.22 m ball is then about 4 px.
- At 25 m/s and 30 fps the ball moves about 0.83 m (about 15 px) between frames.
- Blur inside one frame is speed × exposure:
  - at 1/500 s, about 5 cm, about 1 px
  - at 1/60 s (dusk), about 42 cm, about 7–8 px streak
- So the exposure time read from the phone metadata, which differs between sunny and dim footage, should drive the blur length.

**3. Ball appearance.**
- Prefer real ball patches cut from our own footage over drawn sprites: near and far, sunny and shaded, with an estimated alpha.
- Or render a sphere with simple Lambert shading from the sun direction plus a ground shadow.
- Composite with the FMO model in linear light: integrate 16–32 sub-frame positions over the exposure.

**4. Backgrounds.**
- Use real frames of the same and other matches, not only median empty plates.
- Players, lines, shadows and other balls in the backgrounds give natural hard negatives.
- Place the ball only on grass or in the air above it, near play (for example within N m of the player centroid, or starting at a player's foot). Never in the stands, sky or goal netting, except when a trajectory goes there physically.

**5. Degradation chain over the whole composite frame**, so the ball shares the background's artefacts:
- slight defocus or optical blur
- sensor-like noise
- the phone's sharpening halo
- downscale exactly as in our pipeline
- an HEVC/H.264 re-encode with ffmpeg at the phone's bitrate (encode the 3-frame sequence as video, not as separate JPEGs)

This removes the "pasted = sharper or cleaner" shortcut.

**6. Seams.** Randomize blending (hard alpha, feathered, Poisson-like) per sample, as in Dwibedi.

**7. Temporal consistency for the 3-frame model.**
- Generate full sequences so the ball's motion across the 3 frames and the prior are physically consistent.
- Also add temporal negatives with label "no ball": static white blobs, one-frame flickers, blobs that jump inconsistently.
- This teaches the network that motion consistency, not brightness, defines the ball.

**8. Mixing.** Start small:
- Add synthetic positives only for the missing regime (fast, far, blurred).
- Keep them a minority of training samples, for example 10–30%, a guess to tune.
- Keep every real negative.
- Prefer synthetic pretraining followed by a real fine-tune.
- Gate every change on held-out real data (unseen match plus the last 20% of each video) and on the false-alarms-per-minute metric, not only recall.

**9. Evaluation-only use.** The compositor can also make labelled test clips of fast far passes that we cannot easily label in real footage, which fits "find it automatically". Treat them as a supplement to real checklists, not a replacement.

**Engine choice for later player synthesis.**
- If synthetic players are ever needed, Blender (GPL; output is ours; Python-scriptable; Cycles/Eevee on M1) or Godot (MIT) avoid any EULA question.
- Unreal and Unity are free at our revenue level but add closed EULAs and heavy tooling.
- Unity's synthetic-data package is discontinued.
- All of them cost far more of the owner's daily hour than a 2D compositor.

**Licence compliance with "nothing third-party ships".**
- Rendered or composited images are data we own (Blender, Godot, our own Python).
- The trained weights are ours.
- Only the tools stay on the Mac, which fits the product rule.

### Gaps
- No published measurement found of how much a physically correct blur model improves small-ball detection over simple Gaussian or box blur.
- No published false-alarm analysis of copy-paste for tiny (<10 px) sports balls. The causes above are inferred from general copy-paste studies on larger objects.
- iPhone exposure times at 4K 30 fps outdoors were not researched here. The blur estimates assume 1/500 s to 1/60 s.
- The exact current Unreal EULA text (2026) and the Fab asset licence's ML-training terms were not retrieved (403).
