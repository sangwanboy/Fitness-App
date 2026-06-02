import Foundation

/// Aggregated sleep profile derived from the user's stored `SleepSession`s.
/// Built fresh on-demand by `SleepPatternAnalyzer` (no separate persistence —
/// the underlying sessions are the source of truth). Used by:
///   - The Home tracking card (shows "your typical bedtime").
///   - The morning report ("30 min less than usual").
///   - Astra's system prompt (gives the coach a per-user baseline to
///     reason against instead of universal thresholds).
public struct SleepPattern: Codable {
    public let sessionCount: Int

    /// Hour of day, 24-hour clock. Median of `onsetAt` hour over the last 21 sessions.
    public let typicalBedtimeHour: Int?
    public let typicalBedtimeMinute: Int?

    /// Same for wake.
    public let typicalWakeHour: Int?
    public let typicalWakeMinute: Int?

    public let medianDurationMinutes: Int
    public let bestDurationMinutes: Int
    public let medianRestlessness: Int
    public let medianSnoreEpisodes: Int
    public let medianSnoreMinutes: Int

    /// 0–100. How tight the bedtime/wake spread is — higher = more
    /// consistent. Based on inter-quartile range of onset times.
    public let consistencyScore: Int

    /// Weekday vs weekend bedtime delta in minutes. Positive = goes to bed
    /// later on weekends. nil when not enough weekend data.
    public let weekendDelayMinutes: Int?

    /// Last 7-day median duration minus prior 7-day median.
    /// Positive = sleeping more recently. nil when not enough history.
    public let weeklyTrendMinutes: Int?

    /// Last 5 sessions' duration in minutes, oldest → newest. Used to draw
    /// a sparkline + show trend at-a-glance.
    public let recentDurations: [Int]

    public var hasEnoughHistory: Bool { sessionCount >= 3 }

    /// One-line summary for chat / card injection. "—" when no history.
    public var summary: String {
        guard hasEnoughHistory else { return "Not enough history yet — track a few nights to unlock your pattern." }
        var parts: [String] = []
        if let bh = typicalBedtimeHour, let bm = typicalBedtimeMinute,
           let wh = typicalWakeHour, let wm = typicalWakeMinute {
            parts.append("usually \(formatHM(bh, bm))–\(formatHM(wh, wm))")
        }
        parts.append("\(medianDurationMinutes / 60)h \(medianDurationMinutes % 60)m median")
        if let trend = weeklyTrendMinutes {
            let sign = trend >= 0 ? "+" : ""
            parts.append("\(sign)\(trend) min vs prior week")
        }
        return parts.joined(separator: " · ")
    }

    private func formatHM(_ h: Int, _ m: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var c = DateComponents(); c.hour = h; c.minute = m
        if let d = Calendar.current.date(from: c) { return formatter.string(from: d) }
        return "\(h):\(String(format: "%02d", m))"
    }
}
