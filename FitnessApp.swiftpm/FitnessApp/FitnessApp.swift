import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct FitnessApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Must match Info.plist's `BGTaskSchedulerPermittedIdentifiers` entry.
    private static let backgroundRefreshTaskID = "com.tushar.fitnessapp.refresh"

    init() {
        Self.migrateHomeCardsList()
        Self.migrateLoginGate()
        Self.migrateImplausibleDOB()

        // NotificationManager owns tap routing (queues a notification's
        // chatPrompt into ChatPrefillBus) and foreground presentation, so it
        // must be the delegate before any notification can be shown or tapped.
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        Task { await NotificationManager.shared.requestPermissionIfNeeded() }

        // Touch the singleton early so its .gatewaySessionEstablished /
        // didBecomeActive retry observers are registered from launch, not
        // just whenever something else happens to first reference it.
        _ = GatewayProfileSync.shared

        Self.registerBackgroundRefresh()

        #if DEBUG
        DispatchQueue.main.async {
            DebugScrollAudit.start()
            DebugNotificationAudit.start()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Not before onboarding completes: starting the Focus poll on
                // a fresh install fires the system Focus-sharing permission
                // dialog OVER the Welcome screen (seen in the fresh-install
                // smoke test). ContentView starts it when onboarding ends.
                if UserDefaults.standard.bool(forKey: "is_onboarded") {
                    SleepFocusDetector.shared.start()
                }
            case .background:
                SleepFocusDetector.shared.stop()
            default:
                break
            }
        }
    }

    /// Idempotent one-shot migrations on `home_cards_list`. Each block is
    /// keyed off the absence of the specific card it's adding, so once a
    /// migration has been applied it's a no-op forever — no separate flags
    /// to manage.
    private static func migrateHomeCardsList() {
        let key = "home_cards_list"
        guard let existing = UserDefaults.standard.string(forKey: key) else { return }
        var parts = existing.components(separatedBy: ",").filter { !$0.isEmpty }

        // Splice "predictions" after "coach" (added in Session 7).
        if !parts.contains("predictions") {
            if let idx = parts.firstIndex(of: "coach") {
                parts.insert("predictions", at: idx + 1)
            } else {
                parts.insert("predictions", at: 0)
            }
        }

        // Splice "distance" after "calories" so walking + running distance
        // surfaces alongside the other always-on activity tiles.
        if !parts.contains("distance") {
            if let idx = parts.firstIndex(of: "calories") {
                parts.insert("distance", at: idx + 1)
            } else {
                parts.append("distance")
            }
        }

        // Splice "meals" after "distance" so logged food surfaces inline with
        // the other activity tiles.
        if !parts.contains("meals") {
            if let idx = parts.firstIndex(of: "distance") {
                parts.insert("meals", at: idx + 1)
            } else if let idx = parts.firstIndex(of: "calories") {
                parts.insert("meals", at: idx + 1)
            } else {
                parts.append("meals")
            }
        }

        // Splice "widgets" right after "predictions" so Astra-authored cards
        // sit at the top of the grid where the user expects fresh AI content.
        if !parts.contains("widgets") {
            if let idx = parts.firstIndex(of: "predictions") {
                parts.insert("widgets", at: idx + 1)
            } else if let idx = parts.firstIndex(of: "coach") {
                parts.insert("widgets", at: idx + 1)
            } else {
                parts.insert("widgets", at: 0)
            }
        }

        // Splice "tracksleep" right above the read-only sleep card so the
        // on-device tracker entry point sits adjacent to the metric it powers.
        if !parts.contains("tracksleep") {
            if let idx = parts.firstIndex(of: "sleep") {
                parts.insert("tracksleep", at: idx)
            } else {
                parts.append("tracksleep")
            }
        }

        let updated = parts.joined(separator: ",")
        if updated != existing {
            UserDefaults.standard.set(updated, forKey: key)
        }
    }

    /// One-time migration for the `is_logged_in` default flip (true → false).
    /// Before this change, fresh installs skipped LoginView entirely because
    /// the AppStorage default was `true`, so no gateway session was ever
    /// created and every AI call threw `.notSignedIn`. Now the default is
    /// `false` so new installs actually go through LoginView. That means any
    /// *existing* install that finished onboarding pre-fix never wrote a value
    /// for `is_logged_in` (it only ever read the default) — without this
    /// migration those users would suddenly be dropped at LoginView on next
    /// launch. Detect that exact case (no stored key + already onboarded) and
    /// stamp `true` once so upgraders keep their session state; every other
    /// path (fresh install, or an install that already wrote the key) is
    /// left alone.
    private static func migrateLoginGate() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "is_logged_in") == nil && defaults.bool(forKey: "is_onboarded") {
            defaults.set(true, forKey: "is_logged_in")
        }
    }

    /// One-time cleanup of a corrupt stored birth date. The Personal-details
    /// sheet's date wheel used to default to *today*; saving without touching
    /// it stamped `athlete_dob` ≈ save-day (seen live: "DOB May 2026" → Age 0,
    /// which also poisoned HR-zone max-HR math with 220-0). An implausible
    /// stored DOB (outside age 5…120) is bad data, not a fact — remove it so
    /// every consumer falls back to Apple Health's DOB or honest absence.
    private static func migrateImplausibleDOB() {
        let ud = UserDefaults.standard
        let interval = ud.double(forKey: "athlete_dob")
        guard interval > 0 else { return }
        let years = Calendar.current.dateComponents(
            [.year], from: Date(timeIntervalSince1970: interval), to: Date()).year ?? 0
        if !(5...120).contains(years) {
            ud.removeObject(forKey: "athlete_dob")
        }
    }

    // MARK: - Background refresh (proactive notifications)

    /// Registers the BGAppRefresh handler. Must happen before the app
    /// finishes launching, so this runs synchronously from `init()` — the
    /// handler re-evaluates event nudges, reschedules the morning brief, and
    /// always resubmits the next request so the ~4h cadence continues.
    private static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handleBackgroundRefresh(refreshTask)
        }
        submitBackgroundRefreshRequest()
    }

    private static func submitBackgroundRefreshRequest() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600) // ~4h cadence
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Always resubmit first so a slow/expired refresh never breaks the cadence.
        submitBackgroundRefreshRequest()

        // HealthKit continuations don't observe Task cancellation, so the
        // expiration handler can't just cancel `work` and trust the normal
        // completion path to call setTaskCompleted before the grace window
        // ends — that race is a watchdog kill. One-shot completion flag:
        // whichever side (expiration or normal completion) gets there first
        // wins; the other becomes a no-op.
        let completionLock = NSLock()
        var isCompleted = false
        func completeOnce(_ success: Bool) {
            completionLock.lock()
            defer { completionLock.unlock() }
            guard !isCompleted else { return }
            isCompleted = true
            task.setTaskCompleted(success: success)
        }

        // Assign the expiration handler BEFORE starting `work` so there's no
        // window where expiration could fire against a not-yet-assigned handler.
        var work: Task<Void, Never>?
        task.expirationHandler = {
            completeOnce(false)
            work?.cancel()
        }

        work = Task {
            await HealthKitManager.shared.refreshIfStale(maxAgeMinutes: 60)
            await MainActor.run {
                NotificationManager.shared.evaluateProactiveNudges()
            }
            // Work Package B2: attempt today's Astra-written morning brief
            // before rescheduling the notification, so the notification body
            // (NotificationManager.rescheduleMorningBrief) can pick it up the
            // same cycle instead of waiting for the next BG refresh.
            await MorningBriefEngine.shared.generateIfNeeded()
            await MainActor.run {
                NotificationManager.shared.rescheduleMorningBrief()
            }
        }

        Task {
            _ = await work?.result
            completeOnce(!(work?.isCancelled ?? true))
        }
    }
}
