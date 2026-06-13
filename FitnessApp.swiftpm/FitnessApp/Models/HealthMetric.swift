import SwiftUI

/// Locale-aware DISPLAY conversions. Storage / HealthKit / stored goals stay
/// imperial everywhere (miles, mi/hr, inches) for history + cross-app
/// consistency; these helpers convert ONLY for on-screen display and for the
/// goal-editor slider (which reads/writes the stored imperial value through
/// `milesFromDisplay`). For a UK (metric) user distance shows km, walking
/// speed km/h, step length cm.
public enum LocaleUnits {
    public static var usesMetric: Bool { Locale.current.measurementSystem == .metric }

    // MARK: Distance (stored in miles)
    public static func distanceDisplay(fromMiles miles: Double) -> (value: Double, unit: String) {
        usesMetric ? (miles * 1.60934, "km") : (miles, "mi")
    }
    /// Inverse of `distanceDisplay` — converts a slider/display value back to
    /// the stored miles value. Metric input is km; imperial input is already miles.
    public static func milesFromDisplay(_ v: Double) -> Double {
        usesMetric ? v / 1.60934 : v
    }
    public static var distanceUnit: String { usesMetric ? "km" : "mi" }

    // MARK: Walking speed (stored in mi/hr)
    public static func speedDisplay(fromMph mph: Double) -> (value: Double, unit: String) {
        usesMetric ? (mph * 1.60934, "km/h") : (mph, "mi/hr")
    }
    public static var speedUnit: String { usesMetric ? "km/h" : "mi/hr" }

    // MARK: Walking step length (stored in inches)
    public static func stepLengthDisplay(fromInches inches: Double) -> (value: Double, unit: String) {
        usesMetric ? (inches * 2.54, "cm") : (inches, "in")
    }
    public static var stepLengthUnit: String { usesMetric ? "cm" : "in" }
}

public enum HealthMetricType: String, CaseIterable, Identifiable {
    // Always-on tiles
    case steps
    case heartRate
    case activeEnergy
    case sleep
    case distance
    case hrv
    case hydration

    // Show-more tiles (revealed by the "Show more" toggle on Home)
    case restingHeartRate
    case bodyMass
    case flightsClimbed
    case exerciseMinutes
    case standHours
    case mindfulMinutes
    case oxygenSaturation
    case vo2Max

