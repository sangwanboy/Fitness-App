import Foundation
import HealthKit

// MARK: - Supporting types

public struct DailyLoad: Identifiable {
    public let id: Date
    public let date: Date
    public let load: Double  // kcal or duration-estimate

    public init(date: Date, load: Double) {
        self.id = date
        self.date = date
        self.load = load
    }
}

public struct WeeklyVolume: Identifiable {
    public let id: String          // ISO week string, e.g. "2026-W22"
    public let weekStart: Date
    public let totalLoad: Double
    public let isCurrentWeek: Bool

    public init(id: String, weekStart: Date, totalLoad: Double, isCurrentWeek: Bool) {
        self.id = id
        self.weekStart = weekStart
        self.totalLoad = totalLoad
        self.isCurrentWeek = isCurrentWeek
    }
}

public struct PersonalRecords {
    public let longestWorkout: HKWorkout?
    public let highestCalories: HKWorkout?
    public let mostActiveDaysInWeek: Int
    public let currentWeekStreak: Int

    public init(longestWorkout: HKWorkout?,
                highestCalories: HKWorkout?,
                mostActiveDaysInWeek: Int,
                currentWeekStreak: Int) {
        self.longestWorkout = longestWorkout
        self.highestCalories = highestCalories
        self.mostActiveDaysInWeek = mostActiveDaysInWeek
        self.currentWeekStreak = currentWeekStreak
    }
}

public enum ACWRZone {
    case optimal     // 0.8 – 1.3   green
    case caution     // 1.3 – 1.5   amber
    case overreach   // > 1.5        red
    case low         // < 0.8        blue (under-training)

    public init(acwr: Double) {
        switch acwr {
        case ..<0.8:           self = .low
        case 0.8..<1.3:        self = .optimal
        case 1.3..<1.5:        self = .caution
        default:               self = .overreach
        }
    }

    public var label: String {
        switch self {
        case .optimal:   return "Optimal"
        case .caution:   return "Caution"
        case .overreach: return "Overreach Risk"
        case .low:       return "Under-Training"
        }
    }

    public var subtitle: String {
        switch self {
        case .optimal:
            return "Training load is optimal — good time to push."
        case .caution:
            return "Elevated load — consider an easier day or active recovery."
        case .overreach:
            return "High overreach risk — take a rest day to avoid injury."
        case .low:
            return "Low training load — increasing volume is safe and beneficial."
        }
    }

    /// SwiftUI Color name as a string to avoid importing SwiftUI here.
    /// Consumers can match on this or use the accentSystemColor property.
    public var colorName: String {
        switch self {
        case .optimal:   return "green"
        case .caution:   return "orange"
        case .overreach: return "red"
        case .low:       return "blue"
        }
    }
}

// MARK: - Engine

public final class TrainingLoadEngine: ObservableObject {

    @Published public var dailyLoads: [DailyLoad] = []
    @Published public var acuteLoad: Double = 0     // 7-day rolling average
    @Published public var chronicLoad: Double = 0   // 28-day rolling average
    @Published public var acwr: Double = 0
    @Published public var acwrZone: ACWRZone = .low
    @Published public var weeklyVolumes: [WeeklyVolume] = []
    @Published public var personalRecords: PersonalRecords = PersonalRecords(
        longestWorkout: nil,
        highestCalories: nil,
        mostActiveDaysInWeek: 0,
        currentWeekStreak: 0
    )
    @Published public var isComputing: Bool = false

    public init() {}

