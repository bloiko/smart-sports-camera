import Foundation

/// Матчі на цьому телефоні (екран 4 «Мої матчі»). Кожен матч — своя папка Documents/matches/match_<дата-час>/
/// з chunks/ (широкий запис 4K) і highlights/ (кліпи): новий старт ніколи не перезаписує попередні записи
/// (раніше всі матчі писали в Documents/chunks з номерами від 001 і затирали один одного).
struct MatchRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var watchURL: String?
    var durationS: Double
    var chunkFiles: [String]            // у <folder>/chunks (старі записи без folder — у Documents/chunks)
    var clipFiles: [String]             // у <folder>/highlights
    var goals: Int
    var knownPitch: Bool
    var folder: String? = nil           // назва папки матчу в Documents/matches
    var recording: Bool? = nil          // true, поки йде запис (видно навіть після збою застосунку)
}

enum MatchStore {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var url: URL { docs.appendingPathComponent("matches.json") }
    static func load() -> [MatchRecord] { (try? JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: url))) ?? [] }
    static func save(_ all: [MatchRecord]) { try? JSONEncoder().encode(all).write(to: url) }
    static func add(_ m: MatchRecord) { var all = load(); all.insert(m, at: 0); save(all) }
    /// Додати або оновити за id (запис створюється на старті матчу і доповнюється після Стоп).
    static func upsert(_ m: MatchRecord) {
        var all = load()
        if let i = all.firstIndex(where: { $0.id == m.id }) { all[i] = m } else { all.insert(m, at: 0) }
        save(all)
    }

    /// Папка матчу за часом старту: той самий час (відновлення ефіру після збою) — та сама папка.
    static func folderName(for start: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"; f.locale = Locale(identifier: "en_US_POSIX")
        return "match_" + f.string(from: start)
    }
    static func folderURL(_ name: String) -> URL { docs.appendingPathComponent("matches").appendingPathComponent(name) }
    static func chunksDir(_ m: MatchRecord) -> URL { m.folder.map { folderURL($0).appendingPathComponent("chunks") } ?? docs.appendingPathComponent("chunks") }
    static func highlightsDir(_ m: MatchRecord) -> URL { m.folder.map { folderURL($0).appendingPathComponent("highlights") } ?? docs.appendingPathComponent("highlights") }

    /// Файли широкого запису матчу по порядку (з диска, а не зі списку: після збою список міг не оновитись).
    static func chunks(_ m: MatchRecord) -> [URL] {
        let dir = chunksDir(m)
        let all = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "mp4" }
        let mine = m.folder == nil ? all.filter { m.chunkFiles.contains($0.lastPathComponent) } : all
        return mine.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Видалити широкий запис матчу (кліпи й посилання лишаються) — звільняє ~15–20 GB за 90 хв.
    static func deleteRecording(_ m: MatchRecord) {
        for u in chunks(m) { try? FileManager.default.removeItem(at: u) }
        var all = load(); if let i = all.firstIndex(where: { $0.id == m.id }) { all[i].chunkFiles = [] }; save(all)
    }

    /// Видалити матч цілком: папку (запис 4K і кліпи) і рядок у списку. Старі матчі без папки — лише їхні файли.
    static func delete(_ m: MatchRecord) {
        if let f = m.folder { try? FileManager.default.removeItem(at: folderURL(f)) }
        else {
            for u in chunks(m) { try? FileManager.default.removeItem(at: u) }
            for c in m.clipFiles { try? FileManager.default.removeItem(at: highlightsDir(m).appendingPathComponent(c)) }
        }
        save(load().filter { $0.id != m.id })
    }

    static func freeGB() -> Double {
        Double((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64) ?? 0) / 1e9
    }
}
