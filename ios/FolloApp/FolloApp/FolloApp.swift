import SwiftUI

@main
struct FolloApp: App {
    @State var onboarded = UserDefaults.standard.bool(forKey: "onboarding.done") || CommandLine.arguments.contains("--autostart")

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--wipe-matches") { Self.wipeMatches() }
        #endif
    }

    #if DEBUG
    /// Debug (`--wipe-matches` from the Mac): delete recorded matches — 4K chunks, highlight clips, the match list — and
    /// write what was freed and the free space to Documents/debug/wipe.txt. Test video and pitch memory stay.
    static func wipeMatches() {
        let fm = FileManager.default, docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func size(_ u: URL) -> Int64 {
            guard let e = fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0) { $0 + Int64($1) }
        }
        var freed: Int64 = 0
        for name in ["chunks", "highlights"] { let u = docs.appendingPathComponent(name); freed += size(u); try? fm.removeItem(at: u) }
        let m = docs.appendingPathComponent("matches.json"); freed += Int64((try? m.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0); try? fm.removeItem(at: m)
        let free = (try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let text = String(format: "wiped matches: freed %.2f GB; free space now %.1f GB\n", Double(freed) / 1e9, Double(free ?? 0) / 1e9)
        try? fm.createDirectory(at: docs.appendingPathComponent("debug"), withIntermediateDirectories: true)
        try? text.write(to: docs.appendingPathComponent("debug/wipe.txt"), atomically: true, encoding: .utf8)
    }
    #endif
    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded { MyMatchesView() } else { OnboardingView { onboarded = true } }
            }.preferredColorScheme(.dark)
        }
    }
}
