import Foundation

/// Represents a single Gemini function call that the app has to render and/or execute.
/// The associated values are typed per-tool so SwiftUI can render a tailored card
/// without poking at a raw dictionary.
public enum ToolCall: Codable, Equatable {
    case logFood(
        name: String,
        calories: Double, protein: Double, carbs: Double, fat: Double,
        serving: String,
        tags: [String],
        highlights: [String],
        cautions: [String],
        isEstimate: Bool,
        confidence: String?,  // "low" | "medium" | "high" — nil for verified label data
        daysAgo: Int          // 0 = today (default), max 7 — backdated logging
    )
    // Logs a hydration sample (litres → HealthKit dietaryWater). Mirrors
    // log_food's confirmation-gated write pattern; daysAgo backdates same as
    // log_food. Distinct from the widget button_row "log_water" action (a
    // tap on an Astra-authored widget, not an LLM tool call) — this is the
    // real chat-callable tool so "log 500ml water" works from a conversation.
    case logWater(milliliters: Double, daysAgo: Int)
    // Logs a sleep session the user reports conversationally ("I slept 1:30
    // to 9", "napped 2h", "slept from 1:30 to now") to Apple Health as an
    // `.asleepUnspecified` sample — the tool that didn't exist when a real
    // incident had Astra confabulate "data gaps" / "check your watch
    // settings" instead of just writing down what the user said. `end`
    // defaults to now when the model omits it (the common "slept until now"
    // phrasing). Confirmation-gated like logWater; plausibility (end > start,
    // duration, staleness, future end) is validated at execution time in
    // `ChatViewModel.sleepLogError`, not here.
    case logSleep(start: Date, end: Date)
    case addReminder(title: String, dueAt: Date?, category: String?)
    case addCalendarEvent(title: String, startsAt: Date, endsAt: Date, notes: String?)
    case showMetricChart(metric: String, days: Int)
    case showComparisonChart(metric: String, periodA: String, periodB: String, title: String?)
    case renderCard(title: String, icon: String, color: String, headline: String?, bullets: [String], stats: [Stat])

    // App-scoped EventKit ops the LLM can drive. All restricted to the
    // "Fitness Guru" calendar / reminder list by EventKitManager — Astra
    // can never touch the user's personal events or reminders.
    case listReminders(filter: String?)                    // "all" | "active" | "completed"
    case listCalendarEvents(daysAhead: Int)                // 1-30
    case updateReminder(id: String, title: String?, dueAt: Date?, notes: String?)
    case updateCalendarEvent(id: String, title: String?, startsAt: Date?, endsAt: Date?, notes: String?)
    case deleteReminder(id: String, title: String?)        // title is hint shown on the confirm card
    case deleteCalendarEvent(id: String, title: String?)

    // On-device predictions from PredictionEngine. Auto-executes, no args.
    // Returns recovery readiness, next-likely-workout, goal trajectories,
    // and any active sedentary alert so the model can reason on structured
    // data instead of hallucinating from the prompt summary alone.
    case getPredictions

    // Today's logged food log — list / update / delete. The id passed to
    // update/delete is the UUID of the underlying dietaryEnergyConsumed
    // sample; the app's update path also delete-and-rewrites the matching
    // protein / carbs / fat samples that share its start time + name.
    case listFoodLog
    case updateFoodLog(id: String,
                       name: String?,
                       calories: Double?,
                       protein: Double?,
                       carbs: Double?,
                       fat: Double?)
    case deleteFoodLog(id: String, name: String?)

    // Astra-authored Home widgets. Persistent. Astra has full creative control
    // within a constrained schema (layout / icon / color / copy / live metric).
    case createWidget(title: String,
                      icon: String,
                      color: String,
                      layout: String,
                      headline: String?,
                      body: String?,
                      bullets: [String],
                      metricRef: String?,
                      goalValue: Double?,
                      blocks: [WidgetBlock]?)
    case listWidgets
    case updateWidget(id: String,
                      title: String?,
                      icon: String?,
                      color: String?,
                      layout: String?,
                      headline: String?,
                      body: String?,
                      bullets: [String]?,
                      metricRef: String?,
                      goalValue: Double?,
                      blocks: [WidgetBlock]?)
    case deleteWidget(id: String, title: String?)

    // Astra's cross-session memory. Overwrites the full notes blob —
    // the model manages its own pruning strategy. No user confirmation;
    // this is internal coach memory, not user data.
    case updateNotes(notes: String)

