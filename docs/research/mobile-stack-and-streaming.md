# Mobile device and app stack for a phone-based auto-filming sports camera with live streaming (as of October 2026)

Research date: 2026-10-10. Audience: senior Java developer planning one iOS + Android app that records wide 4K, runs an on-device ball detector, crops a 1080p frame, and uploads chunks or streams RTMP to YouTube.

## 1. iPhone 15 (base) and mid-range Android camera, file size, thermal and battery limits

### Takeaway
The base iPhone 15 has a 12MP, 13 mm, f/2.4, 120° ultra-wide camera. The phone records 4K at up to 60 fps and supports HEVC and H.264. Apple-documented 4K60 storage is about 440 MB per minute, so a 90-minute match is roughly 40 GB. Long sessions are limited by heat more than by battery. Apple says the phone slows or stops charging and cuts app frame rates when it overheats, and a third-party test showed an iPhone shutting down after about 15 minutes of streaming in direct sun. The camera stops whenever the app goes to the background, so the app must stay in the foreground with the screen awake.

### Cited Findings
**iPhone 15 camera and video (Apple spec sheet)**
- Ultra Wide camera: 12MP, 13 mm, f/2.4, 120° field of view. Lens correction is listed, but optical stabilization is not (sensor-shift OIS is for the Main camera only). — [Apple Support: iPhone 15 Technical Specifications](https://support.apple.com/en-us/111831)
- Video modes: 4K at 24/25/30/60 fps, 1080p at 25/30/60 fps, 720p at 30 fps. Other modes: HDR Dolby Vision up to 4K60, Action mode up to 2.8K60, Cinematic up to 4K30, and slo-mo 1080p at 120/240 fps. Video is recorded in HEVC and H.264. — [Apple Support 111831](https://support.apple.com/en-us/111831)
- Battery: up to 20 h of video playback, or 16 h streamed. Apple publishes no figure for recording time. — [Apple Support 111831](https://support.apple.com/en-us/111831)
- USB-C is USB 2 (up to 480 Mb/s), which matters for offloading large files by cable. Charging: about 50% in 30 minutes with a 20W+ adapter, MagSafe/Qi2 up to 15W, Qi up to 7.5W. — [Apple Support 111831](https://support.apple.com/en-us/111831)

**File sizes per minute**
- Approximate per-minute sizes as shown in iPhone Settings > Camera > Record Video: 4K60 about 440 MB, 4K30 about 190 MB, 4K24 about 150 MB, 1080p60 about 100 MB, 1080p30 about 60 MB. The source does not say which codec; these numbers match what iOS shows for the default High Efficiency (HEVC) setting. — [AllThings.how](https://allthings.how/how-to-record-a-video-in-4k-60fps-on-iphone/)

**Thermal behavior and charging**
- Apple's ambient operating range is 0–35 °C. When the device is too hot it may slow or stop charging ("Charging On Hold"), dim or blank the display, disable camera features, and lower app frame rates. — [Apple Support: Keep iPhone within acceptable operating temperatures](https://support.apple.com/en-us/118431)
- Charging while recording is physically possible, but charging adds heat and is paused once the phone gets too warm. — [Apple Support 118431](https://support.apple.com/en-us/118431); [Ulanzi, Sep 2026](https://www.ulanzi.com/blogs/knowledges/phone-overheating-battery-grip-recording)
- Overheating reports at the iPhone 15 launch (Sept 2023) covered all four models. 9to5Mac measured about 47 °C on the case. Ming-Chi Kuo blamed thermal design compromises, not the 3nm chip. — [PetaPixel, 2023](https://petapixel.com/2023/09/28/some-users-are-reporting-that-the-iphone-15-is-getting-too-hot/)
- Streaming test on an iPhone 13 at 29 °C outdoors:
  - In shade it streamed a full hour, reaching thermal state "serious" at 60 minutes.
  - In direct sun without a case it shut off at about 15 minutes; with a case, about 30 minutes.
  - Recommendations: avoid direct sun, use cooling strips, and avoid fan coolers because they drain the battery.
  - Source: [Speedify (updated Oct 2026)](https://speedify.com/blog/better-streaming/test-iphone-overheating-when-live-streaming-solutions/)
- Larix (Softvelum) production best practices for long streams:
  - Rehearse for about twice the event length to find heat and battery problems.
  - Use a power bank or mains power.
  - Turn the screen off where possible (Android background mode) and disable overlays to cut heat.
  - Use SRT instead of RTMP on unreliable mobile networks.
  - Most Android devices are limited to about 1080p30 for third-party apps (as of 2021).
  - Source: [Softvelum blog, 2021](https://blog.wmspanel.com/2021/08/larix-broadcaster-production-best-practices.html)
- Ulanzi (Sep 2026) says there is "no single wattage or temperature number." Each setup has to find its working duty cycle by testing, and dropping from 4K to 1080p frees thermal headroom. — [Ulanzi](https://www.ulanzi.com/blogs/knowledges/phone-overheating-battery-grip-recording)

**Background camera on iOS**
- iOS interrupts an `AVCaptureSession` with `videoDeviceNotAvailableInBackground` when the app goes to the background. — [Apple Developer: AVCaptureSession.InterruptionReason](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)

**Mid-range Android example: Galaxy A56 (March 2025)**
- Main camera 50MP with OIS records 4K30 and 1080p30/60. Ultra-wide is 12MP, 123° FOV, 1/3.06" sensor; GSMArena lists no separate video specs for it. Chip is Exynos 1580; battery 5000 mAh; 45W charging. — [GSMArena: Galaxy A56](https://www.gsmarena.com/samsung_galaxy_a56-13603.php)

**Android background limits**
- Apps targeting Android 15 can run `dataSync` and `mediaProcessing` foreground services for at most 6 hours per 24 hours while in the background. — [Android Developers: FGS timeout](https://developer.android.com/develop/background-work/services/fgs/timeout)
- On Android 14+, camera use from a foreground service needs the `FOREGROUND_SERVICE_CAMERA` permission. — [Flutter camera_android_camerax README](https://flutter.googlesource.com/mirrors/packages/+/HEAD/packages/camera/camera_android_camerax/)

### Inferences
- **Storage:** at about 440 MB/min, a 90-minute match in 4K60 needs about 40 GB, and 4K30 needs about 17 GB. Uploading the full 4K source over mobile data is unrealistic. Prefer uploading the 1080p crop (about 60–100 MB/min), or recording 4K30.
- **Ultra-wide image quality:** the iPhone 15 ultra-wide has no OIS and a small f/2.4 sensor. For a tripod shot that is fine, but in evening or indoor light expect noise.
- **Detection field of view:** a 120° FOV covers a full pitch from the sideline, so the 1080p crop is about a quarter of the 4K area. Zoomed-in detail of distant play will be soft.
- **Thermal design for the product:** design for thermal-state monitoring (`ProcessInfo.thermalState` on iOS, `PowerManager` thermal status on Android). Step down from 4K60 to 4K30 or 1080p and lower the ML rate automatically, and ship with a shade or cooling guidance and a power bank.
- **Android ultra-wide 4K:** many mid-range Android phones (e.g. the Samsung A series) appear not to offer 4K on the ultra-wide, only 1080p, and they also limit third-party apps. Check per device with Camera2 `StreamConfigurationMap` and CameraX `Recorder` quality queries.

### Gaps
- **iPhone 15 ultra-wide 4K60:** Apple's spec sheet does not say per lens whether the ultra-wide supports 4K60; it lists only device-wide modes. I believe AVFoundation exposes 4K60 formats on the iPhone 15 ultra-wide, but did not verify this. Confirm with `AVCaptureDevice.formats` on a real device.
- **Apple's official HEVC vs H.264 per-minute table:** no first-party page found; the figures above come from a secondary source. In iOS Settings, 4K60 H.264 ("Most Compatible") is commonly reported at about 400 MB/min, but this is not verified.
- **Recording endurance tests:** no 2025–2026 test found that measures continuous 4K recording time or battery drain while streaming on the iPhone 15 specifically.
- **Mid-range Android ultra-wide video:** no authoritative data found on whether ultra-wide 4K is available on specific devices (A55/A56, Pixel 8a/9a).

## 2. Cross-platform framework options (KMP/Compose Multiplatform, Flutter, React Native, .NET MAUI)

### Takeaway
No cross-platform framework does real-time camera, ML, encoding and RTMP from shared code. In every option the pipeline (capture → inference → crop → encoder → muxer/RTMP) has to be written natively: Swift with AVFoundation and VideoToolbox on iOS, Kotlin with Camera2/CameraX and MediaCodec on Android. The UI and business logic can be shared. For a Java developer, Kotlin Multiplatform is the natural fit: shared Kotlin for logic, upload, API calls and state; native camera and encoder modules; and Compose Multiplatform for the UI. Compose Multiplatform for iOS has been stable since May 2025.

### Cited Findings
- **Compose Multiplatform 1.8.0 (May 2025):** iOS declared stable and production-ready. It supports embedding native views in Compose screens and Compose in native apps, and adds about 9 MB to an iOS app. — [JetBrains blog](https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/)
- **KMP camera libraries:** several community libraries exist (CameraK, Camposer, compose-camera, Peekaboo). They are aimed at preview, photo and simple capture, not frame-level ML and encoding pipelines. — [CameraK](https://gittrend.io/repo/Kashif-E/CameraK); [Camposer on klibs.io](https://klibs.io/package/io.github.ujizin/camposer)
- **React Native VisionCamera V5 (released April 16, 2026):**
  - Built on Nitro Modules, with frame processors on react-native-worklets.
  - Native frame-processor plugins are type-safe Nitro Modules.
  - A new GPU resizer (Metal on iOS, Vulkan on Android) handles resize, YUV→RGB and crop for ONNX/TFLite pipelines, about 5x faster than the CPU resizer.
  - Supports multi-cam sessions and a Constraints API for FPS and HDR.
  - V4 is no longer actively maintained. The README does not mention RTMP or streaming.
  - Sources: [Margelo blog](https://margelo.com/blog/whats-new-in-visioncamera-v5); [GitHub README](https://github.com/margelo/react-native-vision-camera)
- **Flutter camera plugin (Android CameraX implementation):**
  - `streamOptions` in `startVideoCapturing` is unsupported and silently ignored.
  - `setDescriptionWhileRecording` cancels recording unless persistent recording is enabled.
  - The docs do not say whether image streaming plus recording plus preview run reliably together at 4K.
  - Source: [camera_android_camerax README](https://flutter.googlesource.com/mirrors/packages/+/HEAD/packages/camera/camera_android_camerax/)
- **HaishinKit Flutter plugin:** v0.16.0 (Feb 2026), RTMP only. The author says development "is progressing slowly" and recommends other plugins for anyone who needs stability. — [pub.dev haishin_kit](https://pub.dev/packages/haishin_kit)

### Inferences
- **KMP + Compose Multiplatform (best fit for a Java/Kotlin developer):**
  - Share in Kotlin: upload queue, YouTube API client (Ktor), state and settings, and tracking or smoothing math (e.g. a Kalman filter on ball position, crop-window easing).
  - Write natively: on iOS, a Swift module using AVFoundation capture, Core ML/Vision, Metal or Core Image crop, AVAssetWriter, and HaishinKit; on Android, a Kotlin module using CameraX/Camera2, LiteRT, OpenGL crop, MediaCodec, and RootEncoder.
  - Expose both behind an `expect`/`actual` interface.
- **React Native:** VisionCamera V5 gives the most mature cross-platform frame access and ML. RTMP output of the cropped frames still needs a custom native module, e.g. wrapping HaishinKit and RootEncoder.
- **Flutter:** the official camera plugin is too limited for a capture → ML → crop → encode pipeline at 4K. You would write platform channels around native code anyway, and the RTMP plugins are weakly maintained.
- **.NET MAUI:** no evidence of a maintained real-time camera, ML and RTMP ecosystem was found (see Gaps). It is not recommended for this project.
- **Key architectural point:** the crop must be applied to GPU textures or pixel buffers before the hardware encoder (VideoToolbox, MediaCodec input surface). Passing frames through a JS or Dart bridge at 4K would be too slow.

### Gaps
- **.NET MAUI:** I did not research its 2026 state for camera and RTMP (no sources collected).
- **Benchmarks:** no independent benchmarks found comparing frameworks for 4K frame-processing throughput.

## 3. Libraries: streaming (HaishinKit, RootEncoder, Larix), FFmpeg, and on-device ML runtimes

### Takeaway
For streaming, use **HaishinKit.swift** on iOS (RTMP and SRT, BSD-3) and **RootEncoder** on Android (RTMP/RTMPS/SRT/RTSP, H.264/H.265/AV1, can record MP4 while streaming, Apache-2.0). The Larix iOS SDK has been discontinued. FFmpegKit was retired; its binaries were removed in 2025 and the repo archived in July 2026, so avoid it and use native encoders. For ML, use **Core ML** on iOS and **LiteRT** on Android, or ONNX Runtime or ExecuTorch for one model format on both.

### Cited Findings
**HaishinKit.swift**
- Platforms: iOS, macOS, tvOS, visionOS. Protocols: RTMP and SRT, publish and playback; WHIP/WHEP in alpha.
- Features: multi-camera, multi-streaming, video mixing (overlays/watermarks).
- Requirements: iOS 15+; v2.2.0 needs Xcode 26 / Swift 6. License: BSD-3-Clause.
- Related projects: HaishinKit for Android and for Flutter (both RTMP).
- Source: [GitHub HaishinKit.swift](https://github.com/HaishinKit/HaishinKit.swift)

**RootEncoder (pedroSG94)**
- Latest version 2.8.1. Protocols: RTMP/RTMPS/RTMPT, RTSP/RTSPS, SRT, UDP, WHIP.
- Supports Camera1/Camera2 and CameraX (extra-sources module), OpenGL real-time filters, H.265 and AV1 (AV1 not over SRT/UDP), and recording MP4 while streaming.
- Core needs API 16+; extra sources need API 21+. License: Apache-2.0. A separate RootEncoder-iOS repo exists.
- Source: [GitHub RootEncoder](https://github.com/pedroSG94/RootEncoder)

**api.video iOS live-stream SDK:** built on HaishinKit, RTMP only. — [GitHub](https://github.com/apivideo/api.video-ios-live-stream)

**Larix Broadcaster iOS SDK:** "was sunset, it's not available for purchase," and support has ended. The free Larix apps remain available. — [Softvelum Larix iOS SDK page](https://softvelum.com/larix/ios_sdk)

**FFmpegKit**
- Officially retired with "no further releases."
- Binaries for versions below 6.0 were removed on 1 Feb 2025, and for 6.0 on 1 Apr 2025.
- Source: [quoted from the official README on the B4X forum](https://www.b4x.com/android/forum/threads/pndffmpegkit-ffmpeg-library.137426/)
- The repo was archived on 2 July 2026. The README points to **FFmpegKitNext** (source-only, github.com/arthenica/ffmpeg-kit-next) and to community forks on Maven Central, pub.dev and npm. — [GitHub arthenica/ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit)
- Community Flutter fork example: `ffmpeg_kit_flutter_minimal`. — [pub.dev](https://pub.dev/documentation/ffmpeg_kit_flutter_minimal/6.0.5/index.html)

**On-device ML runtimes**
- **LiteRT (successor to TFLite), Jan 28, 2026 update:**
  - Advanced acceleration is now in production. The ML Drift GPU engine covers Android, iOS (Metal), macOS, Windows, Linux and Web, about 1.4x faster than the old TFLite GPU delegate.
  - NPU support (MediaTek, Qualcomm) is delivered via Google Play for On-device AI.
  - `.tflite` models remain compatible, and a new CompiledModel API is added.
  - Source: [Google Developers Blog](https://developers.googleblog.com/litert-the-universal-framework-for-on-device-ai/)
- **NNAPI:** deprecated as of Android 15. Google recommends TFLite/LiteRT in Play Services with the GPU delegate instead. — [Android NDK NNAPI migration guide](https://developer.android.com/ndk/guides/neuralnetworks/migration-guide)
- **MediaPipe Object Detector:** runs on Android, iOS, Web and Python and has a LIVE_STREAM mode with an async result listener. Custom models must be TFLite with metadata. Pre-trained models: EfficientDet-Lite0/2 and SSD MobileNetV2. — [Google AI Edge: MediaPipe Object Detector](https://developers.google.com/edge/mediapipe/solutions/vision/object_detector)
- **ONNX Runtime Mobile CoreML Execution Provider:** needs iOS 13+; the MLProgram format (iOS 15+) supports more operators. — [ONNX Runtime docs](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- **ExecuTorch (PyTorch):**
  - 1.0 shipped with backends including CoreML, XNNPACK, Vulkan and Qualcomm QNN. — [ExecuTorch 1.0 backends overview](https://docs.pytorch.org/executorch/1.0/backends-overview.html)
  - 1.4.0 (about Aug 2026) added CoreML compute-plan reporting across ANE/GPU/CPU, XNNPACK quantized conv improvements and QNN quantization updates, and moved the Android API from Java to Kotlin. — [newreleases.io: ExecuTorch 1.4.0](https://newreleases.io/project/pypi/executorch/release/1.4.0)
  - A community Flutter binding exists (`executorch_flutter`, 0.5.0-rc). — [pub.dev](https://pub.dev/packages/executorch_flutter/versions/0.5.0-rc.4/changelog)

### Inferences
- **Recommended ML path:** train a small detector (e.g. a YOLO-family nano model). Export to Core ML (`.mlpackage`) for iOS (Neural Engine) and to LiteRT `.tflite` for Android (GPU/NPU), or use ONNX Runtime or ExecuTorch for a single format on both.
- **Inference rate:** run inference at a lower rate than capture (e.g. 10–15 Hz on a downscaled 640-px frame) and interpolate the crop window. This keeps heat and battery use manageable.
- **Encoding without FFmpeg:** native encoders cover the whole need. On iOS: AVAssetWriter, VideoToolbox and HaishinKit. On Android: MediaCodec, MediaMuxer and RootEncoder. This avoids FFmpeg licensing and binary-size problems.
- **Two outputs at once:** for simultaneous 4K archive recording and a 1080p cropped stream, use two encoder sessions on the same capture. RootEncoder records MP4 while streaming, but that MP4 is the stream output, not the 4K source.

### Gaps
- **Running both encoders at once:** no source confirms that the iPhone 15 or mid-range Android hardware encoders can sustain 4K60 recording plus a 1080p60 stream encode together. This needs device testing.
- **HaishinKit RTMPS:** the README does not mention RTMPS. YouTube recommends RTMPS, so check HaishinKit's issues and docs.
- **Detector latency:** no benchmarks found for small ball-detection models on the iPhone 15 Neural Engine or on Exynos/Tensor mid-range chips.

## 4. Background upload of large files and chunked/resumable upload

### Takeaway
On iOS, use a background `URLSession` with upload-from-file tasks. These run outside the app process, and they handle IETF-draft resumable uploads automatically (iOS 17+) when the server supports the protocol. On Android, use WorkManager for short, interruptible chunk uploads. For long uploads the user starts, use JobScheduler user-initiated data transfer (UIDT) jobs on Android 14+, because `dataSync` foreground services are capped at 6 h per 24 h on Android 15. On the server, use S3 multipart (5 MiB–5 GiB parts, up to 10,000 parts) or tus.

### Cited Findings
**iOS**
- Since iOS 17, `URLSession` supports resumable uploads per the IETF HTTP WG draft (draft-ietf-httpbis-resumable-upload).
  - The server must support the protocol.
  - Background-configuration uploads resume automatically; manual `resumeData` is needed only for non-background uploads.
  - Source: [Apple: Pausing and resuming uploads](https://developer.apple.com/documentation/foundation/pausing-and-resuming-uploads.md)
- The tus team takes part in standardizing that IETF resumable-uploads draft. — [tus.io blog, 2023](https://tus.io/blog/2023/08/09/resumable-uploads-ietf)
- Apple DTS guidance on background uploads:
  - `discretionary = true` lets the system defer transfers a lot.
  - `timeoutIntervalForResource` should be days, not minutes.
  - BGProcessingTask timing cannot be controlled.
  - Source: [Apple Developer Forums thread 777033](https://developer.apple.com/forums/thread/777033)

**Android**
- Apps targeting Android 15 can run `dataSync`/`mediaProcessing` foreground services for 6 h per 24 h in the background; `onTimeout()` must call `stopSelf()`. — [Android FGS timeout](https://developer.android.com/develop/background-work/services/fgs/timeout)
- UIDT jobs (Android 14 / API 34+):
  - Need the `RUN_USER_INITIATED_JOBS` permission and a notification, and are not subject to App Standby quotas.
  - Run time scales with `setEstimatedNetworkBytes`, and the system may stop them for thermal reasons.
  - There is no Jetpack/WorkManager support; use WorkManager as the fallback below Android 14.
  - Source: [Android UIDT docs](https://developer.android.com/develop/background-work/background-tasks/uidt)

**Server side**
- S3 multipart: parts of 5 MiB–5 GiB (no minimum for the last part), up to 10,000 parts, objects up to 48.8 TiB. Use multipart for objects of about 100 MB or more. — [AWS S3 quotas](https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html)
- tus 1.0.0: HEAD returns `Upload-Offset`; PATCH sends the remaining bytes. Extensions: Creation, Concatenation (parallel/partial uploads), Expiration, Checksum, Termination. — [tus protocol](https://tus.io/protocols/resumable-upload)
- Client libraries: TUSKit (iOS), and a Flutter `tus_background_upload` package exists. — [TUSKit issue tracker](https://github.com/tus/TUSKit/issues/193); [pub.dev tus_background_upload](https://pub.dev/packages/tus_background_upload)

### Inferences
- **Recording as chunks:** roll the recording into fixed segments (e.g. 1-minute fMP4/MP4 or HLS-style segments). Upload each finished segment as its own file task to S3 presigned PUT URLs, or as multipart parts. A lost connection then costs at most one segment, and the server can start processing during the match.
- **Server choice for a Java backend:** S3 multipart with presigned URLs is simplest (fits Spring Boot and the AWS SDK). tus works too (tus-java-server) if you want resumability inside a single large file.

### Gaps
- No quantified limits found for the iOS background `URLSession`: throughput, behavior on cellular vs Wi-Fi, or `allowsExpensiveNetworkAccess` defaults for very large (10+ GB) total volumes.

## 5. YouTube Live: ingest, settings, API, eligibility, archives

### Takeaway
An app should stream to YouTube the "encoder" way: create a `liveBroadcast` and a `liveStream` through the YouTube Data API (OAuth scope `youtube` or `youtube.force-ssl`; each live call costs 1 quota unit of the default 10,000/day), then push RTMPS (H.264, 2 s keyframes, CBR). HEVC requires HLS ingest. The 50-subscriber minimum applies only to YouTube's own mobile app. An encoder or API stream needs a verified channel with live streaming enabled, which can take up to 24 hours the first time. Archives are kept only for streams under 12 hours. Unlisted is a supported privacy status.

### Cited Findings
**Eligibility**
- To go live, the channel must be verified and have had no live-streaming restrictions in the past 90 days. Limits: 10 active streams per channel and 3 per stream key. — [YouTube Help 2474026](https://support.google.com/youtube/answer/2474026)
- Mobile live streaming in the YouTube app:
  - Needs at least 50 subscribers.
  - Channels with 50–999 subscribers may have viewer counts limited, and their archives default to private.
  - The first stream may need a 24-hour activation wait, after which the channel can go live instantly.
  - Source: [YouTube Help 9228390](https://support.google.com/youtube/answer/9228390)

**Encoder settings**
- Protocol: RTMPS recommended (RTMP supported).
- Codecs: H.264, H.265 or AV1; HEVC is recommended for HDR, and HLS is the fallback for HDR.
- Up to 60 fps, 2 s keyframes (4 s maximum), CBR.
- Audio: AAC or MP3, stereo 44.1 kHz at 128 kbps.
- Bitrates (H.264 recommended / minimum): 1080p60 17 / 6 Mbps; 1080p30 14 / 5 Mbps; 720p60 8 / 3 Mbps; 4K30 42 / 11 Mbps. HEVC/AV1: 1080p60 12 / 4 Mbps.
- Source: [YouTube Help 2853702](https://support.google.com/youtube/answer/2853702)
- The ingestion protocol comparison in the YouTube API docs lists RTMP and RTMPS as H.264-only, with normal, low or ultra-low latency. HLS supports H.264 and HEVC, is better suited to 4K and HDR, has higher latency, and does not support ultra-low latency. DASH supports H.264 and VP9. — [YouTube Live: Ingestion protocol comparison](https://developers.google.com/youtube/v3/live/guides/ingestion-protocol-comparison); [HLS ingestion guide](https://developers.google.com/youtube/v3/live/guides/hls-ingestion)
- **Conflict:** the Help Center page says H.265 and AV1 work over RTMP(S), via Enhanced RTMP, while the older API ingestion comparison lists RTMP as H.264-only. **Use H.264 over RTMPS for compatibility.**

**YouTube Data API (live)**
- `liveBroadcasts.insert` requires OAuth scope `https://www.googleapis.com/auth/youtube` or `.../youtube.force-ssl`.
  - Settable fields: `status.privacyStatus` (required), `contentDetails.enableAutoStart`, `enableAutoStop`, `enableDvr`, `recordFromStart`, and others.
  - Error `liveStreamingNotEnabled` means the user must enable live streaming at youtube.com/features.
  - Source: [liveBroadcasts.insert](https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/insert)
- Privacy status can be public, private or unlisted; unlisted means anyone with the link can watch. Requests must be authorized by the Google account that owns the channel. — [YouTube Live Streaming API: Getting started](https://developers.google.com/youtube/v3/live/getting-started)
- Quota: every `liveBroadcasts` method (insert, bind, transition, list, update, delete, insertCuepoint) and every `liveStreams` method costs 1 unit. Default quota is 10,000 units/day per project. `search.list` and `videos.insert` have separate 100-calls/day limits. — [YouTube Data API quota costs](https://developers.google.com/youtube/v3/determine_quota_cost)

**Archives**
- Streams shorter than 12 hours are archived automatically. Longer streams "may not be captured at all," so keep a local backup. — [YouTube Help 6247592](https://support.google.com/youtube/answer/6247592)

### Inferences
- **Typical app flow:**
  1. Google Sign-In with the `youtube.force-ssl` scope.
  2. `liveStreams.insert` (ingestion type rtmp, 1080p, variable frame rate) to get `ingestionAddress` and `streamName`.
  3. `liveBroadcasts.insert` (privacy unlisted, `enableAutoStart`/`enableAutoStop` true).
  4. `liveBroadcasts.bind`.
  5. Push RTMPS.
  - Each match costs about 5–10 quota units, so 10,000/day supports roughly 1,000+ streams per day across all users before you need a quota increase.
- **Google OAuth verification:** a public app using the `youtube`/`youtube.force-ssl` scopes probably needs Google OAuth app verification (sensitive scopes). Plan for it; see Gaps.
- **Mobile upload bandwidth:** 1080p30 H.264 at YouTube's recommended 14 Mbps is too heavy for most mobile uplinks. In practice, use 4–6 Mbps (at or near the H.264 minimum of 5 Mbps for 1080p30) or 720p60, with adaptive bitrate.
- **Users with few subscribers:** they can still stream through the app, because RTMP ingest counts as encoder streaming and the 50-subscriber rule is for the YouTube mobile app. I found no source saying the 50-subscriber rule applies to encoder streaming. Users must still enable live streaming and may wait up to 24 h the first time.

### Gaps
- I did not fetch the page that explicitly states the 24-hour activation for encoder/web streaming; the 24 h figure comes from the mobile requirements page.
- Google OAuth sensitive vs restricted scope classification for `youtube.force-ssl` and the verification timeline were not verified.
- I did not find how DVR length behaves on long streams.

## 6. Alternatives to YouTube (Twitch, Facebook, own SRT/HLS)

### Takeaway
- **Facebook Live:** works through its Live Video API with a `secure_stream_url` (RTMPS) and the `publish_video` permission.
- **Twitch:** limited to about 1080p60 at around 6 Mbps for standard ingest.
- **Your own infrastructure:** SRT ingest from the phone (supported by both HaishinKit and RootEncoder) to a media server or cloud service that outputs HLS gives the most control. It also allows restreaming to YouTube and Facebook from the server.

### Cited Findings
- **Facebook Live Video API:** create a live video and use the returned `secure_stream_url` (rtmps://). Requires Facebook Login and the `publish_video` permission. — [Meta for Developers: Live Video API, Getting Started](https://developers.facebook.com/documentation/live-video-api/getting-started)
- **Twitch** recommended settings (secondary source): 1080p60 at 6,000 kbps, 1080p30 at 4,500, 720p60 at 4,500, 720p30 at 3,000, 2 s keyframes, no 4K. — [Restream (updated Jan 2025)](https://restream.io/integrations/twitch/best-live-streaming-settings-for-twitch/)
- **SRT for mobile:** SRT is better than RTMP on unreliable mobile networks; set latency to about 4× RTT. — [Softvelum best practices](https://blog.wmspanel.com/2021/08/larix-broadcaster-production-best-practices.html)
- **Library support for SRT:** RootEncoder (Android) and HaishinKit (iOS) both publish SRT. — [RootEncoder](https://github.com/pedroSG94/RootEncoder); [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift)

### Inferences
- **Two-tier design:**
  - **MVP:** RTMPS directly to YouTube via the user's OAuth. No streaming servers to run.
  - **Later:** an SRT ingest server (e.g. SRS, MediaMTX, or a cloud live service) that restreams to YouTube, Facebook and Twitch, adds overlays such as score and team logos server-side, and records the archive. Costs rise with bandwidth.

### Gaps
- Twitch's current official broadcasting guidelines page did not render, so the numbers come from a secondary source. Twitch's 2025–2026 Enhanced Broadcasting (HEVC/AV1, multitrack) status was not verified.
- Facebook Live maximum stream duration and resolution limits were not verified.
- No pricing collected for managed SRT/HLS services (AWS IVS, Cloudflare Stream, Mux, etc.).
