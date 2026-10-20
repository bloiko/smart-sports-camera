# Hard test conditions for a wide static amateur-football auto camera, and where to find footage

Scope: conditions that break ball/player detection, pitch detection and virtual-camera following for one wide static camera (Follo: iPhone ultra-wide 0.5x, 4K30, halfway line), with documented failure evidence and public footage/datasets per condition. Research done 2026-10-21 with a limited tool budget (about 20 calls); several vendor pages (support.veo.com) returned HTTP 403 and were read only through search snippets. Items marked **UNVERIFIED** come from prior knowledge and were not checked at a primary source in this session.

## Which conditions are documented as failure modes for automatic sports cameras?

### Takeaway
Vendor support pages document a consistent short list of failure causes: the camera facing the sun or lights, uneven light and hard shadows, a tripod that is too low, obstructions (nets, poles) and placement between two pitches, similar kit colours, small or indoor courts with fast transitions, rain on the lens, and snow (use a coloured ball). The best-known public failure is a ball-like distractor (the Pixellot "bald linesman" case). Night, fog, wind shake, spare balls and spectators in the foreground are rarely documented by vendors, so they have to be tested from our own footage.

### Cited Findings
**Light: sun, shadows, night**
- Trace lists these causes of poor tracking: "Your camera was pointed into the sun"; large light differences across the field, such as tree shadows; and "If a human struggles to identify players", the system will probably struggle too. — [Trace Processing FAQ (PlayerFocus)](https://support.traceup.com/content/processing-faq-playerfocus)
- Veo's setup guide lists a well-lit pitch (daylight or artificial light) as a prerequisite and advises keeping the sun or lights behind the camera so they do not shine into the lenses (read through a search snippet; the page returned 403). — [Veo: How to set up your Veo Cam](https://support.veo.com/hc/en-us/articles/5922516538897-How-to-set-up-your-Veo-Cam-for-recording)
- Veo says the camera adjusts to low light and "recommends even, consistent lighting across the pitch for better tracking" (search snippet only, page 403). — [Veo: How Veo works in different weather conditions](https://support.veo.com/hc/en-us/articles/4465147745169-How-Veo-works-in-different-weather-conditions)
- A Veo Cam 3 review says floodlights can overexpose parts of the video because of contrast across the field; HDR helped as players moved between areas lit differently. — [Soccer Stripes: Veo Camera 3 review](https://soccerstripes.com/veo-camera-3-review/)
- A study of the Trackscore tennis system (not football, but the same kind of static camera) says tracking is challenged in suboptimal light and when light changes during a game. — [FHNW IP6 project page](https://web0.fhnw.ch/ht/informatik/ip6/24fs/24fs_imvs05/index.html)

**Weather: rain, snow, heat**
- Veo: the camera is "water-resistant and not waterproof". It copes with light rain, but in heavier rain the owner should wipe the lenses at half time. For snow: close the rubber covers and use a coloured ball, which is easier to spot. Recording works up to 45 °C. Fog and wind are not mentioned. The article claims the ball is detected "in all weather conditions" but gives no specifics. — [Veo: Record with Veo in different weather conditions](https://www.veo.com/article/how-does-the-veo-camera-perform-in-different-weather-conditions)

**Camera height and position**
- Trace: "Your tripod was too low", so raise it to full height. Place the camera a few steps back from midfield, with sandbags on outdoor fields. — [Trace Processing FAQ](https://support.traceup.com/content/processing-faq-playerfocus)
- Trace, indoor: do not place the camera behind a net, pole or other obstruction, between two fields, or too far back. — [Trace Indoor soccer and futsal FAQ](https://support.traceup.com/content/indoor-soccer-and-futsal-faq)

**Kit colours**
- Trace: tracking fails when jersey colour and number colour are very similar, or when a team's jersey colours match the opponent's. — [Trace Processing FAQ](https://support.traceup.com/content/processing-faq-playerfocus)

**Small pitches, futsal, indoor**
- Trace: on a modified field or court, transitions are faster and PlayerFocus may miss moments; it suggests a "Training Session" recording instead. The AI is tuned for regulation soccer and basketball. — [Trace Indoor soccer and futsal FAQ](https://support.traceup.com/content/indoor-soccer-and-futsal-faq); [Trace: How to record more sports](https://support.traceup.com/content/how-to-record-more-sports)

**Ball-like distractors**
- Pixellot at Inverness Caledonian Thistle (Oct 2020): the AI camera repeatedly followed a linesman's bald head instead of the ball. Pixellot blamed the visual similarity, the camera angle that made the head appear inside the pitch, and the yellow ball. — [PetaPixel](https://petapixel.com/2020/11/02/ai-tracking-camera-mistakes-referees-bald-head-for-a-soccer-ball); [Inverness Courier](https://inverness-courier.co.uk/news/ict-robot-camera-wasn-t-on-the-ball-216638)
- In the same case, the SPFL said it knew of "a few brief instances of wandering cameras" and that Pixellot was working on a fix. — [Inverness Courier](https://inverness-courier.co.uk/news/ict-robot-camera-wasn-t-on-the-ball-216638)

### Inferences
Test matrix for Follo. Columns: condition, what breaks in our pipeline, and evidence level (D = vendor or press documented; I = inferred from our pipeline and general CV knowledge).

| # | Condition | Likely failure in Follo | Evidence |
|---|---|---|---|
| 1 | Night under floodlights | Sensor noise and motion blur hide the small ball; overexposed patches under lights and dark corners shift the grass mask; mains flicker (50 Hz in Ukraine) at 30 fps makes brightness bands or pulses; halos around lamps | D (Veo, review), I |
| 2 | Low sun facing the lens, hard shadows (stand or tree shadows across half the pitch) | Grass mask splits along the shadow edge; players in shadow lose contrast; flare looks like a ball | D (Trace, Veo) |
| 3 | Rain, drops on the lens | Blurred patches, false ball detections from drops, lower contrast | D (Veo) |
| 4 | Fog or mist | Low contrast at the far touchline; the far goal is lost | I (no vendor source found) |
| 5 | Snow-covered pitch, orange ball | Grass-colour pitch finder fails entirely; the line or ball colour assumption breaks | D (Veo: coloured ball) |
| 6 | Worn natural grass, brown patches, faded lines | Holes in the grass mask; touchline detection fails | I |
| 7 | Multi-sport artificial pitch with many lines (rugby, futsal, 5/7-a-side) | Wrong touchline or end line chosen; pitch outline locks onto the wrong rectangle | I |
| 8 | Small-sided pitches (5/7/9-a-side), several pitches side by side | Players from the neighbouring pitch counted; goals inferred wrongly; faster transitions | D (Trace: between two fields, fast transitions) |
| 9 | Indoor futsal (wooden or PU floor, wall reflections, LED lights) | No grass, so the pitch finder cannot work; reflections of players on the floor; LED flicker | D (Trace: indoor), I |
| 10 | Youth matches (small players, small goals, parents on the touchline) | Small objects below the detector's limit; adults on the touchline dominate the detections; goals from player positions shift | I |
| 11 | Spectators' heads or bodies in the foreground (camera at 1.5 m) | Large false detections; the ball is hidden by heads | D (Trace: obstructions), I |
| 12 | Spare balls next to the pitch, a ball-like head | Ball tracker jumps to the distractor; the camera wanders | D (Pixellot bald head) |
| 13 | Similar kits, goalkeeper and referee colours | Team assignment and goal-side logic fail (the referee is counted as a player) | D (Trace: jersey colours) |
| 14 | Camera too low (1.5 m) vs high (5 m) | Low camera: far players are tiny and occluded, the far half is compressed | D (Trace: tripod too low) |
| 15 | Camera not at halfway (corner, behind a goal) | Assumptions about the pitch outline and goal positions break | D (Trace: placement), I |
| 16 | Wind shaking the tripod | The static-camera assumption breaks: the pitch mask and goal positions drift; the virtual camera jitters | I (Trace's sandbags imply it) |
| 17 | Very long pitch that does not fit the frame / half-pitch training | Ends of the pitch are not visible, so the logic that needs "both goals" breaks | I |
| 18 | Changing light during a match (sunset into floodlights, clouds) | A pitch model calibrated once goes stale | D (Trackscore tennis), I |

### Gaps
- No primary-source text was read from Pixellot, Spiideo or XbotGo support centres (searches returned nothing relevant). Reddit and forum threads on XbotGo or Veo failures were not found by the search engine; search Reddit directly (r/bootroom, r/SoccerCoaching, r/veo).
- No vendor documents fog, wind shake, floodlight flicker or spare balls. These come from our own reasoning only.
- I did not find an academic paper that quantifies ball-detection recall by condition (night vs day) for wide static cameras.

## Which public datasets and footage include each condition, and under what licence?

### Takeaway
Only a few open datasets come from fixed wide cameras at amateur level. SoccerTrack v2 (CC BY 4.0, 10 university matches, 4K panoramas, at least one night match) is the best fit and the only one with a verified licence. TeamTrack (MIT repo; licence of the data itself not stated) adds fixed full-pitch soccer, handball and basketball. Nothing found covers rain, snow, fog or youth matches from a static wide camera with a clear licence; those conditions have to be filmed by the owner, or taken from YouTube clips under Creative Commons licences (verify each one).

### Cited Findings
- **SoccerTrack v2**: 10 full-length university-level matches, about 900 min (the paper says 932 min) of 4K panoramic video from fixed BePro systems (Cerberus for 2 matches, a 3-camera panorama for 8). The project page shows sample frames captioned "Daytime Match" and "Night Match". Annotations: player trajectories with IDs and 12 ball-action classes (Pass, Shot, Goal...); the page does not mention per-frame ball positions. **Licence: dataset CC BY 4.0, code MIT; academic and commercial use allowed with attribution.** Hosted on Hugging Face (canonical), with a Google Drive mirror. — [SoccerTrack v2 project page](https://atomscott.github.io/SoccerTrack-v2/); [arXiv 2508.01802](https://arxiv.org/abs/2508.01802v1)
- **SoccerTrack (v1)**: wide-view fisheye from a Z CAM E2-F8 (8K, 30 fps) plus top-view drone (DJI Mavic 3), with bounding boxes. — [CVPRW 2022 paper](https://openaccess.thecvf.com/content/CVPR2022W/CVSports/papers/Scott_SoccerTrack_A_Dataset_and_Tracking_Algorithm_for_Soccer_With_Fish-Eye_CVPRW_2022_paper.pdf); [Kaggle](https://www.kaggle.com/datasets/atomscott/soccertrack). Licence not verified in this session (UNVERIFIED).
- **TeamTrack**: soccer (side and top views), basketball (side, side 2, top), handball (side); 4K–8K full-pitch videos; over 4 million boxes. The repository is MIT; the page names no separate data licence. — [GitHub TeamTrack](https://github.com/AtomScott/TeamTrack); [Kaggle](https://www.kaggle.com/datasets/atomscott/teamtrack). The handball and basketball indoor-hall views are the closest open proxy for **indoor futsal** (hall lighting, floor reflections, many court lines).
- **Futsal-Player-and-Ball-detection (Roboflow Universe)**: classes ball, referee, player; CC BY 4.0; no description, so camera setup and source unknown. — [Roboflow Universe](https://universe.roboflow.com/masters-program/futsal-player-and-ball-detection-ch025)
- **"Ball and Player Detection in Futsal Videos Using YOLOv8" (CEUR-WS Vol-3885)**: the search snippet says the authors plan to build a larger futsal dataset. Camera setup and data availability could not be read (the PDF could not be parsed in this session). — [CEUR-WS paper28](https://ceur-ws.org/Vol-3885/paper28.pdf)
- **Soccana player/ball detection (Hugging Face)**: about 25k curated images (23,372 train rows) from SoccerNet, video-game renders, public match footage and eight Roboflow datasets; classes player, referee, ball. Licence not stated on the page; the label mapping is inconsistent. A search snippet claimed it includes night games under floodlights, but the fetched page does not confirm this. Images are mostly broadcast. — [Hugging Face](https://huggingface.co/datasets/Adit-jain/Soccana_player_ball_detection_v1)
- **SoccerSynth-Detection**: synthetic player-detection data with random lighting, textures and motion blur. A possible source for synthetic night or texture variation. — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v1)
- **SoccerNet-Tracking**: 200 clips of 30 s from 12 games, broadcast (not static). — [arXiv 2204.06918](https://arxiv.org/pdf/2204.06918)
- **PadelTracker100** (padel, CC BY 4.0, single fixed camera, about 100k frames): not football, but a fixed-camera ball-tracking dataset with a verified licence. Useful only for small-ball tracking in an indoor court. — [Zenodo](https://zenodo.org/records/14653706)
- **Veo footage library**: includes night soccer clips from the Veo Cam 3 (useful to look at how a competitor's night output looks; no reuse licence). — [Veo footage library](https://www.veo.com/footage-library)

Per-condition source map:

| Condition | Best source found | Licence |
|---|---|---|
| Night / floodlights | SoccerTrack v2 "Night Match" (fixed panorama) | CC BY 4.0 (verified) |
| Daylight, fixed panorama, many players | SoccerTrack v2, TeamTrack soccer | CC BY 4.0 / MIT repo (data licence unclear) |
| Indoor hall (futsal proxy) | TeamTrack handball/basketball side view; Roboflow futsal images | MIT repo (data unclear); CC BY 4.0 |
| Fisheye very wide view | SoccerTrack v1 wide view | UNVERIFIED |
| Synthetic light variation | SoccerSynth-Detection | not checked |
| Rain, snow, fog, wind, youth, 5/7-a-side, spectators in foreground, spare balls | No open dataset found; own recordings or YouTube CC clips | per clip |
| Ball-like distractors | Press coverage of the Pixellot case (no video licence) | n/a |

UNVERIFIED leads to check at the primary source:
- **Alfheim dataset** (Simula, Tromsø IL stadium, fixed camera array panorama, artificial turf, Norwegian winter matches; usage terms for research): [datasets.simula.no/alfheim](https://datasets.simula.no/alfheim/). The fetch failed on a certificate error. Could cover dim northern light or snow at the touchlines.
- **ISSIA-CNR Soccer dataset** (6 fixed cameras, Italian stadium, research-only terms): not checked.
- SoccerNet videos (broadcast, many night matches) require an NDA and are not usable for a static-camera test.

### Inferences
- For night tests, start with the SoccerTrack v2 night match: it is the only verified-licence, fixed-panorama, amateur-level floodlit match found. Expect a different lens and height from an iPhone 0.5x at the halfway line, so it tests detection and pitch finding more than geometry.
- YouTube offers a "Creative Commons" filter; downloading still needs care with the YouTube Terms of Service, and every clip's CC BY status must be checked by hand. Use it for rain, snow, futsal and youth clips, but treat the footage as a visual check only (usually not static, often edited).
- The most reliable path for Follo's own conditions (Ukrainian municipal pitches, snow, rain, youth matches, 5/7-a-side cages, futsal halls) is the owner's own recordings, since no open dataset covers them from a static phone-height camera.

### Gaps
- No public dataset found of **indoor futsal or 5-a-side from a fixed wide camera** with a clear licence. The Roboflow futsal set has no source description; the CEUR paper's data availability is unknown.
- No static-camera dataset found with rain, snow, fog or youth matches.
- I did not check the licences of SoccerTrack v1, the TeamTrack data, Alfheim, ISSIA or SoccerSynth.
- I did not find Brazilian, Portuguese or Spanish futsal tracking datasets in this pass; a targeted search on SIBGRAPI, RECPAD, Data in Brief and Zenodo is still needed.

## What sample size gives a meaningful test per condition?

### Takeaway
No source in this pass gives a sample-size rule for sports-camera evaluation, so this rests on standard statistics. To claim "shots and goals never leave the frame" for a condition, count events, not minutes. With 0 failures in n events, the 95% upper bound on the failure rate is about 3/n (the "rule of three"). So 30 events give an upper bound of about 10%, and 60 events about 5%.

### Cited Findings
- No cited source found for sample-size practice in auto-camera evaluation (searches returned nothing relevant).

### Inferences
- Suggested minimum per condition (owner's time is limited, so these are floors):
  - Shots and goals in frame (hard rule): at least 30 shots or goals per condition, which gives an upper failure bound of about 10% if 0 are missed. Amateur matches give roughly 10–25 shots per 90 min (estimate, not sourced), so about 2 full matches per condition.
  - Ball-detection recall: at least 10 min of play spread over at least 2 matches and both halves, with labels sampled every 1–2 s (300–600 frames) for a contact sheet.
  - Pitch finding (mask, touchlines, ends): it is static per setup, so count **setups**, not minutes: at least 5 different pitches or camera positions per condition, plus a check every 5 min for light-driven drift (sunset, clouds, floodlights coming on).
  - Distractors (spare balls, head-like objects, neighbouring pitch): at least 10 timestamped incidents per type.
- Keep the project rule: the held-out last 20% of each video, and at least one match the model has never seen, per condition.

### Gaps
- No published benchmark of event counts per condition for Veo, Pixellot or Trace was found.
- The shots-per-match rate for amateur football is an estimate and needs checking from our own checklists in `specs/checklists/`.
