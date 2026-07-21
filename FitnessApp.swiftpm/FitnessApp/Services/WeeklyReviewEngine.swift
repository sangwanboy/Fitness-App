import Foundation
import SwiftUI
import HealthKit

// MARK: - Models

/// One metric's weekly aggregate: this-week vs prior-week totals/averages,
/// a signed delta, and how many of the 7 days actually carried a reading for
/// this metric — a "0 avg from 1 tracked day" reads very differently from
/// one backed by all 7, so the card / narrative can be honest about it.
public struct WeeklyMetricStat: Codable, Equatable, Identifiable {
    public var id: String { metric.rawValue }
    public let metric: HealthMetricType
    public let thisWeekTotal: Double
    /// Average per TRACKED day (total / dataDays), not per calendar day —
    /// a missing day doesn't drag the average toward zero.
    public let thisWeekAverage: Double
    public let priorWeekTotal: Double
    public let priorWeekAverage: Double
    /// (thisWeekAverage - priorWeekAverage) / priorWeekAverage * 100.
    /// 0 when there's no prior-week baseline (priorWeekAverage <= 0) —
    /// callers should check `priorWeekAverage > 0` before trusting this as
    /// a real comparison rather than "no baseline."
    public let deltaPct: Double
    /// 0...7 — days this week with a non-zero reading for this metric.
    public let dataDays: Int
    /// True when a LOWER value is the desirable direction (resting heart
    /// rate only, today) — flips the up/down color convention already used
    /// across the app (WidgetsCard.DeltaBlockView, SleepReportView.deltaStat).
    public let lowerIsBetter: Bool

    public init(metric: HealthMetricType, thisWeekTotal: Double, thisWeekAverage: Double,
                priorWeekTotal: Double, priorWeekAverage: Double, deltaPct: Double,
                dataDays: Int, lowerIsBetter: Bool) {
        self.metric = metric
        self.thisWeekTotal = thisWeekTotal
        self.thisWeekAverage = thisWeekAverage
        self.priorWeekTotal = priorWeekTotal
        self.priorWeekAverage = priorWeekAverage
        self.deltaPct = deltaPct
        self.dataDays = dataDays
        self.lowerIsBetter = lowerIsBetter
    }
}

/// Deterministic weekly aggregates — the trailing 7 COMPLETED days (yesterday
/// back through the 6 days before that) compared against the 7 days before
/// those, so the comparison is always apples-to-apples regardless of what
/// weekday it is "today." Every number here comes straight from on-device
/// engines (HealthKitManager, TrainingLoadEngine, SleepPatternAnalyzer,
/// StreakEngine) — nothing is invented, and the AI narrative is instructed to
/// only narrate these numbers, never fabricate new ones.
public struct WeeklyReviewData: Codable, Equatable {
    /// First day of the reviewed window (today - 7).
    public let weekStart: Date
    /// Last day of the reviewed window — yesterday, the last COMPLETED day.
    public let weekEnd: Date
    /// Steps, active energy, exercise minutes, sleep, resting heart rate —
    /// in that fixed order (matches the card's row order).
    public let stats: [WeeklyMetricStat]

    public let workoutsCompleted: Int
    public let workoutsCompletedPriorWeek: Int

    /// From TrainingLoadEngine.dailyLoads (kcal, or duration-minute proxy
    /// when energy data is absent) — same two 7-day windows.
    public let trainingLoadThisWeek: Double
    public let trainingLoadPriorWeek: Double
    /// 0 when there's no prior-week load to compare against.
    public let trainingLoadDeltaPct: Double

    /// Deterministic training-phase classifier ("build"/"peak"/"deload"/
    /// "recover"/"steady"), read from the already-computed
    /// `HealthKitManager.shared.predictions?.periodization` (itself derived
    /// from the same load history TrainingLoadEngine tracks). Narrative
    /// context only — not rendered as its own stat row. nil when the engine
    /// doesn't have enough workout signal to classify.
    public let periodizationPhase: String?

    /// StreakEngine.shared.currentStreak at aggregation time.
    public let currentStreakWeeks: Int

    /// SleepPatternAnalyzer output over the on-device tracked sessions —
    /// narrative context (distinct from the HK "sleep hours" stat row, which
    /// reflects whatever wrote sleep samples to Health). nil when the user
    /// has fewer than 3 tracked sessions.
    public let sleepConsistencyScore: Int?
    public let sleepWeeklyTrendMinutes: Int?

