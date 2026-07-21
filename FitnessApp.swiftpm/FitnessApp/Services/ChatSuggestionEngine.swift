import Foundation
import Combine

/// Deterministic, zero-network engine that derives up to 3 predictive
/// suggestion chips for the Coach chat's composer overlay. Every candidate
/// comes from already-computed on-device state — no HTTP, no Gemini, no
/// randomness — so the same state snapshot always ranks the same way.
///
/// Sources read (see each rule below for the exact property):
///   - `HealthKitManager.shared.predictions` — illness early-warning,
///     recovery readiness, sedentary alert, sleep forecast.
///   - `HealthKitManager.shared.metricSummaries[.sleep]` — last tracked
///     night's hours vs `HealthKitManager.userGoal(for:)`.
///   - `TrainingPlanStore.shared` — today's planned session / plan coverage.
///   - `NutritionTargets.shared` + `HealthKitManager.shared.dietaryProteinToday`
///     / `.todayFoodLog` — protein pace and logging gaps.
///   - `StreakEngine.shared` — this week's streak-qualifying activity.
///   - `WeeklyReviewEngine.shared.narrative` — weekly review freshness.
///   - `AstraMemoryStore.shared.profile.goals` — low-priority tiebreaker
///     flavor, quoting the user's own stored goal text (never invented).
///
/// Ranking: each rule below computes a fixed urgency score (0-100). All
/// candidates are sorted descending by score, with ties broken by the order
/// rules were evaluated (an explicit index, not relied on stdlib sort
/// stability) — so re-running `refresh()` against an unchanged state
/// snapshot always produces the identical top-3, never a per-render shuffle.
/// Fewer than 3 qualifying candidates are padded out with the honest generic
/// fallback trio (the same copy the old hardcoded chip row always showed).
@MainActor
public final class ChatSuggestionEngine: ObservableObject {
    public static let shared = ChatSuggestionEngine()

    /// One suggestion chip: `label` is the ≤26-char chip text, `prompt` is
    /// the full sentence sent to Astra verbatim when tapped (identical
    /// contract to the old hardcoded chips, where label == prompt).
    public struct SuggestionChip: Identifiable, Equatable {
        public var id: String { label }
        public let label: String
        public let prompt: String
    }

    @Published public private(set) var chips: [SuggestionChip] = []

