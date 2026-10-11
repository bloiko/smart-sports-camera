# Cloud infrastructure for a zero-budget PoC, and legal/compliance risks of a phone-based sports auto-filming app (as of Oct 2026)

Context: solo developer in Ukraine, global market. App records amateur football/basketball (4K, ~15 GB per 90-min match), stores it and runs ball detection on a cloud GPU, then streams to YouTube. Research date: 2026-10-10. Prices change often, so check each vendor page before committing. **This is not legal advice.**

## 1. Object storage free tiers and pricing (R2, B2, S3, GCP, Oracle, Supabase/Firebase)

### Takeaway
No free tier holds even one 4K match (15 GB): most cap free storage at 5–20 GB. Paid storage is still cheap. Cloudflare R2 ($0.015/GB-mo, zero egress) and Backblaze B2 (~$0.007/GB-mo, egress free up to 3x stored) are the best fits. AWS and GCP free offers are now credit-based trials, not lasting free storage.

### Cited Findings
- **Cloudflare R2:** free tier of 10 GB-month of Standard storage, 1M Class A and 10M Class B ops per month. Standard storage costs $0.015/GB-month. Infrequent Access costs $0.01/GB-month plus $0.01/GB retrieval, with a 30-day minimum. Egress is free when served via the Workers API, S3 API or r2.dev — [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- **Backblaze B2:** first 10 GB always free, then from $6.95/TB/month. Egress is free up to 3x average monthly storage, then $0.01/GB, and free via CDN/compute partners. Class A/B/C API calls are free. Class D costs $0.004 per 10k, with the first 2,500/day free — [Backblaze B2 pricing](https://www.backblaze.com/cloud-storage/pricing)
- **AWS Free Tier (changed July 15–16, 2025):** new customers get $100 in credits at sign-up and can earn $100 more (up to $200 total). The "free plan" ends at 6 months or when the credits run out, whichever comes first. More than 30 always-free services remain — [AWS What's New, Jul 2025](https://aws.amazon.com/about-aws/whats-new/2025/07/aws-free-tier-credits-month-free-plan/); see also [Rackspace: AWS Free Tier 2026](https://spot.rackspace.com/blog/aws-free-tier)
- **Google Cloud:** $300 free-trial credit for new customers. Always Free includes 5 GB-months of Cloud Storage Standard, 1 e2-micro VM per month and 2M Cloud Run requests per month. These are "subject to change" — [Google Cloud Free](https://cloud.google.com/free). The 90-day trial duration comes from general knowledge and was not confirmed on the fetched page.
- **Oracle Cloud Always Free:**
  - Compute: Ampere A1 up to 2 OCPU and 12 GB RAM in total (1,500 OCPU-hours and 9,000 GB-hours per month), home region only.
  - Storage: 200 GB block/boot storage. Object Storage is 20 GB combined for always-free-only accounts, or 10 GB per tier for paid/trial accounts.
  - Network: 10 TB/month outbound.
  - Idle reclaim: an instance can be reclaimed if, over 7 days, 95th-percentile CPU, network and (A1) memory are all below 20%.
  - Trial expiry: if you exceed 20 GB of Object Storage when the trial ends, all objects are deleted.
  - Source: [Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- **Supabase Free:** 1 GB file storage, 50 MB max upload, 5 GB egress (plus 5 GB cached). Projects pause after 1 week of inactivity, and the limit is 2 active projects. Pro starts at $25/month with 100 GB storage included, then $0.0213/GB — [Supabase pricing](https://supabase.com/pricing)
- **Firebase Storage:** the default bucket has generally required the Blaze (pay-as-you-go) plan. This is general knowledge only and was **not verified** this session; the fetch of the Google free-tier docs page returned a 404.

### Inferences
- **Storage cost per match:** 15 GB × $0.015 ≈ $0.23/month on R2, or 15 GB × ~$0.007 ≈ $0.10/month on B2 (my arithmetic). A PoC with about 20 stored matches (300 GB) would cost roughly $2–5/month. Short retention (for example, delete raw 4K after 7–30 days and keep only highlights or 1080p) keeps it near zero and also helps with GDPR data minimisation.
- **Egress:** R2's zero egress matters if video is pulled to a third-party GPU host (RunPod/Vast) for processing. B2 would also be free up to 3x stored volume.
- Oracle's 200 GB block storage plus 10 TB egress make it the most generous "truly free" option for a backend VM and a temporary video buffer. The idle-reclaim rule and region capacity limits are the main risks.
- Supabase and Firebase are a poor fit for raw 4K files: the 50 MB upload cap applies on Free, and per-GB cost is higher on Pro. They suit metadata and auth only.

### Gaps
- Firebase's current Spark vs Blaze rules for Storage were not verified.
- Under the new AWS free plan, the exact S3 allowance (if any beyond credits) was not verified.
- GCP free egress allowance and the trial duration were not confirmed on a primary page.

## 2. Free and cheap GPU options (Colab, Kaggle, Modal, Lightning, RunPod, Vast.ai)

### Takeaway
Free notebooks (Colab and Kaggle, with roughly 30 GPU-hours/week on Kaggle by user reports) are fine for model training experiments. They are not a production pipeline: the terms target interactive use, sessions are time-limited and quotas are unpublished. Modal's $30/month free credit is the best "free" option for serverless batch inference. RTX 4090 rental runs about $0.34–0.69/hr.

### Cited Findings
Free-tier limits below were read from vendor pages on 21 Sep 2026 by [gpuperhour.com: Free Cloud GPUs in 2026](https://gpuperhour.com/blog/free-cloud-gpus-and-credits):
- **Google Colab free:** GPU is unnamed (users report a T4). There is no published quota, and sessions last "at most 12 hours" depending on availability.
- **Kaggle:** T4/P100 class GPUs, 12-hour sessions. The weekly quota is shown in account settings and users commonly report about 30 h/week; Kaggle docs give no number. Linked Colab Pro or Pro+ accounts get +15 or +30 GPU-h/week.
- **Modal Starter:** "$30 / month free compute".
- **Lightning AI free:** 1 active Studio, 4-hour restarts, 50 GB persistent storage. The monthly credit amount is unconfirmed.
- **Others:** HF ZeroGPU gives 5 min/day free (Gradio Spaces only). SageMaker Studio Lab is closed to new users.

Paid rental (RunPod and Vast.ai rates read 11 Aug 2026), from [Spheron: RunPod vs Vast.ai pricing 2026](https://www.spheron.network/blog/gpu-cloud-pricing-comparison-runpod-vs-vastai-2026/):
- **RunPod RTX 4090:** $0.34/hr on Community Cloud, $0.69/hr on Secure Cloud.
- **Vast.ai RTX 4090:** $0.34–0.50/hr (unverified to verified hosts).
- This source has no A10, T4 or L4 prices.

### Inferences
- **Estimating the cost of one 90-minute 4K match:** these are my own estimates; nothing was benchmarked this session.
  - **Frames:** 90 min × 60 s × 25–30 fps = 135k–162k frames. Halve that by processing every 2nd frame and interpolating the track, which is usually enough to keep a ball in a virtual camera crop.
  - **Throughput:** YOLO-small at 640–1280 px on a 4090 typically handles a few hundred FPS for inference alone. Decoding 4K H.265 (NVDEC) and resizing, or tiling 4K into 2–4 crops for a small ball, will likely be the bottleneck, at roughly 100–300 effective FPS.
  - **Time:** about 10–30 minutes of GPU time, plus 5–10 minutes to download 15 GB and render the output.
  - **Cost:** about 0.25–0.75 GPU-hours × $0.34–0.69/hr ≈ **$0.10–0.50 per match**. Re-encoding a 1080p "virtual camera" output with NVENC adds little.
  - **Method to validate:** run the pipeline on a 5-minute clip, measure end-to-end FPS, then multiply.
- **Kaggle and Colab for the PoC:** they work for training and for manual batch processing of a few test matches. Their terms of use and unpublished quotas make them unsuitable as an automated backend for customers.
- **Alternative to cloud GPUs:** run detection on-device (phone NPU via CoreML/TFLite at reduced resolution) and upload only the cropped stream. This removes cloud GPU cost and most raw-video storage, and reduces the amount of personal data processed (privacy-by-design).

### Gaps
- No verified 2026 hourly prices for T4, A10 or L4 on RunPod/Vast. Older public figures put T4 around $0.2–0.4/hr, but this was not verified.
- No measured YOLO benchmark on 4K sports footage was found. The FPS numbers above are estimates.
- Modal's per-second GPU rates were not fetched.

## 3. App store fees, TestFlight and Google Play testing rules

### Takeaway
Apple charges $99/year and Google Play charges a one-time $25. The bigger barrier for a solo developer is Google's rule that new personal accounts must run a closed test with 12 testers for 14 consecutive days before getting production access.

### Cited Findings
- **Apple Developer Program:** 99 USD per membership year (local equivalent). Fee waivers exist only for nonprofits, educational institutions and government entities. Developing and testing on your own device is free — [Apple: Compare memberships](https://developer.apple.com/support/compare-memberships/)
- **TestFlight:**
  - Testers: up to 100 internal and up to 10,000 external testers (by email or public link), each on up to 30 devices.
  - Builds: up to 100 builds.
  - Review: the first external build needs Beta App Review.
  - Source: [Apple TestFlight](https://developer.apple.com/testflight/). The 90-day build expiry is general knowledge; the fetched page did not state it.
- **Google Play:** personal developer accounts created after 13 Nov 2023 need a closed test with at least 12 testers opted in continuously for 14 consecutive days before they can apply for production — [Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB). The $25 one-time registration fee is widely reported, e.g. [Testers Community](https://www.testerscommunity.com/blog/how-much-does-it-cost-to-publish-an-app-on-google-play), but was not confirmed on a Google page this session.

### Inferences
- Budget about $124 in year one to have both stores.
- An Android-first PoC can start with internal testing, but should start recruiting 12 testers early (for example, the amateur teams being filmed).

### Gaps
- Google Play payout and registration for Ukrainian developers (identity verification, payment methods during martial law) were not researched.
- Apple payment availability from Ukraine was also not researched.

## 4. Cheap backend hosting for Java Spring Boot (Fly.io, Render, Railway, Oracle)

### Takeaway
Oracle Always Free A1 (2 OCPU / 12 GB RAM) is the only option that runs a JVM comfortably at $0. Render's free 512 MB instance sleeps after 15 minutes of inactivity, and Spring Boot cold starts make that painful. Railway and Fly.io now offer only about $5 of usage, not a real free tier.

### Cited Findings
- **Render:**
  - Free web service: 512 MB RAM, less than 1 CPU. Cheapest paid instance is $7/month (512 MB). Free Postgres has 256 MB RAM — [Render pricing](https://render.com/pricing)
  - Free services spin down after 15 minutes of inactivity, with cold starts that can exceed 30 seconds — [PkgPulse, Mar 2026](https://www.pkgpulse.com/guides/railway-vs-render-vs-fly-io-app-hosting-platforms-2026)
- **Railway and Fly.io:** each is described as offering about a $5/month credit with usage-based pricing. Fly machines can auto-stop when idle — [PkgPulse, Mar 2026](https://www.pkgpulse.com/guides/railway-vs-render-vs-fly-io-app-hosting-platforms-2026). This is a secondary source; I did not check the vendor pages.
- **Oracle A1:** 2 OCPU and 12 GB RAM always free, but subject to the idle-reclaim policy — [Oracle docs](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)

### Inferences
- **JVM memory:** Spring Boot on 512 MB is tight. Options are GraalVM native image or Spring Boot with `-XX:MaxRAM` tuning, or simply Oracle A1.
- **Suggested split:** Oracle A1 for the API and job queue, R2 or B2 for video, and Modal or RunPod on demand for the GPU work.
- **Fallback:** if Oracle capacity in the home region isn't available, Render's $7 tier or a Hetzner-class VPS is the cheapest predictable choice. Hetzner was not researched here.

### Gaps
- Exact Railway and Fly.io 2026 plan prices (for example, Railway Hobby at $5/month or Fly's pay-as-you-go minimums) were not verified on the vendors' own pages.

## 5. GDPR / UK GDPR: filming amateur sports, consent, minimisation, retention, erasure, minors

### Takeaway
Once video of identifiable players is uploaded, stored or published by the app, the operator is a data controller (or processor for the club). The household exemption covers only private family use. Publishing on YouTube needs a clear legal basis: consent, or legitimate interest with notice and opt-out. Prior notice, signage, opt-out zones, short retention and erasure tooling are expected. Children need parental consent and extra care.

### Cited Findings
- **Irish DPC guidance on photos and videos at sports (Dec 2025)** — [Irish DPC: Sports – Taking Photos and Videos (PDF)](https://www.dataprotection.ie/sites/default/files/uploads/2025-12/Sports-TakingPhotosandVideos.pdf):
  - When a club posts images or video on its website or social media, GDPR applies and the club is a controller.
  - Family photos kept only for personal memories fall under the household exemption.
  - A legal basis is needed before publishing, chosen from the six Art. 6 bases. If relying on consent, it must be informed (purpose, who captures), clear (where shown, how long kept) and freely given/withdrawable.
  - Parents usually consent for children, but children should be involved depending on age.
  - At large events: inform participants in advance (registration forms), display signs, and offer an opt-out or safe area.
- **YouTube Content ID in live streams:** YouTube scans live streams for third-party content, and matched content can replace the stream with a placeholder or end it. Licensed content needs Content ID allowlisting — [YouTube Help: live stream copyright](https://support.google.com/youtube/answer/3367684). This relates to music, covered in section 7.
- **EDPB video guidance:** the EDPB's Guidelines 3/2019 on processing personal data through video devices are the main EU reference on video and legitimate interest, signage (layered notice), retention and erasure — [EDPB Guidelines 3/2019](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-32019-processing-personal-data-through-video_en). I did not fetch the content this session. From prior knowledge, it says storage should generally be a few days for surveillance, and it centres on CCTV, so it only partly fits sports broadcasting.
- **GDPR Art. 8:** parental consent is required for information-society services offered directly to children under 16 (member states may lower this to 13) — [GDPR Art. 8](https://gdpr-info.eu/art-8-gdpr/). This applies when the child is the user; a filmed child is not necessarily the user.

### Inferences
- **Likely role model:**
  - The team or league organiser that sets up filming and publishing is the controller.
  - The app vendor is a processor for storage and processing (it needs a DPA/Art. 28 terms in its ToS).
  - The vendor becomes a controller for any of its own uses, such as training ML on customer video or analytics.
  - Training ML models on user footage needs a separate legal basis and disclosure, and is high-risk for minors.
- **Practical controls:**
  - In-app pre-match checklist: "players informed, minors' parental consent collected".
  - Downloadable signage/notice template.
  - Unlisted or private YouTube default.
  - Default retention of raw 4K for 7–30 days.
  - A per-match "delete" and "erasure request" flow.
  - Blur on request.
  - Avoid face recognition.
- **UK:** UK GDPR is substantively similar. ICO-specific guidance was not fetched; NSPCC sport safeguarding guidance is commonly used in UK grassroots sport ([NSPCC photography guidance](https://sport.nspcc.org.uk/resource-library/feature-boxes/key-info-photography/), not fetched).
- **DPIA:** large-scale video with children, plus any automated tracking, likely calls for a DPIA (Art. 35). This is an inference, not a verified threshold.

### Gaps
- The ICO's own text on sports photography was not fetched; a historical ICO statement exists ([Pinsent Masons/Out-Law](https://www.pinsentmasons.com/out-law/news/sports-day-photos-are-ok-says-information-commissioner), not fetched).
- No authoritative guidance was found that specifically covers automated AI sports cameras (Veo, Pixellot-style) under GDPR.

## 6. Minors: YouTube rules, App Store rules, COPPA; Ukrainian law; US biometric law (BIPA)

### Takeaway
- **Minors on YouTube:** youth games are high-risk. Live streams of under-16s not visibly accompanied by an adult may be removed, and comments or live chat may be disabled.
- **App Store:** Apple requires explicit consent and a visible recording indicator, in-app account deletion and UGC moderation.
- **COPPA:** the amended Rule (compliance date 22 Apr 2026) counts face templates as personal information.
- **BIPA:** adding face recognition or player re-identification triggers Illinois exposure.
- **Ukraine:** the new GDPR-style Bill 8153 passed first reading in Nov 2024. Final adoption is unconfirmed.

### Cited Findings
- **YouTube Child safety policy** — [YouTube Child safety policy](https://support.google.com/youtube/answer/2801999):
  - "Live streams with minors under 16 who are not visibly accompanied by an adult may be removed."
  - Content depicting children may have comments, live chat, live streaming, recommendations etc. disabled, even when it doesn't violate policy.
  - Revealing a minor's personal information (doxxing) is prohibited.
  - The "made for kids" audience setting must be accurate.
- **Apple App Review Guidelines** — [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  - **2.5.14:** explicit user consent and a clear visual or audible indicator when recording with the camera or mic.
  - **5.1.1:** consent, data minimisation, and in-app account deletion if accounts exist.
  - **5.1.2(i):** disclose sharing with third parties, "including with third-party AI".
  - **5.1.2(vi):** camera or facial-mapping data may not be used for marketing or data mining.
  - **1.2:** UGC apps need filtering, reporting, blocking and contact info.
  - **5.1.4:** apps handling minors' data need a privacy policy and compliance with COPPA/GDPR. "For Kids" wording is reserved for the Kids category.
- **Amended COPPA Rule:** compliance date 22 April 2026. Personal information now includes biometric identifiers (face templates, voiceprints). It requires a written data-retention policy, with deletion when data is no longer reasonably necessary, and a written security program — [BBB National Programs](https://bbbprograms.org/media/insights/blog/coppa-amended); rule text at [Federal Register, 22 Apr 2025](https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule)
- **Illinois BIPA** — [Davis Wright Tremaine](https://dwt.com/blogs/privacy--security-law-blog/2024/08/illinois-bipa-biometrics-law-amended-for-damages):
  - SB 2979 (signed 2 Aug 2024) limits recovery to one violation per person per collection method.
  - Damages remain up to $1,000 (negligent) or $5,000 (intentional/reckless).
  - Electronic signature consent is allowed.
  - It keeps a private right of action without proof of actual injury.
  - The Seventh Circuit held the amendment retroactive (2026 update).
- **Ukraine:**
  - **Current law:** "On Personal Data Protection" No. 2297-VI (2010) uses "owner/handler" terms and gives rights including access, objection, deletion and consent withdrawal. Today's max fine is about UAH 34,000 — [VoxUkraine, Feb 2024](https://voxukraine.org/en/mandatory-informing-control-and-high-penalties-how-the-new-draft-law-changes-the-rules-of-personal-data-protection)
  - **Draft 8153 (new law) and 6177 (new regulator):** propose GDPR-style rights, 72-hour breach notification, and fines up to UAH 150M or 8% of turnover — [VoxUkraine](https://voxukraine.org/en/mandatory-informing-control-and-high-penalties-how-the-new-draft-law-changes-the-rules-of-personal-data-protection)
  - **Status of 8153:** adopted in first reading on 20 Nov 2024 and still being revised as of April 2025. It includes special rules for recording public events — [7eminar.ua, 23 Apr 2025](https://7eminar.ua/news/7121-strafi-zaboroni-prava-yaki-zmini-nese-novii-zakon-pro-personalni); bill card: [Rada bill 8153](https://itd.rada.gov.ua/billInfo/Bills/Card/40707)

### Inferences
- **YouTube for youth games:** stream only with a visible adult (the coach is usually in frame) or upload unlisted after the game. Consider not auto-publishing youth games publicly at all. Collect parental consent through the club, which as controller holds the consent records.
- **COPPA:** applies if the app is directed to children under 13 or has actual knowledge of collecting their data. Target adult organisers and coaches as users, not children. Never run face templates on kids.
- **Biometrics:** avoid face recognition. For player identification, use jersey numbers or OCR and manual tagging, not biometric identifiers, to stay outside BIPA, GDPR Art. 9 and the COPPA biometric definition.
- **Ukraine:** because the product targets EU/UK users, GDPR applies extraterritorially (Art. 3(2)) whatever the Ukrainian law says. Designing to GDPR covers most of current and future Ukrainian law.

### Gaps
- Bill 8153's status after April 2025 (second reading or enactment by Oct 2026) was not found. Check [Rada bill 8153](https://itd.rada.gov.ua/billInfo/Bills/Card/40707) directly.
- Other US state biometric laws (Texas CUBI, Washington) and state age-appropriate design codes were not researched.
- Google Play Families policy was not fetched.

## 7. Venue/league rights to film and broadcast; music copyright in streams

### Takeaway
No primary sources were gathered on amateur venue or league filming rights. These depend on the pitch rental contract, league rules and national law. Music is a concrete risk: YouTube live streams are scanned in real time, and background music at venues can interrupt or end a stream.

### Cited Findings
- YouTube scans live streams for third-party content; on a match it may replace the stream with a placeholder, interrupt or end it, and strikes can follow. Content ID claims on live streams are made after the stream ends, and only if archived. A licence alone is not enough without allowlisting — [YouTube Help](https://support.google.com/youtube/answer/3367684)

### Inferences
- **Audio:** offer "mute ambient audio / replace with commentary" or a low-gain audio option by default for streams. PA music at venues is a real Content ID trigger.
- **Venue terms:** private sports facilities can ban filming or commercial broadcast in their terms of use. Leagues (especially federation-affiliated youth leagues) may hold media rights or have safeguarding rules on filming. The app's ToS should make the user responsible for obtaining venue and league permission. The onboarding checklist can prompt for it.

### Gaps
- Not researched: specific FA, UEFA or national federation grassroots filming rules, typical pitch-rental contract clauses, and the Ukrainian Association of Football's rules. These need dedicated research or a lawyer.

## 8. ML model licensing: Ultralytics AGPL-3.0; datasets (SoccerNet)

### Takeaway
Ultralytics YOLO, including trained weights by Ultralytics' own reading, is AGPL-3.0. Using it in a closed-source app or SaaS requires open-sourcing the whole project or buying an Enterprise licence (price on quote). SoccerNet videos are gated behind an NDA whose terms are not public; treat them as research-only unless confirmed otherwise.

### Cited Findings
- **Ultralytics licence page** — [Ultralytics License](https://www.ultralytics.com/license):
  - Using YOLO code, models or training pipelines means either open-sourcing the entire project under AGPL-3.0 or obtaining an Enterprise License.
  - SaaS or API deployment is listed as a trigger.
  - Compliance means publishing the complete source of the derivative work, including model weights where applicable.
  - "All Ultralytics YOLO trained models fall under the AGPL-3.0 License by default."
  - The Enterprise licence covers YOLO26 and earlier models; pricing is by quote only.
- **SoccerNet:** gated datasets with video require a Hugging Face account and acceptance of the SoccerNet NDA, with a personalised NDA emailed on request. The data page does not state commercial terms — [SoccerNet data](https://www.soccer-net.org/data). The DevKit code is MIT, but that doesn't cover videos — [SoccerNetv2 DevKit](https://github.com/SilvioGiancola/SoccerNetv2-DevKit)

### Inferences
- **Ultralytics' view vs the law:** whether trained weights are a "derivative work" under AGPL is legally contested. However, Ultralytics' public position creates enforcement and dispute risk.
- **Safer alternatives:** permissively licensed detectors, which I did not verify this session:
  - RT-DETR (Apache-2.0, in the original Baidu repo)
  - YOLOX (Apache-2.0)
  - YOLOv7/YOLOv9 (GPL-3.0, still copyleft)
  - D-FINE / RF-DETR (Apache-2.0)
  - Check each repo's LICENSE before use.
- **Training data:** a PoC can use SoccerNet for research benchmarking, but the commercial model should be trained on footage you own or license (with GDPR-compliant consent, ideally adults-only) or on permissively licensed datasets.

### Gaps
- Ultralytics Enterprise pricing is not public.
- The actual SoccerNet NDA text, and whether it bans commercial use, was not accessible.
- The licences of the alternative models were not verified this session.
