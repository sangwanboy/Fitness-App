import Foundation

// MARK: - Shared

public enum PredictionConfidence: String, Codable {
    case low
    case medium
    case high

    public var displayLabel: String {
        switch self {
        case .low: return "Low confidence"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }
}

public struct PredictionExplanation: Codable, Equatable {
    public var bullets: [String]

    public init(bullets: [String] = []) {
        self.bullets = bullets
    }
}

/// A single logged symptom — user-reported, used only to *corroborate*
/// physiological strain signals in the illness early-warning, never to trigger
/// one on its own.
public struct SymptomEntry: Codable, Equatable {
    public let date: Date
    public let name: String        // display name, e.g. "Fatigue", "Headache"
    public let severity: String    // "present" | "mild" | "moderate" | "severe"
    public init(date: Date, name: String, severity: String) { self.date = date; self.name = name; self.severity = severity }
}

// MARK: - Recovery Readiness

public enum RecoveryLabel: String, Codable {
    case strong       // green, "Push hard"
    case moderate     // yellow-green, "Steady"
    case low          // amber, "Easy day"
    case rest         // red, "Rest day"

    public var headline: String {
        switch self {
        case .strong: return "Push hard"
        case .moderate: return "Steady"
        case .low: return "Easy day"
        case .rest: return "Rest day"
        }
    }
}

public struct RecoveryReadiness: Codable, Equatable {
    public let score: Int                  // 0...100
    public let label: RecoveryLabel
    public let confidence: PredictionConfidence
    public let usedHRV: Bool
    public let usedRHR: Bool
    public let explanation: PredictionExplanation

    public init(score: Int, label: RecoveryLabel, confidence: PredictionConfidence,
                usedHRV: Bool, usedRHR: Bool, explanation: PredictionExplanation) {
        self.score = score
        self.label = label
        self.confidence = confidence
        self.usedHRV = usedHRV
        self.usedRHR = usedRHR
        self.explanation = explanation
    }
}

// MARK: - Next Likely Workout

/// Coarse activity grouping used for pattern detection — broader than
/// HKWorkoutActivityType so HIIT / strength / mixed users still produce
/// meaningful patterns instead of fragmenting across 30+ raw cases.
public enum ActivityCategory: String, Codable {
    case run
    case walk
    case cycle
    case strength
    case yoga
    case hiit
    case swim
    case other

    public var displayName: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Cycle"
        case .strength: return "Strength"
        case .yoga: return "Yoga"
        case .hiit: return "HIIT"
        case .swim: return "Swim"
        case .other: return "Workout"
        }
    }

    public var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .yoga: return "figure.yoga"
        case .hiit: return "bolt.fill"
        case .swim: return "figure.pool.swim"
        case .other: return "figure.mixed.cardio"
        }
    }
}

public struct NextWorkoutForecast: Codable, Equatable {
    public let category: ActivityCategory
    public let startHour: Int              // 24h, 0...23 — bucket start (e.g. 6 means "6–9 AM")
    public let endHour: Int                // 24h, bucket end exclusive
    public let confidence: PredictionConfidence
    public let support: Double             // 0...1 — ratio of recent weeks the pattern repeats
    public let isCategoryFallback: Bool    // true when only a time-of-day pattern emerged
    public let weekdayLabel: String        // "today" / "tomorrow" / "Mon"

    public init(category: ActivityCategory, startHour: Int, endHour: Int,
                confidence: PredictionConfidence, support: Double,
                isCategoryFallback: Bool, weekdayLabel: String) {
        self.category = category
        self.startHour = startHour
        self.endHour = endHour
        self.confidence = confidence
        self.support = support
        self.isCategoryFallback = isCategoryFallback
        self.weekdayLabel = weekdayLabel
    }
}

// MARK: - Goal Trajectory

public enum TrajectoryStatus: String, Codable {
    case aheadOfPace
    case onPace
    case behind
    case farBehind

