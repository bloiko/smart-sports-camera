import SwiftUI
import AVFoundation

@main
struct FolloApp: App {
    @State var onboarded = UserDefaults.standard.bool(forKey: "onboarding.done") || CommandLine.arguments.contains("--autostart")

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--wipe-matches") { Self.wipeMatches() }
        #endif
        Self.watchSystemEvents()
    }

    /// Why iOS takes the app off the screen (found in a 90-min run: the app went to the background at 33 min with no
    /// visible cause). Every event goes to the debug log.
    static func watchSystemEvents() {
        let nc = NotificationCenter.default
        let named: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "app will resign active"),
            (UIApplication.didEnterBackgroundNotification, "app did enter background"),
            (UIApplication.willEnterForegroundNotification, "app will enter foreground"),
            (UIApplication.didBecomeActiveNotification, "app did become active"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "device LOCKED (protected data unavailable)"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "device unlocked"),
            (UIApplication.didReceiveMemoryWarningNotification, "MEMORY WARNING"),
            (UIApplication.userDidTakeScreenshotNotification, "screenshot taken"),
            (UIScreen.capturedDidChangeNotification, "screen capture changed")]
        for (n, text) in named { nc.addObserver(forName: n, object: nil, queue: nil) { _ in DebugLog.log("system: " + text) } }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .began ? "began" : "ended"
            let reason = n.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt ?? 0
            DebugLog.log("system: audio interruption \(type) reason \(reason) (call, Siri, alarm, other app audio)")
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
            DebugLog.log("system: thermal state \(ProcessInfo.processInfo.thermalState.rawValue)")
        }
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
