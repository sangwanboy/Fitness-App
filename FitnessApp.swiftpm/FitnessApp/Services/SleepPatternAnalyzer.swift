import Foundation

/// Computes a `SleepPattern` from the user's stored `SleepSession`s. Stateless
/// — call `compute(from:)` whenever you need a fresh snapshot. Cheap enough
/// to run inline (the store is capped at 30 sessions; arithmetic is tiny).
public enum SleepPatternAnalyzer {

    /// Build a `SleepPattern` from up to the last `lookback` sessions.
    public static func compute(from sessions: [SleepSession], lookback: Int = 21) -> SleepPattern {
        let recent = Array(sessions.prefix(lookback))
        guard !recent.isEmpty else { return empty }

        // Durations (post-onset).
        let durations = recent.map { Int($0.totalDurationSeconds / 60) }.sorted()
        let medianDuration = median(durations)
        let bestDuration = durations.max() ?? 0

        // Restlessness + snore.
        let restlessness = recent.map { $0.restlessnessScore }.sorted()
        let snoreCounts = recent.map { $0.snoreEpisodes.count }.sorted()
        let snoreMins = recent.map { Int($0.totalSnoreSeconds / 60) }.sorted()

        // Bedtime / wake hour-of-day medians.
        let onsetMinutes = recent.map { hourMinuteToMinutes(of: $0.onsetAt) }.sorted()
        let wakeMinutes = recent.map { hourMinuteToMinutes(of: $0.endedAt) }.sorted()
        let medianOnsetMin = median(onsetMinutes)
        let medianWakeMin = median(wakeMinutes)

        // Consistency: derived from inter-quartile range of onset times.
        // IQR < 30 min → very consistent (100). > 180 min → all over the place (0).
        let iqr = quartile(onsetMinutes, 0.75) - quartile(onsetMinutes, 0.25)
        let consistency = max(0, min(100, Int(100.0 * (1 - Double(iqr) / 180.0))))

        // Weekday vs weekend onset delta.
        let weekendOnsets = recent.filter { isWeekend($0.onsetAt) }.map { hourMinuteToMinutes(of: $0.onsetAt) }
        let weekdayOnsets = recent.filter { !isWeekend($0.onsetAt) }.map { hourMinuteToMinutes(of: $0.onsetAt) }
        let weekendDelay: Int? = (weekendOnsets.count >= 2 && weekdayOnsets.count >= 2)
            ? median(weekendOnsets.sorted()) - median(weekdayOnsets.sorted())
            : nil

        // 7-day vs prior 7-day median.
        let now = Date()
        let week = 7.0 * 24 * 3600
        let last7 = recent.filter { now.timeIntervalSince($0.endedAt) < week }
        let prior7 = recent.filter {
            let dt = now.timeIntervalSince($0.endedAt)
            return dt >= week && dt < 2 * week
        }
        let trend: Int? = (last7.count >= 2 && prior7.count >= 2)
            ? median(last7.map { Int($0.totalDurationSeconds / 60) }.sorted())
              - median(prior7.map { Int($0.totalDurationSeconds / 60) }.sorted())
            : nil

        // Last 5 durations, oldest → newest.
        let last5 = recent.prefix(5).reversed().map { Int($0.totalDurationSeconds / 60) }

        return SleepPattern(
            sessionCount: recent.count,
            typicalBedtimeHour: medianOnsetMin / 60,
            typicalBedtimeMinute: medianOnsetMin % 60,
            typicalWakeHour: medianWakeMin / 60,
            typicalWakeMinute: medianWakeMin % 60,
            medianDurationMinutes: medianDuration,
            bestDurationMinutes: bestDuration,
            medianRestlessness: median(restlessness),
            medianSnoreEpisodes: median(snoreCounts),
            medianSnoreMinutes: median(snoreMins),
            consistencyScore: consistency,
            weekendDelayMinutes: weekendDelay,
            weeklyTrendMinutes: trend,
            recentDurations: Array(last5)
        )
    }

    private static var empty: SleepPattern {
        SleepPattern(sessionCount: 0,
                     typicalBedtimeHour: nil, typicalBedtimeMinute: nil,
                     typicalWakeHour: nil, typicalWakeMinute: nil,
                     medianDurationMinutes: 0, bestDurationMinutes: 0,
                     medianRestlessness: 0, medianSnoreEpisodes: 0, medianSnoreMinutes: 0,
                     consistencyScore: 0,
                     weekendDelayMinutes: nil, weeklyTrendMinutes: nil,
                     recentDurations: [])
    }

    // MARK: - Helpers

    /// Bedtimes near midnight create a wrap-around problem (23:50 vs 00:10
    /// are ~20 min apart but naive minute arithmetic puts them 23h40m apart).
    /// Shift the day so 18:00 = 0 — gives a continuous window that covers
    /// the normal sleep range (6 PM through 6 AM the next day).
    private static func hourMinuteToMinutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let raw = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        // Shift so 18:00 (1080 min) becomes 0 — covers 18:00–06:00 next day
        // as 0..720. Things outside that window get folded but those aren't
        // sleep times anyway.
        return (raw - 18 * 60 + 24 * 60) % (24 * 60)
    }

    private static func median(_ sorted: [Int]) -> Int {
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private static func quartile(_ sorted: [Int], _ q: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * q)))
        return sorted[idx]
    }

    private static func isWeekend(_ d: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: d)
        return wd == 1 || wd == 7    // Sun or Sat
    }
}
