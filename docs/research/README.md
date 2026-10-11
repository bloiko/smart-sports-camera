# Research (October 2026)

Deep research done on 10 Oct 2026. Each file below holds dated findings with source links, inferences and open gaps. Prices and market figures change: re-check before relying on them.

| File | Topic |
| --- | --- |
| [competitors-and-market.md](competitors-and-market.md) | Competitors, prices, subscriptions, market size, user complaints, funding |
| [ball-tracking-technology.md](ball-tracking-technology.md) | Ball detection models, open-source projects, datasets, licences, virtual camera algorithms, on-device speed |
| [mobile-stack-and-streaming.md](mobile-stack-and-streaming.md) | iPhone 15 camera, file sizes, heat, cross-platform options, RTMP libraries, YouTube Live requirements |
| [cloud-costs-and-legal.md](cloud-costs-and-legal.md) | Free tiers, GPU prices, cost per match, app store fees, GDPR, minors, COPPA/BIPA, model licences |

## Key findings

**Market and niche**
- No polished product yet films with one phone and no accessory, follows the ball by cropping, streams live to YouTube, and runs on both iPhone and Android.
- Phone-based competitors are iPhone-only. BallerCam needs a $299 lens and streams at 720p; Veo Go needs two iPhones and has no live mode.
- Veo has 34% one-star reviews on Trustpilot (subscription lock-in, recording-hour limits, billing after cancellation).

**Technology**
- Ball recall is the weak link everywhere (≈ 0.5 for YOLOv8s on broadcast football). The virtual camera must rely on player positions, with the ball refining the framing.
- Recommended camera logic: Kalman filter on the ball, fallback to players after 0.5–1 s without the ball, dead zone, speed and acceleration limits, leading the play, wider crop when uncertain, two-sided smoothing offline.
- `roboflow/sports` (MIT) is the best reference code; its weights are AGPL because they use Ultralytics.
- Apache-2.0 detectors for a closed product: RF-DETR N/S/M/L, D-FINE, DEIM, YOLOX, RT-DETR.
- On device: one or two 640 px passes per frame is realistic at 30 fps; tiling full 4K in real time is not.

**Mobile and streaming**
- iPhone 15 ultra-wide: 12 MP, 13 mm, f/2.4, 120° field of view, 4K up to 60 fps (ultra-wide 4K60 not confirmed).
- File sizes: 4K30 ≈ 190 MB/min, 4K60 ≈ 440 MB/min (≈ 40 GB per 90-minute match).
- Heat, not battery, is the main limit; iOS stops the camera when the app goes to the background.
- No cross-platform framework runs camera → ML → crop → encode → RTMP from shared code; that part is native on each platform. FFmpegKit was retired in 2025.
- YouTube Live via API: OAuth scope `youtube` or `youtube.force-ssl`; RTMPS, H.264, 2-second keyframes, CBR; streams under 12 hours are archived; unlisted is supported.

**Costs and legal**
- One match (≈ 15 GB) exceeds every free storage tier, but paid storage is cheap (≈ $0.10–0.25 per match per month).
- Ultralytics AGPL covers trained weights: the biggest licensing risk for a closed product.
- GDPR: a club publishing video is the controller, the app vendor is a processor; reusing footage to train models makes the vendor directly responsible.
- YouTube may remove live streams of under-16s not visibly with an adult; avoid face recognition entirely (COPPA amendments 2026, BIPA).

## Open questions from the research

- Quality of a single phone on a full 11×11 pitch.
- Heat during 90 minutes of recording with on-device inference.
- Whether mid-range Android ultra-wide cameras record 4K.
- RF-DETR export to Core ML and TFLite.
- How a Ukrainian developer receives Apple and Google payouts.
- Venue and league rules on filming.
