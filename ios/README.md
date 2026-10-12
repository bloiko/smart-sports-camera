# PitchCam iOS skeleton (phase 3/5)

What it does today: 4K 30 fps from the ultra-wide camera, recorded in 3-minute HEVC chunks to `Documents/chunks/`, a setup/live screen with thermal state and chunk count, a "Go live" button that creates a YouTube broadcast through the Live API (token needed) and starts recording. Not yet: on-device virtual camera (Core ML), RTMPS streaming (HaishinKit), Google Sign-In. Design mockup: see the artifact linked in `specs/status.md`.

## Run on your own iPhone for free (no App Store, no paid account)

1. Install **Xcode** from the Mac App Store (free, ~12 GB). Open it once and let it install iOS components.
2. Xcode → Settings → Accounts → **+** → sign in with your Apple ID (a normal one; the free "Personal Team" is enough).
3. Create the project: File → New → Project → iOS → **App**, name `PitchCam`, interface SwiftUI, language Swift. Save it in `ios/PitchCam/` and **replace** the generated `ContentView.swift`/`PitchCamApp.swift` with the files from `ios/PitchCam/PitchCam/`.
4. Project → target PitchCam → **Signing & Capabilities**: Team = your Personal Team, Bundle Identifier = something unique, e.g. `com.<yourname>.pitchcam`. Xcode creates the certificate itself.
5. Target → Info → add key **Privacy - Camera Usage Description** (`NSCameraUsageDescription`), value "Records the match".
6. iPhone: Settings → Privacy & Security → **Developer Mode** → on (reboots). Connect the phone by cable, trust the Mac.
7. Select the iPhone as the run target (top bar) and press **Run**. First launch: on the phone, Settings → General → VPN & Device Management → trust your Apple ID.

Limits of the free Personal Team: the app stops launching after **7 days** (just press Run again), at most 3 apps at a time, no App Store, no push notifications. Everything else we need (camera, 4K, Core ML, network) works. Later `AltStore` can re-sign automatically every week if you want it without the Mac.

## YouTube test token (temporary)

Until Google Sign-In is added, you can paste a short-lived OAuth token into Info.plist as `YT_TOKEN` (get one with `python src/golive.py`, which stores it in `secrets/token.json` → field `token`). It expires in 1 hour; without it the app only records.
