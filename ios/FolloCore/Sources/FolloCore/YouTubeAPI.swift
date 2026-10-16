import Foundation

/// YouTube Live through the Data API v3 with our own sign-in (stage 1 of docs/youtube-signin-and-ui-test-plan.md).
/// - One reusable stream per channel: the stream key never changes and is never shown to the user.
/// - One broadcast per match, created **unlisted**, with auto start on and **auto stop off**, so a network drop does
///   not end it and the link stays the same; a restart of the app during the match reuses it.
/// - Public is refused unless `allowPublic` (release builds, after the owner confirms). Debug builds pass false.
public final class YouTubeAPI: @unchecked Sendable {
    public enum Privacy: String, Sendable, CaseIterable { case `private`, unlisted, `public` }
    public struct Stream: Codable, Equatable, Sendable { public var id: String; public var ingestURL: String; public var key: String }
    public struct Broadcast: Codable, Equatable, Sendable {
        public var id: String; public var privacy: String; public var lifeCycle: String
        public var watchURL: String { "https://youtu.be/\(id)" }
        /// A broadcast that can still carry this match (not ended, not removed).
        public var reusable: Bool { !["complete", "revoked"].contains(lifeCycle) }
    }
    public enum APIError: Error, LocalizedError {
        case publicNotAllowed, http(Int, String), shape(String)
        public var errorDescription: String? {
            switch self {
            case .publicNotAllowed: return "Тестова збірка не вмикає «Для всіх»"
            case .http(let c, let b): return "YouTube \(c): \(Self.reason(b))"
            case .shape(let s): return "YouTube: неочікувана відповідь (\(s))"
            }
        }
        /// The short reason from a Google error body ("liveStreamingNotEnabled", "quotaExceeded"…).
        static func reason(_ body: String) -> String {
            if let d = body.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let e = j["error"] as? [String: Any] {
                let r = ((e["errors"] as? [[String: Any]])?.first?["reason"] as? String) ?? ""
                return [r, e["message"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
            }
            return String(body.prefix(200))
        }
    }

    public var base = URL(string: "https://www.googleapis.com/youtube/v3/")!
    public let allowPublic: Bool
    private let token: @Sendable () async throws -> String
    /// Every call, for the debug log (method and path, no tokens).
    public var log: (@Sendable (String) -> Void)?

    public init(allowPublic: Bool, token: @escaping @Sendable () async throws -> String) {
        self.allowPublic = allowPublic; self.token = token
    }

    /// The channel the user signed in with (shown on the setup screen, so the owner sees the right channel).
    public func channelTitle() async throws -> String? {
        let j = try await call("GET", "channels?part=snippet&mine=true")
        return (((j["items"] as? [[String: Any]])?.first?["snippet"] as? [String: Any])?["title"] as? String)
    }

    /// Everything GO LIVE needs: the reusable stream (created once) and this match's broadcast. A broadcast saved
    /// from before a restart is reused while YouTube still has it open: same link for the viewers.
    public func prepare(streamId: String?, resumeBroadcastId: String?, title: String, privacy: Privacy) async throws -> (Broadcast, Stream) {
        let s = try await stream(reuse: streamId)
        if let id = resumeBroadcastId, let b = try await broadcast(id), b.reusable {
            log?("youtube: reuse broadcast \(id) (\(b.lifeCycle), \(b.privacy))"); return (b, s)
        }
        let b = try await createBroadcast(title: title, privacy: privacy)
        _ = try await call("POST", "liveBroadcasts/bind?part=id,contentDetails&id=\(b.id)&streamId=\(s.id)")
        return (b, s)
    }

    public func stream(reuse id: String?) async throws -> Stream {
        if let id {
            let j = try await call("GET", "liveStreams?part=id,cdn&id=\(id)")
            if let item = (j["items"] as? [[String: Any]])?.first, let s = Self.stream(item) { return s }
        }
        let j = try await call("POST", "liveStreams?part=snippet,cdn,contentDetails", [
            "snippet": ["title": "Follo"],
            "cdn": ["ingestionType": "rtmp", "resolution": "variable", "frameRate": "variable"],
            "contentDetails": ["isReusable": true]])
        guard let s = Self.stream(j) else { throw APIError.shape("liveStreams.insert") }
        return s
    }

    public func createBroadcast(title: String, privacy: Privacy) async throws -> Broadcast {
        if privacy == .public && !allowPublic { throw APIError.publicNotAllowed }
        let start = ISO8601DateFormatter().string(from: Date())
        let j = try await call("POST", "liveBroadcasts?part=snippet,status,contentDetails", [
            "snippet": ["title": title, "scheduledStartTime": start],
            "status": ["privacyStatus": privacy.rawValue, "selfDeclaredMadeForKids": false],
            "contentDetails": ["enableAutoStart": true, "enableAutoStop": false, "latencyPreference": "low", "enableDvr": true,
                               "monitorStream": ["enableMonitorStream": false]]])
        guard let b = Self.broadcast(j) else { throw APIError.shape("liveBroadcasts.insert") }
        return b
    }

    public func broadcast(_ id: String) async throws -> Broadcast? {
        let j = try await call("GET", "liveBroadcasts?part=id,status&id=\(id)")
        return ((j["items"] as? [[String: Any]])?.first).flatMap(Self.broadcast)
    }

    /// "Не для всіх" ⇄ "Для всіх" (release only) during the match; the link stays the same.
    public func setPrivacy(_ id: String, _ privacy: Privacy) async throws -> Broadcast {
        if privacy == .public && !allowPublic { throw APIError.publicNotAllowed }
        let j = try await call("PUT", "liveBroadcasts?part=status", [
            "id": id, "status": ["privacyStatus": privacy.rawValue, "selfDeclaredMadeForKids": false]])
        guard let b = Self.broadcast(j) else { throw APIError.shape("liveBroadcasts.update") }
        return b
    }

    /// STOP: end the broadcast (auto stop is off, so YouTube would otherwise keep waiting for data).
    public func complete(_ id: String) async throws {
        _ = try await call("POST", "liveBroadcasts/transition?part=id,status&broadcastStatus=complete&id=\(id)")
    }

    // ---------------------------------------------------------------- plumbing

    static func stream(_ j: [String: Any]) -> Stream? {
        guard let id = j["id"] as? String, let ing = (j["cdn"] as? [String: Any])?["ingestionInfo"] as? [String: Any],
              let url = (ing["rtmpsIngestionAddress"] as? String) ?? (ing["ingestionAddress"] as? String),
              let key = ing["streamName"] as? String else { return nil }
        return Stream(id: id, ingestURL: url, key: key)
    }
    static func broadcast(_ j: [String: Any]) -> Broadcast? {
        guard let id = j["id"] as? String else { return nil }
        let st = j["status"] as? [String: Any]
        return Broadcast(id: id, privacy: st?["privacyStatus"] as? String ?? "", lifeCycle: st?["lifeCycleStatus"] as? String ?? "")
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        r.httpMethod = method
        r.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        log?("youtube: \(method) \(path.split(separator: "?").first ?? "") → \(code)")
        guard (200..<300).contains(code) else { throw APIError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data.isEmpty ? [:] : ((try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }
}