    // Structured long-term memory (AstraMemoryStore) — successor to the
    // free-text notes blob above. All four auto-execute with no user
    // confirmation, same rationale as updateNotes: this is Astra's own
    // coach memory, not a user-visible write. Each feeds a small JSON
    // payload back via functionResponse describing what happened.
    case rememberFact(category: String, text: String)
    case forgetFact(query: String)
    case updateProfile(section: String, content: String)
    case getProfile

    // Returns the user's full sleep pattern + last 5 sessions in structured
    // form. Auto-executes — Astra calls it whenever the user asks anything
    // sleep-related so the answer can cite real per-user numbers instead of
    // generic guidance.
    case getSleepPattern

    // Universal metric history read — daily values for ANY tracked HealthKit
    // metric over the last N days (clamped to 90), bucketed one-per-day.
    // Auto-executes; payload feeds back via functionResponse.
    case getMetricHistory(metric: String, days: Int)

    // Returns the last N tracked sleep sessions (clamped 1–14, default 7)
    // in structured form: duration, snoring, restlessness, stage breakdown.
    // Auto-executes; payload feeds back via functionResponse.
    case getSleepSessions(nights: Int)

    // Confirmation-gated write that updates a user-configurable daily goal
    // (the 9 metrics in HealthMetricType.isUserConfigurableGoal). Streaks,
    // challenges, and pace predictions all read the same stored goal, so
    // they adapt instantly after the write.
    case updateGoal(metric: String, value: Double)

    // Confirmation-gated: changes HR-zone math + Live Basics. Called when the
    // user states their birth date in chat — fixes the "two ages" problem
    // where Astra learns a birthday conversationally but athlete_dob (the
    // store Live Basics / HeartRateZoneCalculator read) never updates.
    case setDateOfBirth(date: Date)

    // Confirmation-gated: Astra's own suggested (or user-requested) daily
    // protein/kcal targets, distinct from the always-defaulted MacroGoals
    // used by the rings — this store starts genuinely empty ("no target
    // set") so the Nutrition dashboard can be honest about it. At least one
    // of the two fields is set per call.
    case setNutritionTargets(proteinG: Double?, kcal: Double?)

    // Astra-authored weekly training plan (TrainingPlanStore). Kind stays a
    // raw String here (not TrainingPlanStore.PlannedDay.Kind) — same
    // loose-args-in / validate-at-execution convention as `updateGoal`'s
    // `metric: String` — so a malformed value from Gemini fails with an
    // honest error at confirm-time instead of silently dropping the whole
    // tool call at parse-time.
    case getTrainingPlan
    case setTrainingPlan(weekStart: Date, days: [PlannedDayArg])
    case markWorkoutDone(date: Date)

    /// One proposed day within a `setTrainingPlan` call, before semantic
    /// validation (date window, kind enum, duration range) at execution.
    public struct PlannedDayArg: Codable, Equatable {
        public let date: Date
        public let title: String
        public let detail: String
        public let kind: String
        public let durationMin: Int
    }

    public struct Stat: Codable, Equatable {
        public let label: String
        public let value: String
    }

    /// Status the UI shows for write actions.
    public enum Status: String, Codable {
        case pending     // waiting for user to tap Confirm
        case confirmed   // user confirmed, side effect executing
        case done        // side effect succeeded
        case failed
        case cancelled
        case autoExecuted // read tools that don't need confirmation
    }

    public var needsConfirmation: Bool {
        switch self {
        case .logFood, .logWater, .logSleep, .addReminder, .addCalendarEvent,
             .updateReminder, .updateCalendarEvent,
             .deleteReminder, .deleteCalendarEvent,
             .updateFoodLog, .deleteFoodLog,
             .createWidget, .updateWidget, .deleteWidget,
             .updateGoal, .setDateOfBirth, .setNutritionTargets,
             .setTrainingPlan, .markWorkoutDone:
            return true
        case .showMetricChart, .showComparisonChart, .renderCard,
             .listReminders, .listCalendarEvents, .getPredictions,
             .listFoodLog, .listWidgets, .updateNotes, .getSleepPattern,
             .getMetricHistory, .getSleepSessions,
             .rememberFact, .forgetFact, .updateProfile, .getProfile,
             .getTrainingPlan:
            return false
        }
    }

