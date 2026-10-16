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

## Scoreboard (2026-10-15, design chosen 2026-10-16)

The stream shows a TV-style score bug in the top left corner of the 1080p picture. Owner's choice among three proposals (`follosim scoreboards DIR` renders them all): a red clock block on the left with the half ("2Т 67:42"), then the full club names with a colour stripe each and the score in a white box. Added time appears as a white "+3" tab under the clock; while the clock is paused the block says "ПЕРЕРВА"; after a "+" a banner "ГОЛ! <club>" in the team colour shows for 6 s under the bug. Red cards (2026-10-16): a small red-card button per team on the live screen (− removes a wrong one), up to 5 cards; on the bug small cards over the club name (`RedCardStyle.above`, chosen by the owner 2026-10-16; `tab`, `count`, `beside` kept for comparison) and a red banner "ЧЕРВОНА КАРТКА <club>" for 6 s. Code: `FolloCore/ScoreboardStyles.swift` (`ScoreStyle.classic`, `fullNames`), app `ScoreViews.swift`.

Before the game the "Команди" row opens a sheet with the two names, 10 jersey-colour swatches and a show/hide switch; names and colours are kept for the next match. During the game the live screen has big − and + per team, a pause button and "Час і тайм": half (1st/2nd), half length (10–45 min), any clock time (late arrival), added time (0 = hidden), pause for half-time; switching to the 2nd half sets the clock to the half length and clears added time. A new Go live starts at 0:0, 1st half; resuming after a crash keeps everything.

## Matches on the phone (2026-10-16)

Each match is recorded into its own folder `Documents/matches/match_<date-time>/` with `chunks/` (4K, 3-minute files,
10 s fragments) and `highlights/` (clips).
- **Nothing is overwritten.** Before this, every Go live restarted at `chunk_001` in one shared folder and overwrote the
  previous match; that is how the owner's first stadium recording was lost.
- **Resume.** After a crash, resuming the broadcast continues the numbering in the same folder.
- **The record appears at Go live**, marked "запис перервано" until Stop, so a recording cut by a crash or a kill is
  still listed and playable up to its last fragment.

Tapping a match in "Мої матчі" opens the match screen:
- **"Переглянути":** the whole recording plays in one go, from all the chunks.
- **"Зберегти у Фото":** the chunks are joined into one video without re-encoding, then saved; if there is not enough
  space for the joined copy, they are saved part by part.
- **The highlight clips:** play and share.

The result screen after Stop has the same save button. The app asks for "add to Photos" permission
(`NSPhotoLibraryAddUsageDescription`).

## Name

Working name **Follo** (follow the game): short, reads the same in Ukrainian and English, works as a verb, neutral across sports. Motto on the splash screen: "Follo the match." Known clashes to check before publishing: several unrelated "Follo" apps in the stores (construction logistics, finance, healthcare), the Follo region in Norway and its football club, the follo.com domain. Store title should be "Follo: AI sports camera"; domain candidates follo.cam, getfollo.com. Previous working name PitchCam was dropped because of PitchCom/PitchVision/Pitchcam in sports.
