import SwiftUI
import Foundation
import HealthKit
@preconcurrency import UserNotifications

// MARK: - Models

/// Activity summary for a single calendar week (Mon–Sun).
public struct WeekActivity: Identifiable, Equatable {
    public var id: Date { weekStart }
    /// The Monday that starts this week (start of day, local calendar).
    public let weekStart: Date
    /// True when the week had >= 3 distinct workout days OR >= 4 step-goal days.
    public let isActive: Bool
    /// Number of days within the week that contained at least one HK workout.
    public let workoutDays: Int
    /// Number of days where recorded steps >= the user's step goal.
    public let stepGoalDays: Int
}

/// A collectible milestone badge earned on the Trophy Shelf.
public struct StreakBadge: Identifiable, Codable, Equatable {
    public let id: Int          // milestone week count (1, 4, 8, 13, 26, 52)
    public let earnedDate: Date
}

// MARK: - StreakEngine

/// Singleton that computes weekly activity streaks from HealthKit data
/// already loaded by `HealthKitManager.shared`. All state lives on
/// `@MainActor` so SwiftUI can observe it directly.
@MainActor
public final class StreakEngine: ObservableObject {
    public static let shared = StreakEngine()

    // MARK: Published state

    @Published public private(set) var currentStreak: Int = 0
    @Published public private(set) var longestStreak: Int = 0
    @Published public private(set) var weeklyActivity: [WeekActivity] = []
    @Published public private(set) var earnedBadges: [StreakBadge] = []

    // MARK: Constants

    public static let milestoneMilestones: [Int] = [1, 4, 8, 13, 26, 52]

    private let udLongestKey   = "streak_longest"
    private let udBadgesKey    = "streak_badges_v1"
    private let notifCategory  = "STREAK_MILESTONE"
    private let notifIDPrefix  = "com.fitnessapp.streak."

    private init() {
        longestStreak = UserDefaults.standard.integer(forKey: udLongestKey)
        if let data = UserDefaults.standard.data(forKey: udBadgesKey),
           let decoded = try? JSONDecoder().decode([StreakBadge].self, from: data) {
            earnedBadges = decoded
        }
    }

    // MARK: - Public API

    /// Recompute streaks from the current HealthKitManager state.
    /// Call after every `fetchTodayData()` / workout refresh.
    public func refresh() {
        let hk = HealthKitManager.shared
        let workouts  = hk.recentWorkouts28
        let stepsSummary = hk.metricSummaries[.steps]
        let stepGoal  = HealthKitManager.userGoal(for: .steps)

        let activities = buildWeeklyActivity(
            workouts: workouts,
            stepsHistory: stepsSummary?.history ?? [],
            stepGoal: stepGoal
        )
        weeklyActivity = activities

        let (current, longest) = computeStreaks(from: activities)
        currentStreak = current

        let prevLongest = longestStreak
        if longest > prevLongest {
            longestStreak = longest
            UserDefaults.standard.set(longest, forKey: udLongestKey)
        }

        checkAndAwardBadges(currentStreak: current)
    }

    // MARK: - Week building

    private func buildWeeklyActivity(
        workouts: [HKWorkout],
        stepsHistory: [MetricValue],
        stepGoal: Double
    ) -> [WeekActivity] {
        let cal = Calendar(identifier: .gregorian)

        // Determine the range: 28 days back → today's week end.
        let today = Date()
        guard let earliest = cal.date(byAdding: .day, value: -28, to: today) else { return [] }

        // Collect workout days as a Set<Date> (start-of-day).
        let workoutDaySet: Set<Date> = Set(workouts.map {
            cal.startOfDay(for: $0.startDate)
        })

        // Collect step-goal days as a Set<Date>.
        let stepGoalDaySet: Set<Date> = Set(
            stepsHistory
                .filter { $0.value >= stepGoal && stepGoal > 0 }
                .map { cal.startOfDay(for: $0.date) }
        )

        // Build week buckets: find the Monday on or before `earliest`.
        var weeks: [WeekActivity] = []
        var weekStart = mondayOnOrBefore(date: earliest, cal: cal)
        let todayStart = cal.startOfDay(for: today)

        while weekStart <= todayStart {
            guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { break }

            var wDays = 0
            var gDays = 0
            var cursor = weekStart
            while cursor <= weekEnd {
                if workoutDaySet.contains(cursor) { wDays += 1 }
                if stepGoalDaySet.contains(cursor) { gDays += 1 }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
            }

            let isActive = (wDays >= 3) || (gDays >= 4)
            weeks.append(WeekActivity(
                weekStart: weekStart,
                isActive: isActive,
                workoutDays: wDays,
                stepGoalDays: gDays
            ))

            weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86400)
        }

