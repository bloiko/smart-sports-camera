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
