import Foundation

/// Session manager for the Atlas AI Gateway. Owns the access/refresh token
/// pair (persisted in the Keychain, mirrored in memory) and exposes a
/// single-flight `validAccessToken()` for the transport layer.
///
/// Token lifecycle (gateway contract):
/// - Access tokens live `expiresInSec` (3600s); we refresh 60s early.
/// - Refresh tokens ROTATE on every use — both new tokens are persisted
///   before the refresh call returns.
/// - A 401 from /v1/auth/refresh means the session is dead: wipe it and
///   require a full sign-in.
public actor GatewayAuth {
    public static let shared = GatewayAuth()

    // MARK: - Keychain account keys
    private enum Key {
        static let access    = "gw_access_token"
        static let refresh   = "gw_refresh_token"
        static let userId    = "gw_user_id"
        static let expiresAt = "gw_expires_at"     // unix seconds
        static let devSub    = "gw_dev_sub"        // stable dev-flow subject
    }

    private struct Session {
        var accessToken: String
        var refreshToken: String
        var userId: String
        var expiresAt: Date
    }

    /// Wire shape of both /v1/auth/apple and /v1/auth/refresh responses.
    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresInSec: Double
        let userId: String
        let appId: String
    }

    private var session: Session?
    /// Single-flight refresh: concurrent callers await one shared Task
    /// instead of racing rotations (a lost rotation kills the session).
    private var refreshTask: Task<String, Error>?

    private init() {
        if let access = KeychainStore.string(for: Key.access),
           let refresh = KeychainStore.string(for: Key.refresh),
           let userId = KeychainStore.string(for: Key.userId) {
            let expiry = KeychainStore.string(for: Key.expiresAt)
                .flatMap(Double.init)
                .map(Date.init(timeIntervalSince1970:)) ?? .distantPast
            session = Session(accessToken: access, refreshToken: refresh,
                              userId: userId, expiresAt: expiry)
        }
    }

    // MARK: - Public state

    /// True when a persisted session exists. Nonisolated (reads the Keychain
    /// directly) so SwiftUI views can check it synchronously.
    public nonisolated var isSignedIn: Bool {
        KeychainStore.string(for: Key.refresh) != nil
    }

    /// The gateway user id of the stored session, if any. Nonisolated for
    /// synchronous display in Settings.
    public nonisolated var currentUserId: String? {
        KeychainStore.string(for: Key.userId)
    }

    // MARK: - Token access

    /// Returns a non-expired access token, refreshing when needed.
    /// Throws `.notSignedIn` when there is no session at all and
    /// `.unauthorized` when the session is dead (refresh rejected).
    public func validAccessToken() async throws -> String {
        guard let current = session else { throw GatewayError.notSignedIn }
        if current.expiresAt > Date() {
            return current.accessToken
        }
        return try await refresh()
    }

    /// Force-refresh the access token (also used by the transport layer on a
    /// 401 mid-flight). Single-flight; returns the new access token.
    @discardableResult
    public func refresh() async throws -> String {
        if let inflight = refreshTask {
            return try await inflight.value
        }
        let task = Task<String, Error> {
            guard let refreshToken = self.session?.refreshToken else {
                throw GatewayError.notSignedIn
            }
            do {
                let auth = try await Self.postAuth(path: "v1/auth/refresh",
                                                   body: ["refreshToken": refreshToken])
                self.store(auth)
                return auth.accessToken
            } catch GatewayError.unauthorized {
                // Refresh rejected → session dead. Wipe so the UI can show an
                // honest signed-out state; the user must sign in again.
                self.wipeSession()
                throw GatewayError.unauthorized
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Sign-in / out

    #if DEBUG
    /// Dev-only fake-auth flow: `{"fake":{"sub","bundleId"}}` against
    /// /v1/auth/apple. The `sub` is a UUID persisted in the Keychain so the
    /// gateway sees a stable dev identity across launches.
    public func signInDev() async throws {
        let sub: String = {
            if let existing = KeychainStore.string(for: Key.devSub) { return existing }
            let fresh = UUID().uuidString
            KeychainStore.set(fresh, for: Key.devSub)
            return fresh
        }()
        let bundleId = Bundle.main.bundleIdentifier ?? "com.tushar.fitnessapp"
        let auth = try await Self.postAuth(path: "v1/auth/apple",
                                           body: ["fake": ["sub": sub, "bundleId": bundleId]])
        store(auth)
    }
    #endif

    /// Production sign-in: exchange a Sign in with Apple identity token for a
    /// gateway session.
    public func signIn(appleIdentityToken: String) async throws {
        let auth = try await Self.postAuth(path: "v1/auth/apple",
                                           body: ["identityToken": appleIdentityToken])
        store(auth)
    }

    /// Drop the session locally (Keychain + memory).
    public func signOut() {
        wipeSession()
    }

    // MARK: - Internals

    /// Persist a fresh token pair ATOMICALLY relative to callers: memory and
    /// Keychain are both updated before this returns, so a rotated refresh
    /// token can never be lost between the response and the store.
    private func store(_ auth: AuthResponse) {
        let expiresAt = Date().addingTimeInterval(max(0, auth.expiresInSec - 60))
        session = Session(accessToken: auth.accessToken,
                          refreshToken: auth.refreshToken,
                          userId: auth.userId,
                          expiresAt: expiresAt)
        KeychainStore.set(auth.accessToken, for: Key.access)
        KeychainStore.set(auth.refreshToken, for: Key.refresh)
        KeychainStore.set(auth.userId, for: Key.userId)
        KeychainStore.set(String(expiresAt.timeIntervalSince1970), for: Key.expiresAt)
    }

    private func wipeSession() {
        session = nil
        KeychainStore.delete(Key.access)
        KeychainStore.delete(Key.refresh)
        KeychainStore.delete(Key.userId)
        KeychainStore.delete(Key.expiresAt)
        // Key.devSub survives on purpose — the dev identity stays stable
        // across sign-out/sign-in cycles.
    }

    /// POST to an UNauthenticated auth endpoint and decode the token
    /// response. 401 → `.unauthorized`; other non-2xx → envelope-decoded.
    private static func postAuth(path: String, body: [String: Any]) async throws -> AuthResponse {
        guard let url = GatewayConfig.url(for: path) else {
            throw GatewayError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GatewayError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.http(0, "No HTTP response from gateway.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GatewayError.unauthorized }
            throw GatewayError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            throw GatewayError.http(http.statusCode, "Could not decode auth response.")
        }
    }
}
