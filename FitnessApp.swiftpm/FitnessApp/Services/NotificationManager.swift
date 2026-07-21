@preconcurrency import UserNotifications
import Foundation
import UIKit

// MARK: - Notification Kinds

/// Every proactive notification Astra can send. Each kind gets its own
/// UserDefaults-backed enable toggle (key `"notif_kind_<rawValue>"`, default
/// ON) and at most one pending request at a time — the request identifier IS
/// the kind's raw value, so scheduling a kind again always replaces the
/// previous pending one.
public enum AstraNotificationKind: String, CaseIterable {
    case morningBrief
    case illnessWarning
    case streakRisk
    case sleepWindDown
    case recoveryGuidance
    case weeklyReview
    case sedentaryAlert
    case mealReminder
}

/// Owns every local Astra notification: the daily morning brief, the four
/// HealthKit-driven event nudges (illness / streak / sleep / recovery), the
/// legacy sedentary alert, and scheduling support for the weekly review
/// (built elsewhere, scheduled through `schedule(.weeklyReview, ...)` here).
///
/// Also the `UNUserNotificationCenterDelegate` — routes a tapped
/// notification's `chatPrompt` into `ChatPrefillBus` so Coach opens
/// pre-loaded with the right question, and controls foreground presentation
/// (silent banner for nudges, banner + sound for morning brief / weekly
/// review / the sedentary alert).
@MainActor
public final class NotificationManager: NSObject {
    public static let shared = NotificationManager()

    /// Legacy sedentary-alert cadence — unchanged from the original
    /// implementation (fires ~1h after the alert condition is detected).
    private let reminderIntervalSeconds: Double = 3600 // 1 h

    /// Kinds whose delivery plays a sound. Everything else is a silent
    /// banner so HealthKit-driven nudges don't feel alarming. The sedentary
    /// alert always played sound pre-migration, so it stays here for zero
    /// behavior change; the morning brief and weekly review are scheduled
    /// digests where a sound is expected.
    private static let soundedKinds: Set<AstraNotificationKind> = [.morningBrief, .weeklyReview, .sedentaryAlert]

    private override init() {
        super.init()
        // One-time migration: the pre-rewrite app scheduled its sedentary
        // alert under this hardcoded identifier (not
        // `AstraNotificationKind.sedentaryAlert.rawValue`). Cancel whatever's
        // still pending under it once so a stale pre-migration alert can't
        // fire post-update.
        if !UserDefaults.standard.bool(forKey: "notif_legacy_sedentary_migrated") {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["com.tushar.fitnessapp.sedentary"])
            UserDefaults.standard.set(true, forKey: "notif_legacy_sedentary_migrated")
        }

        // Morning brief content is time-sensitive (recovery/sleep/streak as of
        // *now*) and the spec calls for "reschedule on every app foreground."
        // Observing UIApplication directly here keeps that behavior entirely
        // inside this file with zero changes to FitnessApp.swift's scenePhase
        // handling or ContentView.
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                                name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        rescheduleMorningBrief()

