import Foundation
import AVFoundation
import UIKit

/// Стан ефіру, що переживає крах: broadcastId, ключ, час старту зберігаються в UserDefaults (пункт 3 «Відновити ефір?»).
/// Нагрів і батарея (пункти 4, 6); перевірки перед стартом (пункт 7).
@MainActor
final class LiveSession: ObservableObject {
    struct Saved: Codable { var broadcastId: String; var rtmpsURL: String; var streamKey: String; var watchURL: String; var startedAt: Date }
    @Published var saved: Saved? = Self.load()
    @Published var warning: String?
    let streamer = Streamer()

    static func load() -> Saved? {
        guard let d = UserDefaults.standard.data(forKey: "live.saved") else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: d)
    }
    func save(_ s: Saved?) { saved = s; UserDefaults.standard.set(s.flatMap { try? JSONEncoder().encode($0) }, forKey: "live.saved") }

    /// Пункт 7: перевірки перед Go live. Повертає список проблем (порожній = можна).
    func preflight(minutes: Double = 90) -> [String] {
        var out: [String] = []
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64) ?? 0
        let needGB = minutes / 90 * 15
        if Double(free) / 1e9 < needGB { out.append(String(format: "Мало місця: потрібно ~%.0f GB, вільно %.0f GB", needGB, Double(free) / 1e9)) }
        UIDevice.current.isBatteryMonitoringEnabled = true
        if UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel < 0.5 && UIDevice.current.batteryState == .unplugged { out.append("Батарея \(Int(UIDevice.current.batteryLevel * 100))%: підключи павербанк") }
        if ProcessInfo.processInfo.thermalState.rawValue >= 2 { out.append("Телефон уже гарячий: постав у тінь") }
        return out
    }

    /// Пункти 4 і 6: реакція на нагрів і батарею під час ефіру. Викликати раз на кілька секунд.
    func tick(onFrameRate: (Double) -> Void, onDetectEvery: (Int) -> Void, onEnd: () -> Void) {
        let t = ProcessInfo.processInfo.thermalState
        switch t {
        case .nominal, .fair: onFrameRate(30); onDetectEvery(2); warning = nil
        case .serious: onFrameRate(25); streamer.bitrateKbps > 3000 ? streamer.stepBitrateDown() : (); onDetectEvery(3); warning = "Гаряче: знизив fps, стрім іде"
        case .critical: onFrameRate(25); onDetectEvery(4); warning = "Дуже гаряче: постав телефон у тінь"
        @unknown default: break
        }
        let b = UIDevice.current.batteryLevel
        if b >= 0 && UIDevice.current.batteryState == .unplugged {
            if b <= 0.05 { onEnd() }
            else if b <= 0.2 { warning = "Батарея \(Int(b * 100))%: підключи павербанк" }
        }
    }
}
