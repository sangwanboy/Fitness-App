import Foundation

/// Typed errors for all gateway traffic. Decodes the gateway's error
/// envelope — `{"error":{"code","message","retryAfterMs"?}}` — into cases
/// the UI can present honestly (rate limit vs quota vs sign-in vs server).
public enum GatewayError: LocalizedError {
    /// No base URL is configured (release build before the prod deploy,
    /// or a cleared override).
    case notConfigured
    /// No stored session — the user has never signed in (or signed out).
    case notSignedIn
    /// Session is dead: refresh was rejected, full sign-in required.
    case unauthorized
    /// Per-user rate limit (429, code "rate_limited").
    case rateLimited(retryAfterMs: Int?)
    /// Usage quota exhausted (429, code "quota_exceeded").
    case quotaExceeded(retryAfterMs: Int?)
    /// The account isn't allowed this capability (403).
    case forbiddenCapability
    /// The gateway itself is missing its GCP credentials (503) — a server
    /// deployment gap, not a client bug.
    case upstreamNotConfigured
    /// Vertex behind the gateway errored (502).
    case upstreamError(String)
    /// The gateway rejected the request shape (400).
    case badRequest(String)
    /// Any other non-2xx.
    case http(Int, String)
    /// Transport-level failure (no HTTP response at all).
    case network(underlying: Error)

    /// Decode from an HTTP status + response body using the gateway's
    /// `{error:{...}}` envelope. Falls back to `.http` when the body
    /// doesn't match the envelope.
    init(status: Int, data: Data) {
        let envelope = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let code = envelope?["code"] as? String ?? ""
        let message = envelope?["message"] as? String
            ?? String(decoding: data.prefix(200), as: UTF8.self)
        let retryAfterMs = envelope?["retryAfterMs"] as? Int

        switch code {
        case "unauthorized":             self = .unauthorized
        case "forbidden_capability":     self = .forbiddenCapability
        case "rate_limited":             self = .rateLimited(retryAfterMs: retryAfterMs)
        case "quota_exceeded":           self = .quotaExceeded(retryAfterMs: retryAfterMs)
        case "upstream_error":           self = .upstreamError(message)
        case "upstream_not_configured":  self = .upstreamNotConfigured
        case "bad_request":              self = .badRequest(message)
        default:                         self = .http(status, message)
        }
    }

    /// Short, honest, user-facing message per case.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "The AI backend isn't configured yet. Set a gateway URL in Settings → Astra AI backend."
        case .notSignedIn:
            return "Sign in to use Astra (Settings → Astra AI backend)."
        case .unauthorized:
            return "Your Astra session expired — please sign in again."
        case .rateLimited(let ms):
            if let s = Self.seconds(ms) {
                return "Astra is catching its breath — try again in ~\(s)s."
            }
            return "Astra is catching its breath — try again in a moment."
        case .quotaExceeded(let ms):
            if let s = Self.seconds(ms) {
                return "You've reached your AI usage limit — resets in ~\(s)s."
            }
            return "You've reached your AI usage limit for now. Try again later."
        case .forbiddenCapability:
            return "Your account isn't enabled for this AI feature."
        case .upstreamNotConfigured:
            return "The AI server isn't fully configured yet."
        case .upstreamError:
            return "The AI service hit an upstream error. Try again."
        case .badRequest:
            return "The AI server rejected the request. Try again — if it persists, update the app."
        case .http(let code, _):
            return "AI server error (\(code)). Try again."
        case .network:
            return "Couldn't reach the AI server. Check your connection and the gateway URL."
        }
    }

    public var errorDescription: String? { userMessage }

    /// Round retryAfterMs up to whole seconds for display.
    private static func seconds(_ ms: Int?) -> Int? {
        guard let ms, ms > 0 else { return nil }
        return max(1, Int((Double(ms) / 1000).rounded(.up)))
    }
}
