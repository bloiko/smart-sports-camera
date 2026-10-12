# Development phases

The stable plan: what each phase must deliver, how it is tested, and when it is done. Progress, difficulties and lessons for each phase are tracked in `../specs/status.md`.

At about 1 hour a day, phases 0–4 (≈ 4–6 months) produce an iOS app: "record a game → get a video". Live streaming, Android and the full-size pitch are separate phases after that. A phase starts only when the previous one meets its exit criteria.

| Phase | Result | Duration | Budget | Exit criteria |
| --- | --- | --- | --- | --- |
| 0. Test footage | 5–10 game recordings | 1–2 weeks | 0 (tripod ≈ $30–60) | Day and evening footage, 2+ pitches |
| 1. Offline prototype | Script: video → video that follows play | 2–4 weeks | 0 | Ball in frame ≥ 80% of the time on reference clips |
| 2. Tracking quality and own model | Apache-licensed ball detector trained on own footage | 4–8 weeks | 0 (Kaggle / Colab) | ≥ 90% in frame; every goal visible; 3 friends watch to the end |
| 3. iOS app (Follo): record + live | App: 4K recording, virtual camera on the phone, live to YouTube, highlights | 12–16 weeks | $0 (free Apple ID sideload) | 3 full games streamed in a row with no manual step and no stream loss |
| 3b. Cloud processing (optional, later) | Upload the wide recording → better full video and highlights | 5–8 weeks | $0–5/mo | 3 matches processed with no manual steps |
| 4. Everyday use and beta | Owner + 5–10 friends via TestFlight | 4 weeks | ≈ $5/mo | Half of the testers record a game every week |
| 5. YouTube live | 1080p live stream with the virtual camera | 8–12 weeks | ≈ 0 | 90 minutes live without shutdown, with a power bank |
| 6. Android, full pitch, highlights | Second platform and new features | 3+ months | varies | Decision: hobby or business |

## Phase 0: test footage

**Goal:** a set of real recordings to test every later version against.

Recording requirements:
- iPhone, ultra-wide camera (0.5×), 4K 30 fps, landscape, static tripod.
- Mounted 2–3 m high near the halfway line, whole pitch in frame.
- Minimum: 2 day games, 1 evening game under floodlights, 2 different pitches; 5–15 minutes each.
- Ideally one full 40–90 minute match, to measure heat and battery.
- Note the phone position (photo of the setup), weather and time of day.

Testing: check on a Mac that the ball is visible by eye on the far side; note phone temperature warnings and battery before and after.

Exit: 5+ recordings, including at least 3 short "golden" clips (2–3 minutes with hard moments: ball in the air, crowd at the goal, evening light).

## Phase 1: offline prototype on a Mac

**Goal:** prove that a single wide frame can be turned automatically into a pleasant video that follows play. This is the main test of the whole idea.

Functional:
- A command converts a 4K video into 1080p 16:9 that follows play.
- Ball detection with an off-the-shelf model, panorama split into tiles.
- Player detection; when the ball is lost for more than 0.5–1 s, follow the players.
- Dead zone, speed and acceleration limits, two-sided smoothing.
- Debug render: panorama with the camera window, players and ball drawn on top.
- Camera trajectory saved to a file for comparing versions.

Non-functional: runs on a MacBook Air M1/M2 8 GB without the cloud; parameters in a config, not in code; code in Git.

Testing: automatic metrics on golden clips (share of frames with the ball inside the crop, maximum camera speed, number of jumps); watch the debug render and the output side by side; a results table per version.

Exit: ball in frame ≥ 80% of the time on all golden clips, and the owner can watch 5 minutes without irritation.

## Phase 2: tracking quality and own model

**Goal:** "not embarrassing to show" quality and a detector with a permissive licence.

Functional:
- Training data from own footage: pseudo-labels from the pipeline, plus manual labels for hard cases (night, ball in the air, goal area).
- Fine-tune an Apache-2.0 detector (RF-DETR, D-FINE or YOLOX) on Kaggle or Colab.
- Search for the ball in a window around its predicted position, not only in the whole frame.
- Lead the play: shift the crop slightly towards where play is heading.
- Widen the crop when tracking is uncertain.
- Goal-area mode: when the ball or play is near a goal, keep the goal mouth in frame.
- Check export of the model to Core ML (needed for phase 5).

Non-functional: model and dataset licences documented; model ≤ 50 MB; reproducible training script and dataset version.

Testing: hold out the last 20% of every video for validation; measure ball recall; same metrics on golden clips plus 2 new videos the model has never seen; a goal checklist (every goal in the test videos must be visible); show a 5-minute clip to 3 friends without explanation.

Exit: ≥ 90% in frame on day footage, ≥ 75% in the evening; every goal visible; 2 of 3 friends say "I want this for our games".

## Phase 3: iOS app (Follo): recording and live

**Goal (updated 2026-10-12):** live is the main product line. One tap: the phone records the wide 4K video and streams the virtual-camera crop to YouTube; after the game it cuts highlights from the wide recording. Design: `app-design.md`. Edge cases and the feature checklist: `live-edge-cases.md`. Free sideload without the App Store: `../ios/README.md`.

Functional: 4K 30 fps ultra-wide in 3-minute chunks; position check (whole pitch, both goals) before the Go live button appears; Core ML detection and the live camera with a 2 s buffer (validated in `src/live_sim.py`); RTMPS to YouTube via the Live API with Google sign-in; viewer view; thermal, battery and network steps; reconnect to the same broadcast; highlights on the phone.

