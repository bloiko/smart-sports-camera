# Run Follo on your iPhone (free, no App Store)

Takes about 30 minutes the first time, 1 minute afterwards. Works with a normal Apple ID; no paid developer account.

## Once

1. **Xcode**: Mac App Store → Xcode (free, ~12 GB). Open it once and let it install the iOS platform. In Terminal: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. **Apple ID in Xcode**: Xcode → Settings → Accounts → **+** → Apple ID → sign in. Your "Personal Team" appears.
3. **Open the project**: `ios/FolloApp/FolloApp.xcodeproj` (already wired: sources, FolloCore package, HaishinKit, Core ML models, camera/microphone usage strings). Package resolution on first open takes a minute.
4. **Signing**: project → target FolloApp → Signing & Capabilities → Team = your Personal Team. Bundle Identifier is `com.bohdanloiko.follo`; change it if Xcode says it is taken.
5. Optional for the YouTube test: target → Info → add `YT_TOKEN` = the `token` field from `secrets/token.json` (made by `python src/golive.py`; valid 1 hour).
6. **iPhone**: Settings → Privacy & Security → Developer Mode → on (the phone restarts). Connect with a cable, tap "Trust".

Command-line check without a phone: `cd ios/FolloApp && xcodebuild -scheme FolloApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

## Every time

1. Select the iPhone in Xcode's top bar, press **Run** (⌘R). The app installs and opens.
2. First launch only: iPhone → Settings → General → VPN & Device Management → trust your Apple ID.
3. After **7 days** the app refuses to open: press Run again. No data is lost.

## Limits of the free Personal Team

- The app expires after 7 days (re-run from Xcode).
- At most 3 such apps on the phone at once.
- No App Store, TestFlight or push notifications. Camera, 4K, Core ML, network, YouTube API all work.
- Without a cable later: Xcode → Window → Devices → "Connect via network".

## If something fails

- "Untrusted developer": step 2 of Every time.
- "Could not launch": Developer Mode is off (step 7).
- Build errors in Swift files: send the first red line to Claude. `ios/FolloCore` and `LiveCameraRunner.swift` compile on the Mac (`ios/FolloCore/build_mac.sh`); the UIKit files (`SetupView`, `Streamer`, `CameraSession`, `LiveSession`) were written without compiling.
- "Camera: … models players/ball.mlmodelc" at Go live: step 4b was skipped.

## Testing at home without a pitch

`python src/bench_play.py work/m2/game.mp4 --loop` plays the match full screen on the Mac. Put the phone on a tripod 60–80 cm from the screen, landscape, so the screen fills about 80% of the ultra-wide frame; Mac brightness at maximum. The app then sees grass, lines and players as on a real pitch: position check, goals, goal mode, streaming and highlights all run for real. This is a development bench only; nothing in the app depends on it.
