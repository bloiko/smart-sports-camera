# Licences and consent for football video used to test and train Follo (status October 2026)

Scope: a solo developer in Ukraine sells an iPhone app worldwide through the App Store. The app ships only the developer's own code and own small weights. Third-party models such as Ultralytics YOLO run only on the Mac as teachers. This is not legal advice. Every "OK" below is a risk judgement built from primary sources and commentary. It is not a legal opinion.

Note on sources: items marked "(OJ text, not re-fetched)" quote EU legislation from the Official Journal text at the EUR-Lex URL given. I know that wording well, but I did not re-download it in this session. Check it before quoting it externally.

## 1. Datasets: CC BY 4.0, CC BY-NC, CC BY-SA, research-only and NDA (SoccerTrack v2, SoccerNet, DeepSportradar). Is training and shipping weights "distributing adapted material"?

### Takeaway
Creative Commons' own position is that its licences only matter where copyright permission is needed. Whether a trained model is "Adapted Material" is left unanswered. CC BY data is the safe class for commercial weights: attribution is simple, and a link to the dataset is enough. NC data is out for anything commercial: CC says every stage, "from copying the data during training to sharing the trained model", must be non-commercial. SA would push a share-alike licence onto shared models or outputs. NDA and research-only sets like SoccerNet and likely DeepSportradar must stay out of commercial training. SoccerTrack v2, our current source, is CC BY 4.0 for the data and MIT for the code, and its page says both permit commercial use.