Non-functional: ≤ 1 minute from opening the app to live; 90 minutes without a stream loss with a power bank; the stream never stops because of a warning; private (unlisted) by default; app runs 7 days per free sideload.

Testing: the live simulator checklists on recorded videos; failure drills (call during the live, airplane mode for 30 s, Home button, low battery); field tests in sun and in the evening with a temperature log every 5 minutes.

Exit: 3 full games streamed in a row with no manual step and no stream loss.

## Phase 3b: cloud processing (later, optional)

The old phase 3 plan, kept for the premium path: upload the wide recording, process in the cloud, better highlights and full video.

**Goal:** take the Mac out of the loop. Place the phone, press "Record", get a link after the game.

Functional:
- iOS app (Kotlin Multiplatform + native camera module): 4K 30 fps from the ultra-wide camera.
- Setup screen: grid, "whole pitch in frame" hint, horizon level.
- Recording in 2–5 minute chunks; each chunk uploads in the background with resume after a drop, then is deleted from the phone.
- Java 21 + Spring Boot backend: account, matches, signed upload URLs, processing status.
- Job queue and processing worker (the phase 2 pipeline) on a free or cheap GPU.
- Push notification "video ready" and a viewing page with a download button.

Non-functional: ≤ 1 minute from opening the app to recording; at most 2 chunks (≈ 1 GB) on the phone; overheating lowers quality instead of stopping; a 90-minute match processed ≤ 1 hour after upload; private videos, deleting a match deletes all files; costs ≤ $5/month.

Testing: backend unit and integration tests (JUnit, Testcontainers); failure drills (airplane mode mid-upload, app backgrounded, phone restarted: no chunk lost); field tests in sun and in the evening (battery, heat, time to video); every release installed via TestFlight and tried on a real game.

Exit: 3 full matches in a row recorded and processed with no manual step and no lost chunk.

## Phase 4: everyday use and beta

**Goal:** check that people use it regularly. No interviews: measure behaviour and reactions to the videos.

Functional: share a match by link (no sign-up for viewers); 3-screen onboarding on phone placement; "report a problem" button with a timestamp; filming consent screen and in-app account deletion (App Store rule); analytics without faces or personal data.

Non-functional: English and Ukrainian UI; ≤ 1 crash per 10 recordings; privacy policy page (App Store and GDPR).

Testing: 5–10 TestFlight testers; metrics over 4 weeks (testers recording ≥ 1 game a week, views per match, shares); 3–5 highlight clips on Reels and Shorts to watch for "what app is this?" comments.

Exit: half of the testers record at least one game a week for a month. Decide here: hobby or business.

## Phase 5: YouTube live

**Goal:** the owner's main goal, a live stream with the virtual camera and no video stored on the phone. The riskiest phase because of heat.

Functional: Google OAuth and stream creation through the YouTube Live API (unlisted by default); the phase 2 model in Core ML with one or two 640 px passes per frame; 1080p crop from 4K, hardware H.264; RTMPS via HaishinKit at 4–6 Mbit/s with adaptive bitrate; optional local 1080p backup recording; on-screen temperature, battery, bitrate and "ball seen" indicators.

Non-functional: ≤ 33 ms per frame (fall back to 25 fps or detection on every other frame); 90 minutes live with a power bank; on overheating reduce fps or bitrate without dropping the stream; automatic reconnect to the same broadcast; option to mute ambient audio (venue music can end a stream through Content ID).

Testing: first at home, streaming a recorded video instead of the camera; endurance test of 90 minutes indoors, in shade and in sun with a temperature log every 5 minutes; compare the live camera with the offline version of the same match.

Exit: 3 streams of 90 minutes with no drop and no overheating; ball in frame ≥ 85% of the time.

## Phase 6: Android, full pitch, highlights

Expansion only after phases 3–5 work, in the order testers ask for.

| Track | Key requirements | Main difficulty |
| --- | --- | --- |
| Android | CameraX, LiteRT, MediaCodec, RootEncoder; a list of tested phones with ultra-wide 4K | Devices behave differently; Google Play requires 12 testers for 14 days |
| 11×11 pitch | Two phones, time sync and stitching in the cloud | Sync and stitching |
| Highlights | Shots, fast attacks, sharp ball movement | Defining a "good moment" without many false positives |
| Scoreboard | Manual score entry from the phone, overlay on video | Convenient UI during a game |
| Basketball | Separate model for the basketball and indoor courts | Indoor lighting, fast passes |

## How the owner uses the product in each phase

| Phase | Before the game | During | After | What the owner gets |
| --- | --- | --- | --- | --- |
| 0–1 | Tripod, stock camera at 0.5×, 4K | Plays | AirDrop to the Mac, run the script, wait 20–60 min | A video that follows play, on the Mac |
| 2 | Same | Plays | Same, plus 15 min of labelling hard frames once a week | Better video, shared in the team chat |
| 3 | Open the app, place the phone with the guide, "Record" | The app records and uploads chunks | "Stop", go home; notification within an hour | A link to the match, no Mac needed |
| 4 | Same; friends do the same at their games | — | Share the link; flag mistakes with the button | Video for the whole team, usage data |
| 5 | Sign in to YouTube in the app, "Go live", power bank | Live stream, friends watch from home | The archive is already on the YouTube channel | Live stream and archive |
| 6 | Android friends record too; two phones on a big pitch | — | Automatic highlights | Full product |

Weekly rhythm: Monday–Friday 1 hour with Claude on the current phase; Saturday game + field test; Sunday 30 minutes reviewing the result and choosing next week's work.
