import Foundation

/// On-device, pure-math prediction engine. Takes a pre-built `Snapshot` of
/// HealthKit-derived data and produces a single `Predictions` value. No
/// fetches, no side effects, no HealthKit imports — all I/O is the caller's
/// job. This makes the engine unit-testable and trivially fast.
public enum PredictionEngine {

    // MARK: - Snapshot

    public struct WorkoutSample: Equatable {
        public let category: ActivityCategory
        public let weekday: Int          // 1...7 (Sunday = 1, matches Calendar.component(.weekday:))
        public let hour: Int             // 0...23
        public let durationMinutes: Double

        public init(category: ActivityCategory, weekday: Int, hour: Int, durationMinutes: Double) {
            self.category = category
            self.weekday = weekday
            self.hour = hour
            self.durationMinutes = durationMinutes
        }
    }

    public struct Snapshot {
        public let now: Date
        public let hasWatchClassData: Bool

        // Last night's most-recent-non-zero values (caller looked these up
        // from history; 0 / nil means "no recent data we can use").
        public let lastNightSleepHours: Double
        public let lastNightHRV: Double?
        public let lastNightRHR: Double?

        // 28-day histories. Pass only non-zero days where a zero would be
        // misleading (HRV / RHR are sparse); pass all days for sleep so the
        // baseline reflects honest variance.
        public let hrvHistory28: [Double]
        public let rhrHistory28: [Double]
        public let sleepHistory28NonZero: [Double]

        // 30-day daily arrays (chronological, oldest → newest, ZERO-FILLED for
        // missing days — illness-warning & correlation engine align by index).
        // A zero means "no valid reading that day" and is excluded after lag
        // alignment / windowing by the consumers.
        public let hrvHistory30: [Double]
        public let rhrHistory30: [Double]
        public let sleepHistory30: [Double]
        public let stepsHistory30: [Double]
        public let activeEnergyHistory30: [Double]
        public let hydrationHistory30: [Double]
        public let mindfulMinutesHistory30: [Double]

        // Last 14 days (chronological, oldest → newest, includes zeros so
        // empty days don't lie about pace).
        public let stepsHistory14: [Double]
        public let activeEnergyHistory14: [Double]
        public let exerciseMinutesHistory14: [Double]

        // Today's running totals so far.
        public let stepsToday: Double
        public let activeEnergyToday: Double
        public let exerciseMinutesToday: Double

        // Pre-aggregated training load. ACWR = acute / (chronic / 4).
        public let acuteLoadMinutes: Double      // sum of workout minutes in last 7 days
        public let chronicLoadMinutes: Double    // sum of workout minutes in last 28 days

        // 28 zero-filled daily kcal-loads, oldest -> newest (kcal per workout;
        // duration-min x 8 proxy when energy missing). Periodization input.
        public let dailyKcalLoad28: [Double]

        // 28-day workouts with weekday/hour/category for pattern detection.
        public let workouts28: [WorkoutSample]

        // 24 hourly step buckets for today (index = hour-of-day).
        public let hourlyStepsToday: [Double]

        // Number of days in step history with non-zero data (baseline gate).
        public let stepsHistoryNonZeroDayCount: Int

        // MARK: Health Meter inputs
        // Body composition (nil when user hasn't entered them in About You).
        public let heightCm: Double?
        public let weightKg: Double?

        // Nutrition. Today's value is the running sum; history is daily totals
        // for the last 7 days (oldest → newest, empty days zero-filled).
        public let dietaryCaloriesToday: Double
        public let dietaryCalories7Day: [Double]
        public let dietaryProteinToday: Double

        // Hydration mirror for the lifestyle subscore.
        public let hydrationToday: Double
        public let hydration7Day: [Double]

        // Mindful minutes (lifestyle subscore).
        public let mindfulMinutes7Day: [Double]

        // VO₂max — fitness percentile signal (latest reading).
        public let vo2Max: Double?

        // Walking gait quality (lifestyle subscore on iPhone-only).
        public let walkingSpeedToday: Double?
        public let walkingAsymmetryToday: Double?

        // User-logged symptoms over the last 14 days (chronological). Used to
        // CORROBORATE the illness early-warning — they never trigger it alone.
        public let recentSymptoms: [SymptomEntry]

        // Goal-suggestion inputs. `goalHistories28` maps a metric rawValue to 28
        // zero-filled daily values (oldest → newest); `userGoals` maps the same
        // rawValue to the user's current daily goal. Only isUserConfigurableGoal
        // metrics are populated.
        public let goalHistories28: [String: [Double]]
        public let userGoals: [String: Double]

        public init(now: Date,
                    hasWatchClassData: Bool,
                    lastNightSleepHours: Double,
                    lastNightHRV: Double?,
                    lastNightRHR: Double?,
                    hrvHistory28: [Double],
                    rhrHistory28: [Double],
                    sleepHistory28NonZero: [Double],
                    hrvHistory30: [Double] = [],
                    rhrHistory30: [Double] = [],
                    sleepHistory30: [Double] = [],
                    stepsHistory30: [Double] = [],
                    activeEnergyHistory30: [Double] = [],
                    hydrationHistory30: [Double] = [],
                    mindfulMinutesHistory30: [Double] = [],
                    stepsHistory14: [Double],
                    activeEnergyHistory14: [Double],
                    exerciseMinutesHistory14: [Double],
                    stepsToday: Double,
                    activeEnergyToday: Double,
                    exerciseMinutesToday: Double,
                    acuteLoadMinutes: Double,
                    chronicLoadMinutes: Double,
                    dailyKcalLoad28: [Double] = [],
                    workouts28: [WorkoutSample],
                    hourlyStepsToday: [Double],
                    stepsHistoryNonZeroDayCount: Int,
                    heightCm: Double? = nil,
                    weightKg: Double? = nil,
                    dietaryCaloriesToday: Double = 0,
                    dietaryCalories7Day: [Double] = [],
                    dietaryProteinToday: Double = 0,
                    hydrationToday: Double = 0,
                    hydration7Day: [Double] = [],
                    mindfulMinutes7Day: [Double] = [],
                    vo2Max: Double? = nil,
                    walkingSpeedToday: Double? = nil,
                    walkingAsymmetryToday: Double? = nil,
                    recentSymptoms: [SymptomEntry] = [],
                    goalHistories28: [String: [Double]] = [:],
                    userGoals: [String: Double] = [:]) {
            self.now = now
            self.hasWatchClassData = hasWatchClassData
            self.lastNightSleepHours = lastNightSleepHours
            self.lastNightHRV = lastNightHRV
            self.lastNightRHR = lastNightRHR
            self.hrvHistory28 = hrvHistory28
            self.rhrHistory28 = rhrHistory28
            self.sleepHistory28NonZero = sleepHistory28NonZero
            self.hrvHistory30 = hrvHistory30
            self.rhrHistory30 = rhrHistory30
            self.sleepHistory30 = sleepHistory30
            self.stepsHistory30 = stepsHistory30
            self.activeEnergyHistory30 = activeEnergyHistory30
            self.hydrationHistory30 = hydrationHistory30
            self.mindfulMinutesHistory30 = mindfulMinutesHistory30
            self.stepsHistory14 = stepsHistory14
            self.activeEnergyHistory14 = activeEnergyHistory14
            self.exerciseMinutesHistory14 = exerciseMinutesHistory14
            self.stepsToday = stepsToday
            self.activeEnergyToday = activeEnergyToday
            self.exerciseMinutesToday = exerciseMinutesToday
            self.acuteLoadMinutes = acuteLoadMinutes
            self.chronicLoadMinutes = chronicLoadMinutes
            self.dailyKcalLoad28 = dailyKcalLoad28
            self.workouts28 = workouts28
            self.hourlyStepsToday = hourlyStepsToday
            self.stepsHistoryNonZeroDayCount = stepsHistoryNonZeroDayCount
            self.heightCm = heightCm
            self.weightKg = weightKg
            self.dietaryCaloriesToday = dietaryCaloriesToday
            self.dietaryCalories7Day = dietaryCalories7Day
            self.dietaryProteinToday = dietaryProteinToday
            self.hydrationToday = hydrationToday
            self.hydration7Day = hydration7Day
            self.mindfulMinutes7Day = mindfulMinutes7Day
            self.vo2Max = vo2Max
            self.walkingSpeedToday = walkingSpeedToday
            self.walkingAsymmetryToday = walkingAsymmetryToday
            self.recentSymptoms = recentSymptoms
            self.goalHistories28 = goalHistories28
            self.userGoals = userGoals
        }
    }

