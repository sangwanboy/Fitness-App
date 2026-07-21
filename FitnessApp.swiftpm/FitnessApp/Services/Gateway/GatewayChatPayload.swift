import Foundation

/// Builders for the gateway's /v1/chat body. This is the single place that
/// knows the gateway's part shapes — which differ from raw Vertex in two
/// ways the server's zod schemas are STRICT about:
///
/// - Images are `{"image":{"mimeType","data"}}`, NOT Vertex's `inlineData`
///   (the server converts).
/// - `system` is a PLAIN STRING (the server builds Vertex's
///   systemInstruction), not `{parts:[{text}]}`.
/// - `thoughtSignature` rides as a PART-LEVEL SIBLING of `functionCall`,
///   only when non-empty, and ONLY on functionCall parts — never on
///   text/image parts (extra keys there 400).
///
/// Tools (functionDeclarations) and generationConfig (thinkingConfig,
/// responseMimeType, responseSchema, maxOutputTokens, …) pass through to
/// Gemini unchanged, so they stay `[String: Any]` exactly as the services
/// already build them.
enum GatewayChatPayload {

    // MARK: - Parts

    static func textPart(_ text: String) -> [String: Any] {
        ["text": text]
    }

    static func imagePart(data: Data, mimeType: String) -> [String: Any] {
        ["image": ["mimeType": mimeType, "data": data.base64EncodedString()]]
    }

    static func functionCallPart(name: String,
                                 args: [String: Any],
                                 thoughtSignature: String?) -> [String: Any] {
        var part: [String: Any] = [
            "functionCall": ["name": name, "args": args]
        ]
        if let sig = thoughtSignature, !sig.isEmpty {
            part["thoughtSignature"] = sig
        }
        return part
    }

    static func functionResponsePart(name: String,
                                     response: [String: Any]) -> [String: Any] {
        ["functionResponse": ["name": name, "response": response]]
    }

    // MARK: - Messages

    static func message(role: String, parts: [[String: Any]]) -> [String: Any] {
        ["role": role, "parts": parts]
    }

    // MARK: - Body

    /// Assemble the full /v1/chat body. `model` is always the logical name
    /// ("chat") — the server maps it to a concrete Gemini model. `system`
    /// is omitted when empty; `tools` when nil/empty.
    /// Extract the model's usable answer text from a NON-STREAMING /v1/chat
    /// response body. Gemini 3.x with thinking enabled can emit thought parts
    /// ("thought": true) or empty text parts carrying only a thoughtSignature
    /// BEFORE the real answer — naive `parts.first` extraction grabs those
    /// and downstream JSON parsing fails. Returns the LAST non-thought,
    /// non-empty text part + usageMetadata.
    static func responseText(fromBody data: Data) -> (text: String, usage: [String: Any]?)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let usable = parts.compactMap { part -> String? in
            guard (part["thought"] as? Bool) != true,
                  let t = part["text"] as? String,
                  !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return t
        }
        guard let text = usable.last else { return nil }
        return (text, obj["usageMetadata"] as? [String: Any])
    }

    /// Best-effort cleanup for strict-JSON responses: models occasionally
    /// wrap JSON in markdown fences despite responseMimeType.
    static func strippedJSONText(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        t = t.replacingOccurrences(of: "```json", with: "")
             .replacingOccurrences(of: "```", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func body(model: String = GatewayConfig.chatModel,
                     stream: Bool,
                     system: String,
                     messages: [[String: Any]],
                     tools: [[String: Any]]? = nil,
                     generationConfig: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages,
            "generationConfig": generationConfig
        ]
        if !system.isEmpty {
            body["system"] = system
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }
        return body
    }
}
