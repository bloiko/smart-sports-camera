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
    @State var live: LiveTarget?
    @State var status = "Все поле в кадрі? Ворота з обох боків?"
    @State var error: String?
    @State var startedAt: Date?
    @State var thermal = ProcessInfo.processInfo.thermalState
    @State var lastTouch = Date()                                   // пункт 11
    @State var viewer = false
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
        VStack(spacing: 12) {
            HStack {
                if !cam.isRecording { Button { dismiss() } label: { Image(systemName: "chevron.left") } }
                Spacer(); Text(cam.isRecording ? "LIVE" : "Готово до гри").font(.system(size: 28, weight: .heavy, design: .rounded)); Spacer()
            }
            if viewer && cam.isRecording {
                ViewerView(runner: ls.runner).frame(maxWidth: .infinity).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Так бачить глядач (без затримки YouTube). Не виходь із застосунку: камера зупиниться — дивись трансляцію на іншому телефоні.").font(.caption2).foregroundStyle(.secondary)
            } else {
                CameraPreview(cam: cam).frame(maxWidth: .infinity).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if cam.isRecording { Toggle("Погляд глядача", isOn: $viewer).font(.footnote) }
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
            if let l = live {
                HStack { Text(l.watchURL).font(.footnote).lineLimit(1); Spacer()
                    Button("Копіювати") { UIPasteboard.general.string = l.watchURL } }
                    .padding(10).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(error ?? cam.cameraError ?? status).font(.footnote).foregroundStyle(cam.cameraError == nil ? Color.secondary : Color.yellow).multilineTextAlignment(.center)
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
            Spacer()
            if let w = ls.warning { Text(w).font(.footnote).foregroundStyle(.yellow) }
            if !cam.isRecording, let s = ls.saved, Date().timeIntervalSince(s.startedAt) < 3 * 3600 {
                Button("Відновити ефір \(s.watchURL.suffix(11))…") { live = LiveTarget(broadcastId: s.broadcastId, rtmpsURL: s.rtmpsURL, streamKey: s.streamKey, watchURL: s.watchURL); go(resume: true) }
                    .font(.footnote)
            }
            Button(cam.isRecording ? "■  СТОП (утримуй)" : "●  GO LIVE") { if !cam.isRecording { go() } }
                .simultaneousGesture(LongPressGesture(minimumDuration: 1).onEnded { _ in if cam.isRecording { stop() } })
                .disabled(!cam.isRecording && (ls.runner.env == nil || ls.runner.env?.positionProblem != nil))
                .font(.system(size: 22, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity).padding(16)
                .background(cam.isRecording ? Color.gray.opacity(0.4) : Color.red).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        if cam.isRecording { DimOverlay(lastTouch: $lastTouch) }
        }
        .contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in lastTouch = Date() })
        .sheet(isPresented: $showAdvice) { BeforeGameSheet { UserDefaults.standard.set(true, forKey: "advice.shown"); showAdvice = false } }
        .sheet(isPresented: $showTeams) { TeamsSheet(score: score) { showTeams = false } }
        .onChange(of: score.state) { _, _ in if startedAt != nil { score.push(to: ls.runner) } }
        .sheet(isPresented: $result) { ResultView(watchURL: live?.watchURL, clips: clips, progress: hlProgress) }
        .onAppear {
            DebugLog.reset()
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
            if ph == .background { cam.pause() } else if ph == .active { cam.resume() }
        }
        .onDisappear { cam.pause() }
        .onChange(of: cam.sourceFps, initial: true) { _, f in ls.runner.fps = f }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
        .onReceive(ticker) { _ in
            // debug: --golive натискає GO LIVE сам, щойно перевірка позиції пройшла (тест з Mac без дотику)
            if startedAt == nil, !cam.isRecording, CommandLine.arguments.contains("--golive"), ls.runner.env != nil, ls.runner.env?.positionProblem == nil, error == nil { DebugLog.log("auto GO LIVE"); go() }
            if let s = startedAt, Int(Date().timeIntervalSince(s)) % 10 == 0 {
                DebugLog.log("live \(Int(Date().timeIntervalSince(s))) s: frames in \(ls.runner.inFrames) out \(ls.runner.outFrames) ball \(Int(ls.runner.ballShare * 100))% goals \(ls.runner.goalsKnown) chunks \(cam.chunkCount) stream \(ls.streamer.state) \(ls.streamer.bitrateKbps) kbps thermal \(thermalText) mem \(DebugLog.memMB()) MB")
            }
            if startedAt != nil { score.push(to: ls.runner) }
            if startedAt != nil { startedAt = startedAt; ls.tick(onFrameRate: { ls.streamer.setFrameRate($0) }, onDetectEvery: { ls.runner.setDetectEvery($0) }, onLowStorage: { cam.stopRecording() }, onEnd: { stop() }) }
            else if error == nil { let st = ls.runner.env == nil ? "preroll \(ls.runner.prerollCount)/7 building \(ls.runner.building)" : (ls.runner.env?.positionProblem ?? "pitch ok"); if st != lastDbg { DebugLog.log(st); lastDbg = st }
                status = ls.runner.env == nil ? "Перевіряю позицію: кадр \(ls.runner.prerollCount)/7\(ls.runner.building ? ", рахую поле…" : "")" : (ls.runner.env?.positionProblem ?? "Поле в кадрі. Можна в ефір") }
        }
    }

    func go(resume: Bool = false) {
        error = nil; status = "Створюю трансляцію…"
        let problems = ls.preflight()
        if !problems.isEmpty && !resume { status = problems.joined(separator: " · ") }
        Task {
            do {
                // TODO: токен з Google Sign-In; поки що — з Info.plist ключ YT_TOKEN для тесту
                let token = Bundle.main.object(forInfoDictionaryKey: "YT_TOKEN") as? String ?? ""
                if !resume, !token.isEmpty { live = try await YouTubeLive.createBroadcast(token: token, title: "Follo \(Date().formatted(date: .abbreviated, time: .shortened))") }
                else if !resume, let t = YouTubeLive.debugTarget() {                        // debug: свій RTMP-сервер (ffmpeg на Mac)
                    live = LiveTarget(broadcastId: "", rtmpsURL: t.url, streamKey: t.key, watchURL: t.url)
                    DebugLog.log("stream target: \(t.url) (debug), engine \(Streamer.engine.rawValue)")
                }
                else if !resume, token.isEmpty, let k = YouTubeLive.debugStreamKey() {      // debug: ключ з YouTube Studio
                    live = LiveTarget(broadcastId: "", rtmpsURL: YouTubeLive.studioIngest, streamKey: k, watchURL: "https://studio.youtube.com")
                    DebugLog.log("YouTube: Studio stream key")
                }
                else if live == nil { status = "Без YouTube: лише запис (додай Google Sign-In)" }
                if !resume { score.newMatch() }
                // debug: --clock H:MM:SS ставить тайм і час після старту (перевірка табло з Mac)
                if let i = CommandLine.arguments.firstIndex(of: "--clock"), i + 1 < CommandLine.arguments.count {
                    let p = CommandLine.arguments[i + 1].split(separator: ":").compactMap { Int($0) }
                    if p.count == 3 { score.half = p[0]; score.setClock(Double(p[1] * 60 + p[2])) }
                }
                score.push(to: ls.runner)
                cam.startRecording(); startedAt = resume ? ls.saved?.startedAt ?? Date() : Date()
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
        cam.stopRecording(); startedAt = nil; ls.streamer.stop(); ls.save(nil)
        let camOut = ls.runner.stop(); let env = ls.runner.env; let target = live
        result = true; clips = []; hlProgress = "Готую хайлайти…"
        // хайлайти з записаних файлів у фоні (≈ 1–2 хв): кікоф → гол, кліпи 16:9 і 9:16
        DispatchQueue.global(qos: .userInitiated).async {
            let chunks = ((try? FileManager.default.contentsOfDirectory(at: ChunkWriter.dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "mp4" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var out: [HighlightsRunner.Clip] = []
            if let (c, j) = camOut, let e = env { out = (try? HighlightsRunner.make(chunks: chunks, cam: c, jerseys: j, env: e, progress: { p in DispatchQueue.main.async { hlProgress = p } })) ?? [] }
            DispatchQueue.main.async {
                clips = out; hlProgress = nil
                MatchStore.add(MatchRecord(date: startedAtSaved, watchURL: target?.watchURL, durationS: Date().timeIntervalSince(startedAtSaved),
                                           chunkFiles: chunks.map { $0.lastPathComponent }, clipFiles: out.map { $0.file.lastPathComponent },
                                           goals: out.filter { $0.kind == "goal" }.count, knownPitch: ls.runner.knownPitch))
            }
        }
        if let l = target, !l.broadcastId.isEmpty { Task { let t = Bundle.main.object(forInfoDictionaryKey: "YT_TOKEN") as? String ?? ""; await YouTubeLive.complete(token: t, broadcastId: l.broadcastId) } }
        status = "Записано \(cam.chunkCount) файлів у Documents/chunks"
    }

    var thermalText: String { ["ok", "ok", "гаряче", "критично"][min(thermal.rawValue, 3)] }
    func fmt(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.system(size: 20, weight: .heavy, design: .rounded)); Text(l).font(.caption2).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