        // "First foreground after 5am" trigger for MorningBriefEngine's
        // Astra-written brief (Work Package B2). No meaningful "today" data
        // exists before 5am, so gate here rather than inside the engine —
        // `generateIfNeeded()` itself has no time-of-day opinion and is also
        // called unconditionally from the BGAppRefresh handler
        // (FitnessApp.swift). Once the async attempt lands (success OR an
        // honest .engine fallback), reschedule again so the notification body
        // picks up the freshest content instead of waiting for the next
        // foreground/BG cycle.
        guard Calendar.current.component(.hour, from: Date()) >= 5 else { return }
        Task { @MainActor in
            await MorningBriefEngine.shared.generateIfNeeded()
            rescheduleMorningBrief()
        }
    }

    // MARK: - Permission

    public func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Current OS authorization state — read by the Settings permission row.
    public func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Per-kind enable toggle (UserDefaults-backed, default ON)

    public func isKindEnabled(_ kind: AstraNotificationKind) -> Bool {
        let key = Self.kindDefaultsKey(kind)
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    public func setKindEnabled(_ kind: AstraNotificationKind, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.kindDefaultsKey(kind))
        if !enabled { cancelPending(kind) }
    }

    private static func kindDefaultsKey(_ kind: AstraNotificationKind) -> String { "notif_kind_\(kind.rawValue)" }

    // MARK: - Quiet hours (default 22:00–07:00, stored as minutes-from-midnight)

    private var quietStartMinutes: Int {
        (UserDefaults.standard.object(forKey: "notif_quiet_start") as? Int) ?? 22 * 60
    }
    private var quietEndMinutes: Int {
        (UserDefaults.standard.object(forKey: "notif_quiet_end") as? Int) ?? 7 * 60
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func isInsideQuietHours(_ date: Date) -> Bool {
        let start = quietStartMinutes, end = quietEndMinutes
        guard start != end else { return false } // degenerate window — treat as "no quiet hours"
        let m = minutesFromMidnight(date)
        return start < end ? (m >= start && m < end) : (m >= start || m < end)
    }

    /// The next moment quiet hours end, relative to `date`. Handles the
    /// overnight wrap (default 22:00–07:00): a date in the late-evening
    /// portion (>= start) resolves to tomorrow's end time; a date in the
    /// early-morning portion (< end) resolves to today's.
    private func quietHoursEnd(after date: Date) -> Date {
        let cal = Calendar.current
        let start = quietStartMinutes, end = quietEndMinutes
        var day = cal.startOfDay(for: date)
        if start > end, minutesFromMidnight(date) >= start {
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return cal.date(byAdding: .minute, value: end, to: day) ?? date
    }

    // MARK: - Generic scheduling (public contract)

    /// Schedules `kind` for `date`, respecting the per-kind toggle and quiet
    /// hours. Replaces any pending request of the same kind (identifier =
    /// `kind.rawValue`), so at most one request per kind is ever pending.
    ///
    /// Quiet-hours handling differs by kind: `morningBrief` / `weeklyReview`
    /// are recurring digests, so a landing time inside quiet hours SHIFTS to
    /// quiet-hours-end instead of disappearing. The four transient event
    /// nudges (illness / streak / sleep / recovery) are SKIPPED outright — a
    /// nudge that would land at 2 AM isn't worth waking up for. The legacy
    /// `sedentaryAlert` never observed quiet hours before this migration and
    /// keeps that behavior unchanged.
    /// Returns whether the request cleared the SYNCHRONOUS gates (per-kind
    /// toggle, quiet hours, not-already-past) and was handed off for async
    /// scheduling — NOT whether it was actually added, since authorization is
    /// only known async. Callers that dedupe a same-day side effect against
    /// "did this actually get scheduled" (e.g. the illness-warning fired-today
    /// stamp) should gate on this return value instead of assuming success.
    @discardableResult
    public func schedule(_ kind: AstraNotificationKind, title: String, body: String, at date: Date, chatPrompt: String?) -> Bool {
        guard isKindEnabled(kind) else {
            cancelPending(kind)
            return false
        }

        var fireDate = date
        if isInsideQuietHours(date) {
            switch kind {
            case .morningBrief, .weeklyReview:
                fireDate = quietHoursEnd(after: date)
            case .sedentaryAlert:
                break // zero behavior change — pre-migration this never checked quiet hours
            case .illnessWarning, .streakRisk, .sleepWindDown, .recoveryGuidance, .mealReminder:
                cancelPending(kind)
                return false
            }
        }

        // A shifted/adjusted date that's already in the past (e.g. re-evaluated
        // after the target time already elapsed today) means there's nothing
        // left to schedule for — drop any stale pending request instead of
        // registering a trigger that will never fire.
        guard fireDate.timeIntervalSinceNow > 0 else {
            cancelPending(kind)
            return false
        }

        let id = kind.rawValue
        let playsSound = Self.soundedKinds.contains(kind)
        var userInfo: [String: String] = ["kind": kind.rawValue]
        if let chatPrompt { userInfo["chatPrompt"] = chatPrompt }
        let center = UNUserNotificationCenter.current()

        Task.detached {
            let settings = await center.notificationSettings()
            // Provisional and ephemeral (App Clip) authorization can both
            // still deliver notifications — only `.denied`/`.notDetermined`
            // actually block delivery. Matches the Settings permission row's
            // own `isAuthorized` check (NotificationSettingsSection.swift).
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

            await center.removePendingNotificationRequests(withIdentifiers: [id])

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = playsSound ? .default : nil
            content.categoryIdentifier = id
            content.userInfo = userInfo

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
        return true
    }

    public func cancelPending(_ kind: AstraNotificationKind) {
        let id = kind.rawValue
        Task.detached {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    // MARK: - Legacy sedentary alert (now routed through `schedule`)

    /// Called after every prediction engine refresh. Schedules or cancels the
    /// sedentary alert depending on current severity. Idempotent — replaces
    /// any previously scheduled alert. Message text, the 1-hour delay, and
    /// always-on sound are all unchanged from the original implementation;
    /// only the plumbing underneath (now `schedule(.sedentaryAlert, ...)`) is
    /// new, which also picks up the "Notifications → Move reminder" toggle.
    public func updateSedentaryAlert(severity: SedentarySeverity?, quietHours: Int) {
        switch severity {
        case .moderate:
            fireSedentaryAlert(message: "You've been sitting for \(quietHours)h. Even a 5-minute walk helps.")
        case .high:
            fireSedentaryAlert(message: "Extended inactivity detected (\(quietHours)h). Time to move — your body will thank you.")
        default:
            cancelPending(.sedentaryAlert)
        }
    }

    private func fireSedentaryAlert(message: String) {
        let name = UserDefaults.standard.string(forKey: "athlete_name") ?? "athlete"
        schedule(.sedentaryAlert,
                 title: "Time to move, \(name)!",
                 body: message,
                 at: Date().addingTimeInterval(reminderIntervalSeconds),
                 chatPrompt: nil)
    }

    // MARK: - Morning brief

    /// Rebuilds and reschedules the morning brief for the next occurrence of
    /// `notif_morning_time` (minutes-from-midnight, default 480 = 8:00 AM).
    /// Content is composed from whatever real engine data is available right
    /// now; if nothing meaningful has landed yet, nothing is scheduled — no
    /// filler notification. Called on every app foreground (see `init`) and
    /// from the BGAppRefresh handler in FitnessApp.swift.
    public func rescheduleMorningBrief() {
        guard isKindEnabled(.morningBrief) else {
            cancelPending(.morningBrief)
            return
        }

        let cal = Calendar.current
        let now = Date()
        let minutes = (UserDefaults.standard.object(forKey: "notif_morning_time") as? Int) ?? 8 * 60
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        comps.second = 0
        guard var fireDate = cal.date(from: comps) else { return }
        if fireDate <= now {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        // Shared with MorningBriefCard's "Ask Astra about today" button
        // (Views/Components/MorningBriefCard.swift, `coachPrompt`) — both
        // routes into Coach must land on the identical prompt.
        let chatPrompt = "Walk me through my morning brief"

        // Work Package B2: if MorningBriefEngine already has an Astra-WRITTEN
        // brief for TODAY, use its narrative + suggestion instead of the v1
        // engine-composed one-liner. `.engine`-sourced or missing content
        // falls straight through to the unchanged v1 body below — a live
        // user never sees a blank notification.
        if let astraContent = MorningBriefEngine.shared.todaysContent,
           astraContent.source == .astra,
           let narrative = astraContent.narrative, !narrative.isEmpty {
            let suggestion = astraContent.suggestion ?? ""
            let combined = suggestion.isEmpty ? narrative : "\(narrative) \(suggestion)"
            schedule(.morningBrief, title: "Your morning brief",
                     body: Self.truncatedNotificationBody(combined), at: fireDate,
                     chatPrompt: chatPrompt)
            return
        }

        // No engine data yet (e.g. called from didBecomeActive during launch,
        // before HealthKit has returned anything) — leave any PREVIOUSLY
        // scheduled morning brief alone rather than cancelling it. This can
        // run again once real data lands (HealthKitManager.recomputePredictions
        // calls back into this), so a transient nil body must never nuke a
        // request that was already correctly scheduled.
        guard let body = buildMorningBriefBody() else { return }

        schedule(.morningBrief, title: "Your morning brief", body: body, at: fireDate,
                 chatPrompt: chatPrompt)
    }

    /// iOS shows roughly 4 lines of an expanded notification body — clip the
    /// Astra-written narrative + suggestion to a safe character budget rather
    /// than trusting the model to stay short on its own.
    private static func truncatedNotificationBody(_ text: String, limit: Int = 240) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(limit - 1, 0))) + "\u{2026}"
    }

    /// Real values only, pulled from whatever engines currently have data:
    /// - Recovery/readiness: `HealthKitManager.predictions.recovery`
    ///   (`PredictionEngine.predictRecoveryReadiness`, computed in
    ///   `HealthKitManager.recomputePredictions`).
    /// - Sleep last night: `HealthKitManager.metricSummaries[.sleep].currentValue`
    ///   (most-recent-non-zero night — `HealthKitManager.fetchSleep()`).
    /// - Training load: `TrainingLoadEngine.acwrZone` / `.chronicLoad`.
    /// - Streak: `StreakEngine.currentStreak` (refreshed here so it reflects
    ///   the latest HealthKit state even if DashboardView hasn't run this
    ///   session).
    /// Returns nil (→ don't schedule) when none of the four have anything to say.
    private func buildMorningBriefBody() -> String? {
        let hk = HealthKitManager.shared
        var parts: [String] = []

        if let recovery = hk.predictions?.recovery {
            parts.append("recovery \(recovery.score)/100 — \(recovery.label.headline.lowercased())")
        }
        if let sleepHours = hk.metricSummaries[.sleep]?.currentValue, sleepHours > 0 {
            parts.append("slept \(String(format: "%.1f", sleepHours))h")
        }
        let load = TrainingLoadEngine.shared
        if load.chronicLoad > 0 {
            parts.append("training load \(load.acwrZone.label.lowercased())")
        }
        StreakEngine.shared.refresh()
        let streak = StreakEngine.shared.currentStreak
        if streak > 0 {
            parts.append("\(streak)-week streak")
        }

        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " · ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    // MARK: - Event nudges (HealthKit-driven)

    /// Evaluates every HealthKit-driven proactive nudge against the latest
    /// engine state and schedules/cancels each independently. Cheap —
    /// UserDefaults reads + a handful of `schedule`/`cancelPending` calls, no
    /// I/O of its own. Safe to call on every prediction recompute
    /// (`HealthKitManager.recomputePredictions`) and from the BGAppRefresh
    /// handler.
    public func evaluateProactiveNudges() {
        // Each nudge guards on its own data instead of a blanket predictions
        // check — streak-risk and recovery-guidance read straight from
        // HealthKitManager/TrainingLoadEngine and don't need `predictions` at
        // all, so a day with no predictions snapshot yet shouldn't silently
        // skip them too.
        if let predictions = HealthKitManager.shared.predictions {
            evaluateIllnessWarning(predictions)
            evaluateSleepWindDown(predictions)
        }
        evaluateStreakRisk()
        evaluateRecoveryGuidance()
        evaluateMealReminder()
    }

    /// Source: `HealthKitManager.todayFoodLog` — the same source the Home
    /// Meals card and Nutrition dashboard read for "meals logged today"
    /// honesty (Session 33). Fires at most once per calendar day, deduped
    /// via `notif_meal_last_fired`, and only past 14:00 local with nothing
    /// logged yet today. Cancels any pending request the moment food IS
    /// logged (e.g. right after `log_food` calls `refreshDietaryNow` and
    /// `recomputePredictions` re-triggers this evaluation), so a reminder
    /// scheduled earlier in the day never fires after the fact.
    private func evaluateMealReminder() {
        let hk = HealthKitManager.shared
        guard hk.todayFoodLog.isEmpty, hk.dietaryCaloriesToday <= 0 else {
            cancelPending(.mealReminder)
            return
        }

        let cal = Calendar.current
        let now = Date()
        guard cal.component(.hour, from: now) >= 14 else {
            cancelPending(.mealReminder)
            return
        }

        let key = "notif_meal_last_fired"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, cal.isDateInToday(last) {
            return
        }

        // Only quote a protein target if the user/Astra actually set one
        // (NutritionTargets starts genuinely nil) — never invent a number.
        let body: String
        if let target = NutritionTargets.shared.proteinTargetG {
            body = "Nothing logged yet today — protein target \(Int(target.rounded()))g."
        } else {
            body = "Nothing logged yet today."
        }

        // +5s, not `now` exactly — `schedule` requires `fireDate.timeIntervalSinceNow
        // > 0`, and by the time it re-checks that, an exact `now` snapshot taken
        // here would already read as zero/negative and get silently dropped
        // (same race `evaluateIllnessWarning` avoids above).
        if schedule(.mealReminder, title: "Log today's food?",
                    body: body, at: now.addingTimeInterval(5),
                    chatPrompt: "Help me log what I've eaten today.") {
            UserDefaults.standard.set(now, forKey: key)
        }
    }

    /// Source: `Predictions.illnessWarning` (`PredictionEngine.computeIllnessWarning`,
    /// PredictionEngine.swift). Fires at most once per calendar day, deduped
    /// via `notif_illness_last_fired`.
    private func evaluateIllnessWarning(_ predictions: Predictions) {
        guard let illness = predictions.illnessWarning else { return }
        let cal = Calendar.current
        let key = "notif_illness_last_fired"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, cal.isDateInToday(last) {
            return
        }

        var signals: [String] = []
        if illness.rhrDeltaBpm > 0 {
            signals.append("resting HR +\(String(format: "%.0f", illness.rhrDeltaBpm)) bpm vs baseline")
        }
        if illness.hrvDropPct > 0 {
            signals.append("HRV down \(String(format: "%.0f", illness.hrvDropPct))%")
        }
        if illness.sleepDebtHours > 0 {
            signals.append("\(String(format: "%.1f", illness.sleepDebtHours))h sleep debt")
        }
        let signalText = signals.isEmpty ? "resting HR, HRV, and sleep drifting together" : signals.joined(separator: ", ")
        let capitalized = signalText.prefix(1).uppercased() + signalText.dropFirst()
        let dayWord = illness.consecutiveDays == 1 ? "day" : "days"
        let body = "\(capitalized) — \(illness.consecutiveDays) \(dayWord) running. Early strain signals, not a diagnosis."

        // Only stamp "fired today" if `schedule` actually cleared its
        // synchronous gates (kind enabled, not quiet-hours-skipped, not
        // already past) — otherwise a dropped request still burns the once-
        // per-day dedupe and the warning goes silent for the rest of the day.
        // Authorization is checked async inside `schedule`; accepting that as
        // an edge case (rather than plumbing the async result back here) is
        // the documented tradeoff.
        if schedule(.illnessWarning, title: "Astra noticed something",
                    body: body, at: Date().addingTimeInterval(5),
                    chatPrompt: "Why is my illness risk elevated?") {
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }

    /// Source: `HealthKitManager.recentWorkouts28` (today's slice) and
    /// `metricSummaries[.steps]` vs `HealthKitManager.userGoal(for: .steps)` —
    /// the same day-level qualifying condition `StreakEngine.buildWeeklyActivity`
    /// uses per-day (StreakEngine.swift), applied to just today. Body quotes
    /// `StreakEngine.currentStreak`.
    private func evaluateStreakRisk() {
        let hk = HealthKitManager.shared
        let cal = Calendar.current
        let now = Date()
        let workoutToday = hk.recentWorkouts28.contains { cal.isDate($0.startDate, inSameDayAs: now) }
        let stepGoal = HealthKitManager.userGoal(for: .steps)
        let stepsToday = hk.metricSummaries[.steps]?.currentValue ?? 0
        let qualifiesToday = workoutToday || (stepGoal > 0 && stepsToday >= stepGoal)

        guard !qualifiesToday else {
            cancelPending(.streakRisk)
            return
        }

        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 20; comps.minute = 30; comps.second = 0
        guard let fireDate = cal.date(from: comps) else { return }

        StreakEngine.shared.refresh()
        let streak = StreakEngine.shared.currentStreak
        let streakPhrase = streak > 0 ? "your \(streak)-week streak" : "this week's activity streak"
        let progress = stepGoal > 0 ? "\(Int(stepsToday))/\(Int(stepGoal)) steps" : "\(Int(stepsToday)) steps"
        let body = "\(progress), no workout logged yet — \(streakPhrase) is still open tonight."

        schedule(.streakRisk, title: "Keep your streak alive",
                 body: body, at: fireDate,
                 chatPrompt: "Help me protect my activity streak today.")
    }

    /// Source: `Predictions.sleepForecast` (`PredictionEngine.computeSleepForecast`).
    /// "Poor" = forecast under 6.5h, or meaningfully (>=45min) below the
    /// user's own baseline night. Body quotes the engine's own `basis`
    /// sentence verbatim — already a deterministic sentence built from the
    /// user's real historical numbers.
    private func evaluateSleepWindDown(_ predictions: Predictions) {
        guard let forecast = predictions.sleepForecast else { return }
        let isPoor = forecast.predictedHours < 6.5 || forecast.predictedHours < forecast.baselineHours - 0.75
        guard isPoor else {
            cancelPending(.sleepWindDown)
            return
        }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 21; comps.minute = 30; comps.second = 0
        guard let fireDate = cal.date(from: comps) else { return }

        let body = "\(forecast.basis) Consider winding down early tonight."
        schedule(.sleepWindDown, title: "Tonight's sleep forecast is short",
                 body: body, at: fireDate,
                 chatPrompt: "Help me wind down for better sleep tonight.")
    }

    /// Source: `TrainingLoadEngine.dailyLoads` (today's entry) + `.acwrZone` /
    /// `.acwr`. Fires when today carried real load AND the acute:chronic
    /// ratio is elevated (`.caution` or `.overreach` — TrainingLoadEngine.swift).
    private func evaluateRecoveryGuidance() {
        let engine = TrainingLoadEngine.shared
        let cal = Calendar.current
        let now = Date()
        let todayLoad = engine.dailyLoads.first(where: { cal.isDate($0.date, inSameDayAs: now) })?.load ?? 0

        let isElevated: Bool
        switch engine.acwrZone {
        case .caution, .overreach: isElevated = true
        case .optimal, .low: isElevated = false
        }

        guard todayLoad > 0, isElevated else {
            cancelPending(.recoveryGuidance)
            return
        }

        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 19; comps.minute = 0; comps.second = 0
        guard let fireDate = cal.date(from: comps) else { return }

        let body = "Today's acute:chronic load ratio hit \(String(format: "%.2f", engine.acwr)) — \(engine.acwrZone.subtitle)"
        schedule(.recoveryGuidance, title: "Recovery guidance",
                 body: body, at: fireDate,
                 chatPrompt: "How should I recover after today's high training load?")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Foreground presentation: silent banner for the four transient nudges,
    /// banner + sound for morningBrief / weeklyReview / sedentaryAlert.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                        willPresent notification: UNNotification,
                                        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kind = AstraNotificationKind(rawValue: notification.request.identifier)
        let playsSound = kind.map { Self.soundedKinds.contains($0) } ?? false
        completionHandler(playsSound ? [.banner, .sound] : [.banner])
    }

    /// Tap routing: queue the notification's `chatPrompt` (if any) into
    /// `ChatPrefillBus` — ContentView already auto-switches to the Coach tab
    /// once the bus publishes a pending prompt.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                        didReceive response: UNNotificationResponse,
                                        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let chatPrompt = response.notification.request.content.userInfo["chatPrompt"] as? String {
            ChatPrefillBus.shared.queue(chatPrompt)
        }
        completionHandler()
    }
}
