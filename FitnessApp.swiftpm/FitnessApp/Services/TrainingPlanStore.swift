import Foundation

/// Astra-authored weekly training plan — the single source of truth for
/// "what should I do this week" that both the AI (`set_training_plan` /
/// `get_training_plan` / `mark_workout_done` tools, dispatched from
/// `ChatViewModel`) and the UI (`TrainingPlanCard` on the Progress hub) read
/// from. Persisted as a single JSON file in Application Support — a plan's
/// free-text `detail` can run up to 400 chars/day across up to 14 days,
/// comfortably past what's comfortable to keep in a UserDefaults plist blob
/// (the pattern `AstraWidgetStore` uses for its much smaller payload).
///
/// Only ONE active plan exists at a time — covering the current week and
/// optionally the next, per the design brief. Setting a new plan (via
/// `set_training_plan`) replaces it outright; there is no history of past
/// weeks' plans. `WeeklyReviewEngine`'s adherence line for a reviewed week
/// comes back honestly empty once that week's plan has been superseded.
@MainActor
public final class TrainingPlanStore: ObservableObject {
    public static let shared = TrainingPlanStore()

    // MARK: - Models

    public struct PlannedDay: Codable, Equatable, Identifiable {
        public enum Kind: String, Codable, CaseIterable, Equatable {
            case strength, cardio, mobility, rest

            public var displayName: String {
                switch self {
                case .strength: return "Strength"
                case .cardio:   return "Cardio"
                case .mobility: return "Mobility"
                case .rest:     return "Rest"
                }
            }

            /// SF Symbol name — shared by the chat tool-card preview
            /// (`ToolCards.swift`) and the Progress-hub `TrainingPlanCard`
            /// day chips so both surfaces agree on iconography.
            public var icon: String {
                switch self {
                case .strength: return "dumbbell.fill"
                case .cardio:   return "figure.run"
                case .mobility: return "figure.flexibility"
                case .rest:     return "bed.double.fill"
                }
            }
        }

        public var id: UUID
        public var date: Date            // start-of-day, local calendar
        public var title: String         // e.g. "Push — chest focus"
        public var detail: String        // free text, ≤400 chars — exercises / notes
        public var kind: Kind
        public var durationMin: Int      // 10-240
        public var completed: Bool
        /// EventKit identifier for the calendar event this plan created for
        /// this day (nil for rest days, or when calendar access was denied
        /// at save time). Used to delete ONLY app-created events when a plan
        /// is replaced — see `ChatViewModel.executeSetTrainingPlan`.
        public var calendarEventId: String?

        public init(id: UUID = UUID(), date: Date, title: String, detail: String,
                    kind: Kind, durationMin: Int, completed: Bool = false,
                    calendarEventId: String? = nil) {
            self.id = id
            self.date = date
            self.title = title
            self.detail = detail
            self.kind = kind
            self.durationMin = durationMin
            self.completed = completed
            self.calendarEventId = calendarEventId
        }
    }

    public struct TrainingPlan: Codable, Equatable, Identifiable {
        public let id: UUID
        public let createdAt: Date
        public let weekStart: Date       // Monday, start-of-day
        public var days: [PlannedDay]

        public init(id: UUID = UUID(), createdAt: Date = Date(), weekStart: Date, days: [PlannedDay]) {
            self.id = id
            self.createdAt = createdAt
            self.weekStart = weekStart
            self.days = days
        }
    }

    /// Completed vs planned NON-REST sessions for some 7-day window.
    public struct Adherence: Equatable {
        public let completed: Int
        public let total: Int
        public var pct: Double { total > 0 ? Double(completed) / Double(total) * 100 : 0 }
    }

    // MARK: - Published state

    @Published public private(set) var activePlan: TrainingPlan?

    private init() {
        load()
    }

    // MARK: - Public API

    /// Replaces the active plan outright. Callers that need to tear down the
    /// previous plan's calendar events must read `activePlan` BEFORE calling
    /// this (it's about to be overwritten) — see
    /// `ChatViewModel.executeSetTrainingPlan`.
    @discardableResult
    public func upsert(_ plan: TrainingPlan) -> TrainingPlan {
        activePlan = plan
        save()
        return plan
    }

    /// Marks (or unmarks) the planned day matching `date` (compared by
    /// calendar day, not exact timestamp) as completed. No-op — returns
    /// `false` — when there's no active plan or no day matches that date.
    @discardableResult
    public func markCompleted(date: Date, completed: Bool = true) -> Bool {
        guard var plan = activePlan else { return false }
        let cal = Calendar.current
        guard let idx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) else { return false }
        plan.days[idx].completed = completed
        activePlan = plan
        save()
        return true
    }

    public func clear() {
        activePlan = nil
        save()
    }

    /// Adherence for the 7-day window starting `weekStart` (inclusive,
    /// through `weekStart`+6) — completed vs planned NON-REST days only.
    /// Works for any 7-day window, not just the active plan's own
    /// Monday-anchored week, so `WeeklyReviewEngine` can pass its own
    /// rolling review window and still get a correct count as long as the
    /// active plan's days overlap it. Returns `nil` when there's no active
    /// plan, or none of its training days fall inside the window — an
    /// honest "nothing to report" rather than a fake 0/0.
    public func adherence(for weekStart: Date) -> Adherence? {
        guard let plan = activePlan else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: weekStart)
        guard let end = cal.date(byAdding: .day, value: 6, to: start) else { return nil }
        let trainingDays = plan.days.filter { day in
            let d = cal.startOfDay(for: day.date)
            return d >= start && d <= end && day.kind != .rest
        }
        guard !trainingDays.isEmpty else { return nil }
        let completed = trainingDays.filter { $0.completed }.count
        return Adherence(completed: completed, total: trainingDays.count)
    }

    /// The Monday-anchored calendar week containing `date` — the same
    /// alignment `set_training_plan`'s `week_start` is expected to use.
    public static func mondayOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    /// This calendar week's planned days (Monday–Sunday containing today),
    /// sorted by date — what the Progress-hub `TrainingPlanCard` renders as
    /// its 7 day chips. Empty when there's no active plan, or its days don't
    /// overlap the current week (e.g. a plan authored only for "next week").
    public var currentWeekDays: [PlannedDay] {
        guard let plan = activePlan else { return [] }
        let cal = Calendar.current
        let start = Self.mondayOfWeek(containing: Date(), calendar: cal)
        guard let end = cal.date(byAdding: .day, value: 6, to: start) else { return [] }
        return plan.days
            .filter { let d = cal.startOfDay(for: $0.date); return d >= start && d <= end }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Persistence (JSON file in Application Support)
    //
    // Same directory-per-store / atomic-write shape as
    // WeeklyReviewEngine's disk cache, minus the per-week file fan-out —
    // this store only ever keeps ONE active plan, so a single file suffices.

    private static let dirName = "TrainingPlan"
    private static let fileName = "active_plan.json"

    private func fileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(Self.dirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(Self.fileName)
    }

    private func load() {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return }
        activePlan = try? JSONDecoder().decode(TrainingPlan.self, from: data)
    }

    private func save() {
        guard let url = fileURL() else { return }
        guard let plan = activePlan else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(plan) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
