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

        public init(now: Date,
                    hasWatchClassData: Bool,
                    lastNightSleepHours: Double,
                    lastNightHRV: Double?,
                    lastNightRHR: Double?,
                    hrvHistory28: [Double],
                    rhrHistory28: [Double],
                    sleepHistory28NonZero: [Double],
                    stepsHistory14: [Double],
                    activeEnergyHistory14: [Double],
                    exerciseMinutesHistory14: [Double],
                    stepsToday: Double,
                    activeEnergyToday: Double,
                    exerciseMinutesToday: Double,
                    acuteLoadMinutes: Double,
                    chronicLoadMinutes: Double,
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
                    walkingAsymmetryToday: Double? = nil) {
            self.now = now
            self.hasWatchClassData = hasWatchClassData
            self.lastNightSleepHours = lastNightSleepHours
            self.lastNightHRV = lastNightHRV
            self.lastNightRHR = lastNightRHR
            self.hrvHistory28 = hrvHistory28
            self.rhrHistory28 = rhrHistory28
            self.sleepHistory28NonZero = sleepHistory28NonZero
            self.stepsHistory14 = stepsHistory14
            self.activeEnergyHistory14 = activeEnergyHistory14
            self.exerciseMinutesHistory14 = exerciseMinutesHistory14
            self.stepsToday = stepsToday
            self.activeEnergyToday = activeEnergyToday
            self.exerciseMinutesToday = exerciseMinutesToday
            self.acuteLoadMinutes = acuteLoadMinutes
            self.chronicLoadMinutes = chronicLoadMinutes
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
        return Predictions(
            generatedAt: s.now,
            recovery: recovery,
            nextWorkout: nextWorkout,
            trajectories: trajectories,
            sedentary: sedentary,
            healthMeter: healthMeter,
            anomalies: anomalies,
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

    /// 0–100 composite blending activity / nutrition / body / vitals /
    /// lifestyle. Each sub-score caps independently and the total is the sum.
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
        let usedNutrition = !intake7.isEmpty || s.dietaryCaloriesToday > 0
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

        // ---------- Lifestyle sub-score (0...15) ----------
        // Mindful minutes + VO2max percentile + walking gait quality.
        var lifestyleRaw: Double = 0
        let mindfulAvg = mean(s.mindfulMinutes7Day.filter { $0 > 0 })
        if mindfulAvg >= 10 { lifestyleRaw += 5 }
        else if mindfulAvg >= 5 { lifestyleRaw += 3 }
        else if mindfulAvg > 0 { lifestyleRaw += 1 }

        if let v = s.vo2Max, v > 0 {
            // Approx percentiles: 30 = below avg, 40 = avg, 50 = good, 60+ = excellent.
            switch v {
            case 50...:    lifestyleRaw += 5
            case 40..<50:  lifestyleRaw += 4
            case 30..<40:  lifestyleRaw += 2
            default:       lifestyleRaw += 1
            }
        }
        if let speed = s.walkingSpeedToday, speed > 0 {
            // 2.8+ mi/hr is a healthy adult walking pace.
            if speed >= 2.8 { lifestyleRaw += 3 }
            else if speed >= 2.0 { lifestyleRaw += 1.5 }
        }
        if let asym = s.walkingAsymmetryToday, asym >= 0 {
            // Apple flags >3% as elevated. Reward low asymmetry, penalize high.
            if asym <= 1.0 { lifestyleRaw += 2 }
            else if asym >= 3.0 { lifestyleRaw -= 2 }
        }
        let lifestyleScore = min(15, max(0, Int(lifestyleRaw.rounded())))

        // ---------- Totals ----------
        let total = activityCapped + nutritionScore + bodyScore + vitalsScore + lifestyleScore
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
            ("Activity", activityCapped, 25),
            ("Nutrition", nutritionScore, 25),
            ("Body composition", bodyScore, 15),
            ("Vitals", vitalsScore, 20),
            ("Lifestyle", lifestyleScore, 15)
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
        if mindfulAvg < 5 {
            bullets.append("No regular mindfulness logged this week.")
        }

        return HealthMeterScore(
            score: total,
            label: label,
            confidence: confidence,
            activityScore: activityCapped,
            nutritionScore: nutritionScore,
            bodyScore: bodyScore,
            vitalsScore: vitalsScore,
            lifestyleScore: lifestyleScore,
            explanation: PredictionExplanation(bullets: Array(bullets.prefix(4))),
            usedNutrition: usedNutrition,
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
