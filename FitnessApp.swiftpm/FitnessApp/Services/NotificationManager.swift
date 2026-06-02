@preconcurrency import UserNotifications
import Foundation

/// Manages local sedentary-alert notifications. Scheduling happens from the
/// foreground each time the prediction engine produces a new snapshot. The
/// app cancels pending alerts when the user becomes active again, so the user
/// only gets nudged when they're genuinely sitting still.
@MainActor
public final class NotificationManager {
    public static let shared = NotificationManager()
    private init() {}

    private let sedentaryCategory = "SEDENTARY_ALERT"
    private let alertIdentifier    = "com.tushar.fitnessapp.sedentary"
    private let reminderIntervalSeconds: Double = 3600 // 1 h

    // MARK: - Permission

    public func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Scheduling

    /// Called after every prediction engine refresh. Schedules or cancels the
    /// sedentary alert depending on current severity. Idempotent — replaces any
    /// previously scheduled alert.
    public func updateSedentaryAlert(severity: SedentarySeverity?, quietHours: Int) {
        switch severity {
        case .moderate:
            scheduleSedentaryAlert(message: "You've been sitting for \(quietHours)h. Even a 5-minute walk helps.")
        case .high:
            scheduleSedentaryAlert(message: "Extended inactivity detected (\(quietHours)h). Time to move — your body will thank you.")
        default:
            cancelSedentaryAlert()
        }
    }

    private func scheduleSedentaryAlert(message: String) {
        let center = UNUserNotificationCenter.current()
        let id = alertIdentifier
        let category = sedentaryCategory
        let interval = reminderIntervalSeconds
        let name = UserDefaults.standard.string(forKey: "athlete_name") ?? "athlete"

        Task.detached {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            await center.removePendingNotificationRequests(withIdentifiers: [id])

            let content = UNMutableNotificationContent()
            content.title = "Time to move, \(name)!"
            content.body = message
            content.sound = .default
            content.categoryIdentifier = category

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    public func cancelSedentaryAlert() {
        let id = alertIdentifier
        Task.detached {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [id])
        }
    }
}
