import Foundation

/// POST /v1/feedback — user feedback about Astra. Authenticated; the body
/// must contain at least one of rating / thumb / non-empty text, and absent
/// fields are OMITTED entirely (the gateway's zod schema treats them as
/// optional, NOT nullable — sending null 400s).
public enum FeedbackService {

    public enum Thumb: String, CaseIterable {
        case up, down
    }

    /// Send feedback. Throws `GatewayError` (including `.notSignedIn` when
    /// there's no session). Field limits mirror the server schema:
    /// text ≤ 4000, tag ≤ 64, appVersion ≤ 32.
    public static func send(rating: Int? = nil,
                            thumb: Thumb? = nil,
                            text: String? = nil,
                            tag: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let rating {
            body["rating"] = min(max(rating, 1), 5)
        }
        if let thumb {
            body["thumb"] = thumb.rawValue
        }
        if let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            body["text"] = String(trimmed.prefix(4000))
        }
        if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            body["tag"] = String(tag.prefix(64))
        }
        // Server requires at least one of rating / thumb / non-empty text.
        guard body["rating"] != nil || body["thumb"] != nil || body["text"] != nil else {
            throw GatewayError.badRequest("Add a rating, thumbs, or some text first.")
        }
        body["appVersion"] = appVersion

        _ = try await GatewayTransport.postJSON(path: "v1/feedback", body: body, timeout: 15)
    }

    /// "1.0 (248)" from the bundle, clamped to the server's 32-char cap.
    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return String("\(short) (\(build))".prefix(32))
    }
}
