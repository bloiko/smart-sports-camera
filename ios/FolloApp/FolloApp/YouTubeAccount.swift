import Foundation
import Combine
import AuthenticationServices
import Security
import UIKit
import FolloCore

/// The owner's YouTube account: own Google sign-in (FolloCore.GoogleAuth, no Google SDK) in the system web sheet,
/// tokens in the Keychain, and the YouTube API with them (stage 1 of docs/youtube-signin-and-ui-test-plan.md).
/// The client ID comes from `google_client_id.txt` in the app bundle (copied from the Mac's git-ignored `secrets/`);
/// without it sign-in is hidden and the debug paths (Studio key, own RTMP server) work as before.
@MainActor
final class YouTubeAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var signedIn = false
    @Published private(set) var channel: String?
    @Published var error: String?
    @Published private(set) var busy = false
    let auth: GoogleAuth?
    private var apiBase: URL?
    private var persist = true                       // false for the fake server in UI tests: never into the Keychain
    private var tokens: GoogleAuth.Tokens? { didSet { if persist { Keychain.save(tokens) }; signedIn = tokens?.refreshToken != nil } }
    private var session: ASWebAuthenticationSession?

    /// Test builds can never go public (owner: "для тестування я не хочу для всіх включати").
    static var allowPublic: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// The reusable YouTube stream (same key for every match), created on the first GO LIVE.
    var streamId: String? {
        get { UserDefaults.standard.string(forKey: "yt.streamId") }
        set { UserDefaults.standard.set(newValue, forKey: "yt.streamId") }
    }

    override init() {
        let id = Bundle.main.url(forResource: "google_client_id", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        var a = id.map { GoogleAuth(clientId: $0) }
        #if DEBUG
        // UI tests on the simulator: src/fake_youtube.py instead of Google, already signed in
        if let i = CommandLine.arguments.firstIndex(of: "--youtube-api"), i + 1 < CommandLine.arguments.count, let u = URL(string: CommandLine.arguments[i + 1]) {
            var f = GoogleAuth(clientId: "123-test.apps.googleusercontent.com")
            f.authEndpoint = u.appendingPathComponent("auth"); f.tokenEndpoint = u.appendingPathComponent("token")
            a = f; apiBase = u.appendingPathComponent("youtube/v3/")
        }
        #endif
        auth = a
        super.init()
        #if DEBUG
        if apiBase != nil { persist = false; tokens = GoogleAuth.Tokens(accessToken: "", refreshToken: "test-refresh", expiresAt: .distantPast) }
        else { tokens = Keychain.load() }
        #else
        tokens = Keychain.load()
        #endif
        // didSet does not run for assignments inside the class's own init: set the flag by hand
        signedIn = tokens?.refreshToken != nil
        if signedIn { Task { await loadChannel() } }
    }

    func signIn() async {
        guard let auth, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        let attempt = auth.begin()
        do {
            let callback: URL = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: attempt.url, callbackURLScheme: auth.callbackScheme) { url, err in
                    if let url { cont.resume(returning: url) } else { cont.resume(throwing: err ?? GoogleAuth.AuthError.badCallback) }
                }
                s.presentationContextProvider = self
                session = s
                if !s.start() { cont.resume(throwing: GoogleAuth.AuthError.badCallback) }
            }
            let code = try auth.code(from: callback, attempt: attempt)
            tokens = try await auth.exchange(code: code, verifier: attempt.verifier)
            DebugLog.log("YouTube: signed in")
            await loadChannel()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            DebugLog.log("YouTube: sign-in cancelled")
        } catch {
            self.error = error.localizedDescription; DebugLog.log("YouTube: sign-in failed: \(error)")
        }
        session = nil
    }

    func signOut() { tokens = nil; channel = nil; streamId = nil; DebugLog.log("YouTube: signed out") }

    /// A valid access token, refreshed when it has expired. A revoked or expired sign-in signs out.
    func accessToken() async throws -> String {
        guard let auth, let t = tokens, let rt = t.refreshToken else { throw GoogleAuth.AuthError.signedOut }
        if t.expiresAt > Date(), !t.accessToken.isEmpty { return t.accessToken }
        do { let n = try await auth.refresh(rt); tokens = n; return n.accessToken }
        catch GoogleAuth.AuthError.signedOut { signOut(); throw GoogleAuth.AuthError.signedOut }
    }

    func api() -> YouTubeAPI {
        let a = YouTubeAPI(allowPublic: Self.allowPublic) { [weak self] in
            guard let self else { throw GoogleAuth.AuthError.signedOut }
            return try await self.accessToken()
        }
        if let b = apiBase { a.base = b }
        a.log = { s in DebugLog.log(s) }
        return a
    }

    private func loadChannel() async {
        do { channel = try await api().channelTitle() } catch { DebugLog.log("YouTube: channel: \(error.localizedDescription)") }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

/// Google tokens in the Keychain (this device only, readable after the first unlock so a restart mid-match works).
enum Keychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "follo.google", kSecAttrAccount as String: "tokens"]
    static func save(_ t: GoogleAuth.Tokens?) {
        SecItemDelete(query as CFDictionary)
        guard let t, let d = try? JSONEncoder().encode(t) else { return }
        var q = query; q[kSecValueData as String] = d; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load() -> GoogleAuth.Tokens? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleAuth.Tokens.self, from: d)
    }
}
