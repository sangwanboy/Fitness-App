import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    @Published public var isGenerating: Bool = false
    @Published public var currentStreamingText: String = ""
    
    /// The canned opening line a fresh conversation starts with. Kept as a
    /// single source so `init`, `clearChat`, and `startNewChat` stay in sync.
    private static let greetingText =
        "Hey! I'm Astra, your AI health coach. I've synced with your HealthKit stats for today. How can I help you reach your goals?"

    public init() {
        // Resume the live conversation if one was interrupted (force-quit,
        // process termination). It stays LIVE — not an archived replay — so
        // the user picks up exactly where they left off. Fresh installs and
        // post-new-chat launches fall back to the greeting.
        let restored = ChatHistoryStore.shared.loadLive()
        if restored.isEmpty {
            messages.append(ChatMessage(role: .model, text: Self.greetingText))
        } else {
            messages = restored.map { $0.toChatMessage() }
        }
    }

    /// Snapshot the live conversation into the persistent live slot. Called
    /// when a turn settles (message append, stream end, tool status change) —
    /// NEVER per streaming delta. No-op while replaying an archived session,
    /// so a read-only replay can't overwrite the slot.
    private func persistLiveSnapshot() {
        guard !isViewingArchivedSession else { return }
        ChatHistoryStore.shared.saveLive(messages: messages)
    }

    /// Minimum gap between publishing accumulated streaming text to a message
    /// bubble. Deltas keep landing in `currentStreamingText` on every chunk, but
    /// we only mutate `messages[idx].text` (which forces a full markdown
    /// re-parse + re-render of StructuredMarkdownText) at most ~20×/sec. This
    /// turns an O(n²) re-parse-per-delta into a bounded number of re-parses.
    private static let streamFlushInterval: TimeInterval = 0.05

    /// Publish `currentStreamingText` into `messages[idx].text`, but only if
    /// enough time has elapsed since `lastFlush` (or when `force` is set — used
    /// for the final value on stream end / tool-call return / error paths so
    /// the reply is never left truncated). Returns the (possibly updated)
    /// `lastFlush` timestamp for the caller to thread through the loop.
    private func flushStreamingText(into idx: Int,
                                    lastFlush: Date,
                                    force: Bool) -> Date {
        guard messages.indices.contains(idx) else { return lastFlush }
        let now = Date()
        if force || now.timeIntervalSince(lastFlush) >= Self.streamFlushInterval {
            messages[idx].text = currentStreamingText
            return now
        }
        return lastFlush
    }
    
    /// Send a prompt queued from elsewhere (currently: Predictions card action
    /// chips). Skips the "two-character minimum" guard since these are always
    /// well-formed sentences from the AI. No-op if a stream is already running.
    public func sendPrefilledPrompt(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }
        await sendMessage(trimmed)
    }

    public func sendMessage(_ text: String, imageData: Data? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Block trivially-short text-only messages (e.g. an accidental "?")
        // that produce a one-character bubble and a wasted Gemini call.
        // Images are always allowed through (caption optional).
        if imageData == nil {
            guard trimmed.count >= 2 else { return }
        } else {
            guard !trimmed.isEmpty || true else { return } // image-only OK
        }

        // Add User Message (text + optional image). Sending into a loaded past
        // session turns it back into a live conversation, so it becomes
        // archivable again on the next new-chat / leave.
        isViewingArchivedSession = false
        let userMessage = ChatMessage(role: .user, text: trimmed, imageData: imageData)
        messages.append(userMessage)
        persistLiveSnapshot()

        isGenerating = true
        currentStreamingText = ""
        // Always reset state — even when the loop is broken by a tool call or thrown error.
        // Earlier versions used a bare `return` inside the switch which leaked isGenerating=true
        // and left the typing dots spinning forever.
        defer {
            isGenerating = false
            currentStreamingText = ""
            persistLiveSnapshot()
        }

        let systemInstruction = await buildSystemInstruction()
        // Use a copy of messages excluding the last user message as history
        let history = Array(messages.dropLast())

        // Default prompt when user sends only an image
        let prompt = trimmed.isEmpty ? "What is this? Give me full details." : trimmed

        do {
            let stream = await VertexGeminiClient.shared.streamGenerateContent(
                prompt: prompt,
                history: history,
                systemInstruction: systemInstruction,
                imageData: imageData,
                imageMimeType: "image/jpeg",
                model: "gemini-3.5-flash"
            )

            // Placeholder for the model's reply that we mutate as chunks arrive
            let modelId = UUID()
            messages.append(ChatMessage(id: modelId, role: .model, text: ""))

            // Throttle text publishes to ~20×/sec; deltas always accumulate in
            // currentStreamingText, but we only re-render at most every 50ms.
            var lastFlush = Date.distantPast

            for try await chunk in stream {
                guard let idx = messages.firstIndex(where: { $0.id == modelId }) else { break }
                switch chunk {
                case .text(let delta):
                    currentStreamingText += delta
                    lastFlush = flushStreamingText(into: idx, lastFlush: lastFlush, force: false)
                case .toolCall(let call):
                    // Force the partial text out before the tool takes over.
                    _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
                    messages[idx].toolCall = call
                    messages[idx].toolStatus = call.needsConfirmation ? .pending : .autoExecuted
                    // Stop streaming the current model turn; the tool now drives the flow.
                    // List/read tools auto-execute and trigger their own follow-up so the
                    // model can speak about the results.
                    if call.producesPayload {
                        await autoExecuteReadTool(messageId: modelId)
                    }
                    return
                case .usage(let usage):
                    messages[idx].tokenUsage = usage
                case .thoughtSignature(let sig):
                    messages[idx].thoughtSignature = sig
                }
            }
            // Stream ended cleanly — make sure the final accumulated text lands.
            if let idx = messages.firstIndex(where: { $0.id == modelId }) {
                _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
            }
        } catch {
            print("Chat streaming error: \(error.localizedDescription)")
            // Flush whatever text streamed before the error so a partial reply
            // isn't truncated when the error bubble is appended below. Only act
            // when there's real partial text, so we never blank out a bubble
            // (e.g. the placeholder, or an earlier message) on a pre-stream error.
            if !currentStreamingText.isEmpty,
               let idx = messages.lastIndex(where: { $0.role == .model && $0.toolCall == nil }) {
                messages[idx].text = currentStreamingText
            }
            messages.append(ChatMessage(
                role: .model,
                text: "Sorry, I ran into an issue connecting to my processors. Please check your network connection and try again.",
                isError: true
            ))
        }
    }

    /// Runs a read-only tool (list_reminders, list_calendar_events) immediately,
    /// stashes the JSON payload on the message, and dispatches a follow-up
    /// Gemini turn so the model can reason on the items it just received.
    private func autoExecuteReadTool(messageId: UUID) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let call = messages[idx].toolCall else { return }
        let payload = await executeReadTool(call)
        messages[idx].toolStatus = .done
        if let payload, let json = encodeJSON(payload) {
            messages[idx].toolResultJSON = json
        }
        persistLiveSnapshot()
        await sendFollowup()
    }

    private func executeReadTool(_ call: ToolCall) async -> [String: Any]? {
        switch call {
        case .listReminders(let filter):
            let all = await EventKitManager.shared.listAppReminders()
            let filtered: [[String: Any]] = {
                switch (filter ?? "active").lowercased() {
                case "completed": return all.filter { ($0["completed"] as? Bool) == true }
                case "all":       return all
                default:          return all.filter { ($0["completed"] as? Bool) != true } // "active"
                }
            }()
            return ["items": filtered, "count": filtered.count]
        case .listCalendarEvents(let days):
            let items = EventKitManager.shared.listAppEvents(daysAhead: days)
            return ["items": items, "count": items.count]
        case .getPredictions:
            return await Self.predictionsPayload()
        case .listFoodLog:
            let items = await HealthKitManager.shared.listAppFoodToday()
            return ["items": items, "count": items.count]
        case .updateNotes(let notes):
            UserDefaults.standard.set(notes, forKey: "astra_notes")
            return ["success": true, "saved_length": notes.count]
        case .getSleepPattern:
            return Self.sleepPatternPayload()
        case .listWidgets:
            let widgets = AstraWidgetStore.shared.widgets
            let items: [[String: Any]] = widgets.map { w in
                var d: [String: Any] = [
                    "id": w.id.uuidString,
                    "title": w.title,
                    "icon": w.icon,
                    "color": w.colorName,
                    "layout": w.layout.rawValue,
                    "bullets": w.bullets,
                    "created_at": ISO8601DateFormatter().string(from: w.createdAt)
                ]
                if let h = w.headline { d["headline"] = h }
                if let b = w.body { d["body"] = b }
                if let m = w.metricRef { d["metric_ref"] = m }
                if let g = w.goalValue { d["goal_value"] = g }
                if let blocks = w.blocks { d["blocks"] = blocks.map { $0.asDict } }
                return d
            }
            return ["items": items,
                    "count": items.count,
                    "remaining_slots": max(0, AstraWidgetStore.maxWidgets - widgets.count)]
        case .showMetricChart(let metric, let days):
            guard let type = Self.chartMetricType(from: metric),
                  let history = HealthKitManager.shared.metricSummaries[type]?.history,
                  !history.isEmpty else {
                return ["available": false, "metric": metric,
                        "reason": "No HealthKit history for this metric."]
            }
            // Clip to the requested window — same slice the rendered card shows.
            let cal = Calendar.current
            let cutoff = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let points = Array(history.filter { $0.date >= cutoff }.suffix(days).map(\.value))
            guard let first = points.first, let last = points.last else {
                return ["available": false, "metric": metric, "days": days,
                        "reason": "No samples in the requested window."]
            }
            return ["available": true,
                    "metric": metric,
                    "unit": type.unit,
                    "days": days,
                    "points": points.map { Self.round1($0) },
                    "avg": Self.round1(points.reduce(0, +) / Double(points.count)),
                    "min": Self.round1(points.min() ?? 0),
                    "max": Self.round1(points.max() ?? 0),
                    "latest": Self.round1(last),
                    "change_pct_first_to_last": first == 0 ? 0 : Self.round1((last - first) / first * 100)]
        case .showComparisonChart(let metric, let periodA, let periodB, _):
            guard let type = Self.chartMetricType(from: metric),
                  let history = HealthKitManager.shared.metricSummaries[type]?.history,
                  !history.isEmpty else {
                return ["available": false, "metric": metric,
                        "reason": "No HealthKit history for this metric."]
            }
            func stats(for period: String) -> [String: Any] {
                let (start, end) = Self.chartPeriodRange(period)
                let vals = history.filter { $0.date >= start && $0.date <= end }.map(\.value)
                guard !vals.isEmpty else {
                    return ["period": period, "available": false]
                }
                return ["period": period,
                        "available": true,
                        "points": vals.count,
                        "avg": Self.round1(vals.reduce(0, +) / Double(vals.count)),
                        "min": Self.round1(vals.min() ?? 0),
                        "max": Self.round1(vals.max() ?? 0)]
            }
            let a = stats(for: periodA)
            let b = stats(for: periodB)
            var d: [String: Any] = ["available": true,
                                    "metric": metric,
                                    "unit": type.unit,
                                    "period_a": a,
                                    "period_b": b]
            if let aAvg = a["avg"] as? Double, let bAvg = b["avg"] as? Double, bAvg != 0 {
                d["delta_pct"] = Self.round1((aAvg - bAvg) / bAvg * 100)
            }
            return d
        case .renderCard(let title, _, _, _, _, _):
            return ["rendered": true, "title": title]
        default:
            return nil
        }
    }

    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }

    /// Mirror of the metric-name mapping the chart ToolCards use, so the stats
    /// fed back to Gemini describe exactly the series the user is looking at.
    private static func chartMetricType(from raw: String) -> HealthMetricType? {
        switch raw.lowercased() {
        case "steps": return .steps
        case "heart_rate", "heart": return .heartRate
        case "sleep": return .sleep
        case "active_energy", "calories": return .activeEnergy
        case "distance": return .distance
        case "hrv": return .hrv
        case "hydration", "water": return .hydration
        default: return nil
        }
    }

    /// Mirror of ComparisonChartToolCard's period resolver (start...end, both
    /// startOfDay-inclusive) so payload stats match the rendered bars.
    private static func chartPeriodRange(_ period: String) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func days(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: today) ?? today }
        switch period.lowercased() {
        case "today":             return (today, today)
        case "yesterday":         return (days(1), days(1))
        case "this_week":         return (days(6), today)
        case "last_week":         return (days(13), days(7))
        case "last_7_days":       return (days(6), today)
        case "previous_7_days":   return (days(13), days(7))
        case "this_month":        return (days(29), today)
        case "last_month":        return (days(59), days(30))
        default:                  return (days(6), today)
        }
    }

    /// Inline text version of the sleep pattern for the system prompt. Same
    /// data as `sleepPatternPayload` but compressed into a few lines so the
    /// per-turn prompt doesn't bloat. Astra still calls `get_sleep_pattern`
    /// when it needs the structured per-night details.
    fileprivate static func sleepPatternInlineBlock() -> String {
        let sessions = SleepSessionStore.shared.sessions
        let pattern = SleepPatternAnalyzer.compute(from: sessions)
        let detector = SleepFocusDetector.shared
        guard pattern.hasEnoughHistory else {
            let focusLine = detector.sleepFocusLikely
                ? "Sleep Focus is currently active on iOS — user is likely in bed."
                : detector.isWithinBedtimeWindow
                    ? "Within typical bedtime window."
                    : ""
            return [
                "Sessions tracked on-device: \(sessions.count). Need ≥3 nights to surface a stable pattern — encourage the user to tap 'Track tonight' on Home.",
                focusLine
            ].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        var lines: [String] = []
        lines.append("• \(pattern.sessionCount) tracked nights. \(pattern.summary)")
        lines.append("• Restlessness baseline: \(pattern.medianRestlessness)% (lower is better).")
        if pattern.medianSnoreEpisodes > 0 {
            lines.append("• Snore baseline: \(pattern.medianSnoreEpisodes) episodes / \(pattern.medianSnoreMinutes) min per night.")
        } else {
            lines.append("• Snore baseline: typically quiet (no episodes).")
        }
        lines.append("• Bedtime consistency: \(pattern.consistencyScore)/100 (higher = more regular).")
        if let w = pattern.weekendDelayMinutes, abs(w) >= 15 {
            lines.append(w > 0 ? "• Goes to bed ~\(w) min later on weekends." : "• Goes to bed ~\(-w) min earlier on weekends.")
        }
        if let t = pattern.weeklyTrendMinutes {
            lines.append(t >= 0 ? "• Sleep duration trending UP \(t) min vs prior week." : "• Sleep duration trending DOWN \(-t) min vs prior week.")
        }
        if detector.sleepFocusLikely {
            lines.append("• iOS Sleep Focus is active right now — user is likely in bed.")
        } else if detector.isWithinBedtimeWindow {
            lines.append("• Currently inside the user's typical bedtime window.")
        }
        return lines.joined(separator: "\n")
    }

    /// Structured per-user sleep summary for `get_sleep_pattern`. Pattern
    /// from the analyzer + the last 5 sessions with motion / snore detail
    /// so Astra can reason on concrete nights, not just aggregates.
    private static func sleepPatternPayload() -> [String: Any] {
        let sessions = SleepSessionStore.shared.sessions
        let pattern = SleepPatternAnalyzer.compute(from: sessions)
        guard pattern.hasEnoughHistory else {
            return [
                "available": false,
                "reason": "User has \(sessions.count) tracked night(s). Need ≥3 before a stable pattern emerges. Encourage them to use the Home > Sleep Tracker card before bed.",
                "session_count": sessions.count
            ]
        }
        let recent: [[String: Any]] = sessions.prefix(5).map { s in
            [
                "id": s.id.uuidString,
                "started_at": ISO8601DateFormatter().string(from: s.startedAt),
                "ended_at": ISO8601DateFormatter().string(from: s.endedAt),
                "onset_at": ISO8601DateFormatter().string(from: s.onsetAt),
                "duration_minutes": Int(s.totalDurationSeconds / 60),
                "in_bed_minutes": Int(s.inBedSeconds / 60),
                "onset_latency_minutes": Int(s.onsetLatencySeconds / 60),
                "restlessness_score": s.restlessnessScore,
                "snore_episodes": s.snoreEpisodes.count,
                "snore_total_minutes": Int(s.totalSnoreSeconds / 60),
                "stages": [
                    "deep_minutes":  Int(s.stageBreakdown.deep  / 60),
                    "light_minutes": Int(s.stageBreakdown.light / 60),
                    "awake_minutes": Int(s.stageBreakdown.awake / 60)
                ]
            ]
        }
        var d: [String: Any] = [
            "available": true,
            "session_count": pattern.sessionCount,
            "typical_bedtime":   pattern.typicalBedtimeHour.map { "\($0):\(String(format: "%02d", pattern.typicalBedtimeMinute ?? 0))" } ?? "—",
            "typical_wake_time": pattern.typicalWakeHour.map    { "\($0):\(String(format: "%02d", pattern.typicalWakeMinute    ?? 0))" } ?? "—",
            "median_duration_minutes":  pattern.medianDurationMinutes,
            "best_duration_minutes":    pattern.bestDurationMinutes,
            "median_restlessness":      pattern.medianRestlessness,
            "median_snore_episodes":    pattern.medianSnoreEpisodes,
            "median_snore_minutes":     pattern.medianSnoreMinutes,
            "consistency_score":        pattern.consistencyScore,
            "recent_durations_minutes": pattern.recentDurations,
            "recent_sessions":          recent
        ]
        if let w = pattern.weekendDelayMinutes { d["weekend_delay_minutes"] = w }
        if let t = pattern.weeklyTrendMinutes  { d["weekly_trend_minutes"]  = t }
        let detector = SleepFocusDetector.shared
        d["focus_state"] = [
            "is_in_focus":              detector.isInFocus as Any,
            "is_within_bedtime_window": detector.isWithinBedtimeWindow,
            "sleep_focus_likely":       detector.sleepFocusLikely
        ]
        return d
    }

    /// Serialize the latest `HealthKitManager.predictions` snapshot into a
    /// dict shape Gemini can consume via functionResponse. Returns either
    /// the structured snapshot or `{ "available": false, "reason": ... }`
    /// when the user is still inside the baseline window.
    private static func predictionsPayload() async -> [String: Any] {
        let hk = HealthKitManager.shared
        // Don't trigger a refresh here — the caller's buildSystemInstruction
        // already runs refreshIfStale, and stacking refetches would double the
        // HK round-trip latency for a single coach turn.
        guard let predictions = hk.predictions else {
            return [
                "available": false,
                "reason": "Snapshot not yet computed. Open the Home tab to seed it, then try again."
            ]
        }
        if let needed = predictions.insufficientHistoryDays, needed > 0 {
            return [
                "available": false,
                "reason": "Building baseline — \(needed) more day(s) of step history needed before predictions unlock."
            ]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(predictions),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return ["available": false, "reason": "Could not serialize prediction snapshot."]
    }

    /// Build the NUTRITION TODAY section for the system prompt. Lists every
    /// food item logged today (name + kcal + time) so Astra can answer
    /// "what did I log today?" / "did I log my wrap?" accurately. When
    /// nothing's been logged, says so explicitly so the model can't claim
    /// to "see" food that isn't there.
    fileprivate static func nutritionBlock(calories: Double,
                                           protein: Double,
                                           log: [FoodLogEntry],
                                           goals: MacroGoals) -> String {
        let goalsLine = "- Daily goals: \(Int(goals.calories)) kcal · \(Int(goals.protein))g protein · \(Int(goals.carbs))g carbs · \(Int(goals.fat))g fat — coach intake against these."
        if log.isEmpty && calories <= 0 {
            return """
            NUTRITION TODAY (from HealthKit dietary samples)
            \(goalsLine)
            - No meals logged yet today. If the user mentions a meal, do NOT claim to see it — confirm it isn't logged and offer to log it via the log_food tool.
            """
        }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let items: String = log
            .map { entry in
                let timeStr = f.string(from: entry.loggedAt)
                let kcalStr = String(format: "%.0f", entry.calories)
                let pStr = entry.protein > 0 ? " · \(String(format: "%.0f", entry.protein))g P" : ""
                return "  - \(entry.name) at \(timeStr) — \(kcalStr) kcal\(pStr)"
            }
            .joined(separator: "\n")
        let header = "NUTRITION TODAY (from HealthKit dietary samples — these are real entries already saved)"
        let totals = "- Total: \(Int(calories.rounded())) kcal · \(String(format: "%.0f", protein)) g protein"
        return items.isEmpty
            ? "\(header)\n\(totals)\n\(goalsLine)"
            : "\(header)\n\(totals)\n\(goalsLine)\n- Logged items:\n\(items)"
    }

    /// Full structured breakdown of the prediction snapshot for the system
    /// prompt. Mirrors what the user sees on the Predictions card so the
    /// model never has to call `get_predictions` for routine follow-ups.
    /// Skips AI-generated narrative fields (daily insight, action chip text,
    /// anomaly interpretation) — those are downstream products of the model
    /// itself, re-injecting them would be recursion.
    fileprivate static func predictionsFullBlock(_ p: Predictions?) -> String {
        guard let p else { return "Snapshot not yet computed." }
        if let n = p.insufficientHistoryDays, n > 0 {
            return "Building baseline — \(n) more day(s) of step history needed before predictions unlock."
        }
        var lines: [String] = []

        // Health Meter (most important — shows first)
        if let m = p.healthMeter {
            lines.append("• Health Meter: \(m.score)/100 (\(m.label.headline), \(m.confidence.rawValue) confidence)")
            lines.append("    Activity:    \(m.activityScore)/30")
            let nutritionNote: String
            if !m.usedNutrition {
                nutritionNote = "   (no meals logged — neutral estimate)"
            } else if !m.mealsLoggedToday {
                nutritionNote = "   (from last 7 days — NO meals logged TODAY; never claim the user ate or logged food today)"
            } else {
                nutritionNote = ""
            }
            lines.append("    Nutrition:   \(m.nutritionScore)/30\(nutritionNote)")
            let bmiNote = m.usedBMI ? "" : "   (no height/weight — neutral estimate)"
            lines.append("    Body comp:   \(m.bodyScore)/18\(bmiNote)")
            lines.append("    Vitals:      \(m.vitalsScore)/22")
            for b in m.explanation.bullets {
                lines.append("    – \(b)")
            }
        }

        // Recovery
        if let r = p.recovery {
            let watchTag = (r.usedHRV || r.usedRHR) ? "" : " — estimated from sleep + load (no Watch HRV/RHR)"
            lines.append("• Recovery: \(r.score)/100 (\(r.label.headline), \(r.confidence.rawValue) confidence)\(watchTag)")
            for b in r.explanation.bullets {
                lines.append("    – \(b)")
            }
        }

        // Next workout
        if let n = p.nextWorkout {
            let cat = n.isCategoryFallback ? "workout (time-only pattern; activity varies)" : n.category.displayName
            lines.append("• Next likely workout: \(cat), \(n.weekdayLabel) \(n.startHour):00–\(n.endHour):00 — support \(Int(n.support * 100))%, \(n.confidence.rawValue) confidence")
        }

        // Trajectories (one bullet per metric)
        for t in p.trajectories {
            let cur = Int(t.currentValue.rounded())
            let proj = Int(t.projectedEOD.rounded())
            let base = Int(t.baselineEOD.rounded())
            lines.append("• \(t.metric.displayName) trajectory: now \(cur) \(t.metric.unit), projected EOD \(proj) (avg \(base)), pace \(String(format: "%.2f", t.pace))× — \(t.status.headline)")
        }

        // Sedentary
        if let s = p.sedentary {
            let lastActive: String = {
                if let h = s.lastActiveHour { return ", last 250+ step hour was \(h):00" }
                return ""
            }()
            lines.append("• Sedentary: \(s.quietHours)h consecutive quiet (severity \(s.severity.rawValue))\(lastActive). Day total \(s.dayTotalSoFar) vs 14-day baseline \(s.baselineDayTotal).")
        }

        // Anomalies (engine-detected, NOT the AI's interpretation)
        for a in p.anomalies {
            let dir = a.direction == "low" ? "BELOW" : "ABOVE"
            lines.append("• Anomaly: \(a.metric.displayName) is \(dir) baseline — today \(String(format: "%.1f", a.today)) \(a.metric.unit), baseline \(String(format: "%.1f", a.baseline)), z=\(String(format: "%.2f", a.zScore)) (\(a.severity.rawValue))")
        }

        if lines.isEmpty {
            return "All quiet — no notable signals from your last 28 days."
        }
        return lines.joined(separator: "\n")
    }

    /// One-line summary of the latest snapshot for injection into the
    /// system prompt. Empty parts are dropped — the line stays compact.
    fileprivate static func predictionsSummaryLine(_ p: Predictions?) -> String {
        guard let p else { return "Snapshot not yet computed." }
        if let n = p.insufficientHistoryDays, n > 0 {
            return "Building baseline — \(n) more day(s) of history needed."
        }
        var parts: [String] = []
        if let m = p.healthMeter {
            parts.append("Health \(m.score)/100 (\(m.label.headline))")
        }
        if let r = p.recovery {
            parts.append("Recovery \(r.score)/100 (\(r.label.headline), \(r.confidence.rawValue) conf)")
        }
        if let n = p.nextWorkout {
            let f = DateFormatter(); f.dateFormat = "ha"
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let s = cal.date(byAdding: .hour, value: n.startHour, to: today) ?? today
            let e = cal.date(byAdding: .hour, value: n.endHour, to: today) ?? today
            let cat = n.isCategoryFallback ? "workout" : n.category.displayName.lowercased()
            parts.append("likely \(cat) \(n.weekdayLabel) \(f.string(from: s))–\(f.string(from: e))")
        }
        if let traj = p.trajectories.first(where: { $0.metric == .steps }) {
            parts.append("steps \(traj.status.headline.lowercased())")
        }
        if let s = p.sedentary {
            parts.append("\(s.quietHours)h quiet")
        }
        return parts.isEmpty ? "All quiet — no notable signals." : parts.joined(separator: " · ")
    }

    private func encodeJSON(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
    
    /// Run the confirmed side effect for a write-action tool call attached to `messageId`.
    /// Bounded by a 60s timeout so a hung HealthKit / EventKit write never leaves
    /// the card stuck in the `.confirmed` spinner state. On terminal status,
    /// fires a follow-up Gemini turn so Astra can acknowledge ("Logged ✓").
    public func confirmToolCall(messageId: UUID) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let call = messages[idx].toolCall else { return }
        messages[idx].toolStatus = .confirmed
        let ok = await withTimeout(seconds: 60) {
            await self.executeWriteTool(call)
        } ?? false
        messages[idx].toolStatus = ok ? .done : .failed
        persistLiveSnapshot()
        await sendFollowup()
    }

    /// Runs `op` and returns its result, or nil if it doesn't finish within `seconds`.
    private func withTimeout<T: Sendable>(seconds: Double, op: @Sendable @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    public func cancelToolCall(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].toolStatus = .cancelled
        persistLiveSnapshot()
        // Skip the acknowledgment turn while another stream is active — a
        // concurrent sendFollowup would append a doubled model message. The
        // cancelled status still round-trips as a functionResponse on the
        // next turn. Set isGenerating before the Task so nothing can slip in
        // between scheduling and execution.
        guard !isGenerating else { return }
        isGenerating = true
        Task { await sendFollowup() }
    }

    /// Re-invokes Gemini with an empty prompt after a tool reaches a terminal state.
    /// The history serializer in VertexGeminiClient injects the matching
    /// `functionResponse` part, so the model streams a short acknowledgment as a
    /// fresh model message. No-op for tools that don't need confirmation.
    private func sendFollowup() async {
        isGenerating = true
        currentStreamingText = ""
        defer {
            isGenerating = false
            currentStreamingText = ""
            persistLiveSnapshot()
        }

        let systemInstruction = await buildSystemInstruction()
        let history = messages

        do {
            let stream = await VertexGeminiClient.shared.streamGenerateContent(
                prompt: "",
                history: history,
                systemInstruction: systemInstruction,
                imageData: nil,
                imageMimeType: "image/jpeg",
                model: "gemini-3.5-flash"
            )

            let modelId = UUID()
            messages.append(ChatMessage(id: modelId, role: .model, text: ""))

            // Throttle text publishes — same 50ms cadence as sendMessage.
            var lastFlush = Date.distantPast

            for try await chunk in stream {
                guard let idx = messages.firstIndex(where: { $0.id == modelId }) else { break }
                switch chunk {
                case .text(let delta):
                    currentStreamingText += delta
                    lastFlush = flushStreamingText(into: idx, lastFlush: lastFlush, force: false)
                case .toolCall(let call):
                    // Force the partial text out before the tool takes over.
                    _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
                    // A follow-up that itself chains a tool — re-enter the same
                    // pending/confirmation loop. ChatView's card UI handles this
                    // identically to the original toolCall. Read tools that
                    // produce a payload auto-execute here too, so chains like
                    // get_predictions → list_reminders keep flowing.
                    messages[idx].toolCall = call
                    messages[idx].toolStatus = call.needsConfirmation ? .pending : .autoExecuted
                    if call.producesPayload {
                        await autoExecuteReadTool(messageId: modelId)
                    }
                    return
                case .usage(let usage):
                    messages[idx].tokenUsage = usage
                case .thoughtSignature(let sig):
                    messages[idx].thoughtSignature = sig
                }
            }
            // Stream ended cleanly — make sure the final accumulated text lands.
            if let idx = messages.firstIndex(where: { $0.id == modelId }) {
                _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
            }
            // If the follow-up produced no text and no tool call, drop the empty placeholder
            // so the chat doesn't show a blank bubble.
            if let idx = messages.firstIndex(where: { $0.id == modelId }),
               messages[idx].text.isEmpty, messages[idx].toolCall == nil {
                messages.remove(at: idx)
            }
        } catch {
            print("Follow-up streaming error: \(error.localizedDescription)")
            // Flush any partial text that streamed before the error so a real
            // reply isn't lost. Only a genuinely-empty placeholder is dropped
            // below, so the user sees a single error bubble (not blank+error).
            if let idx = messages.lastIndex(where: { $0.role == .model && $0.toolCall == nil && $0.text.isEmpty }) {
                if currentStreamingText.isEmpty {
                    messages.remove(at: idx)
                } else {
                    messages[idx].text = currentStreamingText
                }
            }
            messages.append(ChatMessage(
                role: .model,
                text: "Couldn't reach the coach to finish that step. Tap Retry to try again.",
                isError: true
            ))
        }
    }

    private func executeWriteTool(_ call: ToolCall) async -> Bool {
        switch call {
        case .logFood(let name, let cal, let p, let c, let f, _, _, _, _, let est, let conf):
            let ok = await HealthKitManager.shared.logFood(
                name: name, calories: cal, protein: p, carbs: c, fat: f,
                isEstimate: est, confidence: conf
            )
            if ok {
                // Refresh dietary state so the next Coach turn AND the Home
                // Meals card AND the Health Meter recompute pick up the new
                // entry immediately — without waiting for a full HK refetch.
                await HealthKitManager.shared.refreshDietaryNow()
            }
            return ok
        case .addReminder(let title, let due, _):
            return EventKitManager.shared.addReminder(title: title, dueDate: due)
        case .addCalendarEvent(let title, let start, let end, let notes):
            return EventKitManager.shared.addEvent(title: title, startDate: start, endDate: end, notes: notes)
        case .updateReminder(let id, let title, let due, let notes):
            return await EventKitManager.shared.updateAppReminder(id: id, title: title, dueDate: due, notes: notes)
        case .updateCalendarEvent(let id, let title, let start, let end, let notes):
            return EventKitManager.shared.updateAppEvent(id: id, title: title, startDate: start, endDate: end, notes: notes)
        case .deleteReminder(let id, _):
            return EventKitManager.shared.deleteAppReminder(id: id)
        case .deleteCalendarEvent(let id, _):
            return EventKitManager.shared.deleteAppEvent(id: id)
        case .updateFoodLog(let id, let name, let cal, let p, let c, let f):
            return await HealthKitManager.shared.updateAppFood(
                id: id, name: name, calories: cal, protein: p, carbs: c, fat: f
            )
        case .deleteFoodLog(let id, _):
            return await HealthKitManager.shared.deleteAppFood(id: id)
        case .createWidget(let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            // Default to .composed when blocks are provided so the legacy
            // layout enum doesn't conflict.
            let layoutEnum: WidgetLayout = {
                if blocks != nil { return .composed }
                return WidgetLayout(rawValue: layout) ?? .narrative
            }()
            let widget = AstraWidget(
                title: title, icon: icon, colorName: color, layout: layoutEnum,
                headline: headline, body: body, bullets: bullets,
                metricRef: metricRef, goalValue: goalValue,
                blocks: blocks
            )
            return AstraWidgetStore.shared.add(widget)
        case .updateWidget(let id, let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            guard let uuid = UUID(uuidString: id) else { return false }
            let layoutEnum: WidgetLayout? = layout.flatMap { WidgetLayout(rawValue: $0) }
                ?? (blocks != nil ? .composed : nil)
            return AstraWidgetStore.shared.update(
                id: uuid,
                title: title, icon: icon, colorName: color, layout: layoutEnum,
                headline: headline, body: body, bullets: bullets,
                metricRef: metricRef, goalValue: goalValue, blocks: blocks
            )
        case .deleteWidget(let id, _):
            guard let uuid = UUID(uuidString: id) else { return false }
            return AstraWidgetStore.shared.remove(id: uuid)
        case .showMetricChart, .showComparisonChart, .renderCard,
             .listReminders, .listCalendarEvents, .getPredictions,
             .listFoodLog, .listWidgets, .updateNotes, .getSleepPattern:
            return true
        }
    }

    /// Re-fire whichever request produced the most recent error bubble. If the
    /// failure came from a follow-up turn (last non-error message is a model
    /// bubble with a terminal-state tool call), re-run `sendFollowup`. Otherwise
    /// re-run the original user message via the standard streaming flow.
    public func retryLast() async {
        guard let errIdx = messages.lastIndex(where: { $0.isError }) else { return }
        let priorIdx = errIdx - 1
        guard priorIdx >= 0 else { return }
        let prior = messages[priorIdx]

        // Tool-followup failure: prior is a model bubble whose tool reached a
        // terminal state. Re-firing sendFollowup re-uses the existing
        // functionResponse round-trip without needing a new user prompt.
        let priorIsToolDone: Bool = {
            guard prior.role == .model, prior.toolCall != nil else { return false }
            switch prior.toolStatus {
            case .done, .failed, .cancelled: return true
            default: return false
            }
        }()

        messages.remove(at: errIdx)

        if priorIsToolDone {
            await sendFollowup()
            return
        }

        // Otherwise: re-fire the original sendMessage flow. Find the most
        // recent user message and replay it (the user bubble stays — only the
        // error is removed and a fresh model bubble streams in its place).
        let priorSlice = messages.prefix(through: priorIdx)
        guard let userIdx = priorSlice.lastIndex(where: { $0.role == .user }) else { return }
        let user = messages[userIdx]
        let history = Array(messages.prefix(userIdx))

        isGenerating = true
        currentStreamingText = ""
        defer {
            isGenerating = false
            currentStreamingText = ""
            persistLiveSnapshot()
        }

        let systemInstruction = await buildSystemInstruction()
        let prompt = user.text.isEmpty ? "What is this? Give me full details." : user.text

        do {
            let stream = await VertexGeminiClient.shared.streamGenerateContent(
                prompt: prompt,
                history: history,
                systemInstruction: systemInstruction,
                imageData: user.imageData,
                imageMimeType: "image/jpeg",
                model: "gemini-3.5-flash"
            )

            let modelId = UUID()
            messages.append(ChatMessage(id: modelId, role: .model, text: ""))

            // Throttle text publishes — same 50ms cadence as sendMessage.
            var lastFlush = Date.distantPast

            for try await chunk in stream {
                guard let idx = messages.firstIndex(where: { $0.id == modelId }) else { break }
                switch chunk {
                case .text(let delta):
                    currentStreamingText += delta
                    lastFlush = flushStreamingText(into: idx, lastFlush: lastFlush, force: false)
                case .toolCall(let call):
                    // Force the partial text out before the tool takes over.
                    _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
                    messages[idx].toolCall = call
                    messages[idx].toolStatus = call.needsConfirmation ? .pending : .autoExecuted
                    if call.producesPayload {
                        await autoExecuteReadTool(messageId: modelId)
                    }
                    return
                case .usage(let usage):
                    messages[idx].tokenUsage = usage
                case .thoughtSignature(let sig):
                    messages[idx].thoughtSignature = sig
                }
            }
            // Stream ended cleanly — make sure the final accumulated text lands.
            if let idx = messages.firstIndex(where: { $0.id == modelId }) {
                _ = flushStreamingText(into: idx, lastFlush: lastFlush, force: true)
            }
        } catch {
            print("Retry streaming error: \(error.localizedDescription)")
            // Flush whatever text streamed before the error so a partial reply
            // isn't truncated when the error bubble is appended below. Only act
            // when there's real partial text, so we never blank out a bubble
            // (e.g. the placeholder, or an earlier message) on a pre-stream error.
            if !currentStreamingText.isEmpty,
               let idx = messages.lastIndex(where: { $0.role == .model && $0.toolCall == nil }) {
                messages[idx].text = currentStreamingText
            }
            messages.append(ChatMessage(
                role: .model,
                text: "Still couldn't reach the coach. Check your network and try again.",
                isError: true
            ))
        }
    }

    public func clearChat() {
        messages = [
            ChatMessage(
                role: .model,
                text: "Chat cleared! Let's start fresh. How can I help you with your fitness journey today?"
            )
        ]
        // The cleared conversation is the new live state — a relaunch must not
        // resurrect what the user just erased.
        ChatHistoryStore.shared.clearLive()
    }

    // MARK: - Session history

    /// True once the current conversation has at least one real user turn —
    /// i.e. it's worth archiving. A lone greeting (or an empty viewer of a
    /// past session) is not. Used to gate `archiveCurrent()` callers.
    public var hasArchivableConversation: Bool {
        // A read-only replay of a past session is never re-archived (it would
        // duplicate an existing entry); only live conversations are.
        guard !isViewingArchivedSession else { return false }
        return messages.contains { $0.role == .user }
    }

    /// Set while the user is looking at a loaded past session, so we don't
    /// archive a duplicate copy when they then start a new chat or leave.
    private var isViewingArchivedSession = false

    /// Push the current live conversation into the persistent history archive
    /// (newest-first, capped). No-op when there's nothing worth keeping or when
    /// we're merely viewing an already-archived session.
    public func archiveCurrent() {
        guard hasArchivableConversation else { return }
        ChatHistoryStore.shared.archive(messages: messages)
    }

    /// Archive whatever is on screen, then reset to a fresh greeting. This is
    /// the "compose new chat" affordance.
    public func startNewChat() {
        archiveCurrent()
        ChatHistoryStore.shared.clearLive()
        isViewingArchivedSession = false
        messages = [ChatMessage(role: .model, text: Self.greetingText)]
        currentStreamingText = ""
    }

    /// Replace the current conversation with a past session for read-only
    /// replay. Archives the live conversation first so it isn't lost. Past
    /// tool cards render as plain text — only text + images are restored.
    public func loadSession(_ session: ChatSession) {
        archiveCurrent()
        // The live conversation is safely archived; empty the live slot so a
        // relaunch mid-replay doesn't resume the replaced conversation. If the
        // user reactivates this replay by sending a message, sendMessage flips
        // isViewingArchivedSession and re-fills the slot.
        ChatHistoryStore.shared.clearLive()
        let restored = session.messages.map { $0.toChatMessage() }
        messages = restored.isEmpty
            ? [ChatMessage(role: .model, text: Self.greetingText)]
            : restored
        isViewingArchivedSession = true
        currentStreamingText = ""
    }
    
    private func historySummary(for type: HealthMetricType) -> String {
        guard let summary = HealthKitManager.shared.metricSummaries[type] else { return "No historical data" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Filter history to last 7 days (excluding today's live sample)
        let last7Days = summary.history
            .filter { $0.date < today }
            .sorted(by: { $0.date > $1.date })
            .prefix(7)
            .reversed()
        
        if last7Days.isEmpty {
            return "No historical records available."
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MM/dd"
        
        return last7Days.map { item in
            let dateStr = formatter.string(from: item.date)
            let valStr: String
            if type == .steps || type == .activeEnergy {
                valStr = String(format: "%.0f", item.value)
            } else if type == .heartRate {
                valStr = String(format: "%.0f", item.value)
            } else if type == .distance {
                valStr = String(format: "%.2f", item.value)
            } else {
                valStr = String(format: "%.1f", item.value)
            }
            return "\(dateStr): \(valStr) \(type.unit)"
        }.joined(separator: ", ")
    }
    
    private func buildSystemInstruction() async -> String {
        let hk = HealthKitManager.shared

        // Make sure the prediction snapshot we inject below is fresh — a long
        // chat session shouldn't reason on a 30-minute-old fetch. No-op when
        // `predictions.generatedAt` is within 5 minutes.
        await hk.refreshIfStale(maxAgeMinutes: 5)

        let ud = UserDefaults.standard

        // -- User profile (AppStorage + HK characteristics) -------------------
        let name      = ud.string(forKey: "athlete_name") ?? "—"
        let dobIv     = ud.double(forKey: "athlete_dob")
        let heightCm  = ud.double(forKey: "athlete_height_cm")
        let weightKg  = ud.double(forKey: "athlete_weight_kg")
        let appSex    = ud.string(forKey: "athlete_sex") ?? ""
        let coachPer  = ud.string(forKey: "coach_personality") ?? "Direct"
        let goalsRaw  = ud.string(forKey: "training_goals") ?? ""

        let (hkDob, hkSex, hkBlood) = hk.readMedicalIdCharacteristics()
        let dobDate: Date? = dobIv > 0 ? Date(timeIntervalSince1970: dobIv) : hkDob
        let age: String = {
            guard let d = dobDate else { return "—" }
            return String(Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 0)
        }()
        let sexLabel: String = {
            if !appSex.isEmpty { return appSex }
            switch hkSex ?? .notSet {
            case .female: return "Female"
            case .male:   return "Male"
            case .other:  return "Other"
            default:      return "—"
            }
        }()
        let bloodLabel: String = {
            switch hkBlood ?? .notSet {
            case .aPositive:   return "A+"
            case .aNegative:   return "A−"
            case .bPositive:   return "B+"
            case .bNegative:   return "B−"
            case .abPositive:  return "AB+"
            case .abNegative:  return "AB−"
            case .oPositive:   return "O+"
            case .oNegative:   return "O−"
            default:           return "—"
            }
        }()
        let heightIn = heightCm > 0 ? String(format: "%.1f", heightCm / 2.54) : "—"
        let weightLb = weightKg > 0 ? String(format: "%.1f", weightKg * 2.2046) : "—"
        let heightCmStr = heightCm > 0 ? String(format: "%.0f", heightCm) : "—"
        let weightKgStr = weightKg > 0 ? String(format: "%.1f", weightKg) : "—"
        let dobStr: String = {
            guard let d = dobDate else { return "—" }
            let f = DateFormatter(); f.dateStyle = .medium
            return f.string(from: d)
        }()

        // -- Medical profile (clinical records; empty arrays when not opted in) ---
        let (allergies, conditions, medications) = await hk.readClinicalRecords()
        let allergiesStr   = allergies.isEmpty   ? "None known" : allergies.joined(separator: ", ")
        let conditionsStr  = conditions.isEmpty  ? "None known" : conditions.joined(separator: ", ")
        let medicationsStr = medications.isEmpty ? "None known" : medications.joined(separator: ", ")
        let conditionGate = (conditions.isEmpty && medications.isEmpty)
            ? ""
            : "\n\nTreat these as gatekeepers — flag activities, foods, or intensities that could conflict, and recommend the user consult their doctor for anything clinically significant."

        // -- Locale -----------------------------------------------------------
        let tz = TimeZone.current.identifier
        let useMetric = Locale.current.measurementSystem == .metric
        let unitsLabel = useMetric ? "metric" : "imperial"

        // -- Today's metrics --------------------------------------------------
        func cur(_ t: HealthMetricType) -> Double { hk.metricSummaries[t]?.currentValue ?? 0 }
        func goalOf(_ t: HealthMetricType) -> Double { hk.metricSummaries[t]?.goal ?? 0 }
        func displayOr(_ v: Double, _ format: String) -> String {
            v > 0 ? String(format: format, v) : "—"
        }
        let steps   = cur(.steps);         let stepsGoal   = goalOf(.steps)
        let cals    = cur(.activeEnergy);  let calsGoal    = goalOf(.activeEnergy)
        let sleepH  = cur(.sleep);         let sleepGoal   = goalOf(.sleep)
        let dist    = cur(.distance);      let distGoal    = goalOf(.distance)
        let hrLive  = cur(.heartRate)
        let rhr     = cur(.restingHeartRate)
        let hrv     = cur(.hrv)
        let vo2     = cur(.vo2Max)
        let spo2    = cur(.oxygenSaturation)
        func pct(_ v: Double, _ g: Double) -> Int { g > 0 ? Int((v / g) * 100) : 0 }

        // -- On-device prediction snapshot — full structured breakdown -------
        let predictionsBlock = Self.predictionsFullBlock(hk.predictions)

        // -- Sleep pattern (from on-device SleepSessionStore) ----------------
        let sleepPatternBlock = Self.sleepPatternInlineBlock()

        // -- Today's nutrition (logged meals) ---------------------------------
        let nutritionBlock = Self.nutritionBlock(
            calories: hk.dietaryCaloriesToday,
            protein: hk.dietaryProteinToday,
            log: hk.todayFoodLog,
            goals: NutritionService.shared.macroGoals
        )

        // -- 7-day histories --------------------------------------------------
        let stepsHistory = historySummary(for: .steps)
        let calsHistory  = historySummary(for: .activeEnergy)
        let sleepHistory = historySummary(for: .sleep)
        let distHistory  = historySummary(for: .distance)
        let hrHistory    = historySummary(for: .heartRate)
        let rhrHistory   = historySummary(for: .restingHeartRate)
        let hrvHistory   = historySummary(for: .hrv)

        // -- Cross-session memory (stored by update_notes tool) ---------------
        let savedNotes = UserDefaults.standard.string(forKey: "astra_notes") ?? ""
        let notesBlock: String = savedNotes.isEmpty
            ? "No notes yet. Use update_notes silently when you learn something lasting."
            : savedNotes

        let instructions = """
        You are "Astra", an elite, personalized fitness and wellness companion grounded in the user's real Apple Health data. Stay confident, encouraging, concise.

        USER PROFILE
        - Name: \(name)
        - Sex: \(sexLabel)
        - DOB: \(dobStr) (age \(age))
        - Height: \(heightCmStr) cm / \(heightIn) in
        - Weight: \(weightKgStr) kg / \(weightLb) lb
        - Blood type: \(bloodLabel)
        - Coach style: \(coachPer)
        - Training goals: \(goalsRaw.isEmpty ? "none set" : goalsRaw)

        YOUR MEMORY (cross-session notes written by you via update_notes — treat as gospel for personalisation)
        \(notesBlock)

        MEDICAL PROFILE (from HealthKit clinical records when the user has linked a provider; otherwise empty. "None known" means we don't have a record — never confuse with "the user has none.")
        - Allergies: \(allergiesStr)
        - Conditions: \(conditionsStr)
        - Medications: \(medicationsStr)\(conditionGate)

        LOCALE
        - Timezone: \(tz) — use this for ALL relative-time conversion ("tomorrow morning", "in 2 hours").
        - Units: \(unitsLabel) — never mix.

        TODAY'S METRICS (live from HealthKit)
        - Steps: \(Int(steps)) / \(Int(stepsGoal)) (\(pct(steps, stepsGoal))%)
        - Active calories: \(Int(cals)) / \(Int(calsGoal)) kcal (\(pct(cals, calsGoal))%)
        - Sleep: \(displayOr(sleepH, "%.1f")) h / \(Int(sleepGoal)) h (\(pct(sleepH, sleepGoal))%)
        - Distance: \(displayOr(dist, "%.2f")) / \(String(format: "%.1f", distGoal)) mi
        - Latest HR: \(displayOr(hrLive, "%.0f")) bpm
        - Resting HR: \(displayOr(rhr, "%.0f")) bpm
        - HRV: \(displayOr(hrv, "%.0f")) ms
        - VO₂ max: \(displayOr(vo2, "%.1f")) ml/kg·min
        - SpO₂: \(displayOr(spo2, "%.0f"))%

        PREDICTIONS (on-device snapshot — same data the user sees on the Home card. You have it INLINE so you do not need to call get_predictions unless you want the raw JSON.)
        \(predictionsBlock)

        SLEEP PATTERN (built on-device from the user's tracked sleep sessions — separate from HK sleep metrics. Pattern emerges after ≥3 nights. Use this as the user's personal baseline before any universal sleep rule. Call get_sleep_pattern when you need the per-night breakdown for the last 5 sessions.)
        \(sleepPatternBlock)

        \(nutritionBlock)

        LAST 7 DAYS (for trend + baseline math)
        - Steps: \(stepsHistory)
        - Active calories: \(calsHistory)
        - Sleep: \(sleepHistory)
        - Distance: \(distHistory)
        - Heart rate: \(hrHistory)
        - Resting HR: \(rhrHistory)
        - HRV: \(hrvHistory)

        DATA SEMANTICS
        - "—" or null = HealthKit returned no record. NEVER invent or imply a value.
        - 0 may be a genuine value depending on context: 0 steps at 6 AM is "early morning"; 0 sleep is almost certainly "not synced yet" — use judgement. When in doubt, state the ambiguity.
        - Watch-class metrics (HR, HRV, RHR, exercise/stand minutes, VO₂max, SpO₂) require a Watch / wearable. If those are all "—" you're iPhone-only — coach around steps / distance / sleep / nutrition.
        - If the user asks about a metric you don't have, say so plainly and explain how they'd enable it.

        PERSONAL BASELINES (use these BEFORE universal thresholds)
        - Compute baselines from the 7-day history above. For RHR / HRV / sleep, deviation from the user's own mean matters more than any fixed cutoff.
        - A "fit athlete" RHR of 45 spiking to 75 is a large signal — flag it, even though 75 is "normal" by universal rules.
        - Flag when today's value is > 1.5× standard deviation from the 7-day mean in the concerning direction (RHR up, HRV down, sleep down).

        SAFETY RAILS
        - Acute injury / pain: if the user mentions pain ("my knee hurts mid-run"), STOP the session, do not push through, recommend rest. If pain is recurring or severe, suggest a clinician — never minimize it.
        - Out-of-range backstops: resting HR > 100 sustained, sleep < 4 h, sustained HR ≥ 90% of estimated max at rest. For estimated max HR use the Tanaka formula (208 − 0.7 × age) unless a measured max is available — flag the estimate as approximate.
        - HRV is highly individual. Only flag HRV when it's notably below the user's own 7-day baseline; avoid absolute cutoffs.
        - Disordered eating patterns: refuse aggressive caloric-deficit plans, "lose X lb in Y days" exceeding 1%/week, fasting > 24 h, or restriction-coded requests. Redirect to sustainable habits.
        - Overtraining: high 7-day load AND HRV trending down (or RHR up) → prioritize recovery, not hard sessions.
        - Conditions in MEDICAL PROFILE override generic advice. Cardiac → cap zone-3+, defer to cardiology. Asthma → environmental cues. Pregnancy (if disclosed by the user, may not be in records) → avoid contraindicated movements, recommend OB consult. Diabetes → fueling around insulin/meds.
        - Medications: beta-blockers blunt HR-zone targets — use RPE instead. Diuretics → flag hydration. Anticoagulants → flag contact-sport risk.
        - Minors: if derived age < 18 → no caloric deficits, no aggressive intensity programming, conservative volume guidance, encourage adult / clinician oversight.
        - Standing disclaimer (1 line, only when advice is clinical/diagnostic): "I'm not a medical professional — confirm with your doctor."

        ALLERGY HANDLING
        - "None known" = absence of record, NOT absence of allergy. Never tell the user a food is "safe for you" or "allergy-free" on the basis of empty allergy data.
        - When allergies ARE listed: cross-check log_food items and surface conflicts in `cautions` ("Contains peanuts — listed in your allergies").
        - When allergies are empty: if the food contains common allergens (peanuts, tree nuts, shellfish, dairy, gluten, soy, eggs), note them in `cautions` generically ("Contains peanuts — common allergen") WITHOUT claiming safety either way.

        TOOLS — prefer over prose whenever they fit
        - update_notes : your cross-session memory. Call silently at the END of any turn where you learn something lasting — injury, preference, goal, pattern. Overwrite the full blob. Do NOT interrupt the conversation with a note about it.
        - get_sleep_pattern : on-device sleep pattern + the last 5 tracked nights with per-night motion/snore detail. Call FIRST whenever the user asks anything about sleep — "how's my sleep", "am I getting enough", "why am I tired", "is my snoring getting worse". Cite the user's personal numbers (typical bedtime, restlessness baseline, consistency) instead of generic guidance. If the user has fewer than 3 tracked nights, gently encourage them to use the Home > Sleep Tracker card before bed.
        - log_food : food photos or text. Fill ALL FOUR macros (calories, protein, carbs, fat) using your nutrition training data — never default to 0 unless the food genuinely has 0 of that macro (e.g. fat in a plain banana is ~0.4g, NOT 0). Fill tags / highlights / cautions. ALWAYS set is_estimate=true and pick a confidence level (low/medium/high) — only set is_estimate=false when the user supplied exact label nutrition. For ambiguous portions ASK rather than guess. For multi-item plates, emit ONE log_food per distinct item.
        - add_reminder / add_calendar_event : convert relative times to ISO8601 in the user's TZ. Default workout 30 min.
        - list_reminders / list_calendar_events : READ-ONLY. Use FIRST when asked to modify / postpone / delete — you cannot guess ids. If list returns exactly ONE match for the user's description, proceed straight to update_/delete_ without asking.
        - update_reminder / update_calendar_event / delete_reminder / delete_calendar_event : by id from the prior list_* call. Always pass `title` on deletes.
        - show_metric_chart / show_comparison_chart : visualize trends. Use comparison proactively when a 7-day pattern is interesting. After either chart renders, you receive the series stats (avg/min/max/latest/change %) via functionResponse and you MUST reply with a brief grounded analysis — 2-3 sentences MAX: the trend, one notable high or low, one actionable takeaway — quoting the user's actual numbers from the stats. Never re-list the chart's contents point by point.
        - render_card : structured visuals that don't fit other tools. SF Symbol icon, color ∈ {accent, red, green, blue, orange, purple, cyan, yellow}. After the card renders you get an ack via functionResponse — follow with a SINGLE-sentence takeaway; never re-list the card's contents.
        - get_predictions : on-device PredictionEngine snapshot (recovery readiness, next-likely-workout, goal trajectory, sedentary alert). Call FIRST whenever the user asks "how should I train", "am I recovered", "should I rest/run/lift", "on track for my goals". Always surface the structured confidence + why-bullets it returns — never quote raw numbers as gospel. Prefer this over re-deriving from raw 7-day history.
        - list_food_log / update_food_log / delete_food_log : READ + WRITE for today's logged meals. Use list_food_log FIRST when the user asks to fix, correct, rename, change, or delete a logged meal — you cannot guess the id. If list returns exactly ONE match for the user's description, proceed straight to update_/delete_ without asking. Pass `name` on deletes so the confirm card shows what's about to go.
        - create_widget / list_widgets / update_widget / delete_widget : ASTRA STUDIO — your creative canvas on the user's Home screen. See the WIDGET STUDIO block below for when and how to use it.

        WIDGET STUDIO (this is your canvas — go bold)
        - You have a 6-slot widget grid on the user's Home, dedicated entirely to your output. You have FULL CREATIVE LICENSE over composition, color, icon, and copy — design widgets that are surprising, varied, and genuinely useful. Treat every widget as a chance to make something the user will love seeing each day. Boring, samey, single-block cards are a missed opportunity.
        - PROACTIVELY offer a widget when you spot something pin-worthy: a streak forming, a pattern worth a daily nudge, a stat the user keeps asking about, a habit worth tracking. "Want me to pin this to your Home so you see it every day?" is a great move.
        - TWO AUTHORING MODES — pick one per widget:
          1. Legacy preset (`layout: kpi | narrative | list | progress`) — fast, fits 4 common shapes. Use headline/body/bullets/metric_ref/goal_value as documented. Fine for a quick single-purpose card.
          2. COMPOSABLE BLOCKS (`layout: composed`, plus a `blocks` array) — THIS is where the magic happens. Stack 2-4 of these primitives in any order you like and let your imagination run:
             • metric_value — big number, live-bound or literal
             • ring — animated progress ring (fills on appear)
             • sparkline — 14-day line of a metric (draws in left→right)
             • mini_bars — last N daily bars, color-graded against the average
             • comparison — A-vs-B twin bars with delta % chip
             • delta — single "+12% vs last 7 days" chip with up/down arrow
             • bullets — short list
             • text — paragraph
             • chip_row — horizontal status pills
             • quote — italic motivational line
             • checklist — an INTERACTIVE to-do list; each item gets a tappable checkbox the user ticks off (state persists). This is how you make a "to-do style" health card: routines, recovery checklists, habit stacks.
             • button_row — tappable action buttons; action is 'coach_prompt' (value = a message sent to you on tap) or 'log_water' (value = millilitres logged to Health). Great for one-tap actions on a card.
        - BE BOLD WITH COMPOSITION. Mix block types freely and unexpectedly: a checklist on top of a ring; a metric_value + sparkline + delta trio; a quote + mini_bars; a comparison + chip_row + button_row. Combine checklist + buttons + metrics + sparklines in one card when it serves the user. The more varied the combinations across the grid, the better. Don't default to one block or one familiar shape — invent layouts the user hasn't seen yet.
        - TO-DO / HABIT CARDS: when the user wants a checklist, routine, habit tracker, or "to-do style" card, use layout:composed with a checklist block — and feel free to dress it up with a text intro, a metric/ring showing progress, and a button_row for one-tap actions. Keep items terse and actionable.
        - Live metric bindings (`metric_ref` field on blocks): steps, heart_rate, active_energy, resting_energy, sleep, distance, hydration, hrv, resting_hr, exercise_minutes, stand_hours, mindful_minutes, flights, vo2_max, walking_speed, step_length, body_mass, health_meter, recovery_score. Live-bound blocks animate when their data updates. Use ONLY these metric_ref values — anything else won't bind.
        - GO WILD ON COLOR & ICONS (within the palette). Match icons expressively to the topic (flame.fill for streaks, bolt.heart for cardio, leaf.fill for recovery, sunrise for morning, moon.zzz for sleep, drop.fill for hydration, fork.knife for nutrition, brain for mindfulness, chart.line.uptrend.xyaxis for trends — but reach for unexpected, fitting symbols too). Vary colors widely across the grid so no two widgets look alike — rotate through accent, red, orange, yellow, green, blue, indigo, purple, pink, cyan, gray rather than reusing one.
        - HARD LIMITS (these stay fixed — everything else is yours): max 6 widgets at once; the user must confirm every create/update/delete; use only the block types listed above; use only the metric_ref values listed above.
        - When full (6 widgets), call list_widgets to see what's there, then delete_widget the stalest before creating a new one — or ask the user which to drop.
        - Pin when there's a reason, not reflexively at the start of every chat. When in doubt, ask first — but once the user says yes, make it bold and beautiful.

        NEVER FAKE WRITES (this is the most important rule in this section)
        - You can ONLY claim to have updated / logged / deleted / scheduled something if you actually invoked the matching tool in THIS turn and the tool's confirmation state was `.done`.
        - If the user asks to correct a meal and you haven't called list_food_log + update_food_log, do NOT say "I've updated it" or "Got it, updated". Say honestly that you'll update it, then call the tool.
        - This applies to log_food, update_food_log, delete_food_log, add_reminder/update/delete, add_calendar_event/update/delete. Hallucinating success on any of these breaks trust.

        SCOPE
        - You see and modify only items the app created — never the user's personal calendar / reminders. Don't claim you can.

        DECISIVENESS
        - Workable time/quantity/range → ACT. Pick a sensible default ("4–5 pm" → 4:00 PM, 30 min). Confirm card lets the user adjust.
        - Ask back only when input is genuinely ambiguous ("schedule it" with no time).

        MULTI-TOOL
        - Two asks in one message → emit BOTH tool calls in the same turn if the backend supports parallel function calls.

        TREND-AWARE COACHING (don't just report — correlate)
        - Look across metrics for patterns: "sleep drops on days you train late", "HRV dipped Thu–Sat — your hardest 3-day stretch."
        - Propose goal adjustments when trends warrant: steps consistently 130%+ → raise goal. Sleep consistently <80% → earlier wind-down.

        OUTPUT FORMAT — STRICT (rendered as markdown)
        - Open with the takeaway: 1 sentence, 8–15 words.
        - `### Section` heading when ≥ 2 distinct sections.
        - `-` bullets, ONE line each, ≤ 18 words. No paragraphs.
        - **Bold** for any quantitative call-out (numbers, BPM, kcal, hours).
        - "Next:" line at the end — REQUIRED for advisory replies; OPTIONAL for trivial lookups ("what's my resting HR?" → just the number).
        - Never apologise, never preface with "Sure!" or "As Astra…".

        BREVITY (~600 tokens)
        - Priority order when trimming: keep TAKEAWAY → keep NEXT → keep most-relevant SECTION → drop other sections → only then compress bullets. If even that won't fit, render_card it.

        IMAGE HANDLING
        - FOOD / BEVERAGE: call log_food with is_estimate=true and a confidence level. Keep prose to the takeaway only — the card carries the detail (no double-rendering). Multi-item plate → one log_food per distinct item. Ambiguous portion → ASK ("looks like ~150 g — is that right?") rather than invent. Prefix the food name with "est." when guessing without a reference. Do NOT emit the legacy [FOOD] text line — the tool replaces it.
        - FITNESS EQUIPMENT / sportswear: identify precisely, sections: ### How to use · ### Targets · ### Safety.
        - Other: briefly describe, steer back to fitness.

        EXAMPLE SHAPE
        > **Recovery is strong.** Push intensity today.
        >
        > ### Why
        > - HRV up **12%** vs your 7-day baseline.
        > - Resting HR at a 30-day low (**61 bpm**).
        >
        > ### Plan
        > - 45 min zone-4 ride before 6 PM.
        > - Refuel: **30 g** protein within 30 min after.
        >
        > Next: ride this evening, log it in the app.
        """
        return instructions
    }
}
