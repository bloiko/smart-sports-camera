# Owner profile and decisions

Context for anyone (or any AI chat) picking up the project. Append new decisions at the bottom of the decision log with a date.

## Owner profile

- Senior Java developer based in Ukraine; builds this solo together with Claude.
- Hardware: MacBook Air M1/M2 with 8 GB RAM, iPhone 15.
- Time: at least 1 hour a day, more when needed.
- Played a lot of football; also basketball, volleyball, table tennis and padel.
- Personal pain points that started the idea: no one to film games, no camera that follows the ball; also the cost of games and travel, finding players and equipment (possible future products).
- Has a YouTube channel for testing streams.

## Answers to the 20 kick-off questions (10 Oct 2026)

| Topic | Answer | Resulting decision |
| --- | --- | --- |
| Sport | Football of all formats, basketball; volleyball probably too fast | Start with football 5×5 / 7×7, then 11×11 and basketball; volleyball postponed |
| Venues | Different places | Test day and evening light |
| Output | Full match and highlights; landscape (YouTube) | Full 16:9 first, highlights next |
| Who sets up the camera | Anyone | One-tap start, no settings |
| Scoreboard | Later, but interesting | Phase 6 |
| Tripod | Will have one | Target height 2–3 m |
| Mobile data at pitches | Stable 4G/5G | Live streaming is realistic |
| Phone storage | Would rather not depend on it | Long term: stream to YouTube as free storage |
| Mobile platforms | iOS and Android | Kotlin Multiplatform + native modules for camera, ML, RTMP |
| Cloud | Free first, paid only if justified | Free tiers until the PoC convinces |
| Budget | Zero until the value is proven | PoC costs nothing except a tripod |
| Live streaming | The goal, but can come later | Phase 5; architecture allows it from the start |
| Team | Solo with Claude | — |
| User interviews | Does not want to do them | Validate by publishing videos and measuring reactions |
| Market | Whole world | English UI from day one; GDPR by design |
| Hobby or business | Decide after the prototype | Decision point after phase 4 |

## Decision log

