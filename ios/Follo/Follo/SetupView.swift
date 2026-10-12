import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspect; v.layer.addSublayer(l); return v
    }
    func updateUIView(_ v: UIView, context: Context) { v.layer.sublayers?.first?.frame = v.bounds }
}

struct SetupView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var cam = CameraSession()
    @StateObject var ls = LiveSession()
    @State var live: LiveTarget?
    @State var status = "Все поле в кадрі? Ворота з обох боків?"
    @State var error: String?
    @State var startedAt: Date?
    @State var thermal = ProcessInfo.processInfo.thermalState
    @State var lastTouch = Date()                                   // пункт 11
    @State var viewer = false                                       // пункт 10
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
                ViewerView(runner: ls.runner).aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Так бачить глядач (без затримки YouTube). Не виходь із застосунку: камера зупиниться — дивись трансляцію на іншому телефоні.").font(.caption2).foregroundStyle(.secondary)
            } else {
                CameraPreview(session: cam.session).aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if cam.isRecording { Toggle("Погляд глядача", isOn: $viewer).font(.footnote) }
            HStack {
                stat(cam.isRecording ? "\(cam.chunkCount)" : "—", "файлів 4K")
                stat(thermalText, "телефон")
                stat(startedAt.map { fmt(Date().timeIntervalSince($0)) } ?? "—", "у ефірі")
                stat(startedAt != nil ? "\(Int(ls.runner.ballShare * 100))%" : "—", "м'яч")
            }
            if let l = live {
                HStack { Text(l.watchURL).font(.footnote).lineLimit(1); Spacer()
                    Button("Копіювати") { UIPasteboard.general.string = l.watchURL } }
                    .padding(10).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(error ?? status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        .sheet(isPresented: $result) { ResultView(watchURL: live?.watchURL, clips: clips, progress: hlProgress) }
        .onAppear {
            cam.configure(); UIApplication.shared.isIdleTimerDisabled = true
            ls.calls.onCall = { [ls] active in ls.warning = active ? "Дзвінок: камера на паузі, після дзвінка ефір відновиться сам" : nil }
            // до ефіру: кадри для перевірки позиції (маска поля); під час ефіру: віртуальна камера
            cam.frameHandler = { [ls] sb in
                if ls.runner.isLive { ls.runner.push(sb) }
                else if let pb = CMSampleBufferGetImageBuffer(sb) { ls.runner.addPrerollFrame(pb, time: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if startedAt != nil { startedAt = startedAt; ls.tick(onFrameRate: { ls.streamer.setFrameRate($0) }, onDetectEvery: { ls.runner.setDetectEvery($0) }, onLowStorage: { cam.stopRecording() }, onEnd: { stop() }) }
            else if error == nil { status = ls.runner.env == nil ? "Перевіряю позицію (10 с)…" : (ls.runner.env?.positionProblem ?? "Поле в кадрі. Можна в ефір") }
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
                else if live == nil { status = "Без YouTube: лише запис (додай Google Sign-In)" }
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
        let live = ls.runner.stop(); let env = ls.runner.env
        result = true; clips = []; hlProgress = "Готую хайлайти…"
        // хайлайти з записаних файлів у фоні (≈ 1–2 хв): кікоф → гол, кліпи 16:9 і 9:16
        DispatchQueue.global(qos: .userInitiated).async {
            let chunks = ((try? FileManager.default.contentsOfDirectory(at: ChunkWriter.dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "mp4" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var out: [HighlightsRunner.Clip] = []
            if let (c, j) = live, let e = env { out = (try? HighlightsRunner.make(chunks: chunks, cam: c, jerseys: j, env: e, progress: { p in DispatchQueue.main.async { hlProgress = p } })) ?? [] }
            DispatchQueue.main.async {
                clips = out; hlProgress = nil
                MatchStore.add(MatchRecord(date: startedAtSaved, watchURL: live?.watchURL, durationS: Date().timeIntervalSince(startedAtSaved),
                                           chunkFiles: chunks.map { $0.lastPathComponent }, clipFiles: out.map { $0.file.lastPathComponent },
                                           goals: out.filter { $0.kind == "goal" }.count, knownPitch: ls.runner.knownPitch))
            }
        }
        if let l = live { Task { let t = Bundle.main.object(forInfoDictionaryKey: "YT_TOKEN") as? String ?? ""; await YouTubeLive.complete(token: t, broadcastId: l.broadcastId) } }
        status = "Записано \(cam.chunkCount) файлів у Documents/chunks"
    }

    var thermalText: String { ["ok", "ok", "гаряче", "критично"][min(thermal.rawValue, 3)] }
    func fmt(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.system(size: 20, weight: .heavy, design: .rounded)); Text(l).font(.caption2).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