    public var headline: String {
        switch self {
        case .aheadOfPace: return "Ahead of pace"
        case .onPace: return "On pace"
        case .behind: return "Behind"
        case .farBehind: return "Far behind"
        }
    }
}

public struct GoalTrajectory: Codable, Equatable {
    public let metric: HealthMetricType
    public let currentValue: Double
    public let projectedEOD: Double         // projected end-of-day value at current pace
    public let baselineEOD: Double          // 14-day mean for this metric
    public let pace: Double                 // 1.0 = on pace
    public let status: TrajectoryStatus
    public let confidence: PredictionConfidence

    public init(metric: HealthMetricType, currentValue: Double, projectedEOD: Double,
                baselineEOD: Double, pace: Double, status: TrajectoryStatus,
                confidence: PredictionConfidence) {
        self.metric = metric
        self.currentValue = currentValue
        self.projectedEOD = projectedEOD
        self.baselineEOD = baselineEOD
        self.pace = pace
        self.status = status
        self.confidence = confidence
    }
}

extension HealthMetricType: Codable {}

// MARK: - Sedentary Alert

public enum SedentarySeverity: String, Codable {
    case moderate
    case high
}

public struct SedentaryAlert: Codable, Equatable {
    public let quietHours: Int             // number of consecutive sub-250-step hours
    public let lastActiveHour: Int?        // 24h hour-of-day of the last active bucket; nil if none today
    public let severity: SedentarySeverity
    public let dayTotalSoFar: Int          // step count so far today
    public let baselineDayTotal: Int       // 14-day mean step total

    public init(quietHours: Int, lastActiveHour: Int?, severity: SedentarySeverity,
                dayTotalSoFar: Int, baselineDayTotal: Int) {
        self.quietHours = quietHours
        self.lastActiveHour = lastActiveHour
        self.severity = severity
        self.dayTotalSoFar = dayTotalSoFar
        self.baselineDayTotal = baselineDayTotal
    }
}

// MARK: - Health Meter (composite wellness score)

public enum HealthMeterLabel: String, Codable {
    case excellent  // 85+
    case good       // 65–84
    case fair       // 45–64
    case needsWork  // <45

    public var headline: String {
        switch self {
        case .excellent: return "Excellent"
        case .good:      return "Good"
        case .fair:      return "Fair"
        case .needsWork: return "Needs work"
        }
    }
}

/// 0–100 composite score blending activity, nutrition, body composition, and
/// vitals signals. Computed deterministically by the engine from already-fetched
/// HK data — no AI involvement in the number itself.
public struct HealthMeterScore: Codable, Equatable {
    public let score: Int              // 0...100
    public let label: HealthMeterLabel
    public let confidence: PredictionConfidence

    // Sub-scores (max in parens). Sum equals `score`.
    public let activityScore: Int      // 0...30
    public let nutritionScore: Int     // 0...30
    public let bodyScore: Int          // 0...18
    public let vitalsScore: Int        // 0...22

    public let explanation: PredictionExplanation

    /// Whether the user has actual nutrition data — if false, nutrition
    /// sub-score is a neutral estimate and the card flags it.
    public let usedNutrition: Bool
    /// Whether any meal was logged TODAY. `usedNutrition` can be true off the
    /// 7-day window alone — surfaces must not claim food was logged today
    /// unless this is also true.
    public let mealsLoggedToday: Bool
    /// Whether the user has height + weight to compute BMI — if false, body
    /// sub-score is a neutral estimate.
    public let usedBMI: Bool

    public init(score: Int, label: HealthMeterLabel, confidence: PredictionConfidence,
                activityScore: Int, nutritionScore: Int, bodyScore: Int,
                vitalsScore: Int,
                explanation: PredictionExplanation,
                usedNutrition: Bool, mealsLoggedToday: Bool, usedBMI: Bool) {
        self.score = score
        self.label = label
        self.confidence = confidence
        self.activityScore = activityScore
        self.nutritionScore = nutritionScore
        self.bodyScore = bodyScore
        self.vitalsScore = vitalsScore
        self.explanation = explanation
        self.usedNutrition = usedNutrition
        self.mealsLoggedToday = mealsLoggedToday
        self.usedBMI = usedBMI
    }
}

