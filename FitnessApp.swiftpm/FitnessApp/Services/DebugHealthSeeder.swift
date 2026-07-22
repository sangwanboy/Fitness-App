#if DEBUG
import Foundation
import HealthKit

/// DEBUG-only synthetic HealthKit seeder so the Simulator — which has no
/// real wearable — can exercise WP-J's stale-data paths and WP-K's rMSSD
/// path. Writes real samples into the sim's local HealthKit store. Never
/// compiled into a Release build (see the `#if DEBUG` wrapping this whole
/// file, and the matching `#if DEBUG` block in
/// `HealthKitManager.requestAuthorization` that extends the app's WRITE
/// share set with the few types this seeder needs but the shipping app
/// never writes — resting heart rate, HRV, and heartbeat series).
enum DebugHealthSeeder {
    enum Scenario {
        /// Steps/active-energy TODAY (iPhone-sourced), RHR + HRV samples
        /// dated 2 days ago, and an HR sample 2 days ago (establishes
        /// `hasWatchClassData` without any HR in the last 18h) — exercises
        /// WP-J's STALE tags + the watch-not-worn banner.
        case staleWatch
        /// HR/HRV/RHR recent + a synthetic overnight heartbeat series (~60
        /// beats, ~800ms R-R + small jitter) inside a resting window —
        /// exercises WP-K's rMSSD path end-to-end.
        case freshDay
    }

    struct SeedResult {
        let summary: String
        let heartbeatSeriesWritten: Bool
    }

    private static let healthStore = HKHealthStore()

    @MainActor
    static func seed(_ scenario: Scenario) async -> SeedResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return SeedResult(summary: "HealthKit isn't available on this device.", heartbeatSeriesWritten: false)
        }
        // Re-request authorization through the app's own manager so the
        // DEBUG-only share types (RHR, HRV, heartbeat series) are actually
        // granted, even on a sim that finished onboarding before this shipped.
        guard await HealthKitManager.shared.requestAuthorization() else {
            return SeedResult(summary: "HealthKit authorization was denied — can't seed.", heartbeatSeriesWritten: false)
        }

        switch scenario {
        case .staleWatch: return await seedStaleWatch()
        case .freshDay: return await seedFreshDay()
        }
    }

    // MARK: - staleWatch

    private static func seedStaleWatch() async -> SeedResult {
        let now = Date()
        let cal = Calendar.current
        var samples: [HKObject] = []

        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            samples.append(HKQuantitySample(type: stepsType,
                                            quantity: HKQuantity(unit: .count(), doubleValue: 3200),
                                            start: cal.startOfDay(for: now), end: now,
                                            device: .local(), metadata: nil))
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(type: energyType,
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 180),
                                            start: cal.startOfDay(for: now), end: now,
                                            device: .local(), metadata: nil))
        }

        // RHR + HRV + a raw HR sample all dated 2 days ago — establishes
        // `hasWatchClassData` (any HR-class sample in the last 7 days) while
        // leaving a >18h gap since the last HR reading, so the watch-gap
        // banner + STALE tags both fire on the next fetchTodayData().
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now) ?? now.addingTimeInterval(-2 * 86_400)
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            samples.append(HKQuantitySample(type: rhrType,
                                            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 58),
                                            start: twoDaysAgo, end: twoDaysAgo))
        }
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            samples.append(HKQuantitySample(type: hrvType,
                                            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 45),
                                            start: twoDaysAgo, end: twoDaysAgo))
        }
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            samples.append(HKQuantitySample(type: hrType,
                                            quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 64),
                                            start: twoDaysAgo, end: twoDaysAgo))
        }

        do {
            try await healthStore.save(samples)
            return SeedResult(
                summary: "Seeded staleWatch: steps+energy today (iPhone), RHR/HRV/HR dated 2d ago. Pull to refresh — expect STALE tags + the watch-not-worn banner.",
                heartbeatSeriesWritten: false
            )
        } catch {
            return SeedResult(summary: "staleWatch seed failed: \(error.localizedDescription)", heartbeatSeriesWritten: false)
        }
    }

    // MARK: - freshDay

    private static func seedFreshDay() async -> SeedResult {
        let now = Date()
        let cal = Calendar.current
        var samples: [HKObject] = []

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            samples.append(HKQuantitySample(type: hrType,
                                            quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 62),
                                            start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-600),
                                            device: .local(), metadata: nil))
        }
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            samples.append(HKQuantitySample(type: hrvType,
                                            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 52),
                                            start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-3600)))
        }
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            samples.append(HKQuantitySample(type: rhrType,
                                            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 56),
                                            start: now, end: now))
        }

        do {
            try await healthStore.save(samples)
        } catch {
            return SeedResult(summary: "freshDay vitals seed failed: \(error.localizedDescription)", heartbeatSeriesWritten: false)
        }

        guard #available(iOS 16.0, *) else {
            return SeedResult(summary: "Seeded freshDay vitals; heartbeat series needs iOS 16+ (unavailable on this OS).", heartbeatSeriesWritten: false)
        }

        // Series start: the most recent local 01:00 that's still in the
        // past, so it always lands inside fetchRestingRMSSD's 36h lookback
        // AND its local hour (1) always falls in the 22:00–10:00 resting
        // window, no matter what time of day the seeder is run.
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 1; comps.minute = 0; comps.second = 0
        var seriesStart = cal.date(from: comps) ?? now.addingTimeInterval(-6 * 3600)
        if seriesStart > now {
            seriesStart = cal.date(byAdding: .day, value: -1, to: seriesStart) ?? seriesStart.addingTimeInterval(-86_400)
        }

        let builder = HKHeartbeatSeriesBuilder(healthStore: healthStore, device: .local(), start: seriesStart)
        do {
            var elapsed: TimeInterval = 0
            for i in 0..<60 {
                if i > 0 {
                    let jitterMs = Double.random(in: -20...20)
                    elapsed += (800 + jitterMs) / 1000.0
                }
                try await builder.addHeartbeat(at: elapsed, precededByGap: false)
            }
            _ = try await builder.finishSeries()
            return SeedResult(
                summary: "Seeded freshDay: HR/HRV/RHR + a 60-beat resting heartbeat series at \(seriesStart.formatted(date: .abbreviated, time: .shortened)). Pull to refresh — rMSSD should compute on the next fetchTodayData().",
                heartbeatSeriesWritten: true
            )
        } catch {
            return SeedResult(
                summary: "Seeded freshDay vitals; heartbeat series write FAILED: \(error.localizedDescription) — heartbeat series may not be writable for this app in the Simulator.",
                heartbeatSeriesWritten: false
            )
        }
    }
}
#endif