| Date | Decision | Why |
| --- | --- | --- |
| 2026-10-10 | Product idea: phone-only smart sports camera with a virtual camera that follows play | Owner's own pain; useful even to one user; teaches CV, mobile and video |
| 2026-10-10 | Recorded mode before live mode | Offline processing can smooth in both directions and use heavier models; live is limited by heat |
| 2026-10-10 | Prototype in Python, backend in Java/Spring later | CV ecosystem is in Python; backend is the owner's strength |
| 2026-10-10 | Bootstrap on public panoramic footage (SoccerTrack-style university matches) until own iPhone footage exists | Unblocks phases 1–2 immediately |
| 2026-10-10 | Self-training on pseudo-labels instead of manual labelling | Owner asked Claude to do everything without manual work |
| 2026-10-10 | Combine several ball models (`merge_balls.py`) | Models fail in different places; the union beat each model alone |
| 2026-10-11 | Make the pipeline stadium-independent (adaptive field mask, auto depth, crop inside image content) | Match 3 had a different stadium, resolution and light |
| 2026-10-11 | Repository documentation: stable docs in `docs/`, changing state in `specs/`, all in English | Reuse across chats and tools |
| 2026-10-11 | No manual steps for the user: goals (and later the pitch) are found automatically; a "tap both goals" setup screen was rejected | Owner: the user should not do anything by hand |
| 2026-10-11 | Goal finding by own computation (tips of the play area from player positions); open-vocabulary detectors (OWLv2, Grounding DINO) rejected | Owner does not want third-party models or services with their own licences; the player-based method found all 6 test goals within ~60–80 px |
| 2026-10-11 | Virtual camera v0.3: ball and goals as hard constraints, goal-area mode triggered by the ball or by an attack | Shots and goals must never leave the frame; accepted cost: players in frame fell from 64–71% to 56–63% |
| 2026-10-11 | Drop ball detections that match the static background (`ball_bgdiff.py`) | Owner spotted a logo letter on the grass counted as the ball |
| 2026-10-11 | Run the pipeline on the owner's M1 Mac with the Apple GPU (MPS) instead of the cloud sandbox | Detection about 3–4× faster; no upload limits for videos |
| 2026-10-11 | Recognise goals by the kickoff that follows them (teams by jersey colour, each team in its own half) | Own computation on data we already have; reliable signal on both test goals, while ball-based signals miss goals when the ball is not detected |
| 2026-10-11 | Default sampling step 15 (~1.7 frames/s), half precision on GPU, hardware video encoding, debug video only on request | 3× faster with identical checklist, goal and highlight results; sparser steps (30+) start producing false kickoffs |
| 2026-10-11 | Live streaming is the main product line: the phone records the full wide video and streams the virtual-camera crop to YouTube in real time; post-processing (highlights, better full video) comes from the wide recording | Owner's goal; YouTube's own delay allows a look-ahead buffer |
| 2026-10-11 | Live camera with a 2 s look-ahead buffer | Simulator on 3 matches: 2 s passes all 7 checklist events and is smooth; 0–1 s fail events; 3–5 s add nothing |
| 2026-10-11 | Live goals: mirror the goal of a side play has not reached through the halfway line | Players alone cannot find a goal nobody stands near in the first minute; mirroring cut the early error from ~900 px to 54–125 px in 2 of 3 matches |
| 2026-10-11 | Ball detector: keep YOLO for now; whether "own computation only" also applies to it is an open experiment (backlog) | Owner wants to decide later; nothing changes until then |
| 2026-10-12 | Working app name **Follo**, motto "Follo the match."; final name decided later after store, trademark and domain checks | Short, bilingual, verb-like; PitchCam clashed with existing sports products |
| 2026-10-12 | Live camera is strictly causal with a 2 s buffer (`src/live_cam.py`): nothing later than f + 2 s is used, field mask and halfway line from the first 10 s | The batch simulator looked up to 4 s ahead in places; the phone cannot. Checklist still 7/7 with the honest version |
| 2026-10-12 | Virtual camera on the phone = `ios/FolloCore`, a Swift port kept line-for-line in sync with `live_cam.py`, verified on the Mac with `follosim` (identical path) | Catches logic bugs before the owner has Xcode; every camera change is measured in Python and replayed in Swift |
| 2026-10-12 | Core ML models exported with NMS inside (players 1280×672, ball 640×640, fp16) from a separate venv with torch 2.7 | torch 2.14 + coremltools 9 fail; NMS in the model keeps the Swift side small |
| 2026-10-12 | Detection on the phone uses the AGPL YOLO weights for the prototype only; the own-detector question stays open (backlog P1 item 5) | Unchanged owner decision |
| 2026-10-12 | Highlights on the phone reuse the live camera path and jersey colours sampled during the live; no second detection pass over the recording | A 90-minute 4K re-detection would take longer than the game on a phone; the live path already holds the goal-mode episodes and balls |
| 2026-10-12 | Live goals: accept outward moves only with a small change in y (`dy_max` 60 px) | Corner kicks pulled the estimate 200–350 px to the corner flags late in every match; the guard keeps it within 68 px |
| 2026-10-12 | Pitch memory: goals of the previous match on the same pitch are the prior for the next one; no earlier estimate without memory | Early estimates (15–20 s) are 300–900 px off and break the checklist; a prior gives goal mode from the first second |
| 2026-10-12 | The GOAL label from the kick-off alone is not trusted on the phone until another cue exists | No statistic of team separation had a margin on the 3 test matches |
| 2026-10-15 | Black camera in the app was caused by Xcode Device Hub mirroring the phone screen (iOS privacy), not by the camera code; the app now detects `UIScreen.isCaptured` with a flat black frame and tells the user; camera tests go through on-device debug logs, not Device Hub | Experiment: `screenCaptured true` ↔ Y=16 sd 0.0, `false` ↔ normal image |
| 2026-10-15 | Position check looks only at the far quarter of the pitch (row ends, 10th/90th percentile, margin W/33) | The old rule "grass touches the frame side" failed m1 and m2 themselves: near the camera the grass reaches the sides of a wide lens; the goals stand at the far corners |
| 2026-10-15 | Home tests on the phone use a debug-only test-video source instead of filming the Mac screen | Filming the screen adds glare, bezels and a stretched picture and cannot be compared with `live_sim.py`; the file source gives the same input on the phone and on the Mac |
| 2026-10-15 | A lost ball is re-acquired far from players or the play only when it flies; a still one is black-listed after three looks | Core ML finds real spare balls beyond the touchline and ball boys; the camera drove to them. Jumps fell to ~1.6% on all 3 matches with the checklist unchanged |
| 2026-10-15 | The phone builds the pre-game environment at full resolution | Kernels are sized for full resolution; at 1/4 the mask grew to 90% of the frame and the crop was 20% wider. Full resolution takes 3.2 s on the iPhone 15 |
| 2026-10-15 | Swift skips the extra picture AVAssetReader emits for an empty edit; Core ML resamples like cv2 (bicubic, no colour management) | Frames were shifted by one against Python in matches 2 and 3; with alignment and cv2-like resampling the ball model agrees 100% with Python on the same ROIs |
| 2026-10-15 | On 16:9 frames the player tiles cover only the pitch band at the model aspect ratio | The fixed 1280×672 Core ML input shrank full-height tiles of a 4K phone frame to 0.31; the band tiles give +40–75% players at the same cost |
| 2026-10-16 | Goal mode uses the goal-zone player count averaged over 1 s and keeps its chosen goal unless the other is clearly ahead | The instant count jumped 1–5 and equal counts flipped the camera to the other goal: twitches in match 3 fell from 2.5 to 0.3 per minute, checklist unchanged |
| 2026-10-16 | The finished app contains only our own code and our own model weights: own detectors (FolloNet-P, FolloNet-B, trained from scratch), own RTMP(S) client instead of HaishinKit, own OAuth instead of the Google Sign-In SDK. Apple system frameworks and Mac dev tools (PyTorch, OpenCV, ffmpeg, coremltools) are allowed; third-party models only as a temporary label teacher on the Mac | Owner's rule: nothing under another software licence in the product. Plan: `docs/detector-licence-plan.md` |
| 2026-10-16 | UI is checked on the simulator by XCUITest (`ios/ui_test.sh`) before a build goes to the phone | The STOP-restarts-the-broadcast bug reached the owner; the simulator runs the real app on the test video, so screens and flows are checked and screenshotted on the Mac |
| 2026-10-16 | GO LIVE is refused inside `go()` until the position check passes (pitch found, far corners with the goals in frame); test runs (test video or launch from the Mac) start the stream muted | Owner's rules: never broadcast from the camera without the pitch and goals; sound always off in tests. The check in `go()` covers GO LIVE, "Відновити ефір" and `--golive` alike. Real goals are found only during play, so before the start the check is on the goal corners being in frame |
| 2026-10-16 | Broadcasts start unlisted; public only from a release build, by the owner, with confirmation; debug builds cannot go public | Owner: test broadcasts must never be public; the switch to public happens only when he has checked everything |
| 2026-10-17 | GO LIVE starts the recording first; the stream target is fetched separately with retries | Owner: a YouTube error or an expired sign-in must never stop the recording of a match |
| 2026-10-17 | Stream bitrate follows the bytes the ingest server acknowledges (own BitrateAdvisor), no third-party speed test | Owner: no point pushing 4.5 Mbit/s into a 3 Mbit/s upload. Measured on the real path to YouTube; on the Mac the delay stayed at 1 s instead of growing to 56 s on a 2.5 Mbit/s link |
| 2026-10-17 | Half-time shows a card in the stream and turns camera, detection and recording off | Owner's idea; the phone cools down during the break and viewers see the score instead of an empty pitch |
| 2026-10-17 | MetricKit reports saved on the phone and shareable | Explain trips to the background without a cable; system framework, allowed by the "everything own" rule |
| 2026-10-17 | Automatic catch-up from 1.5 s behind (was 5 s) | A short reconnect left the stream 3.9 s behind for good; now back to 1 s within about 15 s, no frames lost (Mac) |
| 2026-10-17 | A background task keeps the stream connection while the app is briefly off screen during a match (`--no-bg-task` to compare) | A one-second swipe out made iOS close the socket (phone log 2026-10-16). The simulator does not reproduce it: before/after on the phone |