    /// Days (0...7) with ANY tracked metric reading this week — the union
    /// across `stats`. Gates `.insufficientData` at < 3.
    public let totalDataDays: Int

    public init(weekStart: Date, weekEnd: Date, stats: [WeeklyMetricStat],
                workoutsCompleted: Int, workoutsCompletedPriorWeek: Int,
                trainingLoadThisWeek: Double, trainingLoadPriorWeek: Double, trainingLoadDeltaPct: Double,
                periodizationPhase: String?, currentStreakWeeks: Int,
                sleepConsistencyScore: Int?, sleepWeeklyTrendMinutes: Int?,
                totalDataDays: Int) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.stats = stats
        self.workoutsCompleted = workoutsCompleted
        self.workoutsCompletedPriorWeek = workoutsCompletedPriorWeek
        self.trainingLoadThisWeek = trainingLoadThisWeek
        self.trainingLoadPriorWeek = trainingLoadPriorWeek
        self.trainingLoadDeltaPct = trainingLoadDeltaPct
        self.periodizationPhase = periodizationPhase
        self.currentStreakWeeks = currentStreakWeeks
        self.sleepConsistencyScore = sleepConsistencyScore
        self.sleepWeeklyTrendMinutes = sleepWeeklyTrendMinutes
        self.totalDataDays = totalDataDays
    }
}

/// Astra-voiced weekly narrative generated FROM `WeeklyReviewData` — the
/// gateway is instructed to only narrate the numbers it's given, never
/// invent new ones.
public struct WeeklyReviewNarrative: Codable, Equatable {
    public let summary: String   // 3-4 sentences
    public let focus: String     // one concrete next-week focus
    public let generatedAt: Date

    public init(summary: String, focus: String, generatedAt: Date = Date()) {
        self.summary = summary
        self.focus = focus
        self.generatedAt = generatedAt
    }
}

/// Disk-cached bundle for one ISO week. Aggregates are always present once
/// computed; narrative is optional (gateway may be unreachable, or the AI
/// call may still be in flight).
private struct WeeklyReviewCacheEntry: Codable {
    let isoWeekKey: String
    let data: WeeklyReviewData
    var narrative: WeeklyReviewNarrative?
    let generatedAt: Date
}

private enum WeeklyReviewNarrativeError: Error {
    case parseError
}

// MARK: - Engine

/// AI-side companion for the Progress hub's weekly review. Aggregates the
/// trailing 7 completed days (+ the 7 before, for deltas) from the real
/// on-device sources, caches the result per ISO-week in Application Support,
/// and — once there's enough signal — asks Astra for a short narrative built
/// strictly from those aggregates. Mirrors `PredictionAIService`'s honesty
/// conventions: on gateway failure the aggregates still render, the
/// narrative just goes to `.unavailable` with a retry affordance.
@MainActor
public final class WeeklyReviewEngine: ObservableObject {
    public static let shared = WeeklyReviewEngine()

    public enum NarrativeState: Equatable {
        case idle
        case loading
        case ready
        case unavailable
    }

    @Published public private(set) var data: WeeklyReviewData?
    @Published public private(set) var narrative: WeeklyReviewNarrative?
    @Published public private(set) var narrativeState: NarrativeState = .idle
    /// Non-nil (0...2) while there isn't enough HK history this week yet.
    /// nil once the review is ready (>= 3 data days).
    @Published public private(set) var insufficientDataDays: Int? = nil

    private var currentWeekKey: String?
    private var narrativeTask: Task<Void, Never>?
    private var lastNarrativeFailureAt: Date?
    /// Mirrors HealthKitManager's AI-enrichment backoff so a dead gateway
    /// doesn't get hammered on every hub visit.
    private let narrativeFailureBackoff: TimeInterval = 300

    private init() {
        // Self-heal: a narrative that failed while signed out (401) shouldn't
        // sit behind its backoff waiting for a manual Retry once the user
        // signs in.
        NotificationCenter.default.addObserver(
            forName: .gatewaySessionEstablished, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.data != nil, self.narrative == nil,
                      self.insufficientDataDays == nil else { return }
                self.retryNarrative()
            }
        }

