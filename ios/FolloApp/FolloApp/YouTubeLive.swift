import Foundation

/// YouTube Live API: створити трансляцію + стрім, зв'язати, отримати RTMPS-адресу і ключ.
/// Токен OAuth (scope youtube.force-ssl) передається ззовні: Google Sign-In SDK додається в проєкт
/// (SPM: https://github.com/google/GoogleSignIn-iOS) — див. ios/README.md.
struct LiveTarget { let broadcastId: String; let rtmpsURL: String; let streamKey: String; let watchURL: String }

enum YouTubeLive {
    /// Тестові збірки — private (бачить лише власник каналу, без сповіщень підписникам); реліз — unlisted.
    #if DEBUG
    static let defaultPrivacy = "private"
    #else
    static let defaultPrivacy = "unlisted"
    #endif

    static func createBroadcast(token: String, title: String, privacy: String = YouTubeLive.defaultPrivacy) async throws -> LiveTarget {
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(15))
        let b = try await post(token, "liveBroadcasts?part=snippet,status,contentDetails", [
            "snippet": ["title": title, "scheduledStartTime": start],
            "status": ["privacyStatus": privacy, "selfDeclaredMadeForKids": false],
            "contentDetails": ["enableAutoStart": true, "enableAutoStop": true, "latencyPreference": "low"]])
        let s = try await post(token, "liveStreams?part=snippet,cdn,contentDetails", [
            "snippet": ["title": title],
            "cdn": ["frameRate": "30fps", "ingestionType": "rtmp", "resolution": "1080p"],
            "contentDetails": ["isReusable": false]])
        let bid = b["id"] as! String, sid = s["id"] as! String
        _ = try await post(token, "liveBroadcasts/bind?part=id&id=\(bid)&streamId=\(sid)", [:])
        let ing = ((s["cdn"] as! [String: Any])["ingestionInfo"] as! [String: Any])
        return LiveTarget(broadcastId: bid, rtmpsURL: ing["rtmpsIngestionAddress"] as! String,
                          streamKey: ing["streamName"] as! String, watchURL: "https://youtu.be/\(bid)")
    }

    static func complete(token: String, broadcastId: String) async {
        _ = try? await post(token, "liveBroadcasts/transition?part=id&id=\(broadcastId)&broadcastStatus=complete", [:])
    }

    private static func post(_ token: String, _ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3/\(path)")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !body.isEmpty { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else {
            throw NSError(domain: "YouTube", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "error"])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
