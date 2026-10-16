import SwiftUI
import Combine
import FolloCore
import AVFoundation

/// Прев'ю до ефіру: кадр з камери → UIImage (5 fps). AVCaptureVideoPreviewLayer і AVSampleBufferDisplayLayer
/// на цій сесії (ручний 4K-формат, NV12) на iPhone 15 нічого не показували.
struct CameraPreview: View {
    @ObservedObject var cam: CameraSession
    var body: some View {
        ZStack {
            Color.black
            if let img = cam.previewImage { Image(uiImage: img).resizable().scaledToFit() }
            else { Text("Камера…").foregroundStyle(.secondary) }
        }
    }
}

struct SetupView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var cam = CameraSession()
    @StateObject var ls = LiveSession()
    @StateObject var score = ScoreModel()                            // рахунок на трансляції
    @State var showTeams = false
    @State var autoWentLive = false                                  // debug --golive: only once per launch
    @State var match: MatchRecord?                                   // поточний матч: своя папка, запис у списку з першої секунди
    @State var live: LiveTarget?
    @State var status = "Все поле в кадрі? Ворота з обох боків?"
    @State var error: String?
    @State var startedAt: Date?
    @State var thermal = ProcessInfo.processInfo.thermalState
    @State var lastTouch = Date()                                   // пункт 11
    @State var viewer = false
    @State var stoppedAt: Date?                                      // GO LIVE не спрацьовує 3 с після СТОП
    @State var holdingStop = false
    @State var muted = false
    @StateObject var yt = YouTubeAccount()                           // власний вхід Google → ефір «Не для всіх»
    @State var privacy: YouTubeAPI.Privacy = .unlisted               // з чим стартує ефір (debug: приватне або не для всіх)
    @State var livePrivacy: String?                                  // видимість ефіру зараз (з YouTube)
    @State var confirmPublic = false                                         // кнопка «Звук»: тиша в ефірі замість мікрофона
    @State var lastDbg = ""
    // таймер один на весь екран: Timer.publish у body перестворювався з кожним кадром прев'ю і не встигав спрацювати
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.scenePhase) var scenePhase                                       // пункт 10
    @State var showAdvice = !UserDefaults.standard.bool(forKey: "advice.shown")   // пункти 9, 14
    @State var result: Bool = false                                 // екран результату після Стоп
    @State var clips: [HighlightsRunner.Clip] = []
    @State var hlProgress: String?

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
        // екран прокручується: на малому телефоні прев'ю, табло і кнопки не влазять разом; GO LIVE / СТОП завжди внизу
        ScrollView {
        VStack(spacing: 12) {
            HStack {
                if !cam.isRecording { Button { dismiss() } label: { Image(systemName: "chevron.left") }.accessibilityIdentifier("back") }
                Spacer(); Text(cam.isRecording ? "LIVE" : "Готово до гри").font(.system(size: 28, weight: .heavy, design: .rounded)).accessibilityIdentifier("title"); Spacer()
            }
            if viewer && cam.isRecording {
                ViewerView(runner: ls.runner).frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Так бачить глядач (без затримки YouTube). Не виходь із застосунку: камера зупиниться — дивись трансляцію на іншому телефоні.").font(.caption2).foregroundStyle(.secondary)
            } else {
                CameraPreview(cam: cam).frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if cam.isRecording {
                HStack(spacing: 12) {
                    Toggle("Погляд глядача", isOn: $viewer).font(.footnote)
                    Button { muted.toggle(); ls.streamer.setMuted(muted) } label: {
                        Label(muted ? "Звук вимкнено" : "Звук", systemImage: muted ? "mic.slash.fill" : "mic.fill")
                    }.accessibilityIdentifier("mute").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(muted ? Color.red.opacity(0.4) : Color.white.opacity(0.08)).clipShape(Capsule())
                }
            }
            HStack {
                stat(cam.isRecording ? "\(cam.chunkCount)" : "—", "файлів 4K")
                stat(thermalText, "телефон")
                stat(startedAt.map { fmt(Date().timeIntervalSince($0)) } ?? "—", "у ефірі")
                stat(startedAt != nil ? "\(Int(ls.runner.ballShare * 100))%" : "—", "м'яч")
            }
            if cam.isRecording { ScoreBar(score: score) }
            else {
                Button { showTeams = true } label: {
                    HStack { Text("Команди"); Spacer(); Text("\(score.state.home.name) – \(score.state.away.name)").foregroundStyle(.secondary).lineLimit(1) }
                }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !cam.isRecording, yt.auth != nil { youTubeRow }
            if let l = live, cam.isRecording {
                HStack { Text(l.watchURL).font(.footnote).lineLimit(1).accessibilityIdentifier("watchURL"); Spacer()
                    Button("Копіювати") { UIPasteboard.general.string = l.watchURL }
                    if let u = URL(string: l.watchURL), u.host?.contains("youtu") == true { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } } }
                    .padding(10).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                if !l.broadcastId.isEmpty { livePrivacyRow(l) }
            }
            Text(error ?? cam.cameraError ?? status).accessibilityIdentifier("status").font(.footnote).foregroundStyle(cam.cameraError == nil ? Color.secondary : Color.yellow).multilineTextAlignment(.center)
            if !cam.isRecording, !CameraSession.testVideos.isEmpty {      // лише debug: тестове відео замість камери
                Picker("Джерело", selection: Binding(get: { cam.testVideo }, set: { cam.setSource($0); ls.runner.resetPosition() })) {
                    Text("Камера").tag(URL?.none)
                    ForEach(CameraSession.testVideos, id: \.self) { Text("Відео \($0.deletingPathExtension().lastPathComponent)").tag(URL?.some($0)) }
                }.pickerStyle(.segmented)
            }
            #if DEBUG
            if !cam.isRecording {                                             // debug: which stream path (rollback switch, stage 1f)
                Picker("Стрім", selection: Binding(get: { Streamer.engine.rawValue }, set: { UserDefaults.standard.set($0, forKey: "debug.streamer") })) {
                    Text("Стрім: HaishinKit").tag("haishinkit"); Text("Стрім: Follo").tag("follo")
                }.pickerStyle(.segmented)
            }
            #endif
            if cam.isRecording, ls.streamer.delayS > 5 {                      // own engine after a network drop
                HStack { Text("Ефір відстає на \(Int(ls.streamer.delayS)) с").font(.footnote); Spacer(); Button("Наздогнати ефір") { ls.streamer.catchUp() }.font(.footnote) }
                    .padding(8).background(Color.yellow.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !cam.formatInfo.isEmpty { Text(cam.formatInfo).font(.caption2).foregroundStyle(.secondary) }
            if let l = cam.lowLight { Text(l).font(.caption2).foregroundStyle(Color.yellow).multilineTextAlignment(.center) }
            if !cam.isRecording, (ls.runner.env?.positionProblem ?? "").contains("too small") || cam.useWide {
                Button(cam.useWide ? "Назад до 0.5× (ультраширока)" : "Поле замале → спробувати камеру 1×") {
                    cam.switchCamera(wide: !cam.useWide); ls.runner.resetPosition()
                }.font(.footnote)
            }
            if let w = ls.warning { Text(w).font(.footnote).foregroundStyle(.yellow) }
            if !cam.isRecording, yt.signedIn, let s = ls.saved, !s.broadcastId.isEmpty, Date().timeIntervalSince(s.startedAt) < 3 * 3600 {
                Text("GO LIVE продовжить ефір \(s.watchURL) (те саме посилання)").font(.footnote).foregroundStyle(.secondary)
            } else if !cam.isRecording, let s = ls.saved, Date().timeIntervalSince(s.startedAt) < 3 * 3600 {
                Button("Відновити ефір \(s.watchURL.suffix(11))…") { live = LiveTarget(broadcastId: s.broadcastId, rtmpsURL: s.rtmpsURL, streamKey: s.streamKey, watchURL: s.watchURL); go(resume: true) }
                    .font(.footnote).disabled(!positionOK)
            }
        }
        .padding(16)
        }
            // СТОП — окремий вигляд без дії на дотик: у Button з утриманням відпускання пальця після стопу натискало GO LIVE
            Group {
                if cam.isRecording {
                    Text(holdingStop ? "■  Тримай…" : "■  СТОП (утримуй)").frame(maxWidth: .infinity).padding(16)
                        .background(holdingStop ? Color.red.opacity(0.7) : Color.gray.opacity(0.4))
                        .onLongPressGesture(minimumDuration: 1, perform: { holdingStop = false; stop() }, onPressingChanged: { holdingStop = $0 })
                        .accessibilityIdentifier("stop").accessibilityAddTraits(.isButton)
                } else {
                    // сіра, поки позиція не перевірена (вимкнена кнопка з червоним тлом виглядала активною)
                    Button(positionOK ? "●  GO LIVE" : "Перевіряю поле…") { if stoppedAt.map({ Date().timeIntervalSince($0) > 3 }) ?? true { go() } }
                        .disabled(!positionOK).accessibilityIdentifier("goLive")
                        .frame(maxWidth: .infinity).padding(16).background(positionOK ? Color.red : Color.gray.opacity(0.35))
                }
            }
                .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
        if cam.isRecording { DimOverlay(lastTouch: $lastTouch) }
        }
        .background(TouchWatcher { if Date().timeIntervalSince(lastTouch) > 1 { lastTouch = Date() } })    // дотик і прокрутка
        .sheet(isPresented: $showAdvice) { BeforeGameSheet { UserDefaults.standard.set(true, forKey: "advice.shown"); showAdvice = false } }
        .confirmationDialog("Зробити ефір «Для всіх»? Його побачать на каналі, у пошуку і підписники отримають сповіщення.", isPresented: $confirmPublic, titleVisibility: .visible) {
            Button("Так, для всіх") { if let l = live { setPrivacy(l, .public) } }
        }
        .sheet(isPresented: $showTeams) { TeamsSheet(score: score) { showTeams = false } }
        .onChange(of: score.state) { _, _ in if startedAt != nil { score.push(to: ls.runner) } }
        .sheet(isPresented: $result) { ResultView(watchURL: live?.watchURL, clips: clips, progress: hlProgress, match: match) }
        .onAppear {
            DebugLog.reset(); UIDevice.current.isBatteryMonitoringEnabled = true
            // debug: --video NAME з Mac або останній вибір у перемикачі
            if let i = CommandLine.arguments.firstIndex(of: "--video"), i + 1 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 1], forKey: "debug.testVideo") }
            if CommandLine.arguments.contains("--camera") { UserDefaults.standard.removeObject(forKey: "debug.testVideo") }
            if let i = CommandLine.arguments.firstIndex(of: "--streamer"), i + 1 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 1], forKey: "debug.streamer") }
            if let n = UserDefaults.standard.string(forKey: "debug.testVideo") { cam.testVideo = CameraSession.testVideos.first { $0.lastPathComponent == n } }
            cam.configure(); UIApplication.shared.isIdleTimerDisabled = true
            ls.calls.onCall = { [ls] active in ls.warning = active ? "Дзвінок: камера на паузі, після дзвінка ефір відновиться сам" : nil }
            // до ефіру: кадри для перевірки позиції (маска поля); під час ефіру: віртуальна камера
            cam.frameHandler = { [ls] sb in
                if ls.runner.isLive { ls.runner.push(sb) }
                else if let pb = CMSampleBufferGetImageBuffer(sb) { ls.runner.addPrerollFrame(pb, time: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))) }
            }
        }
        .onChange(of: scenePhase) { _, ph in
            // у фоні iOS і так зупиняє камеру; відпускаємо її явно, щоб вона не лишалась зайнятою
            DebugLog.log("scene \(ph == .active ? "active" : ph == .background ? "background" : "inactive")")
            if ph == .background { cam.pause() } else if ph == .active { cam.resume() }
        }
        .onDisappear { cam.pause() }
        .onChange(of: cam.sourceFps, initial: true) { _, f in ls.runner.fps = f }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
        .onReceive(ticker) { _ in
            // debug: --golive натискає GO LIVE сам, щойно перевірка позиції пройшла (тест з Mac без дотику)
            if startedAt == nil, !cam.isRecording, !autoWentLive, CommandLine.arguments.contains("--golive"), positionOK, error == nil { DebugLog.log("auto GO LIVE"); autoWentLive = true; go() }
            if let s = startedAt, Int(Date().timeIntervalSince(s)) % 10 == 0 {
                DebugLog.log("live \(Int(Date().timeIntervalSince(s))) s: frames in \(ls.runner.inFrames) out \(ls.runner.outFrames) ball \(Int(ls.runner.ballShare * 100))% goals \(ls.runner.goalsKnown) chunks \(cam.chunkCount) stream \(ls.streamer.state) \(ls.streamer.bitrateKbps) kbps thermal \(thermalText) mem \(DebugLog.memMB()) MB battery \(Int(UIDevice.current.batteryLevel * 100))% \(UIDevice.current.batteryState == .unplugged ? "unplugged" : "charging") delay \(Int(ls.streamer.delayS)) s")
                if !ls.streamer.diag.isEmpty { DebugLog.log("  " + ls.streamer.diag) }
            }
            if startedAt != nil { score.push(to: ls.runner) }
            // debug: --stop-after N натискає «Стоп» через N секунд ефіру (перевірка запису з Mac)
            if let s = startedAt, let i = CommandLine.arguments.firstIndex(of: "--stop-after"), i + 1 < CommandLine.arguments.count,
               let n = Double(CommandLine.arguments[i + 1]), Date().timeIntervalSince(s) >= n { DebugLog.log("auto STOP after \(Int(n)) s"); stop() }
            if startedAt != nil { startedAt = startedAt; ls.tick(onFrameRate: { ls.streamer.setFrameRate($0) }, onDetectEvery: { ls.runner.setDetectEvery($0) }, onLowStorage: { cam.stopRecording() }, onEnd: { stop() }) }
            else if error == nil { let st = ls.runner.env == nil ? "preroll \(ls.runner.prerollCount)/7 building \(ls.runner.building)" : (ls.runner.env?.positionProblem ?? "pitch ok"); if st != lastDbg { DebugLog.log(st); lastDbg = st }
                status = ls.runner.env == nil ? "Перевіряю позицію: кадр \(ls.runner.prerollCount)/7\(ls.runner.building ? ", рахую поле…" : "")" : (ls.runner.env?.positionProblem ?? "Поле в кадрі. Можна в ефір") }
        }
    }

    /// Правило власника: ефір ніколи не стартує, поки не знайдене поле і обидва дальні кути з воротами не в кадрі
    /// (перевірка позиції). Стоїть у самому go(), тож її не обходить ні GO LIVE, ні «Відновити ефір», ні --golive.
    var positionOK: Bool { ls.runner.env != nil && ls.runner.env?.positionProblem == nil }
    /// Тест: тестове відео замість камери або запуск з Mac. Правило власника: у тестах звук ефіру завжди вимкнений.
    var isTest: Bool { cam.testVideo != nil || CommandLine.arguments.contains("--autostart") }

    func go(resume resumeAsked: Bool = false) {
        var resume = resumeAsked
        guard positionOK else { DebugLog.log("GO LIVE refused: position not checked (\(ls.runner.env?.positionProblem ?? "no pitch yet"))"); return }
        if isTest && !muted { muted = true; ls.streamer.setMuted(true) }
        error = nil; status = "Створюю трансляцію…"
        let problems = ls.preflight()
        if !problems.isEmpty && !resume { status = problems.joined(separator: " · ") }
        Task {
            do {
                if yt.signedIn {
                    // ефір, що лишився після перезапуску застосунку посеред матчу (Стоп не натискали), — той самий: те саме посилання
                    let saved = ls.saved.flatMap { !$0.broadcastId.isEmpty && Date().timeIntervalSince($0.startedAt) < 3 * 3600 ? $0 : nil }
                    // старий ефір після збою (автостоп вимкнено, сам YouTube його не закриє): закрити, щоб не висів «в ефірі»
                    if let old = ls.saved, !old.broadcastId.isEmpty, saved == nil {
                        let api = yt.api(); Task { try? await api.complete(old.broadcastId); DebugLog.log("YouTube: closed stale broadcast \(old.broadcastId)") }
                    }
                    let (b, st) = try await yt.api().prepare(streamId: yt.streamId, resumeBroadcastId: saved?.broadcastId, title: "Follo \(Date().formatted(date: .abbreviated, time: .shortened))", privacy: privacy)
                    yt.streamId = st.id; livePrivacy = b.privacy
                    if b.id == saved?.broadcastId { resume = true }
                    live = LiveTarget(broadcastId: b.id, rtmpsURL: st.ingestURL, streamKey: st.key, watchURL: b.watchURL)
                    DebugLog.log("YouTube: broadcast \(b.id) \(b.privacy) (asked \(privacy.rawValue))\(resume ? " (same as before the restart)" : ""), engine \(Streamer.engine.rawValue)")
                }
                else if !resume, let t = YouTubeLive.debugTarget() {                        // debug: свій RTMP-сервер (ffmpeg на Mac)
                    live = LiveTarget(broadcastId: "", rtmpsURL: t.url, streamKey: t.key, watchURL: t.url)
                    DebugLog.log("stream target: \(t.url) (debug), engine \(Streamer.engine.rawValue)")
                }
                else if !resume, let k = YouTubeLive.debugStreamKey() {      // debug: ключ з YouTube Studio
                    live = LiveTarget(broadcastId: "", rtmpsURL: YouTubeLive.studioIngest, streamKey: k, watchURL: "https://studio.youtube.com")
                    DebugLog.log("YouTube: Studio stream key")
                }
                else if live == nil { status = "Без YouTube: лише запис (увійди в YouTube)" }
                if !resume { score.newMatch() }
                // debug: --clock H:MM:SS ставить тайм і час після старту (перевірка табло з Mac)
                if let i = CommandLine.arguments.firstIndex(of: "--clock"), i + 1 < CommandLine.arguments.count {
                    let p = CommandLine.arguments[i + 1].split(separator: ":").compactMap { Int($0) }
                    if p.count == 3 { score.half = p[0]; score.setClock(Double(p[1] * 60 + p[2])) }
                }
                score.push(to: ls.runner)
                let start = resume ? ls.saved?.startedAt ?? Date() : Date()
                let folder = MatchStore.folderName(for: start)
                var m = MatchStore.load().first(where: { $0.folder == folder })
                    ?? MatchRecord(date: start, watchURL: live?.watchURL, durationS: 0, chunkFiles: [], clipFiles: [], goals: 0, knownPitch: false, folder: folder)
                m.recording = true; MatchStore.upsert(m); match = m
                cam.startRecording(dir: MatchStore.chunksDir(m)); startedAt = start
                DebugLog.log("recording into matches/\(folder)")
                if let l = live {
                    ls.save(.init(broadcastId: l.broadcastId, rtmpsURL: l.rtmpsURL, streamKey: l.streamKey, watchURL: l.watchURL, startedAt: startedAt!))
                    await ls.streamer.start(url: l.rtmpsURL, key: l.streamKey)
                }
                // віртуальна камера: кроп 1920×1080 із затримкою 2 с → стрімер (і «погляд глядача», пункт 10)
                ls.runner.onOutput = { [ls] pb, t in Task { @MainActor in ls.streamer.push(pb, at: t) } }
                do { try ls.runner.start() } catch { self.error = "Камера: \(error.localizedDescription) (моделі players/ball.mlmodelc у проєкті?)" }
            } catch { self.error = "YouTube: \(error.localizedDescription)" }
        }
    }

    func stop() {
        let startedAtSaved = startedAt ?? Date()
        stoppedAt = Date(); DebugLog.log("STOP")
        cam.stopRecording(); startedAt = nil; ls.streamer.stop(); ls.save(nil)
        let camOut = ls.runner.stop(); let env = ls.runner.env; let target = live
        result = true; clips = []; hlProgress = "Готую хайлайти…"
        // хайлайти з записаних файлів у фоні (≈ 1–2 хв): кікоф → гол, кліпи 16:9 і 9:16
        DispatchQueue.global(qos: .userInitiated).async {
            let rec = match ?? MatchRecord(date: startedAtSaved, durationS: 0, chunkFiles: [], clipFiles: [], goals: 0, knownPitch: false, folder: MatchStore.folderName(for: startedAtSaved))
            Thread.sleep(forTimeInterval: 1)                          // останній файл дописується після stopRecording
            let chunks = MatchStore.chunks(rec)
            var out: [HighlightsRunner.Clip] = []
            if let (c, j) = camOut, let e = env { out = (try? HighlightsRunner.make(chunks: chunks, cam: c, jerseys: j, env: e, outDir: MatchStore.highlightsDir(rec), progress: { p in DispatchQueue.main.async { hlProgress = p } })) ?? [] }
            DispatchQueue.main.async {
                clips = out; hlProgress = nil
                var m = rec
                m.watchURL = target?.watchURL ?? m.watchURL; m.durationS = Date().timeIntervalSince(startedAtSaved)
                m.chunkFiles = chunks.map { $0.lastPathComponent }; m.clipFiles = out.map { $0.file.lastPathComponent }
                m.goals = out.filter { $0.kind == "goal" }.count; m.knownPitch = ls.runner.knownPitch; m.recording = false
                MatchStore.upsert(m); match = m
            }
        }
        if let l = target, !l.broadcastId.isEmpty, yt.signedIn {
            Task { do { try await yt.api().complete(l.broadcastId); DebugLog.log("YouTube: broadcast \(l.broadcastId) ended") } catch { DebugLog.log("YouTube: end failed: \(error.localizedDescription)") } }
        }
        livePrivacy = nil
        status = "Записано \(cam.chunkCount) файлів 4K — у «Моїх матчах»: переглянути і зберегти у Фото"
    }

    /// До ефіру: вхід у YouTube і з якою видимістю стартувати. «Для всіх» тут немає ніколи: лише під час ефіру, в релізі.
    var youTubeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                if yt.signedIn { Text("YouTube: \(yt.channel ?? "вхід виконано")").lineLimit(1); Spacer(); Button("Вийти") { yt.signOut() }.foregroundStyle(.secondary) }
                else { Button(yt.busy ? "Вхід…" : "Увійти в YouTube (Google)") { Task { await yt.signIn() } }.disabled(yt.busy).accessibilityIdentifier("signIn"); Spacer() }
            }
            if yt.signedIn {
                #if DEBUG
                Picker("Видимість", selection: $privacy) { Text("Приватне").tag(YouTubeAPI.Privacy.private); Text("Не для всіх").tag(YouTubeAPI.Privacy.unlisted) }
                    .pickerStyle(.segmented).accessibilityIdentifier("privacyPicker")
                #else
                Text("Ефір стартує «Не для всіх»: бачать лише ті, кому ти дав посилання").font(.caption2).foregroundStyle(.secondary)
                #endif
            }
            if let e = yt.error { Text(e).font(.caption2).foregroundStyle(.yellow) }
        }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Під час ефіру: видимість і перемикач. Тестова збірка: приватне ⇄ не для всіх. Реліз: «Для всіх» з підтвердженням.
    func livePrivacyRow(_ l: LiveTarget) -> some View {
        let p = livePrivacy ?? ""
        let name = ["private": "Приватне", "unlisted": "Не для всіх", "public": "Для всіх"][p] ?? "…"
        return HStack {
            Image(systemName: p == "public" ? "globe" : p == "unlisted" ? "link" : "lock.fill")
            Text(name).accessibilityIdentifier("privacy"); Spacer()
            #if DEBUG
            Button(p == "private" ? "Зробити «Не для всіх»" : "Зробити приватним") { setPrivacy(l, p == "private" ? .unlisted : .private) }
            #else
            if p == "public" { Button("Зробити «Не для всіх»") { setPrivacy(l, .unlisted) } }
            else { Button("Зробити «Для всіх»…") { confirmPublic = true } }
            #endif
        }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func setPrivacy(_ l: LiveTarget, _ p: YouTubeAPI.Privacy) {
        Task {
            do { livePrivacy = try await yt.api().setPrivacy(l.broadcastId, p).privacy; DebugLog.log("YouTube: privacy \(livePrivacy ?? "")") }
            catch { self.error = error.localizedDescription }
        }
    }

    var thermalText: String { ["ok", "ok", "гаряче", "критично"][min(thermal.rawValue, 3)] }
    func fmt(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.system(size: 20, weight: .heavy, design: .rounded)); Text(l).font(.caption2).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
