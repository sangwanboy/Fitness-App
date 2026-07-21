import Foundation
import EventKit
import SwiftUI

@MainActor
public final class EventKitManager: ObservableObject {
    public static let shared = EventKitManager()

    private let store = EKEventStore()

    @Published public var calendarsGranted = false
    @Published public var remindersGranted = false
    @Published public var events: [EKEvent] = []
    @Published public var reminders: [EKReminder] = []
    @Published public var isLoading = false

    private init() {}

    // MARK: - Authorization

    public func requestAccess() async {
        await requestCalendarAccess()
        await requestRemindersAccess()
    }

    public func requestCalendarAccess() async {
        // Skip the request if iOS already has a decision — calling it every launch
        // can briefly flash the consent sheet on iOS 26.
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .authorized {
            calendarsGranted = true; return
        }
        if status == .denied || status == .restricted || status == .writeOnly {
            calendarsGranted = false; return
        }
        do {
            if #available(iOS 17.0, *) {
                let granted = try await store.requestFullAccessToEvents()
                calendarsGranted = granted
            } else {
                let granted = try await store.requestAccess(to: .event)
                calendarsGranted = granted
            }
        } catch {
            calendarsGranted = false
        }
    }

    public func requestRemindersAccess() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess || status == .authorized {
            remindersGranted = true; return
        }
        if status == .denied || status == .restricted {
            remindersGranted = false; return
        }
        do {
            if #available(iOS 17.0, *) {
                let granted = try await store.requestFullAccessToReminders()
                remindersGranted = granted
            } else {
                let granted = try await store.requestAccess(to: .reminder)
                remindersGranted = granted
            }
        } catch {
            remindersGranted = false
        }
    }

    // MARK: - App-owned calendars
    //
    // All reads and writes are scoped to a dedicated "Fitness Guru" calendar
    // (events) and reminder list — so the in-app Calendar / Reminders screens
    // never display the user's personal events, and writes can't pollute their
    // default lists. The first save lazily creates the calendar/list; the
    // identifier is persisted in UserDefaults and re-resolved each launch.

    private static let appEventCalendarIDKey   = "app_event_calendar_id"
    private static let appReminderListIDKey    = "app_reminder_list_id"
    private static let appCalendarTitle        = "Fitness Guru"

    /// iCloud > local > default — same source the user already syncs to so the
    /// calendar appears in their normal Apple Calendar lineup.
    private func preferredEventSource() -> EKSource? {
        if let s = store.defaultCalendarForNewEvents?.source { return s }
        if let s = store.sources.first(where: { $0.sourceType == .calDAV }) { return s }
        return store.sources.first(where: { $0.sourceType == .local })
    }

    private func preferredReminderSource() -> EKSource? {
        if let s = store.defaultCalendarForNewReminders()?.source { return s }
        if let s = store.sources.first(where: { $0.sourceType == .calDAV }) { return s }
        return store.sources.first(where: { $0.sourceType == .local })
    }

    /// Return the existing "Fitness Guru" calendar by stored identifier; if it
    /// was deleted by the user (or never created), build a fresh one.
    @discardableResult
    public func ensureAppEventCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: Self.appEventCalendarIDKey),
           let existing = store.calendar(withIdentifier: id),
           existing.allowedEntityTypes.contains(.event) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = Self.appCalendarTitle
        cal.cgColor = UIColor.systemGreen.cgColor
        guard let source = preferredEventSource() else {
            throw NSError(domain: "EventKitManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No event source available to host the Fitness Guru calendar."])
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: Self.appEventCalendarIDKey)
        return cal
    }

    @discardableResult
    public func ensureAppReminderList() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: Self.appReminderListIDKey),
           let existing = store.calendar(withIdentifier: id),
           existing.allowedEntityTypes.contains(.reminder) {
            return existing
        }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = Self.appCalendarTitle
        cal.cgColor = UIColor.systemGreen.cgColor
        guard let source = preferredReminderSource() else {
            throw NSError(domain: "EventKitManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No reminder source available to host the Fitness Guru list."])
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: Self.appReminderListIDKey)
        return cal
    }

    // MARK: - Calendar reads (app-scoped)

    /// Fetch events between two dates. **Only** events on the app's own
    /// "Fitness Guru" calendar — the user's personal events never appear in
    /// the in-app Calendar view.
    public func fetchEvents(from start: Date, to end: Date) {
        guard calendarsGranted else { return }
        do {
            let appCal = try ensureAppEventCalendar()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [appCal])
            events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        } catch {
            events = []
        }
    }

    // MARK: - Calendar writes (app-scoped)

    public func addEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) -> Bool {
        guard calendarsGranted else { return false }
        do {
            let appCal = try ensureAppEventCalendar()
            let ev = EKEvent(eventStore: store)
            ev.title = title
            ev.startDate = startDate
            ev.endDate = endDate
            ev.notes = notes
            ev.calendar = appCal
            try store.save(ev, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Same as `addEvent` but returns the created event's identifier (nil on
    /// failure or missing permission) instead of a bare Bool — used by
    /// callers that need to remember the id for a later targeted delete
    /// (e.g. `set_training_plan`'s execution, which tears down only the
    /// events IT created when a plan is replaced). Purely additive: existing
    /// `addEvent` callers are unaffected.
    @discardableResult
    public func addEventReturningId(title: String, startDate: Date, endDate: Date, notes: String? = nil) -> String? {
        guard calendarsGranted else { return nil }
        do {
            let appCal = try ensureAppEventCalendar()
            let ev = EKEvent(eventStore: store)
            ev.title = title
            ev.startDate = startDate
            ev.endDate = endDate
            ev.notes = notes
            ev.calendar = appCal
            try store.save(ev, span: .thisEvent, commit: true)
            return ev.eventIdentifier
        } catch {
            return nil
        }
    }

    // MARK: - LLM-facing ops (app-scoped by construction)
    //
    // These are the only mutation entry points the AI coach is allowed to use.
    // Every helper either operates on the app's "Fitness Guru" calendar / list,
    // or checks that the target item lives on it — so Astra can never touch
    // the user's personal events or reminders.

    /// List app events in the next `daysAhead` days. Returns a stable
    /// projection (id, title, ISO start/end, notes) that the LLM can feed back
    /// into `update_calendar_event` / `delete_calendar_event` by id.
    public func listAppEvents(daysAhead: Int = 14) -> [[String: Any]] {
        guard calendarsGranted else { return [] }
        guard let appCal = try? ensureAppEventCalendar() else { return [] }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: max(1, daysAhead), to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: [appCal])
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { ev in
            [
                "id":         ev.eventIdentifier ?? "",
                "title":      ev.title ?? "",
                "starts_at":  iso.string(from: ev.startDate),
                "ends_at":    iso.string(from: ev.endDate),
                "notes":      ev.notes ?? ""
            ]
        }
    }

    /// List app reminders. Returns id, title, ISO due (if any), completion state.
    public func listAppReminders() async -> [[String: Any]] {
        guard remindersGranted else { return [] }
        guard let appList = try? ensureAppReminderList() else { return [] }
        let predicate = store.predicateForReminders(in: [appList])
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return await withCheckedContinuation { (cont: CheckedContinuation<[[String: Any]], Never>) in
            store.fetchReminders(matching: predicate) { fetched in
                let items: [[String: Any]] = (fetched ?? []).map { r in
                    var dict: [String: Any] = [
                        "id":        r.calendarItemIdentifier,
                        "title":     r.title ?? "",
                        "completed": r.isCompleted,
                        "notes":     r.notes ?? ""
                    ]
                    if let due = r.dueDateComponents?.date {
                        dict["due_at"] = iso.string(from: due)
                    }
                    return dict
                }
                cont.resume(returning: items)
            }
        }
    }

    /// Update an app event by id. Refuses to touch events on other calendars.
    /// nil fields preserve the existing value.
    public func updateAppEvent(id: String,
                               title: String? = nil,
                               startDate: Date? = nil,
                               endDate: Date? = nil,
                               notes: String? = nil) -> Bool {
        guard calendarsGranted else { return false }
        guard let appCal = try? ensureAppEventCalendar() else { return false }
        guard let ev = store.event(withIdentifier: id) else { return false }
        guard ev.calendar.calendarIdentifier == appCal.calendarIdentifier else { return false }

        if let title { ev.title = title }
        if let startDate { ev.startDate = startDate }
        if let endDate { ev.endDate = endDate }
        if let notes { ev.notes = notes }
        do {
            try store.save(ev, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Update an app reminder by id. Refuses to touch reminders on other lists.
    /// nil fields preserve the existing value.
    public func updateAppReminder(id: String,
                                  title: String? = nil,
                                  dueDate: Date? = nil,
                                  notes: String? = nil) async -> Bool {
        guard remindersGranted else { return false }
        guard let appList = try? ensureAppReminderList() else { return false }
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        guard item.calendar.calendarIdentifier == appList.calendarIdentifier else { return false }

        if let title { item.title = title }
        if let dueDate {
            item.dueDateComponents = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        if let notes { item.notes = notes }
        do {
            try store.save(item, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Delete an app event by id. Refuses if the id doesn't belong to the app calendar.
    public func deleteAppEvent(id: String) -> Bool {
        guard calendarsGranted else { return false }
        guard let appCal = try? ensureAppEventCalendar() else { return false }
        guard let ev = store.event(withIdentifier: id) else { return false }
        guard ev.calendar.calendarIdentifier == appCal.calendarIdentifier else { return false }
        do {
            try store.remove(ev, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Delete an app reminder by id. Refuses if the id doesn't belong to the app list.
    public func deleteAppReminder(id: String) -> Bool {
        guard remindersGranted else { return false }
        guard let appList = try? ensureAppReminderList() else { return false }
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        guard item.calendar.calendarIdentifier == appList.calendarIdentifier else { return false }
        do {
            try store.remove(item, commit: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reminder reads (app-scoped)

    /// Only reminders on the app's own "Fitness Guru" list. The user's
    /// personal grocery / work reminders never appear in the in-app
    /// Reminders screen.
    public func fetchReminders() async {
        guard remindersGranted else { return }
        let appList: EKCalendar
        do { appList = try ensureAppReminderList() }
        catch { reminders = []; return }

        let predicate = store.predicateForReminders(in: [appList])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.fetchReminders(matching: predicate) { fetched in
                Task { @MainActor in
                    self.reminders = (fetched ?? []).sorted {
                        ($0.dueDateComponents?.date ?? .distantFuture) <
                        ($1.dueDateComponents?.date ?? .distantFuture)
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Reminder writes (app-scoped)

    public func addReminder(title: String, dueDate: Date?, notes: String? = nil) -> Bool {
        guard remindersGranted else { return false }
        do {
            let appList = try ensureAppReminderList()
            let r = EKReminder(eventStore: store)
            r.title = title
            r.notes = notes
            if let dueDate {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                r.dueDateComponents = comps
            }
            r.calendar = appList
            try store.save(r, commit: true)
            return true
        } catch {
            return false
        }
    }

    public func toggleCompletion(_ reminder: EKReminder) -> Bool {
        reminder.isCompleted.toggle()
        if reminder.isCompleted { reminder.completionDate = Date() } else { reminder.completionDate = nil }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            reminder.isCompleted.toggle()
            return false
        }
    }

    public func deleteReminder(_ reminder: EKReminder) -> Bool {
        do {
            try store.remove(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }
}