        return weeks
    }

    /// Returns the most-recent Monday that is <= `date`.
    private func mondayOnOrBefore(date: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday (Gregorian: 1=Sun, 2=Mon)
        return cal.date(from: comps) ?? date
    }

    // MARK: - Streak computation

    /// Walk the weeks array newest-first to count currentStreak,
    /// then scan oldest-first to find longestStreak.
    private func computeStreaks(from weeks: [WeekActivity]) -> (current: Int, longest: Int) {
        guard !weeks.isEmpty else { return (0, 0) }

        let sorted = weeks.sorted { $0.weekStart < $1.weekStart }

        // Current streak: walk backward from today's week.
        // If the current (in-progress) week has 0 active days yet we don't
        // penalise it — we exclude it from streak counting and start counting
        // from the previous complete week.
        var currentIdx = sorted.count - 1
        let cal = Calendar(identifier: .gregorian)
        let todayWeekStart = mondayOnOrBefore(date: Date(), cal: cal)

        // If the last entry is the current (incomplete) week, skip it for now.
        var inProgressWeek: WeekActivity? = nil
        if let last = sorted.last, cal.startOfDay(for: last.weekStart) == cal.startOfDay(for: todayWeekStart) {
            inProgressWeek = last
            currentIdx = sorted.count - 2
        }

        // Count backward through complete weeks.
        var current = 0
        var i = currentIdx
        while i >= 0 && sorted[i].isActive {
            current += 1
            i -= 1
        }

        // If the in-progress week already qualifies, include it.
        if let inProg = inProgressWeek, inProg.isActive {
            current += 1
        }

        // Longest: standard sliding-window scan.
        var longest = 0
        var run = 0
        for week in sorted {
            if week.isActive {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        // Also consider current run vs stored longest.
        longest = max(longest, longestStreak)

        return (current, longest)
    }

    // MARK: - Badge awards

    private func checkAndAwardBadges(currentStreak: Int) {
        let now = Date()
        var changed = false
        for milestone in Self.milestoneMilestones where currentStreak >= milestone {
            if !earnedBadges.contains(where: { $0.id == milestone }) {
                earnedBadges.append(StreakBadge(id: milestone, earnedDate: now))
                changed = true
                scheduleStreakNotification(for: milestone)
            }
        }
        if changed {
            persistBadges()
        }
    }

    private func persistBadges() {
        if let data = try? JSONEncoder().encode(earnedBadges) {
            UserDefaults.standard.set(data, forKey: udBadgesKey)
        }
    }

    // MARK: - Notifications

    private func scheduleStreakNotification(for milestone: Int) {
        let name = UserDefaults.standard.string(forKey: "athlete_name") ?? "Champion"
        let body: String
        switch milestone {
        case 1:  body = "You've completed your first active week! The streak begins. Keep going."
        case 4:  body = "One month of consistent activity! You're building a real habit."
        case 8:  body = "Two months in! Your streak is stronger than 90% of users."
        case 13: body = "Quarter-year streak! Three months of showing up — incredible."
        case 26: body = "Half a year! Six-month streak achieved. You're unstoppable."
        case 52: body = "One full year! 52-week streak. You've changed your life."
        default: body = "\(milestone)-week streak! Amazing consistency."
        }

        let identifier = "\(notifIDPrefix)\(milestone)"
        let category   = notifCategory

        Task.detached {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "🔥 \(milestone)-Week Streak, \(name)!"
            content.body  = body
            content.sound = .default
            content.categoryIdentifier = category

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

// MARK: - Badge metadata (UI helpers)

public extension StreakBadge {
    var displayName: String {
        switch id {
        case 1:  return "First Flame"
        case 4:  return "Monthly Fire"
        case 8:  return "Eight-Week Blaze"
        case 13: return "Quarter Year"
        case 26: return "Half Year"
        case 52: return "Full Year"
        default: return "\(id)-Week Streak"
        }
    }

    var icon: String {
        switch id {
        case 1:  return "flame"
        case 4:  return "flame.fill"
        case 8:  return "trophy"
        case 13: return "trophy.fill"
        case 26: return "star.circle.fill"
        case 52: return "crown.fill"
        default: return "medal.fill"
        }
    }

    var badgeColor: Color {
        switch id {
        case 1:  return Color.orange
        case 4:  return Color.red
        case 8:  return Color(red: 1.0, green: 0.75, blue: 0.0)
        case 13: return Color.mint
        case 26: return Color.cyan
        case 52: return Color(red: 0.92, green: 0.8, blue: 0.35)
        default: return Color.gray
        }
    }
}
