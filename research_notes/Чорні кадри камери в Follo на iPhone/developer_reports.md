# Real-world developer reports: black frames / black preview in third-party AVFoundation apps while the built-in Camera works (2022–2026)

Scope note: ~30 searches/fetches on Apple Developer Forums, HaishinKit GitHub, Hacking with Swift, Stack Overflow and blogs. Many reports are single-developer anecdotes with no Apple confirmation; marked as **[anecdote]** vs **[confirmed/Apple]** vs **[documented API]**. A surprising number of threads with "black screen" symptoms have no root cause recorded at all.

## Q1. Black frames because exposure is capped by a fixed 30 fps frame duration in low light (ultra-wide, f/2.4)

### Takeaway
No source gives a lux threshold at which the ultra-wide at 1/30 s renders near-black (Y≈16); the mechanism (frame-duration cap → exposure cap) is documented, and Apple's own fix is "auto video frame rate" (iOS 18+) which drops 30 → 24 fps in low light. Published low-light photo EXIF for the ultra-wide shows the system Camera already running at ISO 800–2500 and 1/17–1/50 s, i.e. at 1/30 s and the ISO ceiling a dim room is marginal, but nobody has quantified "nearly black".

### Cited Findings
- `activeVideoMinFrameDuration` is the reciprocal of the max frame rate; setting it caps the frame rate for the session — [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration) **[documented API]**
- A developer found that the lowest exposure duration in captured photos equalled `activeVideoMaxFrameDuration`; setting frame duration alone did not change it, he also had to set `activeMaxExposureDuration`, after which "the viewfinder became terribly slow in low light" — [Apple forums thread 124228](https://developer.apple.com/forums/thread/124228) **[anecdote, pre-2022 but API unchanged]**
- `isAutoVideoFrameRateEnabled`: "Under low light conditions, it decreases the frame rate to properly expose the scene. For 30 fps formats, the frame rate switches between 30-24"; once enabled, setting `activeVideoMinFrameDuration`/`activeVideoMaxFrameDuration` throws an exception — [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturedevice/isautovideoframerateenabled) **[documented API]**
- `activeMaxExposureDuration`: the auto-exposure algorithm "picks a default maximum exposure duration that's tuned for the current configuration, balancing low light image quality with motion preservation"; out-of-range values throw — [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemaxexposureduration) **[documented API]**
- Measured system-Camera ultra-wide low-light stills (iPhone 12 Pro Max): f/2.4, ISO 1250, 1/33 s; range across the test ~1/17–1/50 s at ISO 800–2500 — [GSMArena flagship comparison, fall 2020](https://m.gsmarena.com/flagship_camera_comparison_fall_2020-review-2202p8.php) **[measured, photo not video]**
- Ultra-wide's f/2.4 vs main f/1.8 (iPhone 11) / f/1.6 (iPhone 12) means "significant light lost in your photo or video" — [Moment review](https://www.shopmoment.com/reviews/iphone-11s-built-in-ultra-wide-vs-moment-wide-18mm-lens) **[reviewer]**
- Night mode on the ultra-wide: reviewers in 2019 noted Night mode wasn't available on the ultra-wide (iPhone 11), attributed to lack of OIS; by iPhone 12 Pro Night mode worked on all lenses — [BGR](https://www.bgr.com/tech/iphone-11-pro-camera-review-features-with-night-mode-app/); [Inverse](https://inverse.com/input/reviews/galaxy-s21-ultra-vs-iphone-12-pro-max-which-camera-phone-takes-better-night-photos/amp) **[reviewer; stills only, no evidence Night mode applies to video]**
- Apple's TN3121 warns BGRA is not a native capture format and forces a conversion; native formats are 420v/420f — [TN3121](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput) **[documented]** (relevant to "Y=16" diagnosis: uniform Y=16 is video-range black, i.e. a real dark exposure or a range/format mismatch, not a dead pipeline)

### Inferences
- The system Camera in video mode on a 30 fps format is itself limited to ~1/30 s per frame unless auto-frame-rate drops it to 24 fps (1/24 s), so its advantage over a third-party app at a hard 30 fps is at most ~0.3 EV from frame rate; the rest comes from ISO ceiling, noise reduction/tone mapping (Deep Fusion/Smart HDR style processing) and, in Photo mode, multi-second Night mode. A third-party video pipeline that looks "nearly black" where the Camera app's *photo* preview looks fine is likely comparing against Night-mode preview, not against the Camera app's *video* mode.
- If the app pins `activeVideoMinFrameDuration = activeVideoMaxFrameDuration = 1/30` AND locks or caps exposure (`activeMaxExposureDuration`, `exposureMode = .custom/.locked`), frames go dark much sooner. Check `device.exposureDuration` and `device.iso` on live frames: if ISO is at `activeFormat.maxISO` and duration at 1/30, the scene is simply below the sensor floor.
- Recommended test: compare the same dark room in the Camera app's Video mode at 4K30 against the app; if both are dark, it is physics, not a bug.

### Gaps
- No lux figure or developer anecdote found for "ultra-wide at 1/30 s renders Y≈16"; no Halide/Lux or Obscura blog post on ultra-wide video low-light limits surfaced (Halide coverage found was only about RAW/manual-focus support on the ultra-wide and 2017 1/3 s still limits).
- `isAutoVideoFrameRateSupported` per-format support on the ultra-wide of iPhone 15/16/17 is not documented in any source found; must be checked on the device.

## Q2. `startRunning` succeeds but frames/preview are black: lifecycle, interruptions, competing sessions, multi-cam

### Takeaway
The dominant 2025–2026 report is interruption reason 4 (`videoDeviceNotAvailableWithMultipleForegroundApps`) firing on iPhones that are not multitasking, after iOS 18.4.1/18.5, leaving the preview black until a phone reboot; Apple DTS called it a likely bug. The second documented pattern is a second `AVCaptureSession` (or a not-yet-deallocated one) in the same process taking the device: the first session freezes/interrupts with "video device is in use by another client".

### Cited Findings
**Interruption reason 4 on iPhone (iOS 18.4.1+)**
- Production app saw a "significant uptick" of `AVCaptureSessionWasInterrupted` with reason rawValue 4 correlated with iOS 18.4.1; preview stays black, photo capture fails with `AVFoundationErrorDomain -11803 "Cannot Record"`; backgrounding and reinstall do not recover, only reboot — [Apple forums 785206](https://developer.apple.com/forums/thread/785206) **[anecdote, multiple reporters]**
- Xcode's description of reason 4: "An interruption caused when the app is running in a multi-app layout... the session may only be run if your app occupies the full screen"; docs: not raised if `isMultitaskingCameraAccessEnabled` is true — same thread **[documented]**
- Reported workaround: enable the Multitasking Camera Access capability and set `session.isMultitaskingCameraAccessEnabled = true` before `startRunning()` — [785206, AnonUser1996 reply](https://developer.apple.com/forums/thread/785206) **[anecdote]**
- Apple DTS (Greg) on a parallel thread: PiP exists on iPhone (FaceTime), but the interruption "should not happen" without multiple foreground apps; symptoms "strongly indicate" a bug; file Feedback. DTS advised **against** enabling multitasking camera access as a workaround because it requires the VoIP background mode ("you should not enable the voip background mode unless your app is a voip app") — [Apple forums 791671](https://developer.apple.com/forums/thread/791671) **[Apple DTS]**
- Second reporter (Oct 2025): no PiP, no other camera app, still reason 4; thread shows no resolution — same thread **[anecdote]**
- Another iOS 18.5 report of black camera for "some production users"; reply: "potential bug in iOS that is causing black screen issues for 3rd party apps... users have to reboot" — [Apple forums 791199](https://developer.apple.com/forums/thread/791199) **[anecdote, no root cause]**
- HaishinKit added `isMultitaskingCameraAccessEnabled` support in PR #1870 (Jan 2026) — [GitHub PR 1870](https://github.com/HaishinKit/HaishinKit.swift/pull/1870) **[confirmed code]**

**Two sessions in one process / device contention**
- Apple engineer: when an `AVCaptureMultiCamSession` was not really deallocated (KVO held it) and a new `AVCaptureSession` was created, the 1080p preset gave "Capture session was interrupted (video device is in use by another client)" and the 4K preset gave -11873 "active format is unsupported by this session". Fix: `stopRunning()` the old session before releasing it; also `videoPreviewLayer.session = nil` before reuse, else assertion `figCaptureSession == NULL` in `attachToFigCaptureSession:` — [Apple forums 134114](https://developer.apple.com/forums/thread/134114) **[Apple engineer]**
- Developer running a second session on the same camera: "as soon as the 2nd session is established the first freezes"; Apple engineer (ARKit context): there can only be one running capture session at a time — [Apple forums 697994](https://developer.apple.com/forums/thread/697994); [SO 11071202 mirror](https://dev.library.kiwix.org/content/stackoverflow_en_nopic_2021-08/questions/11071202/run-multiple-avcapturesessions-or-add-multiple-inputs) **[anecdote + Apple]**
- `AVCaptureMultiCamSession`: "If your app only needs to capture from a single camera at a time, use AVCaptureSession instead"; check `isMultiCamSupported` — [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession) **[documented]**
- WebRTC logs the interruption reason as `VideoDeviceInUseByAnotherClient` from `AVCaptureSessionWasInterrupted` userInfo — [Chromium codereview](https://codereview.webrtc.org/2028403003/patch/80001/90001) **[code]**; a liveness SDK's notes describe it as the OS taking the camera (call/FaceTime/another app), recovery = wait then restart session — [Advance.AI release notes](https://support.advance.ai/hc/en-us/articles/59517693731353-Liveness-Detection-SDK-Release-Note-IOS-v4-1-3-2025-12-29) **[vendor]**

**`isRunning == true` with no frames**
- iPhone 15 Pro / iOS 18.0: preview blank 0.5–2 s after lock/unlock or camera switch while `isRunning == true`; a temporary `AVCaptureVideoDataOutput` showed **no sample buffers** during the gap; delays, queues, restart in `InterruptionEnded`, rebuilding I/O did not help. OP's final diagnosis: SwiftUI remounting the preview because `session.isRunning` was in the view's visibility condition; fix = remove `isRunning` from the condition — [Apple forums 811759](https://developer.apple.com/forums/thread/811759) **[anecdote; note the no-sample-buffers observation is not fully explained by the SwiftUI fix]**

**Format-combination black**
- iPhone 16 Pro: 4K@120 fps on the wide camera with `AVCaptureMovieFileOutput` + `AVCaptureVideoDataOutput`, `activeMaxExposureDuration = 1/960`, `exposureMode = .locked` → black preview and black recording; every other combination works; 0 replies — [Apple forums 772769](https://developer.apple.com/forums/thread/772769) **[anecdote; locked exposure at 1/960 is itself a plausible cause of black]**

### Inferences
- A black preview + `isRunning == true` + no `captureOutput` callbacks is the interruption signature; always log `AVCaptureSession.wasInterruptedNotification` with `AVCaptureSessionInterruptionReasonKey`, `interruptionEndedNotification` and `runtimeErrorNotification` before anything else.
- Any library that lazily creates its own `AVCaptureSession` and adds the camera as input will preempt a hand-rolled session the moment it calls `startRunning()`; before that moment it is harmless (see Q3).
- Starting the session before the scene is `foregroundActive` should surface as reason 1 (`videoDeviceNotAvailableInBackground`) and recover on `interruptionEnded`; no report found of this causing a *persistent* black preview in a correctly-observing app.

### Gaps
- No report found of a session configured on a background queue "while UI not yet active" producing black frames independently of the interruption mechanism.
- Apple's interruption-reason doc page could not be fetched (JS-only); raw values 1–6 listed above come from the WebRTC source and Xcode quotes, not from the fetched doc.

## Q3. HaishinKit 2.x: when does `MediaMixer` create its `AVCaptureSession`, and can an idle mixer break another session?

### Takeaway
`MediaMixer` does **not** create an `AVCaptureSession` in `init`; the session is a `lazy var` created on first access of `videoIO`/`audioIO` (i.e. on `attachVideo`/`attachAudio`), and it is only started by `startRunning()`/`startCapturing()`. An instantiated but untouched `MediaMixer` therefore cannot compete for the device; a mixer with `attachAudio`/`attachVideo` called but not started holds an un-started session with inputs (harmless to another session until `startRunning`). The mixer does not set the `AVAudioSession` category. No HaishinKit issue about "two capture sessions in one process" was found.

### Cited Findings
- `MediaMixer.swift` (main): `private lazy var session: (any CaptureSessionConvertible) = captureSessionMode.makeSession()`; `init` only stores `captureSessionMode` and `isMultiTrackAudioMixingEnabled`; `audioIO`/`videoIO` are lazy and reference `session` — [MediaMixer.swift](https://raw.githubusercontent.com/HaishinKit/HaishinKit.swift/main/HaishinKit/Sources/Mixer/MediaMixer.swift) **[confirmed code]**
- `captureSessionMode`: `.single` (plain session), `.multi` (`isMultiCamSessionEnabled = true`), `.manual` (`NullCaptureSession`, no AVCaptureSession; for ReplayKit) — same file; introduced by PR #1765 (Aug 2025), replacing `multiCamSessionEnabled: false` — [GitHub PR 1765](https://github.com/HaishinKit/HaishinKit.swift/pull/1765) **[confirmed code]**
- `attachVideo`/`attachAudio` forward to `videoIO`/`audioIO` and create the session if needed but do not start it; `startRunning()` → `startCapturing()` → `session.startRunning()` if not already running; `stopRunning()` → `stopCapturing()` → `session.stopRunning()` — same file **[confirmed code]**
- The mixer does not set or activate the `AVAudioSession` category; it observes `AVAudioSession.interruptionNotification` (`.began` → `audioIO.suspend()` + `session.startRunningIfNeeded()`, comment: "video capture continues even while an incoming call is ringing") — same file **[confirmed code]**
- Background handling: on background `setInBackground(true)` suspends `videoIO` unless `session.isMultitaskingCameraAccessEnabled`; on foreground resumes and calls `startRunningIfNeeded()`; on `.mediaServicesWereReset` and on error -11800 (not in background) it restarts the session — same file **[confirmed code]**
- PR #1851 (Dec 2025): `MediaMixer.isCapturing` now reflects real `AVCaptureSession.isRunning` instead of a separate flag — [GitHub PR 1851](https://github.com/HaishinKit/HaishinKit.swift/pull/1851) **[confirmed]**
- Issue #1773 (Aug 2025, 2.0.8): after `close()` the attached camera/mic are detached; not re-attaching sends no frames, re-attaching twice freezes the stream from duplicated inputs — [GitHub issue 1773](https://github.com/HaishinKit/HaishinKit.swift/issues/1773) **[anecdote]**
- Issue #1850 (Dec 2025): AVCaptureSession stopped when a USB audio interface was reconnected; fixed — [GitHub PR 1850](https://github.com/HaishinKit/HaishinKit.swift/pull/1850) **[confirmed]**
- Historic `startRunning` `NSGenericException` crashes (#1238, #1522, #1662) traced to races between `startRunningIfNeeded` and configuration; fixed by making calls thread-safe in PR #1526 — [GitHub issue 1522](https://github.com/HaishinKit/HaishinKit.swift/issues/1522) **[confirmed]**
- Issue #1547: 4K@60 fps via HaishinKit captures wrong aspect ratio/FOV, 4K@30 fine; no fix shown — [GitHub issue 1547](https://github.com/HaishinKit/HaishinKit.swift/issues/1547) **[anecdote]**
- GitHub search `repo:HaishinKit/HaishinKit.swift black screen` returns 31 closed issues; none describes a conflict with a second `AVCaptureSession` in the same process; most black-screen issues are about the RTMP/SRT output or `MTHKView`, and the majority record no cause — [GitHub issue search](https://github.com/HaishinKit/HaishinKit.swift/issues?q=black+screen) **[confirmed listing]**

### Inferences
- For Follo: if `MediaMixer` is only instantiated (and audio attached) but `startRunning()` is never called, it cannot be the cause of black frames in the app's own `AVCaptureSession`. If `attachVideo` is ever called on it (even once) and `startRunning()`/`startCapturing()` runs, the mixer's session will take the camera from the app's session → interruption reason 3 on the app's session.
- Because HaishinKit's session subscribes to `AVAudioSession.interruptionNotification` and may call `startRunningIfNeeded()` on `.began`, an idle mixer that has an attached *audio* device could start its session on an audio interruption (phone call) — this is a code-reading inference; a session with only an audio input would claim the mic (reason 2 on the other session) but not the camera.
- Clean approach for a single camera + streaming: feed HaishinKit from the app's own `AVCaptureVideoDataOutput` via `captureSessionMode: .manual` + `append(sampleBuffer)` so only one `AVCaptureSession` exists.

### Gaps
- `CaptureSession.swift` (IO layer) could not be fetched (path moved; GitHub code search needs auth), so `automaticallyConfiguresApplicationAudioSession` handling inside HaishinKit is unverified.
- No HaishinKit issue or discussion about an idle mixer breaking another session exists; absence of reports ≠ absence of the problem.

## Q4. SwiftUI `fullScreenCover` + `UIViewRepresentable` camera preview: spurious `onDisappear`, double-created views, two sessions

### Takeaway
Multiple reports confirm `onAppear` fires spuriously or twice (iOS 14-era bugs and an iOS 18 regression) and that `makeUIView` can be called more than once; the recurring fix is to own the session in a single `@StateObject`/singleton outside the representable, make start/stop idempotent on a serial session queue, and start from `.task` or `scenePhase` rather than `onAppear`. No thread specifically about `fullScreenCover` + black camera was found.

### Cited Findings
- Camera's green indicator turned on when unrelated views updated; OP blamed `.onAppear` ("is and has been bugged for some time") firing for the camera view when other views opened; accepted fix: start the camera in `.task`, keep `.onDisappear { stopCamera() }` — [Hacking with Swift forum 20998](https://www.hackingwithswift.com/forums/swift/camera-activated-on-views-without-camera/20998) **[anecdote]**
- `onAppear` called when the view hasn't appeared / called on disappear (iOS 14) — [Apple forums 656655](https://developer.apple.com/forums/thread/656655?page=2); [Apple forums 655338](https://developer.apple.com/forums/thread/655338?page=3) **[anecdote, iOS 14 era]**
- `onAppear` firing twice reported on iOS 18 ("doesn't happen on iOS 17, only 18"), workaround `.task` — surfaced in search summary of the same forum tag; primary thread not fetched **[anecdote, unverified]**
- `makeUIView(context:)` called twice although documented to be called once (RealityKit `ManipulationComponent` case, 2025) — [Apple forums 840238](https://developer.apple.com/forums/thread/840238) **[anecdote]**; MapKit `makeUIView` called repeatedly when navigating — [Apple forums 681947](https://developer.apple.com/forums/thread/681947) **[anecdote]**
- SwiftUI remounting the preview host because `session.isRunning` was in the visibility condition caused a black flash; fix = stable `cameraReady` flag — [Apple forums 811759](https://developer.apple.com/forums/thread/811759) **[anecdote]**
- Standard pattern: `UIViewRepresentable` whose backing `UIView` uses `AVCaptureVideoPreviewLayer` as `layerClass`; session owned by a `@StateObject` manager; start on appear/stop on disappear on a dedicated `sessionQueue` guarded by `isRunning` — [Create with Swift](https://www.createwithswift.com/integrating-device-camera-in-swiftui-apps/); [Canopas](https://canopas.com/ios-how-to-integrate-camera-apis-using-swiftui-ea604a2d2d0f) **[tutorial]**
- Community diagnostic checklist: black preview = session never started, permission denied, or no camera input; "camera freezes on phone call" = missing interruption handling; threading problems are the largest share of camera failures (~35%, the author's own tally) — [Axiom camera-capture-diag skill](https://skills.cat/skills/charleswiltgen/axiom/axiom-camera-capture-diag) **[community heuristic]**

### Inferences
- With `fullScreenCover`, the presenting view's `onDisappear`/the cover's `onAppear` ordering is not guaranteed; if a camera manager is created in the cover's body (not `@StateObject`), two managers can exist: one stopped (by a late `onDisappear`), one whose preview layer is bound to the stopped session → black. Log object identities of session and manager in `makeUIView`/`dismantleUIView`/`onAppear`/`onDisappear`.
- If stop is called from `onDisappear` after start from `onAppear` of the *new* instance (out-of-order), an idempotent start/stop pair keyed on a running-generation counter is the robust fix.

### Gaps
- No report found specifically of `fullScreenCover` producing a double camera session; the double-`makeUIView` reports are from other UIKit wrappers.

## Q5. Xcode / `devicectl` launch with screen locked or app not active → black camera until reopened

### Takeaway
No report found that names `devicectl` or Xcode launch as the cause of a black camera. Closest related mechanisms: (a) interruption reason 1 (`videoDeviceNotAvailableInBackground`) when the session starts before the app is foreground-active; (b) the iOS 18/26 SpringBoard watchdog that SIGKILLs camera apps launched via `CameraCaptureIntent` when no session runs and no `AVCaptureEventInteraction` is installed; (c) reason 4 on iPhone (see Q2) where "the camera sometimes fails immediately on launch".

### Cited Findings
- SpringBoard kills the app ("Camera not actively used; AVCaptureEventInteraction not installed", SIGKILL, "Terminated due to signal 9") when launched through a `CameraCaptureIntent`/Camera Control and no capture session is running; workaround: start a throw-away `AVCaptureSession` with one input + `AVCaptureVideoDataOutput` for ~2 s and install an `AVCaptureEventInteraction` on a hidden view; still required on iOS 26 — [JuniperPhoton substack](https://juniperphoton.substack.com/p/addressing-unexpected-terminations) **[anecdote, detailed]**
- TimeMark (full-screen camera app): "the camera sometimes fails immediately on launch, before the user can interact with it" with reason 4; restart of the app does not help, only reboot — [Apple forums 791671](https://developer.apple.com/forums/thread/791671) **[anecdote + DTS "likely bug"]**
- AVCam-style guidance: observe `wasInterruptedNotification`/`interruptionEndedNotification`, restart on `interruptionEnded`; one developer reports restarting there did **not** clear a blank preview — [Apple forums 811759](https://developer.apple.com/forums/thread/811759) **[anecdote]**

### Inferences
- An Xcode/`devicectl` launch while the phone is locked puts the app in the background at `startRunning()` time; the session should get reason 1 and resume on `interruptionEnded` when unlocked. If the app restarts the session itself on `scenePhase == .active` before `interruptionEnded`, a double start/stop race can leave a preview layer bound to a stopped session; make the restart idempotent and driven by notifications, not by scene phase alone.

### Gaps
- No primary source for "devicectl launch + locked screen = black camera"; this remains an untested hypothesis.

## Q6. iOS 17/18/26 regressions for the ultra-wide / 4K with `videoDataOutput`; Apple responses

### Takeaway
No report of black frames specifically from the ultra-wide 4K `videoDataOutput` on iOS 17–26 was found. Confirmed iPhone 17-generation issues: preview freeze on ultra-wide 30↔60 fps switch on iOS 26.1 with `FigCaptureSourceRemote err=-17281` (workaround: keep stabilization on), and recurring -17281 logs on iOS 26.2 with `videoDataOutput` even in minimal setups. Apple's response pattern across these threads is "file Feedback" with no documented fix.

### Cited Findings
- iPhone 17 Pro, iOS 26.1: switching the ultra-wide (0.5x) between 30 and 60 fps freezes the preview, "particularly when stabilization was enabled"; works on iPhone 16 Pro and earlier; logged `FigXPCUtilities signalled err=... FigCaptureSourceRemote err=-17281`; OP's accepted fix: "the new camera system requires stabilization to stay enabled during format changes, so we now force stabilization ON at all times"; no Apple reply — [Apple forums 808479](https://developer.apple.com/forums/thread/808479) **[anecdote]**
- iOS 26.2: recurring `FigCaptureSourceRemote err=-17281` logs during real-time frame processing via `AVCaptureVideoDataOutput`, absent on iOS 18.x with identical code; asked whether it is a regression; no Apple answer in results — search summary citing Apple forums (thread id not captured) **[anecdote, unverified]**
- Ultra-wide at min zoom via AVFoundation gave 16 mm equivalent vs Camera app's 13 mm (iPhone 11/12 mini, 2022); suggested cause/fix: `preferredVideoStabilizationMode = .cinematicExtended` crops, use `.standard`; unconfirmed — [Apple forums 718519](https://developer.apple.com/forums/thread/718519) **[anecdote]**
- Data output stops zooming past a level while the preview layer keeps going, only on physical lenses (wide/ultra-wide/tele), not virtual devices; DTS: not expected, file Feedback — [Apple forums 821988](https://developer.apple.com/forums/thread/821988) **[Apple DTS acknowledges]**
- `automaticallyConfiguresOutputBufferDimensions`: the output "is free to scale the buffers delivered to the delegate to a size suitable for preview" — [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/automaticallyconfiguresoutputbufferdimensions) **[documented]**; developer saw delivered frames much lower-res than `activeFormat` after a preset change — [Apple forums 60453](https://developer.apple.com/forums/thread/60453) **[anecdote]**
- iOS 18.5 era: multiple apps report black camera for a subset of users, reboot-only recovery; "similar reports on Twitter across multiple apps" — [Apple forums 791199](https://developer.apple.com/forums/thread/791199) **[anecdote]**

### Inferences
- On iPhone 17 the ultra-wide format/fps/stabilization change path is fragile; configure the ultra-wide format, fps and stabilization once inside a single `beginConfiguration`/`commitConfiguration`, before `startRunning`, and avoid toggling afterwards. Log `-17281` lines from the console alongside the first-black-frame timestamp.
- Nothing suggests a known iOS regression that returns uniformly black (Y=16) buffers from a healthy running ultra-wide session; such frames most likely mean underexposure (Q1), an interrupted session (Q2), or a wrong preview/session binding (Q4).

### Gaps
- The iOS 26.2 `-17281` thread id and the "iOS 18 onAppear fires twice" thread were only seen in search summaries and not fetched.
- No DXOMARK/lab measurement of ultra-wide *video* low-light floor for iPhone 15/16/17 found.
