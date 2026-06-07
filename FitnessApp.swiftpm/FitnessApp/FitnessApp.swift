import SwiftUI

@main
struct FitnessApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.migrateHomeCardsList()
        Task { await NotificationManager.shared.requestPermissionIfNeeded() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                SleepFocusDetector.shared.start()
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
}
