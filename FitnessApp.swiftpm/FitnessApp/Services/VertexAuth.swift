import Foundation
import Security

public class VertexAuth {
    public static let shared = VertexAuth()

    /// Guards the cached-token fields below — getAccessToken is hit
    /// concurrently from chat, vision, and prediction services. Never held
    /// across an await.
    private let cacheLock = NSLock()
    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var cachedClientEmail: String?  // invalidate cache if user pastes a different key

    private init() {}

    public func getAccessToken() async throws -> String {
        let (sa, _) = try VertexConfig.current()
        cacheLock.lock()
        let cached: String? = {
            guard let token = cachedToken,
                  let expiry = tokenExpiry,
                  expiry > Date(),
                  cachedClientEmail == sa.clientEmail else { return nil }
            return token
        }()
        cacheLock.unlock()
        if let cached { return cached }
        return try await refreshAccessToken(sa)
    }

    /// Clears the cached OAuth token. Call after the user pastes a new key.
    public func invalidateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedToken = nil
        tokenExpiry = nil
        cachedClientEmail = nil
    }

    private func refreshAccessToken(_ sa: VertexConfig.ServiceAccount) async throws -> String {
        let jwt = try createJWT(clientEmail: sa.clientEmail, tokenUri: sa.tokenUri, privateKeyPEM: sa.privateKey)
        
        guard let tokenURL = URL(string: sa.tokenUri) else {
            throw NSError(domain: "VertexAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid token_uri in service account: \(sa.tokenUri)"])
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (tokenData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: tokenData, encoding: .utf8) ?? "Unknown token exchange error"
            throw NSError(domain: "VertexAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(errorMsg)"])
        }
        
        struct TokenResponse: Codable {
            let accessToken: String
            let expiresIn: Int
            
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: tokenData)
        
        cacheLock.lock()
        self.cachedToken = tokenResponse.accessToken
        self.tokenExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn - 60))
        self.cachedClientEmail = sa.clientEmail
        cacheLock.unlock()

        return tokenResponse.accessToken
    }
    
    private func createJWT(clientEmail: String, tokenUri: String, privateKeyPEM: String) throws -> String {
        // Construct header
        let header = ["alg": "RS256", "typ": "JWT"]
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let headerBase64 = headerData.base64UrlEncodedString()
        
        // Construct claims
        let iat = Int(Date().timeIntervalSince1970)
        let exp = iat + 3600
        let claims: [String: Any] = [
            "iss": clientEmail,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud": tokenUri,
            "iat": iat,
            "exp": exp
        ]
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        let claimsBase64 = claimsData.base64UrlEncodedString()
        
        let signingInput = "\(headerBase64).\(claimsBase64)"
        guard let signingInputData = signingInput.data(using: .utf8) else {
            throw NSError(domain: "VertexAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to construct JWT signing input."])
        }
        
        // Load the key and sign
        let secKey = try loadPrivateKey(pem: privateKeyPEM)
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInputData as CFData,
            &error
        ) else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown signing error"
            throw NSError(domain: "VertexAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "RSA-SHA256 signature generation failed: \(errorDesc)"])
        }
        
        let signatureBase64 = (signature as Data).base64UrlEncodedString()
        return "\(signingInput).\(signatureBase64)"
    }
    
    private func loadPrivateKey(pem: String) throws -> SecKey {
        // Service account JSONs may store the key with literal "\n" escape sequences
        // instead of real newlines (it's a JSON string field). Normalize first.
        let normalized = pem.replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let base64Body = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty &&
                   !trimmed.hasPrefix("-----BEGIN") &&
                   !trimmed.hasPrefix("-----END")
        }.joined()

        guard let derData = Data(base64Encoded: base64Body) else {
            throw NSError(domain: "VertexAuth", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Malformed base64 block in private key."])
        }

        // Google service-account keys are PKCS#8 ("-----BEGIN PRIVATE KEY-----").
        // SecKeyCreateWithData(kSecAttrKeyTypeRSA, .private) wants raw PKCS#1.
        // Strip the PKCS#8 wrapper to extract the inner RSAPrivateKey.
        let pkcs1Data: Data
        if normalized.contains("BEGIN RSA PRIVATE KEY") {
            pkcs1Data = derData  // already PKCS#1
        } else {
            pkcs1Data = try extractPKCS1RSAKey(fromPKCS8: derData)
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs1Data as CFData, attributes as CFDictionary, &error) else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Key import failed"
            throw NSError(domain: "VertexAuth", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create SecKey from DER data: \(errorDesc)"])
        }
        return secKey
    }

    /// Walk the PKCS#8 PrivateKeyInfo ASN.1 structure and return the inner OCTET STRING
    /// (which is the PKCS#1 RSAPrivateKey that SecKey wants).
    /// Structure:
    /// SEQUENCE { INTEGER version, SEQUENCE AlgorithmIdentifier, OCTET STRING privateKey }
    private func extractPKCS1RSAKey(fromPKCS8 data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var idx = 0

        func expect(_ tag: UInt8) throws {
            guard idx < bytes.count, bytes[idx] == tag else {
                throw NSError(domain: "VertexAuth", code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "Expected ASN.1 tag 0x\(String(tag, radix: 16)) at offset \(idx)"])
            }
            idx += 1
        }

        func readLength() throws -> Int {
            guard idx < bytes.count else {
                throw NSError(domain: "VertexAuth", code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading ASN.1 length"])
            }
            let first = bytes[idx]; idx += 1
            if first & 0x80 == 0 { return Int(first) }
            let n = Int(first & 0x7F)
            var len = 0
            for _ in 0..<n {
                guard idx < bytes.count else {
                    throw NSError(domain: "VertexAuth", code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF in ASN.1 length"])
                }
                len = (len << 8) | Int(bytes[idx])
                idx += 1
            }
            return len
        }

        // Outer SEQUENCE
        try expect(0x30)
        _ = try readLength()

        // INTEGER (version)
        try expect(0x02)
        let vLen = try readLength()
        idx += vLen

        // SEQUENCE (AlgorithmIdentifier)
        try expect(0x30)
        let algLen = try readLength()
        idx += algLen

        // OCTET STRING (private key bytes — PKCS#1 RSAPrivateKey)
        try expect(0x04)
        let octLen = try readLength()

        guard idx + octLen <= bytes.count else {
            throw NSError(domain: "VertexAuth", code: 422,
                userInfo: [NSLocalizedDescriptionKey: "PKCS#8 OCTET STRING length \(octLen) overruns buffer"])
        }
        return data.subdata(in: idx..<(idx + octLen))
    }
}

extension Data {
    func base64UrlEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
