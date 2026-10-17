# Ideas under discussion (nobody is working on them)

**Status: talk only.** These ideas came up in conversations with the owner on 2026-10-17 and 2026-10-18. None of them is
planned, scheduled or started, and nothing here is a decision. When the owner picks one, it moves to `specs/backlog.md`
with a plan, and the decision goes to `decisions.md`.

The owner's rules apply to every idea that is ever built:
- everything in the product is our own code (Apple system frameworks allowed);
- every new flow can be switched off;
- every change is compared before and after.

## 1. Features that could draw new people

Effort: S about an evening, M 2–3 evenings, L a week or more.

### For parents (the largest audience)

| Idea | What it is | What exists already | Effort |
| --- | --- | --- | --- |
| "My player" | Parents enter a shirt number and kit colour before the match; after it they get a personal reel of that player's touches, shots and goals, vertical for Instagram | Player tracking, team colours, highlight cutting; shirt-number recognition is missing | L |
| Voice commentary in Ukrainian | "Shot! Goal! Dynamo lead 1:0 in the 23rd minute" from detected events, spoken by Apple's system speech synthesis | Goals, kick-offs and half-time are already detected | M |
| "The match in 3 minutes" and auto-publishing | A ready reel right after the whistle, with the score bug and team names, plus vertical clips for TikTok, Reels and Shorts | Highlights exist; styling and publishing are missing. Uploads from an unverified Google project may be forced private | S–M |

### For coaches and clubs

| Idea | What it is | What exists already | Effort |
| --- | --- | --- | --- |
| TV-style statistics | Possession by team, shots, heat map per player, distance, sprints | Player positions, team colours, pitch geometry | M |
| Tactical top view | Moving dots on a pitch diagram; a small window in the stream, full replay after the match | Same as above plus a pitch homography | M |
| Voice markers and telestration | The coach says "Follo, moment" and gets clips; draws arrows on a paused frame on a tablet | Highlight cutting | M |

### For leagues and tournaments

| Idea | What it is | What exists already | Effort |
| --- | --- | --- | --- |
| League mode | All league matches on one channel, automatic table, top scorers from the score bug, a tournament page with live streams | Score bug, YouTube API | M (mostly server and web) |
| Season profile of a player | Best moments, goals and statistics over a year, e.g. to show to an academy | Needs "My player" | M |

### For sponsors and broadcast quality

| Idea | What it is | What exists already | Effort |
| --- | --- | --- | --- |
| Advertising on the pitch | A sponsor banner drawn on the grass or a board with the correct perspective, so clubs can sell the space | Pitch geometry | M |
| Instant goal replay in the stream | A few seconds after a goal, a closer replay from the 4K recording | 4K recording, goal detection, close-up camera | L |

### Wider

| Idea | What it is | Effort |
| --- | --- | --- |
| Other sports | Futsal, handball, basketball, field hockey: the same engine of pitch, people and ball | M per sport |

### Smaller ideas from the same talks

- A broadcast and its link created the day before, to share with parents in advance.
- "Share to chat" with a ready message.
- A "Goal? +1" hint for the score.
- A clock that starts itself from the kick-off.
- Goal chapters in the YouTube description.
- A thumbnail with the final score.
- A season playlist per team.
- A remote control on a second phone.
- The stream key in the Keychain.

## 2. Several iPhones on one pitch

### Four cameras around the pitch, in levels

- **Level 1: several cameras, no live switching.** About 3–4 weeks, low risk.
  - Every phone records.
  - After the match the recordings are aligned on one timeline.
  - Goal replays from the camera behind the goal; highlights from the best angle.
- **Level 2: two cameras live (wide + behind the goal).** About 1.5–2 months, medium risk.
  - On attacks near that goal the stream switches to the goal camera.
  - The main risk is the link between phones over about 50 m, which can only be tested on a real pitch.
- **Level 3: four cameras, full automatic direction.** 3+ months, high risk.
  - Automatic cuts, replays from several angles, one ball track fused from all cameras.
  - Heat and battery of the directing phone become the real limit.

Problems to solve:
- **Network on the pitch.** MultipeerConnectivity, or a small travel router on a power bank at the halfway line.
- **Clock sync** to a few milliseconds.
- **Per-camera calibration** to pitch coordinates.
- **The director's rules:** best view of the ball, shots at least 4–6 s, goal camera for attacks and set pieces.
- **Power for every phone.**
- **Joining by QR code**, with guided placement.

