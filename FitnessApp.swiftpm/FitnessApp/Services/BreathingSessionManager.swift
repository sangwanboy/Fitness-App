import Foundation
import SwiftUI
import HealthKit
@preconcurrency import UserNotifications

// MARK: - Breathing Phase

public enum BreathPhase: String, CaseIterable {
    case inhale  = "inhale"
    case hold1   = "hold1"
    case exhale  = "exhale"
    case hold2   = "hold2"

    public var label: String {
        switch self {
        case .inhale: return "Inhale"
        case .hold1:  return "Hold"
        case .exhale: return "Exhale"
        case .hold2:  return "Hold"
        }
    }

    public var icon: String {
        switch self {
        case .inhale: return "arrow.up.circle.fill"
        case .hold1:  return "pause.circle.fill"
        case .exhale: return "arrow.down.circle.fill"
        case .hold2:  return "pause.circle.fill"
        }
    }
}

// MARK: - Breathing Protocol

public struct BreathingProtocol: Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let inhaleSec: Double
    public let hold1Sec: Double
    public let exhaleSec: Double
    public let hold2Sec: Double
    public let colorHex: String
    public let icon: String

    public var totalCycleSec: Double {
        inhaleSec + hold1Sec + exhaleSec + hold2Sec
    }

    public var estimatedMinutes: Int {
        // Typical session is ~4 minutes / 3–5 cycles
        let cycles = 5.0
        return max(1, Int((cycles * totalCycleSec / 60.0).rounded()))
    }

    public var color: Color {
        ThemeHelper.color(from: colorHex)
    }

    /// Ordered phases, skipping any with zero duration.
    public var activePhases: [(phase: BreathPhase, duration: Double)] {
        let all: [(BreathPhase, Double)] = [
            (.inhale, inhaleSec),
            (.hold1,  hold1Sec),
            (.exhale, exhaleSec),
            (.hold2,  hold2Sec)
        ]
        return all.filter { $0.1 > 0 }
    }

    // MARK: - Built-ins

    public static let box = BreathingProtocol(
        id: "box",
        name: "Box Breathing",
        description: "Equal 4-count rhythm. Reduces stress and sharpens focus.",
        inhaleSec: 4, hold1Sec: 4, exhaleSec: 4, hold2Sec: 4,
        colorHex: "#007AFF",
        icon: "square"
    )

    public static let relaxing478 = BreathingProtocol(
        id: "478",
        name: "4-7-8 Relaxation",
        description: "Navy SEAL sleep technique. Activates parasympathetic response.",
        inhaleSec: 4, hold1Sec: 7, exhaleSec: 8, hold2Sec: 0,
        colorHex: "#5856D6",
        icon: "moon.fill"
    )

    public static let coherent = BreathingProtocol(
        id: "coherent",
        name: "Coherent Breathing",
        description: "5-5 resonance. Maximises HRV and cardiac coherence.",
        inhaleSec: 5, hold1Sec: 0, exhaleSec: 5, hold2Sec: 0,
        colorHex: "#34C759",  // teal mapped to system green since teal hex varies
        icon: "waveform"
    )

    public static func custom(inSec: Double, holdSec: Double, outSec: Double) -> BreathingProtocol {
        BreathingProtocol(
            id: "custom",
            name: "Custom",
            description: "Your personalized rhythm.",
            inhaleSec: inSec, hold1Sec: holdSec, exhaleSec: outSec, hold2Sec: 0,
            colorHex: "#FF9F0A",
            icon: "slider.horizontal.3"
        )
    }

    public static func allProtocols(customIn: Double, customHold: Double, customOut: Double) -> [BreathingProtocol] {
        [.box, .relaxing478, .coherent, .custom(inSec: customIn, holdSec: customHold, outSec: customOut)]
    }
}

// MARK: - Completed Breathing Session Record

public struct BreathingSessionRecord: Identifiable, Codable {
    public let id: UUID
    public let protocolId: String
    public let protocolName: String
    public let startDate: Date
    public let endDate: Date
    public let cycleCount: Int
    public let colorHex: String

