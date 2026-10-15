# AVFoundation: causes of constant black frames from AVCaptureVideoDataOutput on iPhone (Apple-documented behaviour)

Context of the question: iPhone 15 (non-Pro), iOS 27, `builtInUltraWideCamera`, `.hd4K3840x2160` preset (also manual `activeFormat` 3840x2160), `AVCaptureVideoDataOutput` with `420v`, `alwaysDiscardsLateVideoFrames = true`, serial delegate queue. Frames arrive at 30 fps but the Y plane is a constant 15–16; sometimes from the first frame, sometimes after ~8–12 s. The system Camera app shows a normal image at the same time. App launched via Xcode/devicectl or by tapping the icon.

Overall finding (important for the report writer): **no Apple primary source describes a mode in which AVFoundation keeps delivering sample buffers at full frame rate whose content is black.** Every documented failure mode on the Apple side (background, another client, multitasking, system pressure, sensitive content) is an *interruption*: the session reports `isInterrupted == true`, posts `wasInterruptedNotification`, and the device "can't continue to provide input" (frames stop). Frames that keep arriving at 30 fps with Y = 16 therefore point to one of: (a) the TCC/permission black-stream case, (b) the app's own buffer handling, or (c) an undocumented bug (Apple DTS treats persistent black camera across apps as a bug to file). Details per question below.

## Q1. Which conditions make AVFoundation deliver black frames rather than stop the session (background, other client, multitasking, system pressure, lock screen, Control Center)?

### Takeaway
Apple documents all of these as *interruptions* (session stops providing frames, `wasInterruptedNotification` with a reason) — not as black frames. The one Apple-adjacent, widely repeated case of "black frames keep flowing" is camera permission not yet granted/denied (TCC): the input "sends a stream of black frames". Apple's own docs never say the pipeline substitutes black pixels during an interruption.

