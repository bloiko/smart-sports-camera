import SwiftUI
import Combine
import AVKit
import Photos
import FolloCore

/// «Зберегти у Фото»: весь широкий запис матчу одним відео (склеєно без перекодування). Якщо місця на склеєну копію
/// не вистачає — частинами (по 3 хв).
@MainActor
final class PhotoSaver: ObservableObject {
    @Published var state: String?
    @Published var busy = false

    func save(_ m: MatchRecord) async {
        busy = true; defer { busy = false }
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else { state = "Немає дозволу на Фото: Параметри → Follo → Фото"; return }
        let chunks = MatchStore.chunks(m)
        guard !chunks.isEmpty else { state = "Широкого запису немає"; return }
        let needGB = Double(MatchVideo.bytes(chunks)) / 1e9
        DebugLog.log("photos: saving \(chunks.count) chunks, \(String(format: "%.2f", needGB)) GB, free \(String(format: "%.1f", MatchStore.freeGB())) GB")
        if MatchStore.freeGB() > needGB + 0.5 {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Follo_\(m.folder ?? "match").mp4")
            do {
                state = "Склеюю запис…"
                try await MatchVideo.join(chunks, to: out) { p in Task { @MainActor in self.state = "Склеюю запис… \(Int(p * 100))%" } }
                state = "Зберігаю у Фото…"
                try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: out) }
                state = "Збережено у Фото ✓"
                DebugLog.log("photos: saved one video")
            } catch {
                state = "Не вдалося: \(error.localizedDescription)"; DebugLog.log("photos: failed \(error)")
            }
            try? FileManager.default.removeItem(at: out)
        } else {
            var saved = 0
            for (i, u) in chunks.enumerated() {
                state = "Місця на склеєну копію мало — зберігаю частину \(i + 1) з \(chunks.count)…"
                do { try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: u) }; saved += 1 }
                catch { DebugLog.log("photos: part \(i + 1) failed \(error)") }
            }
            state = saved == chunks.count ? "Збережено у Фото частинами (\(saved)) ✓" : "Збережено \(saved) з \(chunks.count) частин"
        }
    }
}

/// Екран матчу: переглянути весь запис підряд, зберегти у Фото, кліпи хайлайтів.
struct MatchDetailView: View {
    let match: MatchRecord
    @StateObject var saver = PhotoSaver()
    @State var player: AVPlayer?
    @State var showPlayer = false
    @State var clip: URL?

    var body: some View {
        let chunks = MatchStore.chunks(match)
        let clips = ((try? FileManager.default.contentsOfDirectory(at: MatchStore.highlightsDir(match), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "mp4" && (match.folder != nil || match.clipFiles.contains($0.lastPathComponent)) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        List {
            Section("Запис усього поля (4K)") {
                if chunks.isEmpty { Text("Широкого запису на телефоні немає").foregroundStyle(.secondary) }
                else {
                    Button {
                        Task { if let c = try? await MatchVideo.composition(chunks) { player = AVPlayer(playerItem: AVPlayerItem(asset: c)); showPlayer = true } }
                    } label: { Label("Переглянути", systemImage: "play.rectangle.fill") }
                    Button { Task { await saver.save(match) } } label: { Label("Зберегти у Фото", systemImage: "square.and.arrow.down") }
                        .disabled(saver.busy)
                    if let s = saver.state { Text(s).font(.footnote).foregroundStyle(.secondary) }
                    Text(String(format: "%d частин по 3 хв, %.1f GB", chunks.count, Double(MatchVideo.bytes(chunks)) / 1e9)).font(.caption).foregroundStyle(.secondary)
                    if match.recording == true { Text("Запис не завершено (застосунок закрили під час гри) — збережене до того моменту доступне").font(.caption).foregroundStyle(.yellow) }
                }
            }
            if !clips.isEmpty {
                Section("Хайлайти") {
                    ForEach(clips, id: \.self) { u in
                        HStack {
                            Text(u.deletingPathExtension().lastPathComponent).font(.footnote)
                            Spacer()
                            Button { clip = u } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless)
                            ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            if let w = match.watchURL, let u = URL(string: w), w.hasPrefix("http") { Section("Трансляція") { Link(w, destination: u) } }
        }
        .navigationTitle(match.date.formatted(date: .abbreviated, time: .shortened))
        .sheet(isPresented: $showPlayer) { if let p = player { VideoPlayer(player: p).ignoresSafeArea().onAppear { p.play() } } }
        .sheet(item: $clip) { u in VideoPlayer(player: AVPlayer(url: u)).ignoresSafeArea() }
    }
}
