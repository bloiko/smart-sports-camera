# Plan: own Google sign-in with stable broadcasts, UI tests on the simulator, drops, camera, own models

Written 2026-10-16 after the first private YouTube broadcast from the phone. Owner's rules apply: everything in the
product is our own code (Apple system frameworks allowed), each stage is compared before/after, the old path stays
switchable, the next stage starts only after the previous one is tested in detail.

## Why

- **Studio stream key:** every restart of the app can open a new broadcast. It gets a new link and Studio's default
  visibility, so friends need a new link each time and the broadcast may be private again.
- **Bugs reach the owner first.** The "STOP restarts the broadcast" bug was found by the owner. I build the app but
  never see its screen.
- **Network drops on YouTube are untested.** Recovery is proven only on our own server: we do not know if viewers see
  one continuous broadcast after 30 s without network.
- **A one-second trip to the background costs a reconnect** and leaves the stream 3 s behind for good: automatic
  catch-up starts only above 5 s.
- **The camera still loses the ball.** It is the most important product problem, but it needs footage from the owner's
  stadium.
- **The detectors are AGPL.** They are the last third-party part.

## Owner's visibility rule

- A broadcast starts as **"Не для всіх" (unlisted)**: only people with the link see it. It does not appear on the
  channel, in search or in subscribers' feeds.
- The owner can switch to "Для всіх" (public) from the app when he decides, and back. This needs a confirmation
  dialog and is available only in release builds.
- **Test (debug) builds have no "Для всіх" at all:** the option is not compiled in. They offer "Приватне" and "Не для
  всіх".

## Stage 0. UI tests on the simulator (first: every later stage is checked with it)

**Goal:** I see the app's screens and catch UI bugs before the owner does.

- An iPhone simulator (iOS 27 is installed) runs the app with the test video instead of the camera. The simulator has
  no camera; Core ML runs on the CPU there.
- The stream goes to a local RTMP receiver on the Mac (`127.0.0.1`, so the firewall does not matter). The received
  file is checked with `src/stream_check.py`.
- An XCUITest target (`FolloAppUITests`) drives the real UI:
  - GO LIVE → the title shows "LIVE".
  - Hold STOP for 1 s and release → the title shows "Готово до гри" and stays so for 5 s (the STOP bug).
  - Tap STOP briefly → nothing happens.
  - Scroll to the bottom → every control can be reached.
  - Mute → the label changes and the log says `stream sound off`.
  - Screenshots of each step are saved to `work/ui/` for me to look at.
- Views get accessibility identifiers (`goLive`, `stop`, `mute`, `title`, …).
- One command: `ios/ui_test.sh`. It builds, boots the simulator, copies the test video, starts the receiver, runs the
  tests and collects the screenshots and the log.
- **Check before moving on:**
  - the old STOP bug, re-introduced on purpose, makes the test fail;
  - the fixed code passes;
  - 3 runs in a row are green.

## Stage 1. YouTube through our own Google sign-in

**Goal:** the app itself creates an unlisted broadcast, shows its link, keeps the same link through restarts and
drops, and switches visibility on request.

- **Sign-in:** own OAuth 2.0 code with PKCE.
  - The sign-in page is the system web page (`ASWebAuthenticationSession`). This is what Google requires for apps; no
    Google SDK.
  - Tokens are kept in the Keychain. The access token is refreshed with the refresh token.
- **API calls:** a `YouTubeAPI` module in FolloCore, platform-neutral. It can be tested with `follosim` on the Mac.
  - One **reusable stream** (`liveStreams.insert`, `isReusable: true`), created once. The stream key never changes and
    is never shown.
  - Each match: `liveBroadcasts.insert`:
    - `privacyStatus: unlisted`;
    - `enableAutoStart: true`;
    - **`enableAutoStop: false`**, so a drop does not end the broadcast;
    - `latencyPreference: low`.
  - Then `bind`. STOP ends the broadcast with `transition → complete`.
  - Restart of the app during a match: the saved broadcast is checked (`liveBroadcasts.list`). If it is not complete,
    it is reused: **same link**.
  - Visibility switch: `liveBroadcasts.update` (status). The screen shows the current visibility.
  - Link: shown on the live screen with "Копіювати" and "Поділитися" (system share sheet).
- **Tests without Google and without the phone:**
  - `src/fake_youtube.py` (Python standard library only) imitates the token endpoint and the five YouTube calls. It
    records every request and hands out an ingest address on the local RTMP receiver.
  - `follosim youtube --api http://127.0.0.1:PORT` runs the whole sequence on the Mac.
  - The stage 0 UI tests run the same against the simulator: sign-in skipped with a debug launch argument. They check
    that a broadcast is created as unlisted, the link is shown, a restart reuses it, STOP completes it, and the debug
    build never sends `public`.