### Cited Findings
- `AVCaptureSession.InterruptionReason` cases (iOS 9+): `videoDeviceNotAvailableInBackground` ("app being sent to the background while using a camera"), `audioDeviceInUseByAnotherClient`, `videoDeviceInUseByAnotherClient` ("video device temporarily being made unavailable (for example, when used by another capture session)"), `videoDeviceNotAvailableWithMultipleForegroundApps` ("running in Slide Over, Split View, or Picture in Picture mode on iPad"), `videoDeviceNotAvailableDueToSystemPressure` ("system pressure, such as thermal duress"), `sensitiveContentMitigationActivated` (iOS 26+, `SCVideoStreamAnalyzer`; resume with `continueStream`) — [Apple: AVCaptureSession.InterruptionReason](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason)
- Background: "Camera usage is prohibited while in the background. If you attempt to start running a camera while in the background, the capture session sends an `wasInterruptedNotification` with this interruption reason. If you don't explicitly call the `stopRunning()` method, your `startRunning()` request is preserved, and when your app comes back to foreground, you receive `interruptionEndedNotification` and your session starts running." — [Apple: videoDeviceNotAvailableInBackground](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)
- Multitasking: "If your capture session configuration disallows accessing the camera while multitasking, the system interrupts it with this reason when a user switches to a multitasking mode like Split View. The system doesn't interrupt your capture session with this reason if `isMultitaskingCameraAccessEnabled` is true." — [Apple: videoDeviceNotAvailableWithMultipleForegroundApps](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailablewithmultipleforegroundapps)
- `isMultitaskingCameraAccessEnabled` defaults to false (true only with the `com.apple.developer.avfoundation.multitasking-camera-access` entitlement when supported); must be set "prior to starting the capture session" — [Apple: isMultitaskingCameraAccessEnabled](https://developer.apple.com/documentation/avfoundation/avcapturesession/ismultitaskingcameraaccessenabled)
- Apple's multitasking article: "The system only allows one app to use the device's camera at a time. ... if your app is running in Stage Manager and another app utilizes the camera, the system suspends your app's use of the camera until the other app finishes. When the system interrupts your app's use of the camera, it notifies your app so you can update your user interface." Also: "When the pressure reaches excessive levels, the capture system shuts down and emits an `wasInterruptedNotification`." And: "Enabling multitasking camera access isn't recommended if your app uses resource-intensive capabilities such as 4K video capture". — [Apple: Accessing the camera while multitasking on iPad](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
- System pressure: "When system pressure reaches a `shutdown` state, the capture device can't continue to provide input, and the capture session becomes interrupted until the pressured state abates." — [Apple: systemPressureState](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property); "When system pressure reaches this level, the capture system automatically shuts down, causing a session interruption." — [Apple: SystemPressureState.Level.shutdown](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.class/level-swift.struct/shutdown)
- Permission / TCC black stream (not Apple, but long-established): "Until the user accepts the dialog, the camera input will send a stream of black frames." — [objc.io, Camera Capture on iOS](https://www.objc.io/issues/21-camera-and-photos/camera-capture-on-ios/). Apple's AVCam sample checks `AVCaptureDevice.authorizationStatus(for: .video)` and calls `requestAccess` *before* starting the session; if not authorized it "shows an error message" — [Apple: AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)
- Reason 4 on iPhone (DTS reply): PiP exists on iPhone too (FaceTime), but an interruption with this reason without multiple foreground apps "should not happen"; users reporting that *other camera apps also go black* and only a reboot fixes it "strongly indicates that this is a bug" — file Feedback. DTS does not recommend adding the `voip` background mode to get multitasking camera access. — [Apple Forums 791671 (DTS answer)](https://developer.apple.com/forums/thread/791671)
- Production report: spike of reason-4 interruptions after iOS 18.4.1, preview stays black, photo capture fails with AVError -11803 "Cannot Record"; only device reboot helps; one developer claims enabling the Multitasking Camera Access capability + `isMultitaskingCameraAccessEnabled = true` before `startRunning()` fixed it (unconfirmed by Apple) — [Apple Forums 785206](https://developer.apple.com/forums/thread/785206)
- Known app-side mimic: a blank preview while `isRunning == true` after lock/unlock turned out to be SwiftUI remounting the preview based on `session.isRunning` fluctuating during the interruption; a temporary `AVCaptureVideoDataOutput` confirmed **no sample buffers at all** arrived during the gap (frames stop, they do not go black) — [Apple Forums 811759](https://developer.apple.com/forums/thread/811759)
- ARKit: DTS says "there's no supported way for you to access the ultra wide camera while an ARSession is running"; a developer saw the ultra-wide feed stop after under a second — [Apple Forums 812818 via search](https://developer.apple.com/forums/thread/812818)

### Inferences
- Lock screen and Control Center on iPhone: locking the device or pulling Control Center backgrounds/deactivates the scene; by the documented rule this yields `videoDeviceNotAvailableInBackground` (frames stop, auto-resume on foreground), not black frames. (Inferred from the background doc; Apple has no page naming Control Center specifically.)
- The system Camera app working at the same moment proves the sensor and ISP are fine; the Camera app will itself interrupt a third-party session with `videoDeviceInUseByAnotherClient` while it is in front, so "same moment" comparisons should be done by log timestamps rather than by switching apps.
- A constant Y = 16 at a steady 30 fps with no interruption notification is inconsistent with every documented AVFoundation interruption path; the TCC case (authorizationStatus `.notDetermined`/`.denied` while the session still runs) is the only Apple-platform behaviour that matches "frames flow, content black". Check `AVCaptureDevice.authorizationStatus(for: .video)` at the moment of the black frames, and whether the app was reinstalled/reset (devicectl installs can reset TCC decisions).
- iPhone 15 has no Camera Control button (iPhone 16+) and no Dynamic Island interactions documented to affect capture; the LockedCameraCapture framework only matters if the app ships a capture extension.

### Gaps
- No Apple document states what pixel content (if any) outputs receive during an interruption; the forum evidence (811759) says none. Nothing found documenting a "black frame substitution" mode.
- No Apple source on whether iOS 27 changed any of this; release notes for iOS 17–27 mentioning camera black frames were not found.

## Q2. Is wasInterrupted / interruptionEnded / runtimeError the right signal; what does Apple recommend observing; does the session stop or deliver black during an interruption?

### Takeaway
Yes: Apple's recommended observation set is `wasInterruptedNotification` (read `AVCaptureSessionInterruptionReasonKey` and, for pressure, `AVCaptureSessionInterruptionSystemPressureStateKey`), `interruptionEndedNotification`, `runtimeErrorNotification`, KVO on `isRunning`/`isInterrupted`, and KVO on `AVCaptureDevice.systemPressureState`. During an interruption the device stops providing input; the `startRunning()` request is preserved and resumes automatically.

### Cited Findings
- `wasInterruptedNotification`: "A notification the system posts when it interrupts a capture session." User-info keys: `AVCaptureSessionInterruptionReasonKey`, `AVCaptureSessionInterruptionSystemPressureStateKey` ("state value that indicates the system pressure level and contributing factors that caused the interruption") — [Apple: wasInterruptedNotification](https://developer.apple.com/documentation/avfoundation/avcapturesession/wasinterruptednotification)
- `isInterrupted` and `isRunning` are KVO-observable; `didStartRunning`, `didStopRunning`, `runtimeErrorNotification` ("posts when an error occurs during a capture session") are the other session signals — [Apple: AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- Apple's sample observer code: observe `.AVCaptureSessionWasInterrupted` and `.AVCaptureSessionInterruptionEnded`, parse `AVCaptureSessionInterruptionReasonKey`, switch on `.videoDeviceInUseByAnotherClient` / `.videoDeviceNotAvailableDueToSystemPressure` — [Apple: Accessing the camera while multitasking](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
- Auto-resume: "your `startRunning()` request is preserved, and when your app comes back to foreground, you receive `interruptionEndedNotification` and your session starts running" — [Apple: videoDeviceNotAvailableInBackground](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)
- WWDC26 session 303 ordering: after `commitConfiguration()` check `captureSession.hardwareCost <= 1.0` (above 1 "the system can't support the configuration"), then `startRunning()`, then `device.observe(\.systemPressureState, options: [.initial, .new])` and "as the system pressure state increases, consider reducing the capture device's frame rate, or throttling any use of the GPU or Apple Neural Engine, or minimizing UI work" — [Apple WWDC26 303: Build a responsive camera app that launches quickly](https://developer.apple.com/videos/play/wwdc2026/303/)
- Apple's AVMultiCamPiP snippet throttles to min 1/20 s / max 1/15 s at `.serious`/`.critical` and logs "Session stopped running due to system pressure level" at `.shutdown` — [Apple: Accessing the camera while multitasking](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
- Evidence that frames stop (not blacken) during interruptions: temporary video data output received no buffers during the blank period — [Apple Forums 811759](https://developer.apple.com/forums/thread/811759)

### Inferences
- For diagnosis, log in one place with timestamps: every `wasInterrupted` reason, `interruptionEnded`, `runtimeError` (`AVCaptureSessionErrorKey`), KVO of `isRunning`/`isInterrupted`, `device.systemPressureState.level/factors`, `session.hardwareCost`, `UIApplication.shared.applicationState` / `UIScene.activationState`, and `AVCaptureDevice.authorizationStatus`. If black frames at 30 fps arrive with **no** interruption and `isInterrupted == false`, the cause is outside the documented AVFoundation interruption model.

### Gaps
- `interruptionEndedNotification` page has no discussion text; `isInterrupted` only says it is KVO-observable. Apple nowhere states explicitly "no sample buffers are delivered while interrupted"; this is inferred from "can't continue to provide input" plus forum evidence.

## Q3. Does launching via devicectl / Xcode "process launch" start a foreground-active scene? Known cases of non-active scene causing black frames?

### Takeaway
`xcrun devicectl device process launch` defaults to `--activate` ("Launches the application in the foreground"), so a devicectl/Xcode launch is foreground by default. No Apple source links a non-active scene to black frames; a non-foreground scene produces the background *interruption* (frames stop), and Apple expects only `sceneWillEnterForeground` + `sceneDidBecomeActive` on a normal launch but tells developers to tolerate quick resign/active flips.

### Cited Findings
- `devicectl device process launch --help` (Xcode on this Mac): "`--activate/--no-activate`  Launches the application in the foreground. (default: --activate)"; `--start-stopped` "Launches the app in a suspended state, waiting for a debugger"; `--console` attaches stdout. — local `xcrun devicectl device process launch --help` output (run 2026-10-15; no public Apple web page for this text was found)
- DTS (Rico, Apple) on a lock-screen-launched camera app seeing `sceneWillEnterForeground, sceneDidBecomeActive, sceneWillResignActive, sceneDidBecomeActive`: "I would expect the first 2 to be called and nothing else, but since the correct delegate method is called at the end, your correct code should execute ... handling the resign case in quick succession is a scenario that you should code for" — [Apple Forums 767914 (DTS)](https://developer.apple.com/forums/thread/767914)
- Background rule (frames stop, auto-resume): [Apple: videoDeviceNotAvailableInBackground](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)

### Inferences
- If the device is locked when devicectl launches the app, the scene cannot become foreground-active and the documented result is an interruption (reason `videoDeviceNotAvailableInBackground`) with resumption on unlock — again not black frames. Log the scene `activationState` when the first black frame arrives to rule this out.
- The "sometimes from the first frame" vs "after 8–12 s" split does not map to the launch method in any documented way; nothing found tying Xcode/devicectl launches to black camera output.

### Gaps
- No Apple documentation page for `devicectl process launch` semantics on the web (only the CLI help). No Apple or forum case found where a launched-but-inactive scene yields black (rather than no) frames.

## Q4. 4K + ultra-wide on iPhone 15 (non-Pro): does builtInUltraWideCamera support 3840x2160 with AVCaptureVideoDataOutput? Documented limits?

### Takeaway
Apple publishes no per-lens format list; the authoritative source is `device.formats` on the phone. Apple's spec sheet gives device-level "4K ... at 24/25/30/60 fps" with a 12 MP Ultra Wide; the only documented per-format restrictions are `unsupportedCaptureOutputClasses`, `isVideoBinned`, `videoSupportedFrameRateRanges`, and the `activeFormat` vs `sessionPreset` mutual exclusion. Apple also warns that 4K formats raise `hardwareCost` and that high-resolution-photo formats may miss the target frame rate with a video data output.

### Cited Findings
- iPhone 15 tech specs: "4K Dolby Vision video recording at 24 fps, 25 fps, 30 fps, or 60 fps"; "12MP Ultra Wide: 13 mm, ƒ/2.4 aperture and 120° field of view"; the video section does not say which lens supports which mode — [Apple Support: iPhone 15 Technical Specifications](https://support.apple.com/en-us/111831)
- `activeFormat` vs preset: "In iOS, a device's active format and a capture session's `sessionPreset` are mutually exclusive. If you set a device's active format, the session ... changes its preset to `inputPriority`. Likewise if you set a preset on a capture session, the session assumes control of its input devices, and configures their active format appropriately." Also: "If you configure a session to use an active format intended for high resolution still photography, and you apply zoom, orientation, or format changes to an `AVCaptureVideoDataOutput`, the system may not meet the target framerate." — [Apple: activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)
- `unsupportedCaptureOutputClasses`: "capture formats with a given mediaType are available for use with all AVCaptureOutput subclasses that accept that media type. However, this isn't always the case. For example, formats for high-resolution photo capture may not support the AVCaptureMovieFileOutput class due to bandwidth limitations." — [Apple: unsupportedCaptureOutputClasses](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/unsupportedcaptureoutputclasses)
- `AVCaptureDevice.Format` exposes `isVideoBinned`, `videoSupportedFrameRateRanges`, `isMultiCamSupported`, `isVideoHDRSupported`, `supportedColorSpaces`, `isHighestPhotoQualitySupported` — [Apple: AVCaptureDevice.Format](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format)
- Hardware cost (WWDC26 303): "A value above one means the system can't support the configuration"; contributors: number of cameras, active formats "such as using 1080p or 4K", the format's **max** frame rate ("Hardware cost assumes the format's max frame rate ... Use the framerate override property to reduce the cost"), and "Binned formats use less hardware bandwidth" — [Apple WWDC26 303](https://developer.apple.com/videos/play/wwdc2026/303/)
- Multitasking doc: 4K video capture is called "resource-intensive" — [Apple: Accessing the camera while multitasking](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
- Field reports (no Apple reply): a 4K 120 fps request on iPhone 16 Pro gave a black preview *and* black recording with `.hd4K3840x2160` preset set and then `activeFormat` assigned (preset/format conflict suspected by readers) — [Apple Forums 772769](https://developer.apple.com/forums/thread/772769); several Pro models return no 3840x2160@60 format for the wide camera despite the Camera app doing 4K60 — [Apple Forums 809047 via search](https://developer.apple.com/forums/thread/809047); on a different device "Only .builtInUltraWideCamera supports" 4K60 — [Apple Forums 659589 via search](https://developer.apple.com/forums/thread/659589)
- Lower-resolution delivery: `AVCaptureVideoDataOutput` can silently deliver preview-sized/downscaled buffers (`deliversPreviewSizedOutputBuffers`, `automaticallyConfiguresOutputBufferDimensions`) — [Apple: AVCaptureVideoDataOutput](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput); thread [Apple Forums 60453](https://developer.apple.com/forums/thread/60453)

### Inferences
- Setting `.hd4K3840x2160` **and** a manual `activeFormat` in the same configuration is contradictory per the `activeFormat` doc; whichever is set last wins and the other is overridden. Use exactly one: either the preset, or `sessionPreset = .inputPriority` + `activeFormat` + min/max frame durations inside one `beginConfiguration/commitConfiguration`.
- The forum 4K120 black case shows that an unsupported/conflicting format can produce black output rather than an error, so dump `device.formats` on the iPhone 15 ultra-wide, pick a 3840x2160 format whose `videoSupportedFrameRateRanges` covers 30 fps, check `unsupportedCaptureOutputClasses` does not contain `AVCaptureVideoDataOutput`, and log `device.activeFormat` + `session.hardwareCost` after commit.

### Gaps
- No Apple document listing `builtInUltraWideCamera` formats for iPhone 15; the Unity report of only 640x480 on an iPhone 16 ultra-wide is a third-party, unverified claim.

## Q5. Setting activeVideoMinFrameDuration/maxFrameDuration before vs after commitConfiguration / sessionPreset: documented pitfalls

### Takeaway
Apple documents that choosing a new session preset resets `activeVideoMinFrameDuration` to its default, that values outside the active format's ranges raise `NSInvalidArgumentException`, that `lockForConfiguration()` is mandatory, and that format + durations should be set together between `beginConfiguration()` and `commitConfiguration()`.

### Cited Findings
- "The capture device automatically chooses a default minimum frame duration based on its active format. ... return to the default ... by setting ... `CMTime.invalid`. Choosing a new preset for the capture session also resets this property to its default value. Attempting to set this property to a value not found in the active format's `videoSupportedFrameRateRanges` array raises an exception (`invalidArgumentException`). ... you must call `lockForConfiguration()` ... Otherwise, setting the value of this property raises an exception." — [Apple: activeVideoMinFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration)
- Apple's canonical sequence: `beginConfiguration()` → `lockForConfiguration()` → `activeFormat` → `activeVideoMinFrameDuration` → `activeVideoMaxFrameDuration` → `unlockForConfiguration()` → `commitConfiguration()` — [Apple: activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)
- Forum reports (not Apple): durations had no effect until the preset was explicitly set to `inputPriority`; on iOS 16.2 the frame rate reset unless set after the input was added to the session — [Apple Forums 664978 via search](https://developer.apple.com/forums/thread/664978)
- WWDC26: `hardwareCost` assumes the format's max frame rate; use the "framerate override property" (`AVCaptureDeviceInput.videoMinFrameDurationOverride`) to lower cost when running 30 fps on a 60 fps format — [Apple WWDC26 303](https://developer.apple.com/videos/play/wwdc2026/303/); property page exists at [Apple: videoMinFrameDurationOverride](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput/videominframedurationoverride)

### Inferences
- Order that avoids every documented reset: add input → set preset (or `.inputPriority`) → lock device → `activeFormat` (if using inputPriority) → min/max durations → unlock → commit. Setting durations and then changing the preset (or setting `activeFormat` after the preset, which flips the preset to `inputPriority`) silently discards the durations.

### Gaps
- Apple does not document whether `activeVideoMaxFrameDuration` is also reset by a preset change (likely symmetric; not confirmed).

## Q6. Memory and CPU pressure: can heavy background computation make the capture pipeline deliver black frames (vs. dropping frames) on iPhone 15?

### Takeaway
Apple documents two effects of load: dropped frames (`alwaysDiscardsLateVideoFrames`) and, under thermal/system pressure, frame-rate throttling or a shutdown *interruption*. Black frames under load are not documented anywhere.

### Cited Findings
- "If this property is true, the output immediately discard[s] frames that captured while the dispatch queue handling existing frames blocks in the `captureOutput(_:didOutput:from:)` delegate method. When set to false, the output gives delegates more time to process old frames before it discards new frames, but application memory usage may increase significantly ... The default is true." — [Apple: alwaysDiscardsLateVideoFrames](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes)
- "Video capture is also sensitive to performance issues once the device enters a pressured state." "As the device heats up, performance gets harder to maintain, because the system throttles to adapt." Mitigations: reduce frame rate, throttle GPU/ANE, minimize UI work — [Apple WWDC26 303](https://developer.apple.com/videos/play/wwdc2026/303/)
- Multitasking with other resource-heavy apps "can lead to frame drops or poor capture quality" — [Apple: Accessing the camera while multitasking](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
- Shutdown pressure → interruption, not black — [Apple: systemPressureState](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property)
- App-side buffer bugs stop delivery rather than blacken it: an iOS 14 case where frames stopped after ~4 s was a leaked attachments dictionary from wrong bridging — [Apple Forums 660034](https://developer.apple.com/forums/thread/660034); "processed CMSampleBuffers come out black" cases were caused by the app's own re-rendered pixel buffers — [Apple Forums 700731](https://developer.apple.com/forums/thread/700731), [Apple Forums 90801](https://developer.apple.com/forums/thread/90801)
- Apple advises native formats (`420v`/`420f`) over BGRA for memory/performance — [Apple: AVCaptureVideoDataOutput](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput), TN3121

### Inferences
- The "normal for 8–12 s then black" pattern coincides with the time a 4K + heavy compute pipeline takes to heat up, but the documented thermal response is throttling → `.serious/.critical` → `.shutdown` interruption. Check `systemPressureState` at the switch moment; if it is `.nominal`/`.fair` and no interruption fires, thermal pressure is ruled out.
- Because the delegate receives buffers from a fixed pool, any in-place write (zeroing, cropping, Metal blit into the same IOSurface) or a retained-then-reused buffer in the app's pipeline could make *every* delivered frame look black; the evidence pattern (Y exactly 16, chroma presumably 128) matches a cleared video-range buffer. Verify by sampling Y directly in `captureOutput` before any processing and by logging `CVPixelBufferGetBaseAddressOfPlane`/`CMSampleBufferGetImageBuffer` validity.

### Gaps
- No Apple or forum source describes black (rather than dropped/stopped) frames under CPU/memory pressure.

## Q7. Is Y = 16 exactly the video-range black level for 420YpCbCr8BiPlanarVideoRange, vs 0 for full range?

### Takeaway
Yes. Apple defines `420v` as "video-range (luma=[16,235] chroma=[16,240])", so Y = 16 (Cb = Cr = 128) is nominal black; the full-range sibling `420f` is luma [0,255]. A constant 15–16 means a legally black video-range frame (lens covered, no exposure, or a buffer cleared to black-level by software), not a zero-filled buffer.

### Cited Findings
- "Bi-Planar Component Y'CbCr 8-bit 4:2:0, video-range (luma=[16,235] chroma=[16,240]). baseAddr points to a big-endian CVPlanarPixelBufferInfo_YCbCrBiPlanar struct." — [Apple: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange](https://developer.apple.com/documentation/corevideo/kcvpixelformattype_420ypcbcr8biplanarvideorange)
- Apple vImage docs: video range typically 16–235 for Y′ and 16–240 for Cb/Cr; clamped video range parameters Yp bias 16, Yp range 235 — [Apple: vImage_YpCbCrPixelRange](https://developer.apple.com/documentation/accelerate/vimage_ypcbcrpixelrange)
- CVPixelBuffer.h lists `420f` (FullRange) as luma [0,255], chroma [1,255] — [CVPixelBuffer.h (SDK header mirror)](https://jenkins.heirloomcomputing.com/downloads/MacOSX10.8.sdk/System/Library/Frameworks/CoreVideo.framework/Headers/CVPixelBuffer.h)
- Real camera buffers in `420v` can exceed the nominal range (Y up to 255 reported on iOS 17.3.1), so values are not hard-clamped by the ISP — [Apple Forums 746874](https://developer.apple.com/forums/thread/746874)

### Inferences
- A value of 15 next to 16 is consistent with sensor noise around black level (a real dark frame), whereas a software-cleared buffer would be exactly 16 (or 0) everywhere. Measure the Y-plane standard deviation: ~0 → software-filled; small nonzero → genuinely dark exposure (covered lens, exposure/ISO driven to minimum, e.g. a stuck custom `exposureMode`).
- Because a zero-filled (uninitialised) buffer would read Y = 0, the observed 16 means something produced a *valid* black video-range image: either the ISP (no light / permission-masked stream) or code that knows the format.

### Gaps
- Apple does not document what pixel values the "permission not granted" black stream contains (0 vs 16); not verified.

## Additional documented mechanisms worth checking (iOS 26/27-specific)

### Takeaway
iOS 26 introduced Deferred Start; for apps linked against the iOS 26+ SDK it runs automatically and the session "waits until each output that provides streaming data to your app sends its first frame" when a non-deferred output exists. This changes *when* frames start, not their content, but a misconfigured deferred data output receives no frames (not black ones). `sensitiveContentMitigationActivated` (iOS 26) is a new interruption that pauses the stream only when the app uses `SCVideoStreamAnalyzer`.

### Cited Findings
- "Deferred Start is a feature that allows you to control, on a per-output basis, whether output objects start when or after the session is started. ... If there are AVCaptureOutput objects that have isDeferredStartEnabled set to false, then the session waits until each output that provides streaming data to your app sends its first frame. ... By default, for apps that are linked on or after iOS 26, this value is true." — [Apple: automaticallyRunsDeferredStart](https://developer.apple.com/documentation/avfoundation/avcapturesession/automaticallyrunsdeferredstart)
- "an AVCaptureVideoDataOutput that you intend to use for displaying preview should set this value to false, so that the frames are available as soon as possible. For apps that are linked on or after iOS 26, this property value is true for AVCapturePhotoOutput and AVCaptureFileOutput subclasses if supported, and false otherwise. ... Set this value before committing the configuration." — [Apple: isDeferredStartEnabled](https://developer.apple.com/documentation/avfoundation/avcaptureoutput/isdeferredstartenabled)
- `runDeferredStartWhenNeeded()` only when `automaticallyRunsDeferredStart == false`; call once per configuration commit, after the first frame is displayed, not on the main queue — [Apple: runDeferredStartWhenNeeded()](https://developer.apple.com/documentation/avfoundation/avcapturesession/rundeferredstartwhenneeded())
- Sensitive content interruption: resume via `SCVideoStreamAnalyzer.continueStream` — [Apple: sensitiveContentMitigationActivated](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/sensitivecontentmitigationactivated)
- Third-party summary (unverified): "Deferred Start does not apply automatically to a data output" — [Blake Crosley blog](https://blakecrosley.com/blog/responsive-camera-app-ios-27)

### Inferences
- Deferred start is a candidate for "no frames", not for "black frames at 30 fps"; since Follo's data output defaults to `isDeferredStartEnabled = false`, it is probably not involved, but logging `sessionWillRunDeferredStart/DidRun` is cheap.

### Gaps
- No iOS 26/27 release note found that mentions black camera frames or changes to `AVCaptureVideoDataOutput` delivery.

## Consolidated checklist of causes (documented vs. inferred) and fixes

### Takeaway
Ranked from "documented and matches frames-flowing-but-black" to "documented but produces stopped frames" to "inferred".

### Cited Findings
1. Camera permission `.notDetermined`/`.denied` while session runs → stream of black frames. Fix: check `authorizationStatus`, `requestAccess` before `startRunning()`; verify the TCC prompt was not reset by reinstall via devicectl. — [objc.io](https://www.objc.io/issues/21-camera-and-photos/camera-capture-on-ios/), [Apple AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)
2. Preset vs `activeFormat` conflict / unsupported 4K format for the output → observed black preview and black recording (forum, no Apple reply). Fix: use `.inputPriority` with explicit format or the preset alone; validate `unsupportedCaptureOutputClasses`, frame-rate range, `hardwareCost <= 1`. — [Apple: activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat), [Apple Forums 772769](https://developer.apple.com/forums/thread/772769), [WWDC26 303](https://developer.apple.com/videos/play/wwdc2026/303/)
3. Reason-4 (`videoDeviceNotAvailableWithMultipleForegroundApps`) bug on iPhone, iOS 18.4.1+: persistent black camera, -11803, reboot needed; DTS calls it a bug. Mitigation reported by one dev: Multitasking Camera Access capability + `isMultitaskingCameraAccessEnabled = true` before start (Apple warns against enabling it for 4K). — [Forums 791671](https://developer.apple.com/forums/thread/791671), [Forums 785206](https://developer.apple.com/forums/thread/785206), [Apple multitasking doc](https://developer.apple.com/documentation/avkit/accessing-the-camera-while-multitasking-on-ipad)
4. Background / locked device → interruption reason 1, frames stop, auto-resume. — [Apple](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)
5. Another client (Camera app, FaceTime, ARKit ARSession) → interruption reason 3, frames stop. — [Apple](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodeviceinusebyanotherclient), [Forums 812818](https://developer.apple.com/forums/thread/812818)
6. System pressure `.shutdown` → interruption reason 5, frames stop; throttle frame rate at `.serious/.critical`. — [Apple systemPressureState](https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property)
7. Frame-duration settings silently reset by preset changes → wrong fps, not black. — [Apple activeVideoMinFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration)
8. Delegate too slow → dropped frames (`captureOutput(_:didDrop:from:)`), not black. — [Apple alwaysDiscardsLateVideoFrames](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes)
9. App-side buffer misuse (in-place writes, retained buffers, wrong plane/stride, re-rendered buffers) → black or frozen output in several forum cases. — [Forums 700731](https://developer.apple.com/forums/thread/700731), [Forums 90801](https://developer.apple.com/forums/thread/90801), [Forums 660034](https://developer.apple.com/forums/thread/660034)

### Inferences
- Given Y = 16 ± 1 at steady 30 fps with the system Camera app healthy, the most probable Apple-documented explanations are (1) and (2); (3) is the only documented iPhone-specific *black camera* bug but it also blacks out other apps. Instrumenting the interruption/pressure/authorization signals in one timestamped log will discriminate among them in a single run.

### Gaps
- No primary source for an iOS 27 regression; the owner should file Feedback with a sysdiagnose if (1)–(3) are excluded, per DTS guidance in thread 791671.
