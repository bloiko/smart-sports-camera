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
    @StateObject var cam = CameraSession()
    @StateObject var ls = LiveSession()
    @State var live: LiveTarget?
    @State var status = "Все поле в кадрі? Ворота з обох боків?"
    @State var error: String?
    @State var startedAt: Date?
    @State var thermal = ProcessInfo.processInfo.thermalState

    var body: some View {
        VStack(spacing: 12) {
            Text(cam.isRecording ? "LIVE" : "Готово до гри").font(.system(size: 28, weight: .heavy, design: .rounded))
            CameraPreview(session: cam.session).aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            HStack {
                stat(cam.isRecording ? "\(cam.chunkCount)" : "—", "файлів 4K")
                stat(thermalText, "телефон")
                stat(startedAt.map { fmt(Date().timeIntervalSince($0)) } ?? "—", "у ефірі")
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
                .font(.system(size: 22, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity).padding(16)
                .background(cam.isRecording ? Color.gray.opacity(0.4) : Color.red).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .onAppear { cam.configure(); UIApplication.shared.isIdleTimerDisabled = true }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if startedAt != nil { startedAt = startedAt; ls.tick(onFrameRate: { ls.streamer.setFrameRate($0) }, onDetectEvery: { _ in }, onEnd: { stop() }) }
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
                    // TODO: віртуальна камера (Core ML) → ls.streamer.push(crop1080p, at: time); поки що — центр кадру
                    cam.frameHandler = { [ls] sb in
                        if let pb = CMSampleBufferGetImageBuffer(sb) { Task { @MainActor in ls.streamer.push(pb, at: CMSampleBufferGetPresentationTimeStamp(sb)) } }
                    }
                }
            } catch { self.error = "YouTube: \(error.localizedDescription)" }
        }
    }

    func stop() {
        cam.stopRecording(); startedAt = nil; ls.streamer.stop(); ls.save(nil); cam.frameHandler = nil
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
