import SwiftUI

/// Екран 4 «Мої матчі»: список матчів, кнопка нового матчу, вільне місце, видалення широкого запису.
struct MyMatchesView: View {
    @State var matches = MatchStore.load()
    @State var newMatch = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { newMatch = true } label: {
                        HStack { Image(systemName: "record.circle.fill").foregroundStyle(.red); Text("Новий матч").font(.system(size: 20, weight: .heavy, design: .rounded)) }
                    }
                    Text(String(format: "Вільно %.0f GB (90 хв 4K ≈ 15 GB)", MatchStore.freeGB())).font(.caption).foregroundStyle(MatchStore.freeGB() < 15 ? .yellow : .secondary)
                }
                Section(matches.isEmpty ? "Ще немає матчів" : "Матчі") {
                    ForEach(matches) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                if m.knownPitch { Image(systemName: "mappin.circle").foregroundStyle(.secondary) }
                                Spacer(); Text(fmt(m.durationS)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Label("\(m.clipFiles.count) кліпів", systemImage: "film"); Label("\(m.goals)", systemImage: "soccerball")
                                if !m.chunkFiles.isEmpty { Label("4K на телефоні", systemImage: "internaldrive") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if let w = m.watchURL { Link(w, destination: URL(string: w)!).font(.caption) }
                        }
                        .swipeActions {
                            if !m.chunkFiles.isEmpty { Button("Видалити 4K", role: .destructive) { MatchStore.deleteRecording(m); matches = MatchStore.load() } }
                        }
                    }
                }
            }
            .navigationTitle("Follo")
            .fullScreenCover(isPresented: $newMatch, onDismiss: { matches = MatchStore.load() }) { SetupView() }
        }
    }
    func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