    // Additional iPhone-trackable show-more tiles
    case restingEnergy            // basalEnergyBurned (kcal)
    case walkingSpeed             // walkingSpeed (mi/hr)
    case walkingStepLength        // walkingStepLength (in)
    case walkingDoubleSupport     // walkingDoubleSupportPercentage (%)
    case walkingAsymmetry         // walkingAsymmetryPercentage (%)
    case headphoneAudio           // headphoneAudioExposure (dBASPL)

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .heartRate: return "Heart Rate"
        case .activeEnergy: return "Calories"
        case .sleep: return "Sleep"
        case .distance: return "Distance"
        case .hrv: return "Recovery (HRV)"
        case .hydration: return "Hydration"
        case .restingHeartRate: return "Resting HR"
        case .bodyMass: return "Weight"
        case .flightsClimbed: return "Flights"
        case .exerciseMinutes: return "Exercise"
        case .standHours: return "Stand"
        case .mindfulMinutes: return "Mindful"
        case .oxygenSaturation: return "Blood O₂"
        case .vo2Max: return "VO₂ Max"
        case .restingEnergy: return "Resting Energy"
        case .walkingSpeed: return "Walking Speed"
        case .walkingStepLength: return "Step Length"
        case .walkingDoubleSupport: return "Double Support"
        case .walkingAsymmetry: return "Walking Asymmetry"
        case .headphoneAudio: return "Headphone Level"
        }
    }

    public var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .heartRate: return "heart.fill"
        case .activeEnergy: return "flame.fill"
        case .sleep: return "bed.double.fill"
        case .distance: return "arrow.triangle.turn.up.right.diamond.fill"
        case .hrv: return "waveform.path.ecg"
        case .hydration: return "drop.fill"
        case .restingHeartRate: return "heart.text.square.fill"
        case .bodyMass: return "scalemass.fill"
        case .flightsClimbed: return "stairs"
        case .exerciseMinutes: return "figure.run"
        case .standHours: return "figure.stand"
        case .mindfulMinutes: return "brain.head.profile"
        case .oxygenSaturation: return "lungs.fill"
        case .vo2Max: return "wind"
        case .restingEnergy: return "bolt.heart.fill"
        case .walkingSpeed: return "gauge.with.dots.needle.67percent"
        case .walkingStepLength: return "ruler.fill"
        case .walkingDoubleSupport: return "figure.walk.motion"
        case .walkingAsymmetry: return "figure.walk.arrival"
        case .headphoneAudio: return "headphones"
        }
    }

    public var unit: String {
        switch self {
        case .steps: return "steps"
        case .heartRate: return "bpm"
        case .activeEnergy: return "kcal"
        case .sleep: return "hrs"
        case .distance: return LocaleUnits.distanceUnit
        case .hrv: return "ms"
        case .hydration: return "L"
        case .restingHeartRate: return "bpm"
        case .bodyMass: return "kg"
        case .flightsClimbed: return "flights"
        case .exerciseMinutes: return "min"
        case .standHours: return "hrs"
        case .mindfulMinutes: return "min"
        case .oxygenSaturation: return "%"
        case .vo2Max: return "ml/kg·min"
        case .restingEnergy: return "kcal"
        case .walkingSpeed: return LocaleUnits.speedUnit
        case .walkingStepLength: return LocaleUnits.stepLengthUnit
        case .walkingDoubleSupport: return "%"
        case .walkingAsymmetry: return "%"
        case .headphoneAudio: return "dB"
        }
    }

    public var themeColor: Color {
        switch self {
        case .steps: return Color(.systemTeal)
        case .heartRate: return Color(.systemRed)
        case .activeEnergy: return Color(.systemOrange)
        case .sleep: return Color(red: 0.68, green: 0.52, blue: 0.98)
        case .distance: return Color(.systemGreen)
        case .hrv: return Color(.systemCyan)
        case .hydration: return Color(.systemBlue)
        case .restingHeartRate: return Color(.systemPink)
        case .bodyMass: return Color(.systemIndigo)
        case .flightsClimbed: return Color(.systemMint)
        case .exerciseMinutes: return Color(red: 0.62, green: 0.91, blue: 0.19)
        case .standHours: return Color(red: 0, green: 0.83, blue: 1)
        case .mindfulMinutes: return Color(.systemPurple)
        case .oxygenSaturation: return Color(.systemBlue)
        case .vo2Max: return Color(.systemYellow)
        case .restingEnergy: return Color(.systemBrown)
        case .walkingSpeed: return Color(.systemTeal)
        case .walkingStepLength: return Color(.systemMint)
        case .walkingDoubleSupport: return Color(red: 0.72, green: 0.62, blue: 0.95)
        case .walkingAsymmetry: return Color(.systemPink)
        case .headphoneAudio: return Color(.systemYellow)
        }
    }

    public var defaultGoal: Double {
        switch self {
        case .steps: return 10000
        case .heartRate: return 120
        case .activeEnergy: return 600
        case .sleep: return 8
        case .distance: return 5.0
        case .hrv: return 100
        case .hydration: return 3.0
        case .restingHeartRate: return 60
        case .bodyMass: return 70
        case .flightsClimbed: return 10
        case .exerciseMinutes: return 30
        case .standHours: return 12
        case .mindfulMinutes: return 10
        case .oxygenSaturation: return 100
        case .vo2Max: return 40
        // Observational metrics — no behavioral goal. defaultGoal returns
        // a representative typical-value so the engine has something to
        // compute a "% of goal" against, but the cards omit goal labels.
        case .restingEnergy: return 1600           // typical adult BMR
        case .walkingSpeed: return 3.0             // ~3 mph average walking pace
        case .walkingStepLength: return 28         // typical inches
        case .walkingDoubleSupport: return 24      // typical %
        case .walkingAsymmetry: return 0           // ideally low
        case .headphoneAudio: return 75            // safe listening dB
        }
    }

    /// Whether the user is allowed to override this metric's goal. Heart-rate,
    /// HRV, RHR, SpO2, VO2max, body mass are personal physiological readings —
    /// not behavioral targets — so they're excluded from the goals editor.
    public var isUserConfigurableGoal: Bool {
        switch self {
        case .steps, .activeEnergy, .sleep, .distance, .hydration,
             .exerciseMinutes, .standHours, .mindfulMinutes, .flightsClimbed:
            return true
        default:
            return false
        }
    }

    /// Slider bounds for the goals editor: (min, max, step). nil for metrics
    /// that aren't user-configurable goals.
    public var goalRange: (min: Double, max: Double, step: Double)? {
        switch self {
        case .steps:           return (3000, 20000, 500)
        case .activeEnergy:    return (200, 1200, 50)
        case .sleep:           return (5.0, 10.0, 0.5)
        case .distance:        return (1.0, 15.0, 0.5)
        case .hydration:       return (1.0, 5.0, 0.25)
        case .exerciseMinutes: return (15, 120, 5)
        case .standHours:      return (6, 16, 1)
        case .mindfulMinutes:  return (5, 60, 5)
        case .flightsClimbed:  return (3, 40, 1)
        default:               return nil
        }
    }
}

