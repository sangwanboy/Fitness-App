import Foundation
import SwiftUI
import UserNotifications

// MARK: - Models

public struct Challenge: Identifiable, Codable {
    public let id: String
    public let title: String
    public let description: String
    public let metric: HealthMetricType
    public let targetValue: Double
    public let icon: String
    public let colorHex: String
    public let expiresAt: Date

    public init(
        id: String,
        title: String,
        description: String,
        metric: HealthMetricType,
        targetValue: Double,
        icon: String,
        colorHex: String,
        expiresAt: Date
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.metric = metric
        self.targetValue = targetValue
        self.icon = icon
        self.colorHex = colorHex
        self.expiresAt = expiresAt
    }
}

public struct CompletedChallenge: Identifiable, Codable {
    public let id: UUID
    public let challengeId: String
    public let title: String
    public let metric: HealthMetricType
    public let targetValue: Double
    public let icon: String
    public let colorHex: String
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        challengeId: String,
        title: String,
        metric: HealthMetricType,
        targetValue: Double,
        icon: String,
        colorHex: String,
        completedAt: Date
    ) {
        self.id = id
        self.challengeId = challengeId
        self.title = title
        self.metric = metric
        self.targetValue = targetValue
        self.icon = icon
        self.colorHex = colorHex
        self.completedAt = completedAt
    }
}

// MARK: - Challenge Template

private struct ChallengeTemplate {
    let title: String
    let description: String
    let metric: HealthMetricType
    let baseTarget: Double
    let icon: String
    let colorHex: String
    /// When true, targetValue is computed dynamically (e.g. HRV * 1.1)
    let dynamic: Bool

    init(
        title: String,
        description: String,
        metric: HealthMetricType,
        baseTarget: Double,
        icon: String,
        colorHex: String,
        dynamic: Bool = false
    ) {
        self.title = title
        self.description = description
        self.metric = metric
        self.baseTarget = baseTarget
        self.icon = icon
        self.colorHex = colorHex
        self.dynamic = dynamic
    }
}

// MARK: - Engine

@MainActor
public final class ChallengeEngine: ObservableObject {

    public static let shared = ChallengeEngine()

    @Published public var activeChallenge: Challenge?
    @Published public var progress: Double = 0.0          // 0–1 clamped
    @Published public var completedChallenges: [CompletedChallenge] = []

    private var midnightTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    /// UserDefaults key for today's selected challenge id (to survive restarts)
    private static let activeChallengeKey = "active_challenge_v1"
    private static let completedKey = "completed_challenges_v1"
    private static let lastCompletionDateKey = "challenge_last_completion_date"

    // MARK: - 30 Template pool

