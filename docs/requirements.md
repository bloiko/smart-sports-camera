# Requirements

Stable product requirements. The current implementation status of each item lives in `../specs/status.md`.

## Functional requirements

| ID | Requirement | Stage |
| --- | --- | --- |
| F1 | Load a game video (file from the phone or a Mac) | MVP |
| F2 | Detect the ball in every sampled frame | MVP |
| F3 | When the ball is not visible, predict its position or follow the cluster of players | MVP |
| F4 | Crop a 1080p 16:9 frame that moves smoothly without jitter | MVP |
| F5 | Export a finished MP4 | MVP |
| F6 | Optional vertical 9:16 output for Reels and Shorts | MVP |
| F7 | When the ball is near a goal, keep both the ball and the goal mouth in frame (shots and goals must never be missed) | MVP |
| F8 | iOS app: 4K recording from the ultra-wide camera, with a setup guide for placing the phone | v1 |
| F9 | Record in 1–5 minute chunks and upload them to the cloud in the background | v1 |
| F10 | Cloud processing, a "video ready" notification and a viewing link | v1 |
| F11 | User account and a list of the user's matches | v1 |
| F12 | Live stream to YouTube over RTMP with on-device processing | v2 |
| F13 | Automatic highlights (goals, attacks) and short clips | v2 |
| F14 | Scoreboard: score and time burned into the video | v2 |
| F15 | Share a match with the team, comments, player tags | v3 |
| F16 | Support for several sports (separate models per ball type) | v3 |

## Non-functional requirements

The phone sets the hardest limits: battery, heat and mobile data. Numbers are starting targets.

| Category | Requirement (target) |
| --- | --- |
| Tracking quality | Ball inside the crop ≥ 90% of play time; camera motion looks like a human operator |
| Goal coverage | 100% of shots on goal and goals visible in the output |
| Video quality | Output 1080p 30 fps; source 4K 30 fps from the ultra-wide camera |
| Offline processing speed | A 90-minute match processed in ≤ 30 min in the cloud or on a Mac |
| Live latency (v2) | On-device processing ≤ 33 ms per frame (30 fps) |
| Battery | 90-minute recording with a power bank; a warning without one |
| Heat | Works at +30 °C; on overheating lower quality first, never stop recording |
| Storage | At most 1–2 chunks (≈ 1–2 GB) on the phone at once; a 4K match (≈ 15–40 GB) lives in the cloud |
| Network | Uploads resume after a drop; live 1080p needs a stable ~5–6 Mbit/s uplink |
| Reliability | A failed upload or processing step never loses footage; retries |
| Cost | Cloud cost per match known and below the subscription price |
| Security | Videos private by default; access by link or from the account |
| Privacy | People on video, including children: consent, deletion on request, EU storage (GDPR) |
| Usability | ≤ 1 minute from opening the app to recording, no settings |
| Devices | Start: iPhone 15 and newer; then iPhone 12+ and mid-range Android with ultra-wide 4K |
| Licensing | Every model and dataset used in the product must allow commercial closed-source use |

## Owner constraints

See `decisions.md` for the full list. Key ones: solo developer with Claude, about 1 hour a day, zero budget until a convincing proof of concept, MacBook Air M1/M2 8 GB, iPhone 15, global market (English UI from day one).