// MARK: - Anomaly (engine-detected; AI may enrich with interpretation)

public enum AnomalySeverity: String, Codable {
    case low
    case moderate
    case high

    public var displayLabel: String {
        switch self {
        case .low: return "Mild"
        case .moderate: return "Notable"
        case .high: return "Significant"
        }
    }
}

public struct Anomaly: Codable, Equatable, Identifiable {
    public let id: UUID
    public let metric: HealthMetricType
    public let direction: String         // "low" | "high" — which way the value drifted
    public let zScore: Double            // signed z-score vs the user's own baseline
    public let today: Double
    public let baseline: Double
    public let severity: AnomalySeverity
    /// AI-generated, ≤2 sentences. nil while enrichment is pending or after a failure.
    public var interpretation: String?

    public init(id: UUID = UUID(),
                metric: HealthMetricType,
                direction: String,
                zScore: Double,
                today: Double,
                baseline: Double,
                severity: AnomalySeverity,
                interpretation: String? = nil) {
        self.id = id
        self.metric = metric
        self.direction = direction
        self.zScore = zScore
        self.today = today
        self.baseline = baseline
        self.severity = severity
        self.interpretation = interpretation
    }
}

// MARK: - Illness Early-Warning

/// Surfaced when resting heart rate, HRV, and sleep all drift in the
/// strain direction for ≥ 2 consecutive days. This is NOT a diagnosis —
/// copy must frame it as early physiological strain signals only.
public struct IllnessWarning: Codable, Equatable {
    public let severity: AnomalySeverity        // .moderate | .high only
    public let rhrDeltaBpm: Double              // today RHR minus 28-day baseline (positive = elevated)
    public let hrvDropPct: Double               // percent below 28-day baseline (positive = drop)
    public let sleepDebtHours: Double           // cumulative deficit vs baseline across the flagged window
    public let consecutiveDays: Int             // days the pattern has held (>= 2 to surface)
    public let explanation: PredictionExplanation

    public init(severity: AnomalySeverity, rhrDeltaBpm: Double, hrvDropPct: Double,
                sleepDebtHours: Double, consecutiveDays: Int,
                explanation: PredictionExplanation) {
        self.severity = severity
        self.rhrDeltaBpm = rhrDeltaBpm
        self.hrvDropPct = hrvDropPct
        self.sleepDebtHours = sleepDebtHours
        self.consecutiveDays = consecutiveDays
        self.explanation = explanation
    }
}

// MARK: - Metric Correlation

/// A deterministic Pearson correlation between two daily metric series,
/// optionally lagged. Honest, no causality claims beyond "tends".
public struct MetricCorrelation: Codable, Equatable, Identifiable {
    public var id: String { metricA.rawValue + "-" + metricB.rawValue + "-" + String(lagDays) }
    public let metricA: HealthMetricType        // driver
    public let metricB: HealthMetricType        // outcome
    public let lagDays: Int                     // 0 same-day, 1 next-day
    public let r: Double                        // Pearson, |r| >= 0.45 to surface
    public let sampleDays: Int                  // >= 12 overlapping valid days required
    public let insight: String                  // deterministic template sentence quoting direction

    public init(metricA: HealthMetricType, metricB: HealthMetricType, lagDays: Int,
                r: Double, sampleDays: Int, insight: String) {
        self.metricA = metricA
        self.metricB = metricB
        self.lagDays = lagDays
        self.r = r
        self.sampleDays = sampleDays
        self.insight = insight
    }
}

// MARK: - AI-generated layers