    private static let templates: [ChallengeTemplate] = [
        // Steps
        ChallengeTemplate(
            title: "Step Sprint",
            description: "Walk, run, or move your way to 12,000 steps today.",
            metric: .steps, baseTarget: 12000,
            icon: "figure.walk", colorHex: "#20B2AA"
        ),
        ChallengeTemplate(
            title: "Step Starter",
            description: "Hit 8,000 steps — a solid active day for most people.",
            metric: .steps, baseTarget: 8000,
            icon: "figure.walk", colorHex: "#3CB371"
        ),
        ChallengeTemplate(
            title: "10K Steps",
            description: "The classic 10,000 step daily target. Make it happen.",
            metric: .steps, baseTarget: 10000,
            icon: "shoeprints.fill", colorHex: "#00CED1"
        ),
        ChallengeTemplate(
            title: "Marathon Mover",
            description: "Push it to 15,000 steps — a power walking day.",
            metric: .steps, baseTarget: 15000,
            icon: "figure.run", colorHex: "#FF8C00"
        ),
        // Calories
        ChallengeTemplate(
            title: "Calorie Crusher",
            description: "Burn 700 active calories through movement today.",
            metric: .activeEnergy, baseTarget: 700,
            icon: "flame.fill", colorHex: "#FF4500"
        ),
        ChallengeTemplate(
            title: "Energy Boost",
            description: "Hit 500 active calories — a strong burn for the day.",
            metric: .activeEnergy, baseTarget: 500,
            icon: "flame.fill", colorHex: "#FF6347"
        ),
        ChallengeTemplate(
            title: "Full Burn",
            description: "Torch 900 calories with a mix of cardio and activity.",
            metric: .activeEnergy, baseTarget: 900,
            icon: "bolt.fill", colorHex: "#FF1493"
        ),
        ChallengeTemplate(
            title: "Active Hour",
            description: "Earn 400 active calories to close your move ring strong.",
            metric: .activeEnergy, baseTarget: 400,
            icon: "figure.highintensity.intervaltraining", colorHex: "#DC143C"
        ),
        // Sleep
        ChallengeTemplate(
            title: "Deep Sleep Night",
            description: "Get 7.5+ hours of sleep tonight for full recovery.",
            metric: .sleep, baseTarget: 7.5,
            icon: "bed.double.fill", colorHex: "#7B68EE"
        ),
        ChallengeTemplate(
            title: "Power Sleep",
            description: "Aim for 8 hours of quality sleep to reset your body.",
            metric: .sleep, baseTarget: 8.0,
            icon: "moon.stars.fill", colorHex: "#9370DB"
        ),
        ChallengeTemplate(
            title: "Rest Up",
            description: "Hit 7 hours of sleep — the minimum for cognitive performance.",
            metric: .sleep, baseTarget: 7.0,
            icon: "zzz", colorHex: "#8A2BE2"
        ),
        ChallengeTemplate(
            title: "Sleep Champion",
            description: "Achieve 8.5+ hours for elite-level overnight recovery.",
            metric: .sleep, baseTarget: 8.5,
            icon: "bed.double.fill", colorHex: "#483D8B"
        ),
        // Hydration
        ChallengeTemplate(
            title: "Hydration Hero",
            description: "Drink 3 liters of water throughout the day.",
            metric: .hydration, baseTarget: 3.0,
            icon: "drop.fill", colorHex: "#1E90FF"
        ),
        ChallengeTemplate(
            title: "Water Warrior",
            description: "Log 2.5 liters of water — solid hydration for active days.",
            metric: .hydration, baseTarget: 2.5,
            icon: "drop.fill", colorHex: "#4169E1"
        ),
        ChallengeTemplate(
            title: "Hydration Master",
            description: "Drink 3.5 liters — essential for hard training days.",
            metric: .hydration, baseTarget: 3.5,
            icon: "drop.fill", colorHex: "#00BFFF"
        ),
        ChallengeTemplate(
            title: "Daily H2O",
            description: "Hit 2 liters of water as a baseline hydration goal.",
            metric: .hydration, baseTarget: 2.0,
            icon: "drop.circle.fill", colorHex: "#87CEEB"
        ),
        // HRV
        ChallengeTemplate(
            title: "HRV Recovery",
            description: "Recover well — aim for an HRV 10% above yesterday's reading.",
            metric: .hrv, baseTarget: 0,  // dynamic: currentHRV * 1.1
            icon: "waveform.path.ecg", colorHex: "#00FA9A",
            dynamic: true
        ),
        ChallengeTemplate(
            title: "Heart Balance",
            description: "Achieve an HRV of 60ms+ for strong autonomic recovery.",
            metric: .hrv, baseTarget: 60,
            icon: "waveform.path.ecg", colorHex: "#7FFFD4"
        ),
        ChallengeTemplate(
            title: "Recovery Day",
            description: "Target 70ms HRV — a sign of deep systemic recovery.",
            metric: .hrv, baseTarget: 70,
            icon: "waveform.path.ecg.rectangle", colorHex: "#66CDAA"
        ),
        ChallengeTemplate(
            title: "Elite HRV",
            description: "Push your HRV to 85ms — the mark of peak readiness.",
            metric: .hrv, baseTarget: 85,
            icon: "waveform.path.ecg", colorHex: "#3CB371"
        ),
        // Distance
        ChallengeTemplate(
            title: "Mile Maker",
            description: "Cover 3 miles on foot today — walk or run.",
            metric: .distance, baseTarget: 3.0,
            icon: "figure.walk.motion", colorHex: "#228B22"
        ),
        ChallengeTemplate(
            title: "5K Day",
            description: "Log 3.1 miles to match a classic 5K distance.",
            metric: .distance, baseTarget: 3.1,
            icon: "figure.run", colorHex: "#32CD32"
        ),
        ChallengeTemplate(
            title: "Long Haul",
            description: "Cover 5+ miles to really rack up the distance.",
            metric: .distance, baseTarget: 5.0,
            icon: "arrow.triangle.turn.up.right.diamond.fill", colorHex: "#6B8E23"
        ),
        ChallengeTemplate(
            title: "City Stroller",
            description: "Walk 2 miles exploring your neighborhood.",
            metric: .distance, baseTarget: 2.0,
            icon: "figure.walk", colorHex: "#556B2F"
        ),
        // Exercise minutes
        ChallengeTemplate(
            title: "30-Minute Move",
            description: "Get 30 minutes of credited exercise today.",
            metric: .exerciseMinutes, baseTarget: 30,
            icon: "figure.mixed.cardio", colorHex: "#9ACD32"
        ),
        ChallengeTemplate(
            title: "Active Hour",
            description: "Log 60 minutes of exercise for a gold-standard activity day.",
            metric: .exerciseMinutes, baseTarget: 60,
            icon: "figure.strengthtraining.functional", colorHex: "#ADFF2F"
        ),
        ChallengeTemplate(
            title: "Quick Mover",
            description: "Hit 20 minutes of exercise — even a brisk walk counts.",
            metric: .exerciseMinutes, baseTarget: 20,
            icon: "figure.walk.treadmill", colorHex: "#7CFC00"
        ),
        ChallengeTemplate(
            title: "Triple Timer",
            description: "Hit 45 minutes of exercise for a strong mid-week session.",
            metric: .exerciseMinutes, baseTarget: 45,
            icon: "timer", colorHex: "#00FF7F"
        ),
        // Mindfulness
        ChallengeTemplate(
            title: "Mindful Moment",
            description: "Log 10 minutes of mindfulness to center your day.",
            metric: .mindfulMinutes, baseTarget: 10,
            icon: "brain.head.profile", colorHex: "#DA70D6"
        ),
        ChallengeTemplate(
            title: "Zen Session",
            description: "Practice 20 minutes of mindfulness for deep calm.",
            metric: .mindfulMinutes, baseTarget: 20,
            icon: "figure.mind.and.body", colorHex: "#EE82EE"
        ),
    ]

