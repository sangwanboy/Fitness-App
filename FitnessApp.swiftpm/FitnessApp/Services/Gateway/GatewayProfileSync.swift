import Foundation
import UIKit

/// Best-effort sync of the local profile (name, marketing opt-in, locale, app
/// version) to the gateway's `/v1/me` account record. The gateway endpoints
/// this talks to (`GET`/`POST /v1/me[/profile]`) may not be deployed yet, so
/// every failure is SILENT: it just flips `profile_sync_pending` and waits
/// for the next trigger (a fresh sign-in, the app coming to the foreground,
/// or an explicit profile edit) to retry. This must never block or surface
/// an error on sign-in/chat/profile editing — sync is a nice-to-have.
///
/// Plain class (nothing observes it) — a singleton the same shape as
/// `GatewayConfig`/`FeedbackService`, just stateful enough to need `init()`
/// to register its retry observers.
@MainActor
final class GatewayProfileSync {
    static let shared = GatewayProfileSync()

    /// AboutYouScreen/EditProfileSheet's shipped default — never worth
    /// syncing to the gateway as if it were a real name.
    private static let defaultAthleteName = "Alex Rivera"

    private init() {
        // Fresh sign-ins AND the pending-retry case both funnel through this
        // one notification — mirrors MorningBriefEngine's self-heal observer
        // (weak-self, main queue).
        NotificationCenter.default.addObserver(
            forName: .gatewaySessionEstablished, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }

        // Retry a pending sync (endpoint was down, network dropped, etc.)
        // the next time the app comes to the foreground — same trigger
        // NotificationManager.appDidBecomeActive uses for its own re-checks.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard UserDefaults.standard.bool(forKey: "profile_sync_pending") else { return }
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }
    }

    /// POST /v1/me/profile with whatever local profile state we have.
    /// Silently no-ops when signed out; silently marks `profile_sync_pending`
    /// on any failure instead of throwing.
    func syncNow() async {
        guard await GatewayAuth.shared.currentUserId != nil else { return }

        var body: [String: Any] = [:]
        let name = (UserDefaults.standard.string(forKey: "athlete_name") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != Self.defaultAthleteName {
            body["name"] = String(name.prefix(120))
        }
        // Consent is only OURS to send once the user has actually touched the
        // toggle on this install. Otherwise a fresh reinstall (local default
        // false) would silently clobber a server-side opt-in on the first
        // post-sign-in sync. Untouched installs hydrate FROM the server below.
        let consentTouched = UserDefaults.standard.bool(forKey: "marketing_opt_in_touched")
        if consentTouched {
            body["marketingOptIn"] = UserDefaults.standard.bool(forKey: "marketing_opt_in")
        }
        body["locale"] = String(Locale.current.identifier.prefix(32))
        body["appVersion"] = FeedbackService.appVersion

        do {
            let data = try await GatewayTransport.postJSON(path: "v1/me/profile", body: body, timeout: 30)
            UserDefaults.standard.set(false, forKey: "profile_sync_pending")
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Keeps Settings' Email row honest for accounts whose email only
                // exists server-side (e.g. synced from a different device).
                if let email = obj["email"] as? String {
                    UserDefaults.standard.set(email, forKey: "account_email")
                }
                // Mirror server consent into the local toggle until the user
                // touches it themselves — the server record is the durable one.
                if !consentTouched, let serverOptIn = obj["marketingOptIn"] as? Bool {
                    UserDefaults.standard.set(serverOptIn, forKey: "marketing_opt_in")
                }
            }
        } catch {
            UserDefaults.standard.set(true, forKey: "profile_sync_pending")
        }
    }

    /// GET /v1/me — the raw JSON object, or nil on any failure (signed out,
    /// network error, endpoint not deployed yet). No caller currently
    /// consumes this beyond what `syncNow()` already folds in from the
    /// POST response; exposed for future profile surfaces.
    static func fetchMe() async -> [String: Any]? {
        guard await GatewayAuth.shared.currentUserId != nil else { return nil }
        guard let data = try? await GatewayTransport.getJSON(path: "v1/me") else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
