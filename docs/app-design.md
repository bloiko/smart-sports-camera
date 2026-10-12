# App design (PitchCam, iOS)

Interactive mockup of all screens: https://claude.ai/artifact/YaX8ooupu273H2BhSck7sv (owner's artifact). Skeleton code: `ios/`.

## Principles

- One tap to go live; nothing to configure. The app checks the phone position itself and hides the Go live button until the whole pitch and both goals are in frame.
- During the game the screen is the camera view with one row of small icons (live time, viewers, temperature, battery, free space, upload Mbit/s). Problems turn an icon yellow and show one line of advice; no pop-ups, the stream never stops because of a warning.
- "Viewer view" toggle shows the cropped 1080p frame full screen, exactly what YouTube shows (without YouTube's delay). Leaving the app would stop the camera (iOS), so the stream is checked on another device or through this toggle.
- Screen goes dark after 10 s without touch; the stream continues.
- After "Stop": the YouTube archive link, highlights cut on the phone within ~2 minutes (goals marked, 16:9 and 9:16), one-tap share.

## Phone placement (shown once in onboarding)

- **Landscape**, ultra-wide camera (0.5×). Portrait cannot fit the whole pitch; vertical clips are cut later from the wide frame.
- At the halfway line, behind the touchline, both goals visible.
- 2–3 m high (tripod, railing, fence): the higher, the less players occlude each other and the better the ball is seen.
- Power bank for 90 minutes.

## Screens

1 Google sign-in (once) · 2 onboarding, 3 cards · 3 permissions · 4 my matches · 5 position check · 6 ready (landscape) · 7 live, 7b live with warnings, 7c viewer view · 8 result with highlights · 9 clip (16:9 / 9:16, "not a goal") · 10 settings (YouTube privacy, keep wide recording N days, mute venue audio, storage, privacy/consent, delete account).

## Name

Working name **PitchCam**: "pitch" (the field) + "cam"; short, says what it does, easy to say in Ukrainian and English. Not final: see `decisions.md` and the trademark note in `business-plan.md` before publishing.