    public var durationSeconds: Int { Int(endDate.timeIntervalSince(startDate)) }

    public init(id: UUID = UUID(),
                protocolId: String,
                protocolName: String,
                startDate: Date,
                endDate: Date,
                cycleCount: Int,
                colorHex: String) {
        self.id = id
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.startDate = startDate
        self.endDate = endDate
        self.cycleCount = cycleCount
        self.colorHex = colorHex
    }
}

// MARK: - BreathingSessionManager

@MainActor
public final class BreathingSessionManager: ObservableObject {
    public static let shared = BreathingSessionManager()

    // MARK: Published state

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentPhase: BreathPhase = .inhale
    /// 0 → 1 progress through the current phase.
    @Published public private(set) var phaseProgress: Double = 0
    @Published public private(set) var cycleCount: Int = 0
    @Published public private(set) var sessionSeconds: Int = 0
    @Published public private(set) var selectedProtocol: BreathingProtocol = .box
    @Published public private(set) var todaySessions: [BreathingSessionRecord] = []

    // MARK: AppStorage for custom protocol ratios

    @AppStorage("custom_breath_in")   private var customBreathIn   = 4.0
    @AppStorage("custom_breath_hold") private var customBreathHold = 0.0
    @AppStorage("custom_breath_out")  private var customBreathOut  = 6.0

    // MARK: Private state

    private var sessionTask: Task<Void, Never>?
    private var mindfulTask: Task<Void, Never>?
    private var sessionStart: Date?
    private let healthStore = HKHealthStore()
    private let hapticGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()
    private static let tickInterval: Double = 0.05   // 50 ms → smooth 0→1 per phase

    private let notificationCenter = UNUserNotificationCenter.current()
    private static let hrvNudgeIdentifier = "com.fitnessapp.breathing.hrv_nudge"

    private init() {
        loadTodaySessions()
    }

    // MARK: - Derived helpers

    public var customBreathInValue: Double   { customBreathIn }
    public var customBreathHoldValue: Double { customBreathHold }
    public var customBreathOutValue: Double  { customBreathOut }

    public func setCustomRatios(inSec: Double, holdSec: Double, outSec: Double) {
        customBreathIn   = max(1, inSec)
        customBreathHold = max(0, holdSec)
        customBreathOut  = max(1, outSec)
    }

    public var currentProtocols: [BreathingProtocol] {
        BreathingProtocol.allProtocols(
            customIn: customBreathIn,
            customHold: customBreathHold,
            customOut: customBreathOut
        )
    }

    // MARK: - Session control

    public func startSession(protocol p: BreathingProtocol) {
        guard !isRunning else { return }
        selectedProtocol = p
        isRunning = true
        cycleCount = 0
        sessionSeconds = 0
        sessionStart = Date()
        currentPhase = p.activePhases.first?.phase ?? .inhale
        phaseProgress = 0

        sessionTask = Task { [weak self] in
            await self?.runLoop(protocol: p)
        }
    }

    public func stopSession() {
        sessionTask?.cancel()
        sessionTask = nil

        let endDate = Date()
        let startDate = sessionStart ?? endDate.addingTimeInterval(-Double(sessionSeconds))

        if sessionSeconds >= 10 {
            // Only record sessions that lasted at least 10 seconds
            let record = BreathingSessionRecord(
                protocolId: selectedProtocol.id,
                protocolName: selectedProtocol.name,
                startDate: startDate,
                endDate: endDate,
                cycleCount: cycleCount,
                colorHex: selectedProtocol.colorHex
            )
            persistRecord(record)
            mindfulTask?.cancel()
            mindfulTask = Task { await self.writeMindfulSession(start: startDate, end: endDate) }
        }

        isRunning = false
        phaseProgress = 0
        sessionStart = nil
    }

    // MARK: - Session timer loop