public struct MetricValue: Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let value: Double

    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }

    /// Equality compares ONLY content (date + value), ignoring the random
    /// per-instance `id`. Freshly-built history arrays therefore compare equal
    /// when their samples carry the same dates and values — so an unchanged
    /// HealthKit poll produces no spurious `@Published` publish downstream.
    public static func == (lhs: MetricValue, rhs: MetricValue) -> Bool {
        lhs.date == rhs.date && lhs.value == rhs.value
    }
}

/// One logged food item — built from HealthKit dietary samples grouped by
/// `HKMetadataKeyFoodType` + minute-bucketed timestamp. Source-agnostic:
/// items logged via the app's `log_food` tool, MyFitnessPal, or any other
/// Health-writing nutrition app all surface the same way.
public struct FoodLogEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let loggedAt: Date

    public init(id: UUID = UUID(),
                name: String,
                calories: Double,
                protein: Double,
                carbs: Double,
                fat: Double,
                loggedAt: Date) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.loggedAt = loggedAt
    }
}

public struct MetricSummary: Identifiable, Equatable {
    public var id: HealthMetricType { type }
    public let type: HealthMetricType
    public var currentValue: Double
    public var goal: Double
    public var history: [MetricValue]

    public var percentComplete: Double {
        guard goal > 0 else { return 0 }
        if type == .heartRate {
            // Heart rate doesn't use standard completion percentage in the same way, return relative to 180
            return min(currentValue / 180.0, 1.0)
        }
        if type == .hrv {
            return min(currentValue / 150.0, 1.0)
        }
        return min(currentValue / goal, 1.0)
    }
    
    public var displayValueString: String {
        switch type {
        case .steps, .heartRate, .activeEnergy, .hrv, .restingHeartRate,
             .flightsClimbed, .exerciseMinutes, .standHours, .mindfulMinutes,
             .oxygenSaturation, .restingEnergy, .headphoneAudio:
            return String(format: "%.0f", currentValue)
        case .walkingStepLength:
            // Stored in inches; metric region shows cm (whole number).
            return String(format: "%.0f", LocaleUnits.stepLengthDisplay(fromInches: currentValue).value)
        case .sleep, .hydration, .vo2Max,
             .walkingDoubleSupport, .walkingAsymmetry:
            return String(format: "%.1f", currentValue)
        case .walkingSpeed:
            // Stored in mi/hr; metric region shows km/h.
            return String(format: "%.1f", LocaleUnits.speedDisplay(fromMph: currentValue).value)
        case .distance:
            // Stored in miles; metric region shows km. 2 decimals like mi.
            return String(format: "%.2f", LocaleUnits.distanceDisplay(fromMiles: currentValue).value)
        case .bodyMass:
            return String(format: "%.2f", currentValue)
        }
    }

}
