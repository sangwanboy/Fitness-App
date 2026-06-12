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
        confidence: String?  // "low" | "medium" | "high" — nil for verified label data
    )
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

    // Returns the user's full sleep pattern + last 5 sessions in structured
    // form. Auto-executes — Astra calls it whenever the user asks anything
    // sleep-related so the answer can cite real per-user numbers instead of
    // generic guidance.
    case getSleepPattern

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
        case .logFood, .addReminder, .addCalendarEvent,
             .updateReminder, .updateCalendarEvent,
             .deleteReminder, .deleteCalendarEvent,
             .updateFoodLog, .deleteFoodLog,
             .createWidget, .updateWidget, .deleteWidget:
            return true
        case .showMetricChart, .showComparisonChart, .renderCard,
             .listReminders, .listCalendarEvents, .getPredictions,
             .listFoodLog, .listWidgets, .updateNotes, .getSleepPattern:
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
             .showMetricChart, .showComparisonChart, .renderCard:
            return true
        default: return false
        }
    }

    public var name: String {
        switch self {
        case .logFood: return "log_food"
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
        case .getSleepPattern: return "get_sleep_pattern"
        }
    }

    /// Decodes from Gemini's loose JSON args dict.
    public static func fromFunctionCall(name: String, args: [String: Any]) -> ToolCall? {
        switch name {
        case "log_food":
            guard let n = args["name"] as? String,
                  let cals = (args["calories"] as? Double) ?? doubleFrom(args["calories"]) else { return nil }
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
                confidence: args["confidence"] as? String
            )
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
        case "get_sleep_pattern":
            return .getSleepPattern
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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Serializes the tool args back to the dict shape Gemini originally sent.
    /// Used when the app needs to round-trip the original `functionCall` into a
    /// follow-up request so the model can attach a `functionResponse` to it.
    public var asFunctionCallPayload: [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        switch self {
        case .logFood(let n, let cals, let p, let c, let f, let s, let tags, let hi, let cau, let est, let conf):
            var d: [String: Any] = ["name": n, "calories": cals, "protein": p, "carbs": c, "fat": f,
                                     "serving": s, "tags": tags, "highlights": hi, "cautions": cau,
                                     "is_estimate": est]
            if let conf { d["confidence"] = conf }
            return d
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
        case .getSleepPattern:
            return [:]
        }
    }
}

/// Streaming chunk type — text deltas and tool calls are interleaved.
/// A final `.usage` chunk lands at the end of every Vertex stream once
/// `usageMetadata` is available. A `.thoughtSignature` chunk lands
/// adjacent to a tool call when Gemini 3.x attaches a signature blob to
/// that part (required for the followup turn).
public enum ChatChunk {
    case text(String)
    case toolCall(ToolCall)
    case usage(TokenUsage)
    case thoughtSignature(String)
}
