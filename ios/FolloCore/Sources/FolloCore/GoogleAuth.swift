import Foundation
import CryptoKit

/// Own Google sign-in for an installed app: OAuth 2.0 authorization code with PKCE (RFC 7636), no Google SDK
/// (owner's rule "everything own"). The app opens `authorizationURL` in the system web sheet
/// (ASWebAuthenticationSession), gets the code back on the reversed-client-ID scheme and calls `exchange`; later
/// `accessToken()` refreshes silently. Endpoints can point at `src/fake_youtube.py` for tests.
public struct GoogleAuth: Sendable {
    public struct Tokens: Codable, Equatable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date
        public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
            self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
        }
    }
    /// One sign-in attempt: open `url`, then pass the returned code and this `verifier` to `exchange`.
    public struct Attempt: Sendable { public let url: URL; public let verifier: String; public let state: String }

    public let clientId: String
    public var authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public var tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    /// Creating and ending broadcasts and changing their visibility needs this scope.
    public var scope = "https://www.googleapis.com/auth/youtube.force-ssl"

    public init(clientId: String) { self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// iOS clients redirect to the reversed client ID: "com.googleusercontent.apps.123-abc:/oauthredirect".
    public var callbackScheme: String { clientId.split(separator: ".").reversed().joined(separator: ".") }
    public var redirectURI: String { callbackScheme + ":/oauthredirect" }

    public func begin() -> Attempt {
        let verifier = Self.randomURLSafe(48), state = Self.randomURLSafe(16)
        var c = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: Self.challenge(verifier)), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return Attempt(url: c.url!, verifier: verifier, state: state)
    }

    /// The code from the callback URL; nil if the state does not match (a stale or foreign callback) or the user said no.
    public func code(from callback: URL, attempt: Attempt) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        if let e = v("error") { throw AuthError.denied(e) }
        guard v("state") == attempt.state, let code = v("code") else { throw AuthError.badCallback }
        return code
    }

    public func exchange(code: String, verifier: String) async throws -> Tokens {
        try await token(["code": code, "client_id": clientId, "redirect_uri": redirectURI,
                         "grant_type": "authorization_code", "code_verifier": verifier], keep: nil)
    }

    public func refresh(_ refreshToken: String) async throws -> Tokens {
        try await token(["refresh_token": refreshToken, "client_id": clientId, "grant_type": "refresh_token"], keep: refreshToken)
    }

    public enum AuthError: Error, LocalizedError {
        case denied(String), badCallback, http(Int, String), signedOut
        public var errorDescription: String? {
            switch self {
            case .denied(let e): return "Google: вхід скасовано (\(e))"
            case .badCallback: return "Google: неочікувана відповідь входу"
            case .http(let c, let b): return "Google \(c): \(b.prefix(200))"
            case .signedOut: return "Google: потрібно увійти знову"
            }
        }
    }

    private func token(_ form: [String: String], keep: String?) async throws -> Tokens {
        var r = URLRequest(url: tokenEndpoint); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = form.map { "\($0.key)=\(Self.formEscape($0.value))" }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // invalid_grant: the refresh token was revoked or expired (7 days while the Google project is in Testing)
        if code == 400, String(data: data, encoding: .utf8)?.contains("invalid_grant") == true { throw AuthError.signedOut }
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let at = j["access_token"] as? String else {
            throw AuthError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let exp = (j["expires_in"] as? Double) ?? 3600
        return Tokens(accessToken: at, refreshToken: (j["refresh_token"] as? String) ?? keep, expiresAt: Date().addingTimeInterval(exp - 60))
    }

    static func challenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func randomURLSafe(_ bytes: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return base64url(Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &g) }))
    }
    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func formEscape(_ s: String) -> String {
        var ok = CharacterSet.alphanumerics; ok.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: ok) ?? s
    }
}
