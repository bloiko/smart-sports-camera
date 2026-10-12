# Run Follo on your iPhone (free, no App Store)

Takes about 30 minutes the first time, 1 minute afterwards. Works with a normal Apple ID; no paid developer account.

## Once

1. **Xcode**: Mac App Store → Xcode (free, ~12 GB). Open it once and let it install the iOS platform when asked.
2. **Apple ID in Xcode**: Xcode → Settings → Accounts → **+** → Apple ID → sign in. Your "Personal Team" appears.
3. **Project**: File → New → Project → iOS → App. Product name `Follo`, Interface SwiftUI, Language Swift. Save it into `ios/Follo/` of this repository. Delete the generated `ContentView.swift` and `FolloApp.swift`, then drag all files from `ios/Follo/Follo/` into the project (tick "Copy items if needed" off: they are already there).
4. **HaishinKit** (streaming library): File → Add Package Dependencies → paste `https://github.com/HaishinKit/HaishinKit.swift` → Add to target Follo.
5. **Signing**: project → target Follo → Signing & Capabilities → Team = your Personal Team; Bundle Identifier = `com.<yourname>.follo` (anything unique). Xcode creates the certificate.
6. **Info**: target → Info → add `Privacy - Camera Usage Description` = "Records the match", `Privacy - Microphone Usage Description` = "Match audio". Optional for the YouTube test: `YT_TOKEN` = the `token` field from `secrets/token.json` (made by `python src/golive.py`; valid 1 hour).
7. **iPhone**: Settings → Privacy & Security → Developer Mode → on (the phone restarts). Connect with a cable, tap "Trust".

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
- Build errors in Swift files: send the first red line to Claude; the code was written without compiling.
