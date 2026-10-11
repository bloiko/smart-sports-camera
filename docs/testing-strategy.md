# Testing strategy

Three levels: automatic metrics on reference videos (every change), technical tests of the app and backend (every release), and field tests on real games (weekly). From phase 2 on, people's reactions are a fourth signal.

## 1. Reference videos and metrics (automatic)

- Keep a set of golden clips (`specs/datasets.md` lists the videos in use) with manually marked ball positions every 10 frames where possible.
- `follow.py` writes `metrics.json` for every run:
  - `ball_found_share`: share of sampled frames where the tracker accepted a ball;
  - `ball_in_crop_share`: of those, share where the ball is inside the output crop;
  - `players_in_crop_share`: average share of on-field players inside the crop;
  - `cam_speed_mean_px_s`, `cam_speed_max_px_s`: smoothness of panning;
  - `crop_w_min`, `crop_w_max`: zoom range.
- Model evaluation always uses the **last 20% of each video**, which is never used for training, plus **at least one video the model has never seen**. A model trained and tested on one match is not evidence of anything.
- Record results per version and per match in `specs/results.md`. A change that makes a metric worse is not merged without a reason written down.

### Known limits of these metrics

- `ball_found_share` counts accepted detections, not ground truth. Check precision by eye on a contact sheet of random accepted detections (e.g. 12 crops); report it as "N of 12 correct".
- `ball_in_crop_share` is only measured on frames where the ball was found, so it can be high while the camera still misses play.
- No metric captures "a goal was missed". Keep a **goal checklist**: list every goal and shot on target in the test videos with timestamps, and check each one in the rendered output.

## 2. Technical tests (every release)

- Backend: JUnit + Testcontainers (PostgreSQL, S3-compatible storage), API and queue tests.
- iOS: unit tests for upload logic and the virtual camera; a manual checklist of failure scenarios (airplane mode, app backgrounded, restart, low storage).
- Load: process 3 matches at once; check time and cost.

## 3. Field tests (weekly)

- Checklist before the game: charge, power bank, tripod height, framing.
- Game log: pitch, light, weather, phone temperature, battery at start and end, problems.
- After the game: watch the result and write down 3 moments where the camera was wrong, with timestamps. These become new golden clips.

## 4. People's reactions (from phase 2)

- Send videos to players and watch whether they watch to the end, share them, or ask how they were made.
- Post highlights to Reels and Shorts as a cheap interest test.

## Visual checks Claude should always run

- After changing the field mask: render the mask over the median frame for every test video.
- After building a dataset: a contact sheet of random positive labels per match (labels drift when interpolated).
- After rendering: extract 3–4 frames from the output and look at them (black borders, framing, players cut off).