    // MARK: - Init

    private init() {
        loadPersisted()
        selectOrRestoreChallenge()
        startProgressLoop()
        startMidnightLoop()
    }

    // MARK: - Public API

    /// Force a refresh of progress (e.g. after HealthKit data updates).
    public func refreshProgress() {
        guard let challenge = activeChallenge else {
            progress = 0
            return
        }
        let hk = HealthKitManager.shared
        guard let summary = hk.metricSummaries[challenge.metric] else {
            progress = 0
            return
        }
        let raw = summary.currentValue / challenge.targetValue
        let clamped = min(max(raw, 0), 1.0)
        let wasBelow = progress < 1.0
        progress = clamped
        if wasBelow && clamped >= 1.0 {
            handleCompletion(challenge)
        }
    }

    // MARK: - Challenge Selection

    private func selectOrRestoreChallenge() {
        let today = Calendar.current.startOfDay(for: Date())
        let todayKey = iso(today)

        // If we already picked a challenge for today, reload it
        if let data = UserDefaults.standard.data(forKey: Self.activeChallengeKey),
           let saved = try? JSONDecoder().decode(Challenge.self, from: data),
           Calendar.current.isDateInToday(saved.expiresAt.addingTimeInterval(-1)) {
            activeChallenge = saved
            refreshProgress()
            return
        }

        let challenge = selectTodayChallenge(forDayKey: todayKey)
        activeChallenge = challenge
        if let data = try? JSONEncoder().encode(challenge) {
            UserDefaults.standard.set(data, forKey: Self.activeChallengeKey)
        }
        refreshProgress()
    }

