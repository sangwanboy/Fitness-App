import Foundation

/// Token accounting reported by Vertex in `usageMetadata` on the final
/// streaming chunk. `thoughts` is unique to reasoning-capable models
/// (gemini-3.5-flash and up) — non-thinking models leave it at 0.
public struct TokenUsage: Codable, Equatable {
    public let prompt: Int          // promptTokenCount — what we sent in
    public let output: Int          // candidatesTokenCount — visible model output
    public let thoughts: Int        // thoughtsTokenCount — internal reasoning
    public let total: Int           // totalTokenCount — sum (Vertex reports it)

    public init(prompt: Int, output: Int, thoughts: Int, total: Int) {
        self.prompt = prompt
        self.output = output
        self.thoughts = thoughts
        self.total = total
    }

    /// Parse from Vertex's `usageMetadata` block.
    public init?(usageMetadata: [String: Any]) {
        let p = (usageMetadata["promptTokenCount"]      as? Int) ?? 0
        let o = (usageMetadata["candidatesTokenCount"]  as? Int) ?? 0
        let t = (usageMetadata["thoughtsTokenCount"]    as? Int) ?? 0
        let tot = (usageMetadata["totalTokenCount"]     as? Int) ?? (p + o + t)
        // Skip empty blocks so we don't attach all-zero usage to errored turns.
        guard p + o + t + tot > 0 else { return nil }
        self.prompt = p
        self.output = o
        self.thoughts = t
        self.total = tot
    }
}

public struct ChatMessage: Identifiable, Codable {
    public let id: UUID
    public let role: ChatRole
    public var text: String
    public let timestamp: Date
    /// JPEG-encoded user attachment (food / fitness photo). nil for plain text msgs.
    public let imageData: Data?
    /// Tool call Astra emitted alongside this message (rendered as a card).
    public var toolCall: ToolCall?
    /// Lifecycle state of the attached tool call.
    public var toolStatus: ToolCall.Status?
    /// JSON-encoded structured payload returned by read tools (list_reminders,
    /// list_calendar_events). Merged into the `functionResponse` part when this
    /// message round-trips back to Gemini so the model can reason on the data.
    public var toolResultJSON: String?
    /// True when this bubble is a recoverable error placeholder — drives the
    /// Retry button in the chat UI. `ChatViewModel.retryLast()` finds the most
    /// recent error message and re-fires the appropriate request.
    public var isError: Bool
    /// Token accounting for this turn (attached when the Vertex stream
    /// finishes). nil while streaming or on errored turns.
    public var tokenUsage: TokenUsage?
    /// Gemini 3.x "thought signature" blob bound to the model's functionCall
    /// part on this turn. Required by Vertex to round-trip on every followup
    /// — calls without it are rejected with INVALID_ARGUMENT. Captured from
    /// the stream and re-emitted in the history serializer.
    public var thoughtSignature: String?

    public init(id: UUID = UUID(),
                role: ChatRole,
                text: String,
                timestamp: Date = Date(),
                imageData: Data? = nil,
                toolCall: ToolCall? = nil,
                toolStatus: ToolCall.Status? = nil,
                toolResultJSON: String? = nil,
                isError: Bool = false,
                tokenUsage: TokenUsage? = nil,
                thoughtSignature: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.imageData = imageData
        self.toolCall = toolCall
        self.toolStatus = toolStatus
        self.toolResultJSON = toolResultJSON
        self.isError = isError
        self.tokenUsage = tokenUsage
        self.thoughtSignature = thoughtSignature
    }
}

public enum ChatRole: String, Codable {
    case user
    case model
    
    public var apiRoleName: String {
        switch self {
        case .user: return "user"
        case .model: return "model"
        }
    }
}
