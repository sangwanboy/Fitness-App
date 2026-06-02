import Foundation

// Centralizes service-account loading. User-pasted JSON in UserDefaults takes
// precedence over the bundled vertex-service-account.json. Both VertexAuth and
// VertexGeminiClient call this so they always agree on the credentials in use.
public enum VertexConfig {
    public static let userDefaultsKey = "vertex_service_account_json"
    public static let bundledResource = "vertex-service-account"

    public struct ServiceAccount: Codable {
        public let projectId: String
        public let clientEmail: String
        public let privateKey: String
        public let tokenUri: String

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case clientEmail = "client_email"
            case privateKey = "private_key"
            case tokenUri = "token_uri"
        }
    }

    public enum Source { case userPasted, bundled, none }

    /// Returns parsed service account + which source it came from.
    /// Pasted JSON wins; bundled is the fallback.
    public static func current() throws -> (ServiceAccount, Source) {
        if let pasted = UserDefaults.standard.string(forKey: userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pasted.isEmpty,
           let data = pasted.data(using: .utf8) {
            do {
                let sa = try JSONDecoder().decode(ServiceAccount.self, from: data)
                return (sa, .userPasted)
            } catch {
                // Pasted JSON is malformed; bubble that up so the user can see it
                throw NSError(domain: "VertexConfig", code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "Pasted service account JSON is malformed: \(error.localizedDescription)"])
            }
        }

        if let url = Bundle.main.url(forResource: bundledResource, withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            let sa = try JSONDecoder().decode(ServiceAccount.self, from: data)
            return (sa, .bundled)
        }

        throw NSError(domain: "VertexConfig", code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No service account configured. Paste a JSON key in Settings → AI Coach."])
    }

    public static func setPastedJSON(_ json: String) {
        UserDefaults.standard.set(json, forKey: userDefaultsKey)
    }

    public static func clearPastedJSON() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    public static var hasPastedJSON: Bool {
        let v = UserDefaults.standard.string(forKey: userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return v?.isEmpty == false
    }
}