    private func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Deterministic selection seeded from today's date + weakest metrics.
    /// Struggling metrics (low percentComplete) get weighted higher so users
    /// are challenged where they need improvement most.
    func selectTodayChallenge(forDayKey dayKey: String) -> Challenge {
        let hk = HealthKitManager.shared
        let summaries = hk.metricSummaries

        // Build weights: inverse of percent-complete (lower = more likely)
        // Sum across eligible templates.
        var weights: [Double] = []
        for template in Self.templates {
            let pct = summaries[template.metric]?.percentComplete ?? 0.5
            // Weight = 1 - pct, clamped to [0.05, 1.0] so nothing is excluded
            let w = min(max(1.0 - pct, 0.05), 1.0)
            weights.append(w)
        }

        // Seeded random from dayKey string hash
        var seed: UInt64 = 0
        for char in dayKey.unicodeScalars {
            seed = seed &* 31 &+ UInt64(char.value)
        }
        // LCG random
        func nextRand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }

        let totalWeight = weights.reduce(0, +)
        var pick = nextRand() * totalWeight
        var selectedIndex = 0
        for (i, w) in weights.enumerated() {
            pick -= w
            if pick <= 0 {
                selectedIndex = i
                break
            }
        }

        let template = Self.templates[selectedIndex]

        // Resolve dynamic target (HRV * 1.1)
        let target: Double
        if template.dynamic {
            let currentHRV = summaries[.hrv]?.currentValue ?? 50.0
            let baseHRV = max(currentHRV, 30.0) // floor so target is never trivial
            target = (baseHRV * 1.1).rounded()
        } else {
            target = template.baseTarget
        }

        let midnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(86400)

        return Challenge(
            id: "\(dayKey)-\(selectedIndex)",
            title: template.title,
            description: template.description,
            metric: template.metric,
            targetValue: target,
            icon: template.icon,
            colorHex: template.colorHex,
            expiresAt: midnight
        )
    }

    // MARK: - Completion

    private func handleCompletion(_ challenge: Challenge) {
        // Guard against double-recording for the same challenge id
        if completedChallenges.contains(where: { $0.challengeId == challenge.id }) { return }

        let entry = CompletedChallenge(
            challengeId: challenge.id,
            title: challenge.title,
            metric: challenge.metric,
            targetValue: challenge.targetValue,
            icon: challenge.icon,
            colorHex: challenge.colorHex,
            completedAt: Date()
        )
        completedChallenges.insert(entry, at: 0)
        persist()
        scheduleCompletionNotification(challenge)
    }

    // MARK: - Persistence

    private func loadPersisted() {
        if let data = UserDefaults.standard.data(forKey: Self.completedKey),
           let list = try? JSONDecoder().decode([CompletedChallenge].self, from: data) {
            completedChallenges = list
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(completedChallenges) {
            UserDefaults.standard.set(data, forKey: Self.completedKey)
        }
    }

    // MARK: - Notification

    private func scheduleCompletionNotification(_ challenge: Challenge) {
        let center = UNUserNotificationCenter.current()
        Task.detached {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Challenge Complete!"
            content.body = "You finished '\(challenge.title)' — great work!"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "challenge-complete-\(challenge.id)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - Loops

    private func startProgressLoop() {
        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled {
                refreshProgress()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func startMidnightLoop() {
        midnightTask?.cancel()
        midnightTask = Task {
            while !Task.isCancelled {
                let now = Date()
                let nextMidnight = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) ?? now.addingTimeInterval(86400)
                let gap = max(nextMidnight.timeIntervalSince(now) + 5, 1)
                let ns = UInt64(gap * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                if !Task.isCancelled {
                    selectOrRestoreChallenge()
                }
            }
        }
    }
}
