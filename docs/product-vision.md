# Product vision

A phone on a tripod becomes an automatic camera operator: it films the whole pitch wide, finds the ball and the players, and produces a broadcast-style video (or a live stream to YouTube) that follows play. No dedicated hardware and no person behind the camera.

## Problem

- Amateur players want video of their games, but there is rarely anyone to film them.
- Dedicated AI sports cameras (Veo, Pixellot, Trace, Hudl Focus) cost around $1,000 plus a monthly subscription and target clubs, not pickup games.
- Phone-based alternatives either need extra hardware (gimbals, clip-on lenses), work only on iPhone, or do not stream live.

## Solution

1. The phone records the whole pitch with its ultra-wide camera (4K, static, mounted high).
2. Software detects players and the ball in every sampled frame.
3. A "virtual camera" crops a 1080p window out of the 4K frame and pans and zooms smoothly to follow play, like a TV broadcast. Because 1080p fits inside 4K, the crop loses no resolution.
4. Output modes:
   - **Recorded mode (built first):** record → upload chunks to the cloud → process → finished video link.
   - **Live mode (later):** on-device detection and cropping → RTMP stream to YouTube; YouTube also stores the archive, so the phone keeps nothing.

## Target users

- **Start:** the owner and players like him: amateur football (5×5, 7×7, 11×11), later basketball.
- **Later:** amateur leagues and tournaments, kids' academies and parents, coaches who review games.

## Positioning

"Only a phone and a tripod": zero hardware, iOS and Android, subscription priced like a streaming service. See `research/competitors-and-market.md`.

## Goals

1. **Phase-one goal:** learn (computer vision, mobile, video) and build something the owner actually uses every week.
2. **Later:** decide after the prototype whether this stays a hobby or becomes a business.

## Non-goals (for now)

- Volleyball and other fast small-ball sports: the ball is too fast for the first version.
- Face recognition or player identification by face: legal risk (GDPR, BIPA, COPPA). Identify players by jersey number if needed.
- Dedicated hardware.