- **Real test on the phone:**
  - The owner creates the Google Cloud client, about 15 minutes (see below).
  - He signs in once on the phone. The consent and password are typed by the owner, never by me.
  - Then: GO LIVE → unlisted broadcast with a link → restart the app → same link → STOP → broadcast ended.
- **Rollback:** the Studio-key path stays as a debug option ("Ключ зі Studio"). `git tag before-google-signin`.
- **Limits to know:**
  - **Weekly sign-in.** While the Google project is in "Testing" mode, the sign-in lasts 7 days. Then the owner signs
    in again.
  - **"Unverified app" warning.** Google shows it; the owner presses "Continue". Verification is needed only before a
    public release.
  - **API quota.** A match uses about 200 of the 10 000 free daily quota units.

### What the owner does once (about 15 minutes, free)

1. https://console.cloud.google.com → the project from `docs/youtube-live.md` (or a new one).
2. APIs & Services → Library → **YouTube Data API v3** → Enable. Skip this if it is already enabled.
3. OAuth consent screen:
   - user type External, mode Testing;
   - add your Google account under **Test users**.
4. Credentials → Create credentials → **OAuth client ID** → type **iOS** → Bundle ID `com.bohdanloiko.follo` → Create.
5. Copy the **Client ID**, which ends in `.apps.googleusercontent.com`, into `secrets/google_client_id.txt`.

## Stage 2. Drops and short trips to the background

- **Simulated drop without touching the phone.** A debug launch argument `--net-drop AT:SECONDS` aborts the
  connection and refuses to reconnect for N seconds. Then:
  - check on YouTube that viewers see one broadcast with the same link;
  - check how the resent 2–3 s look.

  After that the owner turns the phone's Wi-Fi off once for 30 s. This is the real case: the phone may switch to mobile
  data.
- **Catch up small delays as well.** Lower the automatic catch-up threshold from 5 s to about 1.5 s. Compare before and
  after on the Mac with `follosim stream` scenarios, and on the phone. Viewers must not notice the 1.25× speed.
- **Keep the connection through a short trip to the background.** Ask iOS for background time
  (`beginBackgroundTask`). The camera stops, but the connection and the ring stay, so a swipe away and back costs no
  reconnect. Test from the Mac by opening Settings on the phone for 1, 5 and 30 s; compare reconnects and delay before
  and after.
- ~~Faster restart~~: not needed. The phone log shows the position check takes 14 s (frames are 1.4 s apart); the 1.5 min gap was the time to reopen the app. It is slow only on the simulator (CPU).
- **Warn when the app leaves the screen:** a sound and a vibration. Suggest Guided Access for matches.

## Stage 3. Camera quality on the owner's stadium

- **Footage.** The owner records 5–10 minutes of a real game with Follo (camera source, recording on).
- **Measure the problems on that footage:**
  - jitter;
  - "shows someone else";
  - ball share.
- **Tune** the tracker and the camera with `live_sim.py`, on the three matches with checklists plus the new one. Same
  rules as always: held-out part, checklists, frames before/after, then the Swift port and `compare_swift.py`.

## Stage 4. Own detectors

The plan in `docs/detector-licence-plan.md`, stages 3–4: FolloNet-B for the ball, FolloNet-P for players. They replace
the AGPL YOLO models. Last, because it is the largest piece of work and changes nothing the owner sees. Every new
detector is compared with the current one on the same checklists before it replaces it.

## Order and status

| Stage | Needs the owner | Status |
| --- | --- | --- |
| 0 UI tests on the simulator | no | done 2026-10-16 (see results below) |
| 1 Google sign-in, unlisted, stable link | 15 min setup + one sign-in on the phone | done 2026-10-17 (phone test passed) |
| 2 Drops and background | 1 Wi-Fi test | planned |
| 3 Camera quality | footage from the stadium | planned |
| 4 Own detectors | no | planned |

## Stage 0 results (2026-10-16)

- `ios/ui_test.sh` runs `FolloAppUITests` on the iPhone 17 simulator in about 5 minutes: 2–3 minutes of build, about
  70 s of position check, the tests themselves. Screenshots go to `work/ui/shots`.
- **What it checks:**
  - GO LIVE is grey and refused until the pitch is found.
  - A test broadcast starts muted; mute toggles.
  - STOP stays reachable when scrolled.
  - A short tap on STOP does nothing.
  - STOP opens the result sheet.
  - The screen stays "Готово до гри" for 6 s after it, with no restart.
  - A match is deleted from the list together with its folder.
