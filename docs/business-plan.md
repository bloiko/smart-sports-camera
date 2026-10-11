# Business plan

The niche is amateurs for whom dedicated sports cameras are too expensive: sell an "operator in your phone" as a subscription, with no hardware. Prices and market figures below come from the October 2026 research (`research/`) and should be re-checked before launch.

## Market and customers

- Amateur teams and pickup groups on rented pitches (football 5×5, 7×7, basketball, padel).
- Amateur leagues and tournaments that need streams.
- Kids' academies and parents who want videos of their child's games.
- Coaches who need game review.

Signals (see `research/competitors-and-market.md`):
- Analyst estimates vary widely: AI sports auto-cameras $486M (2024) → $5.2B by 2034 (Market.us, 26.7%/yr); sports analytics $2.29B (2025) → $4.75B by 2030 (MarketsandMarkets).
- Youth-sports survey (Native Frame with Reeplayer): only 22% of teams stream, 63% of the rest want to; cost is the top barrier (50%); "works on any device" is the most wanted feature (45%).
- Precedent: Balltime (volleyball, phone footage, ~$30/month) was bought by Hudl in February 2025; reported revenue around $100K/month (third-party estimate).

## Competitors and our difference

| Tier | Examples | Model |
| --- | --- | --- |
| Dedicated AI cameras | Veo (€999 + €45–165/mo), Pixellot Air NXT (~$1,149), Hudl Focus, Trace, Spiideo | Hardware + mandatory subscription, aimed at clubs |
| Phone + accessory | XbotGo gimbal ($300–800), BallerCam clip-on lens ($299 + storage plans), FoloCam + DockKit gimbal | Cheaper, still a device; mostly iPhone-only |
| Software only | Veo Go (2 iPhones, no live), Once Sport Autocam (PC/cloud, €5 per game) | Reuses existing cameras |

**Our difference:** one phone and a tripod, zero hardware, iOS and Android, live to YouTube, price like a streaming service. As of October 2026 no polished product combines all of these.

## Monetisation (hypotheses to test)

| Plan | What the user gets | Indicative price |
| --- | --- | --- |
| Free | 1–2 matches a month, watermark, 720p | 0 |
| Player | Unlimited matches, 1080p, highlights | ≈ €5–8 / month |
| Team / league | Streams, several cameras, archive, branding | ≈ €20–50 / month |
| One-off | Processing of one tournament | by agreement |

The watermark on free videos doubles as the main acquisition channel.

## Costs

| Item | Amount |
| --- | --- |
| Apple Developer Program | $99 / year |
| Google Play developer account | ~$25 one-time; new personal accounts need a 12-tester, 14-day closed test |
| Video storage (Cloudflare R2 / Backblaze B2) | 10 GB free, then ≈ $0.015/GB-month (R2) or $6.95/TB-month (B2); ≈ $0.10–0.25 per match per month |
| GPU processing | ≈ $0.10–0.50 per 90-minute match on a rented RTX 4090 (estimate, not measured) |
| Backend hosting | Oracle Always Free for the PoC; ≈ $7/month on Render later |
| Tripod 2–3 m and power bank | ≈ $50–100 one-time |

## Acquisition channels

1. The owner films his own games and posts highlights to Reels, Shorts and TikTok; the watermark advertises the app.
2. Pitch rental venues: free filming in exchange for placement.
3. Amateur leagues and local Telegram chats of players.
4. Later: App Store search and "how to film your game" content.

## Key metrics

- Share of play time with the ball in frame (product quality).
- Matches recorded per user per month (regular use).
- Viewers per match (virality).
- Processing cost per match versus revenue per user.

## Decision point

After phase 4 (beta), decide hobby or business based on three signals: teams come back, people are willing to pay, and quality holds on a 7×7 pitch.