    /// Read-tools that surface structured data back to the LLM via
    /// functionResponse. ChatViewModel auto-runs these and dispatches a
    /// follow-up Gemini turn so the model can reason on the payload.
    /// Chart/card tools are included so Astra receives the series stats and
    /// follows every visual with a brief grounded analysis.
    public var producesPayload: Bool {
        switch self {
        case .listReminders, .listCalendarEvents, .getPredictions,
             .listFoodLog, .listWidgets, .updateNotes, .getSleepPattern,
             .getMetricHistory, .getSleepSessions,
             .showMetricChart, .showComparisonChart, .renderCard,
             .rememberFact, .forgetFact, .updateProfile, .getProfile,
             .getTrainingPlan:
            return true
        default: return false
        }
    }

    public var name: String {
        switch self {
        case .logFood: return "log_food"
        case .logWater: return "log_water"
        case .logSleep: return "log_sleep"
        case .addReminder: return "add_reminder"
        case .addCalendarEvent: return "add_calendar_event"
        case .showMetricChart: return "show_metric_chart"
        case .showComparisonChart: return "show_comparison_chart"
        case .renderCard: return "render_card"
        case .listReminders: return "list_reminders"
        case .listCalendarEvents: return "list_calendar_events"
        case .updateReminder: return "update_reminder"
        case .updateCalendarEvent: return "update_calendar_event"
        case .deleteReminder: return "delete_reminder"
        case .deleteCalendarEvent: return "delete_calendar_event"
        case .getPredictions: return "get_predictions"
        case .listFoodLog: return "list_food_log"
        case .updateFoodLog: return "update_food_log"
        case .deleteFoodLog: return "delete_food_log"
        case .createWidget: return "create_widget"
        case .listWidgets: return "list_widgets"
        case .updateWidget: return "update_widget"
        case .deleteWidget: return "delete_widget"
        case .updateNotes: return "update_notes"
        case .rememberFact: return "remember_fact"
        case .forgetFact: return "forget_fact"
        case .updateProfile: return "update_profile"
        case .getProfile: return "get_profile"
        case .getSleepPattern: return "get_sleep_pattern"
        case .getMetricHistory: return "get_metric_history"
        case .getSleepSessions: return "get_sleep_sessions"
        case .updateGoal: return "update_goal"
        case .setDateOfBirth: return "set_date_of_birth"
        case .setNutritionTargets: return "set_nutrition_targets"
        case .getTrainingPlan: return "get_training_plan"
        case .setTrainingPlan: return "set_training_plan"
        case .markWorkoutDone: return "mark_workout_done"
        }
    }

    /// Every tool name `fromFunctionCall` knows how to decode. Lets the
    /// stream layer (GatewayChatClient) tell "the model called a KNOWN tool
    /// but its args didn't parse" apart from "unrecognized tool name" when
    /// `fromFunctionCall` returns nil — the former should surface an honest,
    /// retryable message instead of silently vanishing. Kept in sync with the
    /// switch below by hand; there's no CaseIterable shortcut for an enum
    /// with associated values.
    public static let recognizedNames: Set<String> = [
        "log_food", "log_water", "log_sleep", "add_reminder", "add_calendar_event",
        "show_metric_chart", "show_comparison_chart", "render_card",
        "list_reminders", "list_calendar_events", "update_reminder", "update_calendar_event",
        "delete_reminder", "delete_calendar_event", "get_predictions",
        "list_food_log", "update_food_log", "delete_food_log",
        "create_widget", "list_widgets", "update_widget", "delete_widget",
        "update_notes", "remember_fact", "forget_fact", "update_profile", "get_profile",
        "get_sleep_pattern", "get_metric_history", "get_sleep_sessions",
        "update_goal", "set_date_of_birth", "set_nutrition_targets",
        "get_training_plan", "set_training_plan", "mark_workout_done"
    ]

