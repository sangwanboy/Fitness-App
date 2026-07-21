import SwiftUI
import Combine
import HealthKit

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

        // New user-initiated turn — force a fresh build so LIVE CONTEXT
        // reflects this moment, then pin it for the rest of this turn's tool
        // loop (see `systemInstructionForTurn`).
        let systemInstruction = await systemInstructionForTurn(refresh: true)
        // Use a copy of messages excluding the last user message as history
        let history = Array(messages.dropLast())

        // Default prompt when user sends only an image
        let prompt = trimmed.isEmpty ? "What is this? Give me full details." : trimmed

        do {
            let stream = await GatewayChatClient.shared.streamGenerateContent(
                prompt: prompt,
                history: history,
                systemInstruction: systemInstruction,
                imageData: imageData,
                imageMimeType: "image/jpeg"
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
                text: Self.errorBubbleText(
                    error,
                    fallback: "Sorry, I ran into an issue connecting to my processors. Please check your network connection and try again."
                ),
                isError: true
            ))
        }
    }

    /// Honest error copy for the chat bubble: gateway states (rate-limited,
    /// quota, signed-out, backend-not-configured) surface their specific
    /// user message; anything else keeps the generic connection fallback.
    private static func errorBubbleText(_ error: Error, fallback: String) -> String {
        if let gateway = error as? GatewayError {
            return gateway.userMessage
        }
        return fallback
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
            guard AstraMemoryStore.shared.isEnabled else {
                return ["success": false, "enabled": false,
                        "message": "Memory is turned off in Settings — nothing was saved."]
            }
            UserDefaults.standard.set(notes, forKey: "astra_notes")
            return ["success": true, "saved_length": notes.count]
        case .rememberFact(let category, let text):
            return Self.rememberFactPayload(category: category, text: text)
        case .forgetFact(let query):
            return Self.forgetFactPayload(query: query)
        case .updateProfile(let section, let content):
            return Self.updateProfilePayload(section: section, content: content)
        case .getProfile:
            return Self.getProfilePayload()
        case .getSleepPattern:
            return Self.sleepPatternPayload()
        case .getTrainingPlan:
            return Self.trainingPlanPayload()
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
        case .getMetricHistory(let metric, let days):
            return Self.metricHistoryPayload(metric: metric, days: days)
        case .getSleepSessions(let nights):
            return Self.sleepSessionsPayload(nights: nights)
        default:
            return nil
        }
    }

    /// `remember_fact` dispatch — validates category + non-empty text, honors
    /// the master memory toggle, and reports any eviction back to the model
    /// so it can (silently) know its memory is capped.
    private static func rememberFactPayload(category: String, text: String) -> [String: Any] {
        guard AstraMemoryStore.shared.isEnabled else {
            return ["success": false, "enabled": false,
                    "message": "Memory is turned off in Settings — nothing was saved."]
        }
        guard let cat = MemoryFact.Category(rawValue: category.lowercased()) else {
            return ["success": false,
                    "message": "Unknown category '\(category)'. Use one of: goal, injury, preference, schedule, nutrition, context."]
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["success": false, "message": "Empty fact text — nothing was saved."]
        }
        let (fact, evicted, truncated) = AstraMemoryStore.shared.remember(category: cat, text: trimmed)
        var message = "Saved to memory (\(cat.displayName)): \"\(fact.text)\"."
        if truncated {
            message += " (truncated to \(AstraMemoryStore.maxFactTextLength) characters)"
        }
        if let evicted {
            message += " Memory was full (\(AstraMemoryStore.maxFacts) facts) — dropped the oldest: \"\(evicted.text)\"."
        }
        return ["success": true, "message": message, "fact_id": fact.id.uuidString, "evicted": evicted != nil]
    }

    /// `forget_fact` dispatch — fuzzy substring match against stored fact text.
    private static func forgetFactPayload(query: String) -> [String: Any] {
        guard AstraMemoryStore.shared.isEnabled else {
            return ["success": false, "enabled": false,
                    "message": "Memory is turned off in Settings — nothing to forget."]
        }
        let removed = AstraMemoryStore.shared.forget(matching: query)
        guard !removed.isEmpty else {
            return ["success": false, "message": "No memory matched \"\(query)\" — nothing removed."]
        }
        let names = removed.map { $0.text }.joined(separator: "; ")
        return ["success": true,
                "message": "Removed \(removed.count) memor\(removed.count == 1 ? "y" : "ies"): \(names)",
                "removed_count": removed.count]
    }

    /// `update_profile` dispatch — full-section overwrite, validated against
    /// the known section names.
    private static func updateProfilePayload(section: String, content: String) -> [String: Any] {
        guard AstraMemoryStore.shared.isEnabled else {
            return ["success": false, "enabled": false,
                    "message": "Memory is turned off in Settings — profile not updated."]
        }
        guard let sec = AstraUserProfile.Section(rawValue: section) else {
            return ["success": false,
                    "message": "Unknown profile section '\(section)'. Use one of: summary, goals, trainingContext, injuriesLimitations, preferences, nutritionNotes."]
        }
        AstraMemoryStore.shared.updateProfileSection(sec, content: content)
        return ["success": true, "message": "Updated profile section '\(sec.displayName)'."]
    }

    /// `get_profile` dispatch — full profile + facts + live basics so the
    /// model can review before editing.
    private static func getProfilePayload() -> [String: Any] {
        guard AstraMemoryStore.shared.isEnabled else {
            return ["success": true, "enabled": false,
                    "message": "Memory is turned off in Settings.", "profile": [String: Any](), "facts": [Any]()]
        }
        return AstraMemoryStore.shared.fullPayload()
    }

    /// Per-night payload for `get_sleep_sessions` — the last N tracked
    /// sessions from SleepSessionStore (newest first), each compressed to the
    /// numbers Astra needs to discuss a concrete night. Honest
    /// `{available: false}` when nothing has been tracked yet.
    private static func sleepSessionsPayload(nights: Int) -> [String: Any] {
        let sessions = SleepSessionStore.shared.sessions
        guard !sessions.isEmpty else {
            return ["available": false, "reason": "no tracked sessions"]
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        func hours(_ seconds: Double) -> Double { ((seconds / 3600) * 10).rounded() / 10 }
        let items: [[String: Any]] = sessions.prefix(nights).map { s in
            [
                "date": f.string(from: s.startedAt),
                "duration_h": hours(s.totalDurationSeconds),
                "onset": Int(s.onsetLatencySeconds / 60),
                "restlessness_pct": s.restlessnessScore,
                "snore_episodes": s.snoreEpisodes.count,
                "snore_total_min": Int(s.totalSnoreSeconds / 60),
                "stages": [
                    "deep_h":  hours(s.stageBreakdown.deep),
                    "light_h": hours(s.stageBreakdown.light),
                    "awake_h": hours(s.stageBreakdown.awake)
                ]
            ]
        }
        return ["available": true, "count": items.count, "nights": items]
    }

    /// Universal daily-history payload for `get_metric_history`. Clips the
    /// stored history to the requested window, buckets one value per calendar
    /// day (latest sample wins), and returns an honest `{available: false}`
    /// when the user has no data for that metric.
    private static func metricHistoryPayload(metric: String, days: Int) -> [String: Any] {
        guard let type = Self.historyMetricType(from: metric),
              let history = HealthKitManager.shared.metricSummaries[type]?.history,
              !history.isEmpty else {
            return ["available": false, "metric": metric,
                    "reason": "No HealthKit history for this metric."]
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        var byDay: [Date: Double] = [:]
        for sample in history.sorted(by: { $0.date < $1.date }) where sample.date >= cutoff {
            byDay[cal.startOfDay(for: sample.date)] = sample.value
        }
        let daily = byDay.sorted { $0.key < $1.key }
        guard let first = daily.first?.value, let last = daily.last?.value else {
            return ["available": false, "metric": metric, "days": days,
                    "reason": "No samples in the requested window."]
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let values = daily.map(\.value)
        return ["available": true,
                "metric": metric,
                "unit": type.unit,
                "days": days,
                "daily": daily.map { ["date": f.string(from: $0.key), "value": Self.round1($0.value)] },
                "avg": Self.round1(values.reduce(0, +) / Double(values.count)),
                "min": Self.round1(values.min() ?? 0),
                "max": Self.round1(values.max() ?? 0),
                "latest": Self.round1(last),
                "change_pct": first == 0 ? 0 : Self.round1((last - first) / first * 100)]
    }

    /// Resolves the loose metric token Gemini passes to `get_metric_history`.
    /// Accepts the documented snake_case names plus common aliases.
    private static func historyMetricType(from raw: String) -> HealthMetricType? {
        switch raw.lowercased() {
        case "steps": return .steps
        case "heart_rate", "heartrate", "heart": return .heartRate
        case "active_energy", "activeenergy", "calories": return .activeEnergy
        case "sleep": return .sleep
        case "distance": return .distance
        case "hrv": return .hrv
        case "hydration", "water": return .hydration
        case "resting_heart_rate", "restingheartrate", "resting_hr", "rhr": return .restingHeartRate
        case "body_mass", "bodymass", "weight": return .bodyMass
        case "flights_climbed", "flightsclimbed", "flights": return .flightsClimbed
        case "exercise_minutes", "exerciseminutes": return .exerciseMinutes
        case "stand_hours", "standhours": return .standHours
        case "mindful_minutes", "mindfulminutes": return .mindfulMinutes
        case "oxygen_saturation", "oxygensaturation", "spo2": return .oxygenSaturation
        case "vo2_max", "vo2max": return .vo2Max
        case "resting_energy", "restingenergy", "basal_energy": return .restingEnergy
        case "walking_speed", "walkingspeed": return .walkingSpeed
        case "walking_step_length", "walkingsteplength", "step_length": return .walkingStepLength
        case "walking_double_support", "walkingdoublesupport": return .walkingDoubleSupport
        case "walking_asymmetry", "walkingasymmetry": return .walkingAsymmetry
        case "headphone_audio", "headphoneaudio": return .headphoneAudio
        default: return nil
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

    /// `get_training_plan` payload — active plan (this week, and next if
    /// authored) with per-day completed flags + adherence, or an honest
    /// "no plan set" when nothing has been authored yet via
    /// `set_training_plan`.
    private static func trainingPlanPayload() -> [String: Any] {
        guard let plan = TrainingPlanStore.shared.activePlan else {
            return ["available": false,
                    "reason": "No training plan set yet. Offer to build one when the user asks, or when they engage during a weekly review — never set one unprompted."]
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let days: [[String: Any]] = plan.days.map { d in
            [
                "date": f.string(from: d.date),
                "title": d.title,
                "detail": d.detail,
                "kind": d.kind.rawValue,
                "duration_min": d.durationMin,
                "completed": d.completed
            ]
        }
        var result: [String: Any] = [
            "available": true,
            "week_start": f.string(from: plan.weekStart),
            "days": days
        ]
        if let adherence = TrainingPlanStore.shared.adherence(for: plan.weekStart) {
            result["adherence_completed"] = adherence.completed
            result["adherence_total"] = adherence.total
            result["adherence_pct"] = Int(adherence.pct.rounded())
        }
        return result
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
        let targetsLine = Self.nutritionTargetsLine(caloriesToday: calories, proteinToday: protein)
        if log.isEmpty && calories <= 0 {
            return """
            NUTRITION TODAY (from HealthKit dietary samples)
            \(goalsLine)
            \(targetsLine)
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
            ? "\(header)\n\(totals)\n\(goalsLine)\n\(targetsLine)"
            : "\(header)\n\(totals)\n\(goalsLine)\n\(targetsLine)\n- Logged items:\n\(items)"
    }

    /// One-line summary of Astra's own (optional) protein/kcal coaching
    /// targets vs today's actual — distinct from the always-defaulted
    /// `goalsLine` above (`MacroGoals`, which silently falls back to 2000
    /// kcal/150g even if the user never touched it). Honest "none set yet"
    /// when `NutritionTargets` is empty, so Astra never implies a target
    /// exists that the user hasn't actually confirmed.
    private static func nutritionTargetsLine(caloriesToday: Double, proteinToday: Double) -> String {
        let t = NutritionTargets.shared
        guard t.proteinTargetG != nil || t.kcalTarget != nil else {
            return "- Astra's nutrition targets: none set yet — propose one via set_nutrition_targets when relevant (e.g. an evidence-based protein target for a hypertrophy goal)."
        }
        var parts: [String] = []
        if let p = t.proteinTargetG {
            let setBy = t.proteinSetBy == .user ? "user-set" : "Astra-set"
            parts.append("protein \(Int(proteinToday.rounded()))g / \(Int(p))g target (\(setBy))")
        }
        if let k = t.kcalTarget {
            let setBy = t.kcalSetBy == .user ? "user-set" : "Astra-set"
            parts.append("kcal \(Int(caloriesToday.rounded())) / \(Int(k)) target (\(setBy))")
        }
        return "- Astra's nutrition targets: " + parts.joined(separator: " · ")
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

        // Illness early-warning (multi-signal physiological strain)
        if let w = p.illnessWarning {
            lines.append("• ILLNESS EARLY-WARNING (\(w.severity.rawValue)): RHR +\(String(format: "%.1f", w.rhrDeltaBpm)) bpm vs 28-day baseline · HRV down \(String(format: "%.0f", w.hrvDropPct))% · sleep debt \(String(format: "%.1f", w.sleepDebtHours)) h — pattern held \(w.consecutiveDays) consecutive days. These are early strain signals - NEVER diagnose, suggest rest/hydration and consulting a professional if symptoms appear.")
        }

        // Cross-metric correlations (deterministic on-device Pearson)
        for c in p.correlations {
            lines.append("• Correlation: \(c.insight) (r=\(String(format: "%.2f", c.r)), \(c.sampleDays) days)")
        }

        // Periodization phase
        if let pz = p.periodization {
            let trendSign = pz.loadTrendPct >= 0 ? "+" : ""
            lines.append("• Training phase: \(pz.phase) (week \(Int(pz.weekLoad.rounded())) vs base \(Int(pz.baselineWeekLoad.rounded())) kcal-load, \(trendSign)\(String(format: "%.0f", pz.loadTrendPct))%) — \(pz.recommendation)")
        }

        // Sleep forecast (tonight's stratified estimate — evening/night only in UI but always in context)
        if let sf = p.sleepForecast {
            let deltaSign = (sf.predictedHours - sf.baselineHours) >= 0 ? "+" : ""
            let delta = String(format: "%.1f", sf.predictedHours - sf.baselineHours)
            lines.append("• Tonight's sleep forecast: ~\(String(format: "%.1f", sf.predictedHours))h vs \(String(format: "%.1f", sf.baselineHours))h baseline (\(deltaSign)\(delta)h, \(sf.deltaDriver)) — \(sf.basis)")
        }

        // Deterministic goal suggestions (28-day attainment vs current goal)
        if !p.goalSuggestions.isEmpty {
            func g(_ v: Double) -> String {
                v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
            }
            for s in p.goalSuggestions {
                lines.append("• Goal suggestion: \(s.metric.displayName) \(g(s.currentGoal)) -> \(g(s.suggestedGoal)) \(s.metric.unit) (\(s.direction), median attainment \(String(format: "%.0f", s.medianAttainmentPct))%) — \(s.rationale)")
            }
            lines.append("• Goal suggestions are advisory: propose one via the update_goal tool ONLY when the user engages with goals (asks about them, mentions a target, or responds to a suggestion). NEVER apply a goal change unprompted.")
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

    /// Mean of the last 7 days of a metric's history, counting only days
    /// with a real (> 0) sample. nil when the user has no data — callers
    /// drop the line entirely (honest "—" semantics, never a fake 0).
    private static func sevenDayAvg(_ type: HealthMetricType) -> Double? {
        guard let history = HealthKitManager.shared.metricSummaries[type]?.history else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let vals = history.filter { $0.date >= cutoff && $0.value > 0 }.map(\.value)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// STREAK & CHALLENGE block — workout-week streak + today's challenge.
    fileprivate static func streakChallengeBlock() -> String {
        let streak = StreakEngine.shared
        let challenge = ChallengeEngine.shared
        var lines: [String] = []
        lines.append("- Streak: \(streak.currentStreak) week(s) current · \(streak.longestStreak) longest · \(streak.earnedBadges.count) badge(s)")
        if let c = challenge.activeChallenge {
            let pct = Int((challenge.progress * 100).rounded())
            lines.append("- Today's challenge: \(c.title) — \(pct)% done (target \(Int(c.targetValue)) \(c.metric.unit)). \(challenge.completedChallenges.count) completed all-time.")
        } else {
            lines.append("- Today's challenge: —")
        }
        return lines.joined(separator: "\n")
    }

    /// BODY & GAIT 7-DAY block — only metrics that actually have data.
    fileprivate static func bodyGaitBlock() -> String {
        var parts: [String] = []
        if let w = HealthKitManager.shared.metricSummaries[.bodyMass]?.currentValue, w > 0 {
            parts.append("weight \(String(format: "%.1f", w)) kg (latest)")
        }
        if let s = sevenDayAvg(.walkingSpeed) {
            let speedDisp = LocaleUnits.speedDisplay(fromMph: s)
            parts.append("walking speed \(String(format: "%.1f", speedDisp.value)) \(speedDisp.unit) avg")
        }
        if let a = sevenDayAvg(.walkingAsymmetry) {
            parts.append("asymmetry \(String(format: "%.1f", a))% avg")
        }
        return parts.isEmpty ? "—" : "- " + parts.joined(separator: " · ")
    }

    /// HYDRATION & MINDFUL 7-DAY block — daily averages over logged days.
    fileprivate static func hydrationMindfulBlock() -> String {
        var parts: [String] = []
        if let h = sevenDayAvg(.hydration) {
            parts.append("hydration \(String(format: "%.1f", h)) L/day")
        }
        if let m = sevenDayAvg(.mindfulMinutes) {
            parts.append("mindful \(String(format: "%.0f", m)) min/day")
        }
        return parts.isEmpty ? "—" : "- " + parts.joined(separator: " · ") + " (avg of days with data)"
    }

    /// RECENT WORKOUTS block — last 3 from the 28-day HealthKit window.
    fileprivate static func recentWorkoutsBlock() -> String {
        let workouts = HealthKitManager.shared.recentWorkouts28
        guard !workouts.isEmpty else { return "None recorded in the last 28 days." }
        let f = DateFormatter()
        f.dateFormat = "EEE MM/dd"
        return workouts
            .sorted { $0.startDate > $1.startDate }
            .prefix(3)
            .map { w in
                let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                let kcalStr = kcal.map { " · \(Int($0)) kcal" } ?? ""
                return "- \(Self.workoutLabel(w.workoutActivityType)) \(f.string(from: w.startDate)) — \(Int(w.duration / 60)) min\(kcalStr)"
            }
            .joined(separator: "\n")
    }

    /// TRAINING LOAD one-liner — acute (7d) vs chronic (28d) load + ACWR +
    /// zone label, read from the shared TrainingLoadEngine (populated by
    /// HealthKitManager after each workout fetch). Empty string until the
    /// engine has computed or when the user has no workouts (block omitted).
    fileprivate static func trainingLoadBlock() -> String {
        let engine = TrainingLoadEngine.shared
        let acute = engine.acuteLoad
        let chronic = engine.chronicLoad
        guard acute > 0 || chronic > 0 else { return "" }
        let cal = Calendar.current
        let cutoff7 = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))
            ?? Date().addingTimeInterval(-6 * 86_400)
        let minutes7 = HealthKitManager.shared.recentWorkouts28
            .filter { $0.startDate >= cutoff7 }
            .reduce(0.0) { $0 + $1.duration / 60.0 }
        return "- Acute (7d) \(Int(acute.rounded())) kcal-load/day vs chronic (28d) \(Int(chronic.rounded())) — ACWR \(String(format: "%.2f", engine.acwr)) (\(engine.acwrZone.label)). \(Int(minutes7.rounded())) workout min last 7d."
    }

    /// TRAINING PLAN one-liner — active Astra-authored plan snapshot (days
    /// completed, adherence this week, next planned session) so Astra has
    /// "recent adherence" grounding without a get_training_plan round trip
    /// on every turn. Empty string when no plan exists (block omitted) —
    /// get_training_plan is still available for the full per-day detail.
    fileprivate static func trainingPlanBlock() -> String {
        guard let plan = TrainingPlanStore.shared.activePlan else { return "" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trainingDays = plan.days.filter { $0.kind != .rest }
        let completed = trainingDays.filter { $0.completed }.count
        let next = plan.days
            .filter { $0.kind != .rest && !$0.completed && cal.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
            .first
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"
        var line = "- Active plan from \(f.string(from: plan.weekStart)): \(completed)/\(trainingDays.count) planned sessions completed"
        if let adherence = TrainingPlanStore.shared.adherence(for: plan.weekStart) {
            line += " (\(Int(adherence.pct.rounded()))% adherence this week)"
        }
        if let next {
            line += ". Next planned: \(next.title) — \(f.string(from: next.date))"
        } else if !trainingDays.isEmpty, completed == trainingDays.count {
            line += ". All planned sessions done!"
        }
        return line
    }

    /// HR ZONES one-liner — the five personalised Karvonen zone ranges from
    /// HeartRateZoneCalculator, same thresholds the Workout Analytics view
    /// shows. Caller gates injection on the user actually having HR data.
    fileprivate static func hrZonesLine(userAge: Int) -> String {
        let t = HeartRateZoneCalculator.shared.makeThresholds(userAge: userAge)
        let ranges = HRZone.allCases.map { zone -> String in
            let lo = Int(t.lowerBPM(for: zone).rounded())
            let hi = zone == .zone5 ? "\(Int(t.maxHR.rounded()))+" : "\(Int(t.upperBPM(for: zone).rounded()))"
            return "Z\(zone.rawValue) \(lo)–\(hi)"
        }
        return "- \(ranges.joined(separator: " · ")) bpm (Karvonen — RHR \(Int(t.restingHR.rounded())), max \(Int(t.maxHR.rounded()))). Use these for zone targets."
    }

    /// CYCLE block — last period start + median cycle length from HealthKit
    /// menstrual-flow days (last 60 days). A period start = a flow day with no
    /// flow the previous day. Median needs ≥2 starts, else just the last
    /// start. Empty string when no flow samples (block omitted).
    fileprivate static func cycleBlock() -> String {
        let flowDays = HealthKitManager.shared.menstrualFlowDays60
        guard !flowDays.isEmpty else { return "" }
        let cal = Calendar.current
        let sorted = flowDays.map { cal.startOfDay(for: $0) }.sorted()
        let daySet = Set(sorted)
        let starts = sorted.filter { d in
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { return true }
            return !daySet.contains(cal.startOfDay(for: prev))
        }
        guard let lastStart = starts.last else { return "" }
        let daysAgo = cal.dateComponents([.day], from: lastStart, to: cal.startOfDay(for: Date())).day ?? 0
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        var line = "- Last period started \(f.string(from: lastStart)) (\(daysAgo) day\(daysAgo == 1 ? "" : "s") ago)"
        if starts.count >= 2 {
            let gaps = zip(starts.dropFirst(), starts)
                .compactMap { cal.dateComponents([.day], from: $1, to: $0).day }
                .sorted()
            if !gaps.isEmpty {
                let mid = gaps.count / 2
                let median = gaps.count % 2 == 1
                    ? Double(gaps[mid])
                    : Double(gaps[mid - 1] + gaps[mid]) / 2
                line += "; median cycle ≈ \(Int(median.rounded())) days"
            }
        }
        line += ". State only what this data shows — never speculate about phase, fertility, or pregnancy."
        return line
    }

    /// SYMPTOMS one-liner — up to 5 most recent HealthKit symptom entries
    /// from the last 14 days. Empty string when none (block omitted).
    fileprivate static func symptomsBlock() -> String {
        let symptoms = HealthKitManager.shared.recentSymptoms14
        guard !symptoms.isEmpty else { return "" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let parts = symptoms.suffix(5).reversed().map { s -> String in
            let ago = cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: today).day ?? 0
            let when = ago <= 0 ? "today" : "\(ago)d ago"
            return "\(s.name) (\(s.severity), \(when))"
        }
        return "SYMPTOMS (14d, from HealthKit): " + parts.joined(separator: ", ")
            + ". Factor these into coaching intensity and recovery advice — NEVER diagnose; suggest a clinician if persistent or severe."
    }

    /// Coarse activity label — mirrors HealthKitManager.activityCategory
    /// (private there), kept tiny for prompt lines.
    private static func workoutLabel(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Run"
        case .walking, .hiking: return "Walk"
        case .cycling: return "Cycle"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining: return "Strength"
        case .yoga, .mindAndBody, .pilates, .flexibility, .barre: return "Yoga"
        case .highIntensityIntervalTraining, .coreTraining: return "HIIT"
        case .swimming, .waterFitness, .waterSports: return "Swim"
        default: return "Workout"
        }
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
        let outcome = await withTimeout(seconds: 60) {
            await self.executeWriteTool(call)
        } ?? WriteToolOutcome(false, error: "Timed out after 60 seconds — please try again.")
        messages[idx].toolStatus = outcome.success ? .done : .failed
        // Merge the failure reason (and/or a non-failure `note`) into
        // toolResultJSON so GatewayChatClient's history serializer folds it
        // into this tool's functionResponse (`response.merge(parsed)`) —
        // Astra receives the real `error` string instead of the generic
        // "The action failed to execute" summary, and ToolCards.swift can
        // render the same reason (or note) on the card itself.
        var resultFields: [String: Any] = [:]
        if let error = outcome.error { resultFields["error"] = error }
        if let note = outcome.note { resultFields["note"] = note }
        if !resultFields.isEmpty, let json = encodeJSON(resultFields) {
            messages[idx].toolResultJSON = json
        }
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
    /// The history serializer in GatewayChatClient injects the matching
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

        // Tool-loop continuation of an existing turn — reuse the pinned
        // snapshot from that turn's initial `sendMessage` so this request's
        // systemInstruction is byte-identical to the prior one in the loop.
        let systemInstruction = await systemInstructionForTurn(refresh: false)
        let history = messages

        do {
            let stream = await GatewayChatClient.shared.streamGenerateContent(
                prompt: "",
                history: history,
                systemInstruction: systemInstruction,
                imageData: nil,
                imageMimeType: "image/jpeg"
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
                text: Self.errorBubbleText(
                    error,
                    fallback: "Couldn't reach the coach to finish that step. Tap Retry to try again."
                ),
                isError: true
            ))
        }
    }

    /// Result of a confirmed write-tool execution. `error`, when present, is
    /// the EXACT reason (a HealthKit access-denial message or the thrown
    /// error's `localizedDescription`) — never an invented string. Stashed
    /// onto the message's `toolResultJSON` on failure so it merges into the
    /// tool's `functionResponse` (see GatewayChatClient's history serializer)
    /// and Astra can quote the real cause instead of guessing.
    private struct WriteToolOutcome: Sendable {
        let success: Bool
        let error: String?
        /// Non-failure informational note (e.g. "calendar events skipped —
        /// permission denied") merged into the functionResponse under a
        /// separate `note` key so it never trips ToolCards' failure-detail
        /// UI or reads to the model as an actual write failure. Only
        /// `set_training_plan` uses this today.
        let note: String?
        init(_ success: Bool, error: String? = nil, note: String? = nil) {
            self.success = success
            self.error = error
            self.note = note
        }
    }

    /// Builds the HealthKit sample date for a backdated log: `daysAgo` days
    /// before today (clamped 0-7), pinned to 12:00 local so the entry reads
    /// as "sometime that day" rather than masquerading as the current
    /// instant. `daysAgo <= 0` returns `Date()` unchanged (today, same-day
    /// behavior is byte-identical to before backdating existed).
    private static func dateForDaysAgo(_ daysAgo: Int) -> Date {
        let clamped = max(0, min(daysAgo, 7))
        guard clamped > 0 else { return Date() }
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -clamped, to: Date()) else { return Date() }
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? day
    }

    private func executeWriteTool(_ call: ToolCall) async -> WriteToolOutcome {
        switch call {
        case .logFood(let name, let cal, let p, let c, let f, _, _, _, _, let est, let conf, let daysAgo):
            let sampleDate = Self.dateForDaysAgo(daysAgo)
            let outcome = await HealthKitManager.shared.logFoodDetailed(
                name: name, calories: cal, protein: p, carbs: c, fat: f,
                date: sampleDate, isEstimate: est, confidence: conf
            )
            if outcome.succeeded {
                // Refresh dietary state so the next Coach turn AND the Home
                // Meals card AND the Health Meter recompute pick up the new
                // entry immediately — without waiting for a full HK refetch.
                // (Only meaningful for today's entries; a backdated entry
                // doesn't move today's totals, but the refresh is cheap and
                // keeps todayFoodLog/dietaryCaloriesToday consistent either way.)
                await HealthKitManager.shared.refreshDietaryNow()
            }
            return WriteToolOutcome(outcome.succeeded, error: outcome.failureReason)
        case .logWater(let ml, let daysAgo):
            guard ml > 0 else {
                return WriteToolOutcome(false, error: "Amount must be greater than 0 ml.")
            }
            let sampleDate = Self.dateForDaysAgo(daysAgo)
            let outcome = await HealthKitManager.shared.logMetricValueDetailed(
                type: .hydration, value: ml / 1000.0, start: sampleDate, end: sampleDate
            )
            return WriteToolOutcome(outcome.succeeded, error: outcome.failureReason)
        case .addReminder(let title, let due, _):
            return WriteToolOutcome(EventKitManager.shared.addReminder(title: title, dueDate: due))
        case .addCalendarEvent(let title, let start, let end, let notes):
            return WriteToolOutcome(EventKitManager.shared.addEvent(title: title, startDate: start, endDate: end, notes: notes))
        case .updateReminder(let id, let title, let due, let notes):
            return WriteToolOutcome(await EventKitManager.shared.updateAppReminder(id: id, title: title, dueDate: due, notes: notes))
        case .updateCalendarEvent(let id, let title, let start, let end, let notes):
            return WriteToolOutcome(EventKitManager.shared.updateAppEvent(id: id, title: title, startDate: start, endDate: end, notes: notes))
        case .deleteReminder(let id, _):
            return WriteToolOutcome(EventKitManager.shared.deleteAppReminder(id: id))
        case .deleteCalendarEvent(let id, _):
            return WriteToolOutcome(EventKitManager.shared.deleteAppEvent(id: id))
        case .updateFoodLog(let id, let name, let cal, let p, let c, let f):
            return WriteToolOutcome(await HealthKitManager.shared.updateAppFood(
                id: id, name: name, calories: cal, protein: p, carbs: c, fat: f
            ))
        case .deleteFoodLog(let id, _):
            return WriteToolOutcome(await HealthKitManager.shared.deleteAppFood(id: id))
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
            return WriteToolOutcome(AstraWidgetStore.shared.add(widget))
        case .updateWidget(let id, let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            guard let uuid = UUID(uuidString: id) else { return WriteToolOutcome(false, error: "Invalid widget id.") }
            let layoutEnum: WidgetLayout? = layout.flatMap { WidgetLayout(rawValue: $0) }
                ?? (blocks != nil ? .composed : nil)
            return WriteToolOutcome(AstraWidgetStore.shared.update(
                id: uuid,
                title: title, icon: icon, colorName: color, layout: layoutEnum,
                headline: headline, body: body, bullets: bullets,
                metricRef: metricRef, goalValue: goalValue, blocks: blocks
            ))
        case .deleteWidget(let id, _):
            guard let uuid = UUID(uuidString: id) else { return WriteToolOutcome(false, error: "Invalid widget id.") }
            return WriteToolOutcome(AstraWidgetStore.shared.remove(id: uuid))
        case .updateGoal(let metric, let value):
            guard let type = Self.historyMetricType(from: metric),
                  type.isUserConfigurableGoal,
                  value > 0 else {
                return WriteToolOutcome(false, error: "'\(metric)' isn't a user-configurable goal, or the value was invalid.")
            }
            let clamped: Double = {
                guard let range = type.goalRange else { return value }
                return min(max(value, range.min), range.max)
            }()
            HealthKitManager.shared.setGoal(clamped, for: type)
            return WriteToolOutcome(true)
        case .setDateOfBirth(let date):
            let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? -1
            guard age >= 5, age <= 120 else {
                return WriteToolOutcome(false, error: "That date puts the user's age at \(age) years, outside the plausible 5-120 range — nothing was saved. Double-check the birth date with the user.")
            }
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "athlete_dob")
            return WriteToolOutcome(true)
        case .setNutritionTargets(let proteinG, let kcal):
            if let p = proteinG, !NutritionTargets.proteinRange.contains(p) {
                return WriteToolOutcome(false, error: "Protein target \(Int(p))g is outside the sane range (\(Int(NutritionTargets.proteinRange.lowerBound))-\(Int(NutritionTargets.proteinRange.upperBound))g) — nothing was saved.")
            }
            if let k = kcal, !NutritionTargets.kcalRange.contains(k) {
                return WriteToolOutcome(false, error: "Calorie target \(Int(k)) kcal is outside the sane range (\(Int(NutritionTargets.kcalRange.lowerBound))-\(Int(NutritionTargets.kcalRange.upperBound)) kcal) — nothing was saved.")
            }
            guard proteinG != nil || kcal != nil else {
                return WriteToolOutcome(false, error: "No target values supplied — nothing was saved.")
            }
            NutritionTargets.shared.setTargets(proteinG: proteinG, kcal: kcal, setBy: .astra)
            return WriteToolOutcome(true)
        case .setTrainingPlan(let weekStart, let daysArgs):
            return Self.executeSetTrainingPlan(weekStart: weekStart, daysArgs: daysArgs)
        case .markWorkoutDone(let date):
            guard TrainingPlanStore.shared.markCompleted(date: date) else {
                return WriteToolOutcome(false, error: "No planned session found on that date — check get_training_plan for the current schedule.")
            }
            return WriteToolOutcome(true)
        case .showMetricChart, .showComparisonChart, .renderCard,
             .listReminders, .listCalendarEvents, .getPredictions,
             .listFoodLog, .listWidgets, .updateNotes, .getSleepPattern,
             .getMetricHistory, .getSleepSessions,
             .rememberFact, .forgetFact, .updateProfile, .getProfile,
             .getTrainingPlan:
            // These never actually route through executeWriteTool — they're
            // producesPayload/no-confirmation tools dispatched via
            // executeReadTool / autoExecuteReadTool instead. Kept here only
            // so this switch stays exhaustive.
            return WriteToolOutcome(true)
        }
    }

    /// `set_training_plan` execution — validates the proposed week (1-14
    /// days, dates inside a 14-day window starting `weekStart`, kind ∈
    /// {strength, cardio, mobility, rest}, duration 10-240 min), tears down
    /// calendar events the app created for whatever plan is being replaced
    /// (only ones it made, by stored id), writes a fresh event per non-rest
    /// day (skipped honestly via `note` when calendar access isn't granted —
    /// the plan itself still saves), then persists the new plan. Runs
    /// synchronously inside `confirmToolCall`'s 60s timeout.
    private static func executeSetTrainingPlan(weekStart weekStartRaw: Date,
                                               daysArgs: [ToolCall.PlannedDayArg]) -> WriteToolOutcome {
        let cal = Calendar.current
        // Snap to Monday: the store's adherence math and the card's week
        // chips both anchor on Monday-of-week; an unenforced model-supplied
        // weekStart (the prompt only ASKS for Monday) would desync them.
        let weekStart = TrainingPlanStore.mondayOfWeek(containing: cal.startOfDay(for: weekStartRaw))

        guard !daysArgs.isEmpty, daysArgs.count <= 14 else {
            return WriteToolOutcome(false, error: "A training plan must cover 1-14 days — got \(daysArgs.count). Nothing was saved.")
        }
        // Reject plans anchored in the wrong year/era — a live plan landed on
        // July 2025 because the model guessed the year. Window: last week
        // through three weeks out.
        let today = cal.startOfDay(for: Date())
        if let earliest = cal.date(byAdding: .day, value: -7, to: today),
           let latest = cal.date(byAdding: .day, value: 21, to: today),
           !(earliest...latest).contains(weekStart) {
            let df2 = DateFormatter(); df2.dateFormat = "EEEE, d MMMM yyyy"
            return WriteToolOutcome(false, error: "week_start \(df.string(from: weekStart)) is outside the plannable window. TODAY is \(df2.string(from: Date())) — re-emit the plan with dates in the current week/year. Nothing was saved.")
        }
        guard let windowEnd = cal.date(byAdding: .day, value: 13, to: weekStart) else {
            return WriteToolOutcome(false, error: "Could not resolve the plan's date window. Nothing was saved.")
        }

        let df = DateFormatter(); df.dateStyle = .medium
        var parsedDays: [TrainingPlanStore.PlannedDay] = []
        for arg in daysArgs {
            guard let kind = TrainingPlanStore.PlannedDay.Kind(rawValue: arg.kind.lowercased()) else {
                return WriteToolOutcome(false, error: "Unknown day kind '\(arg.kind)' for '\(arg.title)' — use strength, cardio, mobility, or rest. Nothing was saved.")
            }
            let dayStart = cal.startOfDay(for: arg.date)
            guard dayStart >= weekStart, dayStart <= windowEnd else {
                return WriteToolOutcome(false, error: "\(df.string(from: arg.date)) falls outside the plan's 14-day window starting \(df.string(from: weekStart)). Nothing was saved.")
            }
            guard (10...240).contains(arg.durationMin) else {
                return WriteToolOutcome(false, error: "Duration \(arg.durationMin) min for '\(arg.title)' is outside the sane 10-240 min range. Nothing was saved.")
            }
            let detail = String(arg.detail.prefix(700))
            parsedDays.append(TrainingPlanStore.PlannedDay(
                date: dayStart, title: arg.title, detail: detail,
                kind: kind, durationMin: arg.durationMin
            ))
        }
        parsedDays.sort { $0.date < $1.date }

        // Tear down whatever calendar events the OLD plan created — only
        // ones this app made (stored ids) — before the store is overwritten.
        if let oldPlan = TrainingPlanStore.shared.activePlan {
            for oldDay in oldPlan.days {
                if let eventId = oldDay.calendarEventId {
                    _ = EventKitManager.shared.deleteAppEvent(id: eventId)
                }
            }
        }

        // Create a Calendar event per non-rest day at a sensible default
        // time (6 PM local) — honest skip when access isn't granted; the
        // plan still saves either way.
        var calendarNote: String? = nil
        if !EventKitManager.shared.calendarsGranted {
            calendarNote = "Calendar access isn't granted, so sessions weren't added to your calendar — enable it in Settings to have them show up automatically. The plan itself still saved."
        } else {
            var wanted = 0, created = 0
            for idx in parsedDays.indices where parsedDays[idx].kind != .rest {
                wanted += 1
                let day = parsedDays[idx]
                guard let startDate = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day.date) else { continue }
                let endDate = cal.date(byAdding: .minute, value: day.durationMin, to: startDate) ?? startDate
                if let eventId = EventKitManager.shared.addEventReturningId(
                    title: day.title, startDate: startDate, endDate: endDate, notes: day.detail
                ) {
                    parsedDays[idx].calendarEventId = eventId
                    created += 1
                }
            }
            // Honest partial-failure note: a green "synced" line over silently
            // missing events would be a fake write.
            if created < wanted {
                calendarNote = "Only \(created) of \(wanted) sessions could be added to your calendar — the rest failed to save as events. The plan itself is fully saved."
            }
        }

        let plan = TrainingPlanStore.TrainingPlan(weekStart: weekStart, days: parsedDays)
        TrainingPlanStore.shared.upsert(plan)
        return WriteToolOutcome(true, note: calendarNote)
    }

    /// "Tuesday, 21 July 2026" — the model has NO reliable sense of the
    /// current date (a live plan landed on July 2025 because nothing in the
    /// prompt said the year). Lives in LIVE CONTEXT: changes daily, so it
    /// must not sit in the cached static head.
    static func todayLine() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: Date())
    }

    /// Behavioral contract for the Profile → Coach personality picker. The
    /// bare label ("Friendly") was too weak a signal against the strict
    /// OUTPUT FORMAT rules — each style needs explicit directives. Static
    /// prompt section: changes only when the user changes the picker (one
    /// cache invalidation, then stable). Shared with MorningBriefEngine.
    static func personalityDirective(_ style: String) -> String {
        switch style {
        case "Friendly":
            return "warm and encouraging — open with genuine acknowledgment of effort, celebrate wins explicitly, frame pushes as invitations (\"let's try…\"). Warmth must never dilute honesty about the numbers."
        case "Concise":
            return "minimum words — numbers and instructions only, no filler sentences, single-line answers whenever the question allows. Brevity overrides the usual section formatting for simple asks."
        case "Motivational":
            return "high energy — tie every reply to the user's goals and momentum, end advisory replies with a challenge, conviction without fluff. Never manufacture hype the data doesn't support."
        default: // "Direct"
            return "no pleasantries, no cheerleading — lead with the number and the instruction, state trade-offs plainly, skip softening language."
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

        // Retrying the SAME turn's original message — reuse the turn's
        // pinned snapshot (falls back to a fresh build if none is cached,
        // e.g. the app relaunched mid-error) rather than rebuilding, so the
        // retried request's prefix still matches whatever the failed attempt
        // sent moments earlier.
        let systemInstruction = await systemInstructionForTurn(refresh: false)
        let prompt = user.text.isEmpty ? "What is this? Give me full details." : user.text

        do {
            let stream = await GatewayChatClient.shared.streamGenerateContent(
                prompt: prompt,
                history: history,
                systemInstruction: systemInstruction,
                imageData: user.imageData,
                imageMimeType: "image/jpeg"
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
                text: Self.errorBubbleText(
                    error,
                    fallback: "Still couldn't reach the coach. Check your network and try again."
                ),
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
        guard !isViewingArchivedSession else { return false }
        return messages.contains { $0.role == .user }
    }

    /// Historically set while viewing a read-only replay of a past session,
    /// so it wouldn't be re-archived as a duplicate. `openSession(_:)` now
    /// always reopens sessions as fully live (never a replay), so this stays
    /// `false` in current flows — kept as a guard for any future read-only
    /// viewing mode rather than deleted outright.
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

    /// Archive the current live conversation (if it has any real content),
    /// then load `id` from the archive back into the LIVE chat — not a
    /// read-only replay. The reopened conversation is immediately editable
    /// and archivable again, and a relaunch resumes it exactly like any
    /// other live session. It's also removed from the archive list at the
    /// same time, so continuing it and later archiving again (new chat,
    /// background, leave) inserts one clean entry instead of leaving a
    /// stale duplicate of the same conversation behind.
    ///
    /// No-op — returns `false` — while a reply is streaming, so the chat
    /// selector can't race a live stream against a full message swap. The
    /// caller (ChatView) also disables the sheet's rows while
    /// `isGenerating`, this is the defensive second gate.
    @discardableResult
    public func openSession(_ id: UUID) -> Bool {
        guard !isGenerating else { return false }
        guard let session = ChatHistoryStore.shared.session(id: id) else { return false }
        archiveCurrent()
        // Clear the OLD live slot (JSON + any per-message image blobs) before
        // swapping in a different session's messages. `saveLive` only ever
        // ADDS image keys for the session it's given — it never prunes ones
        // left over from a completely different previous live session, so
        // skipping this leaks a chat_live_img_<uuid> blob per photo turn in
        // whatever was live before this call.
        ChatHistoryStore.shared.clearLive()
        let restored = session.messages.map { $0.toChatMessage() }
        messages = restored.isEmpty
            ? [ChatMessage(role: .model, text: Self.greetingText)]
            : restored
        isViewingArchivedSession = false
        currentStreamingText = ""
        persistLiveSnapshot()
        // Only remove the reopened session from the archive AFTER it's safely
        // persisted as the live session. If the app is killed in between, the
        // worst case is a recoverable duplicate (still in the archive AND
        // live) instead of the conversation being lost outright.
        ChatHistoryStore.shared.delete(id: id)
        return true
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
            let unitStr: String
            if type == .steps || type == .activeEnergy {
                valStr = String(format: "%.0f", item.value)
                unitStr = type.unit
            } else if type == .heartRate {
                valStr = String(format: "%.0f", item.value)
                unitStr = type.unit
            } else if type == .distance {
                let disp = LocaleUnits.distanceDisplay(fromMiles: item.value)
                valStr = String(format: "%.2f", disp.value)
                unitStr = disp.unit
            } else if type == .walkingSpeed {
                let disp = LocaleUnits.speedDisplay(fromMph: item.value)
                valStr = String(format: "%.1f", disp.value)
                unitStr = disp.unit
            } else if type == .walkingStepLength {
                let disp = LocaleUnits.stepLengthDisplay(fromInches: item.value)
                valStr = String(format: "%.0f", disp.value)
                unitStr = disp.unit
            } else {
                valStr = String(format: "%.1f", item.value)
                unitStr = type.unit
            }
            return "\(dateStr): \(valStr) \(unitStr)"
        }.joined(separator: ", ")
    }
    
    /// The system instruction built at the start of the current user-initiated
    /// turn. Reused byte-for-byte by every follow-up request in that turn's
    /// tool-call loop (`sendFollowup` / `autoExecuteReadTool` chains, and the
    /// tool-followup branch of `retryLast`).
    ///
    /// Why this matters for Gemini's implicit prompt caching: a request's
    /// cacheable prefix is `systemInstruction + tools + contents` and ANY
    /// changed byte invalidates everything after it. `buildSystemInstruction`
    /// now emits a STATIC-first / LIVE-CONTEXT-last shape so the prefix is
    /// stable turn-to-turn, but a tool-call loop fires MULTIPLE requests for
    /// the SAME user turn (initial send → tool call → functionResponse
    /// follow-up → maybe another tool call → …). If each of those requests
    /// rebuilt the system instruction from scratch, the LIVE CONTEXT tail
    /// (Date()-derived lines, HealthKit snapshots that can shift mid-loop)
    /// would differ request-to-request, breaking the cache INSIDE a single
    /// turn — the one place caching should be a guaranteed win, since the
    /// only thing actually growing between those requests is `contents`.
    /// Caching the whole string once per turn also avoids re-running
    /// `HealthKitManager.refreshIfStale` on every follow-up (the double-fetch
    /// `predictionsPayload()` already warns about above).
    private var currentTurnSystemInstruction: String?

    /// Returns the cached instruction for the in-flight turn, or builds
    /// (and caches) a fresh one. Pass `refresh: true` only at the start of a
    /// NEW user-initiated turn (a fresh `sendMessage`) so the LIVE CONTEXT
    /// tail picks up this turn's real data; every request that continues an
    /// EXISTING turn's tool loop should pass `refresh: false` to reuse the
    /// turn's pinned snapshot. Falls back to building fresh regardless of
    /// `refresh` when nothing is cached yet (defensive — shouldn't normally
    /// happen, since every entry point that can start a loop populates the
    /// cache first).
    private func systemInstructionForTurn(refresh: Bool) async -> String {
        if !refresh, let cached = currentTurnSystemInstruction {
            return cached
        }
        let built = await buildSystemInstruction()
        currentTurnSystemInstruction = built
        return built
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

        // -- Compact engagement / body / workout blocks -----------------------
        let streakChallenge = Self.streakChallengeBlock()
        let bodyGait        = Self.bodyGaitBlock()
        let hydrationMindful = Self.hydrationMindfulBlock()
        let recentWorkouts  = Self.recentWorkoutsBlock()

        // -- LIVE conditional blocks: training load / HR zones / cycle / symptoms --
        // Each omits itself entirely when there's no data (token hygiene). All
        // four are derived from today's HealthKit state and/or Date(), so —
        // unlike the memory blocks below — they belong in the LIVE CONTEXT
        // tail, not the cacheable STATIC run: see the prefix-caching note on
        // `buildSystemInstruction` for why the split matters.
        let ageYears: Int = dobDate.map {
            Calendar.current.dateComponents([.year], from: $0, to: Date()).year ?? 30
        } ?? 30
        var liveConditionalBlocks: [String] = []
        let trainingLoad = Self.trainingLoadBlock()
        if !trainingLoad.isEmpty {
            liveConditionalBlocks.append("TRAINING LOAD (28-day window — same math as the Workout Analytics card)\n\(trainingLoad)")
        }
        let trainingPlan = Self.trainingPlanBlock()
        if !trainingPlan.isEmpty {
            liveConditionalBlocks.append("TRAINING PLAN (Astra-authored — get_training_plan / set_training_plan / mark_workout_done)\n\(trainingPlan)")
        }
        if hk.hasWatchClassData || rhr > 0 {
            liveConditionalBlocks.append("HR ZONES (personalised)\n\(Self.hrZonesLine(userAge: ageYears))")
        }
        let cycle = Self.cycleBlock()
        if !cycle.isEmpty {
            liveConditionalBlocks.append("CYCLE (from HealthKit menstrual-flow samples, last 60 days)\n\(cycle)")
        }
        let symptoms = Self.symptomsBlock()
        if !symptoms.isEmpty {
            liveConditionalBlocks.append(symptoms)
        }
        let liveConditionalSection = liveConditionalBlocks.isEmpty
            ? ""
            : "\n" + liveConditionalBlocks.joined(separator: "\n\n") + "\n"

        // -- STATIC personalization: structured long-term memory + legacy notes --
        // Unlike the four blocks above, these change only when the MODEL ITSELF
        // calls remember_fact / update_profile / update_notes — rare relative to
        // the once-per-turn cadence of live HealthKit data — so they're
        // "static-enough" to live in the cacheable STATIC run instead of LIVE
        // CONTEXT. `AstraMemoryStore.renderForSystemPrompt()`'s own ordering is
        // deterministic (profile sections walked via `Section.allCases`, facts
        // grouped into a dictionary but re-emitted by iterating
        // `Category.allCases` rather than the dictionary itself — verified, no
        // fix needed) so re-rendering it turn to turn won't itself churn bytes.
        // Only injected when the master toggle is on AND there's actually
        // something to say, so a fresh install / opted-out user doesn't pay for
        // an empty heading.
        let memoryStore = AstraMemoryStore.shared
        var staticMemoryBlocks: [String] = []
        var structuredMemoryShown = false
        if memoryStore.isEnabled {
            let rendered = memoryStore.renderForSystemPrompt()
            if !rendered.isEmpty {
                staticMemoryBlocks.append("ASTRA'S MEMORY OF THIS USER (built by you via remember_fact / update_profile — treat as gospel, keep it current)\n\(rendered)")
                structuredMemoryShown = true
            }
        }
        // Legacy cross-session notes (astra_notes, written by update_notes) —
        // gated on the SAME master toggle so turning memory off in Settings
        // silences this path too, not just the structured one. Once
        // structured memory has real content it fully supersedes this block
        // (redundant otherwise — see the precedence line in TOOLS below), so
        // this only ever falls back to legacy notes while the structured
        // store is still empty.
        if memoryStore.isEnabled, !structuredMemoryShown {
            let savedNotes = UserDefaults.standard.string(forKey: "astra_notes") ?? ""
            let notesBlock = savedNotes.isEmpty
                ? "No notes yet. Use update_notes silently when you learn something lasting."
                : savedNotes
            staticMemoryBlocks.append("YOUR MEMORY (cross-session notes written by you via update_notes — treat as gospel for personalisation)\n\(notesBlock)")
        }
        let staticMemorySection = staticMemoryBlocks.isEmpty
            ? ""
            : "\n" + staticMemoryBlocks.joined(separator: "\n\n") + "\n"

        // -- 7-day histories --------------------------------------------------
        let stepsHistory = historySummary(for: .steps)
        let calsHistory  = historySummary(for: .activeEnergy)
        let sleepHistory = historySummary(for: .sleep)
        let distHistory  = historySummary(for: .distance)
        let hrHistory    = historySummary(for: .heartRate)
        let rhrHistory   = historySummary(for: .restingHeartRate)
        let hrvHistory   = historySummary(for: .hrv)

        let instructions = """
        You are "Astra", an elite, personalized fitness and wellness companion grounded in the user's real Apple Health data. Stay confident, encouraging, concise.

        USER PROFILE
        - Name: \(name)
        - Sex: \(sexLabel)
        - DOB: \(dobStr) (age \(age))
        - Height: \(heightCmStr) cm / \(heightIn) in
        - Weight: \(weightKgStr) kg / \(weightLb) lb
        - Blood type: \(bloodLabel)
        - Coach style: \(coachPer) — \(Self.personalityDirective(coachPer))
        - Training goals: \(goalsRaw.isEmpty ? "none set" : goalsRaw)

        MEDICAL PROFILE (from HealthKit clinical records when the user has linked a provider; otherwise empty. "None known" means we don't have a record — never confuse with "the user has none.")
        - Allergies: \(allergiesStr)
        - Conditions: \(conditionsStr)
        - Medications: \(medicationsStr)\(conditionGate)

        LOCALE
        - Timezone: \(tz) — use this for ALL relative-time conversion ("tomorrow morning", "in 2 hours").
        - Units: \(unitsLabel) — never mix.
        \(staticMemorySection)
        DATA SEMANTICS
        - "—" or null = HealthKit returned no record. NEVER invent or imply a value.
        - 0 may be a genuine value depending on context: 0 steps at 6 AM is "early morning"; 0 sleep is almost certainly "not synced yet" — use judgement. When in doubt, state the ambiguity.
        - Watch-class metrics (HR, HRV, RHR, exercise/stand minutes, VO₂max, SpO₂) require a Watch / wearable. If those are all "—" you're iPhone-only — coach around steps / distance / sleep / nutrition.
        - If the user asks about a metric you don't have, say so plainly and explain how they'd enable it.

        PERSONAL BASELINES (use these BEFORE universal thresholds)
        - Compute baselines from the 7-day history in LIVE CONTEXT below. For RHR / HRV / sleep, deviation from the user's own mean matters more than any fixed cutoff.
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
        - update_notes : your legacy free-text cross-session memory blob. Superseded by the structured tools below — do NOT use it for new information; update_notes still exists only for continuity with notes saved before the migration.
        - remember_fact / forget_fact / update_profile / get_profile : structured long-term memory (successor to update_notes). remember_fact = one atomic lasting fact (goal/injury/preference/schedule/nutrition/context) per call. update_profile = rewrite a whole section (summary/goals/trainingContext/injuriesLimitations/preferences/nutritionNotes) — full replace, call get_profile first to see current content. forget_fact = remove a fact the user corrected or retracted. Skip trivia and one-off numbers HealthKit already tracks — durable personalization only. All four auto-execute silently, no confirm card. User can review, delete, or clear memory from Settings → Astra's profile of you.
        - Precedence: if structured memory (profile + facts) and the legacy notes ever disagree, structured memory wins.
        - get_sleep_pattern : on-device sleep pattern + the last 5 tracked nights with per-night motion/snore detail. Call FIRST whenever the user asks anything about sleep — "how's my sleep", "am I getting enough", "why am I tired", "is my snoring getting worse". Cite the user's personal numbers (typical bedtime, restlessness baseline, consistency) instead of generic guidance. If the user has fewer than 3 tracked nights, gently encourage them to use the Home > Sleep Tracker card before bed.
        - get_sleep_sessions : per-night detail for the last N tracked nights (1-14, default 7) — date, duration, onset latency, restlessness, snore episodes/minutes, stage hours. Call when the user asks about a specific night or wants night-by-night detail beyond the SLEEP PATTERN block / get_sleep_pattern aggregate.
        - log_food : food photos or text. Fill ALL FOUR macros (calories, protein, carbs, fat) using your nutrition training data — never default to 0 unless the food genuinely has 0 of that macro (e.g. fat in a plain banana is ~0.4g, NOT 0). Fill tags / highlights / cautions. ALWAYS set is_estimate=true and pick a confidence level (low/medium/high) — only set is_estimate=false when the user supplied exact label nutrition. For ambiguous portions ASK rather than guess. For multi-item plates, emit ONE log_food per distinct item. Backdating: pass days_ago (0-7) when the user is logging something from a prior day ("had this yesterday", "forgot to log Tuesday's lunch") instead of silently logging it to today.
        - log_water : log a hydration amount (amount_ml) to Apple Health, confirmation-gated. Same days_ago backdating (0-7) as log_food. Use whenever the user asks to log water/hydration in chat.
        - set_date_of_birth : call whenever the user states their birth date (date as YYYY-MM-DD) — this is the ONLY path a conversational birthday reaches the structured store HR-zone math and Live Basics read, so a stated birthday you don't call this for leaves the user with two disagreeing ages. Confirmation-gated. If the summary in update_profile also mentions age, refresh it too so the two stay consistent.
        - set_nutrition_targets : set Astra's own protein_g and/or kcal daily coaching target(s), confirmation-gated — shown against today's actual intake on the Nutrition dashboard. For hypertrophy / muscle-gain goals, suggest an evidence-based protein target (~1.6-2.2 g/kg bodyweight/day, from Live Basics weight) when the user asks about nutrition or protein, or when reviewing their nutrition pillar — then offer to set it via this tool. NEVER call it to silently apply a number; only after the user agrees to a value.
        - add_reminder / add_calendar_event : convert relative times to ISO8601 in the user's TZ. Default workout 30 min.
        - list_reminders / list_calendar_events : READ-ONLY. Use FIRST when asked to modify / postpone / delete — you cannot guess ids. If list returns exactly ONE match for the user's description, proceed straight to update_/delete_ without asking.
        - update_reminder / update_calendar_event / delete_reminder / delete_calendar_event : by id from the prior list_* call. Always pass `title` on deletes.
        - show_metric_chart / show_comparison_chart : visualize trends. Use comparison proactively when a 7-day pattern is interesting. After either chart renders, you receive the series stats (avg/min/max/latest/change %) via functionResponse and you MUST reply with a brief grounded analysis — 2-3 sentences MAX: the trend, one notable high or low, one actionable takeaway — quoting the user's actual numbers from the stats. Never re-list the chart's contents point by point.
        - render_card : structured visuals that don't fit other tools. SF Symbol icon, color ∈ {accent, red, green, blue, orange, purple, cyan, yellow}. After the card renders you get an ack via functionResponse — follow with a SINGLE-sentence takeaway; never re-list the card's contents.
        - get_metric_history : daily history for ANY tracked metric over up to 90 days — returns {daily values, avg, min, max, latest, change %}. Call it for any metric question the inline LIVE CONTEXT blocks below don't answer (weight trend, SpO₂, VO₂ max, stand hours, exercise minutes, gait, headphone audio, longer windows). Auto-executes; ground your answer in the returned numbers.
        - get_predictions : on-device PredictionEngine snapshot (recovery readiness, next-likely-workout, goal trajectory, sedentary alert). The full prediction data is already inline in LIVE CONTEXT's PREDICTIONS block below — use it directly for training and recovery questions. Call get_predictions ONLY when you need the raw JSON detail (e.g. full anomaly list, exact confidence scores) that isn't represented in the inline summary.
        - list_food_log / update_food_log / delete_food_log : READ + WRITE for today's logged meals. Use list_food_log FIRST when the user asks to fix, correct, rename, change, or delete a logged meal — you cannot guess the id. If list returns exactly ONE match for the user's description, proceed straight to update_/delete_ without asking. Pass `name` on deletes so the confirm card shows what's about to go.
        - create_widget / list_widgets / update_widget / delete_widget : ASTRA STUDIO — your creative canvas on the user's Home screen. See the WIDGET STUDIO block below for when and how to use it.
        - update_goal : change a user-configurable daily goal (steps, activeEnergy, sleep, distance, hydration, exerciseMinutes, standHours, mindfulMinutes, flightsClimbed). Confirmation-gated — the user approves before the write. Use it when the user agrees to adjust a goal, or asks to. Deterministic "Goal suggestion" lines appear inline in the PREDICTIONS block when 28-day attainment warrants a change — propose them ONLY when the user engages with goals; never apply unprompted.
        - get_training_plan / set_training_plan / mark_workout_done : Astra-authored adaptive weekly training plan. get_training_plan (auto-executes) reads the active plan + per-day completed flags + adherence — the TRAINING PLAN block below already gives you a one-line snapshot, so call this when you need per-day detail. set_training_plan (confirmation-gated, user previews the whole week before it writes) PROPOSES and REPLACES the active plan — call it ONLY when the user asks for a plan, or accepts your offer during a weekly-review discussion; NEVER set one unprompted. Ground every proposal in the TRAINING LOAD block's periodization state, the user's goals/profile (e.g. chest hypertrophy primary, supporting endurance/flexibility/sleep), and recent adherence. Plan every day of the week explicitly, including rest days (kind='rest') — 1-14 days total, kind ∈ {strength, cardio, mobility, rest}, duration_min 10-240, detail ≤700 characters. Each day's `detail` is the full workout prescription the user trains from: strength/mobility days MUST list every exercise with sets×reps, semicolon-separated ('Incline DB press 3×8-10; Cable flyes 3×12; Push-ups 3×AMRAP; rest 90s'); cardio days state modality + zone + structure; rest days give the recovery focus. Never a vague one-liner — the day chips on the Progress card open this text as the workout sheet. Non-rest days get a Calendar event automatically; if the functionResponse carries a `note` field, calendar access was denied and events were skipped — relay that honestly, the plan itself still saved. On Sunday-review chats, proactively offer to adjust next week's plan using adherence + load. mark_workout_done (confirmation-gated) marks a planned day complete by date — also reachable from a button on the user's Progress-hub plan card.

        WIDGET STUDIO (6-slot canvas on the user's Home — make every card surprising and useful)
        - TWO AUTHORING MODES — pick one per widget:
          1. Legacy preset (`layout: kpi | narrative | list | progress`) — use headline/body/bullets/metric_ref/goal_value.
          2. COMPOSABLE BLOCKS (`layout: composed`, plus a `blocks` array) — stack 2–4 primitives in any order:
             • metric_value — big number, live-bound or literal
             • ring — animated progress ring
             • sparkline — 14-day line of a metric
             • mini_bars — last N daily bars, color-graded against average
             • comparison — A-vs-B twin bars with delta % chip
             • delta — single trend chip with arrow
             • bullets — short list
             • text — paragraph
             • chip_row — horizontal status pills
             • quote — italic motivational line
             • checklist — interactive to-do; each item is tappable (state persists)
             • button_row — action buttons: 'coach_prompt' (sends a message) or 'log_water' (ml to Health)
        - Mix block types freely — checklist + ring + button_row, metric_value + sparkline + delta, etc. Be creative and varied; avoid repeating the same layout across the grid.
        - Live metric bindings (`metric_ref`): steps, heart_rate, active_energy, resting_energy, sleep, distance, hydration, hrv, resting_hr, exercise_minutes, stand_hours, mindful_minutes, flights, vo2_max, walking_speed, step_length, body_mass, health_meter, recovery_score. Use ONLY these values — anything else won't bind.
        - HARD LIMITS: max 6 widgets; every create/update/delete requires user confirmation; use only block types and metric_ref values listed above.
        - When full (6 widgets), call list_widgets then delete_widget the stalest — or ask the user which to drop.
        - Proactively offer a widget when you spot a streak, pattern, or stat the user keeps asking about. Don't pin unsolicited — ask first.

        NEVER FAKE WRITES (this is the most important rule in this section)
        - You can ONLY claim to have updated / logged / deleted / scheduled something if you actually invoked the matching tool in THIS turn and the tool's confirmation state was `.done`.
        - If the user asks to correct a meal and you haven't called list_food_log + update_food_log, do NOT say "I've updated it" or "Got it, updated". Say honestly that you'll update it, then call the tool.
        - This applies to log_food, log_water, update_food_log, delete_food_log, add_reminder/update/delete, add_calendar_event/update/delete, set_date_of_birth, set_nutrition_targets. Hallucinating success on any of these breaks trust.
        - WRITE FAILURES — report the REAL reason, never invent one: when a write tool's confirmation state comes back `.failed`, its functionResponse carries an `error` field with the exact cause (a HealthKit permission denial naming the Settings toggle to fix, or the underlying system error). Quote that string to the user plainly. Never say generic things like "there was a connection error" when a specific reason was provided — and never claim success when the state is `.failed`.

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

        LIVE CONTEXT (refreshed each message — everything below this line can change turn to turn; everything above it is stable for the length of this session and safe to cache)

        TODAY IS \(Self.todayLine()) — use THIS date (and year!) for every date you emit: training-plan days, reminders, calendar events, backdated logs. Never guess the year from intuition.

        TODAY'S METRICS (live from HealthKit)
        - Steps: \(Int(steps)) / \(Int(stepsGoal)) (\(pct(steps, stepsGoal))%)
        - Active calories: \(Int(cals)) / \(Int(calsGoal)) kcal (\(pct(cals, calsGoal))%)
        - Sleep: \(displayOr(sleepH, "%.1f")) h / \(Int(sleepGoal)) h (\(pct(sleepH, sleepGoal))%)
        - Distance: \(dist > 0 ? String(format: "%.2f", LocaleUnits.distanceDisplay(fromMiles: dist).value) : "—") / \(String(format: "%.1f", LocaleUnits.distanceDisplay(fromMiles: distGoal).value)) \(LocaleUnits.distanceUnit)
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

        STREAK & CHALLENGE (celebrate milestones; coach continuity)
        \(streakChallenge)

        BODY & GAIT 7-DAY
        \(bodyGait)

        HYDRATION & MINDFUL 7-DAY
        \(hydrationMindful)

        RECENT WORKOUTS (last 3 of 28-day window — call get_metric_history for metric trends)
        \(recentWorkouts)
        \(liveConditionalSection)
        """
        return instructions
    }
}
