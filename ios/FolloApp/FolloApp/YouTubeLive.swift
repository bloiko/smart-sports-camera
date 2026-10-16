import Foundation

/// Куди стрімити. З входом у YouTube ефір створює FolloCore.YouTubeAPI (YouTubeAccount); тут лишились debug-шляхи:
/// ключ зі Studio і свій RTMP-сервер (відкат, якщо API підведе).
struct LiveTarget { let broadcastId: String; let rtmpsURL: String; let streamKey: String; let watchURL: String }

enum YouTubeLive {
    /// Debug: ключ трансляції з YouTube Studio (Documents/debug/youtube_key.txt, копіюється з Mac secrets/youtube_key.txt)
    /// замість Google Sign-In + API. Приватність задається в Studio для стріму за замовчуванням.
    static func debugStreamKey() -> String? {
        #if DEBUG
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug/youtube_key.txt")
        let k = (try? String(contentsOf: u, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return k.isEmpty ? nil : k
        #else
        return nil
        #endif
    }
    static let studioIngest = "rtmps://a.rtmps.youtube.com:443/live2"

    /// Debug: stream to any RTMP server instead of YouTube, e.g. ffmpeg on the Mac in the same Wi-Fi
    /// (Documents/debug/rtmp_target.txt: "rtmp://192.168.1.20:1935/live test"). Release builds ignore the file.
    static func debugTarget() -> (url: String, key: String)? {
        #if DEBUG
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug/rtmp_target.txt")
        let p = ((try? String(contentsOf: u, encoding: .utf8)) ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        return p.count >= 2 ? (p[0], p[1]) : nil
        #else
        return nil
        #endif
    }
}