    /// Decodes from Gemini's loose JSON args dict.
    public static func fromFunctionCall(name: String, args: [String: Any]) -> ToolCall? {
        switch name {
        case "log_food":
            guard let n = args["name"] as? String,
                  let cals = (args["calories"] as? Double) ?? doubleFrom(args["calories"]) else { return nil }
            let rawDaysAgo = Int(doubleFrom(args["days_ago"]) ?? 0)
            return .logFood(
                name: n,
                calories: cals,
                protein: doubleFrom(args["protein"]) ?? 0,
                carbs: doubleFrom(args["carbs"]) ?? 0,
                fat: doubleFrom(args["fat"]) ?? 0,
                serving: (args["serving"] as? String) ?? "",
                tags: (args["tags"] as? [String]) ?? [],
                highlights: (args["highlights"] as? [String]) ?? [],
                cautions: (args["cautions"] as? [String]) ?? [],
                // Default to estimate=true for safety. Only label-verified data
                // (user typed exact macros from a package label) should ever set false.
                isEstimate: (args["is_estimate"] as? Bool) ?? true,
                confidence: args["confidence"] as? String,
                daysAgo: max(0, min(rawDaysAgo, 7))
            )
        case "log_water":
            guard let ml = doubleFrom(args["amount_ml"]) else { return nil }
            let rawDaysAgo = Int(doubleFrom(args["days_ago"]) ?? 0)
            return .logWater(milliliters: ml, daysAgo: max(0, min(rawDaysAgo, 7)))
        case "log_sleep":
            // Same ISO8601 parsing convention as add_reminder's due_at below.
            // `end` omitted (or unparseable) defaults to now — the common
            // "slept from 1:30 to now" phrasing.
            guard let startStr = args["start"] as? String,
                  let start = parseISO8601(startStr) else { return nil }
            let end = (args["end"] as? String).flatMap { parseISO8601($0) } ?? Date()
            return .logSleep(start: start, end: end)
        case "add_reminder":
            guard let title = args["title"] as? String else { return nil }
            let due = (args["due_at"] as? String).flatMap { parseISO8601($0) }
            return .addReminder(title: title, dueAt: due, category: args["category"] as? String)
        case "add_calendar_event":
            guard let title = args["title"] as? String,
                  let startStr = args["starts_at"] as? String,
                  let endStr = args["ends_at"] as? String,
                  let start = parseISO8601(startStr),
                  let end = parseISO8601(endStr) else { return nil }
            return .addCalendarEvent(title: title, startsAt: start, endsAt: end, notes: args["notes"] as? String)
        case "show_metric_chart":
            guard let metric = args["metric"] as? String else { return nil }
            let days = Int(doubleFrom(args["days"]) ?? 7)
            return .showMetricChart(metric: metric, days: max(1, min(days, 365)))
        case "show_comparison_chart":
            guard let metric = args["metric"] as? String,
                  let pa = args["period_a"] as? String,
                  let pb = args["period_b"] as? String else { return nil }
            return .showComparisonChart(metric: metric, periodA: pa, periodB: pb, title: args["title"] as? String)
        case "render_card":
            guard let title = args["title"] as? String else { return nil }
            var stats: [Stat] = []
            if let arr = args["stats"] as? [[String: Any]] {
                stats = arr.compactMap { dict in
                    guard let l = dict["label"] as? String, let v = dict["value"] as? String else { return nil }
                    return Stat(label: l, value: v)
                }
            }
            return .renderCard(
                title: title,
                icon: (args["icon"] as? String) ?? "sparkles",
                color: (args["color"] as? String) ?? "accent",
                headline: args["headline"] as? String,
                bullets: (args["bullets"] as? [String]) ?? [],
                stats: stats
            )
        case "list_reminders":
            return .listReminders(filter: args["filter"] as? String)
        case "list_calendar_events":
            let days = Int(doubleFrom(args["days_ahead"]) ?? 14)
            return .listCalendarEvents(daysAhead: max(1, min(days, 30)))
        case "update_reminder":
            guard let id = args["id"] as? String else { return nil }
            let due = (args["due_at"] as? String).flatMap { parseISO8601($0) }
            return .updateReminder(id: id,
                                   title: args["title"] as? String,
                                   dueAt: due,
                                   notes: args["notes"] as? String)
        case "update_calendar_event":
            guard let id = args["id"] as? String else { return nil }
            let start = (args["starts_at"] as? String).flatMap { parseISO8601($0) }
            let end = (args["ends_at"] as? String).flatMap { parseISO8601($0) }
            return .updateCalendarEvent(id: id,
                                        title: args["title"] as? String,
                                        startsAt: start,
                                        endsAt: end,
                                        notes: args["notes"] as? String)
        case "delete_reminder":
            guard let id = args["id"] as? String else { return nil }
            return .deleteReminder(id: id, title: args["title"] as? String)
        case "delete_calendar_event":
            guard let id = args["id"] as? String else { return nil }
            return .deleteCalendarEvent(id: id, title: args["title"] as? String)
        case "get_predictions":
            return .getPredictions
        case "list_food_log":
            return .listFoodLog
        case "update_food_log":
            guard let id = args["id"] as? String else { return nil }
            return .updateFoodLog(
                id: id,
                name: args["name"] as? String,
                calories: doubleFrom(args["calories"]),
                protein: doubleFrom(args["protein"]),
                carbs: doubleFrom(args["carbs"]),
                fat: doubleFrom(args["fat"])
            )
        case "delete_food_log":
            guard let id = args["id"] as? String else { return nil }
            return .deleteFoodLog(id: id, name: args["name"] as? String)
        case "create_widget":
            guard let title = args["title"] as? String,
                  let icon = args["icon"] as? String,
                  let color = args["color"] as? String,
                  let layout = args["layout"] as? String else { return nil }
            let blocks: [WidgetBlock]? = (args["blocks"] as? [[String: Any]])?
                .compactMap { WidgetBlock.from(dict: $0) }
            return .createWidget(
                title: title,
                icon: icon,
                color: color,
                layout: layout,
                headline: args["headline"] as? String,
                body: args["body"] as? String,
                bullets: (args["bullets"] as? [String]) ?? [],
                metricRef: args["metric_ref"] as? String,
                goalValue: doubleFrom(args["goal_value"]),
                blocks: blocks?.isEmpty == true ? nil : blocks
            )
        case "list_widgets":
            return .listWidgets
        case "update_widget":
            guard let id = args["id"] as? String else { return nil }
            let blocks: [WidgetBlock]? = (args["blocks"] as? [[String: Any]])?
                .compactMap { WidgetBlock.from(dict: $0) }
            return .updateWidget(
                id: id,
                title: args["title"] as? String,
                icon: args["icon"] as? String,
                color: args["color"] as? String,
                layout: args["layout"] as? String,
                headline: args["headline"] as? String,
                body: args["body"] as? String,
                bullets: args["bullets"] as? [String],
                metricRef: args["metric_ref"] as? String,
                goalValue: doubleFrom(args["goal_value"]),
                blocks: blocks?.isEmpty == true ? nil : blocks
            )
        case "delete_widget":
            guard let id = args["id"] as? String else { return nil }
            return .deleteWidget(id: id, title: args["title"] as? String)
        case "update_notes":
            guard let notes = args["notes"] as? String else { return nil }
            return .updateNotes(notes: notes)
        case "remember_fact":
            guard let category = args["category"] as? String,
                  let text = args["text"] as? String else { return nil }
            return .rememberFact(category: category, text: text)
        case "forget_fact":
            guard let query = args["query"] as? String else { return nil }
            return .forgetFact(query: query)
        case "update_profile":
            guard let section = args["section"] as? String,
                  let content = args["content"] as? String else { return nil }
            return .updateProfile(section: section, content: content)
        case "get_profile":
            return .getProfile
        case "get_sleep_pattern":
            return .getSleepPattern
        case "get_metric_history":
            guard let metric = args["metric"] as? String else { return nil }
            let days = Int(doubleFrom(args["days"]) ?? 30)
            return .getMetricHistory(metric: metric, days: max(1, min(days, 90)))
        case "get_sleep_sessions":
            let nights = Int(doubleFrom(args["nights"]) ?? 7)
            return .getSleepSessions(nights: max(1, min(nights, 14)))
        case "update_goal":
            guard let metric = args["metric"] as? String,
                  let value = doubleFrom(args["value"]) else { return nil }
            return .updateGoal(metric: metric, value: value)
        case "set_date_of_birth":
            guard let dateStr = args["date"] as? String,
                  let date = parseDateOnly(dateStr) else { return nil }
            return .setDateOfBirth(date: date)
        case "set_nutrition_targets":
            let proteinG = doubleFrom(args["protein_g"])
            let kcal = doubleFrom(args["kcal"])
            guard proteinG != nil || kcal != nil else { return nil }
            return .setNutritionTargets(proteinG: proteinG, kcal: kcal)
        case "get_training_plan":
            return .getTrainingPlan
        case "set_training_plan":
            guard let weekStartStr = args["week_start"] as? String,
                  let weekStart = parseDateOnly(weekStartStr),
                  let daysArr = args["days"] as? [[String: Any]] else { return nil }
            let days: [PlannedDayArg] = daysArr.compactMap { d in
                guard let dateStr = d["date"] as? String,
                      let date = parseDateOnly(dateStr),
                      let title = d["title"] as? String,
                      let kind = d["kind"] as? String else { return nil }
                let detail = (d["detail"] as? String) ?? ""
                let duration = Int(doubleFrom(d["duration_min"]) ?? 45)
                return PlannedDayArg(date: date, title: title, detail: detail, kind: kind, durationMin: duration)
            }
            guard !days.isEmpty else { return nil }
            return .setTrainingPlan(weekStart: weekStart, days: days)
        case "mark_workout_done":
            guard let dateStr = args["date"] as? String,
                  let date = parseDateOnly(dateStr) else { return nil }
            return .markWorkoutDone(date: date)
        default:
            return nil
        }
    }