    /// Honest floor when no on-device signal clears its bar. Verbatim copy
    /// of the previous hardcoded chip row — a deterministic, always-useful
    /// no-data fallback rather than a fabricated "personalized" prompt.
    private static let fallback: [SuggestionChip] = [
        SuggestionChip(label: "How was my sleep?", prompt: "How was my sleep?"),
        SuggestionChip(label: "Plan tomorrow", prompt: "Plan tomorrow"),
        SuggestionChip(label: "Why am I tired?", prompt: "Why am I tired?"),
        SuggestionChip(label: "Suggest a workout", prompt: "Suggest a workout")
    ]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refresh()
        // Recompute whenever HealthKitManager's published state changes
        // (predictions, dietary intake, food log, metric summaries — every
        // fetchTodayData() / pull-to-refresh / goal edit touches at least
        // one). Deferred one run-loop turn via Task so we read state AFTER
        // the triggering @Published property has actually finished storing
        // its new value (Combine's synthesized `objectWillChange` fires
        // during `willSet`, before the write lands).
        HealthKitManager.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            .store(in: &cancellables)
    }

    /// Recompute the top-3 chip list from current on-device state. Pure
    /// arithmetic over already-loaded singletons — cheap enough to call from
    /// `.onAppear` or any publisher callback.
    public func refresh() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday, 2 = Monday

        var candidates: [(score: Int, chip: SuggestionChip)] = []

        // --- Rule 1: illness early-warning active.
        // Source: HealthKitManager.shared.predictions?.illnessWarning
        // (on-device PredictionEngine; severity is .moderate or .high only).
        if let illness = HealthKitManager.shared.predictions?.illnessWarning {
            let score = illness.severity == .high ? 100 : 92
            candidates.append((score, SuggestionChip(
                label: "Recovery under strain?",
                prompt: "Why is my recovery under strain right now?"
            )))
        }

        // --- Rule 2: sedentary alert.
        // Source: HealthKitManager.shared.predictions?.sedentary
        // (SedentaryAlert.severity: .moderate | .high).
        if let sedentary = HealthKitManager.shared.predictions?.sedentary {
            let score = sedentary.severity == .high ? 95 : 84
            candidates.append((score, SuggestionChip(
                label: "Move for 5 minutes",
                prompt: "Get me moving in 5 minutes"
            )))
        }

        // --- Rule 3: streak-qualifying activity unmet, evening.
        // Source: StreakEngine.shared (weeklyActivity / currentStreak) —
        // reuses its own Monday-anchored week + published `isActive` flag
        // rather than re-deriving thresholds from raw HK samples.
        if hour >= 17, StreakEngine.shared.currentStreak > 0 {
            var isoCal = Calendar(identifier: .iso8601)
            isoCal.firstWeekday = 2
            let thisWeekStart = Self.mondayOnOrBefore(now, calendar: isoCal)
            if let thisWeek = StreakEngine.shared.weeklyActivity.first(where: {
                calendar.isDate($0.weekStart, inSameDayAs: thisWeekStart)
            }), !thisWeek.isActive {
                candidates.append((90, SuggestionChip(
                    label: "Save my streak today",
                    prompt: "Save my streak today — what do I need to do?"
                )))
            }
        }

        // --- Rule 4: sleep debt.
        // Sources: HealthKitManager.shared.metricSummaries[.sleep] (most
        // recent tracked night, hours) vs HealthKitManager.userGoal(for:),
        // OR HealthKitManager.shared.predictions?.sleepForecast.predictedHours
        // (the engine's stratified next-night forecast) falling clearly
        // short of goal. Evening/night hours flip the prompt from "why
        // tired" to a wind-down nudge — same underlying signal, different
        // framing depending on time of day.
        let sleepGoal = HealthKitManager.userGoal(for: .sleep)
        let lastNightHours = HealthKitManager.shared.metricSummaries[.sleep]?.currentValue ?? 0
        let forecastHours = HealthKitManager.shared.predictions?.sleepForecast?.predictedHours
        let sleepFarShort = (lastNightHours > 0 && lastNightHours < sleepGoal * 0.75)
            || (forecastHours.map { $0 < sleepGoal * 0.75 } ?? false)
        if sleepFarShort {
            let isEvening = hour >= 17 || hour < 5
            let score = isEvening ? 88 : 76
            let chip = isEvening
                ? SuggestionChip(label: "Wind down tonight", prompt: "Help me wind down tonight")
                : SuggestionChip(label: "Why am I tired?", prompt: "Why am I tired today?")
            candidates.append((score, chip))
        }

        // --- Rule 5: recovery readiness high.
        // Source: HealthKitManager.shared.predictions?.recovery
        // (RecoveryReadiness.score / .label). Biased toward morning/midday,
        // when "what should I push today" is actually actionable.
        if let recovery = HealthKitManager.shared.predictions?.recovery,
           recovery.label == .strong || recovery.score >= 80 {
            let score = (5..<15).contains(hour) ? 85 : 58
            candidates.append((score, SuggestionChip(
                label: "What should I push today?",
                prompt: "What should I push today?"
            )))
        }

        // --- Rule 6: training plan.
        // Source: TrainingPlanStore.shared (currentWeekDays / activePlan).
        let planStore = TrainingPlanStore.shared
        let today = calendar.startOfDay(for: now)
        if let pendingDay = planStore.currentWeekDays.first(where: {
            calendar.isDate($0.date, inSameDayAs: today) && $0.kind != .rest && !$0.completed
        }) {
            let score = (5..<11).contains(hour) ? 78 : 65
            let shortTitle = pendingDay.title.prefix(18)
            let label = String("Today: \(shortTitle)".prefix(26))
            candidates.append((score, SuggestionChip(
                label: label,
                prompt: "Walk me through today's \(pendingDay.title)."
            )))
        } else if planStore.activePlan == nil || planStore.currentWeekDays.isEmpty {
            let score = (weekday == 1 || weekday == 2) ? 75 : 63 // Sun/Mon bump
            candidates.append((score, SuggestionChip(
                label: "Build my training week",
                prompt: "Build my training week"
            )))
        }

        // --- Rule 7: nutrition — nothing logged past 13:00.
        // Source: HealthKitManager.shared.todayFoodLog. Takes priority over
        // the "behind pace" rule below when nothing at all was logged, since
        // that's the more precise (and more actionable) gap.
        let foodLogEmpty = HealthKitManager.shared.todayFoodLog.isEmpty
        if foodLogEmpty, hour >= 13 {
            candidates.append((72, SuggestionChip(
                label: "Log what I've eaten",
                prompt: "Log what I've eaten today"
            )))
        } else if let proteinTarget = NutritionTargets.shared.proteinTargetG {
            // --- Rule 7b: nutrition target set + behind pace.
            // Sources: NutritionTargets.shared.proteinTargetG +
            // HealthKitManager.shared.dietaryProteinToday. Paces expected
            // intake across a 7 AM–9 PM (14h) active eating window.
            let elapsedHours = Double(hour - 7)
            let fraction = min(max(elapsedHours / 14.0, 0), 1)
            let expectedByNow = proteinTarget * fraction
            let actual = HealthKitManager.shared.dietaryProteinToday
            if fraction > 0.15, actual < expectedByNow * 0.65 {
                candidates.append((68, SuggestionChip(
                    label: "Hit my protein target",
                    prompt: "What should I eat to hit my protein target today?"
                )))
            }
        }

        // --- Rule 8: weekly review freshness.
        // Source: WeeklyReviewEngine.shared.narrative (non-nil only once
        // aggregates + the AI narrative both landed) gated to Sun/Mon.
        if (weekday == 1 || weekday == 2), WeeklyReviewEngine.shared.narrative != nil {
            candidates.append((55, SuggestionChip(
                label: "Review my week",
                prompt: "Walk me through my weekly review"
            )))
        }

        // --- Rule 9: memory-goal tiebreaker flavor.
        // Source: AstraMemoryStore.shared.profile.goals — low-priority
        // filler that quotes the user's OWN stored goal text verbatim
        // (truncated), never a fabricated goal.
        let goalsText = AstraMemoryStore.shared.profile.goals.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !goalsText.isEmpty {
            let snippet = goalsText.prefix(60)
            candidates.append((20, SuggestionChip(
                label: "Check my goal progress",
                prompt: "How am I progressing toward my goal: \(snippet)?"
            )))
        }

        // --- Rank, dedupe by label, pad with the honest fallback.
        let ranked = Self.topThree(from: candidates)
        if ranked != chips {
            chips = ranked
        }
    }

    /// Sorts by score descending (stable on declaration order via an
    /// explicit index — never left to depend on the stdlib sort's own
    /// stability guarantees), dedupes by label, and pads any remaining
    /// slots from the generic fallback trio/quad.
    private static func topThree(from candidates: [(score: Int, chip: SuggestionChip)]) -> [SuggestionChip] {
        let sorted = candidates.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }
        var seenLabels = Set<String>()
        var ranked: [SuggestionChip] = []
        for entry in sorted {
            guard ranked.count < 3 else { break }
            guard seenLabels.insert(entry.element.chip.label).inserted else { continue }
            ranked.append(entry.element.chip)
        }
        if ranked.count < 3 {
            for fallbackChip in fallback {
                guard ranked.count < 3 else { break }
                guard seenLabels.insert(fallbackChip.label).inserted else { continue }
                ranked.append(fallbackChip)
            }
        }
        return ranked
    }

    /// Returns the most-recent Monday that is <= `date`. Mirrors
    /// `StreakEngine.mondayOnOrBefore` / `TrainingPlanStore.mondayOfWeek`'s
    /// identical ISO-8601 math so this engine's notion of "this week"
    /// lines up exactly with the weekly-activity data it's reading.
    private static func mondayOnOrBefore(_ date: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // ISO 8601: 2 = Monday
        return calendar.date(from: comps) ?? date
    }
}