    // MARK: - Top-level

    public static func computeAll(snapshot s: Snapshot) -> Predictions {
        // Baseline gate: need at least 7 days of step history before any
        // prediction is honest. Below that, render the "Building baseline" state
        // and skip AI enrichment entirely.
        let needed = 7
        let have = s.stepsHistoryNonZeroDayCount
        if have < needed {
            return Predictions(generatedAt: s.now,
                               aiEnrichmentStatus: .skipped,
                               insufficientHistoryDays: needed - have)
        }
        let recovery = predictRecoveryReadiness(snapshot: s)
        let nextWorkout = predictNextWorkout(snapshot: s)
        let trajectories = predictGoalTrajectories(snapshot: s)
        let sedentary = detectSedentaryAlert(snapshot: s)
        let anomalies = detectAnomalies(snapshot: s)
        let healthMeter = computeHealthMeter(snapshot: s)
        let illnessWarning = computeIllnessWarning(snapshot: s)
        let correlations = computeCorrelations(snapshot: s)
        let periodization = computePeriodization(snapshot: s)
        let goalSuggestions = computeGoalSuggestions(snapshot: s)
        let sleepForecast = computeSleepForecast(snapshot: s)
        return Predictions(
            generatedAt: s.now,
            recovery: recovery,
            nextWorkout: nextWorkout,
            trajectories: trajectories,
            sedentary: sedentary,
            healthMeter: healthMeter,
            anomalies: anomalies,
            illnessWarning: illnessWarning,
            correlations: correlations,
            periodization: periodization,
            goalSuggestions: goalSuggestions,
            sleepForecast: sleepForecast,
            aiEnrichmentStatus: .pending,
            insufficientHistoryDays: nil
        )
    }

    // MARK: - Anomaly Detection

    /// Flags metrics that deviated > 1.5σ from the user's own baseline in
    /// the concerning direction. Only signals that complete daily (sleep) or
    /// represent a single most-recent reading (RHR, HRV) — running totals
    /// like steps / energy are covered by GoalTrajectory instead.
    public static func detectAnomalies(snapshot s: Snapshot) -> [Anomaly] {
        var out: [Anomaly] = []

        // Sleep: low is concerning
        if s.lastNightSleepHours > 0,
           let a = anomalyOrNil(metric: .sleep,
                                today: s.lastNightSleepHours,
                                baselineValues: s.sleepHistory28NonZero,
                                concerningDirection: .low) {
            out.append(a)
        }

        // RHR: high is concerning (Watch users only)
        if let lastRHR = s.lastNightRHR, lastRHR > 0,
           let a = anomalyOrNil(metric: .restingHeartRate,
                                today: lastRHR,
                                baselineValues: s.rhrHistory28,
                                concerningDirection: .high) {
            out.append(a)
        }

        // HRV: low is concerning (Watch users only)
        if let lastHRV = s.lastNightHRV, lastHRV > 0,
           let a = anomalyOrNil(metric: .hrv,
                                today: lastHRV,
                                baselineValues: s.hrvHistory28,
                                concerningDirection: .low) {
            out.append(a)
        }

        return out
    }

    private enum AnomalyDirection { case low, high }

    private static func anomalyOrNil(metric: HealthMetricType,
                                     today: Double,
                                     baselineValues: [Double],
                                     concerningDirection: AnomalyDirection) -> Anomaly? {
        let nonZero = baselineValues.filter { $0 > 0 }
        guard nonZero.count >= 7 else { return nil }
        let m = mean(nonZero)
        let sd = stdDev(nonZero, mean: m)
        // Need real variance — if the baseline is flat, any reading is "normal."
        guard sd > 0.001 else { return nil }
        let z = (today - m) / sd
        let concerning: Bool
        switch concerningDirection {
        case .low:  concerning = z <= -1.5
        case .high: concerning = z >= 1.5
        }
        guard concerning else { return nil }
        let severity: AnomalySeverity
        switch abs(z) {
        case 2.5...:      severity = .high
        case 1.8..<2.5:   severity = .moderate
        default:          severity = .low
        }
        return Anomaly(
            metric: metric,
            direction: concerningDirection == .low ? "low" : "high",
            zScore: z,
            today: today,
            baseline: m,
            severity: severity,
            interpretation: nil
        )
    }

    // MARK: - Illness Early-Warning

    /// Surfaces an `IllnessWarning` when resting heart rate, HRV, and sleep all
    /// drift in the strain direction for ≥ 2 consecutive days ending today:
    ///   • RHR ≥ +4 bpm above the 28-day baseline,
    ///   • HRV ≥ 12% below baseline,
    ///   • sleep below the user's own baseline (cumulative debt > 1h).
    /// Baselines are the mean of non-zero days EXCLUDING the flagged window.
    /// Watch-less users (no RHR/HRV data) get nil — never a guess. This is NOT
    /// a diagnosis; the explanation frames it as early strain signals only.
    public static func computeIllnessWarning(snapshot s: Snapshot) -> IllnessWarning? {
        let rhr = s.rhrHistory30
        let hrv = s.hrvHistory30
        let sleep = s.sleepHistory30
        // Need the arrays aligned by day for the lookback. If any is empty we
        // can't evaluate that day honestly.
        guard !rhr.isEmpty, !hrv.isEmpty, !sleep.isEmpty else { return nil }
        // Watch-less: no HRV/RHR readings at all → bail, never guess.
        guard rhr.contains(where: { $0 > 0 }), hrv.contains(where: { $0 > 0 }) else { return nil }

        let n = min(rhr.count, min(hrv.count, sleep.count))
        guard n >= 4 else { return nil }
        // Index from the newest end so "today" is the last element of each.
        let rhrW = Array(rhr.suffix(n))
        let hrvW = Array(hrv.suffix(n))
        let sleepW = Array(sleep.suffix(n))

        // Walk backwards from today counting consecutive days where ALL THREE
        // strain conditions hold. Baselines are recomputed to EXCLUDE the
        // flagged window each step (mean of non-zero days before the window).
        let maxWindow = min(n - 1, 5) // cap; need at least 1 day outside for baseline
        var bestDays = 0
        var bestRhrDelta = 0.0, bestHrvDrop = 0.0, bestSleepDebt = 0.0
        var bestRhrToday = 0.0, bestRhrBase = 0.0
        var bestHrvToday = 0.0, bestHrvBase = 0.0
        var bestSleepBase = 0.0

        for windowLen in stride(from: 2, through: maxWindow, by: 1) {
            let windowStart = n - windowLen
            // Baseline = non-zero days strictly before the window.
            let rhrBaseDays = Array(rhrW.prefix(windowStart)).filter { $0 > 0 }
            let hrvBaseDays = Array(hrvW.prefix(windowStart)).filter { $0 > 0 }
            let sleepBaseDays = Array(sleepW.prefix(windowStart)).filter { $0 > 0 }
            guard rhrBaseDays.count >= 3, hrvBaseDays.count >= 3, sleepBaseDays.count >= 3 else { continue }
            let rhrBase = mean(rhrBaseDays)
            let hrvBase = mean(hrvBaseDays)
            let sleepBase = mean(sleepBaseDays)
            guard rhrBase > 0, hrvBase > 0, sleepBase > 0 else { continue }

            // Every day in the window must satisfy all three conditions with
            // valid (non-zero) readings.
            var allHold = true
            var sleepDebt = 0.0
            for i in windowStart..<n {
                let dayRhr = rhrW[i], dayHrv = hrvW[i], daySleep = sleepW[i]
                guard dayRhr > 0, dayHrv > 0, daySleep > 0 else { allHold = false; break }
                let rhrUp = dayRhr - rhrBase
                let hrvDownPct = (hrvBase - dayHrv) / hrvBase * 100.0
                let sleepShort = daySleep < sleepBase
                if rhrUp >= 4.0 && hrvDownPct >= 12.0 && sleepShort {
                    sleepDebt += (sleepBase - daySleep)
                } else {
                    allHold = false; break
                }
            }
            guard allHold, sleepDebt > 1.0 else { continue }

            if windowLen > bestDays {
                bestDays = windowLen
                let todayRhr = rhrW[n - 1], todayHrv = hrvW[n - 1]
                bestRhrDelta = todayRhr - rhrBase
                bestHrvDrop = (hrvBase - todayHrv) / hrvBase * 100.0
                bestSleepDebt = sleepDebt
                bestRhrToday = todayRhr; bestRhrBase = rhrBase
                bestHrvToday = todayHrv; bestHrvBase = hrvBase
                bestSleepBase = sleepBase
            }
        }

        guard bestDays >= 2 else { return nil }
        guard bestRhrDelta.isFinite, bestHrvDrop.isFinite, bestSleepDebt.isFinite else { return nil }

        var severity: AnomalySeverity =
            (bestDays >= 3 || (bestRhrDelta >= 8 && bestHrvDrop >= 20)) ? .high : .moderate

        // ---------- Symptom corroboration (never a trigger) ----------
        // The flagged window covers the last `bestDays` calendar days ending
        // today. Corroborate with symptoms logged inside that window or in the
        // 2 days immediately before it. Distinct symptom-days INSIDE the window
        // (>= 2) bump .moderate → .high. Symptoms alone never surface a warning —
        // we only reach here because the RHR+HRV+sleep gate already held.
        let cal = Calendar.current
        let today0 = cal.startOfDay(for: s.now)
        let windowStartDay = cal.date(byAdding: .day, value: -(bestDays - 1), to: today0) ?? today0
        let corroborationStart = cal.date(byAdding: .day, value: -2, to: windowStartDay) ?? windowStartDay

        var corroboratingSymptoms: [SymptomEntry] = []
        var distinctInWindowDays = Set<Date>()
        for entry in s.recentSymptoms {
            let day = cal.startOfDay(for: entry.date)
            // Inside corroboration range [windowStart - 2 days, today].
            guard day >= corroborationStart, day <= today0 else { continue }
            corroboratingSymptoms.append(entry)
            // Distinct days strictly inside the flagged window drive the bump.
            if day >= windowStartDay {
                distinctInWindowDays.insert(day)
            }
        }

        if distinctInWindowDays.count >= 2 && severity == .moderate {
            severity = .high
        }

        let todaySleep = sleepW[n - 1]
        var bullets: [String] = []
        bullets.append("RHR \(Int(bestRhrToday.rounded())) vs \(Int(bestRhrBase.rounded())) baseline (+\(Int(bestRhrDelta.rounded())))")
        bullets.append("HRV \(Int(bestHrvToday.rounded())) vs \(Int(bestHrvBase.rounded())) baseline (-\(Int(bestHrvDrop.rounded()))%)")
        bullets.append("Sleep \(formattedDuration(todaySleep)) vs \(formattedDuration(bestSleepBase)) baseline — \(formattedDuration(bestSleepDebt)) debt over \(bestDays) days")
        if !corroboratingSymptoms.isEmpty {
            // Most recent first, de-duplicate by name, cap at 3.
            var seenNames = Set<String>()
            var listed: [String] = []
            for entry in corroboratingSymptoms.sorted(by: { $0.date > $1.date }) {
                guard !seenNames.contains(entry.name) else { continue }
                seenNames.insert(entry.name)
                listed.append("\(entry.name) (\(entry.severity))")
                if listed.count == 3 { break }
            }
            bullets.append("Logged symptoms: \(listed.joined(separator: ", "))")
        }
        bullets.append("Pattern has held \(bestDays) days — these are early strain signals, not a diagnosis.")

        return IllnessWarning(
            severity: severity,
            rhrDeltaBpm: bestRhrDelta,
            hrvDropPct: bestHrvDrop,
            sleepDebtHours: bestSleepDebt,
            consecutiveDays: bestDays,
            explanation: PredictionExplanation(bullets: bullets)
        )
    }

