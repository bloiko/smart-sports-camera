# Sources of amateur / grassroots football match video (static wide camera) for testing and training Follo

Scope: legally usable footage that looks like what Follo users will film (one static phone or wide camera, amateur pitch). Status as of 2026-10-21. Not legal advice; uncertainty is marked.

## 1. YouTube Creative Commons (CC BY) videos: how to find them, and may they be downloaded?

### Takeaway
YouTube lets uploaders mark videos CC BY (linked to CC BY 4.0) and offers a "Creative Commons" search filter plus an API filter (`videoLicense=creativeCommon`, `videoDuration=long`), which is the best way to find full amateur matches. But YouTube's Terms of Service separately forbid downloading any Content, CC or not, except with YouTube's written permission, through a Service feature, or as "applicable law" allows. So a CC BY licence covers copyright, and downloading with yt-dlp is still a breach of contract with YouTube (low practical risk, but not "clean").

### Cited Findings
- YouTube's help page says creators can mark videos with a "CC BY license" (it links to CC BY 4.0). To find such videos you "select Creative Commons from the list of advanced search filters". Reusers "need to give them credit (attribution)": title, author, source URL and licence info, e.g. "is licensed under CC BY". The page says nothing about downloading. — [YouTube Help: Creative Commons](https://support.google.com/youtube/answer/2797468?hl=en)
- YouTube Terms of Service (dated December 15, 2023, the current version when fetched), "Permissions and Restrictions": you may not "access, reproduce, download, distribute, transmit, broadcast, display, sell, license, alter, modify or otherwise use any part of the Service or any Content" unless (a) the Service expressly allows it, (b) YouTube and, if applicable, the rights holders give prior written permission, or (c) applicable law allows it (the exception structure was confirmed in the Ukrainian-language version of the same page). You also may not "access the Service using any automated means (such as robots, botnets or scrapers)" except public search engines following robots.txt, or with YouTube's prior written permission. — [YouTube Terms of Service](https://www.youtube.com/t/terms?hl=en&gl=US)
- The ToS licence uploaders give to other users is narrow: "You also grant each other user of the Service a worldwide, non-exclusive, royalty-free license … only as enabled by a feature of the Service (such as video playback or embeds)". The ToS text does not mention Creative Commons at all. — [YouTube Terms of Service](https://www.youtube.com/t/terms?hl=en&gl=US)
- YouTube Data API v3 `search.list` supports `videoLicense` = `creativeCommon` ("Returns only videos with a Creative Commons license"), `videoDuration` = `long` ("Only videos longer than 20 minutes") and `videoDefinition` = `high`. This makes systematic, ToS-compliant discovery of candidate CC matches possible (search and metadata only, not download). — [YouTube Data API search.list](https://developers.google.com/youtube/v3/docs/search/list)
- Secondary commentary (blog, low authority): YouTube rarely sues individuals for downloading alone; its "primary enforcement mechanism is account termination and IP blocking". No source found saying a CC licence overrides the YouTube ToS. — [legallyexplained.com](https://legallyexplained.com/is-it-legal-to-download-youtube-videos/)
- A university project statement notes downloading YouTube content without permission "may violate YouTube's Terms of Service and applicable copyright laws". — [UCL students project statement](https://students.cs.ucl.ac.uk/2024/group1/docs/appendices/youtube-statement)
- The "applicable law" route in Ukraine is weak: the TDM exception in Law No. 2811-IX (Art. 22(2)(14), in force 1 Jan 2023) is reported to cover only research, only scientific publications, only where not opted out, and it is "not protected from contractual override". — [Jonathan Band / infojustice](https://infojustice.org/?p=45509); [EIFL comments, Oct 2023](https://www.eifl.net/system/files/resources/202310/eifl_comments_ukraine_ip_dialogue_19_oct_2023.pdf)

### Inferences
- Realistic legal position: (a) testing on a private Mac with a downloaded CC BY match: copyright is cleared by CC BY 4.0, which allows any use including commercial and ML; the remaining issue is the ToS download ban (a contract matter with YouTube, enforced by account or IP blocks). Low practical risk, but technically a breach. (b) Training a shipped commercial model: CC BY 4.0 permits it (attribution needed; for model weights, keeping a list of sources with credits is the common reading), but the same ToS issue applies to how the file was obtained. The cleanest route is to email the channel owner, ask for the original file, and get written permission. That removes both the ToS issue and the doubt about whether the CC mark is genuine; amateur uploaders often have the originals.
- CC marks on YouTube are self-declared. Many CC-marked football videos are re-uploads of TV broadcasts the uploader does not own. Prefer channels that clearly filmed their own matches (league or club channels, a parent with a tripod).
- Search strategy (my suggestions, not tested in this session): turn on the Creative Commons filter plus "Over 20 minutes" (or the API with `videoLicense=creativeCommon&videoDuration=long`), then run queries such as:
  - EN: "full match" amateur, "full game" U12 soccer, "sunday league full match", "tripod" soccer full game, "veo" full match, "grassroots football full match", "5-a-side full match"
  - UK: "повний матч" аматори, "аматорська ліга" футбол, "дитячий футбол" повний матч, "ДЮФЛ" матч, "чемпіонат області" футбол
  - RU: "полный матч" любители, "любительская лига" футбол, "ЛФЛ" полный матч, "детский футбол" полная игра
  - PL: "cały mecz" "klasa A", "klasa okręgowa" cały mecz, "B-klasa", "orlik" mecz, "trampkarze" mecz
  - ES: "partido completo" "fútbol base", "partido completo" alevín / infantil / cadete, "tercera regional" partido completo
  - JA: "サッカー フルマッチ 少年", "ジュニア サッカー 試合 フル", "社会人サッカー フル", "高校サッカー 県大会 フル"
- Verifying a static wide camera: check thumbnails and the first minutes for no pans; "Veo" or "Pixellot" in a title usually means AI follow-cam output, not a raw static view.

### Gaps
- No YouTube statement was found on whether CC-marked videos are an exception to the download ban. The YouTube Studio/Create "remix CC video" feature was not checked as a "feature of the Service".
- Count of CC BY full amateur matches on YouTube: not measured (would need API queries).
- The `sp=` URL parameter for the CC filter in web search was not verified.

## 2. Auto-camera products (Veo, Pixellot, Trace, XbotGo, Hudl, Spiideo, others): sample raw panoramas or open datasets?

### Takeaway
No vendor (Veo, Pixellot, Spiideo, Trace, XbotGo, Hudl) was found to publish raw panoramic match files or an open real-footage dataset under permissive terms. Veo explicitly does not allow downloading the panorama even for the owning club; only the follow-cam MP4. The only vendor-linked open data is Spiideo's synthetic SoccerNet-SynLoc.

### Cited Findings
- Veo support (via search snippet; the page returned HTTP 403 to direct fetch): you can only download a match assigned to your team (or as a clubhouse admin); panoramic/interactive views and Veo Analytics data cannot be downloaded; the only download is the follow-cam view as MP4. — [Veo support: How to download your Veo recordings](https://support.veo.com/hc/en-us/articles/4451733961361) (snippet, not fully verified)
- Veo League Exchange downloads are also MP4 files and "cannot be analyzed within Veo". — [Veo support: League Exchange download](https://support.veo.com/hc/en-us/articles/28048236995217-How-to-download-a-video-from-Veo-League-Exchange) (snippet)
- Product facts: Veo Cam 3 uses two 4K lenses for a 180° panorama; Pixellot Air NXT records panoramic 4K at 30 fps. These are product descriptions, not data releases. — [Veo: camera systems compared](https://www.veo.com/article/soccer-camera-systems-compared)
- Spiideo SoccerNet SynLoc: synthetic athletes rendered onto images from real Spiideo static-camera installations; the dataset and code are public on GitHub. — [SynLoc paper, SciTePress 2025](https://www.scitepress.org/Papers/2025/131082/131082.pdf)
- SoccerTrack v2 used BePro (Cerberus) fixed panoramic camera systems, so this is the closest thing to "vendor panorama, openly licensed" (see section 5). — [SoccerTrack v2 arXiv](https://arxiv.org/html/2508.01802)
- Pixellot: only a 2021 terms page on a staging domain was found, with no relevant content clauses. — [pixellotyou.wpengine.com terms](https://pixellotyou.wpengine.com/terms-of-use)

### Inferences
- Veo public match pages are viewing only. Grabbing the panorama by screen recording or stream capture would breach Veo's terms (likely) and the clubs' rights. Not a usable route.
- A realistic route is through clubs that own Veo/Pixellot/Trace cameras: the club owns or controls its recordings and can give Follo the follow-cam MP4. Note that a follow-cam MP4 is already cropped, so it is not a static wide view. It is still useful for detector testing, but not for testing the camera logic.
- XbotGo, Insta360 and DockKit stands are phone gimbals that pan, so their footage is not static. Their main value is as competitor examples, not data.

### Gaps
- Veo, Pixellot, Trace, XbotGo, Hudl and Spiideo terms of use (ownership of user recordings, vendor's AI-training licence, ban on scraping) were not retrieved: veo.com/terms-of-use returned 404 and the others were not found. Check these by hand.
- No sample raw panorama download pages were found for any vendor. It is uncertain whether sales teams give samples on request.

## 3. Stock and open-media sites (Wikimedia Commons, Internet Archive, Vimeo CC, Pexels, Pixabay, Mixkit, Videvo, Coverr)

### Takeaway
Stock sites have short, artistic, mostly moving-camera clips, not static full-pitch matches. Pexels and Pixabay terms (Nov 2024) explicitly ban scraping and bulk or systematic copying "for machine learning purposes" without permission, and ban using content to build a "competing service". Single hand-downloaded clips for private testing are allowed; building a training set from them is not safe. Wikimedia Commons has about 96 football videos, some of French regional and youth matches, under per-file free licences. This is the cleanest legal source, but the amount is tiny.

### Cited Findings
- Pexels licence: "All photos and videos on Pexels are free to use", "Attribution is not required", may modify; not allowed: selling unaltered copies, implying endorsement, redistributing on other stock platforms, use in trademarks. The licence page has no AI/ML text. — [Pexels License](https://www.pexels.com/license/)
- Pexels Terms of Service (last updated November 15, 2024), Section 8: "Data mining, extraction, scraping and the use of programs or robots for automatic data collection … is strictly prohibited for all unauthorised purposes, including without limitation for machine learning purposes"; "Bulk, large-scale or systematic copying of Content is strictly prohibited unless explicit permission has been granted by us"; no "use or compile any Content to replicate a similar or competing service"; no access "for building or marketing a competitive product". — [Pexels Terms of Service](https://www.pexels.com/terms-of-service/)
- Pixabay Content Licence summary: free use, no attribution, may modify; cannot sell or distribute "on a Standalone basis"; no commercial use of content containing recognisable trademarks in relation to goods and services. — [Pixabay License Summary](https://pixabay.com/service/license-summary/)
- Pixabay Terms (last updated November 18, 2024), Section 8: same wording as Pexels: scraping "strictly prohibited for all unauthorised purposes, including without limitation for machine learning purposes"; "Bulk, large-scale or systematic copying of Content is strictly prohibited"; Section 5 bans compiling content "to replicate a similar or competing service". Section 7A: Pixabay itself may use uploads for machine learning (uploaders can opt out). — [Pixabay Terms of Service](https://pixabay.com/service/terms/)
- Wikimedia Commons "Videos of association football": 7 subcategories, 96 files. Filenames include ACBB v. Olympique Adamois (Régional 2), ACBB v. OSC Elancourt (U18 Féminines Régional 3), ACBB v. US Torcy 2 (U16 Régional 1, 1917×494, which suggests a wide panoramic crop), ACBB v. Neuilly-sur-Marne 2 (U20 Coupe de Paris), "Finale schoolvoetbalwedstrijden.webm" and "Ascens Cardedeu 2012.ogv". The subcategory "Videos of association football matches" has 26 files. — [Commons: Videos of association football](https://commons.wikimedia.org/wiki/Category:Videos_of_association_football)
- Mixkit has a separate "Stock Video Free License", but its text could not be retrieved (dynamic page). — [Mixkit License](https://mixkit.co/license/)

### Inferences
- (a) Private testing: a few hand-picked Pexels/Pixabay clips are fine under their licences. (b) Training: a model is arguably not a "competing stock service", but the explicit "for machine learning purposes" scraping and systematic-copying ban means written permission is needed before any dataset-scale use. Treat Pexels and Pixabay as test-only.
- Wikimedia Commons files carry per-file licences (usually CC BY-SA, CC BY or CC0), and Commons does not restrict downloading. The ACBB regional and youth files are the strongest leads: check each file page for camera type (the 1917×494 aspect suggests a panorama), licence and duration. CC BY-SA on training data: whether model weights are "adapted material" is unsettled; CC BY or CC0 files are safer for training.
- Internet Archive, Vimeo CC, Videvo and Coverr: likely little static full-match amateur footage. Internet Archive licences are set by each uploader per item; Vimeo shows a per-video CC licence and lets the owner enable downloads. Not verified this session.

### Gaps
- Internet Archive terms could not be retrieved (page rendered empty). Vimeo CC search, Videvo and Coverr licences were not checked.
- Mixkit licence text and any AI clause were not retrieved.
- Camera setup and licence of each ACBB Commons file were not opened.

## 4. Asking local clubs, leagues and academies for recordings (consent, minors)

### Takeaway
This is the most realistic route to "real user" footage that is clean for both testing and commercial training: you get the original file directly, so no platform ToS applies. You need written permission from whoever filmed it (copyright) and a lawful basis for processing identifiable players. For children, get written consent from a parent or guardian, collected by the club.

### Cited Findings
- Ukrainian Civil Code Art. 307 (as summarised by the Kharkiv Human Rights Protection Group): a person may be filmed "лише за її згодою", and consent is presumed when filming openly at public events. A person may demand that public showing stop, and consent can be withdrawn. — [KHPG methodology PDF](https://old.helsinki.org.ua/wp-content/uploads/2021/12/Personal_Photo_A5.pdf)
- Under the Ukrainian Law "On Personal Data Protection", an image is personal data when the person can be identified. The Law "On Protection of Childhood", Art. 10, bans publishing information about a child that may harm them. Schools commonly use written parental consent forms for photo and video. — [Radio Svoboda on children's data](https://www.radiosvoboda.org/a/zahyst-personalnyh-danyh-dytyny/31603271.html); [HSA blog](https://www.hsa.org.ua/blog/ziomka-ditini-na-foto-kino-tele-ci-videoplivku-tretimi-osobami-shho-maiut-znati-pro-ce-batki-ta-diti)
- GDPR Art. 8(1): for information society services offered directly to a child under point (a) of Art. 6(1) (consent), processing is lawful when the child "is at least 16 years old"; below that, only if "consent is given or authorised by the holder of parental responsibility"; Member States may lower this to no less than 13. — [GDPR Art. 8](https://gdpr-info.eu/art-8-gdpr/)

### Inferences
- Art. 8 GDPR covers online services aimed at children, not dataset collection. For training on EU footage the basis would be consent or legitimate interest, with special care for minors. Practical safe default: written parental or guardian consent for all under-18s, stating the purpose (testing and training an auto-camera algorithm), no publication, storage period and the right to withdraw.
- Ask for: (1) a written licence from the camera owner or club, covering internal testing and model training for a commercial product; (2) confirmation that players or parents were informed and consented; (3) raw static files, not edited highlights. Adult amateur leagues are easier than youth clubs.
- Ukraine-specific: Ukrainian amateur leagues (city and regional championships, ЛФЛ-type leagues) often stream with one fixed camera. Offering them a free Follo stream in exchange for raw files is a natural trade.

### Gaps
- The exact text of Ukrainian Civil Code Arts. 307/308 on minors, and the age at which a child's own consent counts, was not verified on zakon.rada.gov.ua.
- Whether the presumed consent for public events under Art. 307 extends to ML processing: not found.

## 5. Research datasets and community collections of grassroots or amateur full-pitch video

### Takeaway
The best openly licensed source is SoccerTrack v2: 10 full university matches (about 930 min) from fixed panoramic cameras covering the whole pitch, CC BY 4.0 (commercial use allowed with attribution), Hugging Face gated click-through. It is very likely the owner's current "university dataset"; only 3×4 min are in use, so about 900 more minutes are available. Academic papers that used YouTube or TikTok footage usually do not redistribute it ("available on request"), which confirms that the copyright barrier is real.

### Cited Findings
- SoccerTrack v2 Hugging Face card: "Ten university-level soccer matches (934 minutes)", "20 panoramic half-match videos (two 45-minute periods per match)", "recorded by fixed panoramic camera systems whose field of view spans the entire pitch", licence "CC BY 4.0", "The release is pseudonymised", no personal names; access needs you to "agree to share your Hugging Face information" (gated but public). — [HF atomscott/soccertrack-v2](https://huggingface.co/datasets/atomscott/soccertrack-v2)
- SoccerTrack v2 paper: 932 min of fixed-camera 4K panoramic video, BePro camera systems, game-state labels (player pitch positions, IDs, jersey numbers, roles, teams) and 12 ball-action classes; code MIT. — [arXiv 2508.01802](https://arxiv.org/html/2508.01802); [project page](https://atomscott.github.io/SoccerTrack-v2/)
- Original SoccerTrack (CVPRW 2022): 8K fish-eye and 4K drone video with GNSS and bounding-box tracking (University of Tsukuba, Nagoya University, AIST); data and code said to be available; licence not confirmed in search results. — [CVPRW 2022 paper](https://openaccess.thecvf.com/content/CVPR2022W/CVSports/papers/Scott_SoccerTrack_A_Dataset_and_Tracking_Algorithm_for_Soccer_With_Fish-Eye_CVPRW_2022_paper.pdf)
- A 2022 player-detection paper "collected a large amount of occlusion football players from Tiktok and Youtube videos", labelled them by hand, and made the data available only "upon request". — [PMC9296282](https://pmc.ncbi.nlm.nih.gov/articles/PMC9296282/)
- SoccerSynth-Detection (2025) notes that copyright restrictions "severely restrict" public soccer detection datasets, which motivated synthetic data. — [arXiv 2501.09281](https://arxiv.org/html/2501.09281v1)
- Roboflow Universe and Kaggle have football detection image sets under CC BY 4.0, CC0 or Apache 2.0 (e.g. "Football Player Detection YOLOv8", Apache 2.0), mostly broadcast-style frames, not static amateur video. — [Kaggle](https://www.kaggle.com/datasets/iasadpanwhar/football-player-detection-yolov8); [Roboflow](https://universe.roboflow.com/footballdetecting/football-videos-dataset)

### Inferences
- Priority for Follo: (1) use the whole of SoccerTrack v2 now (test on unseen matches, held-out 20%), keeping a CC BY attribution line in the app credits; (2) Wikimedia Commons ACBB files; (3) CC BY YouTube matches found through the API, with written permission requested from the uploaders; (4) partner clubs or leagues with raw files and consent; (5) the owner's own filming. Pexels and Pixabay clips are for testing only.
- SoccerTrack v2 is high-end panorama hardware on a university pitch, without phone artefacts (heads in front, phone compression, floodlights). It does not replace footage of real phone users. Club partnerships and own filming remain essential.
- Roboflow/Kaggle image sets: per-dataset licences vary, and the images are often taken from broadcasts without rights. Check each one before training a shipped model.

### Gaps
- No community platform was found that publishes all amateur matches from a fixed camera under an open licence (no source found in this session). School and amateur streaming platforms (e.g. NFHS Network, Hudl, Veo Live) were not checked in detail; they are expected to be view-only under proprietary terms.
- The original SoccerTrack (v1) licence was not confirmed.
- Other amateur fixed-camera academic datasets (e.g. TeamTrack, SportsMOT soccer subset) were not checked in this session.