### Cited Findings
- CC's AI-training guidance: "CC licenses apply only when copyright permission is required"; "If exceptions or limitations apply, then the CC license terms don't apply." It notes that the answer varies by jurisdiction. — [Creative Commons, Using CC-licensed works for AI training](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/)
- On NC, the same page says that if training data has an NC term, "all stages, from copying the data during training to sharing the trained model, must not be for commercial gain", and "The NonCommercial (NC) restriction applies to all uses requiring permission under copyright." — [Creative Commons](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/)
- On SA, the page says "CC BY-SA and CC BY-NC-SA require that adaptations be shared under the same license", and "If AI models or outputs are based on ShareAlike content and they will be shared publicly", the same CC licence would be needed. — [Creative Commons](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/)
- On attribution, the page says "For AI model training, attribution could be a simple link to the source of the dataset used to train the model." — [Creative Commons](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/)
- The CC page never says whether a trained model is "Adapted Material". It also shows no publication date; an embedded primer PDF sits under a 2025/05 upload path. — [Creative Commons](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/)
- The CC BY 4.0 legal code defines Adapted Material as material "derived from or based upon the Licensed Material and in which the Licensed Material is translated, altered, arranged, transformed, or otherwise modified in a manner requiring permission under the Copyright and Similar Rights". The attribution duty in Section 3(a) is triggered when you "Share" the Licensed Material (OJ-style text, not re-fetched). — [CC BY 4.0 legal code](https://creativecommons.org/licenses/by/4.0/legalcode.en)
- The UK High Court found that Stable Diffusion's model weights were not an "infringing copy" because they never stored or contained copies of the training images. This is the strongest judicial support so far for "weights are not a copy or adaptation of the training works". — [Bird & Bird on Getty v Stability [2025] EWHC 2863 (Ch)](https://cm.twobirds.com/en/insights/2025/uk/stability-ai-defeats-getty-images-copyright-claims-in-first-of-its-kind-dispute-before-the-high-cour); [Mayer Brown, 13 Nov 2025](https://www.mayerbrown.com/insights/publications/2025/11/getty-images-v-stability-ai-what-the-high-courts-decision-means-for-rights-holders-and-ai-developers)
- The SoccerTrack v2 repository lists code under MIT and the dataset (videos plus GSR, BAS and MOT annotations) under CC BY 4.0. It states "Both permit commercial use" and asks users to cite arXiv:2508.01802 (Scott, Uchida, Kuroda, Kim, Fujii 2025). It says nothing about the personal data of filmed players. — [SoccerTrack-v2 GitHub](https://github.com/AtomScott/SoccerTrack-v2); [arXiv 2508.01802](https://arxiv.org/abs/2508.01802v1)
- SoccerTrack v2 consists of 10 full-length panoramic 4K recordings of university-level matches, captured with BePro cameras. — [arXiv 2508.01802](https://arxiv.org/abs/2508.01802v1)
- SoccerNet's old NDA form is deprecated. Access to gated "protected video content" now goes through Hugging Face: you "accept the NDA conditions" there and get a "personalized copy of the NDA" by email. The public data page states no licence and no permitted uses. — [SoccerNet data page](https://www.soccer-net.org/data)
- A derived dataset card (SoccerChat, secondary source) says SoccerNet video access requires the NDA and that clips may not be redistributed, publicly hosted, reconstructed or used commercially. — [SoccerChat dataset card (mirror)](https://s9gkls5--c7029cb47f3111f1aaa91607ee4eb77e.web.val.run/datasets/SimulaMet/SoccerChat)
- DeepSportradar: third-party mirrors list the instance-segmentation set as CC BY-NC-SA 4.0 and the DeepSport set as "Non-Commercial", crediting LNB with the image copyright. The official licence for the basketball-instants set (Kaggle and the GitHub licence section) was not verified. — [Dataset Ninja](https://datasetninja.com/deep-sport-radar); [HyperAI](https://beta.hyper.ai/en/datasets/20440); [DeepSportradar GitHub](https://github.com/DeepSportradar/ball-3d-localization-challenge/blob/main/README.md)

### Inferences
- CC BY 4.0, such as SoccerTrack v2, is OK for private evaluation and OK for training shipped weights. There are two cases:
  - If weights are not Adapted Material (the Getty reasoning), the licence may not even be triggered.
  - If they are, attribution satisfies it. Either way, a NOTICE or credits entry linking the dataset, its licence and the paper is cheap and matches CC's own guidance.
- CC BY-NC is acceptable at most for private evaluation, and even that carries some risk. CC reads NC to cover "all stages", and evaluating a model for a paid app plausibly counts as "directed towards commercial advantage". The cleanest policy is to keep NC data entirely out of the Follo pipeline, or limit it to a clearly separated sanity check that never feeds model selection. It must never train shipped weights.
- CC BY-SA and BY-NC-SA should be avoided for shipped weights: CC says models "based on ShareAlike content" that are shared publicly need the same licence, and shipping weights inside the app is sharing them.
- NDA and research-only sets (SoccerNet, DeepSportradar, most broadcast-derived sets) carry contractual restrictions plus third-party broadcast rights (leagues, broadcasters). Do not use them for commercial training. Private evaluation is likely also outside the NDA if it serves a commercial product. Assume "no" unless the NDA text says otherwise.
- SoccerTrack v2 players are identifiable students. CC BY covers copyright, not the players' personal-data or image rights. That risk is low for internal training, but publishing frames from the data, for example in marketing, needs extra care.

### Gaps
- I could not retrieve the actual SoccerNet Hugging Face NDA text. Whether it says "research only" or "non-commercial" is not confirmed here.
- No official CC FAQ statement says outright whether model weights are "Adapted Material". CC deliberately leaves this to national law.
- The DeepSportradar official licence is unverified.

## 2. Pseudo-labels from an AGPL teacher (Ultralytics YOLO) used to train our own model

### Takeaway
Ultralytics claims that every model trained with its code ("trained models") falls under AGPL-3.0. That claim reaches models trained by Ultralytics software, not models trained by our own code. On generated annotations, an Ultralytics community answer says auto-annotated labels "are not themselves subject to the AGPL-3.0 license". That matches the FSF's general position that a program's output is not covered by the program's copyright. Training our own network, with our own code, on YOLO pseudo-labels is therefore low risk under AGPL. It is not zero risk: Ultralytics' licensing language is aggressive and no court has ruled.

### Cited Findings
- Ultralytics licence page: "All Ultralytics YOLO trained models fall under the AGPL-3.0 License by default"; "The AGPL-3.0 License covers the training code and the models produced by that training code". It says this applies even when you train from scratch or use YOLO only internally. It lists "model weights" among items to be released publicly, and says "Any commercial product or service" requires an Enterprise licence, including "hardware, edge devices, robotics, cameras, or appliances". — [Ultralytics License](https://www.ultralytics.com/license)
- An Ultralytics community forum answer (user pderrenger, 12 January 2025) says "Generated annotations using the `auto_annotate` feature are not themselves subject to the AGPL-3.0 license". It describes them as outputs of the software rather than derived works, and adds that using or modifying the auto_annotate code itself requires AGPL compliance. The page does not show the answerer's role. pderrenger is widely seen as an Ultralytics team account, but that is not verified here. — [Ultralytics Community: Auto_annotate and AGPL](https://community.ultralytics.com/t/auto-annotate-and-agpl/676)
- Community discussion disputes Ultralytics' reach over custom-trained models. Some GitHub commenters argue that AGPL does not cover custom-trained models the way Ultralytics describes. — [Ultralytics GitHub issue #2129](https://github.com/ultralytics/ultralytics/issues/2129)
- FSF GPL FAQ ("Is there some way that I can GPL the output people get from use of my program?"): the output of a program is not, in general, covered by the copyright on the program's code, unless the output contains copied parts of the program (not re-fetched in this session). — [GNU GPL FAQ, GPLOutput](https://www.gnu.org/licenses/gpl-faq.html#GPLOutput)

### Inferences
- Our situation: YOLO runs locally on the Mac, nothing is offered over a network, and the shipped student model is trained by our own code with no Ultralytics code or weights inside it. Under the FSF and forum reasoning, neither the label files nor the student weights are AGPL works.
- The residual risk is contractual or reputational. Ultralytics' page says use "in business" needs an Enterprise licence, even for internal use. AGPL itself imposes no restriction on private use or on outputs, so that statement reads as Ultralytics' position rather than a licence term.
- Mitigations:
  - Keep the teacher strictly off-device.
  - Never copy Ultralytics code (loss functions, augmentation, export) into our training code.
  - Never initialise the student from YOLO weights.
  - Log which teacher produced which labels.
  - Plan to replace the teacher with an Apache-2.0 detector (already in CLAUDE.md) or with our own labels before a big commercial push.
- The same reasoning applies to any teacher. Check each teacher model's weight licence: some weights carry their own non-commercial terms, which a forum answer about outputs would not override.

### Gaps
- No court decision or formal Ultralytics legal statement addresses pseudo-labelling or distillation specifically.
- I found no published legal commentary from a law firm on AGPL and distillation.

## 3. YouTube videos, EU TDM exceptions, EU AI Act, US fair use, UK, Ukraine

### Takeaway
Downloading from YouTube breaches the YouTube Terms of Service unless YouTube "expressly authorized" it, gave written permission, or applicable law allows it. A CC BY licence from the uploader solves copyright, but not the ToS contract, and not whether the uploader had the rights to license in the first place.

On the legal regimes:
- **EU**: Article 4 of the DSM Directive (commercial text and data mining, TDM) allows mining of lawfully accessible content unless the rightholder opts out in machine-readable form. Article 3 covers only research organisations.
- **AI Act**: training-data summaries apply to general-purpose AI (GPAI) model providers, not to a small ball detector.
- **US**: two 2025 district courts found training fair use for generative LLMs. The Third Circuit (29 September 2026) affirmed that a non-generative competing tool was not fair use.
- **UK**: Getty v Stability held that weights are not infringing copies.
- **Ukraine**, where the copying physically happens: Article 22 of Law 2811-IX allows TDM only for research. A Ukrainian solo commercial developer therefore has no statutory TDM safe harbour and needs a licence (CC BY) or own footage.

### Cited Findings
- YouTube ToS (Ukrainian version; effective 5 January 2022), Permissions and Restrictions, item 1: you may not "access, reproduce, download, distribute…" any part of the Service or Content except as expressly authorised by the Service, with prior written permission from YouTube and the rights holders, or as permitted by applicable law. Item 3 prohibits automated access except by public search engines under robots.txt, with prior written permission, or as allowed by law. The ToS does not mention Creative Commons. — [YouTube Terms of Service](https://www.youtube.com/static?template=terms)
- YouTube Help on the CC licence: YouTube offers only "Creative Commons Attribution license" (CC BY). "If you add a Creative Commons Attribution license to your video, it means other creators can reuse your work subject to the terms of the CC BY license." Attribution should name the title, author, source URL and licence. A video with a Content ID claim cannot be CC-licensed, and YouTube "can't grant you rights to use someone else's content". — [YouTube Help, Creative Commons](https://support.google.com/youtube/answer/2797468)
- DSM Directive 2019/790 (OJ text, not re-fetched):
  - Article 3 lets "research organisations and cultural heritage institutions" mine works for scientific research.
  - Article 4(1) gives a general TDM exception for lawfully accessible works.
  - Article 4(3) applies it "on condition that the use … has not been expressly reserved by their rightholders in an appropriate manner, such as machine-readable means in the case of content made publicly available online."
  - Article 4(2) allows keeping copies "for as long as is necessary for the purposes of text and data mining".
  - Source: [Directive (EU) 2019/790, EUR-Lex](https://eur-lex.europa.eu/eli/dir/2019/790/oj)
- Germany, Kneschke v LAION: on 10 December 2025 the Hamburg Higher Regional Court (5 U 104/24) held that the TDM exceptions cover reproducing images to build a training dataset. It found Article 3 (German §60d) applies to the non-profit LAION and that Article 4 was also satisfied. It held that an opt-out "formulated in natural language" did not meet the machine-readability requirement. A further appeal to the BGH was admitted. — [Technology's Legal Edge, 10 Dec 2025](https://www.technologyslegaledge.com/2025/12/robert-kneschke-v-laion-judgment-of-10-december-2025-ref-5-u-104-24/); [Freshfields](https://technologyquotient.freshfields.com/post/102mebl/ai-training-copyright-part-2-text-and-data-mining-under-court-scrutiny); [Hogan Lovells tracker](https://digital-client-solutions.hoganlovells.com/resources/ai-litigation-case-law-tracker/case/robert-kneschke-vs-laion-e-v/decision/1)
- EU AI Act (Regulation 2024/1689; OJ text, not re-fetched):
  - Article 53(1)(c) and (d) require providers of general-purpose AI models to keep a policy to comply with Union copyright law, including Article 4(3) opt-outs, and to publish "a sufficiently detailed summary about the content used for training".
  - Article 3(63) defines a GPAI model as one that "displays significant generality and is capable of competently performing a wide range of distinct tasks".
  - Source: [Regulation (EU) 2024/1689, EUR-Lex](https://eur-lex.europa.eu/eli/reg/2024/1689/oj)
- Commentary on AI Act timing and thresholds:
  - The Commission's July 2025 guidelines use an indicative GPAI threshold of training compute above 10^23 FLOP plus language, image or video output.
  - Systemic-risk status is presumed above 10^25 FLOP.
  - GPAI obligations started on 2 August 2025, Commission enforcement powers on 2 August 2026, and models already on the market must comply by 2 August 2027.
  - Sources: [Bird & Bird on GPAI Code and training summary template](https://cm.twobirds.com/en/insights/2025/taking-the-eu-ai-act-to-practice-decoding-the-gpai-code-of-practice-and-the-training-data-summary-te); [Steptoe](https://www.steptoe.com/en/news-publications/eu-ai-act-obligations-for-gpai-models-now-applicable.html); [Opsio summary](https://opsiocloud.com/knowledge-base/eu-ai-act-general-purpose-ai-gpai/). These are secondary sources and conflict slightly on the figures.
- US, Bartz v Anthropic (N.D. Cal., 23 June 2025, Alsup J.): training on lawfully acquired books was fair use ("exceedingly transformative"), but using pirated copies to build a library was not, and that issue went to trial. — [Debevoise](https://www.debevoise.com/insights/publications/2025/06/anthropic-and-meta-decisions-on-fair-use); [Wiggin](https://www.wiggin.com/publication/bartz-v-anthropic-first-court-decision-on-fair-use-defense-in-llm-training/)
- US, Kadrey v Meta (N.D. Cal., 25 June 2025, Chhabria J.): Meta won fair use on the record presented. The judge stressed that evidence of market harm or dilution could change the outcome. — [Manatt](https://www.manatt.com/insights/newsletters/client-alert/making-sense-of-the-first-two-often-contradictory-sometimes-confounding-gen-ai-fair-use-rulings); [Debevoise](https://www.debevoise.com/insights/publications/2025/06/anthropic-and-meta-decisions-on-fair-use)
- US, Thomson Reuters v ROSS (3rd Cir., No. 25-2153, 29 September 2026): affirmed that copying Westlaw headnotes to train a competing non-generative AI legal-research tool was not fair use. The use was commercial and minimally transformative, and harmed a licensing market. This is the first appellate AI-training fair-use ruling. ROSS reportedly plans to seek Supreme Court review. — [LawNext, Sept 2026](https://www.lawnext.com/2026/09/3rd-Circuit-rules-for-thomson-reuters-in-its-copyright-fight-against-legal-research-startup-ross.html); [Jackson Walker](https://www.jw.com/?p=105798); [Plagiarism Today, 1 Oct 2026](https://www.plagiarismtoday.com/2026/10/01/understanding-the-reuters-ross-ai-ruling/)
- UK, Getty v Stability ([2025] EWHC 2863 (Ch), November 2025): the court rejected secondary copyright infringement because the weights do not store copies. Getty had dropped its training and output claims, so those questions remain open in the UK. Leave to appeal was reportedly granted on 17 December 2025; the outcome was not found. — [Bird & Bird](https://cm.twobirds.com/en/insights/2025/uk/stability-ai-defeats-getty-images-copyright-claims-in-first-of-its-kind-dispute-before-the-high-cour); [AIPPI](https://www.aippi.org/news/getty-images-v-stability-ai-uk-high-court-finds-no-secondary-copyright-infringement-in-landmark-genai-ruling/); [CMS tracker](https://cms.law/en/hkg/publication/artificial-intelligence-and-copyright-case-tracker/united-kingdom-getty-images-us-inc-ors-v-stability-ai-ltd2)
- Ukraine: Law No. 2811-IX "On Copyright and Related Rights" was adopted on 1 December 2022. A consolidated version (15 April 2023) is on WIPO Lex. — [WIPO Lex](https://www.wipo.int/wipolex/en/legislation/details/22385)
- Ukraine, Article 22 (TDM): EIFL's October 2023 comments say the exception is modelled on the DSM Directive but is "far more restrictive": it covers research purposes only, scientific publications only, apparently searching only, and is not protected from contract override. — [EIFL comments, 19 Oct 2023 (PDF)](https://www.eifl.net/system/files/resources/202310/eifl_comments_ukraine_ip_dialogue_19_oct_2023.pdf)
- A secondary legal index likewise describes the Ukrainian TDM exception as research-only, requiring a lawful source and respecting machine-readable opt-outs, with commercial TDM and AI training for commercial products not covered. — [UNGOVR AI law index, Ukraine](https://law.ungovr.org/ai/ua)

### Inferences
- **YouTube (any licence)** is OK for private evaluation in practice; the copyright risk is low. Under the ToS, downloading with tools such as yt-dlp is still a breach of contract unless "applicable law" permits it. In the EU, Article 4 TDM could arguably be that law; in Ukraine it is not, because Article 22 is research-only.
  - **Training shipped weights on ordinary YouTube videos (all rights reserved)**: not OK for a Ukraine-based commercial developer. There is no Ukrainian TDM exception for commercial use, and US fair use is unsettled: ROSS is a non-generative commercial training case that went against the trainer.
  - **YouTube CC BY videos**: OK for training on the copyright side if the uploader really owns the footage. That excludes re-uploaded TV broadcasts, where the CC tag is often wrong. Attribute with title, author, URL and "CC BY". The ToS download issue remains a residual contract risk. YouTube's own CC feature is designed for reuse "in the YouTube editor" ecosystem, and YouTube "can't grant you rights to use someone else's content."
- **EU AI Act**: a single-purpose ball or player detector is not a "general-purpose AI model" and is far below the 10^23 FLOP indicator. The Article 53 training-data summary therefore does not apply to Follo. Follo is also not a high-risk system under Annex III, since no biometric identification is involved. This is my assessment; I found no guidance naming small vision models.
- **Where the act happens**: copyright is territorial. The reproductions made while training on the Mac happen in Ukraine, so Ukrainian law is the most directly relevant for training copies. EU and US law matter for selling into those markets and for any claim that the shipped weights are themselves infringing. Getty in the UK says they are not, if they store no copies.
- **US fair use for our case**: a ball detector does not substitute for the football videos, which helps under factor 4. ROSS shows, however, that a licensing market for training data can count against the trainer, and our use is commercial. Treat fair use as an uncertain defence, not a plan.

### Gaps
- I did not obtain the operative Ukrainian text of Article 22 of Law 2811-IX from zakon.rada.gov.ua. The research-only scope relies on EIFL and one secondary index.
- I did not check whether Ukraine has amended Law 2811-IX in 2024–2026, for example through EU-accession harmonisation or the planned AI white-paper and draft laws, to add a DSM-style Article 4 exception.
- I did not verify the full published text of the 3rd Circuit ROSS opinion; sources disagree on whether it was initially sealed.
- I did not check the Bartz settlement or trial outcome or later Kadrey developments after June 2025.
- I found no case law on YouTube ToS enforcement against individual researchers who download videos.

## 4. Stock footage sites: Pexels, Pixabay, Mixkit, Videvo, and AI or ML training

### Takeaway
Pexels' and Pixabay's terms both prohibit scraping or automated extraction "for machine learning purposes" and bulk copying without permission. Pixabay's own blog (October 2025) says its content cannot be used to train ML models. Their basic licences allow free commercial use and modification without attribution, but the ML clauses make them unsuitable for training sets. Mixkit's and Videvo's AI terms could not be verified. Stock football clips are also rarely static wide-angle full-pitch shots, so their value is low.

### Cited Findings
- Pexels licence: "All photos and videos on Pexels can be downloaded and used for free"; "Attribution is not required"; you may modify. Restrictions: "Identifiable people may not appear in a bad light…", "Don't redistribute or sell the photos and videos on other stock photo or wallpaper platforms." The licence page itself does not mention AI. — [Pexels License](https://www.pexels.com/license/)
- Pexels Terms of Service, Section 8: automated extraction "is strictly prohibited for all unauthorised purposes, including without limitation for machine learning purposes"; "Bulk, large-scale or systematic copying of Content is strictly prohibited" without Pexels' explicit permission. Section 7A: Pexels itself may use uploads for machine learning, and contributors can opt out. — [Pexels Terms](https://www.pexels.com/terms-of-service/)
- Pixabay Terms (last updated 18 November 2024), Section 8: "Data mining, extraction, scraping and the use of programs or robots for automatic data collection … is strictly prohibited for all unauthorised purposes, including without limitation for machine learning purposes"; "Bulk, large-scale or systematic copying of Content is strictly prohibited unless explicit permission has been granted by us." — [Pixabay Terms](https://pixabay.com/service/terms/)
- The Pixabay content licence summary lists no AI clause. Its prohibitions include "You cannot sell or distribute Content … on a Standalone basis" and "You cannot use Content in any immoral or illegal way, especially Content which features recognisable people." — [Pixabay License summary](https://pixabay.com/service/license-summary/)
- Pixabay's October 2025 guide (as summarised by search; not fetched in full) says Pixabay content "can't be used to train machine learning models or incorporated into AI generation tools", and that redistribution for machine learning or database-building isn't permitted. Content uploaded before 9 January 2019 was CC0. — [Pixabay blog, Intellectual Property Explained](https://pixabay.com/ko/blog/posts/intellectual-property-explained-441/); [Wikipedia, Pixabay](https://en.wikipedia.org/wiki/Pixabay)
- Videvo offers a standard licence without attribution, a CC 3.0 option requiring credit, and premium plans. No AI or ML term was found. — [Videvo blog](https://www.videvo.net/blog/about)
- The Mixkit licence page (mixkit.co/license) did not render its "Stock Video Free License" text in the fetch. — [Mixkit License](https://mixkit.co/license/)

### Inferences
- **Pexels**: manually downloading a handful of clips for private evaluation is arguably allowed by the licence, but not for ML training. Section 8 targets automated or bulk extraction "for machine learning purposes", and Pixabay's sister guidance (same owner, Canva) states the training ban outright. Treat Pexels and Pixabay as "evaluation only, a few clips, manual download, never in training".
- **Mixkit and Videvo**: unknown. Read the current licence page and keep a dated copy before any use. Default to evaluation only.

### Gaps
- I could not find the Mixkit Stock Video Free License text or Videvo's licence wording on AI.
- I could not fetch the full Pixabay October 2025 blog text.

## 5. Recording amateur and youth matches ourselves: consent, GDPR, Ukrainian law, YouTube "made for kids", COPPA, club practice

### Takeaway
In Ukraine, Article 307 of the Civil Code presumes consent to open filming at public events, but Article 308 requires consent to publicly show or distribute images of a person. For minors, parents or guardians give that consent. GDPR applies when filming EU players or targeting the EU. Video of players is personal data, but not "biometric" special-category data unless processed for unique identification, and Follo does no face recognition. UK and FA club practice requires written parental consent before filming under-16s, including Veo footage that goes public. YouTube requires every creator, anywhere, to set "made for kids". A youth match stream for a general or parent audience is most likely "not made for kids", but the FTC factors include "the age of models", so judge each video. For training data, our own recordings with signed parental or club consent are the cleanest possible source.

### Cited Findings
- Ukraine, Civil Code Article 307:
  - A natural person may be filmed only with their consent.
  - Consent is presumed if filming is done openly in the street or at meetings, conferences, rallies "та інших заходах публічного характеру" (and other public events).
  - Part 2 lets a person who agreed demand that the public showing of the parts concerning their private life stop.
  - Article 308 separately requires consent to publicly show, reproduce or distribute images of a person.
  - Sources: [protocol.ua, Article 307 ЦКУ](https://protocol.ua/ua/tsivilniy_kodeks_ukraini_stattya_307/); [NetFreedom, Can you film a person without consent](https://netfreedom.org.ua/chi-mozhna-znimati-lyudinu-bez-yiyi-zgodi-zakon-i-praktika/); official text: [Civil Code of Ukraine, zakon.rada.gov.ua](https://zakon.rada.gov.ua/laws/show/435-15)
- Ukrainian school and competition consent templates have parents or guardians consent to the collection, use and distribution of a child's personal data. These are templates, not law. — [competition consent template](https://docs.google.com/document/d/1bSHgz3pnCIKjCG4S-D4Hk2x7ATVSNcFy/export?format=pdf); [parental consent template](https://docs.google.com/document/d/1LWzuwsGnXBibcmOCFyWs067dsvYBoxxe/export?format=pdf)
- Ukraine's personal data law is Law No. 2297-VI "On Personal Data Protection" (2010). Consent is a legal basis. — [Law 2297-VI, zakon.rada.gov.ua](https://zakon.rada.gov.ua/laws/show/2297-17) (not fetched in this session)
- GDPR (Regulation 2016/679; OJ text, not re-fetched):
  - Article 3(2): GDPR reaches non-EU controllers who offer goods or services to people in the EU or monitor their behaviour there.
  - Article 6(1)(a) and (f): consent and legitimate interests as legal bases.
  - Article 8: the age 16 threshold (members may lower it to 13) applies only to consent for "information society services" offered directly to a child.
  - Article 4(14): biometric data are data "resulting from specific technical processing … which allow or confirm the unique identification" of a person. Recital 51 adds that photographs count as biometric only when processed through such specific technical means.
  - Article 9: special-category rules.
  - Source: [GDPR, EUR-Lex](https://eur-lex.europa.eu/eli/reg/2016/679/oj); Article 8 in Ukrainian: [gdpr-text](https://devgdprtextwp.gdpr-text.com/uk/?p=22875)
- NSPCC and CPSU (UK child-protection-in-sport) guidance:
  - Consent must be obtained from a parent or carer before taking any photos or videos of a child under 16.
  - The child should also be asked and can withdraw at any time.
  - The consent form template collects both parent and child consent, and the policy template is written for UK GDPR and DPA 2018.
  - Sources: [NSPCC key info, photography](https://sport.nspcc.org.uk/resource-library/feature-boxes/key-info-photography/); [NSPCC consent form template](https://sport.nspcc.org.uk/resource-library/forms/photography-and-video-consent-form-template/); [NSPCC policy template](https://sport.nspcc.org.uk/resource-library/policies/photography-and-filming-policy-template/)
- Club practice with Veo:
  - The FA's guidance, quoted in a club policy, requires written or electronic parental consent before filming a player, including Veo footage that goes into the public domain.
  - Berkhamsted Raiders names Veo as an approved provider and says parents must be told where filming happens.
  - NSFA (Australia, 2026) covers Veo and elevated cameras, notes they record audio, and treats a parent's refusal of public sharing as final.
  - Sources: [Laund Hill CC policy (PDF)](https://laundhillcc.co.uk/wp-content/uploads/2025/03/PhotographingFilmingChildren.pdf); [Berkhamsted Raiders filming policy, Dec 2025 (PDF)](https://knowhow.berkhamstedraiders.com/wp-content/uploads/2017/11/Raiders-Filming-Policy-Dec-25.pdf); [NSFA Video and Photography Policy 3.0 (PDF)](https://nsfa.asn.au/wp-content/uploads/2026/07/Video-and-Photography-Policy-3.0.pdf)
- YouTube "made for kids":
  - "Regardless of your location, we require you to tell us whether or not your videos are made for kids."
  - Factors include "Whether the video includes child actors or models" and "Whether the video includes activities that appeal to children".
  - "Just because your content may include some of these factors does not automatically mean it's made for kids". Content is not made for kids merely because it covers "an activity traditionally associated with children" or "Children may incidentally see it".
  - In the US a kid is under 13; other countries may differ.
  - Source: [YouTube Help, Determining if your content is made for kids](https://support.google.com/youtube/answer/9528076)
- FTC on YouTube channel owners (2019):
  - COPPA applies "in the same way it would if the channel owner had its own website or app" when content is directed to children and personal information is collected, for example by an ad network.
  - Factors include "the age of models" and "child-oriented activities".
  - Penalties then were "up to $42,530 per violation".
  - Source: [FTC business blog, Nov 2019](https://www.ftc.gov/business-guidance/blog/2019/11/youtube-channel-owners-your-content-directed-children)
- Later figures from secondary sources: one creator legal blog cites up to $53,088 per violation. In September 2025 Disney agreed to pay $10 million to settle FTC COPPA allegations over labelling whole YouTube channels "Not Made for Kids". — [promise.legal blog](https://blog.promise.legal/coppa-rules-youtube-twitch-streamers/); [vidIQ](https://vidiq.com/blog/post/coppa-kids-content-youtube/)

### Inferences
- **The owner's own recordings (Ukraine)**:
  - Open filming at a public match falls under the Article 307 presumption.
  - Publishing a YouTube stream of identifiable minors, and keeping footage for training, should rest on explicit written consent from parents or guardians, collected through the club. Add the child's own assent from about age 14.
  - Use a one-page form, modelled on the NSPCC template, covering three things: (a) recording, (b) live streaming or publishing on YouTube, (c) use of the footage to develop and test the camera software, never published or shared. Consent for (c) must be separate and optional.
  - Store the signed forms and a per-match register.
- **GDPR**: for footage recorded in Ukraine of Ukrainian players, GDPR likely does not apply, because Follo neither offers services to nor monitors those players in the EU. Ukrainian Law 2297-VI and the Civil Code apply. If Follo users film in the EU, the user (club or parent) is the controller of the stream. Follo stays out of the data flow if all processing stays on the phone and the stream goes from the user's own YouTube account.
- **No user footage for training without opt-in**: if Follo ever collects user footage to train, it becomes a GDPR controller (Article 3(2) "offering services" to EU users). It would then need explicit, separate, opt-in consent, parental consent for children's footage, a privacy policy and an App Store privacy label. Until then, collect nothing.
- **Not biometric**: detection and tracking of the ball and players without identifying anyone is not "biometric data" under Article 4(14) and Recital 51. Avoid face recognition, re-identification across matches, and storing jersey-number-to-name links, so the processing stays non-special-category.
- **Made for kids**: youth match streams aimed at parents and club followers are best labelled "not made for kids". They are a sports event, not child-directed entertainment. The FTC factor "age of models" and the Disney settlement show the label should be considered per stream, not set blindly per channel. The setting is the user's (channel owner's) duty. Follo should surface the choice in the app, perhaps with a default prompt, rather than decide it.
- **Under-13 streams in the US**: if a stream is labelled made for kids, YouTube restricts features, but the specific restrictions were not confirmed on the fetched page.

### Gaps
- I did not fetch the operative text of Law 2297-VI. I could not confirm the current status of Ukraine's draft GDPR-aligned personal data law (No. 8153) as of October 2026.
- I did not confirm from a primary source which YouTube features (comments, live chat, personalised ads, notifications) are disabled for made-for-kids live streams.
- I found no Veo-authored consent template or Veo data processing terms.
- I did not research the Ukrainian Association of Football (UAF) rules on filming youth matches.
- I did not verify the effects of the 2025 amendments to the COPPA rule.

## 6. Decision table and minimal compliant data policy for a solo developer

### Takeaway
Train shipped weights only on own footage with signed consent and on CC BY or MIT-type data with an attribution file. Keep everything else (NC, SA, NDA, research-only, ordinary YouTube, stock sites) out of training. At most a few clearly logged, unpublished evaluation clips, and preferably none for NC and NDA sets. Keep AGPL tools as off-device teachers only.

### Cited Findings
- The table below synthesises the sources cited in sections 1–5; see them for each claim. CC's NC "all stages" rule — [Creative Commons](https://creativecommons.org/using-cc-licensed-works-for-ai-training-2/). Ultralytics' trained-model claim and the annotation forum answer — [Ultralytics License](https://www.ultralytics.com/license), [forum](https://community.ultralytics.com/t/auto-annotate-and-agpl/676). YouTube ToS download clause — [YouTube ToS](https://www.youtube.com/static?template=terms). Pexels and Pixabay ML clauses — [Pexels Terms](https://www.pexels.com/terms-of-service/), [Pixabay Terms](https://pixabay.com/service/terms/). Ukrainian research-only TDM — [EIFL](https://www.eifl.net/system/files/resources/202310/eifl_comments_ukraine_ip_dialogue_19_oct_2023.pdf).

### Inferences

Decision table (risk judgement, not legal advice; as of October 2026):

| Source type | Private evaluation | Training weights shipped commercially | Attribution | Main risks |
|---|---|---|---|---|
| Own recordings with signed parental or club consent | Yes | Yes (best source) | None; keep the consent register | Personal data of minors; consent scope must cover "software development"; storage security; withdrawals |
| Own recordings without written consent (public match, open filming) | Yes, internal only | Possible under the Civil Code Art. 307 presumption, but weak for minors; avoid | None | Art. 308 bars distribution; parents object; GDPR if filmed in the EU |
| Club recordings (Veo or phone) given by the club | Yes, with a written data-sharing note from the club | Yes, only if the club confirms it holds parental consent covering third-party development use, and grants us a licence | Per agreement | The club's consent may only cover streaming; Veo's ToS may claim rights over footage; get a written licence |
| CC BY 4.0 datasets (SoccerTrack v2) and MIT code | Yes | Yes | Credits or NOTICE: dataset name, authors, link, "CC BY 4.0", paper citation | Players' personal data or image rights not covered by CC; do not republish frames in marketing |
| CC BY on YouTube | Yes | Probably yes, if the uploader really owns the footage | Title, author, URL, "CC BY" | Mis-licensed TV re-uploads; YouTube ToS forbids downloading; keep evidence of the licence at download time |
| CC BY-SA | Yes | Avoid (ShareAlike may attach to the shared model) | Required if used | Licence contamination of the weights |
| CC BY-NC / BY-NC-SA (e.g. DeepSportradar, if confirmed) | Grey; CC says "all stages" must be non-commercial; prefer not | No | Required | Breach of licence ends it; commercial-advantage argument |
| Research-only or NDA (SoccerNet, broadcast-derived) | Only if the NDA allows it; it probably does not for a commercial product | No | Per NDA | Contract breach plus broadcast rights of leagues and TV |
| Ordinary YouTube (all rights reserved) | Low practical risk, but a ToS breach; no Ukrainian TDM exception | No | — | Copyright (Ukraine, US after ROSS), ToS, broadcasting rights |
| Stock sites (Pexels, Pixabay) | A few clips, manual download only | No (terms ban ML extraction; Pixabay bans training) | Not required by licence | Terms breach; identifiable people clause |
| Stock sites (Mixkit, Videvo) | Read the terms first | Unknown, default No | Videvo CC 3.0 clips need credit | Unverified terms |
| AGPL teacher outputs (YOLO pseudo-labels) | Yes (local) | Labels used by our own training code: low risk | Credit Ultralytics as the teacher in internal docs | Ultralytics' broad "trained models" claim; never ship YOLO code or weights or derive the student from them |

Minimal data policy (proposal):
1. **Data register** (`specs/datasets.md` or `data/REGISTER.csv`, committed; no videos). For every source, log:
   - id, origin URL or owner, date obtained, licence with a link and a dated archive copy, how obtained (manual or automatic), personal-data notes (minors yes or no, consent reference);
   - allowed uses: `eval` / `train` / `none`;
   - which model versions used it, and the train/held-out split.
2. **Attribution file**: `THIRD_PARTY_DATA.md` in the repo, plus an "Acknowledgements" screen or App Store description note for any CC BY data in shipped-weight training. Example: "Ball detector trained in part on SoccerTrack v2 (Scott et al., 2025), CC BY 4.0, github.com/AtomScott/SoccerTrack-v2".
3. **Model card per shipped weight file**: training data ids from the register, teacher models used (YOLO, AGPL, off-device only), date, and code commit.
4. **Never use for training**: NC, SA, NDA or research-only sets; ordinary YouTube; stock sites; footage without consent where minors are identifiable; anything scraped against ToS; user footage from the app without separate opt-in consent.
5. **Consent kit for own youth recordings**: club-distributed parental form with separate tick boxes for (a) recording, (b) public stream, (c) internal software development. Add the child's assent from about 14, a withdrawal route (delete that match's footage), a retention limit (e.g. delete raw video 24 months after the match, keep only derived labels), and storage on an encrypted disk.
6. **On-device by design**: the app sends nothing to the developer. Streams go from the user's own YouTube account, and the user sets the "made for kids" flag; the app asks about it before the first youth stream.
7. **Revisit triggers**: a Supreme Court grant in ROSS, a BGH ruling in LAION, a Ukrainian copyright amendment adding commercial TDM, or any plan to collect user footage.

### Gaps
- The table has not been reviewed by a Ukrainian or EU lawyer. For a commercial launch, one hour with an IP or privacy lawyer covering three points (Article 22 scope, club data-sharing wording, the parental consent form) is the highest-value check.
- I did not research Apple App Store Review Guidelines 5.1 and 5.2 (privacy and IP) or App Store privacy-label obligations for training data.
- I did not research Veo's own terms on footage ownership, which matter if clubs hand over Veo recordings.
