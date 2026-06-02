import Foundation
import HealthKit
import SwiftUI

// MARK: - HRZone

public enum HRZone: Int, CaseIterable, Identifiable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .zone1: return "Zone 1"
        case .zone2: return "Zone 2"
        case .zone3: return "Zone 3"
        case .zone4: return "Zone 4"
        case .zone5: return "Zone 5"
        }
    }

    public var description: String {
        switch self {
        case .zone1: return "Recovery"
        case .zone2: return "Aerobic Base"
        case .zone3: return "Tempo"
        case .zone4: return "Threshold"
        case .zone5: return "VO2 Max"
        }
    }

    public var color: Color {
        switch self {
        case .zone1: return Color(.systemBlue)
        case .zone2: return Color(.systemGreen)
        case .zone3: return Color(.systemYellow)
        case .zone4: return Color(.systemOrange)
        case .zone5: return Color(.systemRed)
        }
    }

    /// Karvonen reserve-zone lower-boundary percentage for this zone.
    /// Zone N lower = zone (N-1) upper = restingHR + reserve * percentLower.
    public var reservePercentLower: Double {
        switch self {
        case .zone1: return 0.50
        case .zone2: return 0.60
        case .zone3: return 0.70
        case .zone4: return 0.80
        case .zone5: return 0.90
        }
    }

    public var reservePercentUpper: Double {
        switch self {
        case .zone1: return 0.60
        case .zone2: return 0.70
        case .zone3: return 0.80
        case .zone4: return 0.90
        case .zone5: return 1.00
        }
    }
}

// MARK: - ZoneThresholds

/// Personalised BPM boundaries computed via the Karvonen formula.
/// reserve = maxHR − restingHR
/// zoneN_lower = restingHR + (reserve × percentLower)
public struct ZoneThresholds {
    public let restingHR: Double
    public let maxHR: Double

    public init(restingHR: Double, maxHR: Double) {
        self.restingHR = max(restingHR, 40)
        self.maxHR     = max(maxHR, restingHR + 10)
    }

    private var reserve: Double { maxHR - restingHR }

    /// Lower BPM bound for a given zone (inclusive).
    public func lowerBPM(for zone: HRZone) -> Double {
        restingHR + reserve * zone.reservePercentLower
    }

    /// Upper BPM bound for a given zone (exclusive, except Zone 5 where it is max).
    public func upperBPM(for zone: HRZone) -> Double {
        restingHR + reserve * zone.reservePercentUpper
    }

    /// Classify a single heart-rate sample into a zone.
    public func zone(for bpm: Double) -> HRZone {
        if bpm >= lowerBPM(for: .zone5) { return .zone5 }
        if bpm >= lowerBPM(for: .zone4) { return .zone4 }
        if bpm >= lowerBPM(for: .zone3) { return .zone3 }
        if bpm >= lowerBPM(for: .zone2) { return .zone2 }
        return .zone1
    }

    /// Human-readable BPM range string for display (e.g. "120 – 139 bpm").
    public func rangeLabel(for zone: HRZone) -> String {
        let lo = Int(lowerBPM(for: zone).rounded())
        let hi = zone == .zone5
            ? "\(Int(maxHR.rounded()))+"
            : String(Int((upperBPM(for: zone) - 1).rounded()))
        return "\(lo) – \(hi) bpm"
    }
}

// MARK: - WorkoutZoneBreakdown

public struct WorkoutZoneBreakdown: Identifiable {
    public let id: UUID
    public let workout: HKWorkout
    public let durationByZone: [HRZone: TimeInterval]
    public let thresholds: ZoneThresholds

    public init(id: UUID = UUID(),
                workout: HKWorkout,
                durationByZone: [HRZone: TimeInterval],
                thresholds: ZoneThresholds) {
        self.id = id
        self.workout = workout
        self.durationByZone = durationByZone
        self.thresholds = thresholds
    }