public struct DailyInsight: Codable, Equatable {
    public let headline: String          // 8-15 words
    public let body: String              // 1-2 sentences
    public let confidence: PredictionConfidence
    public let generatedAt: Date

    public init(headline: String, body: String, confidence: PredictionConfidence, generatedAt: Date = Date()) {
        self.headline = headline
        self.body = body
        self.confidence = confidence
        self.generatedAt = generatedAt
    }
}

public enum ActionCategory: String, Codable {
    case workout
    case nutrition
    case recovery
    case planning
    case other

    public var displayColor: String {
        switch self {
        case .workout:   return "blue"
        case .nutrition: return "orange"
        case .recovery:  return "purple"
        case .planning:  return "indigo"
        case .other:     return "gray"
        }
    }
}

public struct ActionSuggestion: Codable, Equatable, Identifiable {
    public let id: UUID
    public let icon: String              // SF Symbol name
    public let title: String             // ≤24 chars chip label
    public let prefillPrompt: String     // sent verbatim to Astra when tapped
    public let category: ActionCategory

    public init(id: UUID = UUID(),
                icon: String,
                title: String,
                prefillPrompt: String,
                category: ActionCategory) {
        self.id = id
        self.icon = icon
        self.title = title
        self.prefillPrompt = prefillPrompt
        self.category = category
    }
}

/// Identifies which prediction the user tapped "Why?" on, so the AI can
/// stream an explanation tailored to that one.
public enum PredictionKind: String, Codable, Identifiable {
    case recovery
    case nextWorkout
    case trajectory
    case sedentary
    case healthMeter
    case illness
    case correlations

    public var id: String { rawValue }
}

/// Lifecycle state of the optional AI enrichment layered on top of the
/// deterministic engine. Drives the "Retry insights" chip UI.
public enum EnrichmentStatus: String, Codable {
    case skipped         // didn't attempt (baseline state, or Vertex not configured)
    case pending         // engine returned, AI is in flight
    case complete        // AI landed successfully
    case failed          // AI errored / timed out — deterministic-only
    case cached          // pulled from yesterday's cache (same calendar day)
}

// MARK: - Top-Level Container

public struct Predictions: Codable, Equatable {
    public let generatedAt: Date
    public let recovery: RecoveryReadiness?
    public let nextWorkout: NextWorkoutForecast?
    public let trajectories: [GoalTrajectory]
    public let sedentary: SedentaryAlert?

    /// Composite wellness score from activity + nutrition + body + vitals.
    /// Always computed when the user has at least 5 days of
    /// step history; otherwise nil (baseline state).
    public let healthMeter: HealthMeterScore?

    /// Engine-detected anomalies. `interpretation` field is populated by AI
    /// once enrichment lands; nil before then.
    public let anomalies: [Anomaly]

    /// AI-generated daily insight. nil before enrichment / on failure.
    public let dailyInsight: DailyInsight?

    /// AI-suggested action chips. Empty before enrichment / on failure.
    public let actions: [ActionSuggestion]

    /// On-device illness early-warning. nil when the pattern doesn't hold or
    /// the user has no HRV/RHR data (Watch-less) — never guessed.
    public let illnessWarning: IllnessWarning?

    /// On-device cross-metric correlations (top 3 by |r|). Empty when nothing
    /// clears the sample-size / magnitude bar.
    public let correlations: [MetricCorrelation]

    /// Lifecycle of the AI layer for UI gating.
    public let aiEnrichmentStatus: EnrichmentStatus

    /// When > 0, the user doesn't yet have enough HK history to compute
    /// reliable predictions. The card renders a "Building baseline · Day N of 7"
    /// state instead. nil or 0 means baseline is established.
    public let insufficientHistoryDays: Int?