    // MARK: - Correlation Engine

    private struct CorrelationCandidate {
        let driver: HealthMetricType
        let outcome: HealthMetricType
        let lag: Int
    }

    /// Pearson r over 30-day daily arrays for a fixed candidate set. Pairs days
    /// only when BOTH values are non-zero/valid after lag alignment; requires
    /// ≥ 12 overlapping days and |r| ≥ 0.45. Returns the top 3 by |r|. Insights
    /// are deterministic, direction-aware, and avoid causality claims.
    public static func computeCorrelations(snapshot s: Snapshot) -> [MetricCorrelation] {
        func series(_ m: HealthMetricType) -> [Double] {
            switch m {
            case .sleep:             return s.sleepHistory30
            case .hrv:               return s.hrvHistory30
            case .restingHeartRate:  return s.rhrHistory30
            case .steps:             return s.stepsHistory30
            case .activeEnergy:      return s.activeEnergyHistory30
            case .hydration:         return s.hydrationHistory30
            case .mindfulMinutes:    return s.mindfulMinutesHistory30
            default:                 return []
            }
        }

        let candidates: [CorrelationCandidate] = [
            .init(driver: .sleep,          outcome: .hrv,              lag: 1),
            .init(driver: .sleep,          outcome: .restingHeartRate, lag: 1),
            .init(driver: .steps,          outcome: .sleep,            lag: 1),
            .init(driver: .activeEnergy,   outcome: .sleep,            lag: 1),
            .init(driver: .mindfulMinutes, outcome: .hrv,              lag: 1),
            .init(driver: .hydration,      outcome: .steps,            lag: 0),
            .init(driver: .sleep,          outcome: .steps,            lag: 1)
        ]

        var results: [MetricCorrelation] = []
        for c in candidates {
            let a = series(c.driver)
            let b = series(c.outcome)
            guard !a.isEmpty, !b.isEmpty else { continue }

            // Align: driver day i predicts outcome day i+lag. Pair only where
            // both are valid (> 0).
            var xs: [Double] = []
            var ys: [Double] = []
            let count = min(a.count, b.count)
            for i in 0..<count {
                let j = i + c.lag
                guard j < b.count else { break }
                let dv = a[i], ov = b[j]
                if dv > 0 && ov > 0 {
                    xs.append(dv)
                    ys.append(ov)
                }
            }
            guard xs.count >= 12 else { continue }
            guard let r = pearson(xs, ys) else { continue }
            guard r.isFinite, abs(r) >= 0.45 else { continue }

            let insight = correlationInsight(driver: c.driver, outcome: c.outcome,
                                             lag: c.lag, r: r, days: xs.count)
            results.append(MetricCorrelation(
                metricA: c.driver,
                metricB: c.outcome,
                lagDays: c.lag,
                r: r,
                sampleDays: xs.count,
                insight: insight
            ))
        }

        return Array(results.sorted { abs($0.r) > abs($1.r) }.prefix(3))
    }

    private static func correlationInsight(driver: HealthMetricType, outcome: HealthMetricType,
                                           lag: Int, r: Double, days: Int) -> String {
        let positive = r > 0
        let rStr = String(format: "%.2f", r)
        let nextDay = lag == 1 ? "next-day " : ""

        func driverPhrase(_ m: HealthMetricType) -> String {
            switch m {
            case .sleep:          return "sleep more"
            case .steps:          return "take more steps"
            case .activeEnergy:   return "burn more energy"
            case .mindfulMinutes: return "spend more time on mindfulness"
            case .hydration:      return "drink more water"
            default:              return "log more \(m.displayName.lowercased())"
            }
        }
        func outcomeUp(_ m: HealthMetricType, up: Bool) -> String {
            let dir = up ? "higher" : "lower"
            switch m {
            case .hrv:              return "\(nextDay)HRV tends to run \(dir)"
            case .restingHeartRate: return "\(nextDay)resting heart rate tends to run \(dir)"
            case .sleep:            return "\(nextDay)sleep tends to run \(dir)"
            case .steps:            return "\(nextDay)step count tends to run \(dir)"
            default:                return "\(nextDay)\(m.displayName.lowercased()) tends to run \(dir)"
            }
        }

        return "Days you \(driverPhrase(driver)), \(outcomeUp(outcome, up: positive)) (r \(rStr), \(days) days)"
    }

    // MARK: - Periodization