    /// Feed the engine with the 28-day workout list from HealthKitManager.
    /// Computation is synchronous within a background Task so it never blocks
    /// the main thread.
    public func compute(from workouts: [HKWorkout]) {
        isComputing = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let cal = Calendar.current
            let now = Date()
            let windowStart = cal.startOfDay(
                for: cal.date(byAdding: .day, value: -27, to: now)!
            )

            // --- 1. Build daily-load map (one entry per calendar day) ---
            var loadByDay: [Date: Double] = [:]
            for workout in workouts {
                let day = cal.startOfDay(for: workout.startDate)
                guard day >= windowStart else { continue }
                let load = Self.workoutLoad(workout)
                loadByDay[day, default: 0] += load
            }

            // Fill every day in the 28-day window (0 if no workout).
            var loads: [DailyLoad] = []
            var cursor = windowStart
            while cursor <= cal.startOfDay(for: now) {
                loads.append(DailyLoad(date: cursor, load: loadByDay[cursor] ?? 0))
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }

            // --- 2. Rolling averages ---
            let allLoadValues = loads.map { $0.load }
            let acute = Self.rollingAverage(allLoadValues, days: 7)
            let chronic = Self.rollingAverage(allLoadValues, days: 28)
            let ratio = acute / max(chronic, 1.0)

            // --- 3. Weekly volumes (last 8 ISO weeks) ---
            let currentWeekOfYear = cal.component(.weekOfYear, from: now)
            let currentYear = cal.component(.year, from: now)

            var weekMap: [String: (start: Date, total: Double)] = [:]
            for entry in loads {
                guard entry.load > 0 else { continue }
                let weekOfYear = cal.component(.weekOfYear, from: entry.date)
                let year = cal.component(.yearForWeekOfYear, from: entry.date)
                let key = "\(year)-W\(String(format: "%02d", weekOfYear))"
                // Find Monday of that week
                var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
                comps.weekday = 2  // Monday
                let monday = cal.date(from: comps) ?? entry.date
                if let existing = weekMap[key] {
                    weekMap[key] = (existing.start, existing.total + entry.load)
                } else {
                    weekMap[key] = (monday, entry.load)
                }
            }

            // Sort into chronological order and take last 8 weeks.
            let sortedWeeks = weekMap
                .sorted { $0.value.start < $1.value.start }
                .suffix(8)
                .map { (key, val) -> WeeklyVolume in
                    let woy = cal.component(.weekOfYear, from: val.start)
                    let yr = cal.component(.yearForWeekOfYear, from: val.start)
                    let isCurrent = (woy == currentWeekOfYear && yr == currentYear)
                    return WeeklyVolume(
                        id: key,
                        weekStart: val.start,
                        totalLoad: val.total,
                        isCurrentWeek: isCurrent
                    )
                }

            // --- 4. Personal records ---
            let longest = workouts.max { a, b in a.duration < b.duration }
            let highCal = workouts.max { a, b in
                let ac = a.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
                let bc = b.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
                return ac < bc
            }

            // Most active days in any single week within the window.
            var activeDaysByWeek: [String: Set<Date>] = [:]
            for workout in workouts {
                let day = cal.startOfDay(for: workout.startDate)
                let woy = cal.component(.weekOfYear, from: day)
                let yr = cal.component(.yearForWeekOfYear, from: day)
                let key = "\(yr)-W\(woy)"
                activeDaysByWeek[key, default: []].insert(day)
            }
            let maxActiveDays = activeDaysByWeek.values.map { $0.count }.max() ?? 0

            // Consecutive active weeks ending this week (week streak).
            let weekStreak = Self.computeWeekStreak(workouts: workouts, calendar: cal, now: now)

            let prs = PersonalRecords(
                longestWorkout: longest,
                highestCalories: highCal,
                mostActiveDaysInWeek: maxActiveDays,
                currentWeekStreak: weekStreak
            )

            // Publish on main actor.
            await MainActor.run {
                self.dailyLoads = loads
                self.acuteLoad = acute
                self.chronicLoad = chronic
                self.acwr = ratio
                self.acwrZone = ACWRZone(acwr: ratio)
                self.weeklyVolumes = Array(sortedWeeks)
                self.personalRecords = prs
                self.isComputing = false
            }
        }
    }

    // MARK: - Private helpers

    /// Load for a single workout: active energy kcal, or duration-minutes * 8
    /// as a proxy when no energy is recorded (strength workouts often lack it).
    private static func workoutLoad(_ w: HKWorkout) -> Double {
        if let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()), kcal > 0 {
            return kcal
        }
        return (w.duration / 60.0) * 8.0  // 8 kcal/min proxy
    }

    /// Rolling average of the last `days` values in a series. Returns the mean
    /// of those final values (or all values if fewer than `days` exist).
    private static func rollingAverage(_ values: [Double], days: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let slice = values.suffix(days)
        let nonZero = slice.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return slice.reduce(0, +) / Double(slice.count)
    }

    /// Consecutive weeks (ending this week) during which the athlete had at
    /// least one workout. Returns 0 if there was no workout in the current week.
    private static func computeWeekStreak(workouts: [HKWorkout],
                                          calendar: Calendar,
                                          now: Date) -> Int {
        // Build a set of ISO week keys that had at least one workout.
        var activeWeeks: Set<String> = []
        for w in workouts {
            let woy = calendar.component(.weekOfYear, from: w.startDate)
            let yr = calendar.component(.yearForWeekOfYear, from: w.startDate)
            activeWeeks.insert("\(yr)-W\(woy)")
        }

        let thisWOY = calendar.component(.weekOfYear, from: now)
        let thisYr = calendar.component(.yearForWeekOfYear, from: now)

        // Must have at least one workout this week to start counting.
        guard activeWeeks.contains("\(thisYr)-W\(thisWOY)") else { return 0 }

        var streak = 1
        var checkDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        // Only look back as far as our 28-day window (4 weeks).
        for _ in 0..<4 {
            let woy = calendar.component(.weekOfYear, from: checkDate)
            let yr = calendar.component(.yearForWeekOfYear, from: checkDate)
            if activeWeeks.contains("\(yr)-W\(woy)") {
                streak += 1
                checkDate = calendar.date(byAdding: .weekOfYear, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        return streak
    }
}