Side effect: several views would also fix the main tracking problem. When players hide the ball from one camera,
another camera sees it.

### The "ideal" 11-a-side setup with five iPhones

| Phone | Where | Lens | Role |
| --- | --- | --- | --- |
| C1 "Overview" | Halfway line, near touchline, as high as possible (5–8 m) | 0.5×, 4K | Sees the whole pitch, finds ball and players, writes the full 4K recording, fallback stream |
| C4 "Tele" | Next to C1 on a DockKit motorised stand | 1× / 2× | The main shot: the motor turns to where C1 sees the ball, the lens zooms |
| C2, C3 "Goals" | Behind each goal, 3–4 m | 1× | Attacks, corners, free kicks, goals, replays |
| D "Director" | With the owner, not filming | — | Receives all cameras over local Wi-Fi, cuts, adds the score bug, commentary and replays, streams to YouTube |

Supporting pieces:
- **Shared pitch map and clock.** All cameras map what they see to pitch coordinates on one shared clock.
- **Stream delay.** The stream runs 2–3 s behind so the director can cut in time.
- **Local 4K recordings.** Every phone records 4K locally, so a dropped camera or a lost network never stops the stream.
- **After the match:** multi-angle replays, better statistics, "My player".

Path:
1. One camera (today).
2. Add the DockKit tele camera.
3. Add goal cameras, recording only.
4. Add the director and live switching.

## 3. Two phones: wide orchestrator plus a motorised tele phone

- **Phone A, the orchestrator.** Ultra-wide camera, our tracker and networks, the 4K wide recording. It decides
  where to look and how far to zoom.
- **Phone B, the operator.** Mounted directly under A on an Apple DockKit stand, lens 1×/2× (3× on Pro phones). It
  turns and zooms on A's commands and streams to YouTube with the score bug.

Why it is attractive:
- **Only commands travel** between the phones (bytes, 10–30 times a second), over MultipeerConnectivity or Bluetooth.
- **Easy calibration.** Both phones share one viewpoint, so mapping a point in A's frame to B's pan and tilt angles
  is simple. B can sweep once at start for automatic calibration.
- **Load is split:** detection and recording on A, encoding and streaming on B.
- **Fallback.** If B misses the ball, show A's virtual camera for a few seconds; video from A to B is easy at 1 m.
- **B can be an old iPhone.**

Hard parts:
- **Motor latency.** The motor cannot look 2 s ahead like the virtual camera. A must predict the ball 0.3–0.5 s
  ahead, ramp smoothly, and fall back on very fast switches of play.
- **Motor speed.** It depends on the stand.
- **Calibration drift** from wind and bumps. Re-align B against A periodically.
- **B's own exposure and focus.** Lock focus at infinity and keep exposure changes smooth.
- **A DockKit stand costs about $100–200** (e.g. Insta360 Flow 2 Pro, Belkin). Check DockKit support before buying.

Path, if it is ever chosen:
1. Simulate a "virtual motor" with real limits on the Mac, on recorded wide footage.
2. Stand and pan only.
3. Add zoom.
4. Add the fallback to A's virtual camera.

## 4. Single-phone quality options (also only discussed)

The half-pitch 1× mode is the one item from this discussion that exists: a test mode, 2026-10-18.

The rest is talk only:
- **A higher mount** (3–5 m): the cheapest quality gain.
- **Automatic choice of 1× when the whole pitch fits.**
- **A DockKit stand for a single phone:** physical pan with 1×/2× instead of the virtual camera.
- **Two cameras of one phone at once:** ultra-wide to find the ball, 1× for the picture.

## Reference: what the "good-looking" amateur stream used

Owner's example: <https://www.youtube.com/watch?v=mQqBYK4ocxI>, Volodymyr district championship, looked at on
2026-10-17.
- **Camera:** real optical zoom with a physical pan, from 2–4 m just behind the running track at the halfway line.
  Either a human operator or a phone on an auto-tracking stand.
- **Stream:** 1080p with a streaming-app score bug.
- **Comparison:** Veo and Pixellot instead use a panoramic virtual camera, like Follo.
