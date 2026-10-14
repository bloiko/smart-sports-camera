import Foundation

/// Матчі на цьому телефоні (екран 4 «Мої матчі»): дата, посилання YouTube, кліпи, тривалість. JSON у Documents.
struct MatchRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var watchURL: String?
    var durationS: Double
    var chunkFiles: [String]            // широкий запис 4K (Documents/chunks)
    var clipFiles: [String]             // Documents/highlights
    var goals: Int
    var knownPitch: Bool
}

enum MatchStore {
    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("matches.json") }
    static func load() -> [MatchRecord] { (try? JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: url))) ?? [] }
    static func save(_ all: [MatchRecord]) { try? JSONEncoder().encode(all).write(to: url) }
    static func add(_ m: MatchRecord) { var all = load(); all.insert(m, at: 0); save(all) }

    /// Видалити широкий запис матчу (кліпи й посилання лишаються) — звільняє ~15 GB за 90 хв.
    static func deleteRecording(_ m: MatchRecord) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chunks")
        for f in m.chunkFiles { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        var all = load(); if let i = all.firstIndex(where: { $0.id == m.id }) { all[i].chunkFiles = [] }; save(all)
    }

    static func freeGB() -> Double {
        Double((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64) ?? 0) / 1e9
    }
}
