import SwiftUI
import UserNotifications

/// Self-contained Settings section for Astra's proactive notifications:
/// permission status, a per-kind enable toggle with an honest one-line
/// description, the morning-brief time, and the quiet-hours window. Reuses
/// `ProfileListGroup` / `ProfileListRow` / `ProfileListDivider` from
/// SettingsView so it reads as native to the screen rather than a bolt-on —
/// mirrors `AstraProfileSection`'s structure.
///
/// All state is read/written straight through `NotificationManager` and
/// matching `@AppStorage` keys (`notif_kind_<rawValue>`, `notif_morning_time`,
/// `notif_quiet_start`, `notif_quiet_end`) — no local mirror state to drift
/// out of sync.
public struct NotificationSettingsSection: View {
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private struct KindMeta {
        let kind: AstraNotificationKind
        let icon: String
        let color: Color
        let title: String
        let description: String
    }

    private static let kindMeta: [KindMeta] = [
        KindMeta(kind: .morningBrief, icon: "sun.max.fill", color: .orange,
                 title: "Morning brief",
                 description: "A daily summary of your recovery, sleep, and training load."),
        KindMeta(kind: .illnessWarning, icon: "cross.case.fill", color: .red,
                 title: "Illness early warning",
                 description: "An early heads-up when resting HR, HRV, and sleep drift together."),
        KindMeta(kind: .streakRisk, icon: "flame.fill", color: .orange,
                 title: "Streak risk",
                 description: "An evening reminder if today hasn't kept your streak alive yet."),
        KindMeta(kind: .sleepWindDown, icon: "moon.zzz.fill", color: .indigo,
                 title: "Sleep wind-down",
                 description: "A nudge to wind down when tonight's sleep forecast looks short."),
        KindMeta(kind: .recoveryGuidance, icon: "heart.text.square.fill", color: .purple,
                 title: "Recovery guidance",
                 description: "Evening guidance after a high-strain training day."),
        KindMeta(kind: .weeklyReview, icon: "calendar.badge.clock", color: .blue,
                 title: "Weekly review",
                 description: "A weekly recap of your training and recovery trends."),
        KindMeta(kind: .sedentaryAlert, icon: "figure.walk", color: .mint,
                 title: "Move reminder",
                 description: "A nudge to get moving after a long stretch of inactivity.")
    ]

    public init() {}

    public var body: some View {
        ProfileListGroup(header: "Notifications") {
            NotificationPermissionRow(accentColor: accentColor)
            ProfileListDivider()

            ForEach(Array(Self.kindMeta.enumerated()), id: \.element.kind) { index, meta in
                NotificationKindToggleRow(kind: meta.kind, icon: meta.icon, iconColor: meta.color,
                                           title: meta.title, description: meta.description)
                if index < Self.kindMeta.count - 1 {
                    ProfileListDivider()
                }
            }

            ProfileListDivider()
            NotificationTimeRow(title: "Morning brief time", icon: "clock.fill", iconColor: .orange,
                                 defaultsKey: "notif_morning_time", defaultMinutes: 8 * 60)
            ProfileListDivider()
            NotificationTimeRow(title: "Quiet hours start", icon: "moon.fill", iconColor: .indigo,
                                 defaultsKey: "notif_quiet_start", defaultMinutes: 22 * 60)
            ProfileListDivider()
            NotificationTimeRow(title: "Quiet hours end", icon: "sunrise.fill", iconColor: .yellow,
                                 defaultsKey: "notif_quiet_end", defaultMinutes: 7 * 60)
        }
    }
}

// MARK: - Permission status row

private struct NotificationPermissionRow: View {
    let accentColor: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    @Environment(\.scenePhase) private var scenePhase

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill((isAuthorized ? Color.green : Color.orange).opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isAuthorized ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isDark ? .white : .black)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            Spacer()
            actionControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .task { status = await NotificationManager.shared.currentAuthorizationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            // The user may have flipped the OS-level permission from iOS
            // Settings while the app was backgrounded — re-check on every
            // return to foreground instead of only once when the row first appeared.
            guard newPhase == .active else { return }
            Task { status = await NotificationManager.shared.currentAuthorizationStatus() }
        }
    }

    private var isAuthorized: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "On — Astra can send alerts"
        case .denied: return "Off — enable in iOS Settings"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        switch status {
        case .denied:
            Button("Open Settings") { ExternalLink.openAppSettings() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
        case .notDetermined:
            if isRequesting {
                ProgressView().controlSize(.small)
            } else {
                Button("Enable") {
                    Task {
                        isRequesting = true
                        await NotificationManager.shared.requestPermissionIfNeeded()
                        status = await NotificationManager.shared.currentAuthorizationStatus()
                        isRequesting = false
                        // A granted permission with nothing scheduled yet is a
                        // dead end — arm the morning brief + event nudges right
                        // away instead of waiting for the next foreground/HK refresh.
                        if isAuthorized {
                            NotificationManager.shared.rescheduleMorningBrief()
                            NotificationManager.shared.evaluateProactiveNudges()
                        }
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
            }
        default:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Per-kind toggle row

private struct NotificationKindToggleRow: View {
    let kind: AstraNotificationKind
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    @AppStorage private var isEnabled: Bool
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    init(kind: AstraNotificationKind, icon: String, iconColor: Color, title: String, description: String) {
        self.kind = kind
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        // Same UserDefaults key NotificationManager.isKindEnabled/setKindEnabled
        // read and write ("notif_kind_<rawValue>", default ON) — this row and
        // the manager can never disagree about a kind's enabled state.
        _isEnabled = AppStorage(wrappedValue: true, "notif_kind_\(kind.rawValue)")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isDark ? .white : .black)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(iconColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: isEnabled) { _, newValue in
            // AppStorage already persisted the flag under the same key the
            // manager reads — routing through setKindEnabled too so a
            // disable also cancels any pending request for this kind.
            NotificationManager.shared.setKindEnabled(kind, newValue)
            NotificationManager.shared.evaluateProactiveNudges()
            NotificationManager.shared.rescheduleMorningBrief()
        }
    }
}

// MARK: - Time-of-day row (morning brief time / quiet hours)

private struct NotificationTimeRow: View {
    let title: String
    let icon: String
    let iconColor: Color

    @AppStorage private var minutes: Int
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    init(title: String, icon: String, iconColor: Color, defaultsKey: String, defaultMinutes: Int) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        _minutes = AppStorage(wrappedValue: defaultMinutes, defaultsKey)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isDark ? .white : .black)
            Spacer()
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: minutes) { _, _ in
            NotificationManager.shared.evaluateProactiveNudges()
            NotificationManager.shared.rescheduleMorningBrief()
        }
    }
}