    public init(generatedAt: Date = Date(),
                recovery: RecoveryReadiness? = nil,
                nextWorkout: NextWorkoutForecast? = nil,
                trajectories: [GoalTrajectory] = [],
                sedentary: SedentaryAlert? = nil,
                healthMeter: HealthMeterScore? = nil,
                anomalies: [Anomaly] = [],
                dailyInsight: DailyInsight? = nil,
                actions: [ActionSuggestion] = [],
                illnessWarning: IllnessWarning? = nil,
                correlations: [MetricCorrelation] = [],
                aiEnrichmentStatus: EnrichmentStatus = .pending,
                insufficientHistoryDays: Int? = nil) {
        self.generatedAt = generatedAt
        self.recovery = recovery
        self.nextWorkout = nextWorkout
        self.trajectories = trajectories
        self.sedentary = sedentary
        self.healthMeter = healthMeter
        self.anomalies = anomalies
        self.dailyInsight = dailyInsight
        self.actions = actions
        self.illnessWarning = illnessWarning
        self.correlations = correlations
        self.aiEnrichmentStatus = aiEnrichmentStatus
        self.insufficientHistoryDays = insufficientHistoryDays
    }

    /// Equatable signature over the *meaningful* prediction fields, EXCLUDING
    /// `generatedAt`. `Predictions` is `Equatable`, but because `generatedAt` is
    /// stamped fresh on every `computeAll`, a plain `==` always differs even when
    /// nothing of substance changed. Comparing `contentSignature` instead lets a
    /// recompute that produced an identical result skip the `@Published`
    /// reassignment — and the whole-tree re-render it would trigger.
    public struct ContentSignature: Equatable {
        let recovery: RecoveryReadiness?
        let nextWorkout: NextWorkoutForecast?
        let trajectories: [GoalTrajectory]
        let sedentary: SedentaryAlert?
        let healthMeter: HealthMeterScore?
        let anomalies: [Anomaly]
        let dailyInsight: DailyInsight?
        let actions: [ActionSuggestion]
        let illnessWarning: IllnessWarning?
        let correlations: [MetricCorrelation]
        let aiEnrichmentStatus: EnrichmentStatus
        let insufficientHistoryDays: Int?
    }

    public var contentSignature: ContentSignature {
        ContentSignature(
            recovery: recovery,
            nextWorkout: nextWorkout,
            trajectories: trajectories,
            sedentary: sedentary,
            healthMeter: healthMeter,
            anomalies: anomalies,
            dailyInsight: dailyInsight,
            actions: actions,
            illnessWarning: illnessWarning,
            correlations: correlations,
            aiEnrichmentStatus: aiEnrichmentStatus,
            insufficientHistoryDays: insufficientHistoryDays
        )
    }

    /// True when nothing actionable surfaced — render the empty / baseline state.
    public var isEmpty: Bool {
        recovery == nil && nextWorkout == nil && trajectories.isEmpty && sedentary == nil
            && healthMeter == nil
            && anomalies.isEmpty && dailyInsight == nil && actions.isEmpty
            && illnessWarning == nil && correlations.isEmpty
    }

    /// Return a copy with the AI layer fields swapped in (engine fields unchanged).
    public func merging(insight: DailyInsight?,
                        actions: [ActionSuggestion],
                        anomalyInterpretations: [UUID: String],
                        status: EnrichmentStatus) -> Predictions {
        var newAnomalies = self.anomalies
        for i in newAnomalies.indices {
            if let text = anomalyInterpretations[newAnomalies[i].id] {
                newAnomalies[i].interpretation = text
            }
        }
        return Predictions(
            generatedAt: generatedAt,
            recovery: recovery,
            nextWorkout: nextWorkout,
            trajectories: trajectories,
            sedentary: sedentary,
            healthMeter: healthMeter,
            anomalies: newAnomalies,
            dailyInsight: insight,
            actions: actions,
            illnessWarning: illnessWarning,
            correlations: correlations,
            aiEnrichmentStatus: status,
            insufficientHistoryDays: insufficientHistoryDays
        )
    }
}
