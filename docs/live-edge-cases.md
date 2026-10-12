# Live streaming: edge cases and how the app handles them

Key fact: **iOS stops the camera as soon as the app leaves the screen.** Most cases below are about keeping the app in front and recovering the stream within seconds when it was not.

## Phone and iOS

| Case | What happens | Handling |
| --- | --- | --- |
| Incoming call | Full-screen call stops the camera; stream and recording stop | Before Go live the app asks to enable a Do Not Disturb focus and warns if it is off. If a call still comes: recording is in 3-minute chunks, so only the current one is cut short; on return the stream reconnects to the **same broadcast** (YouTube accepts the same key again), viewers see a 10–30 s pause, not the end |
| Messages, push banners | Do not stop the camera | Nothing; Do Not Disturb hides them too |
| User leaves to watch the stream on YouTube | Camera stops | "Viewer view" inside the app; a hint before leaving: "the stream stops, watch on another phone" |
| Screen auto-lock | Lock = background = camera stops | Auto-lock disabled during the live; the app dims the screen after 10 s, a touch restores it |
| Accidental Home / swipe | Background | Suggest Guided Access in onboarding; fast reconnect |
| App crash | Everything stops | Chunks are already on disk; next launch offers "Resume the live?" with the same broadcast; crash logs collected |
| Phone reboot | Same | Same; after ~2 min without data YouTube ends the broadcast, then a new one is created and the new link is shared |
| Overheating | iOS throttles, then kills the camera | Steps: 42 °C → 25 fps, 44 °C → 3 Mbit/s, 46 °C → detection every 3rd frame, 48 °C → "move to shade". The stream stops only when iOS stops the camera |
| Battery 20% / 10% / 5% | Dies mid-game | Yellow then red icon and "power bank" hint; at 5% the broadcast is ended cleanly (archive kept) and the chunk is finished |
| Out of storage | Recording stops | Before start: 90 min of 4K HEVC ≈ 15 GB; offer to delete old wide recordings. During the game the stream has priority: at 1 GB free only the recording stops |
| Tripod moved / phone taken | Pitch leaves the frame | Position check every 10 s: a sudden field-mask change shows a "camera moved" icon; goals are re-estimated |
| Rain, sun in the lens | Detector goes blind | Camera falls back to players or pitch centre; hint shown |

## Network and YouTube

| Case | Handling |
| --- | --- |
| Internet drops 10–60 s | In-memory frame buffer up to 60 s; reconnect to the same RTMPS key every 2 s; YouTube keeps the broadcast ~2 min without data |
| Weak uplink | Adaptive bitrate 4.5 → 3 → 2 Mbit/s (720p); the icon turns yellow; never stop |
| No internet from the start | "Go live" becomes "Record only"; highlights from the recording after the game |
| Mobile data disabled for the app | Checked before start, with a hint |
| Google token expired | Silent refresh; if that fails, sign-in is asked 10 s before start |
| Channel not allowed to stream (24 h after enabling, or a strike) | Checked before the game (`liveBroadcasts.list`): "Enable live streaming on YouTube, it takes up to 24 h" |
| YouTube API quota (10 000 units/day, ≈ 150 per broadcast) | Only a problem with hundreds of users; then an API proxy |
| Content ID for venue music | "Mute audio" option; warning at first start |
| Broadcast deleted or privacy changed during the game | Stream continues (recording too); error shown; upload of the recording offered afterwards |

## The game

| Case | Handling |
| --- | --- |
| Half-time, players leave | Empty pitch → wide centre view, "pause" on screen; the stream is not cut |
| People walking in front of the tripod | Field mask ignores everything off the pitch (already works) |
| Two matches in a row, overtime | No limit up to YouTube's 12 h archive limit; chunks stay 3 min |
| Few players, one-sided game | Goal mode by players; unvisited goal mirrored through the halfway line (already works) |
| "Stop" pressed by accident | Hold 1 s to stop |

## People

| Case | Handling |
| --- | --- |
| Someone does not want to be filmed | Unlisted by default; "delete broadcast" in one tap; consent screen in onboarding |
| Children in frame (YouTube may remove streams of minors without an adult) | Warning in onboarding; the recording stays on the phone |
| Phone stolen from the tripod | Nothing technical; hint "keep the tripod in the team's view"; the phone holds only video |

## Feature checklist (phase 5, ordered by priority)

Status: ☐ not started, ◐ in progress, ☑ done.

**Critical**
- ◐ 8. RTMPS streaming (HaishinKit, code) and Core ML (not started) virtual camera on the phone
- ☑ 1. Reconnect (code in `Streamer.swift`, untested on a phone) to the same broadcast after a call, network loss or crash
- ☑ 2. Frame buffer (code, untested) up to 60 s during a network drop
- ☑ 3. "Resume the live?" (code, untested) after a crash or reboot
- ◐ 4. Thermal steps (fps and bitrate; sparser detection waits for Core ML) (25 fps → bitrate → sparser detection)
- ☑ 5. Adaptive bitrate (code, untested) 4.5 → 3 → 2 Mbit/s
- ☑ 6. Battery warnings (code, untested) at 20/10%, clean end at 5%
- ◐ 7. Pre-start checks (storage, battery, heat; YouTube rights and token pending): storage, channel live rights, Google token, mobile data

**Important**
- ☐ 9. Do Not Disturb request before Go live
- ☐ 10. Viewer view in the app; hint before leaving
- ☑ 11. Screen dims after 10 s, touch restores (auto-lock off done; dimming pending)
- ☑ 12. Hold 1 s to stop
- ☐ 13. Stream over recording when storage is low
- ☐ 14. Guided Access advice in onboarding

**Nice to have**
- ☐ 15. Tripod-move detection and goal re-estimation
- ☐ 16. Pause mode on an empty pitch
- ☐ 17. Mute audio option
- ☐ 18. Delete broadcast, consent screen, minors warning
- ☐ 19. Crash logs

**Later**
- ☐ 20. API proxy for YouTube quota
- ☐ 21. Record-only fallback without internet (partly: no token → record only)
