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
    /// 1. UserDefaults override, when it parses as a valid URL — set
    ///    Settings → Astra AI backend to http://<mac-ip>:8787 for the local
    ///    dev gateway (http://localhost:8787 from the simulator).
    /// 2. The production gateway on Azure (deployed 2026-07-20, TLS via
    ///    Caddy/Let's Encrypt — https satisfies ATS). Since 2026-07-21 this
    ///    is the default for Debug builds too: the local dev server is no
    ///    longer always-on, so out of the box every build talks to prod.
    public static var baseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: baseURLDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw),
           url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://atlas-gw-tushar.denmarkeast.cloudapp.azure.com")
    }

    /// True when the effective gateway is a local/LAN dev server (plain-http
    /// or a private/loopback host). Auth flows use this to decide between the
    /// gateway's fake dev-auth (local only) and real Sign in with Apple.
    public static var isLocalGateway: Bool {
        guard let url = baseURL, let host = url.host else { return false }
        if url.scheme == "http" { return true }
        if host == "localhost" || host.hasPrefix("127.") { return true }
        return host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.range(of: #"^172\.(1[6-9]|2\d|3[01])\."#, options: .regularExpression) != nil
    }

    /// Build an absolute URL for a gateway path like "v1/chat".
    /// nil when no base URL is configured.
    public static func url(for path: String) -> URL? {
        guard let base = baseURL else { return nil }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(trimmed)
    }
}
