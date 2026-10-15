# Plan: remote control from a second phone, and a 60 s network-drop buffer

Status: proposal, 2026-10-16. Owner asked for a plan that compares solutions and picks the best one.

## 1. Remote control from a second phone

**Goal.** Change the score, red cards, half, clock time, added time and pause without touching the camera phone, which
stands on a tripod (often high, behind a fence). Same actions as the score bar on the live screen.

**Constraints.** Zero budget; prefer own code over third-party services; works at a pitch without venue Wi-Fi; the
camera phone streams over mobile data and must stay in the foreground; the second phone may be an Android phone of a
parent or coach.

### Options

| | A. Web page from the camera phone (hotspot or shared Wi-Fi) | B. Two iPhones with Follo (Multipeer Connectivity) | C. Commands in the YouTube live chat | D. Bluetooth shutter remote (volume keys) |
| --- | --- | --- | --- | --- |
| Second device | Any phone or laptop with a browser | iPhone with Follo installed | Any device with YouTube | A 100–200 UAH clicker |
| Install on the second device | Nothing (scan a QR code) | Follo (free signing: 7-day profile per device) | Nothing | Pairing only |
| Network | Camera phone's Personal Hotspot, or the same Wi-Fi | None: peer-to-peer Wi-Fi/Bluetooth | Internet on both | Bluetooth |
| Range | Wi-Fi, ~30–50 m | ~30 m | Anywhere | ~10 m |
| Latency | < 0.2 s | < 0.2 s | 2–10 s (chat polling) | Instant |
| What it can do | Everything (+ a preview of the score bug) | Everything | Everything, but typed commands | One or two actions (+1 home / +1 away) |
| Depends on | Apple Network framework (system) | Apple MultipeerConnectivity (system) | Google Sign-In, YouTube API quota; commands are visible to viewers | `AVCaptureEventInteraction` (iOS 17.2+, system) |
| Our work | ~1.5 days | ~1.5 days | ~1 day after Google Sign-In | ~0.5 day |
| Main risk | iOS hotspot visibility and reconnects; the Local Network permission prompt | iPhone only; profiles expire every 7 days with free signing | Quota and lag; needs Google Sign-In first | Too few buttons; no minus, no clock |

### Recommendation: A, with D as a later extra

A works with any phone, needs nothing installed and no third-party service, and covers every action. B is cleaner
technically, but it excludes Android and a parent's phone. C is the only option that works from home; it is a good
second step once Google Sign-In exists. D is a cheap backup for "+1" if the second phone is not at hand.

### Design of A

- **Server in the app.** `RemoteServer` on Apple's Network framework (`NWListener`, TCP port 8080), a minimal HTTP/1.1
  handler, no third-party code. Platform-neutral, so it lives in `FolloCore` and is tested on the Mac with `curl`.
  - `GET /` returns one HTML page: CSS and JavaScript inline, about 10 KB.
  - `GET /state` returns JSON: teams, colours, score, red cards, half, clock, added time, paused, live status, battery, temperature.
  - `POST /cmd` applies one command: goal ±, red ±, half, set clock, pause, added ±.
  - `GET /bug.png` returns the current score bug, so the operator sees exactly what viewers see.
- **Updates.** The page polls `/state` every second, which is simple and survives Wi-Fi drops; no WebSocket is needed.
  Every command carries a client id, and the server ignores repeats of the last 50 ids, so a retried tap never scores twice.
- **Access.** A 4-digit PIN per match. It is in the QR code (`http://172.20.10.1:8080/?pin=4821`, plus the Wi-Fi address) and is checked on every command.
  - A wrong PIN gets 403, and after 10 wrong attempts the server stops answering for 1 minute.
  - The page remembers the PIN in the browser.
- **One source of truth.** Commands go into the same `ScoreModel` the live screen uses, on the main thread, so the phone UI and the remote never disagree.
- **App UI.** A "Пульт" button on the live screen shows the QR code, both addresses and the number of connected remotes.
  - Info.plist gets `NSLocalNetworkUsageDescription`.
  - The server starts at Go live and stops at Stop.
- **Remote page.** Built for one thumb on a sunny pitch: large buttons, high contrast. The layout:
  - two team blocks with the team colour, the name, a big score, and − / + buttons for goals and red cards;
  - a clock row with half 1/2, pause, set time and added time;
  - the score-bug preview on top;
  - a red banner when the camera phone is not reachable.

### Steps and checks

1. `RemoteServer` + `RemoteCommand` in FolloCore. Mac test: `follosim remote` serves a fake state, and the checks are:
   - `curl` for every command, a wrong PIN and a repeated id;
   - opening the page in the Mac browser.
2. App wiring: `ScoreModel` as the target, the "Пульт" sheet with the QR code, the Info.plist key. Build and type-check.
3. Phone test on home Wi-Fi: the phone runs the test video, the Mac browser is the remote. Score, cards and clock must
   change in the stream frame (`output.jpg`) within 1 s.
