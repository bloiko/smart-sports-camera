# Follo iOS: code and log evidence for the constant black camera frames (Y = 15/16) on iPhone 15

All file references are to `/Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/` (the `ios/FolloApp/FolloApp/` copies are byte-identical, `diff -rq` differs only in assets/models). Log = `/private/tmp/claude-501/-Users-bohdan-loiko-IdeaProjects-smart-sports-camera/f70e384c-a8c2-4110-8770-b9142b6da51f/scratchpad/dev/log.txt` (run of 01:13, iOS 27.0.1). Apple documentation pages could not be fetched (developer.apple.com renders via JS; WebFetch returned only titles), so API semantics below are stated from AVFoundation knowledge and marked "(API knowledge, not fetched)".

## Q1. Does the luma measurement read the right plane/rows, so 15/16 really means black video?

### Takeaway
Yes. The sampler reads plane 0 (Y) of the NV12 buffer with the plane's own bytesPerRow and x < width, so no padding is sampled. Every sampled pixel is exactly 16 = video-range black; "mean 15" is an off-by-one in the denominator, not darker pixels. So the frames are a perfectly flat, noise-free black, which is itself a diagnostic clue.

### Cited Findings
- Output format is NV12 video range: `out.videoSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]` — [CameraSession.swift:78](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L78). In video-range Y′CbCr (BT.601/709 "legal range") black is Y = 16, white is 235 (standard; API knowledge, not fetched).
- Sampler: `CVPixelBufferGetBaseAddressOfPlane(pb, 0)`, `bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)`, `for y in stride(0, to: h, by: 60) { for x in stride(0, to: w, by: 60) { p8[y * bpr + x] } }` — [CameraSession.swift:118-121](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L118-L121). `x < w` and `y < h`, row offset uses `bpr`, so sampled bytes are inside the valid image, never in row padding.
- Denominator bug: `mean = sum / ((h / 60 + 1) * (w / 60 + 1))` — [CameraSession.swift:122](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L122). For 3840×2160 the loops visit 64×36 = 2304 pixels but divide by 65×37 = 2405. If every pixel is 16: 16·2304/2405 = 15.33 → "mean 15 max 16". That is exactly the logged value: `01:13:24.533 luma mean 15 max 16 mem 63 MB` (log line 6) and every later luma line (lines 8, 11, 15, 19, 20, 23–25, 28, 29).
- The saved preview JPEG (`scratchpad/dev/preview.jpg`, 01:13) is uniformly black, consistent with the luma numbers (same source buffer, see Q3).
- Frame delivery is live and at 30 fps: luma lines are logged every 60 frames (`previewCount % 60 == 0`, [CameraSession.swift:116](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L116)) and arrive at 01:13:24.533, 26.528, 28.531 — 2.00 s apart = 30.0 fps (log lines 6, 8, 11). So the capture graph is running and delivering real buffers; the problem is their content.

