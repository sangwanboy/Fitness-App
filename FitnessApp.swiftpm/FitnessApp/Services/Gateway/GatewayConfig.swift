import Foundation

/// Central configuration for the Atlas AI Gateway — the backend that now
/// fronts all Gemini traffic. The app holds NO Google credentials; it
/// authenticates users against the gateway (Sign in with Apple in prod,
/// a fake-auth dev flow in DEBUG) and calls a Gemini-shaped proxy.
public enum GatewayConfig {
    /// Logical model name the gateway maps to a concrete Gemini model
    /// server-side. The app never names "gemini-*" — model upgrades are a
    /// server concern and don't require an app release.
    public static let chatModel = "chat"

    /// UserDefaults key for the user-editable base-URL override
    /// (Settings → Astra AI backend).
    public static let baseURLDefaultsKey = "gateway_base_url"

    /// Effective gateway base URL. Resolution order:
    /// 1. UserDefaults override, when it parses as a valid URL.
    /// 2. DEBUG default — the Mac's LAN IP so the phone can reach the local
    ///    dev gateway (editable in Settings → Astra AI backend). From the
    ///    simulator, set the override to http://localhost:8787.
    /// 3. Release: nil — no production URL exists yet (it lands after the
    ///    gateway's azd deploy). Callers surface an honest
    ///    "AI backend not configured" error instead of guessing.
    public static var baseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: baseURLDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw),
           url.scheme != nil, url.host != nil {
            return url
        }
        #if DEBUG
        // Mac LAN IP for on-device dev testing against the local gateway.
        return URL(string: "http://10.130.154.45:8787")
        #else
        return nil
        #endif
    }

    /// Build an absolute URL for a gateway path like "v1/chat".
    /// nil when no base URL is configured.
    public static func url(for path: String) -> URL? {
        guard let base = baseURL else { return nil }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(trimmed)
    }
}
