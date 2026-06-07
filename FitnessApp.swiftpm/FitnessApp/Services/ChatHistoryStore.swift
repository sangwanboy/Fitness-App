import SwiftUI

/// Persistent archive of past Astra chat sessions. Singleton so the Coach view
/// (current conversation) and the history sheet read/write the same source.
/// Storage: a single JSON blob in UserDefaults — small payloads, infrequent
/// writes, no DB worth the complexity. Mirrors `AstraWidgetStore`'s pattern.
///
/// We deliberately do NOT persist `ChatMessage` directly: it carries large
/// per-turn baggage (image bytes, token usage, thought signatures) and a
/// `ToolCall` whose associated values aren't meaningful to replay. A past chat
/// only needs to be RE-DISPLAYED, so we store a compact `SessionMessage` (id,
/// role, text, createdAt, optional imageData) and convert to/from `ChatMessage`.
@MainActor
public final class ChatHistoryStore: ObservableObject {
    public static let shared = ChatHistoryStore()

    /// Hard cap so the archive doesn't grow unbounded. Oldest sessions are
    /// dropped first when this is exceeded.
    public static let maxSessions = 30

    private static let storageKey = "astra_chat_history_v1"

    @Published public private(set) var sessions: [ChatSession] = []

    private init() {
        load()
    }

    // MARK: - Public API

    /// Archive a finished conversation. No-op when there's nothing worth
    /// keeping (empty, or only the canned greeting with no user turn). Newest
    /// sessions sort first; the archive is capped to `maxSessions`.
    public func archive(messages: [ChatMessage]) {
        let persistable = messages.compactMap { SessionMessage(from: $0) }
        // Require at least one real user message — a lone greeting isn't a chat.
        guard persistable.contains(where: { $0.role == .user }) else { return }

        let title = Self.deriveTitle(from: persistable)
        let session = ChatSession(
            id: UUID(),
            title: title,
            createdAt: Date(),
            messages: persistable
        )
        sessions.insert(session, at: 0)
        if sessions.count > Self.maxSessions {
            sessions = Array(sessions.prefix(Self.maxSessions))
        }
        save()
    }

    public func delete(id: UUID) {
        let before = sessions.count
        sessions.removeAll { $0.id == id }
        if sessions.count < before { save() }
    }

    public func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        save()
    }

    public func session(id: UUID) -> ChatSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Title derivation

    /// First user message, trimmed to ~40 chars. Falls back to "New chat".
    private static func deriveTitle(from messages: [SessionMessage]) -> String {
        let firstUserText = messages
            .first { $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = firstUserText, !raw.isEmpty else { return "New chat" }
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= 40 { return oneLine }
        let clipped = oneLine.prefix(40).trimmingCharacters(in: .whitespaces)
        return clipped + "…"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Models

/// One archived conversation.
public struct ChatSession: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var messages: [SessionMessage]

    public init(id: UUID, title: String, createdAt: Date, messages: [SessionMessage]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }

    /// First model or user line for a one-line preview in the history list.
    /// Prefers the first model reply (Astra's answer); falls back to the
    /// opening user message.
    public var preview: String {
        let candidate = messages.first(where: { $0.role == .model && !$0.text.isEmpty })
            ?? messages.first(where: { !$0.text.isEmpty })
        guard let text = candidate?.text else { return "No messages" }
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 80 { return oneLine }
        return oneLine.prefix(80).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Compact, fully-Codable form of a chat message — enough to re-display a past
/// conversation. Tool cards are intentionally dropped on archive: when a
/// session is loaded back, any turn that was only a tool card is reduced to its
/// text (or skipped if it had none).
public struct SessionMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: ChatRole
    public var text: String
    public let createdAt: Date
    /// JPEG-encoded user attachment, preserved so past food/fitness photos
    /// still show on replay. nil for plain-text turns.
    public let imageData: Data?

    public init(id: UUID, role: ChatRole, text: String, createdAt: Date, imageData: Data?) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.imageData = imageData
    }

    /// Build from a live `ChatMessage`. Returns nil for turns that carry no
    /// re-displayable content (empty text, no image) — e.g. a bare tool-card
    /// placeholder or a stray empty model bubble.
    public init?(from message: ChatMessage) {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || message.imageData != nil else { return nil }
        self.id = message.id
        self.role = message.role
        self.text = message.text
        self.createdAt = message.timestamp
        self.imageData = message.imageData
    }

    /// Re-hydrate into a `ChatMessage` for read-only replay in the chat view.
    /// Past tool cards aren't restored — only the text/image survives.
    public func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            text: text,
            timestamp: createdAt,
            imageData: imageData
        )
    }
}