    /// Total seconds that had at least one HR sample contributing to any zone.
    public var totalActiveSeconds: TimeInterval {
        durationByZone.values.reduce(0, +)
    }

    /// Zone with the highest time-in-zone. nil when no HR data present.
    public var dominantZone: HRZone? {
        durationByZone.max(by: { $0.value < $1.value })?.key
    }

    public var workoutDate: Date { workout.startDate }
}

// MARK: - HeartRateZoneCalculator

@MainActor
public final class HeartRateZoneCalculator: ObservableObject {
    public static let shared = HeartRateZoneCalculator()

    private let healthStore = HKHealthStore()

    // Cached zone breakdowns for the latest batch of workouts.
    @Published public var breakdowns: [WorkoutZoneBreakdown] = []
    @Published public var isLoading = false

    // Persisted max-HR override (0 = use age-estimated value).
    @AppStorage("max_hr_override") public var maxHROverride: Int = 0

    private init() {}

    // MARK: - Public API

    /// Build `ZoneThresholds` using stored or estimated values.
    /// - Parameters:
    ///   - userAge: years, used for "220 − age" when no override is set.
    ///   - restingHR: fallback 60 bpm when HealthKit doesn't have data.
    public func makeThresholds(userAge: Int) -> ZoneThresholds {
        let rhr = HealthKitManager.shared.metricSummaries[.restingHeartRate]?.currentValue ?? 60
        let maxHR: Double = maxHROverride > 0
            ? Double(maxHROverride)
            : Double(max(220 - userAge, 120))
        return ZoneThresholds(restingHR: rhr, maxHR: maxHR)
    }

    /// Fetch heart-rate samples for every workout in `workouts` and compute
    /// time-in-zone buckets. Results are stored in `breakdowns` (published).
    public func computeZoneBreakdowns(for workouts: [HKWorkout], userAge: Int) async {
        guard !workouts.isEmpty else {
            breakdowns = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        let thresholds = makeThresholds(userAge: userAge)
        var results: [WorkoutZoneBreakdown] = []

        for workout in workouts {
            let breakdown = await buildBreakdown(for: workout, thresholds: thresholds)
            results.append(breakdown)
        }

        // Most-recent first.
        breakdowns = results.sorted { $0.workoutDate > $1.workoutDate }
    }

    // MARK: - Private helpers

    private func buildBreakdown(for workout: HKWorkout,
                                 thresholds: ZoneThresholds) async -> WorkoutZoneBreakdown {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return WorkoutZoneBreakdown(workout: workout, durationByZone: [:], thresholds: thresholds)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: [.strictStartDate, .strictEndDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, rawSamples, _ in
                cont.resume(returning: (rawSamples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }

        guard !samples.isEmpty else {
            return WorkoutZoneBreakdown(workout: workout, durationByZone: [:], thresholds: thresholds)
        }

        // Accumulate seconds in each zone using trapezoidal-like interval
        // bucketing: the duration credited to each sample is the gap to the
        // NEXT sample (or to workout end for the final sample).
        var buckets: [HRZone: TimeInterval] = [:]
        let bpmUnit = HKUnit(from: "count/min")

        for (idx, sample) in samples.enumerated() {
            let bpm = sample.quantity.doubleValue(for: bpmUnit)
            let zone = thresholds.zone(for: bpm)

            let intervalEnd: Date = idx + 1 < samples.count
                ? samples[idx + 1].startDate
                : workout.endDate

            // Cap interval to 5 minutes to avoid inflating time when HR data
            // has large gaps (e.g. Apple Watch missed beats mid-workout).
            let interval = min(
                intervalEnd.timeIntervalSince(sample.startDate),
                300
            )
            if interval > 0 {
                buckets[zone, default: 0] += interval
            }
        }

        return WorkoutZoneBreakdown(workout: workout, durationByZone: buckets, thresholds: thresholds)
    }
}