        let key = Self.isoWeekKey(for: Date())
        guard let cached = loadFromDisk(weekKey: key) else { return }
        currentWeekKey = key
        data = cached.data
        narrative = cached.narrative
        narrativeState = cached.narrative != nil ? .ready : .idle
        insufficientDataDays = cached.data.totalDataDays < 3 ? cached.data.totalDataDays : nil
    }

    // MARK: - Public API

    /// Cheap — call from the card's `.onAppear`. Recomputes aggregates when
    /// the ISO week rolled over, nothing is cached yet, or the cached
    /// trailing-7-day window has simply gone stale (a new day completed
    /// since it was last built — the window is NOT re-derived just because
    /// the calendar date changed, so a week can otherwise sit on stale
    /// aggregates for up to 6 days). Otherwise just makes sure a narrative is
    /// in flight if one's missing.
    public func refreshIfNeeded() {
        let key = Self.isoWeekKey(for: Date())
        guard currentWeekKey == key, let data else {
            computeAndCache(weekKey: key)
            return
        }

        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? .distantPast
        guard data.weekEnd == yesterday else {
            refreshAggregatesOnly(weekKey: key)
            return
        }

        kickoffNarrativeIfNeeded()
    }

    /// Recomputes just the deterministic aggregates in place — same window/
    /// insufficiency logic as `computeAndCache`, minus the narrative-cache
    /// bootstrapping (this is a same-week refresh, not a week rollover). The
    /// per-week narrative cache is left untouched here: a narrative already
    /// generated for this week isn't regenerated just because the aggregates
    /// moved (`kickoffNarrativeIfNeeded` no-ops once `narrative` is non-nil);
    /// it only actually kicks off a call the first time this week's data
    /// crosses the sufficiency threshold.
    private func refreshAggregatesOnly(weekKey: String) {
        guard let aggregates = buildAggregates() else { return }
        data = aggregates

        guard aggregates.totalDataDays >= 3 else {
            insufficientDataDays = aggregates.totalDataDays
            persistToDisk(weekKey: weekKey, data: aggregates, narrative: nil)
            return
        }
        insufficientDataDays = nil
        persistToDisk(weekKey: weekKey, data: aggregates, narrative: narrative)
        scheduleWeeklyReviewNotification(data: aggregates)
        kickoffNarrativeIfNeeded()
    }

    /// Explicit user-triggered refresh — recomputes aggregates AND forces a
    /// fresh narrative regardless of cache / backoff.
    public func forceRefresh() {
        computeAndCache(weekKey: Self.isoWeekKey(for: Date()), forceNarrative: true)
    }

    /// Retry just the narrative (aggregates unchanged) — the card's "narrative
    /// unavailable" retry button. Bypasses the failure backoff since it's an
    /// explicit tap.
    public func retryNarrative() {
        guard let data else { return }
        startNarrativeTask(for: data, weekKey: currentWeekKey ?? Self.isoWeekKey(for: Date()), bypassBackoff: true)
    }

    // MARK: - Aggregation

    private struct DateWindow { let start: Date; let end: Date } // both start-of-day, inclusive

    private static func windows(now: Date = Date(), calendar: Calendar = .current) -> (current: DateWindow, prior: DateWindow)? {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: -1, to: today),        // yesterday — last completed day
              let start = cal.date(byAdding: .day, value: -6, to: end),        // 7 days inclusive of `end`
              let priorEnd = cal.date(byAdding: .day, value: -1, to: start),
              let priorStart = cal.date(byAdding: .day, value: -6, to: priorEnd)
        else { return nil }
        return (DateWindow(start: start, end: end), DateWindow(start: priorStart, end: priorEnd))
    }

    private static func dailyMap(_ history: [MetricValue], calendar: Calendar) -> [Date: Double] {
        var map: [Date: Double] = [:]
        for mv in history {
            map[calendar.startOfDay(for: mv.date)] = mv.value
        }
        return map
    }

    /// Sums non-zero days in `window` and counts how many of the 7 carried
    /// a reading. A day absent from `map` and a day present with value 0
    /// are treated identically ("no data that day") — HealthKitManager's
    /// history fetchers use both conventions depending on the query type.
    private static func sumAndDataDays(_ map: [Date: Double], window: DateWindow, calendar: Calendar) -> (total: Double, dataDays: Int) {
        var total = 0.0
        var dataDays = 0
        var cursor = window.start
        while cursor <= window.end {
            if let v = map[cursor], v > 0 {
                total += v
                dataDays += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (total, dataDays)
    }

    private static func metricStat(_ type: HealthMetricType, hk: HealthKitManager,
                                   current: DateWindow, prior: DateWindow, calendar: Calendar) -> WeeklyMetricStat {
        let history = hk.metricSummaries[type]?.history ?? []
        let map = dailyMap(history, calendar: calendar)
        let (curTotal, curDays) = sumAndDataDays(map, window: current, calendar: calendar)
        let (priorTotal, priorDays) = sumAndDataDays(map, window: prior, calendar: calendar)
        let curAvg = curDays > 0 ? curTotal / Double(curDays) : 0
        let priorAvg = priorDays > 0 ? priorTotal / Double(priorDays) : 0

        // Active energy + exercise minutes are DISPLAYED as weekly totals
        // (WeeklyReviewCard.displayValue), so their delta must compare
        // totals too — a per-tracked-day-average delta can read as
        // improving while the total (the number actually on screen) moved
        // the other way. Every other stat is displayed as a per-day average,
        // so its delta stays average-on-average.
        let curBasis: Double
        let priorBasis: Double
        switch type {
        case .activeEnergy, .exerciseMinutes:
            curBasis = curTotal
            priorBasis = priorTotal
        default:
            curBasis = curAvg
            priorBasis = priorAvg
        }
        let delta = priorBasis > 0 ? ((curBasis - priorBasis) / priorBasis) * 100 : 0

        return WeeklyMetricStat(metric: type, thisWeekTotal: curTotal, thisWeekAverage: curAvg,
                                priorWeekTotal: priorTotal, priorWeekAverage: priorAvg,
                                deltaPct: delta, dataDays: curDays,
                                lowerIsBetter: type == .restingHeartRate)
    }

    /// The five metrics the task explicitly grounds this feature in, read
    /// straight from `HealthKitManager.metricSummaries` — steps, active
    /// energy, exercise minutes, sleep, resting heart rate (HealthKitManager.swift,
    /// `metricSummaries` @Published dict + the per-type `history` arrays built
    /// by `fetchHistory` / `fetchSimpleHistory`).
    private static let statOrder: [HealthMetricType] = [.steps, .activeEnergy, .exerciseMinutes, .sleep, .restingHeartRate]

    private func buildAggregates() -> WeeklyReviewData? {
        let cal = Calendar.current
        guard let (current, prior) = Self.windows(calendar: cal) else { return nil }
        let hk = HealthKitManager.shared

        let stats = Self.statOrder.map { Self.metricStat($0, hk: hk, current: current, prior: prior, calendar: cal) }

        // "Any data this day" — union across the five tracked metrics.
        var totalDataDays = 0
        var cursor = current.start
        while cursor <= current.end {
            let hasAny = Self.statOrder.contains { type in
                (hk.metricSummaries[type]?.history ?? []).contains {
                    cal.isDate($0.date, inSameDayAs: cursor) && $0.value > 0
                }
            }
            if hasAny { totalDataDays += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // Workouts — HealthKitManager.recentWorkouts28 (28-day cache, covers
        // both 7-day windows).
        let workouts = hk.recentWorkouts28
        let workoutsCompleted = workouts.filter {
            let day = cal.startOfDay(for: $0.startDate)
            return day >= current.start && day <= current.end
        }.count
        let workoutsPrior = workouts.filter {
            let day = cal.startOfDay(for: $0.startDate)
            return day >= prior.start && day <= prior.end
        }.count

        // Training load — TrainingLoadEngine.dailyLoads (28-day, kcal or
        // duration-minute proxy; TrainingLoadEngine.swift `compute(from:)`).
        let loadByDay = Dictionary(uniqueKeysWithValues: TrainingLoadEngine.shared.dailyLoads.map {
            (cal.startOfDay(for: $0.date), $0.load)
        })
        func sumLoad(_ w: DateWindow) -> Double {
            var total = 0.0
            var c = w.start
            while c <= w.end {
                total += loadByDay[c] ?? 0
                guard let n = cal.date(byAdding: .day, value: 1, to: c) else { break }
                c = n
            }
            return total
        }
        let loadThis = sumLoad(current)
        let loadPrior = sumLoad(prior)
        let loadDelta = loadPrior > 0 ? ((loadThis - loadPrior) / loadPrior) * 100 : 0

        // Periodization phase — already computed by PredictionEngine from the
        // same load history TrainingLoadEngine tracks; narrative context only.
        let phase = hk.predictions?.periodization?.phase

        // Streak — StreakEngine.shared.currentStreak.
        let streakWeeks = StreakEngine.shared.currentStreak

        // Sleep pattern — SleepPatternAnalyzer over the on-device tracked
        // sessions (SleepSessionStore.shared.sessions).
        let sleepPattern = SleepPatternAnalyzer.compute(from: SleepSessionStore.shared.sessions)
        let sleepConsistency = sleepPattern.hasEnoughHistory ? sleepPattern.consistencyScore : nil
        let sleepTrend = sleepPattern.hasEnoughHistory ? sleepPattern.weeklyTrendMinutes : nil

        return WeeklyReviewData(
            weekStart: current.start, weekEnd: current.end, stats: stats,
            workoutsCompleted: workoutsCompleted, workoutsCompletedPriorWeek: workoutsPrior,
            trainingLoadThisWeek: loadThis, trainingLoadPriorWeek: loadPrior, trainingLoadDeltaPct: loadDelta,
            periodizationPhase: phase, currentStreakWeeks: streakWeeks,
            sleepConsistencyScore: sleepConsistency, sleepWeeklyTrendMinutes: sleepTrend,
            totalDataDays: totalDataDays
        )
    }

    private func computeAndCache(weekKey: String, forceNarrative: Bool = false) {
        guard let aggregates = buildAggregates() else { return }
        currentWeekKey = weekKey
        data = aggregates

        guard aggregates.totalDataDays >= 3 else {
            insufficientDataDays = aggregates.totalDataDays
            narrative = nil
            narrativeState = .idle
            persistToDisk(weekKey: weekKey, data: aggregates, narrative: nil)
            return
        }
        insufficientDataDays = nil

        if forceNarrative {
            narrative = nil
            lastNarrativeFailureAt = nil
        } else if narrative == nil, let cached = loadFromDisk(weekKey: weekKey) {
            // Cold-launch mid-week (engine re-init) — reuse a same-week
            // narrative from disk instead of re-hitting the gateway.
            narrative = cached.narrative
            narrativeState = cached.narrative != nil ? .ready : .idle
        }

        persistToDisk(weekKey: weekKey, data: aggregates, narrative: narrative)
        scheduleWeeklyReviewNotification(data: aggregates)

        if narrative == nil {
            startNarrativeTask(for: aggregates, weekKey: weekKey, bypassBackoff: forceNarrative)
        }
    }

    // MARK: - Narrative (gateway call)

    private func kickoffNarrativeIfNeeded() {
        // Never spend a gateway call on a narrative for a week that doesn't
        // have enough data to review yet — `computeAndCache` already skips
        // this when it first computes aggregates, but a later `refreshIfNeeded()`
        // call (e.g. revisiting the hub) hits this method directly and has no
        // other guard against the same insufficient-data week.
        guard insufficientDataDays == nil else { return }
        guard let data, narrative == nil, narrativeState != .loading else { return }
        startNarrativeTask(for: data, weekKey: currentWeekKey ?? Self.isoWeekKey(for: Date()))
    }

    private func startNarrativeTask(for data: WeeklyReviewData, weekKey: String, bypassBackoff: Bool = false) {
        if !bypassBackoff,
           let failedAt = lastNarrativeFailureAt,
           Date().timeIntervalSince(failedAt) < narrativeFailureBackoff {
            narrativeState = .unavailable
            return
        }
        narrativeTask?.cancel()
        narrativeState = .loading
        narrativeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Self.generateNarrative(for: data)
                await MainActor.run {
                    // Snapshot-replacement guard — bail if the week rolled
                    // over (or a newer refresh landed) while this was in flight.
                    guard self.currentWeekKey == weekKey else { return }
                    self.narrative = result
                    self.narrativeState = .ready
                    self.lastNarrativeFailureAt = nil
                    self.persistToDisk(weekKey: weekKey, data: data, narrative: result)
                }
            } catch {
                await MainActor.run {
                    guard self.currentWeekKey == weekKey else { return }
                    self.lastNarrativeFailureAt = Date()
                    self.narrativeState = .unavailable
                }
            }
        }
    }

    /// One-shot /v1/chat call through the gateway, following
    /// PredictionAIService's `callGeminiJSON` pattern: gateway transport,
    /// strict-JSON response, TokenMeter accounting under the `.insights`
    /// source (weekly review is an insights-class feature; no dedicated
    /// TokenSource case was added to avoid touching TokenMeter.swift, which
    /// is outside this task's file ownership).
    private static func generateNarrative(for data: WeeklyReviewData) async throws -> WeeklyReviewNarrative {
        let prompt = narrativePrompt(for: data)
        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        let maxTokens = 320
        let generationConfig: [String: Any] = [
            "maxOutputTokens": maxTokens + thinkingBudget,
            "temperature": 0.6,
            "thinkingConfig": ["thinkingBudget": thinkingBudget],
            "responseMimeType": "application/json"
        ]
        let body = GatewayChatPayload.body(
            stream: false,
            system: "",
            messages: [GatewayChatPayload.message(role: "user", parts: [GatewayChatPayload.textPart(prompt)])],
            generationConfig: generationConfig
        )

        let raw = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: 15)

        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw WeeklyReviewNarrativeError.parseError
        }
        if let usageMeta = obj["usageMetadata"] as? [String: Any],
           let usage = TokenUsage(usageMetadata: usageMeta) {
            TokenMeter.shared.record(usage, source: .insights)
        }

        guard let jsonData = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let summary = (parsed["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let focus = (parsed["focus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty, !focus.isEmpty else {
            throw WeeklyReviewNarrativeError.parseError
        }
        return WeeklyReviewNarrative(summary: summary, focus: focus)
    }

    private static func narrativePrompt(for data: WeeklyReviewData) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let rangeLabel = "\(df.string(from: data.weekStart)) \u{2013} \(df.string(from: data.weekEnd))"

        var lines: [String] = []
        for stat in data.stats {
            guard stat.dataDays > 0 else {
                lines.append("\(stat.metric.displayName): no data this week")
                continue
            }
            let unit = stat.metric.unit
            var line = "\(stat.metric.displayName): \(String(format: "%.1f", stat.thisWeekAverage)) \(unit)/day avg (tracked \(stat.dataDays)/7 days)"
            if stat.priorWeekAverage > 0 {
                let sign = stat.deltaPct >= 0 ? "+" : ""
                line += ", \(sign)\(String(format: "%.0f", stat.deltaPct))% vs prior week (\(String(format: "%.1f", stat.priorWeekAverage)) \(unit)/day)"
            } else {
                line += ", no prior-week baseline"
            }
            lines.append(line)
        }

        var context: [String] = []
        context.append("Workouts completed: \(data.workoutsCompleted) (prior week: \(data.workoutsCompletedPriorWeek))")
        if data.trainingLoadPriorWeek > 0 {
            let sign = data.trainingLoadDeltaPct >= 0 ? "+" : ""
            context.append("Training load: \(String(format: "%.0f", data.trainingLoadThisWeek)) kcal-equivalent, \(sign)\(String(format: "%.0f", data.trainingLoadDeltaPct))% vs prior week")
        }
        if let phase = data.periodizationPhase {
            context.append("Current training phase (deterministic classifier): \(phase)")
        }
        context.append("Current weekly-activity streak: \(data.currentStreakWeeks) week\(data.currentStreakWeeks == 1 ? "" : "s")")
        if let consistency = data.sleepConsistencyScore {
            context.append("Sleep-timing consistency score: \(consistency)/100")
        }
        if let trend = data.sleepWeeklyTrendMinutes {
            let sign = trend >= 0 ? "+" : ""
            context.append("Sleep duration trend (on-device tracked nights): \(sign)\(trend) min vs prior week")
        }

        return """
        You are Astra, the user's AI fitness coach inside Fitness Guru. Write their weekly review.

        WEEK REVIEWED: \(rangeLabel) (7 completed days, compared against the 7 days before)

        METRICS (ground truth — use ONLY these numbers, never invent or estimate a number that isn't here):
        \(lines.joined(separator: "\n"))

        ADDITIONAL CONTEXT:
        \(context.joined(separator: "\n"))

        TASK: Write a brief, honest weekly review.
        - "summary": 3-4 sentences in Astra's voice, addressing the user directly ("you"/"your"). Reference at least 2 of the specific numbers above. If a metric has no data, don't pretend it happened — either skip it or note it's untracked. Never invent a number not present above.
        - "focus": ONE concrete, specific next-week focus — a single actionable sentence (not vague like "keep it up").

        Output STRICT JSON (no markdown fences, no preamble):
        {"summary": "...", "focus": "..."}
        """
    }

    // MARK: - Sunday notification

    /// Trigger scheduling whenever a week's aggregates are computed. The
    /// NotificationManager contract (`isKindEnabled` / `schedule`) is owned
    /// by a parallel rewrite of NotificationManager.swift — this call site
    /// is written to that exact signature.
    private func scheduleWeeklyReviewNotification(data: WeeklyReviewData) {
        guard NotificationManager.shared.isKindEnabled(.weeklyReview) else { return }
        NotificationManager.shared.schedule(.weeklyReview,
            title: "Your week in review",
            body: Self.notificationBody(for: data),
            at: Self.nextSunday7PM(),
            chatPrompt: "Walk me through my weekly review and what to focus on next week.")
    }

    /// One real stat for the notification body — prefers active energy
    /// (matches the contract's example), falls back to whichever tracked
    /// metric moved the most, else an honest generic line.
    private static func notificationBody(for data: WeeklyReviewData) -> String {
        if let energy = data.stats.first(where: { $0.metric == .activeEnergy }),
           energy.dataDays > 0, energy.priorWeekAverage > 0 {
            let direction = energy.deltaPct >= 0 ? "up" : "down"
            return "Active energy \(direction) \(String(format: "%.0f", abs(energy.deltaPct)))% — see what Astra suggests for next week."
        }
        if let best = data.stats
            .filter({ $0.dataDays > 0 && $0.priorWeekAverage > 0 })
            .max(by: { abs($0.deltaPct) < abs($1.deltaPct) }) {
            let direction = best.deltaPct >= 0 ? "up" : "down"
            return "\(best.metric.displayName) \(direction) \(String(format: "%.0f", abs(best.deltaPct)))% this week — see what Astra suggests for next week."
        }
        return "Your weekly review is ready — see what Astra suggests for next week."
    }

    private static func nextSunday7PM(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = calendar
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday ... 7 = Saturday
        let daysUntilSunday = (1 - weekday + 7) % 7
        let candidateDay = cal.date(byAdding: .day, value: daysUntilSunday, to: cal.startOfDay(for: now)) ?? now
        var comps = cal.dateComponents([.year, .month, .day], from: candidateDay)
        comps.hour = 19; comps.minute = 0; comps.second = 0
        let target = cal.date(from: comps) ?? candidateDay
        if target <= now, let pushed = cal.date(byAdding: .day, value: 7, to: target) {
            return pushed
        }
        return target
    }

    // MARK: - ISO-week cache key

    private static func isoWeekKey(for date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let woy = cal.component(.weekOfYear, from: date)
        let yr = cal.component(.yearForWeekOfYear, from: date)
        return "\(yr)-W\(String(format: "%02d", woy))"
    }

    // MARK: - Disk cache (Application Support)

    private static let cacheDirName = "WeeklyReview"
    private static let maxCachedWeeks = 8

    private func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(Self.cacheDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheFileURL(weekKey: String) -> URL? {
        cacheDirectory()?.appendingPathComponent("week-\(weekKey).json")
    }

    private func loadFromDisk(weekKey: String) -> WeeklyReviewCacheEntry? {
        guard let url = cacheFileURL(weekKey: weekKey),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeeklyReviewCacheEntry.self, from: raw)
    }

    private func persistToDisk(weekKey: String, data: WeeklyReviewData, narrative: WeeklyReviewNarrative?) {
        guard let url = cacheFileURL(weekKey: weekKey) else { return }
        let entry = WeeklyReviewCacheEntry(isoWeekKey: weekKey, data: data, narrative: narrative, generatedAt: Date())
        guard let out = try? JSONEncoder().encode(entry) else { return }
        try? out.write(to: url, options: .atomic)
        pruneOldCacheFiles()
    }

    /// Keep only the most recent `maxCachedWeeks` week files so the cache
    /// doesn't grow unbounded across app lifetime.
    private func pruneOldCacheFiles() {
        guard let dir = cacheDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }
        for url in sorted.dropFirst(Self.maxCachedWeeks) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
