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

/// Published per-1M-token pricing for **gemini-3.5-flash** (USD). The Gemini /
/// Vertex API only returns token *counts* in `usageMetadata` — never a dollar
/// cost — so cost is computed here from counts × these rates.
/// Source: Google pricing, gemini-3.5-flash (May 2026): input $1.50, output
/// $9.00 per 1M tokens. Thinking ("thoughts") tokens bill at the output rate.
/// These are list-price ESTIMATES — actual billing (caching, batch, taxes) can
/// differ. Update here if the model or rates change.
public enum GeminiPricing {
    public static let inputPerMillion: Double = 1.50
    public static let outputPerMillion: Double = 9.00
    public static let thinkingPerMillion: Double = 9.00   // thoughts billed as output

    public static func inputCost(_ t: Int) -> Double { Double(t) / 1_000_000 * inputPerMillion }
    public static func outputCost(_ t: Int) -> Double { Double(t) / 1_000_000 * outputPerMillion }
    public static func thinkingCost(_ t: Int) -> Double { Double(t) / 1_000_000 * thinkingPerMillion }
    public static func cost(prompt: Int, output: Int, thoughts: Int) -> Double {
        inputCost(prompt) + outputCost(output) + thinkingCost(thoughts)
    }

    /// "$0.00" / "$0.0042" / "$0.013" / "$1.27" — more precision for tiny sums.
    public static func formatUSD(_ v: Double) -> String {
        if v <= 0 { return "$0.00" }
        if v < 0.01 { return String(format: "$%.4f", v) }
        if v < 1    { return String(format: "$%.3f", v) }
        return String(format: "$%.2f", v)
    }
}

/// Lifetime accounting of every Gemini API call the app makes, summed from the
/// `usageMetadata` block Vertex returns on each response (Gemini's own built-in
/// token report). Persisted across launches in UserDefaults. Single instance:
/// `TokenMeter.shared`.
@MainActor
public final class TokenMeter: ObservableObject {
    public static let shared = TokenMeter()

    @Published public private(set) var prompt: Int = 0
    @Published public private(set) var output: Int = 0
    @Published public private(set) var thoughts: Int = 0
    @Published public private(set) var total: Int = 0
    @Published public private(set) var calls: Int = 0
    /// source.rawValue → totals spent through that source.
    @Published public private(set) var bySource: [String: Int] = [:]
    @Published public private(set) var callsBySource: [String: Int] = [:]
    @Published public private(set) var promptBySource: [String: Int] = [:]
    @Published public private(set) var outputBySource: [String: Int] = [:]
    @Published public private(set) var thoughtsBySource: [String: Int] = [:]
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
        let k = source.rawValue
        bySource[k, default: 0]         += usage.total
        callsBySource[k, default: 0]    += 1
        promptBySource[k, default: 0]   += usage.prompt
        outputBySource[k, default: 0]   += usage.output
        thoughtsBySource[k, default: 0] += usage.thoughts
        if since == nil { since = Date() }
        save()
    }

    public func reset() {
        prompt = 0; output = 0; thoughts = 0; total = 0; calls = 0
        bySource = [:]; callsBySource = [:]
        promptBySource = [:]; outputBySource = [:]; thoughtsBySource = [:]
        since = Date()
        save()
    }

    // MARK: - Token accessors

    public func tokens(for source: TokenSource) -> Int { bySource[source.rawValue] ?? 0 }
    public func callCount(for source: TokenSource) -> Int { callsBySource[source.rawValue] ?? 0 }

    // MARK: - Cost (estimated, computed from GeminiPricing — not billed)

    public var inputCost: Double { GeminiPricing.inputCost(prompt) }
    public var outputCost: Double { GeminiPricing.outputCost(output) }
    public var thinkingCost: Double { GeminiPricing.thinkingCost(thoughts) }
    public var totalCost: Double { inputCost + outputCost + thinkingCost }

    public func cost(for source: TokenSource) -> Double {
        let k = source.rawValue
        return GeminiPricing.cost(prompt: promptBySource[k] ?? 0,
                                  output: outputBySource[k] ?? 0,
                                  thoughts: thoughtsBySource[k] ?? 0)
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var prompt: Int; var output: Int; var thoughts: Int; var total: Int
        var calls: Int; var bySource: [String: Int]; var callsBySource: [String: Int]
        // Added later — optional so older saved blobs still decode.
        var promptBySource: [String: Int]?
        var outputBySource: [String: Int]?
        var thoughtsBySource: [String: Int]?
        var since: Date?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        prompt = s.prompt; output = s.output; thoughts = s.thoughts; total = s.total
        calls = s.calls; bySource = s.bySource; callsBySource = s.callsBySource
        promptBySource = s.promptBySource ?? [:]
        outputBySource = s.outputBySource ?? [:]
        thoughtsBySource = s.thoughtsBySource ?? [:]
        since = s.since
    }

    private func save() {
        let s = Snapshot(prompt: prompt, output: output, thoughts: thoughts, total: total,
                         calls: calls, bySource: bySource, callsBySource: callsBySource,
                         promptBySource: promptBySource, outputBySource: outputBySource,
                         thoughtsBySource: thoughtsBySource, since: since)
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
