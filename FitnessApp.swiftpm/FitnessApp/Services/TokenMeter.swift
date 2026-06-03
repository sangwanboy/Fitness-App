import Foundation
import SwiftUI

/// Where a batch of Gemini tokens was spent. Drives the per-feature breakdown
/// in Settings → AI token usage.
public enum TokenSource: String, Codable, CaseIterable, Sendable {
    case coach        // Astra chat + tool follow-ups (VertexGeminiClient)
    case insights     // predictions: daily insight, action chips, anomalies, "Why?" sheet
    case foodVision   // photo → food recognition
    case other

    public var displayName: String {
        switch self {
        case .coach:      return "Coach chat"
        case .insights:   return "Insights & predictions"
        case .foodVision: return "Food photo scan"
        case .other:      return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .coach:      return "bubble.left.and.bubble.right.fill"
        case .insights:   return "sparkles"
        case .foodVision: return "camera.fill"
        case .other:      return "circle.dashed"
        }
    }

    public var tint: Color {
        switch self {
        case .coach:      return .indigo
        case .insights:   return .purple
        case .foodVision: return .orange
        case .other:      return .gray
        }
    }
}

/// Lifetime accounting of every Gemini API call the app makes, summed from the
/// `usageMetadata` block Vertex returns on each response (Gemini's own built-in
/// token report). Persisted across launches in UserDefaults. Single instance:
/// `TokenMeter.shared`.
///
/// Recording happens at the three points the app parses `usageMetadata`:
///   - `VertexGeminiClient` stream tail  → `.coach`
///   - `PredictionAIService` why-sheet + `callGeminiJSON` → `.insights`
///   - the food-vision recognizer → `.foodVision`
/// so coverage is total regardless of which UI consumes the result.
@MainActor
public final class TokenMeter: ObservableObject {
    public static let shared = TokenMeter()

    @Published public private(set) var prompt: Int = 0
    @Published public private(set) var output: Int = 0
    @Published public private(set) var thoughts: Int = 0
    @Published public private(set) var total: Int = 0
    @Published public private(set) var calls: Int = 0
    /// source.rawValue → total tokens spent through that source.
    @Published public private(set) var bySource: [String: Int] = [:]
    /// source.rawValue → number of calls through that source.
    @Published public private(set) var callsBySource: [String: Int] = [:]
    /// When counting began (first record after install, or last reset).
    @Published public private(set) var since: Date?

    private let key = "token_meter_v1"

    private init() { load() }

    /// Add one API call's usage to the running totals. Call from any context via
    /// `Task { @MainActor in TokenMeter.shared.record(usage, source: …) }`.
    public func record(_ usage: TokenUsage, source: TokenSource) {
        guard usage.total > 0 else { return }   // skip empty/errored turns
        prompt   += usage.prompt
        output   += usage.output
        thoughts += usage.thoughts
        total    += usage.total
        calls    += 1
        bySource[source.rawValue, default: 0]      += usage.total
        callsBySource[source.rawValue, default: 0] += 1
        if since == nil { since = Date() }
        save()
    }

    public func reset() {
        prompt = 0; output = 0; thoughts = 0; total = 0; calls = 0
        bySource = [:]; callsBySource = [:]
        since = Date()
        save()
    }

    /// Tokens spent through one source (0 if none).
    public func tokens(for source: TokenSource) -> Int { bySource[source.rawValue] ?? 0 }
    /// Calls made through one source (0 if none).
    public func callCount(for source: TokenSource) -> Int { callsBySource[source.rawValue] ?? 0 }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var prompt: Int; var output: Int; var thoughts: Int; var total: Int
        var calls: Int; var bySource: [String: Int]; var callsBySource: [String: Int]
        var since: Date?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        prompt = s.prompt; output = s.output; thoughts = s.thoughts; total = s.total
        calls = s.calls; bySource = s.bySource; callsBySource = s.callsBySource; since = s.since
    }

    private func save() {
        let s = Snapshot(prompt: prompt, output: output, thoughts: thoughts, total: total,
                         calls: calls, bySource: bySource, callsBySource: callsBySource, since: since)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Compact token formatting ("12.3K" / "1.2M") for chips and list rows.
public enum TokenFormat {
    public static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