    /// Classifies the current training phase from 4 weeks of daily kcal-load.
    /// Chunks `dailyKcalLoad28` oldest→newest into 4 weeks of 7. Current-week
    /// load is compared to the mean of the prior 3 weeks (counting only weeks
    /// that carried any load). Phase rules are deterministic and blend the
    /// week-over-week trend with ACWR from the pre-aggregated load minutes.
    /// Returns nil when there isn't enough workout signal to classify honestly.
    public static func computePeriodization(snapshot s: Snapshot) -> PeriodizationStatus? {
        let loads = s.dailyKcalLoad28
        guard loads.count == 28 else { return nil }

        // Honest signal gate: enough non-zero workout days to classify.
        let nonZeroDays = loads.filter { $0 > 0 }.count
        let enoughSignal = nonZeroDays >= 6
            || (s.chronicLoadMinutes > 0 && nonZeroDays >= 4)
        guard enoughSignal else { return nil }

        // Chunk oldest→newest into 4 weeks of 7.
        let week1 = Array(loads[0..<7])
        let week2 = Array(loads[7..<14])
        let week3 = Array(loads[14..<21])
        let week4 = Array(loads[21..<28])

        let weekLoad = week4.reduce(0, +)

        // Baseline = mean of prior-3-week sums, counting only weeks with load.
        let priorSums = [week1, week2, week3].map { $0.reduce(0, +) }
        let loadedPriorSums = priorSums.filter { $0 > 0 }
        let baseline = loadedPriorSums.isEmpty
            ? 0.0
            : loadedPriorSums.reduce(0, +) / Double(loadedPriorSums.count)

        // Trend %, clamped to finite.
        let rawTrend = (weekLoad - baseline) / max(baseline, 1.0) * 100.0
        let trend = rawTrend.isFinite ? rawTrend : 0.0

        // ACWR from pre-aggregated load minutes (acute / weekly-equivalent chronic).
        let acwr = s.acuteLoadMinutes / max(s.chronicLoadMinutes / 4.0, 1.0)
        let acwrFinite = acwr.isFinite ? acwr : 0.0

        // Optional recovery score for the recover-vs-deload split.
        let recoveryScore = predictRecoveryReadiness(snapshot: s)?.score

        let phase: String
        if trend >= 15.0 && acwrFinite <= 1.3 {
            phase = "build"
        } else if trend >= 15.0 {
            phase = "peak"
        } else if trend <= -30.0 {
            if let rs = recoveryScore, rs < 50 { phase = "recover" }
            else { phase = "deload" }
        } else {
            phase = "steady"
        }

        let recommendation: String
        switch phase {
        case "build":   recommendation = "Load is ramping — keep ~10% weekly increases and protect sleep."
        case "peak":    recommendation = "Strain is high vs your base — plan a deload inside the next week."
        case "deload":  recommendation = "Lighter week — good time to absorb fitness; keep movement easy."
        case "recover": recommendation = "Low load + low recovery — prioritize rest, easy walks, and sleep."
        default:        recommendation = "Load is consistent with your 4-week base."
        }

        let confidence: PredictionConfidence = nonZeroDays >= 10 ? .high : .medium

        return PeriodizationStatus(
            phase: phase,
            weekLoad: weekLoad.isFinite ? weekLoad : 0.0,
            baselineWeekLoad: baseline.isFinite ? baseline : 0.0,
            loadTrendPct: trend,
            recommendation: recommendation,
            confidence: confidence
        )
    }

    // MARK: - Sleep Forecast

    /// Next-night sleep forecast via a stratified comparison of the user's own
    /// day-activity → next-night-sleep pairs. Deliberately NOT regression at this
    /// sample size — instead it buckets days by a composite activity score into
    /// HIGH / MID / LOW strata, takes each stratum's mean next-night sleep, then
    /// classifies TODAY by the same score and reports the matched stratum's mean.
    /// The basis sentence quotes the user's real numbers. Returns nil when there
    /// aren't ≥ 10 valid pairs or the sleep history is all zeros — never a guess.
    public static func computeSleepForecast(snapshot s: Snapshot) -> SleepForecast? {
        let sleep = s.sleepHistory30
        let steps = s.stepsHistory30
        let energy = s.activeEnergyHistory30
        let kcal = s.dailyKcalLoad28

        // Honest nil when the sleep series is empty or all zeros.
        guard !sleep.isEmpty, sleep.contains(where: { $0 > 0 }) else { return nil }

        // Align activity series to the sleep array's newest-anchored window. All
        // arrays are zero-filled daily oldest→newest ending today, so anchoring
        // every series to sleep's last index keeps day i comparable across them.
        let nDays = sleep.count
        func aligned(_ arr: [Double]) -> [Double] {
            guard !arr.isEmpty else { return Array(repeating: 0, count: nDays) }
            if arr.count >= nDays { return Array(arr.suffix(nDays)) }
            // Pad missing older days with zeros at the front (treated as invalid).
            return Array(repeating: 0, count: nDays - arr.count) + arr
        }
        let stepsA = aligned(steps)
        let energyA = aligned(energy)
        let kcalA = aligned(kcal)

        // dailyKcalLoad28 alignment check: when it carries 28 entries its last
        // bucket is today (same anchor as the 30-day arrays). If it's empty or
        // short, aligned() zero-pads the front, so today's load may read 0 — the
        // composite score below tolerates that by averaging only available ratios.
        let kcalLastIsToday = kcal.count >= nDays || kcal.count == 28

        // ---------- Per-day medians for normalization (non-zero only) ----------
        func nonZeroMedian(_ arr: [Double]) -> Double {
            let nz = arr.filter { $0 > 0 && $0.isFinite }
            return nz.isEmpty ? 0 : median(nz)
        }
        let stepsMed = nonZeroMedian(stepsA)
        let energyMed = nonZeroMedian(energyA)
        let kcalMed = nonZeroMedian(kcalA)

        // Composite activity score for a single day: mean of available ratios
        // (each feature normalized by its own non-zero median). nil when no
        // feature is available that day.
        func activityScore(steps sv: Double, energy ev: Double, kcal kv: Double) -> Double? {
            var ratios: [Double] = []
            if stepsMed > 0, sv > 0, sv.isFinite { ratios.append(sv / stepsMed) }
            if energyMed > 0, ev > 0, ev.isFinite { ratios.append(ev / energyMed) }
            if kcalMed > 0, kv > 0, kv.isFinite { ratios.append(kv / kcalMed) }
            guard !ratios.isEmpty else { return nil }
            let m = mean(ratios)
            return m.isFinite ? m : nil
        }

        // ---------- Build day→next-night pairs ----------
        // Day i activity paired with sleep[i+1] when sleep[i+1] > 0 and the day
        // has a computable activity score. i ranges over 0..<nDays-1.
        struct Pair { let score: Double; let nextSleep: Double }
        var pairs: [Pair] = []
        for i in 0..<(nDays - 1) {
            let nextSleep = sleep[i + 1]
            guard nextSleep > 0, nextSleep.isFinite else { continue }
            guard let score = activityScore(steps: stepsA[i], energy: energyA[i], kcal: kcalA[i]) else { continue }
            pairs.append(Pair(score: score, nextSleep: nextSleep))
        }
        guard pairs.count >= 10 else { return nil }

        // ---------- Baseline: median of all valid next-night values ----------
        let baseline = median(pairs.map { $0.nextSleep })
        guard baseline.isFinite, baseline > 0 else { return nil }

        // ---------- Strata thresholds (percentiles of pair-day scores) ----------
        let scores = pairs.map { $0.score }
        let p75 = percentile(scores, 0.75)
        let p25 = percentile(scores, 0.25)
        guard p75.isFinite, p25.isFinite else { return nil }
        // Degenerate: all scores are identical → strata are meaningless.
        // Fall through to the "typical day" / overall-median path by keeping
        // highPairs and lowPairs empty so the comparisons below never fire.
        let stratified = p75 > p25
        let highPairs = stratified ? pairs.filter { $0.score > p75 } : []
        let lowPairs  = stratified ? pairs.filter { $0.score < p25 } : []
        let midPairs  = stratified ? pairs.filter { $0.score >= p25 && $0.score <= p75 } : pairs

        let overallMedian = baseline
        func stratumMean(_ ps: [Pair]) -> Double? {
            guard ps.count >= 3 else { return nil }
            let m = mean(ps.map { $0.nextSleep })
            return m.isFinite ? m : nil
        }
        let highMean = stratumMean(highPairs)
        let lowMean  = stratumMean(lowPairs)
        let midMean  = stratumMean(midPairs)

        // ---------- Classify TODAY ----------
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: s.now)

        // Today's running totals normalized by the same medians. Before 16:00 we
        // can't classify the day honestly — fall back to "typical day".
        let todayScore: Double? = activityScore(
            steps: s.stepsToday,
            energy: s.activeEnergyToday,
            kcal: kcalLastIsToday ? (kcalA.last ?? 0) : 0
        )
        // Project today's partial score to a full-day estimate so it is
        // comparable against the full-day percentile thresholds.  Cap the
        // divisor at 0.5 so we never amplify by more than 2× (handles the
        // edge case of computing right at 16:00 when ~67% has elapsed).
        let projectedScore: Double? = todayScore.map { raw in
            let frac = elapsedDayFraction(at: s.now)
            return raw / max(frac, 0.5)
        }