### Inferences
- "max 16" over 2304 pixels spread across the whole 4K frame means not a single sampled pixel is above black. A real low-light sensor image normally shows noise (16–30) and any lamp/screen in the 120° ultra-wide field of view would exceed 16; a perfectly flat 16 means either (a) the ISP clamped a scene that is genuinely below its noise floor in the whole FOV (strong temporal noise reduction in video mode can flatten it), or (b) the pipeline is emitting an empty "black" buffer. The same flat-16 signature appeared in daylight at 14:26/14:29 (coordinator's timeline, after 8–12 s of luma 110–125), so the flat-16 signature is NOT by itself proof of a dark scene.
- The blank detector `mx - mean <= 2` ([CameraSession.swift:125](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L125)) therefore cannot distinguish "dark room" from "empty buffer"; it rebuilds the session every 6 s for either.

### Gaps
- No exposure telemetry is logged (ISO, exposureDuration, exposureTargetOffset, lensAperture) — the one piece of data that separates (a) from (b). Suggested: add `dev.iso, dev.exposureDuration, dev.exposureTargetOffset` to the luma log line.

## Q2. Is there a code path leaving the session running with no/disabled video connection, or a failing videoRotationAngle call?

### Takeaway
No. The log proves inputs 1 / outputs 1 and 30 fps delivery; `videoRotationAngle` is guarded by `isVideoRotationAngleSupported(0)`. A missing or disabled connection would mean no delegate callbacks at all, not black ones.

### Cited Findings
- `if session.canAddInput(input) { session.addInput(input) }` / `if session.canAddOutput(out) { session.addOutput(out) }` — silent on failure, [CameraSession.swift:74,81](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L74). But the log confirms both succeeded: `01:13:22.540 session running true Back Ultra Wide Camera 3840x2160 inputs 1 outputs 1` (log line 3; same after each rebuild, lines 13, 22, 27).
- Rotation: `if let c = out.connection(with: .video), c.isVideoRotationAngleSupported(0) { c.videoRotationAngle = 0 }` — [CameraSession.swift:82](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L82). Cannot throw; if unsupported it is simply skipped.
- `connection.isEnabled` is never touched (grep over `ios/Follo/Follo/*.swift` for `isEnabled`/`isActive`: no hits).
- Delegate callbacks are arriving: `preroll frame N` lines (log 4,5,7,9,10,14,16) come from `frameHandler` → `addPrerollFrame` ([SetupView.swift:92-95](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L92-L95), [LiveCameraRunner.swift:36-53](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/LiveCameraRunner.swift#L36-L53)).
- No observer for `AVCaptureSession.runtimeErrorNotification`, `.wasInterruptedNotification`, `.interruptionEndedNotification` anywhere in the app (grep: no hits). A session interruption (camera used by another client, background) stops sample-buffer delivery entirely rather than delivering black frames (API knowledge, not fetched) — which does not match the observed 30 fps delivery.
- The 4K preset path is `session.sessionPreset = canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080` — [CameraSession.swift:76](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L76), set after `addInput`; no `lockForConfiguration`, no frame-duration or exposure settings anywhere in the working tree (grep `lockForConfiguration|FrameDuration|exposure|ISO` → no hits in `ios/Follo/Follo`).

### Inferences
- The capture graph is healthy from AVFoundation's point of view (running, 30 fps, correct dims/format). Whatever makes the pixels black happens upstream of the app: sensor/ISP exposure, or an OS-level black feed.

### Gaps
- Without runtime-error / interruption observers, a silent AVCaptureSession error state cannot be excluded from the log. Experiment: add observers for the three notifications and log `reason`.

## Q3. The preview path (CIImage → scale 0.25 → createCGImage): can a black preview coexist with valid frames?

### Takeaway
The preview and the luma number are derived from the same `CVPixelBuffer` inside the same callback, so they are not independent evidence; the luma reading is the direct one and is trustworthy on its own (Q1). A black preview with valid frames is possible in principle (CI colour handling) but is ruled out here because the raw bytes are 16.

### Cited Findings
- `let ci = CIImage(cvPixelBuffer: pb).transformed(by: scale 0.25)`; `previewCtx.createCGImage(ci, from: ci.extent)`; failure is logged (`preview: createCGImage failed`) — [CameraSession.swift:113-115](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L113-L115). No such failure line in the log; the preview file is written every ≥2 s by `DebugLog.preview` ([DebugLog.swift:26-30](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/DebugLog.swift#L26-L30)).
- The luma sampler runs on the same `pb` two lines later ([CameraSession.swift:116-123](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L116-L123)).
- Note in SetupView: AVCaptureVideoPreviewLayer and AVSampleBufferDisplayLayer "showed nothing" on this session earlier ([SetupView.swift:6-7](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L6-L7)) — this was with the earlier manual-activeFormat setup, before the preset change in the working tree.

### Inferences
- The raw Y bytes are the ground truth; the preview only confirms them. No reason to suspect the preview path.

### Gaps
- None.

## Q4. pause()/resume()/rebuild()/switchCamera(): can they leave the input attached with the device in a bad state, stack inputs/outputs, or re-enter setup()?

### Takeaway
All mutations run on the single serial `queue`, every rebuild removes all inputs and outputs before `setup()`, and the log shows "inputs 1 outputs 1" after each rebuild — so no stacking in this run. There is one real re-entrancy window (resume() calling setup() while the permission callback also schedules setup()), but it did not fire in the 01:13 log (no "session resumed" line) and would at worst add a second data output, not black frames. Rebuild cannot fix a scene/exposure problem.

### Cited Findings
- `pause()`: `if session.isRunning { stopRunning(); log("session paused") }` — [CameraSession.swift:18](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L18).
- `resume()`: guard not running; `if !inputs.isEmpty { startRunning() }`; if still not running → remove all inputs/outputs and `setup()`; always logs `session resumed <bool>` — [CameraSession.swift:19-31](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L19-L31). The 01:13 log has no `session resumed` and no `session paused` line, so neither pause nor resume ran in that run.
- `rebuild()` and `switchCamera()` are identical: stopRunning, beginConfiguration, remove all inputs/outputs, commit, `setup()` — [CameraSession.swift:34-42, 46-53](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L46-L53). Each rebuild is followed by `session running true … inputs 1 outputs 1` (log lines 12→13, 21→22, 26→27) and frames keep arriving at 30 fps with the same flat 16 (lines 15, 23–25, 28–29). Rebuilding three times (every ~6 s) changed nothing.
- `setup()` has no guard against being called twice; `configure()` schedules it from the permission callback ([CameraSession.swift:59-65](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L59-L65)), and `resume()` can also call it when the session has no inputs yet (line 22-27). Both land on the serial `queue`, so they serialise; a second `setup()` would find `canAddInput` false (same device already attached) and could add a second `AVCaptureVideoDataOutput` if `canAddOutput` allows it. Not observed (log always "outputs 1").
- `rebuild()` is triggered from inside the delegate callback (camera `queue`) via `queue.async` — [CameraSession.swift:126, 46-47](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L126) — asynchronous, so no deadlock; `stopRunning()` then runs on the delegate queue itself, which is allowed.
- The `AVCaptureDeviceInput` is never retained outside the session and the device is never locked (`lockForConfiguration` absent), so no leftover device lock or custom exposure/format state can survive a rebuild.
- Memory after rebuild drops (109 → 93 → 79 MB, log lines 19–25): consistent with the ring/pools being released, i.e. the old graph really is torn down.

### Inferences
- The pause/resume/rebuild logic is not the cause of the night-time black: it never ran before the first black frame (first luma at 01:13:24.533, 2 s after start, with no pause/resume in between), and the device enters each new session already black.

### Gaps
- The uncommitted intermediate versions used at 14:26/14:29/14:47 are not in git (`git log` shows only `3829896` and `de75a22` for CameraSession.swift; everything else is working-tree). So the exact code of the 14:47 "working" run cannot be reconstructed from the repo; the differences vs de75a22 are: preset instead of manual activeFormat, no frame-duration lock, preview every 15th frame instead of 6th, pause/resume/rebuild/switchCamera, blank detection (full diff: `git diff de75a22 -- ios/Follo/Follo/CameraSession.swift`).

## Q5. onDisappear { cam.pause() } with fullScreenCover: can onAppear/onDisappear fire in an order that pauses right after start? (01:05 "session paused" 7 s after start)

### Takeaway
`session paused` can only come from `pause()`, which has exactly two callers: `scenePhase == .background` and `onDisappear`. Neither fired in the 01:13 log, and the 01:13 run was black regardless, so this is not the cause of the black frames. The 01:05 event remains unexplained from the available material (that log is not in the scratchpad).

### Cited Findings
- Callers: `.onChange(of: scenePhase) { if ph == .background { cam.pause() } else if ph == .active { cam.resume() } }` and `.onDisappear { cam.pause() }` — [SetupView.swift:97-101](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L97-L101). No other call sites (grep `pause()` in `ios/Follo/Follo`).
- Presentation: `MyMatchesView` shows `SetupView` via `.fullScreenCover(isPresented: $newMatch)`, and `--autostart` sets `newMatch = true` in `onAppear` — [MyMatchesView.swift:37-38](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/MyMatchesView.swift#L37-L38). `FolloApp` skips onboarding when `--autostart` is present — [FolloApp.swift:5](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/FolloApp.swift#L5).
- SetupView additionally presents two sheets over itself (`BeforeGameSheet` on first run, `ResultView` after stop) — [SetupView.swift:86-87](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L86-L87). Presenting a sheet from a view does not call that view's `onDisappear` (SwiftUI behaviour, API knowledge).
- `onAppear` resets the log, requests permission and sets `frameHandler` — [SetupView.swift:88-96](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L88-L96). In the 01:13 log the sequence is `app start` → `camera permission true` → `session running true` within 260 ms (log lines 1–3) — no pause/resume between.
- After `pause()` nothing restarts the session except a `scenePhase → .active` transition ([SetupView.swift:99](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/SetupView.swift#L99)); if `onDisappear` fired spuriously while the view stayed visible, the camera would stay stopped (no frames) — a different symptom (no luma lines) from the black-frame one.

### Inferences
- A pause 7 s after start while the user stayed on screen is most plausibly `scenePhase == .background` (e.g. the phone locked, a devicectl launch that did not foreground the scene, or the user switching to the Camera app to compare) rather than a spurious `onDisappear`. Cannot be settled without that log.
- Launch via `xcrun devicectl … process launch` typically brings the app to foreground, so scenePhase goes `.inactive → .active` once; the `.active` transition calls `resume()`, which returns silently at the guard when the session is already running ([CameraSession.swift:21](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L21)) — consistent with the absence of "session resumed" in the log. If `.active` arrives before the permission callback has run `setup()`, `resume()` falls into the "no inputs → setup()" branch (lines 23–27) and the permission callback runs `setup()` a second time: harmless duplicates, but worth guarding (e.g. a `configured` flag).

### Gaps
- The 01:05 log is not available; recommended: log the caller inside `pause()` (`"session paused (background)"` vs `"(disappear)"`) and the scenePhase values.

## Q6. Why would the ultra-wide be black at night while the system Camera shows an image? Exposure cap, night mode.

### Takeaway
The working tree does NOT cap exposure (no `lockForConfiguration`, no `activeVideoMin/MaxFrameDuration`), but a 4K30 preset without an explicit longer `activeVideoMaxFrameDuration` still limits exposure to one frame period (≈33 ms at 30 fps), with no night mode: in a room dark enough that the system Camera's auto Night mode (moon icon) switches on, the ultra-wide (f/2.4, small pixels, no OIS) at 1/30 s can be at or below the ISP noise floor, and video-mode noise reduction then yields flat Y = 16. The system Camera in photo mode drops preview frame rate / uses Night mode multi-second integration on the much faster 1× sensor, so it shows an image. This is the single explanation that fits "black from frame 1 in every night run, fine in daylight, rebuilds don't help, system Camera in night mode".

### Cited Findings
- Exposure/frame duration: nothing in the current code touches them (grep above; comment at [CameraSession.swift:84](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L84): "без ручного fps: пресет 4K дає 30 fps; лок після commit на iPhone 15 через ~8 с робив кадри порожніми (luma 15)"). The removed code set `activeVideoMinFrameDuration = activeVideoMaxFrameDuration = 1/30` ([git diff de75a22 … CameraSession.swift](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift), removed lines `dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)` / `MaxFrameDuration`).
- AVFoundation semantics (API knowledge, not fetched — Apple doc pages returned only titles): for a 30 fps format selected by a session preset, the device's default `activeVideoMaxFrameDuration` is the format's frame duration (1/30 s), so auto-exposure cannot lengthen exposure beyond ~33 ms unless the app explicitly sets a larger max frame duration (e.g. 1/15 or 1/10 s); there is no "night mode" for AVCaptureVideoDataOutput video. `AVCaptureDevice.iso`, `exposureDuration` and `exposureTargetOffset` are readable at any time without a lock.
- Camera choice at night: `useWide = false` → `.builtInUltraWideCamera` — [CameraSession.swift:15, 69-70](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L69-L70); log confirms `Back Ultra Wide Camera 3840x2160` (line 3). The working tree now defaults `useWide = true` as a temporary experiment (line 15 comment).
- Coordinator's timeline (not reproducible from the repo): night runs 00:49–01:14 black from the first frame, every run, also after reboot and after icon launch; system Camera at 01:14 showed the Night-mode moon icon and a black 1× preview. The Night-mode indicator in the system Camera only appears automatically in low light (iOS Camera behaviour, not fetched).
- The only daylight failure (14:26/14:29: normal luma for 8–12 s then flat 16) coincided with two things that no longer exist in the working tree: the post-commit frame-duration lock (comment at [CameraSession.swift:84](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/CameraSession.swift#L84)) and the env build on `.userInitiated` (now `.utility`, [LiveCameraRunner.swift:18](file:///Users/bohdan.loiko/IdeaProjects/smart-sports-camera/ios/Follo/Follo/LiveCameraRunner.swift#L18)). The 14:47 run with the current graph stayed normal for the whole 45 s build (coordinator's timeline).
- In the 01:13 run the env build takes only 1.4 s and produces "No pitch found" (log line 18) — expected for black input, and CPU load is not a factor (black from 01:13:24, before any build starts at 01:13:30).

### Inferences
- Ranking of root causes for the NIGHT runs:
  1. **Dark scene + ultra-wide 4K30 video with exposure capped at one frame period (most likely).** Fits every observation; code never changed the exposure limit between 14:47 (daylight OK) and night (black). The daylight transient at 14:26 is a separate, already-removed cause (frame-duration lock on a running session / CPU starvation) and should not be conflated with the night symptom. Confirming experiment: in the luma log line also print `dev.iso`, `dev.exposureDuration.seconds`, `dev.exposureTargetOffset`, `dev.activeFormat.maxISO`; if ISO ≈ maxISO and exposureTargetOffset strongly negative (several EV) → the sensor is starved of light. Cheaper check: switch the room light on / point the phone at the Mac screen at full brightness (bench_play setup): luma must rise immediately without any rebuild; and the current `useWide = true` build at night should give a non-black (noisy) image because the 1× sensor is ~2 stops faster.
  2. **OS delivering a muted/black feed to the app while the capture graph reports running** (e.g. a privacy/system state on iOS 27.0.1 affecting only this app, or the camera being claimed by another client without an interruption we would notice because no observers are installed). Weaker: iOS normally stops delivery rather than feeding black, and a reboot did not help. Experiment: add observers for `AVCaptureSession.wasInterruptedNotification` / `.interruptionEndedNotification` / `.runtimeErrorNotification` and log the reason; also log `dev.isSuspended`/`dev.isConnected`.
  3. **Ultra-wide 4K format on iPhone 15 misbehaving in low light (ISP/firmware)**, i.e. the device delivers black instead of a noisy image where the 1080p or 1× path would not. Experiment: at the same spot and light, run with `.hd1920x1080` on the ultra-wide and with the 1× camera at 4K; compare luma.
  4. **Session lifecycle (pause/resume/onDisappear/scenePhase)**: excluded for the black frames (Q4/Q5: never ran before the first black frame). Still worth hardening: guard double `setup()`, log pause reason.
  5. **Measurement/preview error**: excluded (Q1/Q3).
- If hypothesis 1 holds, the practical fix for real evening matches is not a rebuild but exposure headroom: after `commitConfiguration`, `lockForConfiguration` and set `activeVideoMaxFrameDuration` to e.g. 1/15 s on the device (allowing AE to drop to 15 fps in the dark, as the system Camera's "auto low-light FPS" does), and/or prefer the 1× camera when `exposureTargetOffset` stays below about −2 EV; note the earlier observation that a post-commit lock produced black after ~8 s on this phone, so the lock must be done inside `beginConfiguration … commitConfiguration` before `startRunning()`, and re-tested in daylight.

### Gaps
- Whether the system Camera's own 1× *preview* was black at 01:14 (the coordinator's note says both "normal image" and "black 1× preview with moon icon"); if the preview was black and only the Night-mode photo was bright, the room was effectively dark and hypothesis 1 is almost certain.
- Actual light level of the room and the ultra-wide's `maxISO` / minimum exposure on iPhone 15 under iOS 27 — not in the repo; needs the telemetry log above.
- Apple documentation text for `activeVideoMaxFrameDuration` defaults and interruption semantics could not be fetched (JS-only pages); statements are from API knowledge.
