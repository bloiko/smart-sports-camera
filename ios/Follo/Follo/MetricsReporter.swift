import Foundation
import MetricKit
import SwiftUI

/// iOS reports through MetricKit (system framework): once a day the app receives why it was terminated in the
/// foreground and in the background (memory, watchdog, CPU, locked file, …), crashes, hangs and CPU/disk exceptions.
/// Saved as JSON to Documents/debug/metrickit/ and summarised in the log and on "Мої матчі"; each file can be shared
/// from the phone, no cable needed. Goal: explain the unexplained trips to the background in the 90-minute runs.
final class MetricsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsReporter()
    static let dir: URL = {
        let d = DebugLog.dir.appendingPathComponent("metrickit")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }()

    func start() {
        let m = MXMetricManager.shared
        m.add(self)
        // reports delivered while the app was not running
        save(metrics: m.pastPayloads); save(diagnostics: m.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) { save(metrics: payloads) }
    func didReceive(_ payloads: [MXDiagnosticPayload]) { save(diagnostics: payloads) }

    private func save(metrics: [MXMetricPayload]) {
        for p in metrics {
            write(p.jsonRepresentation(), name: "metrics", end: p.timeStampEnd)
            if let e = p.applicationExitMetrics { DebugLog.log("metrickit: " + Self.exits(e)) }
        }
    }
    private func save(diagnostics: [MXDiagnosticPayload]) {
        for p in diagnostics {
            write(p.jsonRepresentation(), name: "diagnostics", end: p.timeStampEnd)
            DebugLog.log("metrickit: crashes \(p.crashDiagnostics?.count ?? 0), hangs \(p.hangDiagnostics?.count ?? 0), cpu \(p.cpuExceptionDiagnostics?.count ?? 0), disk \(p.diskWriteExceptionDiagnostics?.count ?? 0)")
        }
    }
    private func write(_ d: Data, name: String, end: Date) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"
        try? d.write(to: Self.dir.appendingPathComponent("\(name)_\(f.string(from: end)).json"))
    }

    /// "background: memory 1, watchdog 0, …; foreground: …" — only the non-zero reasons.
    static func exits(_ e: MXAppExitMetric) -> String {
        let b = e.backgroundExitData, f = e.foregroundExitData
        let bg: [(String, Int)] = [("normal", b.cumulativeNormalAppExitCount), ("memory pressure", b.cumulativeMemoryPressureExitCount),
                                   ("memory limit", b.cumulativeMemoryResourceLimitExitCount), ("watchdog", b.cumulativeAppWatchdogExitCount),
                                   ("cpu limit", b.cumulativeCPUResourceLimitExitCount), ("locked file", b.cumulativeSuspendedWithLockedFileExitCount),
                                   ("background task timeout", b.cumulativeBackgroundTaskAssertionTimeoutExitCount),
                                   ("abnormal", b.cumulativeAbnormalExitCount), ("bad access", b.cumulativeBadAccessExitCount),
                                   ("illegal instruction", b.cumulativeIllegalInstructionExitCount)]
        let fg: [(String, Int)] = [("normal", f.cumulativeNormalAppExitCount), ("memory limit", f.cumulativeMemoryResourceLimitExitCount),
                                   ("watchdog", f.cumulativeAppWatchdogExitCount), ("abnormal", f.cumulativeAbnormalExitCount),
                                   ("bad access", f.cumulativeBadAccessExitCount), ("illegal instruction", f.cumulativeIllegalInstructionExitCount)]
        func j(_ a: [(String, Int)]) -> String { let n = a.filter { $0.1 > 0 }; return n.isEmpty ? "none" : n.map { "\($0.0) \($0.1)" }.joined(separator: ", ") }
        return "exits in background: \(j(bg)); in foreground: \(j(fg))"
    }

    static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// "Звіти iOS": the saved MetricKit files, newest first, each with Share (to Telegram, AirDrop, mail — no cable).
struct MetricsView: View {
    let files = MetricsReporter.files
    var body: some View {
        List {
            if files.isEmpty { Text("Ще немає. iOS надсилає звіт раз на добу, після першого дня роботи застосунку.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(files, id: \.self) { u in
                HStack {
                    Text(u.deletingPathExtension().lastPathComponent).font(.footnote)
                    Spacer(); ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }.navigationTitle("Звіти iOS")
    }
}