    private func runLoop(protocol p: BreathingProtocol) async {
        let phases = p.activePhases
        guard !phases.isEmpty else { return }

        var phaseIndex = 0
        var elapsed = 0.0
        var sessionElapsed = 0.0
        let tick = Self.tickInterval

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            guard !Task.isCancelled else { break }

            let (phase, duration) = phases[phaseIndex]
            elapsed += tick
            sessionElapsed += tick

            let progress = min(elapsed / duration, 1.0)
            let secs = Int(sessionElapsed)

            await MainActor.run {
                self.currentPhase = phase
                self.phaseProgress = progress
                self.sessionSeconds = secs
            }

            if elapsed >= duration {
                // Advance to next phase
                let nextIndex = (phaseIndex + 1) % phases.count
                let isNewCycle = nextIndex == 0

                fireHaptic()

                await MainActor.run {
                    if isNewCycle { self.cycleCount += 1 }
                }

                phaseIndex = nextIndex
                elapsed = 0
            }
        }
    }

    // MARK: - Haptics

    private func fireHaptic() {
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
    }

    // MARK: - HealthKit: write mindful session

    private func writeMindfulSession(start: Date, end: Date) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)
        else { return }

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end,
            metadata: [
                HKMetadataKeyWasUserEntered: true,
                "BreathingProtocol": selectedProtocol.name
            ]
        )

        do {
            try await healthStore.save(sample)
        } catch {
            // Best-effort — silently ignore HK write failures (e.g. authorization denied)
        }
    }

    // MARK: - Session persistence

    private static let storageKey = "breathing_sessions_today"

    private func persistRecord(_ record: BreathingSessionRecord) {
        var records = loadRawTodayRecords()
        records.append(record)
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.storageKeyForToday())
        }
        todaySessions = records
    }

    private func loadTodaySessions() {
        todaySessions = loadRawTodayRecords()
    }

    private func loadRawTodayRecords() -> [BreathingSessionRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKeyForToday()),
              let records = try? JSONDecoder().decode([BreathingSessionRecord].self, from: data)
        else { return [] }
        return records
    }

    private static func storageKeyForToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "breathing_sessions_\(df.string(from: Date()))"
    }

    public var didCompleteSessionToday: Bool {
        !todaySessions.isEmpty
    }

    // MARK: - HRV Nudge notification

    /// Call this after HealthKit data refreshes (e.g. from HealthKitManager.fetchTodayData()).
    /// Schedules a local notification if HRV has dropped >15% below the 30-day rolling average,
    /// no breathing session was done today, and the time is between 08:00–20:00.
    public func scheduleHRVNudgeIfNeeded(hrv history: [MetricValue]) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        guard hour >= 8 && hour < 20 else { return }
        guard !didCompleteSessionToday else { return }

        // Need at least a week of history for the rolling average
        let sortedHistory = history.sorted { $0.date < $1.date }
        guard sortedHistory.count >= 7 else { return }

        // Last 30 days
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let last30 = sortedHistory.filter { $0.date >= cutoff && $0.value > 0 }
        guard last30.count >= 5 else { return }

        let average = last30.map(\.value).reduce(0, +) / Double(last30.count)
        guard average > 0 else { return }

        // Today's most recent HRV value
        guard let todayValue = sortedHistory.last, todayValue.value > 0 else { return }

        let dropPercent = (average - todayValue.value) / average
        guard dropPercent > 0.15 else { return }

        scheduleHRVNudge()
    }

    private func scheduleHRVNudge() {
        let center = UNUserNotificationCenter.current()
        let id = Self.hrvNudgeIdentifier

        Task.detached {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            // Don't re-schedule if there's already one pending
            let pending = await center.pendingNotificationRequests()
            guard !pending.contains(where: { $0.identifier == id }) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your HRV dipped — take 60 seconds"
            content.body = "A short breathing exercise can help restore heart rate variability. Tap to open a guided session."
            content.sound = .default
            content.userInfo = ["deeplink": "fitnessapp://breathing"]

            // Fire in 2 minutes so it doesn't interrupt immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    public func cancelHRVNudge() {
        Task.detached {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.hrvNudgeIdentifier])
        }
    }
}