        let stratum: String       // "high" | "low" | "mid"
        let deltaDriver: String
        let matchedPairs: [Pair]
        let predictedRaw: Double

        if nowHour >= 16, let ts = projectedScore, stratified {
            if ts > p75 {
                stratum = "high"; deltaDriver = "high load"
                matchedPairs = highPairs
                predictedRaw = highMean ?? overallMedian
            } else if ts < p25 {
                stratum = "low"; deltaDriver = "low activity"
                matchedPairs = lowPairs
                predictedRaw = lowMean ?? overallMedian
            } else {
                stratum = "mid"; deltaDriver = "typical day"
                matchedPairs = midPairs
                predictedRaw = midMean ?? overallMedian
            }
        } else {
            // Too early (or no score yet) — typical day, overall median forecast.
            stratum = "mid"; deltaDriver = "typical day"
            matchedPairs = midPairs
            predictedRaw = overallMedian
        }

        let predicted = clamp(predictedRaw, 3.0, 12.0)
        guard predicted.isFinite, baseline.isFinite else { return nil }

        // ---------- Basis sentence (quotes real numbers) ----------
        let basis: String
        let matchedCount = matchedPairs.count
        switch stratum {
        case "high":
            basis = "After high-activity days you've averaged \(oneDecimal(predicted))h vs your \(oneDecimal(baseline))h median (\(matchedCount) nights)."
        case "low":
            basis = "After low-activity days you've averaged \(oneDecimal(predicted))h vs your \(oneDecimal(baseline))h median (\(matchedCount) nights)."
        default:
            if nowHour >= 16, !matchedPairs.isEmpty {
                basis = "On typical-activity days you've averaged \(oneDecimal(predicted))h, close to your \(oneDecimal(baseline))h median (\(matchedCount) nights)."
            } else {
                basis = "Forecasting your \(oneDecimal(baseline))h median night from \(pairs.count) recent nights."
            }
        }

        // ---------- Confidence ----------
        // high: matched stratum ≥ 6 pairs AND |stratum mean - baseline| ≥ 0.4h.
        // medium: matched stratum ≥ 3 pairs. low: otherwise — but only emit at
        // low when ≥ 3 pairs in the matched stratum; else honest nil.
        let usedStratumDelta = abs(predicted - baseline)
        let confidence: PredictionConfidence
        if matchedCount >= 6 && usedStratumDelta >= 0.4 {
            confidence = .high
        } else if matchedCount >= 3 {
            confidence = .medium
        } else {
            // Matched stratum too thin to stand on. If we fell back to the
            // overall median (typical day before 16:00), the whole pair set
            // (≥ 10) backs it — emit at low. Otherwise honest nil.
            if deltaDriver == "typical day" && pairs.count >= 10 {
                confidence = .low
            } else {
                return nil
            }
        }

