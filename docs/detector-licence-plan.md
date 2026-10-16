# Plan: nothing under someone else's licence in the product (own detectors, own streaming)

Status: plan, 2026-10-16. Owner's rule (2026-10-16): **the finished app contains only our own code and our own model
weights; nothing under another software licence.** This replaces the earlier idea of switching to Apache-2.0 detectors.

## Boundary

| | Allowed | Why |
| --- | --- | --- |
| Apple system frameworks (AVFoundation, Core ML, Vision, VideoToolbox, Network, SwiftUI…) | Yes | The platform itself; every iOS app uses them, nothing is bundled |
| Dev tools on the Mac (Python, PyTorch, NumPy, OpenCV, ffmpeg, coremltools, Xcode) | Yes, never shipped | They only produce our files (weights, `.mlpackage`); the output is ours |
| Third-party models (YOLO, DETR…) as a temporary teacher on the Mac | Only to bootstrap labels, removed at the end | Their outputs are data; the shipped weights are trained by our code on our data |
| Data: SoccerTrack v2 (CC BY 4.0) and the owner's own matches | Yes for training; attribution in the app's "About" for SoccerTrack | Data, not software; long term our own footage dominates |
| Any third-party code or weights inside the app | **No** | Owner's rule |

## What has to go

| In the app today | Licence | Replacement |
| --- | --- | --- |
| `players.mlpackage` (stock YOLO11s) | AGPL-3.0 | **FolloNet-P**: own player detector |
| `ball.mlpackage` (YOLO11n fine-tuned with Ultralytics) | AGPL-3.0 | **FolloNet-B**: own ball detector |
| HaishinKit + Logboard (RTMP streaming) | BSD-3-Clause | **Own RTMP(S) client** on Network.framework, fed by our own VideoToolbox encoder (this also gives the 60 s buffer, `remote-and-buffer-plan.md`) |
| Google Sign-In SDK (planned) | Apache-2.0 | Own OAuth with `ASWebAuthenticationSession` + PKCE (system) |

Everything else is already ours: camera logic, tracker, goals, field mask, highlights, scoreboard, `Detector.swift`.

## Own detectors: realistic with the same results?

**Yes, with more work than switching models, because we train from scratch: no borrowed architecture code and no
pretrained weights.** It is realistic for three reasons:

- **The task is much narrower than general object detection.** One class of people seen from a high fixed camera, and one
  small ball. The camera logic does not need boxes. It needs player **foot points** and **height**, and the **ball
  centre**. Heatmap networks in the style of CenterNet do exactly that and are simple to write and train.
- **There is plenty of data.** SoccerTrack v2 has 10 full matches in 4K; today we use 4 minutes of 3 of them. That is
  hundreds of thousands of frames, and the owner's matches will add more.
- **The phone budget favours a purpose-built small network.** A convolution-only design sized for the Neural Engine
  should be faster than today's YOLO11s on 1280×672 tiles.

Risks and how we handle them:

| Risk | Handling |
| --- | --- |
| Training from scratch needs many labelled frames | Labels from three sources, all producing data, not shipped code (below); heavy augmentation (colour, blur, scale, lighting, compression) |
| Generalising to other stadiums (SoccerTrack is a few university pitches) | Owner's own matches as soon as they exist; a self-training loop: our model labels new matches, our tracker filters the labels, retrain |
| Far, small players (15–30 px tall) | High-resolution output (stride 4), the pitch band only (as the 16:9 tiles already do) |
| A tiny fast ball | The ball network sees 3 consecutive ROI frames (motion), a known strong approach |
| Training time on the M1 | Small networks; resumable training (checkpoint every epoch, project rule); a free cloud GPU only if needed |

## Labels without shipping anyone's code

1. **SoccerTrack v2 annotations: human-made, CC BY 4.0.** Each player's position on the pitch every frame. A
   pitch-to-image homography from the pitch lines (own code: we already find the field mask and the halfway line) projects
   them into the image as foot points. Box height comes from depth: about 1.8 m at the measured scale. These are the best
   labels: human truth.
