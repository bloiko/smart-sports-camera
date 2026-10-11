# Risks

The biggest risk is technical: reliably seeing a small ball in amateur footage. It is tested first, in the first weeks, almost for free.

| Type | Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| Technical | The model loses the ball: small, blurred, hidden by players, poor light | High | Critical | Test on real footage; fine-tune on own frames; Kalman filter; fall back to players |
| Technical | Missed goals: the ball near the goal leaves the crop (confirmed in match 1) | High | Critical | Goal-area framing mode; goal checklist in testing |
| Technical | A single phone cannot cover a full-size pitch, or 1080p cropped from 4K looks soft | Medium | High | Start with small-sided games and basketball; setup guide; two phones for 11×11 |
| Technical | Phone overheats or dies during live streaming | High | High | Recorded mode first; power bank; adaptive quality |
| Technical | Weak mobile data at the pitch | High | Medium | Record locally and resume uploads; live as an option |
| Technical | iOS or YouTube API changes break features | Low | Medium | Isolate integrations; watch changelogs |
| Product | The result is "fine" but not good enough to use weekly | Medium | High | Owner uses it every week; bar = "would I show it to friends" |
| Product | Scope creep (highlights, stats, social) | High | Medium | Strict MVP; every phase is a separate decision |
| Market | Competitors (Veo, XbotGo, Pixellot, Trace, BallerCam, Veo Go) already cover the need | Medium | Medium | Niche: phone only, cheap, iOS + Android, amateurs |
| Market | No community, no first users; owner does not want to interview people | High | High | Owner is the first user; publish videos and measure reactions |
| Legal | Filming people without consent, including children | Medium | High | Consent in the app, private by default, deletion on request, GDPR |
| Legal | Model licences: Ultralytics YOLO is AGPL-3.0, including trained weights | High | Medium | Switch to Apache-2.0 models before any closed release |
| Legal | Dataset licences: SoccerNet is under NDA, DeepSportradar is non-commercial | Medium | Medium | Train the product model on own footage and CC BY / permissive data only |
| Legal | Venue music in live streams (YouTube Content ID) | Low | Low | Option to mute ambient audio |
| Financial | Cloud GPUs and 15–40 GB per match grow with users | Medium | Medium | Measure cost per match; delete originals after processing; process on device |
| Financial | Apple Developer fee and cloud with no income | High | Low | Monthly budget cap; free tiers until the PoC convinces |
| Personal | Motivation drops after 1–2 months | Medium | High | Small phases with visible results; weekly game as the test |
| Personal | Not enough time next to the main job | Medium | Medium | Fixed hours per week; riskiest work first |
