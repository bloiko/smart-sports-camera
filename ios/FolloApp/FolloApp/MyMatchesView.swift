import SwiftUI

/// Екран 4 «Мої матчі»: список матчів, кнопка нового матчу, вільне місце, видалення широкого запису.
struct MyMatchesView: View {
    @State var matches = MatchStore.load()
    @State var newMatch = false
    @State var toDelete: MatchRecord?
    static var autostarted = false
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
                        NavigationLink { MatchDetailView(match: m) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                if m.knownPitch { Image(systemName: "mappin.circle").foregroundStyle(.secondary) }
                                Spacer(); Text(fmt(m.durationS)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Label("\(m.clipFiles.count) кліпів", systemImage: "film"); Label("\(m.goals)", systemImage: "soccerball")
                                if !MatchStore.chunks(m).isEmpty { Label("4K на телефоні", systemImage: "internaldrive") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if m.recording == true { Label("запис перервано", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.yellow) }
                        }
                        }
                        .accessibilityIdentifier("match")
                        .swipeActions {
                            Button("Видалити") { toDelete = m }.tint(.red)
                            if !MatchStore.chunks(m).isEmpty { Button("Лише 4K") { MatchStore.deleteRecording(m); matches = MatchStore.load() }.tint(.orange) }
                        }
                    }
                }
            }
            .navigationTitle("Follo")
            .confirmationDialog("Видалити матч \(toDelete?.date.formatted(date: .abbreviated, time: .shortened) ?? "")? Запис 4K і кліпи зникнуть з телефона (у «Фото» і на YouTube лишаться).",
                                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Видалити матч", role: .destructive) { if let m = toDelete { MatchStore.delete(m); matches = MatchStore.load() }; toDelete = nil }
            }
            .fullScreenCover(isPresented: $newMatch, onDismiss: { matches = MatchStore.load() }) { SetupView() }
            // тест з Mac: одразу екран камери, але лише раз на запуск (після «назад» список лишається відкритим)
            .onAppear { if CommandLine.arguments.contains("--autostart"), !Self.autostarted { Self.autostarted = true; newMatch = true } }
        }
    }
    func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