2. **Teacher labels (bootstrap only).** Today's models, or any large detector, run offline on the Mac. Their outputs
   become extra labels where 1 does not reach: the ball, frames without annotations. Our tracker confirms or drops them.
   The teacher is never shipped and is removed once FolloNet labels better than it.
3. **Own self-training.** From version 2 on, FolloNet labels new footage itself, cleaned by the tracker and the
   SoccerTrack truth.

Hold-out, per project rule: matches 1–3 (today's checklists) and the last 20% of every video are never trained on.

## Network designs (written by us from scratch, PyTorch on the Mac → Core ML)

- **FolloNet-P (players).**
  - Input: a pitch-band tile, the same tiles as today, 1280×672.
  - Body: a small conv stack (depthwise-separable blocks, about 1–2 M parameters).
  - Outputs at stride 4: a foot-point heatmap, a height map, and an optional "near the ball" score.
  - A Core ML pipeline step turns the heatmap peaks into the same boxes `Detector.swift` reads today, so the tracker and camera do not change.
- **FolloNet-B (ball).**
  - Input: the 320 px ROI from 3 consecutive frames (9 channels).
  - Output: a ball-centre heatmap and confidence.
  - Trained with hard negatives: spare balls beyond the line, heads, line crossings, the look-alikes found on 2026-10-15.
- **Core ML.** Plain convolutions only, so everything runs on the Neural Engine. Exported with coremltools (a dev tool); the `.mlpackage` is ours.

## Acceptance criteria (unchanged: "same result")

| Metric | Today (Core ML, aligned) | Required |
| --- | --- | --- |
| Goal checklist | 7/7 | 7/7 |
| Ball in crop | 97.8% / 93.8% / 78.5% | Not lower by more than 1 point |
| Jumps, twitches | 1.4–2.3%, 0.8–1.8 per min | Not worse |
| Player recall vs today's model, far half | — | ≥ 97% |
| iPhone 15 players pass / ball ROI | to measure | ≤ 60 ms / ≤ 15 ms |
| 30-min phone run | 25–30 fps, ~600 MB, thermal ok | Same |

## How we move (owner's rules, 2026-10-16)

- **One step at a time.** The next step starts only after the current one is understood in detail and tested.
- **Always before/after.** Every step is compared with the old flow on identical inputs, with numbers and frames.
- **Switchable.** The old flow stays in the app. Every new part sits behind a switch, so we can always go back:
  - `Streamer` HaishinKit / Follo;
  - detector set YOLO / FolloNet;
  - sign-in via SDK / own.
  The default stays "old" until the new part has passed on the phone.
- **Mac first.** Everything is tested on the Mac (`follosim`, local servers, recorded matches); the phone checks come
  later, in a batch, when the owner has the phone.

## Rollback plan

- **Steps 1a–1e** only add new files to `FolloCore` and new `follosim` commands. The app does not use them, so rolling
  back means doing nothing: the phone keeps streaming through HaishinKit.
- **Step 1f** (app integration):
  - Before it, a git tag `before-own-streamer` marks the last commit with the old path only.
  - The new `FolloStreamer` sits behind a switch, `Streamer.engine = .haishinkit | .follo`. The default stays
    `.haishinkit` until the phone tests pass.
  - A debug toggle on the setup screen and a launch argument (`--streamer follo|haishinkit`) flip it without a rebuild.
- **If something goes wrong on the phone:**
  1. Flip the switch back. It takes one tap, and nothing else changes.
  2. If the build itself is broken, `git checkout before-own-streamer` and rebuild.
- **HaishinKit is removed** only after the new path has passed:
  - every Mac test;
  - the phone tests: local RTMP server, drops of 10, 30 and 60 s, a 90-minute run, and a private YouTube broadcast.
  - The removal is its own commit, so `git revert` brings it back.
- **The same rules hold for the detectors.** The model set is switchable: YOLO, the current one, or FolloNet. The YOLO
  models stay in the bundle until FolloNet meets every acceptance criterion, and they are removed in a separate,
  revertible commit.

## Stages in order of importance

1. **Own streaming core** (replaces HaishinKit, gives the 60 s buffer). Steps, each tested on the Mac before the next:
   - **1a.** H.264 encoder on VideoToolbox (`VideoEncoder`), compared with the same hardware encoder driven by ffmpeg:
     validity, GOP, bitrate, PSNR, speed, frames. **Done 2026-10-16** (`results.md`): equal quality, BT.709 tagged, bitrate steps work; the low step stays 1080p.
   - **1b.** Own FLV muxer, compared with ffmpeg's FLV of the same packets.
   - **1c.** Own RTMP client into a local `ffmpeg -listen` server: the received stream must equal what was sent.
   - **1d.** Encoded ring buffer and reconnect, through a local proxy that cuts the connection for 10/30/60 s: no frame lost.
   - **1e.** AAC audio.
   - **1f.** App integration behind the switch, default HaishinKit.
2. **Detector bench and switch.** `Detector` takes any model with the same outputs; frozen benchmark; the YOLO/FolloNet switch.
3. **FolloNet-B** (ball): smaller and the quicker win.
4. **FolloNet-P** (players), with the homography labels from SoccerTrack.
5. **Own OAuth.**
6. **Removal** of HaishinKit and the YOLO models, only after the phone checks pass.

## Phases

| # | Work (Claude) | Owner | Effort |
| --- | --- | --- | --- |
| 0 | Confirm the SoccerTrack v2 source and terms; download all 10 matches with annotations; record the boundary above in `decisions.md` | Accept the dataset terms if gated | 0.5 day |
| 1 | Benchmark harness: `Detector.swift` takes any model with the same outputs; frozen benchmark on matches 1–3 and the 16:9 versions; phone speed mode | Phone 10 min | 2 days |
| 2 | Own homography from pitch lines; project the SoccerTrack positions into the image; check on contact sheets (look at the output, project rule) | — | 3 days |
| 3 | Player dataset: projected human labels + teacher labels, tracker-cleaned, augmented | — | 2 days, resumable |
| 4 | FolloNet-P: write, train from scratch, export, measure; iterate on size until the phone budget and the recall hold | — | 5–7 days |
| 5 | FolloNet-B: ROI dataset with hard negatives, 3-frame input, train, compare end to end | — | 4–5 days |
| 6 | Own RTMP(S) client + own encoder: handshake, FLV/AVC/AAC packets, chunking over TLS (Network.framework); tested against `ffmpeg -listen` on the Mac, then YouTube; replaces HaishinKit and gives the 60 s buffer | Phone + home Wi-Fi | 5–6 days |
| 7 | Own OAuth (`ASWebAuthenticationSession` + PKCE) instead of the Google Sign-In SDK | Google Cloud project | 1–2 days |
| 8 | Integration: Python reference = Swift parity; every acceptance metric; 30-min phone run; remove the teacher and HaishinKit; a build check that fails on any third-party package or model | Phone 40 min | 2 days |

Total: about 5–6 weeks at the current pace. Order: phase 6 first (it is needed for real broadcasts anyway and removes
HaishinKit); the detector phases run on the Mac in parallel; the switch happens only when every acceptance criterion holds.

## Fallbacks (still all own)

- **FolloNet-P misses far players.** Raise the output resolution in the band, add a second pass on far-half tiles every 8th
  frame, or train longer with more SoccerTrack matches.
- **FolloNet-B is weaker than today's ball model.** Use more temporal context (5 frames), add our background-difference
  map as an extra input channel (own computation we already have), or use a larger ROI model only while the ball is lost.
- **Not enough diversity.** Collect the owner's matches from now on: every recorded game is training data.