- **Found by looking at the screens:**
  - GO LIVE looked active (red) while disabled.
  - The result sheet had no close button, and the swipe did not close it.

  Both are fixed.
- **Test clones.** Xcode first ran the tests on its own clone of the simulator, where the test video was missing.
  `-parallel-testing-enabled NO` fixes this, and the test now fails within 15 s without the video.
- **Limit: the STOP restart bug cannot be reproduced on the simulator.** With the old STOP button put back on purpose,
  test1 still passed: the simulator's synthetic press-and-release does not trigger the button's tap the way a finger
  did on the iPhone. The test still catches any broadcast that restarts after STOP, a tap that stops, and an
  unreachable STOP. The fix itself, STOP as a hold-only control, does not depend on that.
- CPU: the simulator runs Core ML on the Mac's CPU, and the live simulator panel streams video. The script shuts the
  simulator down at the end, and the panel stays closed during runs.

## Stage 1 results so far (2026-10-17)

- Code:
  - `FolloCore/GoogleAuth.swift`: PKCE, code exchange, refresh, "sign in again" on `invalid_grant`.
  - `FolloCore/YouTubeAPI.swift`:
    - reusable stream;
    - unlisted broadcast with auto stop off;
    - reuse after a restart;
    - visibility switch, with public refused unless `allowPublic`;
    - complete.
  - App: `YouTubeAccount.swift` (system web sheet, Keychain) and the setup screen (sign-in row, visibility picker in
    test builds, link with Copy/Share, visibility row during the match).
  - The old `YT_TOKEN` path is removed. The Studio key and own RTMP target stay as debug fallbacks.
- **Mac:** `follosim youtube` against `src/fake_youtube.py` passes all 17 checks.
- **Simulator:** `test3_YouTubeUnlistedSameLink` passes:
  - signed in;
  - unlisted by default, and no public option exists;
  - private ⇄ unlisted;
  - the app is killed mid-match and GO LIVE gives the same link;
  - STOP ends the broadcast;
  - exactly one broadcast insert;
  - `public` is never sent;
  - `enableAutoStop: false`.
- **Bugs the tests found:**
  - Sign-in was lost on every launch: `didSet` does not run inside the class's own `init`.
  - The simulator's microphone aborts the app (AURemoteIO RPC timeout), so the simulator streams without the mic.
  - A broadcast left by a crash would stay "live" forever with auto stop off. It is now closed when a new match starts
    more than 3 h later.
- **Next, on the phone:**
  - the owner signs in once;
  - GO LIVE → check the youtu.be link on another phone (unlisted);
  - kill the app → GO LIVE → same link;
  - STOP → the broadcast ends in Studio.

### Phone test (2026-10-17, iPhone 15, real Google and YouTube)

- **Sign-in.** The owner signed in in the system sheet; the channel name loaded.
- **GO LIVE.** Broadcast `Ib7Nb7IcBOw` was created and bound, and YouTube accepted the stream on the first connection.
- **Visibility.**
  - The broadcast came back **private**. The log did not record the requested visibility, so the cause is unknown:
    most likely the picker was on "Приватне".
  - Switching to unlisted from the app worked (`PUT liveBroadcasts → 200`, unlisted). So YouTube does not lock our
    unverified project to private.
  - The log now records the requested visibility next to YouTube's answer.
- **Restart mid-match.** The app was killed from the switcher; GO LIVE reused `Ib7Nb7IcBOw` (live, unlisted), with the
  same link and the same match folder. YouTube accepted the stream in 0.5 s.
- **STOP** ended the broadcast (`transition → 200`).
- **Gap after a restart: about 1.5 min.** Correction (2026-10-17): the position check itself took 14 s on the phone
  (app start 01:10:44 → "pitch ok" 01:10:58). The rest was the owner reopening the app and pressing GO LIVE.

## UI tests after the overnight work (2026-10-17)

`ios/ui_test.sh` runs 7 tests, all green:
1. GO LIVE and STOP.
2. Delete a match.
3. YouTube unlisted, same link after a restart.
4. Recording does not wait for YouTube.
5. Expired sign-in banner.
6. Landscape.
7. Half-time.

Lessons from the tests themselves:
- **Edge check.** `allInsideScreen` fails a test when a button sticks out of the screen. It found the score panel being
  ~26 pt wider than an iPhone in portrait.
- **Lazy list.** The list loads rows lazily: check that a deleted match is gone by its label, not by the row count.
- **Dimmed screen.** After 60 s without a touch the live screen dims and the first touch only wakes it. Tests call
  `wake()` before STOP.
- **Landscape screenshots.** XCUITest stores them wrongly. Use element frames (`app.windows.firstMatch.frame`, button
  frames) to check landscape, not the pictures.
