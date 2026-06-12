import SwiftUI
import HealthKit
import Combine

@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    @Published public var metricSummaries: [HealthMetricType: MetricSummary] = [:]

    /// True when any source has written heart-rate samples in the last 7 days
    /// (i.e. user has an Apple Watch paired, or a chest strap). Drives whether
    /// the home grid shows Watch-class tiles (HR, HRV, Activity rings) or hides
    /// them behind the Show More toggle. Persisted across launches so the UI
    /// doesn't flicker on cold start.
    @Published public var hasWatchClassData: Bool = UserDefaults.standard.bool(forKey: "has_watch_class_data")

    /// 28-day workout cache used by the prediction engine for pattern
    /// detection (next-likely-workout) and acute/chronic training-load.
    /// Refreshed on every `fetchTodayData()`. The 7-day callers in
    /// DashboardView / WorkoutTrackerView keep using `fetchRecentWorkouts(days:7)`
    /// directly; this property is for prediction-class consumers.
    @Published public var recentWorkouts28: [HKWorkout] = []

    /// Latest on-device prediction snapshot. Recomputed at the end of every
    /// `fetchTodayData()` (foreground + pull-to-refresh + staleness check).
    @Published public var predictions: Predictions? = nil

    /// 24 hourly step buckets for today (index = hour-of-day). Drives the
    /// sedentary-alert prediction; also useful for future debug views.
    @Published public var hourlyStepsToday: [Double] = Array(repeating: 0, count: 24)

    /// Today's dietary calorie sum from HK (logged via the `log_food` tool or
    /// any other Health-writing app). Feeds the Health Meter's nutrition
    /// sub-score.
    @Published public var dietaryCaloriesToday: Double = 0

    /// Today's protein intake in grams. Used for adequacy bonus in the
    /// nutrition sub-score.
    @Published public var dietaryProteinToday: Double = 0

    /// Last 7 days of dietary calorie intake (chronological, oldest → newest).
    @Published public var dietaryCalories7Day: [Double] = []

    /// Today's logged food items, grouped per meal (one entry per
    /// distinct food name + minute-bucketed timestamp). Sorted oldest → newest.
    /// Powers the Home meals card and the Coach's nutrition context.
    @Published public var todayFoodLog: [FoodLogEntry] = []

    /// Last 14 days of HK symptom samples (fatigue, headache, nausea, etc.)
    /// mapped to SymptomEntry with contract severity strings. Chronological.
    /// Feeds the PredictionEngine.Snapshot and Astra's symptom-aware coaching.
    @Published public var recentSymptoms14: [SymptomEntry] = []

    /// Start-of-day dates for days with a menstrual flow sample in the last
    /// 60 days. Chronological. Used by PredictionEngine for cycle-phase context.
    @Published public var menstrualFlowDays60: [Date] = []

    private init() {
        seedEmptySummaries()
    }

    /// Initialize summaries with zero values + empty history so the UI has
    /// well-typed objects to read from before HealthKit returns. Real data
    /// replaces these as soon as fetchTodayData lands. No mock numbers shown.
    /// User-overridden goals (from the Goals editor) are read back here so
    /// they survive cold launches.
    private func seedEmptySummaries() {
        for type in HealthMetricType.allCases {
            metricSummaries[type] = MetricSummary(
                type: type,
                currentValue: 0,
                goal: Self.userGoal(for: type),
                history: []
            )
        }
    }

    /// UserDefaults key for a per-metric goal override. Returns the stored
    /// value if present, falling back to `type.defaultGoal`. Static so the
    /// Goals editor and the seeding path read from the same source.
    public static func userGoal(for type: HealthMetricType) -> Double {
        let key = "goal_\(type.rawValue)"
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : type.defaultGoal
    }

    /// Update the user-overridden goal for a metric. Writes to UserDefaults
    /// and patches the in-memory `metricSummaries` so every card observing
    /// it refreshes instantly — no need to re-fetch HealthKit.
    public func setGoal(_ value: Double, for type: HealthMetricType) {
        let key = "goal_\(type.rawValue)"
        UserDefaults.standard.set(value, forKey: key)
        if var summary = metricSummaries[type] {
            summary.goal = value
            metricSummaries[type] = summary
        }
        // Goals feed trajectories, the Health Meter, and goal suggestions —
        // recompute so every surface adapts immediately.
        recomputePredictions()
    }

    /// Reset a metric's goal back to its `defaultGoal`. Removes the stored
    /// override so future `userGoal(for:)` calls fall through to the default.
    public func resetGoal(for type: HealthMetricType) {
        let key = "goal_\(type.rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
        if var summary = metricSummaries[type] {
            summary.goal = type.defaultGoal
            metricSummaries[type] = summary
        }
    }
    
    public func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        // ALL available HealthKit types we want to read.
        // Some identifiers are gated by iOS version — guard with optional unwrap.
        var typesToRead: Set<HKObjectType> = []

        // Activity & fitness quantities
        let quantityRead: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .walkingHeartRateAverage,
            .heartRateVariabilitySDNN, .oxygenSaturation, .respiratoryRate,
            .bodyTemperature, .basalBodyTemperature,
            .activeEnergyBurned, .basalEnergyBurned,
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
            .flightsClimbed, .pushCount, .swimmingStrokeCount,
            .appleExerciseTime, .appleStandTime, .appleMoveTime,
            .vo2Max, .runningSpeed, .runningPower, .runningStrideLength,
            .walkingSpeed, .walkingStepLength, .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage,
            .sixMinuteWalkTestDistance, .stairAscentSpeed, .stairDescentSpeed,
            // Body measurements
            .bodyMass, .bodyMassIndex, .bodyFatPercentage, .leanBodyMass,
            .height, .waistCircumference,
            // Nutrition
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
            .dietarySugar, .dietaryFiber, .dietaryCaffeine, .dietaryWater,
            .dietaryCholesterol, .dietarySodium, .dietaryPotassium, .dietaryCalcium,
            .dietaryIron, .dietaryVitaminC, .dietaryVitaminD,
            // Blood / vitals
            .bloodGlucose, .bloodAlcoholContent,
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .peripheralPerfusionIndex, .forcedExpiratoryVolume1, .peakExpiratoryFlowRate,
            .environmentalAudioExposure, .headphoneAudioExposure
        ]
        for id in quantityRead {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { typesToRead.insert(t) }
        }

        // Category samples
        let categoryRead: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis, .mindfulSession, .menstrualFlow, .ovulationTestResult,
            .sexualActivity, .intermenstrualBleeding, .lowHeartRateEvent, .highHeartRateEvent,
            .irregularHeartRhythmEvent, .audioExposureEvent, .toothbrushingEvent,
            .handwashingEvent, .appleStandHour, .appleWalkingSteadinessEvent,
            .environmentalAudioExposureEvent, .headphoneAudioExposureEvent,
            .abdominalCramps, .bloating, .constipation, .diarrhea, .heartburn,
            .nausea, .vomiting, .acne, .dizziness, .fatigue, .fever, .headache,
            .hotFlashes, .moodChanges, .sleepChanges
        ]
        for id in categoryRead {
            if let t = HKCategoryType.categoryType(forIdentifier: id) { typesToRead.insert(t) }
        }

        // Workout & series
        typesToRead.insert(HKObjectType.workoutType())
        if #available(iOS 16.0, *) {
            typesToRead.insert(HKSeriesType.workoutRoute())
            typesToRead.insert(HKSeriesType.heartbeat())
        }

        // Characteristic types — these are part of "Medical ID" / Health Profile
        let charRead: [HKCharacteristicTypeIdentifier] = [
            .biologicalSex, .bloodType, .dateOfBirth, .fitzpatrickSkinType,
            .wheelchairUse, .activityMoveMode
        ]
        for id in charRead {
            if let t = HKCharacteristicType.characteristicType(forIdentifier: id) { typesToRead.insert(t) }
        }

        // NOTE: Clinical records (FHIR) are opt-in via Settings → Health Records.
        // Requesting them at startup triggers Apple's "Add provider account" sheet,
        // which re-fires on every launch until the user links a provider — too noisy.

        // What we'll write back (workouts, hydration, mindfulness, body measurements)
        var typesToWrite: Set<HKSampleType> = []
        let quantityWrite: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .activeEnergyBurned, .distanceWalkingRunning,
            .dietaryWater, .bodyMass, .bodyFatPercentage, .height,
            // Food logging from image analysis
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal
        ]
        for id in quantityWrite {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { typesToWrite.insert(t) }
        }
        if let mindful = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            typesToWrite.insert(mindful)
        }
        // Sleep — written by the on-device SleepSessionManager after a tracked night.
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            typesToWrite.insert(sleep)
        }
        typesToWrite.insert(HKObjectType.workoutType())

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await fetchTodayData()
            return true
        } catch {
            print("HealthKit Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Opt-in clinical-records request, fired only when the user toggles it on
    /// in Settings. Available in countries where Apple Health Records is supported
    /// (US, UK, Canada, plus a handful of EU countries). On unsupported regions
    /// the system silently refuses — we surface that to the caller.
    public func requestClinicalRecordsAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        var clinicalTypes: Set<HKObjectType> = []
        let ids: [HKClinicalTypeIdentifier] = [
            .allergyRecord, .conditionRecord, .immunizationRecord,
            .labResultRecord, .medicationRecord, .procedureRecord, .vitalSignRecord
        ]
        for id in ids {
            if let t = HKClinicalType.clinicalType(forIdentifier: id) { clinicalTypes.insert(t) }
        }
        guard !clinicalTypes.isEmpty else { return false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: clinicalTypes)
            UserDefaults.standard.set(true, forKey: "clinical_records_requested")
            return true
        } catch {
            return false
        }
    }

    public var clinicalRecordsRequested: Bool {
        UserDefaults.standard.bool(forKey: "clinical_records_requested")
    }
    
    /// One metric facet produced by a single HK query. `value` and `history`
    /// are independently optional so a value-only query (e.g. today's step sum)
    /// and a history-only query (e.g. 365-day step buckets) for the SAME metric
    /// type can each return just their facet; the accumulator merges both into
    /// the one summary. nil facets leave the existing summary field untouched.
    /// Sendable so it can flow back out of the `withTaskGroup` child tasks.
    private struct MetricFetchResult: Sendable {
        let type: HealthMetricType
        let value: Double?
        let history: [MetricValue]?
    }

    // Fetch today's health metrics from HealthKit
    public func fetchTodayData() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Health-data sync is silent: no global loading flag is toggled here, so
        // automatic / periodic fetches never flash a loading overlay on Home or
        // Progress. Pull-to-refresh shows its own native spinner via `.refreshable`.

        // PERFORMANCE: every metric query RETURNS its result instead of
        // self-mutating `@Published metricSummaries` per callback. We seed a
        // local copy (preserving user goals + any keys we don't touch),
        // accumulate every returned value/history into it, and assign the
        // dictionary back EXACTLY ONCE after the group completes — collapsing
        // ~45-50 publishes per tick into at most one. `recentWorkouts28`,
        // `hourlyStepsToday`, and the dietary batch stay as their own single
        // writes; they back distinct `@Published` properties.
        var newSummaries = self.metricSummaries

        await withTaskGroup(of: MetricFetchResult?.self) { group in
            group.addTask { await self.fetchSteps() }
            group.addTask { await self.fetchCalories() }
            group.addTask { await self.fetchHeartRate() }
            group.addTask { await self.fetchDistance() }
            group.addTask { await self.fetchSleep() }
            group.addTask { await self.fetchHRV() }
            group.addTask { await self.fetchHydration() }
            // History for the seven core tiles (365-day buckets).
            group.addTask { await self.fetchHistory(type: .steps) }
            group.addTask { await self.fetchHistory(type: .activeEnergy) }
            group.addTask { await self.fetchHistory(type: .heartRate) }
            group.addTask { await self.fetchHistory(type: .distance) }
            group.addTask { await self.fetchHistory(type: .sleep) }
            group.addTask { await self.fetchHistory(type: .hrv) }
            group.addTask { await self.fetchHistory(type: .hydration) }
            // Show-more tiles
            group.addTask { await self.fetchSimpleStatistics(.restingHeartRate, hkID: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage) }
            group.addTask { await self.fetchSimpleStatistics(.bodyMass,         hkID: .bodyMass,         unit: .gramUnit(with: .kilo),                       options: .mostRecent) }
            group.addTask { await self.fetchSimpleStatistics(.flightsClimbed,   hkID: .flightsClimbed,   unit: HKUnit.count(),                               options: .cumulativeSum, todayOnly: true) }
            group.addTask { await self.fetchSimpleStatistics(.exerciseMinutes,  hkID: .appleExerciseTime, unit: HKUnit.minute(),                             options: .cumulativeSum, todayOnly: true) }
            group.addTask { await self.fetchSimpleStatistics(.standHours,       hkID: .appleStandTime,   unit: HKUnit.hour(),                                options: .cumulativeSum, todayOnly: true) }
            group.addTask { await self.fetchSimpleStatistics(.oxygenSaturation, hkID: .oxygenSaturation, unit: .percent(),                                   options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleStatistics(.vo2Max,           hkID: .vo2Max,           unit: HKUnit(from: "ml/(kg*min)"),                  options: .mostRecent) }
            group.addTask { await self.fetchMindfulMinutes() }
            // iPhone-trackable show-more tiles (no Watch required)
            group.addTask { await self.fetchSimpleStatistics(.restingEnergy,        hkID: .basalEnergyBurned,                 unit: HKUnit.kilocalorie(),       options: .cumulativeSum, todayOnly: true) }
            group.addTask { await self.fetchSimpleStatistics(.walkingSpeed,         hkID: .walkingSpeed,                      unit: HKUnit(from: "mi/hr"),      options: .discreteAverage) }
            group.addTask { await self.fetchSimpleStatistics(.walkingStepLength,    hkID: .walkingStepLength,                 unit: HKUnit.inch(),              options: .discreteAverage) }
            group.addTask { await self.fetchSimpleStatistics(.walkingDoubleSupport, hkID: .walkingDoubleSupportPercentage,    unit: .percent(),                 options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleStatistics(.walkingAsymmetry,     hkID: .walkingAsymmetryPercentage,        unit: .percent(),                 options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleStatistics(.headphoneAudio,       hkID: .headphoneAudioExposure,            unit: HKUnit.decibelAWeightedSoundPressureLevel(), options: .discreteAverage) }
            // 30-day history for the show-more tiles (so DetailedMetricView opens with a real chart).
            // RHR + exerciseMinutes get a 90-day window because the prediction
            // engine needs richer baselines for the recovery + load math.
            group.addTask { await self.fetchSimpleHistory(.restingHeartRate, hkID: .restingHeartRate,  unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, days: 90) }
            group.addTask { await self.fetchSimpleHistory(.bodyMass,         hkID: .bodyMass,          unit: .gramUnit(with: .kilo),                     options: .mostRecent) }
            group.addTask { await self.fetchSimpleHistory(.flightsClimbed,   hkID: .flightsClimbed,    unit: HKUnit.count(),                             options: .cumulativeSum) }
            group.addTask { await self.fetchSimpleHistory(.exerciseMinutes,  hkID: .appleExerciseTime, unit: HKUnit.minute(),                            options: .cumulativeSum, days: 90) }
            group.addTask { await self.fetchSimpleHistory(.standHours,       hkID: .appleStandTime,    unit: HKUnit.hour(),                              options: .cumulativeSum) }
            group.addTask { await self.fetchSimpleHistory(.oxygenSaturation, hkID: .oxygenSaturation,  unit: .percent(),                                 options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleHistory(.vo2Max,           hkID: .vo2Max,            unit: HKUnit(from: "ml/(kg*min)"),                options: .mostRecent) }
            group.addTask { await self.fetchMindfulHistory() }
            // History for new iPhone-trackable tiles
            group.addTask { await self.fetchSimpleHistory(.restingEnergy,        hkID: .basalEnergyBurned,              unit: HKUnit.kilocalorie(),                       options: .cumulativeSum) }
            group.addTask { await self.fetchSimpleHistory(.walkingSpeed,         hkID: .walkingSpeed,                   unit: HKUnit(from: "mi/hr"),                      options: .discreteAverage) }
            group.addTask { await self.fetchSimpleHistory(.walkingStepLength,    hkID: .walkingStepLength,              unit: HKUnit.inch(),                              options: .discreteAverage) }
            group.addTask { await self.fetchSimpleHistory(.walkingDoubleSupport, hkID: .walkingDoubleSupportPercentage, unit: .percent(),                                 options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleHistory(.walkingAsymmetry,     hkID: .walkingAsymmetryPercentage,     unit: .percent(),                                 options: .discreteAverage, scale: 100) }
            group.addTask { await self.fetchSimpleHistory(.headphoneAudio,       hkID: .headphoneAudioExposure,         unit: HKUnit.decibelAWeightedSoundPressureLevel(), options: .discreteAverage) }

            // Side-channel fetches back their OWN `@Published` properties and
            // each writes itself exactly once on the MainActor. They return nil
            // so they don't touch the metric dictionary, but stay in this same
            // group so they run fully concurrently with the metric queries (as
            // they did before this refactor).
            //
            // One-shot per refresh: ask "is there any HR-class data flowing?"
            // so DashboardView can hide Watch-only cards on iPhone-only setups.
            group.addTask { await self.detectWatchClassData(); return nil }
            // Prediction inputs: 28-day workout cache + hourly steps for sedentary detection.
            group.addTask {
                let workouts = await self.fetchRecentWorkouts(days: 28)
                await MainActor.run {
                    self.recentWorkouts28 = workouts
                    TrainingLoadEngine.shared.compute(from: workouts)
                }
                return nil
            }
            group.addTask {
                let buckets = await self.fetchHourlyStepsToday()
                await MainActor.run { self.hourlyStepsToday = buckets }
                return nil
            }
            // Health Meter inputs: dietary intake from HK (written by log_food
            // or any other Health-writing app the user has).
            group.addTask {
                let kcal = await self.fetchTodayDietaryEnergy()
                let protein = await self.fetchTodayDietaryProtein()
                let history = await self.fetchDietaryEnergyHistory(days: 7)
                let log = await self.fetchTodayFoodLog()
                await MainActor.run {
                    self.dietaryCaloriesToday = kcal
                    self.dietaryProteinToday = protein
                    self.dietaryCalories7Day = history
                    self.todayFoodLog = log
                }
                return nil
            }
            // Symptom + menstrual history for prediction engine + Astra coaching.
            group.addTask {
                let symptoms = await self.fetchSymptomHistory()
                await MainActor.run { self.recentSymptoms14 = symptoms }
                return nil
            }
            group.addTask {
                let flowDays = await self.fetchMenstrualFlowDays()
                await MainActor.run { self.menstrualFlowDays60 = flowDays }
                return nil
            }

            // Drain every returned facet into the local copy. This loop runs on
            // the group's awaiting context (the MainActor) — no data races, and
            // crucially no intermediate `@Published` publishes.
            for await result in group {
                guard let result, var summary = newSummaries[result.type] else { continue }
                if let value = result.value { summary.currentValue = value }
                if let history = result.history { summary.history = history }
                newSummaries[result.type] = summary
            }
        }

        // SINGLE write of the metric dictionary — gated so an unchanged poll
        // emits ZERO publishes (MetricValue/MetricSummary are content-Equatable).
        if newSummaries != self.metricSummaries {
            self.metricSummaries = newSummaries
        }

        // All HK data is in — compute predictions on-device, sync, on main.
        recomputePredictions()

        // Fire-and-forget AI enrichment. Reads cache first; only hits Vertex
        // on a cache miss. Updates `predictions` again when it lands.
        kickoffAIEnrichmentIfNeeded()

        // HRV nudge — schedule a breathing reminder if HRV is below the
        // 30-day rolling average by >15 % and no session was done today.
        if let hrvHistory = metricSummaries[.hrv]?.history, !hrvHistory.isEmpty {
            BreathingSessionManager.shared.scheduleHRVNudgeIfNeeded(hrv: hrvHistory)
        }

        // Challenge progress depends on the freshly-written metric summaries.
        // Mirror the StreakEngine pattern in DashboardView's refreshAllData().
        ChallengeEngine.shared.refreshProgress()
    }

    /// Refresh today's snapshot only if the last computed `predictions` is
    /// older than `maxAgeMinutes`. Call at points where prediction freshness
    /// matters (e.g. top of ChatViewModel.buildSystemInstruction so the
    /// system prompt's one-line summary reflects current state, not a
    /// 30-minute-old fetch).
    public func refreshIfStale(maxAgeMinutes: Int) async {
        let age: TimeInterval
        if let last = predictions?.generatedAt {
            age = Date().timeIntervalSince(last)
        } else {
            age = .greatestFiniteMagnitude
        }
        if age > Double(maxAgeMinutes) * 60 {
            await fetchTodayData()
        }
    }

    /// Heart-rate samples can only originate from a Watch, chest strap, or
    /// third-party wearable — iPhone has no HR sensor. If we see any HR sample
    /// in the last 7 days, we have Watch-class data and the home grid keeps the
    /// HR / HRV / Activity rings cards visible. Otherwise they collapse into
    /// Show More so an iPhone-only user isn't staring at em-dashes.
    private func detectWatchClassData() async {
        guard let t = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let start = Date().addingTimeInterval(-7 * 24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let detected: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let q = HKSampleQuery(sampleType: t, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples?.count ?? 0) > 0)
            }
            healthStore.execute(q)
        }

        if hasWatchClassData != detected {
            hasWatchClassData = detected
            UserDefaults.standard.set(detected, forKey: "has_watch_class_data")
        }
    }

    /// Save a completed workout as a proper `HKWorkout` so Apple Health's
    /// Activity / Workouts sections see a single workout entry (not just
    /// floating energy/distance samples). Uses `HKWorkoutBuilder` because the
    /// legacy `HKWorkout(activityType:...)` initializer was deprecated in iOS 17.
    public func logWorkout(activityType: HKWorkoutActivityType,
                           start: Date,
                           end: Date,
                           calories: Double,
                           distanceMiles: Double) async -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .unknown

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: start)

            var samples: [HKSample] = []
            if calories > 0, let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(HKQuantitySample(type: t,
                                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                                                start: start, end: end))
            }
            if distanceMiles > 0, let t = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                samples.append(HKQuantitySample(type: t,
                                                quantity: HKQuantity(unit: .mile(), doubleValue: distanceMiles),
                                                start: start, end: end))
            }
            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }

            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            await fetchTodayData()
            return true
        } catch {
            print("logWorkout failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // --- HealthKit Specific Queries ---
    
    private func fetchSteps() async -> MetricFetchResult? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let steps: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard let result = result, let sum = result.sumQuantity() else {
                    print("Failed to fetch steps: \(error?.localizedDescription ?? "unknown error")")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sum.doubleValue(for: HKUnit.count()))
            }
            healthStore.execute(query)
        }
        guard let steps else { return nil }
        return MetricFetchResult(type: .steps, value: steps, history: nil)
    }

    private func fetchCalories() async -> MetricFetchResult? {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let kcal: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard let result = result, let sum = result.sumQuantity() else {
                    print("Failed to fetch calories: \(error?.localizedDescription ?? "unknown")")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sum.doubleValue(for: HKUnit.kilocalorie()))
            }
            healthStore.execute(query)
        }
        guard let kcal else { return nil }
        return MetricFetchResult(type: .activeEnergy, value: kcal, history: nil)
    }

    private func fetchHeartRate() async -> MetricFetchResult? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let bpm: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], let latestSample = samples.first else {
                    print("Failed to fetch heart rate: \(error?.localizedDescription ?? "unknown")")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: latestSample.quantity.doubleValue(for: HKUnit(from: "count/min")))
            }
            healthStore.execute(query)
        }
        guard let bpm else { return nil }
        return MetricFetchResult(type: .heartRate, value: bpm, history: nil)
    }

    private func fetchDistance() async -> MetricFetchResult? {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let miles: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let result = result, let sum = result.sumQuantity() else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sum.doubleValue(for: HKUnit.mile()))
            }
            healthStore.execute(query)
        }
        guard let miles else { return nil }
        return MetricFetchResult(type: .distance, value: miles, history: nil)
    }

        private func fetchSleep() async -> MetricFetchResult? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now = Date()
        // Sleep tracking is often spotty — iPhone-only Sleep Focus doesn't
        // necessarily fire every night, and a missed night shouldn't make
        // the card go dark. Look back 30 days and surface the MOST RECENT
        // night with data. The SleepCard reads `summary.history` to derive
        // a date label, so the user always sees an honest reading + when it was.
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: [.strictEndDate])

        let hours: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }

                var asleepByDay: [Date: Double] = [:]
                var inBedByDay: [Date: Double] = [:]
                let calendar = Calendar.current
                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    let day = calendar.startOfDay(for: sample.endDate)
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        asleepByDay[day, default: 0] += duration
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBedByDay[day, default: 0] += duration
                    default:
                        break
                    }
                }

                var mostRecentHours: Double = 0
                var cursor = calendar.startOfDay(for: now)
                for _ in 0..<31 {
                    let asleep = asleepByDay[cursor] ?? 0
                    let inBed = inBedByDay[cursor] ?? 0
                    let hrs = asleep > 0 ? asleep : inBed
                    if hrs > 0 {
                        mostRecentHours = hrs
                        break
                    }
                    guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }

                cont.resume(returning: mostRecentHours)
            }
            healthStore.execute(query)
        }
        guard let hours else { return nil }
        return MetricFetchResult(type: .sleep, value: hours, history: nil)
    }

    
        private func fetchHRV() async -> MetricFetchResult? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-24 * 3600), end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let ms: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], let latestSample = samples.first else {
                    print("Failed to fetch HRV: \(error?.localizedDescription ?? "unknown")")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: latestSample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)))
            }
            healthStore.execute(query)
        }
        guard let ms else { return nil }
        return MetricFetchResult(type: .hrv, value: ms, history: nil)
    }

    
        private func fetchHydration() async -> MetricFetchResult? {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let liters: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: waterType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard let result = result, let sum = result.sumQuantity() else {
                    print("Failed to fetch hydration: \(error?.localizedDescription ?? "unknown")")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sum.doubleValue(for: HKUnit.liter()))
            }
            healthStore.execute(query)
        }
        guard let liters else { return nil }
        return MetricFetchResult(type: .hydration, value: liters, history: nil)
    }

    
        private func fetchHistory(type: HealthMetricType) async -> MetricFetchResult? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let calendar = Calendar.current
        let now = Date()
        guard let anchorDate = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now) else { return nil }
        guard let startDate = calendar.date(byAdding: .day, value: -365, to: anchorDate) else { return nil }

        let interval = DateComponents(day: 1)

        let fetched: [MetricValue]? = await withCheckedContinuation { (cont: CheckedContinuation<[MetricValue]?, Never>) in
            switch type {
            case .steps, .activeEnergy, .distance, .hydration:
                guard let quantityType = getQuantityType(for: type) else { cont.resume(returning: nil); return }
                let query = HKStatisticsCollectionQuery(
                    quantityType: quantityType,
                    quantitySamplePredicate: nil,
                    options: .cumulativeSum,
                    anchorDate: anchorDate,
                    intervalComponents: interval
                )
                query.initialResultsHandler = { _, results, error in
                    guard let results = results else {
                        print("Failed to fetch statistics collection for \(type): \(error?.localizedDescription ?? "unknown error")")
                        cont.resume(returning: nil)
                        return
                    }
                    var history: [MetricValue] = []
                    results.enumerateStatistics(from: startDate, to: now) { statistics, stop in
                        let value: Double
                        if type == .steps {
                            value = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0.0
                        } else if type == .activeEnergy {
                            value = statistics.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0.0
                        } else if type == .distance {
                            value = statistics.sumQuantity()?.doubleValue(for: HKUnit.mile()) ?? 0.0
                        } else {
                            value = statistics.sumQuantity()?.doubleValue(for: HKUnit.liter()) ?? 0.0
                        }
                        history.append(MetricValue(date: statistics.startDate, value: value))
                    }
                    cont.resume(returning: history)
                }
                healthStore.execute(query)

            case .heartRate:
                guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { cont.resume(returning: nil); return }
                let startOfHR = now.addingTimeInterval(-12 * 3600)
                let predicate = HKQuery.predicateForSamples(withStart: startOfHR, end: now, options: .strictStartDate)
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                    guard let samples = samples as? [HKQuantitySample] else { cont.resume(returning: nil); return }
                    let history = samples.map { sample in
                        MetricValue(date: sample.startDate, value: sample.quantity.doubleValue(for: HKUnit(from: "count/min")))
                    }
                    cont.resume(returning: history)
                }
                healthStore.execute(query)

            case .sleep:
                guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { cont.resume(returning: nil); return }
                let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                    var asleepByDay: [Date: Double] = [:]
                    var inBedByDay: [Date: Double] = [:]
                    for sample in samples {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                        let day = calendar.startOfDay(for: sample.endDate)
                        switch sample.value {
                        case HKCategoryValueSleepAnalysis.asleep.rawValue,
                             HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            asleepByDay[day, default: 0] += duration
                        case HKCategoryValueSleepAnalysis.inBed.rawValue:
                            inBedByDay[day, default: 0] += duration
                        default:
                            break
                        }
                    }
                    var history: [MetricValue] = []
                    var currentDate = startDate
                    while currentDate <= now {
                        let day = calendar.startOfDay(for: currentDate)
                        let asleep = asleepByDay[day] ?? 0
                        let duration = asleep > 0 ? asleep : (inBedByDay[day] ?? 0)
                        history.append(MetricValue(date: day, value: duration))
                        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                        currentDate = nextDate
                    }
                    cont.resume(returning: history)
                }
                healthStore.execute(query)

            case .hrv:
                guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { cont.resume(returning: nil); return }
                let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                    guard let samples = samples as? [HKQuantitySample] else { cont.resume(returning: nil); return }
                    var hrvByDay: [Date: [Double]] = [:]
                    for sample in samples {
                        let day = calendar.startOfDay(for: sample.startDate)
                        let ms = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                        hrvByDay[day, default: []].append(ms)
                    }
                    var history: [MetricValue] = []
                    var currentDate = startDate
                    while currentDate <= now {
                        let day = calendar.startOfDay(for: currentDate)
                        let values = hrvByDay[day] ?? []
                        let avgVal = values.isEmpty ? 0.0 : (values.reduce(0, +) / Double(values.count))
                        history.append(MetricValue(date: day, value: avgVal))
                        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                        currentDate = nextDate
                    }
                    cont.resume(returning: history)
                }
                healthStore.execute(query)
            default:
                cont.resume(returning: nil)
            }
        }
        guard let fetched else { return nil }
        return MetricFetchResult(type: type, value: nil, history: fetched)
    }


    private func getQuantityType(for type: HealthMetricType) -> HKQuantityType? {
        switch type {
        case .steps:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .activeEnergy:
            return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .distance:
            return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .hrv:
            return HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .hydration:
            return HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        default:
            return nil
        }
    }
    
    // Writes a new sample to HealthKit
    @discardableResult
    public func logMetricValue(type: HealthMetricType, value: Double, start: Date? = nil, end: Date? = nil) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let now = Date()
        let sampleStart = start ?? now
        let sampleEnd = end ?? now

        let sample: HKSample

        switch type {
        case .steps:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return false }
            let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        case .activeEnergy:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return false }
            let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        case .heartRate:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return false }
            let quantity = HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        case .distance:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return false }
            let quantity = HKQuantity(unit: HKUnit.mile(), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        case .sleep:
            guard let sampleType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return false }
            let sleepStart = start ?? sampleEnd.addingTimeInterval(-value * 3600.0)
            sample = HKCategorySample(type: sampleType, value: HKCategoryValueSleepAnalysis.asleep.rawValue, start: sleepStart, end: sampleEnd)
        case .hrv:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return false }
            let quantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        case .hydration:
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return false }
            let quantity = HKQuantity(unit: HKUnit.liter(), doubleValue: value)
            sample = HKQuantitySample(type: sampleType, quantity: quantity, start: sampleStart, end: sampleEnd)
        default:
            // Show-more tiles (restingHR, bodyMass, flights, exercise, stand, mindful, SpO2, VO2 Max)
            // are read-only from HealthKit in this app — no manual logging path.
            return false
        }

        do {
            try await healthStore.save(sample)
            await fetchTodayData()
            return true
        } catch {
            print("Failed to save sample: \(error.localizedDescription)")
            return false
        }
    }

    /// Write a single body-mass sample (used by EditProfileSheet).
    public func logBodyMass(kilograms: Double) async -> Bool {
        guard kilograms > 0, let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return false }
        let s = HKQuantitySample(type: t, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms), start: Date(), end: Date())
        do { try await healthStore.save(s); return true } catch { return false }
    }

    /// Write a single height sample (cm).
    public func logHeight(centimeters: Double) async -> Bool {
        guard centimeters > 0, let t = HKQuantityType.quantityType(forIdentifier: .height) else { return false }
        let s = HKQuantitySample(type: t, quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: centimeters), start: Date(), end: Date())
        do { try await healthStore.save(s); return true } catch { return false }
    }

    /// Logs a food item to today's diet: dietary energy (kcal) + macros (g) as a
    /// single batch save. Returns true if at least one sample was written.
    /// When `isEstimate` is true (the default for AI-vision logs), the metadata
    /// signals "machine-generated, may be approximate" via Apple's standard
    /// `HKMetadataKeyWasUserEntered = false` plus a custom confidence string so
    /// other apps and future queries know not to treat the values as exact.
    public func logFood(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        date: Date = Date(),
        isEstimate: Bool = false,
        confidence: String? = nil
    ) async -> Bool {
        var samples: [HKSample] = []

        var sampleMetadata: [String: Any] = [
            HKMetadataKeyFoodType: name,
            HKMetadataKeyWasUserEntered: !isEstimate
        ]
        if let confidence {
            sampleMetadata["FitnessGuruEstimateConfidence"] = confidence
        }

        func add(_ id: HKQuantityTypeIdentifier, _ value: Double, unit: HKUnit) {
            guard value > 0, let t = HKQuantityType.quantityType(forIdentifier: id) else { return }
            let q = HKQuantity(unit: unit, doubleValue: value)
            let s = HKQuantitySample(type: t, quantity: q, start: date, end: date,
                                     metadata: sampleMetadata)
            samples.append(s)
        }
        add(.dietaryEnergyConsumed, calories, unit: .kilocalorie())
        add(.dietaryProtein,        protein,  unit: .gram())
        add(.dietaryCarbohydrates,  carbs,    unit: .gram())
        add(.dietaryFatTotal,       fat,      unit: .gram())
        guard !samples.isEmpty else { return false }

        do {
            try await healthStore.save(samples)
            return true
        } catch {
            print("Failed to save food samples: \(error.localizedDescription)")
            return false
        }
    }

    // --- Generic "stat-only" fetch used by the show-more tiles. ---
    // Pick the unit + statistics option per type so the same call works for
    // sum (flights, exercise time), average (resting HR, SpO2), and most-recent
    // (weight, VO2 max).
        private func fetchSimpleStatistics(_ metric: HealthMetricType,
                                       hkID: HKQuantityTypeIdentifier,
                                       unit: HKUnit,
                                       options: HKStatisticsOptions,
                                       todayOnly: Bool = false,
                                       scale: Double = 1.0) async -> MetricFetchResult? {
        guard let qType = HKQuantityType.quantityType(forIdentifier: hkID) else { return nil }
        let now = Date()
        let start: Date = todayOnly
            ? Calendar.current.startOfDay(for: now)
            : now.addingTimeInterval(-30 * 24 * 3600) // 30-day window for averages / most recent
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let value: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: qType, quantitySamplePredicate: predicate, options: options) { _, result, _ in
                guard let result else { cont.resume(returning: nil); return }
                let quantity: HKQuantity?
                if options.contains(.cumulativeSum) {
                    quantity = result.sumQuantity()
                } else if options.contains(.discreteAverage) {
                    quantity = result.averageQuantity()
                } else if options.contains(.mostRecent) {
                    quantity = result.mostRecentQuantity()
                } else {
                    quantity = nil
                }
                guard let q = quantity else { cont.resume(returning: nil); return }
                cont.resume(returning: q.doubleValue(for: unit) * scale)
            }
            healthStore.execute(query)
        }
        guard let value else { return nil }
        return MetricFetchResult(type: metric, value: value, history: nil)
    }


    /// Mindful sessions live in the category-sample table (not quantity) so the
    /// generic helper doesn't apply — sum the durations directly.
        private func fetchMindfulMinutes() async -> MetricFetchResult? {
        guard let t = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let minutes: Double? = await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: t, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let total = samples
                    .map { $0.endDate.timeIntervalSince($0.startDate) / 60.0 }
                    .reduce(0, +)
                cont.resume(returning: total)
            }
            healthStore.execute(query)
        }
        guard let minutes else { return nil }
        return MetricFetchResult(type: .mindfulMinutes, value: minutes, history: nil)
    }


    /// 30-day daily history for show-more tile metrics. Mirrors fetchSimpleStatistics
    /// but builds a bucketed `[MetricValue]` series via HKStatisticsCollectionQuery.
    /// Sparse-data metrics (bodyMass, vo2Max) skip empty days rather than zero-filling
    /// so the chart line stays honest.
        private func fetchSimpleHistory(_ metric: HealthMetricType,
                                    hkID: HKQuantityTypeIdentifier,
                                    unit: HKUnit,
                                    options: HKStatisticsOptions,
                                    days: Int = 30,
                                    scale: Double = 1.0) async -> MetricFetchResult? {
        guard let qType = HKQuantityType.quantityType(forIdentifier: hkID) else { return nil }
        let cal = Calendar.current
        let now = Date()
        let anchor = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else { return nil }

        let fetched: [MetricValue]? = await withCheckedContinuation { (cont: CheckedContinuation<[MetricValue]?, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: qType,
                quantitySamplePredicate: nil,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results = results else { cont.resume(returning: nil); return }
                var history: [MetricValue] = []
                results.enumerateStatistics(from: start, to: now) { stats, _ in
                    let q: HKQuantity?
                    if options.contains(.cumulativeSum) {
                        q = stats.sumQuantity()
                    } else if options.contains(.discreteAverage) {
                        q = stats.averageQuantity()
                    } else if options.contains(.mostRecent) {
                        q = stats.mostRecentQuantity()
                    } else {
                        q = nil
                    }
                    guard let q else { return }
                    let v = q.doubleValue(for: unit) * scale
                    history.append(MetricValue(date: stats.startDate, value: v))
                }
                cont.resume(returning: history)
            }
            healthStore.execute(query)
        }
        guard let fetched else { return nil }
        return MetricFetchResult(type: metric, value: nil, history: fetched)
    }


    /// Today's logged food items as a flat list. Groups samples by
    /// `HKMetadataKeyFoodType` + minute-bucketed startDate so each entry
    /// represents one meal/snack regardless of how many quantity samples
    /// it spans (the log_food tool writes 4 — kcal, protein, carbs, fat).
    private func fetchTodayFoodLog() async -> [FoodLogEntry] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        struct Key: Hashable { let name: String; let minute: TimeInterval }
        struct Acc { var cal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0; var time: Date }

        var bucket: [Key: Acc] = [:]

        // Fetch all 4 dietary nutrient types; merge by (name, minute).
        let pairs: [(HKQuantityTypeIdentifier, HKUnit, WritableKeyPath<Acc, Double>)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), \Acc.cal),
            (.dietaryProtein,        .gram(),        \Acc.protein),
            (.dietaryCarbohydrates,  .gram(),        \Acc.carbs),
            (.dietaryFatTotal,       .gram(),        \Acc.fat)
        ]
        for (id, unit, kp) in pairs {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            for s in samples {
                // Prefer the explicit food name we tag on the sample; fall
                // back to the source app's display name; finally "Meal".
                let name = (s.metadata?[HKMetadataKeyFoodType] as? String)
                    ?? s.sourceRevision.source.name
                    ?? "Meal"
                // Bucket by minute so a single log_food's 4-sample batch
                // collapses into one entry. Tolerant of slight start-date
                // drift across samples within the same write.
                let minuteBucket = floor(s.startDate.timeIntervalSince1970 / 60) * 60
                let key = Key(name: name, minute: minuteBucket)
                var acc = bucket[key] ?? Acc(time: s.startDate)
                acc[keyPath: kp] += s.quantity.doubleValue(for: unit)
                bucket[key] = acc
            }
        }

        return bucket.map { (key, acc) in
            FoodLogEntry(name: key.name,
                         calories: acc.cal,
                         protein: acc.protein,
                         carbs: acc.carbs,
                         fat: acc.fat,
                         loggedAt: acc.time)
        }
        .sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Return the full snapshot of today's food log as plain dicts (for the
    /// Astra `list_food_log` tool). Each entry's `id` is the UUID string of
    /// its `dietaryEnergyConsumed` sample — pass that back to `update_food_log`
    /// or `delete_food_log` to operate on the exact meal.
    public func listAppFoodToday() async -> [[String: Any]] {
        guard let kcalType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let kcalSamples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: kcalType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }

        let iso = ISO8601DateFormatter()
        var out: [[String: Any]] = []
        for k in kcalSamples {
            let name = (k.metadata?[HKMetadataKeyFoodType] as? String) ?? k.sourceRevision.source.name
            if let meal = await loadFullMeal(matchingKcal: k) {
                out.append([
                    "id": k.uuid.uuidString,
                    "name": name,
                    "calories": meal.kcal,
                    "protein": meal.protein,
                    "carbs": meal.carbs,
                    "fat": meal.fat,
                    "logged_at": iso.string(from: k.startDate)
                ])
            }
        }
        return out
    }

    /// Find the full meal (all 4 dietary samples) anchored by a single
    /// `dietaryEnergyConsumed` sample's UUID. Returns the matched samples
    /// (so caller can delete) plus the aggregate macro values.
    private struct FullMeal {
        let name: String
        let start: Date
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let samples: [HKObject]
    }

    private func loadFullMeal(byId id: String) async -> FullMeal? {
        guard let uuid = UUID(uuidString: id),
              let kcalType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return nil
        }
        let pred = HKQuery.predicateForObject(with: uuid)
        let kcalSample: HKQuantitySample? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: kcalType, predicate: pred, limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample])?.first)
            }
            healthStore.execute(q)
        }
        guard let k = kcalSample else { return nil }
        return await loadFullMeal(matchingKcal: k)
    }

    private func loadFullMeal(matchingKcal k: HKQuantitySample) async -> FullMeal? {
        let name = (k.metadata?[HKMetadataKeyFoodType] as? String) ?? "Meal"
        let start = k.startDate
        // log_food writes all 4 samples with the exact same start = end timestamp.
        // Use a 1-second forward window to catch any third-party writes that
        // might be off by tens of microseconds.
        let windowEnd = start.addingTimeInterval(1)
        let pred = HKQuery.predicateForSamples(withStart: start, end: windowEnd, options: [.strictStartDate])

        let types: [(HKQuantityTypeIdentifier, HKUnit)] = [
            (.dietaryEnergyConsumed, .kilocalorie()),
            (.dietaryProtein, .gram()),
            (.dietaryCarbohydrates, .gram()),
            (.dietaryFatTotal, .gram())
        ]

        var allMatches: [HKObject] = []
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        for (id, unit) in types {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            // Filter to samples that match the kcal sample's food-name metadata
            // so we don't accidentally collapse two distinct meals logged in
            // the same second (rare, but possible with backfill imports).
            let matching = samples.filter {
                ($0.metadata?[HKMetadataKeyFoodType] as? String) == name
            }
            allMatches.append(contentsOf: matching)
            let sum = matching.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            switch id {
            case .dietaryEnergyConsumed: kcal = sum
            case .dietaryProtein: protein = sum
            case .dietaryCarbohydrates: carbs = sum
            case .dietaryFatTotal: fat = sum
            default: break
            }
        }
        guard !allMatches.isEmpty else { return nil }
        return FullMeal(name: name, start: start,
                        kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                        samples: allMatches)
    }

    /// Write a `SleepSession` (from `SleepSessionManager`) to HealthKit as
    /// `HKCategoryValueSleepAnalysis.asleepUnspecified` samples. We split
    /// the session into segments based on the on-device motion-derived stage
    /// breakdown so the Health app's sleep timeline shows light vs deep.
    /// "In bed" covers the full startedAt → endedAt window; "asleep" segments
    /// cover onsetAt → endedAt.
    public func writeSleepSession(_ session: SleepSession) async -> Bool {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return false }

        var samples: [HKCategorySample] = []

        // In-bed segment: full session.
        samples.append(HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: session.startedAt,
            end: session.endedAt
        ))

        // Asleep segments: classify each 30-s motion sample based on its
        // kind. Adjacent samples of the same class are merged into one
        // segment to keep the Health app timeline readable.
        let postOnset = session.motionSamples.filter { $0.at >= session.onsetAt }
        if !postOnset.isEmpty {
            let windowSec: TimeInterval = 30
            var i = 0
            while i < postOnset.count {
                let kind = postOnset[i].kind
                let start = postOnset[i].at
                var j = i
                while j + 1 < postOnset.count && postOnset[j + 1].kind == kind {
                    j += 1
                }
                let end = postOnset[j].at.addingTimeInterval(windowSec)
                let value: Int
                switch kind {
                case .stillness: value = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                case .micro:     value = HKCategoryValueSleepAnalysis.asleepCore.rawValue
                case .gross:     value = HKCategoryValueSleepAnalysis.awake.rawValue
                }
                samples.append(HKCategorySample(type: sleepType, value: value, start: start, end: end))
                i = j + 1
            }
        } else {
            // No post-onset samples (very short session) — write one bulk
            // asleep segment so HK at least registers the time.
            if session.onsetAt < session.endedAt {
                samples.append(HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    start: session.onsetAt,
                    end: session.endedAt
                ))
            }
        }

        do {
            try await healthStore.save(samples)
            await fetchTodayData()
            return true
        } catch {
            print("Failed to write sleep session: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete a meal by its dietaryEnergyConsumed sample UUID. Removes all 4
    /// related dietary samples (kcal + protein + carbs + fat) that share the
    /// food name + start time. HK will refuse if the samples weren't written
    /// by this app — that's the right behavior.
    public func deleteAppFood(id: String) async -> Bool {
        guard let meal = await loadFullMeal(byId: id) else { return false }
        do {
            try await healthStore.delete(meal.samples)
            await refreshDietaryNow()
            return true
        } catch {
            print("Failed to delete food samples: \(error.localizedDescription)")
            return false
        }
    }

    /// Edit a meal by deleting the existing samples and writing fresh ones
    /// with any provided overrides applied. nil-valued fields preserve the
    /// existing value, so partial updates (just the name, just the calories)
    /// work cleanly. The startDate is preserved.
    public func updateAppFood(id: String,
                              name: String?,
                              calories: Double?,
                              protein: Double?,
                              carbs: Double?,
                              fat: Double?) async -> Bool {
        guard let meal = await loadFullMeal(byId: id) else { return false }
        do {
            try await healthStore.delete(meal.samples)
        } catch {
            print("Failed to delete during update: \(error.localizedDescription)")
            return false
        }
        let newName = name ?? meal.name
        let newKcal = calories ?? meal.kcal
        let newProtein = protein ?? meal.protein
        let newCarbs = carbs ?? meal.carbs
        let newFat = fat ?? meal.fat
        // Re-log at the original timestamp so the meal stays at the original time.
        let ok = await logFood(name: newName,
                               calories: newKcal,
                               protein: newProtein,
                               carbs: newCarbs,
                               fat: newFat,
                               date: meal.start,
                               isEstimate: true,
                               confidence: nil)
        if ok { await refreshDietaryNow() }
        return ok
    }

    /// Refresh only the dietary state — used after a successful `log_food`
    /// write so the next Coach turn / Health Meter recompute sees the new
    /// data without re-fetching all of HK.
    public func refreshDietaryNow() async {
        async let kcal = fetchTodayDietaryEnergy()
        async let protein = fetchTodayDietaryProtein()
        async let log = fetchTodayFoodLog()
        async let history = fetchDietaryEnergyHistory(days: 7)
        let (k, p, l, h) = await (kcal, protein, log, history)
        await MainActor.run {
            self.dietaryCaloriesToday = k
            self.dietaryProteinToday = p
            self.todayFoodLog = l
            self.dietaryCalories7Day = h
            // Health Meter's nutrition sub-score depends on these — recompute.
            self.recomputePredictions()
        }
    }

    /// Today's dietary energy intake (kcal). Sums any `dietaryEnergyConsumed`
    /// samples in the current calendar day, regardless of source (log_food
    /// tool, MyFitnessPal, etc).
    private func fetchTodayDietaryEnergy() async -> Double {
        await fetchTodaySum(hkID: .dietaryEnergyConsumed, unit: .kilocalorie())
    }

    /// Today's dietary protein intake (grams).
    private func fetchTodayDietaryProtein() async -> Double {
        await fetchTodaySum(hkID: .dietaryProtein, unit: .gram())
    }

    /// Generic today-sum helper used by the dietary fetches above.
    private func fetchTodaySum(hkID: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: hkID) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: v)
            }
            healthStore.execute(q)
        }
    }

    /// Last N days of dietary energy intake (kcal sum per day, oldest → newest).
    private func fetchDietaryEnergyHistory(days: Int) async -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return Array(repeating: 0, count: max(days, 1))
        }
        let cal = Calendar.current
        let now = Date()
        let anchor = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else {
            return Array(repeating: 0, count: max(days, 1))
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<[Double], Never>) in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            q.initialResultsHandler = { _, results, _ in
                var byDay: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: now) { stats, _ in
                    let v = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    byDay[cal.startOfDay(for: stats.startDate)] = v
                }
                var out: [Double] = []
                for offset in stride(from: days - 1, through: 0, by: -1) {
                    if let d = cal.date(byAdding: .day, value: -offset, to: anchor) {
                        out.append(byDay[d] ?? 0)
                    }
                }
                cont.resume(returning: out)
            }
            healthStore.execute(q)
        }
    }

    /// 24 hourly step buckets for today (index = hour-of-day, 0...23). Used
    /// by the sedentary-alert prediction. Single `HKStatisticsCollectionQuery`
    /// with hourly intervals — one extra round-trip on the foreground refresh.
    private func fetchHourlyStepsToday() async -> [Double] {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return Array(repeating: 0, count: 24)
        }
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { (cont: CheckedContinuation<[Double], Never>) in
            let q = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: DateComponents(hour: 1)
            )
            q.initialResultsHandler = { _, results, _ in
                var buckets = Array(repeating: 0.0, count: 24)
                guard let results else { cont.resume(returning: buckets); return }
                results.enumerateStatistics(from: startOfDay, to: now) { stats, _ in
                    let hour = cal.component(.hour, from: stats.startDate)
                    guard (0..<24).contains(hour) else { return }
                    buckets[hour] = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                }
                cont.resume(returning: buckets)
            }
            healthStore.execute(q)
        }
    }

    /// Per-day cache key prefix for AI-enriched predictions. Cache survives
    /// across cold launches within the same calendar day so cold-launching
    /// twice doesn't burn two Vertex calls.
    private static let aiCachePrefix = "prediction_ai_"

    private static func cacheKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return aiCachePrefix + f.string(from: date)
    }

    private func loadCachedEnrichment(for date: Date) -> PredictionAIService.EnrichmentBundle? {
        let key = Self.cacheKey(for: date)
        guard let data = UserDefaults.standard.data(forKey: key),
              let bundle = try? JSONDecoder().decode(PredictionAIService.EnrichmentBundle.self, from: data) else {
            return nil
        }
        return bundle
    }

    private func saveCachedEnrichment(_ bundle: PredictionAIService.EnrichmentBundle, for date: Date) {
        let key = Self.cacheKey(for: date)
        if let data = try? JSONEncoder().encode(bundle) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Invalidate today's AI cache. Called by pull-to-refresh so a manual
    /// refresh always re-runs the AI layer with fresh inputs.
    public func invalidateAIPredictionCache() {
        let key = Self.cacheKey(for: Date())
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Public alias for the AI context — needed by PredictionWhySheet which
    /// lives outside HealthKitManager but uses the same prompt prelude.
    public func aiUserContextForWhySheet() -> String {
        buildAIUserContext()
    }

    /// Trimmed user-context string shipped to Vertex with every AI prediction
    /// request. Smaller than the chat system prompt — only what's needed for
    /// short structured tasks. ~400-500 tokens.
    private func buildAIUserContext() -> String {
        let ud = UserDefaults.standard
        let name = ud.string(forKey: "athlete_name") ?? "—"
        let dobIv = ud.double(forKey: "athlete_dob")
        let heightCm = ud.double(forKey: "athlete_height_cm")
        let weightKg = ud.double(forKey: "athlete_weight_kg")
        let appSex = ud.string(forKey: "athlete_sex") ?? ""
        let coachPer = ud.string(forKey: "coach_personality") ?? "Direct"
        let goalsRaw = ud.string(forKey: "training_goals") ?? ""

        let (hkDob, hkSex, _) = readMedicalIdCharacteristics()
        let dobDate: Date? = dobIv > 0 ? Date(timeIntervalSince1970: dobIv) : hkDob
        let age: String = {
            guard let d = dobDate else { return "—" }
            return String(Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 0)
        }()
        let sexLabel: String = {
            if !appSex.isEmpty { return appSex }
            switch hkSex ?? .notSet {
            case .female: return "Female"
            case .male: return "Male"
            case .other: return "Other"
            default: return "—"
            }
        }()
        let useMetric = Locale.current.measurementSystem == .metric
        let unitsLabel = useMetric ? "metric" : "imperial"
        let tz = TimeZone.current.identifier

        // Brief 7-day metric snapshot — just the means, no full history strings.
        func mean(_ values: [Double]) -> Double {
            let nz = values.filter { $0 > 0 }
            guard !nz.isEmpty else { return 0 }
            return nz.reduce(0, +) / Double(nz.count)
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func last7(_ type: HealthMetricType) -> [Double] {
            guard let h = metricSummaries[type]?.history else { return [] }
            var byDay: [Date: Double] = [:]
            for v in h {
                let day = cal.startOfDay(for: v.date)
                byDay[day, default: 0] += v.value
            }
            var out: [Double] = []
            for offset in 0..<7 {
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                out.append(byDay[d] ?? 0)
            }
            return out
        }
        let stepsAvg = mean(last7(.steps))
        let sleepAvg = mean(last7(.sleep))
        let rhrAvg = mean(last7(.restingHeartRate))
        let hrvAvg = mean(last7(.hrv))

        return """
        USER PROFILE
        - Name: \(name)
        - Sex: \(sexLabel), Age: \(age)
        - Height: \(heightCm > 0 ? "\(Int(heightCm)) cm" : "—"), Weight: \(weightKg > 0 ? String(format: "%.1f kg", weightKg) : "—")
        - Coach style: \(coachPer)
        - Training goals: \(goalsRaw.isEmpty ? "none set" : goalsRaw)

        SETUP
        - Apple Watch / wearable HR data: \(hasWatchClassData ? "yes — Watch / chest strap detected in last 7 days" : "NO — user is iPhone-only. They do NOT own an Apple Watch.")
        - Timezone: \(tz)
        - Units: \(unitsLabel)

        7-DAY BASELINES (for trend math — compare today against these, never population norms)
        - Steps avg: \(Int(stepsAvg.rounded()))
        - Sleep avg: \(String(format: "%.1f", sleepAvg)) h
        - Resting HR avg: \(rhrAvg > 0 ? String(format: "%.0f bpm", rhrAvg) : "—")
        - HRV avg: \(hrvAvg > 0 ? String(format: "%.0f ms", hrvAvg) : "—")

        DEVICE ATTRIBUTION RULES (CRITICAL)
        \(hasWatchClassData
          ? "- This user has a Watch / wearable. You MAY mention it when describing HR-derived data."
          : "- This user is IPHONE-ONLY. They do NOT have an Apple Watch. NEVER say 'your Apple Watch', 'your Watch', or 'your wearable' in any output. Steps come from iPhone's motion sensor, period. Don't suggest pairing a Watch in an explanation (a different surface owns that nudge).")
        - Pace projections / catch-up math / scores are computed by THIS APP'S engine — not by the Watch, not by the iPhone. Never attribute calculations to a device. Phrase as "at your current pace…", "your projected end-of-day is…", "your trend suggests…" — never "your Watch/iPhone projects…".

        STYLE
        - Be brief and personal. Use the user's own baselines.
        - Surface ONE thing at a time per output. Don't pad.
        - Never invent numbers or claim safety without grounds.
        - Never invent hardware. If the SETUP block says iPhone-only, the user has no Watch.
        """
    }

    /// Token used to detect snapshot replacement: if `predictions.generatedAt`
    /// changed while the AI task was in flight, the result is stale and we
    /// should not write it back.
    private var lastEnrichmentTargetTimestamp: Date?

    /// Kicks off the AI enrichment for the latest `predictions` snapshot.
    /// Fire-and-forget — completes async and updates `predictions` again
    /// when it lands. Reads cache first; only calls the network on cache miss.
    private func kickoffAIEnrichmentIfNeeded() {
        guard let p = predictions else { return }
        // Skip when no point: baseline state or already enriched.
        guard p.aiEnrichmentStatus == .pending else { return }
        if let needed = p.insufficientHistoryDays, needed > 0 { return }

        // Snapshot-replacement guard token.
        let target = p.generatedAt
        lastEnrichmentTargetTimestamp = target

        // 1) Same-day cache hit → attach immediately, no API call.
        if let cached = loadCachedEnrichment(for: Date()) {
            let merged = p.merging(insight: cached.insight,
                                   actions: cached.actions,
                                   anomalyInterpretations: cached.anomalyInterpretations,
                                   status: .cached)
            predictions = merged
            return
        }

        // 2) Cache miss → call Vertex.
        let userContext = buildAIUserContext()
        Task { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await PredictionAIService.shared.enrichPredictions(p, userContext: userContext)
                await MainActor.run {
                    // Only assign if the snapshot we kicked off for is still current.
                    guard self.lastEnrichmentTargetTimestamp == target,
                          let current = self.predictions,
                          current.generatedAt == target else { return }
                    let merged = current.merging(insight: bundle.insight,
                                                 actions: bundle.actions,
                                                 anomalyInterpretations: bundle.anomalyInterpretations,
                                                 status: .complete)
                    self.predictions = merged
                    self.saveCachedEnrichment(bundle, for: Date())
                }
            } catch {
                await MainActor.run {
                    guard self.lastEnrichmentTargetTimestamp == target,
                          let current = self.predictions,
                          current.generatedAt == target else { return }
                    // Mark failed so the UI can render a "Retry insights" chip.
                    self.predictions = current.merging(insight: nil,
                                                       actions: [],
                                                       anomalyInterpretations: [:],
                                                       status: .failed)
                }
            }
        }
    }

    /// Manually trigger an AI enrichment retry without re-fetching HealthKit
    /// data — used by the card's "Retry insights" chip after a failure.
    public func retryAIEnrichment() {
        guard let p = predictions else { return }
        // Reset to .pending so kickoffAIEnrichmentIfNeeded re-attempts.
        predictions = p.merging(insight: p.dailyInsight,
                                actions: p.actions,
                                anomalyInterpretations: [:],
                                status: .pending)
        invalidateAIPredictionCache()
        kickoffAIEnrichmentIfNeeded()
    }

    /// Build a `PredictionEngine.Snapshot` from the latest metric summaries +
    /// caches and assign the engine's result to `predictions`. Runs sync on
    /// MainActor — the engine math is ≤5 ms in practice.
    private func recomputePredictions() {
        let now = Date()
        let cal = Calendar.current

        // Helper: extract a [Double] for the last N daily buckets from history,
        // ordered oldest → newest. Missing days are zero-filled so empty days
        // don't lie about pace.
        func lastNDays(_ history: [MetricValue], days: Int) -> [Double] {
            guard days > 0 else { return [] }
            let today = cal.startOfDay(for: now)
            var byDay: [Date: Double] = [:]
            for v in history {
                let key = cal.startOfDay(for: v.date)
                byDay[key, default: 0] += v.value
            }
            var out: [Double] = []
            for offset in stride(from: days - 1, through: 0, by: -1) {
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                out.append(byDay[d] ?? 0)
            }
            return out
        }

        // Most-recent-non-zero from a history array — already used by SleepCard.
        func mostRecentNonZero(_ history: [MetricValue]) -> Double? {
            history.last(where: { $0.value > 0 })?.value
        }

        let sleepHistoryAll = metricSummaries[.sleep]?.history ?? []
        let hrvHistoryAll = metricSummaries[.hrv]?.history ?? []
        let rhrHistoryAll = metricSummaries[.restingHeartRate]?.history ?? []
        let stepsHistoryAll = metricSummaries[.steps]?.history ?? []
        let activeEnergyHistoryAll = metricSummaries[.activeEnergy]?.history ?? []
        let exerciseHistoryAll = metricSummaries[.exerciseMinutes]?.history ?? []

        let sleep28 = lastNDays(sleepHistoryAll, days: 28).filter { $0 > 0 }
        let hrv28 = lastNDays(hrvHistoryAll, days: 28).filter { $0 > 0 }
        let rhr28 = lastNDays(rhrHistoryAll, days: 28).filter { $0 > 0 }

        // Training load — sum durations across workouts in respective windows.
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let twentyEightDaysAgo = cal.date(byAdding: .day, value: -28, to: now) ?? now
        let acute = recentWorkouts28
            .filter { $0.startDate >= sevenDaysAgo }
            .reduce(0.0) { $0 + $1.duration / 60.0 }
        let chronic = recentWorkouts28
            .filter { $0.startDate >= twentyEightDaysAgo }
            .reduce(0.0) { $0 + $1.duration / 60.0 }

        // Per-day kcal-load for the last 28 days (oldest → newest, zero-filled).
        // Uses the same kcal / duration-proxy math as TrainingLoadEngine.
        let dailyKcalLoad28: [Double] = {
            let today = cal.startOfDay(for: now)
            var loadByDay: [Date: Double] = [:]
            for w in recentWorkouts28 {
                let day = cal.startOfDay(for: w.startDate)
                let load: Double
                if let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()), kcal > 0 {
                    load = kcal
                } else {
                    load = (w.duration / 60.0) * 8.0
                }
                loadByDay[day, default: 0] += load
            }
            var out: [Double] = []
            for offset in stride(from: 27, through: 0, by: -1) {
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { out.append(0); continue }
                out.append(loadByDay[d] ?? 0)
            }
            return out
        }()

        // Pre-map workouts to ActivityCategory + weekday/hour.
        let mapped: [PredictionEngine.WorkoutSample] = recentWorkouts28.map { w in
            PredictionEngine.WorkoutSample(
                category: Self.activityCategory(for: w.workoutActivityType),
                weekday: cal.component(.weekday, from: w.startDate),
                hour: cal.component(.hour, from: w.startDate),
                durationMinutes: w.duration / 60.0
            )
        }

        let stepsNonZeroDayCount: Int = {
            var count = 0
            let today = cal.startOfDay(for: now)
            var byDay: [Date: Double] = [:]
            for v in stepsHistoryAll {
                let key = cal.startOfDay(for: v.date)
                byDay[key, default: 0] += v.value
            }
            for (day, value) in byDay where day <= today && value > 0 { count += 1 }
            return count
        }()

        // Health Meter inputs ---------------------------------------------
        let ud = UserDefaults.standard
        let heightCm: Double? = {
            let v = ud.double(forKey: "athlete_height_cm")
            return v > 0 ? v : nil
        }()
        let weightKg: Double? = {
            let v = ud.double(forKey: "athlete_weight_kg")
            return v > 0 ? v : nil
        }()

        let hydrationHistoryAll = metricSummaries[.hydration]?.history ?? []
        let mindfulHistoryAll = metricSummaries[.mindfulMinutes]?.history ?? []

        // Goal-suggestion inputs: 28 zero-filled daily values + current goal for
        // each user-configurable metric.
        var goalHistories28: [String: [Double]] = [:]
        var userGoals: [String: Double] = [:]
        for type in HealthMetricType.allCases where type.isUserConfigurableGoal {
            let history = metricSummaries[type]?.history ?? []
            goalHistories28[type.rawValue] = lastNDays(history, days: 28)
            userGoals[type.rawValue] = Self.userGoal(for: type)
        }

        let snapshot = PredictionEngine.Snapshot(
            now: now,
            hasWatchClassData: hasWatchClassData,
            lastNightSleepHours: mostRecentNonZero(sleepHistoryAll) ?? 0,
            lastNightHRV: mostRecentNonZero(hrvHistoryAll),
            lastNightRHR: mostRecentNonZero(rhrHistoryAll),
            hrvHistory28: hrv28,
            rhrHistory28: rhr28,
            sleepHistory28NonZero: sleep28,
            hrvHistory30: lastNDays(hrvHistoryAll, days: 30),
            rhrHistory30: lastNDays(rhrHistoryAll, days: 30),
            sleepHistory30: lastNDays(sleepHistoryAll, days: 30),
            stepsHistory30: lastNDays(stepsHistoryAll, days: 30),
            activeEnergyHistory30: lastNDays(activeEnergyHistoryAll, days: 30),
            hydrationHistory30: lastNDays(hydrationHistoryAll, days: 30),
            mindfulMinutesHistory30: lastNDays(mindfulHistoryAll, days: 30),
            stepsHistory14: lastNDays(stepsHistoryAll, days: 14),
            activeEnergyHistory14: lastNDays(activeEnergyHistoryAll, days: 14),
            exerciseMinutesHistory14: lastNDays(exerciseHistoryAll, days: 14),
            stepsToday: metricSummaries[.steps]?.currentValue ?? 0,
            activeEnergyToday: metricSummaries[.activeEnergy]?.currentValue ?? 0,
            exerciseMinutesToday: metricSummaries[.exerciseMinutes]?.currentValue ?? 0,
            acuteLoadMinutes: acute,
            chronicLoadMinutes: chronic,
            dailyKcalLoad28: dailyKcalLoad28,
            workouts28: mapped,
            hourlyStepsToday: hourlyStepsToday,
            stepsHistoryNonZeroDayCount: stepsNonZeroDayCount,
            heightCm: heightCm,
            weightKg: weightKg,
            dietaryCaloriesToday: dietaryCaloriesToday,
            dietaryCalories7Day: dietaryCalories7Day,
            dietaryProteinToday: dietaryProteinToday,
            hydrationToday: metricSummaries[.hydration]?.currentValue ?? 0,
            hydration7Day: lastNDays(hydrationHistoryAll, days: 7),
            mindfulMinutes7Day: lastNDays(mindfulHistoryAll, days: 7),
            vo2Max: (metricSummaries[.vo2Max]?.currentValue).flatMap { $0 > 0 ? $0 : nil },
            walkingSpeedToday: (metricSummaries[.walkingSpeed]?.currentValue).flatMap { $0 > 0 ? $0 : nil },
            walkingAsymmetryToday: (metricSummaries[.walkingAsymmetry]?.currentValue).flatMap { $0 > 0 ? $0 : nil },
            recentSymptoms: recentSymptoms14,
            goalHistories28: goalHistories28,
            userGoals: userGoals
        )

        let newPredictions = PredictionEngine.computeAll(snapshot: snapshot)

        // Diff-aware: the engine stamps a fresh `generatedAt` on every run, so a
        // plain `==` always differs. Compare the content signature (everything
        // EXCEPT generatedAt) and only republish — re-rendering the whole tree —
        // when something meaningful actually changed.
        if predictions?.contentSignature != newPredictions.contentSignature {
            predictions = newPredictions
        }

        // Schedule or cancel a sedentary local notification based on the latest
        // snapshot. Cheap + idempotent, so run it every time off the fresh result.
        let sedentary = newPredictions.sedentary
        NotificationManager.shared.updateSedentaryAlert(
            severity: sedentary?.severity,
            quietHours: sedentary?.quietHours ?? 0
        )
    }

    /// Coarse activity grouping for prediction. Mirrors the heuristics used
    /// in `WorkoutTrackerView.workoutTitle`.
    private static func activityCategory(for t: HKWorkoutActivityType) -> ActivityCategory {
        switch t {
        case .running: return .run
        case .walking, .hiking: return .walk
        case .cycling: return .cycle
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            return .strength
        case .yoga, .mindAndBody, .pilates, .flexibility, .barre:
            return .yoga
        case .highIntensityIntervalTraining, .coreTraining:
            return .hiit
        case .swimming, .waterFitness, .waterSports:
            return .swim
        default:
            return .other
        }
    }

    /// Recent workouts (default: last 7 days), sorted newest first.
    public func fetchRecentWorkouts(days: Int = 7) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { (cont: CheckedContinuation<[HKWorkout], Never>) in
            let q = HKSampleQuery(sampleType: HKSampleType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(q)
        }
    }

    /// Consecutive days ending today where step history met the goal. Walks
    /// backward from today, breaks on the first miss. Today counts only if the
    /// goal is already hit (so the number doesn't reset to 0 each morning).
    public func dayStreak(goalRatio: Double = 1.0) -> Int {
        guard let steps = metricSummaries[.steps], steps.goal > 0 else { return 0 }
        let cal = Calendar.current
        let byDay = Dictionary(steps.history.map {
            (cal.startOfDay(for: $0.date), $0.value)
        }, uniquingKeysWith: max)
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while let v = byDay[day], v >= steps.goal * goalRatio {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Earliest non-empty history sample across all populated metric summaries.
    /// Used to backfill `account_created_date` for users upgrading from an
    /// older build that didn't stamp the key.
    public func earliestHistoryDate() -> Date? {
        metricSummaries.values
            .compactMap { $0.history.first?.date }
            .min()
    }

    /// Read Medical-ID characteristic types. Returns (dateOfBirth, biologicalSex, bloodType).
    /// All nil if HealthKit can't supply the value (Medical ID empty, or no auth).
    /// Used by onboarding's About You step to pre-fill the form and by the chat
    /// coach's system prompt for the Medical Profile block.
    public func readMedicalIdCharacteristics() -> (dob: Date?, biologicalSex: HKBiologicalSex?, bloodType: HKBloodType?) {
        var dob: Date? = nil
        if let comps = try? healthStore.dateOfBirthComponents() {
            dob = Calendar.current.date(from: comps)
        }
        let sex = (try? healthStore.biologicalSex().biologicalSex)
        let blood = (try? healthStore.bloodType().bloodType)
        return (dob, sex, blood)
    }

    /// Read HealthKit clinical records (allergies, conditions, medications) for
    /// the system prompt's Medical Profile. Empty arrays if the user hasn't
    /// linked a provider in Apple Health — never assume empty == none.
    /// Only fires when the user has opted in via Settings (clinical records
    /// auth is gated separately from regular HealthKit auth).
    public func readClinicalRecords() async -> (allergies: [String], conditions: [String], medications: [String]) {
        async let allergies   = clinicalTitles(for: .allergyRecord)
        async let conditions  = clinicalTitles(for: .conditionRecord)
        async let medications = clinicalTitles(for: .medicationRecord)
        return (await allergies, await conditions, await medications)
    }

    private func clinicalTitles(for id: HKClinicalTypeIdentifier) async -> [String] {
        guard clinicalRecordsRequested,
              let t = HKObjectType.clinicalType(forIdentifier: id) else { return [] }
        return await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            let q = HKSampleQuery(sampleType: t, predicate: nil, limit: 50, sortDescriptors: nil) { _, samples, _ in
                let titles = (samples as? [HKClinicalRecord])?.compactMap { $0.displayName } ?? []
                cont.resume(returning: Array(Set(titles)).sorted())
            }
            healthStore.execute(q)
        }
    }

    /// 30-day daily history of mindful session duration (minutes). Category sample
    /// table only, so this can't share the quantity helper.
        private func fetchMindfulHistory(days: Int = 30) async -> MetricFetchResult? {
        guard let t = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let cal = Calendar.current
        let now = Date()
        let anchor = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let fetched: [MetricValue]? = await withCheckedContinuation { (cont: CheckedContinuation<[MetricValue]?, Never>) in
            let query = HKSampleQuery(sampleType: t, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                var byDay: [Date: Double] = [:]
                for sample in samples {
                    let day = cal.startOfDay(for: sample.startDate)
                    byDay[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                }
                var history: [MetricValue] = []
                var d = start
                while d <= now {
                    let day = cal.startOfDay(for: d)
                    history.append(MetricValue(date: day, value: byDay[day] ?? 0))
                    guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                    d = next
                }
                cont.resume(returning: history)
            }
            healthStore.execute(query)
        }
        guard let fetched else { return nil }
        return MetricFetchResult(type: .mindfulMinutes, value: nil, history: fetched)
    }


    /// Last 14 days of HK category symptom samples mapped to SymptomEntry.
    /// Covers the authorized symptom identifiers confirmed by the scout.
    /// Returns [] when no samples exist (honest empty). Chronological.
    private func fetchSymptomHistory() async -> [SymptomEntry] {
        let symptomIDs: [(HKCategoryTypeIdentifier, String)] = [
            (.fatigue,       "Fatigue"),
            (.headache,      "Headache"),
            (.nausea,        "Nausea"),
            (.dizziness,     "Dizziness"),
            (.fever,         "Fever"),
            (.vomiting,      "Vomiting"),
            (.abdominalCramps, "Abdominal Cramps"),
            (.bloating,      "Bloating"),
            (.constipation,  "Constipation"),
            (.diarrhea,      "Diarrhea"),
            (.heartburn,     "Heartburn"),
            (.acne,          "Acne"),
            (.hotFlashes,    "Hot Flashes"),
            (.moodChanges,   "Mood Changes"),
            (.sleepChanges,  "Sleep Changes")
        ]
        let cal = Calendar.current
        let now = Date()
        guard let windowStart = cal.date(byAdding: .day, value: -14, to: now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        var entries: [SymptomEntry] = []
        for (identifier, displayName) in symptomIDs {
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { continue }
            let samples: [HKCategorySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                    cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
                healthStore.execute(q)
            }
            for s in samples {
                let severity: String
                switch s.value {
                case HKCategoryValueSeverity.notPresent.rawValue:
                    continue
                case HKCategoryValueSeverity.mild.rawValue:
                    severity = "mild"
                case HKCategoryValueSeverity.moderate.rawValue:
                    severity = "moderate"
                case HKCategoryValueSeverity.severe.rawValue:
                    severity = "severe"
                default:
                    severity = "present"
                }
                entries.append(SymptomEntry(date: s.startDate, name: displayName, severity: severity))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Start-of-day dates with a menstrualFlow sample in the last 60 days.
    /// Returns [] when no samples exist. Chronological, unique per day.
    private func fetchMenstrualFlowDays() async -> [Date] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else { return [] }
        let cal = Calendar.current
        let now = Date()
        guard let windowStart = cal.date(byAdding: .day, value: -60, to: now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(q)
        }
        var seen: Set<Date> = []
        var days: [Date] = []
        for s in samples {
            let day = cal.startOfDay(for: s.startDate)
            if seen.insert(day).inserted { days.append(day) }
        }
        return days.sorted()
    }

    // --- UI State Modifiers ---

    private func updateMetricValue(type: HealthMetricType, value: Double) {
        if var summary = metricSummaries[type] {
            summary.currentValue = value
            metricSummaries[type] = summary
        }
    }
    
    private func updateMetricHistory(type: HealthMetricType, history: [MetricValue]) {
        if var summary = metricSummaries[type] {
            summary.history = history
            metricSummaries[type] = summary
        }
    }
}
