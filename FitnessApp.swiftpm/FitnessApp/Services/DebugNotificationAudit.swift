#if DEBUG
import UIKit
import UserNotifications

/// On-device functional audit of the notification pipeline. Periodically
/// snapshots UNUserNotificationCenter state — authorization, every pending
/// request (kind, fire date, title/body) — to Documents/notification_audit.json
/// so the state can be pulled off a development device with
/// `devicectl device copy` and inspected without a debugger. DEBUG-only,
/// read-only (never mutates scheduling), and independent of
/// NotificationManager so it observes rather than participates.
enum DebugNotificationAudit {
    static func start() {
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { await snapshot() }
        }
    }

    private static func snapshot() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()

        let df = ISO8601DateFormatter()
        var entries: [[String: Any]] = []
        for req in pending {
            var fire = "unscheduled"
            if let cal = req.trigger as? UNCalendarNotificationTrigger,
               let next = cal.nextTriggerDate() {
                fire = df.string(from: next)
            } else if let interval = req.trigger as? UNTimeIntervalNotificationTrigger,
                      let next = interval.nextTriggerDate() {
                fire = df.string(from: next)
            }
            entries.append([
                "id": req.identifier,
                "fires": fire,
                "title": req.content.title,
                "body": req.content.body,
                "hasChatPrompt": req.content.userInfo["chatPrompt"] != nil,
            ])
        }

        let dump: [String: Any] = [
            "capturedAt": df.string(from: Date()),
            "authorization": String(describing: settings.authorizationStatus.rawValue),
            "alertsEnabled": settings.alertSetting == .enabled,
            "pendingCount": pending.count,
            "pending": entries,
        ]

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: docs.appendingPathComponent("notification_audit.json"), options: .atomic)
    }
}
#endif
