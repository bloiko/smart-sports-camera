import Foundation
import UIKit

/// Debug-лог і кадр прев'ю у Documents/debug — Claude читає їх з Mac через `xcrun devicectl device copy from`
/// (див. docs/run-on-iphone.md). У релізі вимкнути: DebugLog.enabled = false.
enum DebugLog {
    static var enabled = true
    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }()
    private static let q = DispatchQueue(label: "follo.debuglog")
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    private static var lastPreview = Date.distantPast

    static func log(_ s: String) {
        guard enabled else { return }
        let line = "\(fmt.string(from: Date())) \(s)\n"
        q.async {
            let u = dir.appendingPathComponent("log.txt")
            if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
            else { try? line.write(to: u, atomically: true, encoding: .utf8) }
        }
    }

    static func preview(_ img: UIImage) {
        guard enabled, Date().timeIntervalSince(lastPreview) > 2 else { return }
        lastPreview = Date()
        q.async { try? img.jpegData(compressionQuality: 0.6)?.write(to: dir.appendingPathComponent("preview.jpg")) }
    }

    /// Резидентна пам'ять процесу, MB.
    static func memMB() -> Int {
        var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    static func reset() { try? FileManager.default.removeItem(at: dir.appendingPathComponent("log.txt")); log("app start \(UIDevice.current.systemVersion), build \(build)") }

    /// Which build runs on the phone: the time the app binary was built ("17.10 01:20"), shown in the log and on
    /// "Мої матчі" (the version number stays 1.0 (1) during development).
    static let build: String = {
        let d = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let f = DateFormatter(); f.dateFormat = "dd.MM HH:mm"
        return d.map { f.string(from: $0) } ?? "?"
    }()
}