        return SleepForecast(
            predictedHours: predicted,
            baselineHours: baseline,
            deltaDriver: deltaDriver,
            basis: basis,
            confidence: confidence
        )
    }

    /// One-decimal hours string ("6.4", "7").
    private static func oneDecimal(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        if r == r.rounded() { return "\(Int(r.rounded()))" }
        return String(format: "%.1f", r)
    }

    // MARK: - Recovery Readiness

    public static func predictRecoveryReadiness(snapshot s: Snapshot) -> RecoveryReadiness? {
        // Sleep is the always-available signal — iPhone-only Sleep Schedule
        // writes inBed, so even Watch-less users get something. Require enough
        // days for a meaningful baseline.
        let minSleepDays = s.hasWatchClassData ? 7 : 14
        guard s.sleepHistory28NonZero.count >= minSleepDays else { return nil }

        let sleepMean = mean(s.sleepHistory28NonZero)
        let sleepStd = max(stdDev(s.sleepHistory28NonZero, mean: sleepMean), 0.5) // floor at 30 min so a tight sleeper doesn't get hypersensitive scoring
        let sleepZ = s.lastNightSleepHours > 0
            ? clamp((s.lastNightSleepHours - sleepMean) / sleepStd, -2.0, 2.0)
            : 0

        // Optional HRV / RHR — require ≥5 non-zero days and a non-nil "last night" value to weight them in.
        let hrvDays = s.hrvHistory28.filter { $0 > 0 }
        let rhrDays = s.rhrHistory28.filter { $0 > 0 }

        var hrvZ: Double = 0
        var rhrZInv: Double = 0
        var usedHRV = false
        var usedRHR = false

        if let lastHRV = s.lastNightHRV, lastHRV > 0, hrvDays.count >= 5 {
            let m = mean(hrvDays)
            let sd = max(stdDev(hrvDays, mean: m), 3.0) // ms floor
            hrvZ = clamp((lastHRV - m) / sd, -2.0, 2.0)
            usedHRV = true
        }
        if let lastRHR = s.lastNightRHR, lastRHR > 0, rhrDays.count >= 5 {
            let m = mean(rhrDays)
            let sd = max(stdDev(rhrDays, mean: m), 1.5) // bpm floor
            // Lower RHR is better → invert sign so positive = recovered.
            rhrZInv = clamp(-(lastRHR - m) / sd, -2.0, 2.0)
            usedRHR = true
        }

        // Training load — ACWR around 1.0 is sweet spot. Convert to a
        // -2...2 z-score-like "load freshness" indicator (loadZ_inverted).
        // Chronic window is 28 days vs acute 7, so divide chronic by 4.
        let chronicWeeklyEquivalent = max(s.chronicLoadMinutes / 4.0, 1.0)
        let acwr = s.acuteLoadMinutes / chronicWeeklyEquivalent
        // freshness = how close to optimal 1.0; deviation pulls negative.
        // |acwr - 1| of 0 → +1.0; 0.5 → 0; 1.0 → -1.0 (very over- or under-trained).
        let loadFreshness = clamp(1.0 - abs(acwr - 1.0) * 2.0, -2.0, 2.0)

        // Weighted blend.
        let watch = s.hasWatchClassData && usedHRV && usedRHR
        let raw: Double
        if watch {
            raw = 0.35 * hrvZ + 0.25 * rhrZInv + 0.25 * sleepZ + 0.15 * loadFreshness
        } else {
            raw = 0.65 * sleepZ + 0.35 * loadFreshness
        }

        // Map raw (~ -2...+2) → 0...100 around 50.
        let score = Int(clamp(50.0 + 25.0 * raw, 0, 100).rounded())

        // Label thresholds.
        let label: RecoveryLabel
        switch score {
        case 75...: label = .strong
        case 55...74: label = .moderate
        case 35...54: label = .low
        default: label = .rest
        }

        // Confidence:
        //   - high: watch user with HRV+RHR+sleep+load all participating
        //   - medium: iPhone-only OR missing one optional signal
        //   - low: only sleep contributed and history is just barely past the gate
        let confidence: PredictionConfidence
        if watch {
            confidence = .high
        } else if s.sleepHistory28NonZero.count >= 21 {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Bullets — gate on |subscore| ≥ 0.4 so we don't pad with noise.
        var bullets: [String] = []
        if usedHRV {
            if hrvZ >= 0.4 { bullets.append("HRV is above your 28-day baseline — autonomic system is relaxed.") }
            else if hrvZ <= -0.4 { bullets.append("HRV is below baseline — body's signaling some strain.") }
        }
        if usedRHR {
            if rhrZInv >= 0.4 { bullets.append("Resting heart rate is lower than usual — solid recovery sign.") }
            else if rhrZInv <= -0.4 { bullets.append("Resting heart rate is elevated — incomplete recovery.") }
        }
        if sleepZ >= 0.4 { bullets.append("Last night was \(formattedDuration(s.lastNightSleepHours)) — above your baseline.") }
        else if sleepZ <= -0.4 { bullets.append("Last night was \(formattedDuration(s.lastNightSleepHours)) — short for you.") }
        if loadFreshness <= -0.4 {
            if acwr > 1.5 {
                bullets.append("7-day training load is well above your 28-day average — high injury risk.")
            } else if acwr < 0.5 {
                bullets.append("Training has been light recently — you're fresh but detraining.")
            }
        }
        if !usedHRV && !usedRHR {
            bullets.append("Estimated from sleep + training load only. Pair an Apple Watch for HRV-based scoring.")
        }

        return RecoveryReadiness(
            score: score,
            label: label,
            confidence: confidence,
            usedHRV: usedHRV,
            usedRHR: usedRHR,
            explanation: PredictionExplanation(bullets: bullets)
        )
    }

    // MARK: - Next Likely Workout

    public static func predictNextWorkout(snapshot s: Snapshot) -> NextWorkoutForecast? {
        guard s.workouts28.count >= 3 else { return nil }

        let cal = Calendar.current
        let nowWeekday = cal.component(.weekday, from: s.now)
        let nowHour = cal.component(.hour, from: s.now)

        // If we're past 6pm and haven't trained yet, look at tomorrow instead
        // of trying to predict the rest of today.
        let predictTomorrow = nowHour >= 18
        let targetWeekday: Int
        if predictTomorrow {
            targetWeekday = (nowWeekday % 7) + 1
        } else {
            targetWeekday = nowWeekday
        }
        let weekdayLabel = predictTomorrow
            ? cal.shortWeekdaySymbols[(targetWeekday - 1) % 7]
            : "today"

        // Bucket: (hourBucket: hour / 3, category) for the target weekday.
        // 4 weekday repeats in 28 days → support = count / 4.
        let weekdaySamples = s.workouts28.filter { $0.weekday == targetWeekday }
        guard !weekdaySamples.isEmpty else { return nil }

        struct Key: Hashable { let bucket: Int; let cat: ActivityCategory }
        var counts: [Key: Int] = [:]
        var anyBucketCounts: [Int: Int] = [:]
        for sample in weekdaySamples {
            let bucket = sample.hour / 3
            counts[Key(bucket: bucket, cat: sample.category), default: 0] += 1
            anyBucketCounts[bucket, default: 0] += 1
        }

        let totalWeeks: Double = 4.0

        // First pass: best (bucket, category).
        if let top = counts.max(by: { $0.value < $1.value }) {
            let support = Double(top.value) / totalWeeks
            if top.value >= 2 && support >= 0.5 {
                let conf: PredictionConfidence = support >= 0.75 ? .high : .medium
                return NextWorkoutForecast(
                    category: top.key.cat,
                    startHour: top.key.bucket * 3,
                    endHour: top.key.bucket * 3 + 3,
                    confidence: conf,
                    support: support,
                    isCategoryFallback: false,
                    weekdayLabel: weekdayLabel
                )
            }
        }

        // Fallback: time-of-day pattern, any category.
        if let topBucket = anyBucketCounts.max(by: { $0.value < $1.value }) {
            let support = Double(topBucket.value) / totalWeeks
            if topBucket.value >= 2 && support >= 0.5 {
                let conf: PredictionConfidence = support >= 0.75 ? .high : .medium
                return NextWorkoutForecast(
                    category: .other,
                    startHour: topBucket.key * 3,
                    endHour: topBucket.key * 3 + 3,
                    confidence: conf,
                    support: support,
                    isCategoryFallback: true,
                    weekdayLabel: weekdayLabel
                )
            }
        }

        return nil
    }

    // MARK: - Goal Trajectory

    public static func predictGoalTrajectories(snapshot s: Snapshot) -> [GoalTrajectory] {
        let elapsedFraction = elapsedDayFraction(at: s.now)
        // Too early in the day to project reliably (~before 4:48 AM).
        guard elapsedFraction >= 0.20 else { return [] }

        var out: [GoalTrajectory] = []
        if let t = trajectory(metric: .steps,
                              today: s.stepsToday,
                              history14: s.stepsHistory14,
                              elapsedFraction: elapsedFraction) { out.append(t) }
        if let t = trajectory(metric: .activeEnergy,
                              today: s.activeEnergyToday,
                              history14: s.activeEnergyHistory14,
                              elapsedFraction: elapsedFraction) { out.append(t) }
        if let t = trajectory(metric: .exerciseMinutes,
                              today: s.exerciseMinutesToday,
                              history14: s.exerciseMinutesHistory14,
                              elapsedFraction: elapsedFraction) { out.append(t) }
        return out
    }

    private static func trajectory(metric: HealthMetricType,
                                   today: Double,
                                   history14: [Double],
                                   elapsedFraction: Double) -> GoalTrajectory? {
        let nonZero = history14.filter { $0 > 0 }
        guard nonZero.count >= 5 else { return nil }
        let baseline = mean(nonZero)
        guard baseline > 0 else { return nil }

        let expectedByNow = baseline * elapsedFraction
        let pace = today / max(expectedByNow, 1.0)
        let projectedEOD = today / max(elapsedFraction, 0.05)

        let status: TrajectoryStatus
        switch pace {
        case 1.10...: status = .aheadOfPace
        case 0.90..<1.10: status = .onPace
        case 0.60..<0.90: status = .behind
        default: status = .farBehind
        }

        // Confidence: more days of history → higher.
        let conf: PredictionConfidence = nonZero.count >= 10 ? .high : .medium

        return GoalTrajectory(
            metric: metric,
            currentValue: today,
            projectedEOD: projectedEOD,
            baselineEOD: baseline,
            pace: pace,
            status: status,
            confidence: conf
        )
    }

    // MARK: - Sedentary Alert

    public static func detectSedentaryAlert(snapshot s: Snapshot) -> SedentaryAlert? {
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: s.now)

        // Only active waking-window hours.
        guard nowHour >= 8 && nowHour <= 22 else { return nil }
        guard s.hourlyStepsToday.count == 24 else { return nil }

        // False-positive guard for post-permission-grant: if the entire
        // morning's buckets are 0 but the day total isn't, the user has
        // steps logged via a backfill / Watch sync that didn't bucket by
        // hour yet — don't fire.
        let bucketsSoFar = Array(s.hourlyStepsToday.prefix(nowHour))
        let anyActivityRecorded = bucketsSoFar.contains { $0 > 0 }
        let dayTotal = s.hourlyStepsToday.reduce(0, +)
        guard dayTotal > 0, anyActivityRecorded else { return nil }

        // Suppress if user has already moved more than usual today.
        let baselineDayTotal = mean(s.stepsHistory14.filter { $0 > 0 })
        if baselineDayTotal > 0 && dayTotal >= 0.8 * baselineDayTotal { return nil }

        // Count consecutive sub-250-step hours ending at currentHour - 1
        // (the current hour is in-progress, not finished, so we don't judge it).
        var quietHours = 0
        var lastActiveHour: Int? = nil
        var h = nowHour - 1
        while h >= 8 {
            let steps = s.hourlyStepsToday[h]
            if steps < 250 {
                quietHours += 1
                h -= 1
            } else {
                lastActiveHour = h
                break
            }
        }
        // Look further back if needed (before 8am) for the last active hour label only.
        if lastActiveHour == nil {
            var hh = 7
            while hh >= 0 {
                if s.hourlyStepsToday[hh] >= 250 {
                    lastActiveHour = hh
                    break
                }
                hh -= 1
            }
        }

        guard quietHours >= 2 else { return nil }

        let severity: SedentarySeverity = quietHours >= 4 ? .high : .moderate
        return SedentaryAlert(
            quietHours: quietHours,
            lastActiveHour: lastActiveHour,
            severity: severity,
            dayTotalSoFar: Int(dayTotal.rounded()),
            baselineDayTotal: Int(baselineDayTotal.rounded())
        )
    }

    // MARK: - Health Meter (composite wellness score)

    /// 0–100 composite blending activity / nutrition / body / vitals.
    /// Each sub-score caps independently and the total is the sum.
    /// Returns nil when the user has < 5 non-zero step days (insufficient
    /// data to compute anything honestly).
    public static func computeHealthMeter(snapshot s: Snapshot) -> HealthMeterScore? {
        guard s.stepsHistoryNonZeroDayCount >= 5 else { return nil }

        // ---------- Activity sub-score (0...25) ----------
        // Steps avg (0...14), active energy avg (0...8), workout volume (0...3).
        let stepsAvg = mean(s.stepsHistory14.filter { $0 > 0 })
        let activeAvg = mean(s.activeEnergyHistory14.filter { $0 > 0 })
        let stepsComp = clamp(stepsAvg / 10000.0, 0, 1.2) * 14.0 / 1.2
        let energyComp = clamp(activeAvg / 500.0, 0, 1.2) * 8.0 / 1.2
        // WHO recommends 150 min/week moderate activity.
        let loadComp = clamp(s.chronicLoadMinutes / 150.0, 0, 1.5) * 3.0 / 1.5
        let activityScore = Int((stepsComp + energyComp + loadComp).rounded())
        let activityCapped = min(25, max(0, activityScore))

        // ---------- Nutrition sub-score (0...25) ----------
        // Intake-to-TDEE ratio + hydration + protein adequacy.
        let intake7 = s.dietaryCalories7Day.filter { $0 > 0 }
        let mealsLoggedToday = s.dietaryCaloriesToday > 0
        let usedNutrition = !intake7.isEmpty || mealsLoggedToday
        var nutritionRaw: Double = 12  // neutral default when no diet data

        if usedNutrition {
            let avgIntake = intake7.isEmpty ? s.dietaryCaloriesToday : mean(intake7)
            let tdee = estimateTDEE(heightCm: s.heightCm, weightKg: s.weightKg,
                                    activeAvg: activeAvg)
            // Score peaks within ±15% of TDEE, decays beyond ±50%.
            let ratio = tdee > 0 ? avgIntake / tdee : 1.0
            let deviation = abs(ratio - 1.0)
            let calComp: Double
            switch deviation {
            case ..<0.15: calComp = 16
            case ..<0.30: calComp = 12
            case ..<0.50: calComp = 7
            default:      calComp = 3
            }
            nutritionRaw = calComp
            // Protein bonus: ≥1.2g/kg if weight known is "good"; ≥1.6g/kg "great".
            if let w = s.weightKg, w > 0, s.dietaryProteinToday > 0 {
                let perKg = s.dietaryProteinToday / w
                if perKg >= 1.6 { nutritionRaw += 4 }
                else if perKg >= 1.2 { nutritionRaw += 2 }
            }
        }

        // Hydration component (always available — even iPhone-only users log it)
        let hydAvg = mean(s.hydration7Day.filter { $0 > 0 })
        let hydComp = clamp(hydAvg / 2.5, 0, 1.0) * 5  // 2.5L target
        let nutritionScore = min(25, max(0, Int((nutritionRaw + hydComp).rounded())))

        // ---------- Body composition sub-score (0...15) ----------
        var usedBMI = false
        var bodyScore = 8  // neutral when no data
        if let h = s.heightCm, let w = s.weightKg, h > 0, w > 0 {
            let bmi = w / pow(h / 100.0, 2)
            bodyScore = bmiSubScore(bmi)
            usedBMI = true
        }

        // ---------- Vitals sub-score (0...20) ----------
        // Sleep duration (0...10), RHR (0...5), HRV (0...5).
        var vitalsRaw: Double = 0
        let sleepAvg = mean(s.sleepHistory28NonZero)
        if sleepAvg > 0 {
            // Ideal 7-9h; quadratic penalty outside.
            let dev = abs(sleepAvg - 8.0)
            vitalsRaw += max(0, 10 - dev * dev * 1.5)
        } else {
            vitalsRaw += 5  // neutral when no sleep data
        }
        if let rhr = s.lastNightRHR, rhr > 0 {
            // 50-65 is great. Penalize as it rises.
            switch rhr {
            case ..<50: vitalsRaw += 5            // possibly elite athlete OR data spike — give credit
            case ..<60: vitalsRaw += 5
            case ..<70: vitalsRaw += 4
            case ..<80: vitalsRaw += 2
            default:    vitalsRaw += 0
            }
        } else {
            vitalsRaw += 2.5
        }
        if let hrv = s.lastNightHRV, hrv > 0 {
            // Linearly score 0-100ms → 0-5.
            vitalsRaw += clamp(hrv / 100.0, 0, 1.0) * 5
        } else {
            vitalsRaw += 2.5
        }
        let vitalsScore = min(20, max(0, Int(vitalsRaw.rounded())))

        // ---------- Redistribute (Lifestyle removed) ----------
        // The four dimensions keep their internal scoring; each is scaled to a new
        // cap so the meter still totals 0–100: Activity 30 / Nutrition 30 / Body 18 /
        // Vitals 22 (the former Lifestyle 15 points spread proportionally).
        let activityFinal  = min(30, max(0, Int((Double(activityCapped) / 25.0 * 30.0).rounded())))
        let nutritionFinal = min(30, max(0, Int((Double(nutritionScore) / 25.0 * 30.0).rounded())))
        let bodyFinal      = min(18, max(0, Int((Double(bodyScore)      / 15.0 * 18.0).rounded())))
        let vitalsFinal    = min(22, max(0, Int((Double(vitalsScore)    / 20.0 * 22.0).rounded())))

        // ---------- Totals ----------
        let total = activityFinal + nutritionFinal + bodyFinal + vitalsFinal
        let label: HealthMeterLabel
        switch total {
        case 85...:   label = .excellent
        case 65...84: label = .good
        case 45...64: label = .fair
        default:      label = .needsWork
        }

        // Confidence: high when ALL inputs present, medium when missing 1-2 of (nutrition/BMI/HRV/RHR), low otherwise.
        let missingSignals = (usedNutrition ? 0 : 1)
            + (usedBMI ? 0 : 1)
            + (s.lastNightHRV ?? 0 > 0 ? 0 : 1)
            + (s.lastNightRHR ?? 0 > 0 ? 0 : 1)
        let confidence: PredictionConfidence
        switch missingSignals {
        case 0...1: confidence = .high
        case 2:     confidence = .medium
        default:    confidence = .low
        }

        // ---------- Explanation bullets ----------
        var bullets: [String] = []
        // Top contributing positive
        let subscores: [(String, Int, Int)] = [
            ("Activity", activityFinal, 30),
            ("Nutrition", nutritionFinal, 30),
            ("Body composition", bodyFinal, 18),
            ("Vitals", vitalsFinal, 22)
        ]
        if let top = subscores.max(by: { Double($0.1) / Double($0.2) < Double($1.1) / Double($1.2) }) {
            bullets.append("Strongest area: \(top.0) (\(top.1)/\(top.2))")
        }
        if let weak = subscores.min(by: { Double($0.1) / Double($0.2) < Double($1.1) / Double($1.2) }) {
            bullets.append("Biggest opportunity: \(weak.0) (\(weak.1)/\(weak.2))")
        }
        if !usedNutrition {
            bullets.append("Logging meals would refine the nutrition score — ask Astra to log your last meal.")
        }
        if !usedBMI {
            bullets.append("Add height + weight in Profile to factor body composition in.")
        }
        if let h = s.heightCm, let w = s.weightKg, h > 0, w > 0, usedBMI {
            let bmi = w / pow(h / 100.0, 2)
            if bmi >= 25 {
                bullets.append("BMI is \(String(format: "%.1f", bmi)) — above the healthy range.")
            } else if bmi < 18.5 {
                bullets.append("BMI is \(String(format: "%.1f", bmi)) — below the healthy range.")
            }
        }
        if sleepAvg > 0 && sleepAvg < 6.5 {
            bullets.append("Sleep avg \(String(format: "%.1f", sleepAvg))h — chronic deficit drags the whole score.")
        }

        return HealthMeterScore(
            score: total,
            label: label,
            confidence: confidence,
            activityScore: activityFinal,
            nutritionScore: nutritionFinal,
            bodyScore: bodyFinal,
            vitalsScore: vitalsFinal,
            explanation: PredictionExplanation(bullets: Array(bullets.prefix(4))),
            usedNutrition: usedNutrition,
            mealsLoggedToday: mealsLoggedToday,
            usedBMI: usedBMI
        )
    }

    /// Total Daily Energy Expenditure estimate via Mifflin-St Jeor + an
    /// activity multiplier scaled by the user's active-energy average. Returns
    /// 0 when height or weight is unknown (caller treats as "use neutral score").
    private static func estimateTDEE(heightCm: Double?, weightKg: Double?, activeAvg: Double) -> Double {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else { return 0 }
        // Sex / age aren't in the snapshot — use a midpoint adult formula:
        // BMR ≈ 10*kg + 6.25*cm - 5*30 + 0 (assuming ~30yo, mid-sex offset).
        let bmr = 10 * w + 6.25 * h - 150
        // Activity multiplier: sedentary 1.2, light 1.375, moderate 1.55, active 1.725.
        // Use active-energy avg as a proxy: 0kcal=1.2, 300=1.4, 600+=1.6.
        let multiplier = 1.2 + min(activeAvg / 1500.0, 0.4)
        return bmr * multiplier
    }

    private static func bmiSubScore(_ bmi: Double) -> Int {
        // Healthy 18.5-24.9 = 15; gradient out.
        switch bmi {
        case 18.5..<25.0: return 15
        case 25.0..<27.0: return 12
        case 27.0..<30.0: return 8
        case 30.0..<35.0: return 5
        case 35.0...:     return 2
        case 17.0..<18.5: return 11
        case 16.0..<17.0: return 6
        default:          return 3
        }
    }

    // MARK: - Goal Suggestions

    /// Recommends raising or lowering each user-configurable daily goal based on
    /// 28 days of attainment. For every metric with a goal + history:
    ///   • use non-zero days only; require ≥ 14 of them (honest gate),
    ///   • attainment per day = value / goal; take the median,
    ///   • LOWER when median < 0.55 → suggest the 70th-percentile daily value
    ///     (a reachable stretch the user actually hits most days),
    ///   • RAISE when median ≥ 1.25 → suggest the median daily value,
    ///   • skip when the suggestion moves the goal < 10% (not worth churning).
    /// Suggestions are sorted by how far median attainment sits from 1.0 and
    /// capped at 3. Confidence is high with ≥ 21 non-zero days, else medium.
    public static func computeGoalSuggestions(snapshot s: Snapshot) -> [GoalSuggestion] {
        let epsilon = 1e-6
        var out: [GoalSuggestion] = []

        for (rawValue, currentGoal) in s.userGoals {
            guard currentGoal > epsilon, currentGoal.isFinite else { continue }
            guard let metric = HealthMetricType(rawValue: rawValue) else { continue }
            guard let history = s.goalHistories28[rawValue] else { continue }

            let nonZero = history.filter { $0 > 0 && $0.isFinite }
            guard nonZero.count >= 14 else { continue }

            let attainments = nonZero.map { $0 / max(currentGoal, epsilon) }
            let medianAttain = median(attainments)
            guard medianAttain.isFinite else { continue }

            let direction: String
            let rawSuggested: Double
            if medianAttain < 0.55 {
                direction = "lower"
                rawSuggested = percentile(nonZero, 0.70)
            } else if medianAttain >= 1.25 {
                direction = "raise"
                rawSuggested = percentile(nonZero, 0.50)
            } else {
                continue
            }
            guard rawSuggested.isFinite, rawSuggested > 0 else { continue }
            // Direction-consistency guard: the suggested value must actually
            // move the goal in the stated direction.  Bimodal distributions
            // can produce, e.g., direction="lower" with P70 > currentGoal.
            if direction == "lower", rawSuggested >= currentGoal { continue }
            if direction == "raise", rawSuggested <= currentGoal { continue }

            let suggested = roundedGoal(rawSuggested, for: metric)
            guard suggested > 0, suggested.isFinite else { continue }

            // Not worth churning if the move is under 10% of the current goal.
            guard abs(suggested - currentGoal) >= 0.10 * currentGoal else { continue }

            let medianPct = medianAttain * 100.0
            guard medianPct.isFinite else { continue }

            let confidence: PredictionConfidence = nonZero.count >= 21 ? .high : .medium
            let rationale = goalRationale(metric: metric,
                                          currentGoal: currentGoal,
                                          suggested: suggested,
                                          medianPct: medianPct,
                                          direction: direction)

            out.append(GoalSuggestion(
                metric: metric,
                currentGoal: currentGoal,
                suggestedGoal: suggested,
                direction: direction,
                medianAttainmentPct: medianPct,
                rationale: rationale,
                confidence: confidence
            ))
        }

        return Array(out.sorted { abs($0.medianAttainmentPct / 100.0 - 1.0) > abs($1.medianAttainmentPct / 100.0 - 1.0) }.prefix(3))
    }

    /// Rounds a suggested goal to a clean, metric-appropriate step.
    private static func roundedGoal(_ value: Double, for metric: HealthMetricType) -> Double {
        func nearest(_ step: Double) -> Double { (value / step).rounded() * step }
        switch metric {
        case .steps:           return nearest(500)
        case .activeEnergy:    return nearest(25)
        case .sleep:           return nearest(0.25)
        case .distance:        return nearest(0.25)
        case .hydration:       return nearest(0.1)
        case .exerciseMinutes: return nearest(5)
        case .standHours:      return nearest(1)
        case .mindfulMinutes:  return nearest(5)
        case .flightsClimbed:  return nearest(1)
        default:               return value.rounded()
        }
    }

    /// Formats a goal/value for a metric's rationale sentence using its native
    /// units (e.g. "10,000-step", "1.5 L water", "30-min exercise").
    private static func goalValuePhrase(_ value: Double, for metric: HealthMetricType) -> String {
        switch metric {
        case .steps:
            return "\(intGrouped(value))-step"
        case .activeEnergy:
            return "\(intGrouped(value)) kcal"
        case .sleep:
            return "\(trimDecimal(value)) h sleep"
        case .distance:
            return "\(trimDecimal(value)) mi"
        case .hydration:
            return "\(trimDecimal(value)) L water"
        case .exerciseMinutes:
            return "\(intGrouped(value))-min exercise"
        case .standHours:
            return "\(intGrouped(value))-hour stand"
        case .mindfulMinutes:
            return "\(intGrouped(value))-min mindfulness"
        case .flightsClimbed:
            return "\(intGrouped(value))-flight"
        default:
            return "\(trimDecimal(value)) \(metric.unit)"
        }
    }

    /// Just the suggested number with its unit, for the back half of the sentence.
    private static func goalTargetPhrase(_ value: Double, for metric: HealthMetricType) -> String {
        switch metric {
        case .steps:           return intGrouped(value)
        case .activeEnergy:    return "\(intGrouped(value)) kcal"
        case .sleep:           return "\(trimDecimal(value)) h"
        case .distance:        return "\(trimDecimal(value)) mi"
        case .hydration:       return "\(trimDecimal(value)) L"
        case .exerciseMinutes: return "\(intGrouped(value)) min"
        case .standHours:      return "\(intGrouped(value)) h"
        case .mindfulMinutes:  return "\(intGrouped(value)) min"
        case .flightsClimbed:  return "\(intGrouped(value)) flights"
        default:               return trimDecimal(value)
        }
    }

    private static func goalRationale(metric: HealthMetricType,
                                      currentGoal: Double,
                                      suggested: Double,
                                      medianPct: Double,
                                      direction: String) -> String {
        let pct = Int(medianPct.rounded())
        let goalPhrase = goalValuePhrase(currentGoal, for: metric)
        let target = goalTargetPhrase(suggested, for: metric)
        if direction == "lower" {
            return "You hit a median \(pct)% of your \(goalPhrase) goal over 28 days — \(target) is a reachable stretch."
        } else {
            return "You beat your \(goalPhrase) goal most days (median \(pct)%) — \(target) matches what you actually do."
        }
    }

    /// Integer with thousands separators ("10,000").
    private static func intGrouped(_ value: Double) -> String {
        let n = Int(value.rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Trims trailing zeros ("1.5", "2", "2.25").
    private static func trimDecimal(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value.rounded()))" }
        return String(format: "%g", (value * 100).rounded() / 100)
    }

    /// Linear-interpolated percentile (0...1) over a copy-sorted array.
    private static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clampedP = min(max(p, 0), 1)
        let rank = clampedP * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = rank - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }

    /// Median via the percentile helper.
    private static func median(_ xs: [Double]) -> Double { percentile(xs, 0.5) }

    // MARK: - Helpers

    private static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func stdDev(_ xs: [Double], mean m: Double) -> Double {
        guard xs.count >= 2 else { return 0 }
        let sumSq = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return sqrt(sumSq / Double(xs.count - 1))
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    /// Pearson correlation over paired arrays. Returns nil on size mismatch,
    /// fewer than 2 points, or zero variance in either series (so we never
    /// emit NaN into Codable output).
    private static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let mx = mean(xs)
        let my = mean(ys)
        var cov = 0.0, vx = 0.0, vy = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx
            let dy = ys[i] - my
            cov += dx * dy
            vx += dx * dx
            vy += dy * dy
        }
        guard vx > 1e-9, vy > 1e-9 else { return nil }
        let r = cov / (sqrt(vx) * sqrt(vy))
        guard r.isFinite else { return nil }
        return clamp(r, -1.0, 1.0)
    }

    /// Fraction of the day that has elapsed at the given time, in [0, 1].
    private static func elapsedDayFraction(at date: Date) -> Double {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(startOfDay)
        return min(max(elapsed / 86400.0, 0), 1)
    }

    private static func formattedDuration(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}