4. Pitch test with the hotspot (owner). Check these:
   - can the second phone join;
   - does it stay connected for 90 min when its screen sleeps;
   - does it rejoin without opening Settings on the camera phone.
   If rejoining needs Settings, the page tells the operator to keep the browser open, and the fallback is the second phone's hotspot.
5. Later: D (volume keys = +1 home / +1 away, with a 3 s on-screen undo); C after Google Sign-In.

## 2. A 60 s buffer for network drops

**Today.** Our virtual camera hands 1920×1080 BGRA frames to HaishinKit, which encodes them. During a drop, `Streamer`
can only keep raw frames: 8 MB each, so 60 s would be 12 GB. It was capped at 2 s after it crashed the phone on 2026-10-15.

**Key fact.** HaishinKit 2.2.5 `RTMPStream.append(_:)` accepts already compressed H.264 sample buffers and sends them as
they are; its own encoder output takes the same path (`RTMPHaishinKit/Sources/RTMP/RTMPStream.swift`, `append`). So we
can encode ourselves and keep a buffer of encoded frames: 4.5 Mbit/s × 60 s ≈ 34 MB.

### Options

| | 1. Raw frames (today) | 2. Raw frames, smaller | 3. JPEG/HEIC frames in memory | 4. Own H.264 encoder, buffer of encoded frames | 5. Re-stream the gap from the 4K recording | 6. No buffer, reconnect only |
| --- | --- | --- | --- | --- | --- | --- |
| Memory for 60 s | 12 GB | 1.6 GB (640×360) | ~270 MB | **~34 MB** (or a file) | 0 | 0 |
| Picture after the drop | — | 360p | Double compression | Same as live | Same | Gap |
| CPU / heat | Low | Low | High (JPEG per frame + re-encode) | Same as today (one hardware encoder) | High (decode 4K + crop + encode while live) | Lowest |
| Complexity | — | Low | Medium | Medium | High | None |
| Viewers miss the moment | Yes, after 2 s | No | No | No | No | Yes |
| Verdict | Not possible | Too ugly | Too heavy | **Best** | Too heavy while live | Fallback only |

### Recommendation: 4, as a delay line

- **Our encoder.** `VideoEncoder` on VideoToolbox (`VTCompressionSession`): H.264 High, 1080p30 or 720p at the low
  bitrate step, a keyframe every 2 s, the bitrate capped with `DataRateLimits`. The adaptive bitrate steps (4500 → 3000 → 2000) move here.
- **Encoded ring.** It holds the last N seconds of encoded frames, 180 s by default (~100 MB). An option keeps it in a file instead, to allow longer outages.
- **Sending.** While live, frames go out in real time, as now.
  - During a drop the ring keeps filling.
  - After reconnecting, sending restarts from the oldest keyframe after the last frame YouTube received. It plays at real
    time, so the viewer delay grows by the length of the drop, but nothing is lost.
  - A "Наздогнати ефір" button and the half-time pause drop the backlog and jump back to live.
  - Faster catch-up (1.25–1.5× real time) is an option only if the measured uplink allows it.
- **Audio.** Version 1 keeps today's live microphone path through HaishinKit, so the drop is silent in the backlog.
  Version 2 encodes AAC ourselves into the same ring.
- **What can break.** Each case and the guard against it:
  - A drop longer than the ring: we send from the oldest keyframe in the ring, and the gap is shown in the log.
  - A new RTMP connection resets timestamps: HaishinKit starts a new stream timeline, and we resend the codec header with the first keyframe.
  - YouTube may end the broadcast after a long silence: this must be measured, see below.

### Steps and checks

1. `VideoEncoder` + `EncodedRing` in FolloCore. Mac test with `follosim`: encode match 2 through the camera path to the
   ring, write the ring to an `.mp4`, and check that it plays, starts at a keyframe and runs at about 4.5 Mbit/s.
2. Feed the encoded frames to `RTMPStream.append` in `Streamer`; remove the raw-frame buffer.
3. **Local RTMP server on the Mac instead of YouTube.**
   - Run `ffmpeg -listen 1 -i rtmp://0.0.0.0:1935/live/test -c copy out.flv`; the phone streams the test video over home Wi-Fi.
   - Check the picture with the score bug, the bitrate, and that there are no gaps.
   - Then turn the phone's Wi-Fi off for 10, 30 and 60 s: `out.flv` must have no missing frames and play continuously.
4. YouTube (private, after the channel is enabled): the same drops of 10, 30, 60 and 120 s. Measure how long YouTube
   keeps the broadcast alive without data, and what viewers see.
5. Memory, heat and battery over 90 min with the test video. The target is under 800 MB, thermal state "fair" or better.

## Order

1. Buffer steps 1–3. A drop at the pitch is the bigger risk for the first real broadcast, and the local RTMP test also
   checks streaming for the first time ever.
2. Remote steps 1–3 (Mac, then phone on home Wi-Fi).
3. With the owner: the remote at the pitch over the hotspot, and the buffer on YouTube.
