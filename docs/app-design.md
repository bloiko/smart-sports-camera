# App design (Follo, iOS)

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

## Status of the screens (2026-10-12)

In code (not run on a phone yet): 1 (placeholder sign-in), 2, 3, 4, 5 (position check inside the setup screen), 6, 7, 7b, 7c (viewer view), 8, 9 (play and share per clip; no "not a goal" button yet). Missing: 10 settings.

## Scoreboard (2026-10-15)

The stream shows a TV-style score bug in the top left corner of the 1080p picture: colour stripe of each team, short name (12 characters), score, match clock. Before the game the "Команди" row opens a sheet with the two names, 10 jersey-colour swatches and a show/hide switch; names and colours are kept for the next match. During the game the live screen has a score bar with big − and + per team (a wrong tap is undone with −), and the "Час і тайм" button opens a sheet to pick the half (1st/2nd), the half length (10–45 min) and any clock time (late arrival), with pause/continue for half-time; switching to the 2nd half sets the clock to the half length (45:00). The bug shows "1Т 23:15". A new Go live starts at 0:0; resuming after a crash keeps the score.

## Name

Working name **Follo** (follow the game): short, reads the same in Ukrainian and English, works as a verb, neutral across sports. Motto on the splash screen: "Follo the match." Known clashes to check before publishing: several unrelated "Follo" apps in the stores (construction logistics, finance, healthcare), the Follo region in Norway and its football club, the follo.com domain. Store title should be "Follo: AI sports camera"; domain candidates follo.cam, getfollo.com. Previous working name PitchCam was dropped because of PitchCom/PitchVision/Pitchcam in sports.