    private static func doubleFrom(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func parseISO8601(_ s: String) -> Date? {
        // Strict, timezone-QUALIFIED ISO8601 first — when the model does
        // supply an offset it must always win over a local-time guess.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        // FALLBACK: Gemini sometimes emits a timezone-NAIVE datetime (e.g.
        // "2026-07-21T13:15:00" for "1:15pm") even when asked for an offset.
        // `ISO8601DateFormatter` rejects those outright, which used to make
        // `fromFunctionCall` return nil and the whole turn vanish — an
        // invisible bubble with tokens spent and nothing shown (the log_sleep
        // bug). Interpret a naive datetime as device-local time instead of
        // discarding it. Covers add_reminder/add_calendar_event the same way.
        let naive = DateFormatter()
        naive.calendar = Calendar(identifier: .gregorian)
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = .current
        naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = naive.date(from: s) { return d }
        naive.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return naive.date(from: s)
    }

    /// Parses a plain "YYYY-MM-DD" date (no time component) for
    /// set_date_of_birth — a birthday has no meaningful time-of-day, and
    /// requiring full ISO8601 datetime from the model would be needless
    /// friction for a value it should produce from "March 4th 1998" style input.
    private static func parseDateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    /// Serializes the tool args back to the dict shape Gemini originally sent.
    /// Used when the app needs to round-trip the original `functionCall` into a
    /// follow-up request so the model can attach a `functionResponse` to it.
    public var asFunctionCallPayload: [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        switch self {
        case .logFood(let n, let cals, let p, let c, let f, let s, let tags, let hi, let cau, let est, let conf, let daysAgo):
            var d: [String: Any] = ["name": n, "calories": cals, "protein": p, "carbs": c, "fat": f,
                                     "serving": s, "tags": tags, "highlights": hi, "cautions": cau,
                                     "is_estimate": est, "days_ago": daysAgo]
            if let conf { d["confidence"] = conf }
            return d
        case .logWater(let ml, let daysAgo):
            return ["amount_ml": ml, "days_ago": daysAgo]
        case .logSleep(let start, let end):
            return ["start": iso.string(from: start), "end": iso.string(from: end)]
        case .addReminder(let title, let due, let cat):
            var d: [String: Any] = ["title": title]
            if let due { d["due_at"] = iso.string(from: due) }
            if let cat { d["category"] = cat }
            return d
        case .addCalendarEvent(let title, let start, let end, let notes):
            var d: [String: Any] = [
                "title": title,
                "starts_at": iso.string(from: start),
                "ends_at": iso.string(from: end)
            ]
            if let notes { d["notes"] = notes }
            return d
        case .showMetricChart(let m, let days):
            return ["metric": m, "days": days]
        case .showComparisonChart(let m, let a, let b, let t):
            var d: [String: Any] = ["metric": m, "period_a": a, "period_b": b]
            if let t { d["title"] = t }
            return d
        case .renderCard(let title, let icon, let color, let headline, let bullets, let stats):
            var d: [String: Any] = ["title": title, "icon": icon, "color": color, "bullets": bullets]
            if let headline { d["headline"] = headline }
            if !stats.isEmpty {
                d["stats"] = stats.map { ["label": $0.label, "value": $0.value] }
            }
            return d
        case .listReminders(let filter):
            var d: [String: Any] = [:]
            if let filter { d["filter"] = filter }
            return d
        case .listCalendarEvents(let days):
            return ["days_ahead": days]
        case .updateReminder(let id, let title, let due, let notes):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            if let due { d["due_at"] = iso.string(from: due) }
            if let notes { d["notes"] = notes }
            return d
        case .updateCalendarEvent(let id, let title, let start, let end, let notes):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            if let start { d["starts_at"] = iso.string(from: start) }
            if let end { d["ends_at"] = iso.string(from: end) }
            if let notes { d["notes"] = notes }
            return d
        case .deleteReminder(let id, let title):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            return d
        case .deleteCalendarEvent(let id, let title):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            return d
        case .getPredictions:
            return [:]
        case .listFoodLog:
            return [:]
        case .updateFoodLog(let id, let name, let cal, let p, let c, let f):
            var d: [String: Any] = ["id": id]
            if let name { d["name"] = name }
            if let cal { d["calories"] = cal }
            if let p { d["protein"] = p }
            if let c { d["carbs"] = c }
            if let f { d["fat"] = f }
            return d
        case .deleteFoodLog(let id, let name):
            var d: [String: Any] = ["id": id]
            if let name { d["name"] = name }
            return d
        case .createWidget(let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            var d: [String: Any] = [
                "title": title, "icon": icon, "color": color, "layout": layout,
                "bullets": bullets
            ]
            if let headline { d["headline"] = headline }
            if let body { d["body"] = body }
            if let metricRef { d["metric_ref"] = metricRef }
            if let goalValue { d["goal_value"] = goalValue }
            if let blocks { d["blocks"] = blocks.map { $0.asDict } }
            return d
        case .listWidgets:
            return [:]
        case .updateWidget(let id, let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            if let icon { d["icon"] = icon }
            if let color { d["color"] = color }
            if let layout { d["layout"] = layout }
            if let headline { d["headline"] = headline }
            if let body { d["body"] = body }
            if let bullets { d["bullets"] = bullets }
            if let metricRef { d["metric_ref"] = metricRef }
            if let goalValue { d["goal_value"] = goalValue }
            if let blocks { d["blocks"] = blocks.map { $0.asDict } }
            return d
        case .deleteWidget(let id, let title):
            var d: [String: Any] = ["id": id]
            if let title { d["title"] = title }
            return d
        case .updateNotes(let notes):
            return ["notes": notes]
        case .rememberFact(let category, let text):
            return ["category": category, "text": text]
        case .forgetFact(let query):
            return ["query": query]
        case .updateProfile(let section, let content):
            return ["section": section, "content": content]
        case .getProfile:
            return [:]
        case .getSleepPattern:
            return [:]
        case .getMetricHistory(let metric, let days):
            return ["metric": metric, "days": days]
        case .getSleepSessions(let nights):
            return ["nights": nights]
        case .updateGoal(let metric, let value):
            return ["metric": metric, "value": value]
        case .setDateOfBirth(let date):
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return ["date": f.string(from: date)]
        case .setNutritionTargets(let proteinG, let kcal):
            var d: [String: Any] = [:]
            if let proteinG { d["protein_g"] = proteinG }
            if let kcal { d["kcal"] = kcal }
            return d
        case .getTrainingPlan:
            return [:]
        case .setTrainingPlan(let weekStart, let days):
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return [
                "week_start": f.string(from: weekStart),
                "days": days.map { d in
                    ["date": f.string(from: d.date), "title": d.title, "detail": d.detail,
                     "kind": d.kind, "duration_min": d.durationMin]
                }
            ]
        case .markWorkoutDone(let date):
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return ["date": f.string(from: date)]
        }
    }
}

/// Streaming chunk type — text deltas and tool calls are interleaved.
/// A final `.usage` chunk lands at the end of every Vertex stream once
/// `usageMetadata` is available.
///
/// `thoughtSignature` (Gemini 3.x's part-level sibling of `functionCall`,
/// required to round-trip on the followup turn) rides bundled ON the
/// `.toolCall` case itself rather than as its own separately-interleaved
/// chunk. Bundling at the source is what lets `ChatViewModel` stamp each
/// call's signature onto that exact call's message — with a standalone
/// `.thoughtSignature` chunk, a turn with two functionCall parts streamed
/// `sig1, call1, sig2, call2` and there was no way to tell which call a
/// given signature belonged to except "whatever arrived most recently",
/// so `sig2` clobbered `sig1` before `call2` ever got its own message.
public enum ChatChunk {
    case text(String)
    case toolCall(ToolCall, thoughtSignature: String?)
    case usage(TokenUsage)
}
