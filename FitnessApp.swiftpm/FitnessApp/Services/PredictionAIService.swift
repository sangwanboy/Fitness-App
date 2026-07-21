import Foundation

/// AI-side companion to `PredictionEngine`. Wraps Gemini calls (via the
/// Atlas AI Gateway proxy) dedicated to *enriching* deterministic
/// predictions with personalized language, cross-metric insight, action
/// chips, and anomaly interpretation.
///
/// The deterministic engine remains canonical — this service is purely
/// additive. On timeout / network failure / parse error, the card renders
/// without enrichment and the user can retry next refresh.
public actor PredictionAIService {
    public static let shared = PredictionAIService()

    // 45s (was 12): the gateway absorbs upstream Vertex 429s by retrying,
    // legitimately pushing slow requests past 30s — a 12s cap turned those
    // eventual successes into client-side failures. Dead-gateway fast-fail
    // is covered by GatewayTransport.ensureReachable's 2s probe, so the
    // long timeout only applies to genuinely slow-but-succeeding calls.
    private let timeout: TimeInterval = 45

    /// In-flight task dedupe: if a second `enrichPredictions` lands while the
    /// first is still streaming, both await the same result instead of
    /// duplicating the API hit.
    private var inflight: Task<EnrichmentBundle, Error>?

    public struct EnrichmentBundle: Codable {
        public let insight: DailyInsight?
        public let actions: [ActionSuggestion]
        public let anomalyInterpretations: [UUID: String]

        // Coding manually so the [UUID: String] map round-trips JSON cleanly.
        enum CodingKeys: String, CodingKey {
            case insight, actions, anomalyInterpretationsList
        }

        private struct AnomalyText: Codable { let id: UUID; let text: String }

        public init(insight: DailyInsight?,
                    actions: [ActionSuggestion],
                    anomalyInterpretations: [UUID: String]) {
            self.insight = insight
            self.actions = actions
            self.anomalyInterpretations = anomalyInterpretations
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.insight = try c.decodeIfPresent(DailyInsight.self, forKey: .insight)
            self.actions = (try? c.decode([ActionSuggestion].self, forKey: .actions)) ?? []
            let list = (try? c.decode([AnomalyText].self, forKey: .anomalyInterpretationsList)) ?? []
            self.anomalyInterpretations = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.text) })
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(insight, forKey: .insight)
            try c.encode(actions, forKey: .actions)
            let list = anomalyInterpretations.map { AnomalyText(id: $0.key, text: $0.value) }
            try c.encode(list, forKey: .anomalyInterpretationsList)
        }
    }

    public enum AIError: Error, LocalizedError {
        case httpStatus(Int)
        case parseError
        case timeout
        /// Gateway-level failure (auth, rate limit, quota, server) — carries
        /// the GatewayError's honest user-facing message.
        case gateway(String)

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "AI backend returned HTTP \(code)."
            case .parseError: return "Could not parse the AI response."
            case .timeout: return "AI request timed out."
            case .gateway(let message): return message
            }
        }
    }

    // MARK: - Public API

    /// One-shot enrichment for the latest deterministic predictions. Returns
    /// a bundle of optional AI extras. Throws only if ALL sub-tasks failed
    /// (signals a transport problem worth marking `.failed` in UI). Safe to
    /// call concurrently — duplicates dedupe via the inflight task.
    public func enrichPredictions(_ p: Predictions,
                                  userContext: String) async throws -> EnrichmentBundle {
        if let existing = inflight { return try await existing.value }
        let task = Task { () throws -> EnrichmentBundle in
            // All three sub-calls in parallel — they're independent.
            async let insightTask = self.generateDailyInsight(predictions: p, userContext: userContext)
            async let actionsTask = self.suggestActions(predictions: p, userContext: userContext)
            async let anomalyTask = self.interpretAnomalies(p.anomalies, userContext: userContext)

            // Tolerate per-call failure — one section nil-ing out should not
            // lose the others. Track failure count so we can throw if Vertex
            // is genuinely down (all three fail with the same transport error).
            var failures = 0
            var insight: DailyInsight? = nil
            var actions: [ActionSuggestion] = []
            var interpretations: [UUID: String] = [:]

            do { insight = try await insightTask } catch { failures += 1 }
            do { actions = try await actionsTask } catch { failures += 1 }
            do { interpretations = try await anomalyTask } catch { failures += 1 }

            if failures >= 3 {
                throw AIError.httpStatus(0) // surrogate: "all sub-tasks failed"
            }
            return EnrichmentBundle(insight: insight,
                                    actions: actions,
                                    anomalyInterpretations: interpretations)
        }
        inflight = task
        defer { inflight = nil }
        return try await task.value
    }

    /// Events yielded by the Why-sheet stream — text chunks as Gemini types
    /// them, and a final `usage` event once `usageMetadata` lands.
    public enum WhyStreamEvent: Sendable {
        case text(String)
        case usage(TokenUsage)
    }

    /// Streaming "Why?" deep-dive for a single prediction kind. Emits text
    /// chunks as Gemini generates them via the gateway's /v1/chat SSE stream
    /// — so the user sees progressive output instead of a 3-second wait then
    /// a wall of text. Caller cancels by closing the sheet.
    public nonisolated func explainPrediction(_ kind: PredictionKind,
                                              predictions: Predictions,
                                              userContext: String) -> AsyncThrowingStream<WhyStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prompt = Self.whyPrompt(kind: kind, predictions: predictions, userContext: userContext)
                    try await self.streamWhyExplanation(prompt: prompt,
                                                        maxTokens: 2000,
                                                        continuation: continuation)
                    continuation.finish()
                } catch let gateway as GatewayError {
                    continuation.finish(throwing: AIError.gateway(gateway.userMessage))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streaming transport via GatewayTransport.streamChat. Each yielded
    /// element is one Vertex-shaped JSON chunk (SSE framing handled by the
    /// transport); forwards non-empty text runs plus a trailing `.usage`
    /// event when `usageMetadata` lands.
    private func streamWhyExplanation(prompt: String,
                                      maxTokens: Int,
                                      continuation: AsyncThrowingStream<WhyStreamEvent, Error>.Continuation) async throws {
        // The chat model spends tokens on internal reasoning before emitting
        // text. Read the shared thinking_level preference and add headroom on
        // top of the caller's `maxTokens` so visible output is never starved.
        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        let body = GatewayChatPayload.body(
            stream: true,
            system: "",
            messages: [GatewayChatPayload.message(role: "user",
                                                  parts: [GatewayChatPayload.textPart(prompt)])],
            generationConfig: [
                "maxOutputTokens": maxTokens + thinkingBudget,
                "temperature": 0.7,
                "thinkingConfig": ["thinkingBudget": thinkingBudget]
            ]
        )

        // Idle timeout of 30s mid-stream is plenty for the outputs we expect.
        let events = try await GatewayTransport.streamChat(body: body, idleTimeout: 30)
        for try await chunk in events {
            if Task.isCancelled { return }
            emitTextChunk(from: chunk, into: continuation)
        }
    }

    /// Extract `candidates[].content.parts[].text` from a single chunked JSON
    /// object and forward each non-empty text run + any usageMetadata as
    /// dedicated stream events.
    private func emitTextChunk(from data: Data,
                               into continuation: AsyncThrowingStream<WhyStreamEvent, Error>.Continuation) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let candidates = obj["candidates"] as? [[String: Any]] {
            for cand in candidates {
                guard let content = cand["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else { continue }
                for part in parts {
                    if let text = part["text"] as? String, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                }
            }
        }
        if let usage = obj["usageMetadata"] as? [String: Any],
           let parsed = TokenUsage(usageMetadata: usage) {
            continuation.yield(.usage(parsed))
            Task { @MainActor in TokenMeter.shared.record(parsed, source: .insights) }
        }
    }

    // MARK: - Sub-tasks

    private func generateDailyInsight(predictions p: Predictions,
                                      userContext: String) async throws -> DailyInsight? {
        let prompt = """
        \(userContext)

        TODAY'S PREDICTIONS (computed on-device, treat as ground truth):
        \(Self.predictionsSummary(p))

        TASK: Surface ONE cross-metric pattern worth highlighting today. Compare against the user's OWN baselines — never population norms. If nothing is worth surfacing, return an empty body.

        Output STRICT JSON (no markdown fences, no preamble):
        {"headline": "8-15 word summary", "body": "1-2 sentence detail", "confidence": "low|medium|high"}
        """
        let raw = try await callGeminiJSON(prompt: prompt, maxTokens: 220, responseJSON: true)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let headline = obj["headline"] as? String,
              let body = obj["body"] as? String,
              !headline.trimmingCharacters(in: .whitespaces).isEmpty,
              !body.trimmingCharacters(in: .whitespaces).isEmpty,
              let confStr = obj["confidence"] as? String,
              let confidence = PredictionConfidence(rawValue: confStr.lowercased()) else {
            return nil
        }
        return DailyInsight(headline: headline, body: body, confidence: confidence)
    }

    private func suggestActions(predictions p: Predictions,
                                userContext: String) async throws -> [ActionSuggestion] {
        let prompt = """
        \(userContext)

        TODAY'S PREDICTIONS:
        \(Self.predictionsSummary(p))

        TASK: Produce 1-3 specific actionable chips the user can tap to ask Astra. Each chip is a SINGLE concrete action: schedule a workout, log a food, plan a recovery walk, adjust a goal.

        prefillPrompt MUST be a complete sentence sent verbatim to the coach (e.g. "Schedule a 30-min Z2 ride at 6 PM today" — NOT "schedule workout"). Use the user's locale / timezone for any times.

        Use SF Symbol names for icon. Choose icons that match the action.

        Output STRICT JSON array (no fences, no preamble):
        [{"icon": "figure.run", "title": "≤24 chars", "prefillPrompt": "complete sentence", "category": "workout|nutrition|recovery|planning"}]
        """
        let raw = try await callGeminiJSON(prompt: prompt, maxTokens: 500, responseJSON: true)
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.prefix(3).compactMap { dict in
            guard let icon = dict["icon"] as? String,
                  let title = dict["title"] as? String,
                  let prompt = dict["prefillPrompt"] as? String,
                  let catStr = dict["category"] as? String else { return nil }
            let category = ActionCategory(rawValue: catStr.lowercased()) ?? .other
            // Defensive clipping in case the model overshoots.
            let trimTitle = String(title.prefix(28))
            return ActionSuggestion(icon: icon, title: trimTitle, prefillPrompt: prompt, category: category)
        }
    }

    private func interpretAnomalies(_ anomalies: [Anomaly],
                                    userContext: String) async throws -> [UUID: String] {
        guard !anomalies.isEmpty else { return [:] }
        let lines = anomalies.enumerated().map { idx, a in
            "\(idx + 1). \(a.metric.displayName): today=\(String(format: "%.1f", a.today)) \(a.metric.unit), 28-day baseline=\(String(format: "%.1f", a.baseline)) \(a.metric.unit), z=\(String(format: "%.2f", a.zScore)) (\(a.direction))"
        }.joined(separator: "\n")

        let prompt = """
        \(userContext)

        DETECTED ANOMALIES (today's value is unusual vs the user's own 28-day baseline):
        \(lines)

        TASK: For each anomaly, write ≤2 sentences explaining what it might mean for the user's day. End with one concrete action. Be specific and personal — don't generalize.

        Output STRICT JSON array in same order as input (no fences):
        [{"index": 1, "text": "explanation..."}]
        """
        let raw = try await callGeminiJSON(prompt: prompt, maxTokens: 500, responseJSON: true)
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var out: [UUID: String] = [:]
        for item in arr {
            guard let idx = item["index"] as? Int,
                  let text = item["text"] as? String,
                  (1...anomalies.count).contains(idx) else { continue }
            out[anomalies[idx - 1].id] = text
        }
        return out
    }

    // MARK: - Gateway transport

    /// One-shot /v1/chat call through the gateway. Optionally constrains the
    /// response to JSON.
    private func callGeminiJSON(prompt: String, maxTokens: Int, responseJSON: Bool) async throws -> String {
        // Add headroom on top of the caller's maxTokens so the model's
        // internal thoughts can't starve the visible JSON payload.
        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        var generationConfig: [String: Any] = [
            "maxOutputTokens": maxTokens + thinkingBudget,
            "temperature": 0.7,
            "thinkingConfig": ["thinkingBudget": thinkingBudget]
        ]
        if responseJSON {
            generationConfig["responseMimeType"] = "application/json"
        }
        let body = GatewayChatPayload.body(
            stream: false,
            system: "",
            messages: [GatewayChatPayload.message(role: "user",
                                                  parts: [GatewayChatPayload.textPart(prompt)])],
            generationConfig: generationConfig
        )

        let data: Data
        do {
            data = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: timeout)
        } catch GatewayError.network(let underlying) {
            // Preserve the old timeout semantics for plain transport drops so
            // enrichPredictions' partial-failure tolerance behaves the same.
            if (underlying as? URLError)?.code == .timedOut { throw AIError.timeout }
            throw AIError.gateway(GatewayError.network(underlying: underlying).userMessage)
        } catch let gateway as GatewayError {
            throw AIError.gateway(gateway.userMessage)
        }

        // Thought-part-safe extraction — see GatewayChatPayload.responseText.
        // (parts.first grabbed Gemini 3.x thought/signature parts whenever a
        // thinking budget was active, breaking downstream JSON parsing.)
        guard let (text, usageMeta) = GatewayChatPayload.responseText(fromBody: data) else {
            throw AIError.parseError
        }
        if let usageMeta, let usage = TokenUsage(usageMetadata: usageMeta) {
            Task { @MainActor in TokenMeter.shared.record(usage, source: .insights) }
        }
        return GatewayChatPayload.strippedJSONText(text)
    }

    // MARK: - Helpers (nonisolated so they can be called from sync contexts)

    nonisolated static func predictionsSummary(_ p: Predictions) -> String {
        var lines: [String] = []
        if let m = p.healthMeter {
            lines.append("Health Meter: \(m.score)/100 (\(m.label.headline)) confidence=\(m.confidence.rawValue) — Activity \(m.activityScore)/30, Nutrition \(m.nutritionScore)/30 (hasMealData=\(m.usedNutrition), mealsLoggedToday=\(m.mealsLoggedToday)), Body \(m.bodyScore)/18 (BMI=\(m.usedBMI)), Vitals \(m.vitalsScore)/22")
        }
        if let r = p.recovery {
            lines.append("Recovery: \(r.score)/100 (\(r.label.headline)) confidence=\(r.confidence.rawValue) usedHRV=\(r.usedHRV) usedRHR=\(r.usedRHR)")
        }
        if let n = p.nextWorkout {
            let cat = n.isCategoryFallback ? "(time-only pattern)" : n.category.displayName
            lines.append("Next workout: \(cat) \(n.weekdayLabel) \(n.startHour)-\(n.endHour) confidence=\(n.confidence.rawValue)")
        }
        for t in p.trajectories {
            lines.append("\(t.metric.displayName): current=\(Int(t.currentValue)) projected=\(Int(t.projectedEOD)) baseline=\(Int(t.baselineEOD)) status=\(t.status.headline) pace=\(String(format: "%.2f", t.pace))")
        }
        if let sed = p.sedentary {
            lines.append("Sedentary: \(sed.quietHours) quiet hours, severity=\(sed.severity.rawValue), today=\(sed.dayTotalSoFar) vs baseline=\(sed.baselineDayTotal)")
        }
        for a in p.anomalies {
            lines.append("Anomaly: \(a.metric.displayName) drifted \(a.direction) (z=\(String(format: "%.2f", a.zScore)), today=\(String(format: "%.1f", a.today)), baseline=\(String(format: "%.1f", a.baseline)))")
        }
        if let w = p.illnessWarning {
            lines.append("Illness warning: severity=\(w.severity.rawValue), RHR delta=+\(String(format: "%.1f", w.rhrDeltaBpm)) bpm above baseline, HRV drop=\(String(format: "%.1f", w.hrvDropPct))%, sleep debt=\(String(format: "%.1f", w.sleepDebtHours))h, consecutive days=\(w.consecutiveDays)")
        }
        for c in p.correlations {
            lines.append("Correlation: \(c.metricA.displayName) → \(c.metricB.displayName) lag=\(c.lagDays)d r=\(String(format: "%.2f", c.r)) n=\(c.sampleDays) days — \(c.insight)")
        }
        if let pz = p.periodization {
            let trendSign = pz.loadTrendPct >= 0 ? "+" : ""
            lines.append("Periodization: phase=\(pz.phase) weekLoad=\(String(format: "%.0f", pz.weekLoad)) kcal baselineWeekLoad=\(String(format: "%.0f", pz.baselineWeekLoad)) kcal trend=\(trendSign)\(String(format: "%.1f", pz.loadTrendPct))% confidence=\(pz.confidence.rawValue) recommendation=\"\(pz.recommendation)\"")
        }
        if let sf = p.sleepForecast {
            let deltaSign = (sf.predictedHours - sf.baselineHours) >= 0 ? "+" : ""
            let delta = String(format: "%.1f", sf.predictedHours - sf.baselineHours)
            lines.append("Sleep forecast tonight: ~\(String(format: "%.1f", sf.predictedHours))h (\(deltaSign)\(delta)h vs \(String(format: "%.1f", sf.baselineHours))h baseline, driver=\(sf.deltaDriver), confidence=\(sf.confidence.rawValue)) — \(sf.basis)")
        }
        if !p.goalSuggestions.isEmpty {
            let parts = p.goalSuggestions.map { s -> String in
                let cur: String
                let sug: String
                switch s.metric {
                case .sleep, .hydration, .distance:
                    cur = String(format: "%.1f", s.currentGoal)
                    sug = String(format: "%.1f", s.suggestedGoal)
                default:
                    cur = String(format: "%.0f", s.currentGoal)
                    sug = String(format: "%.0f", s.suggestedGoal)
                }
                return "\(s.metric.rawValue) \(cur)->\(sug) (\(s.direction), median attainment \(String(format: "%.0f", s.medianAttainmentPct))%)"
            }
            lines.append("Goal suggestions: \(parts.joined(separator: ", "))")
        }
        return lines.isEmpty ? "—" : lines.joined(separator: "\n")
    }

    nonisolated private static func whyPrompt(kind: PredictionKind,
                                              predictions p: Predictions,
                                              userContext: String) -> String {
        let detail: String
        switch kind {
        case .recovery:
            if let r = p.recovery {
                detail = """
                Recovery score: \(r.score)/100 (\(r.label.headline))
                Confidence: \(r.confidence.rawValue)
                Used HRV: \(r.usedHRV) · Used RHR: \(r.usedRHR)
                Bullets: \(r.explanation.bullets.joined(separator: " | "))
                """
            } else {
                detail = "No recovery prediction available."
            }
        case .nextWorkout:
            if let n = p.nextWorkout {
                detail = "\(n.category.displayName) \(n.weekdayLabel) \(n.startHour)-\(n.endHour), support=\(Int(n.support * 100))%, confidence=\(n.confidence.rawValue), categoryFallback=\(n.isCategoryFallback)"
            } else {
                detail = "No next-workout prediction available."
            }
        case .trajectory:
            detail = p.trajectories.map { "\($0.metric.displayName): \($0.status.headline) (pace=\(String(format: "%.2f", $0.pace)), projected=\(Int($0.projectedEOD)) vs baseline=\(Int($0.baselineEOD)))" }.joined(separator: "\n")
        case .sedentary:
            if let s = p.sedentary {
                detail = "\(s.quietHours)h quiet, severity=\(s.severity.rawValue), today=\(s.dayTotalSoFar) vs baseline=\(s.baselineDayTotal)"
            } else {
                detail = "No sedentary alert."
            }
        case .healthMeter:
            if let m = p.healthMeter {
                detail = """
                Total score: \(m.score)/100 (\(m.label.headline), \(m.confidence.rawValue) confidence)
                Activity: \(m.activityScore)/30
                Nutrition: \(m.nutritionScore)/30 (hasMealData=\(m.usedNutrition), mealsLoggedToday=\(m.mealsLoggedToday))\(m.usedNutrition && !m.mealsLoggedToday ? " — score is from the last 7 days; the user has NOT logged any food today, never claim they did" : "")
                Body composition: \(m.bodyScore)/18 (usedBMI=\(m.usedBMI))
                Vitals: \(m.vitalsScore)/22
                Bullets: \(m.explanation.bullets.joined(separator: " | "))
                """
            } else {
                detail = "No health meter score available."
            }
        case .illness:
            if let w = p.illnessWarning {
                detail = """
                Severity: \(w.severity.rawValue)
                RHR delta: +\(String(format: "%.1f", w.rhrDeltaBpm)) bpm above 28-day baseline (positive = elevated)
                HRV drop: \(String(format: "%.1f", w.hrvDropPct))% below 28-day baseline
                Sleep debt: \(String(format: "%.1f", w.sleepDebtHours)) hours cumulative deficit across flagged window
                Consecutive days: \(w.consecutiveDays)
                Explanation bullets: \(w.explanation.bullets.joined(separator: " | "))
                """
            } else {
                detail = "No illness warning available."
            }
        case .correlations:
            if p.correlations.isEmpty {
                detail = "No correlations available."
            } else {
                detail = p.correlations.map { c in
                    "• \(c.metricA.displayName) → \(c.metricB.displayName): r=\(String(format: "%.2f", c.r)), lag=\(c.lagDays) day\(c.lagDays == 1 ? "" : "s"), n=\(c.sampleDays) overlapping days. \(c.insight)"
                }.joined(separator: "\n")
            }
        case .periodization:
            if let pz = p.periodization {
                let trendSign = pz.loadTrendPct >= 0 ? "+" : ""
                // Note: weekLoad is a kcal proxy (duration × 8) when Apple Health energy data is absent.
                detail = """
                Phase: \(pz.phase)
                This week's load: \(String(format: "%.0f", pz.weekLoad)) kcal (proxy: duration-min × 8 when energy data is missing)
                3-week baseline load: \(String(format: "%.0f", pz.baselineWeekLoad)) kcal
                Load trend: \(trendSign)\(String(format: "%.1f", pz.loadTrendPct))% vs baseline
                Confidence: \(pz.confidence.rawValue)
                Deterministic recommendation: \(pz.recommendation)
                """
            } else {
                detail = "No periodization data available."
            }
        case .sleepForecast:
            if let sf = p.sleepForecast {
                let deltaSign = (sf.predictedHours - sf.baselineHours) >= 0 ? "+" : ""
                let delta = String(format: "%.1f", sf.predictedHours - sf.baselineHours)
                detail = """
                Predicted tonight: \(String(format: "%.1f", sf.predictedHours))h
                Baseline (recent median): \(String(format: "%.1f", sf.baselineHours))h
                Delta: \(deltaSign)\(delta)h
                Driver: \(sf.deltaDriver)
                Basis sentence: \(sf.basis)
                Confidence: \(sf.confidence.rawValue)
                Method: stratified comparison — the engine buckets days by activity level (high/mid/low) and reports the mean next-night sleep of whichever stratum today most resembles. This is a tendency based on the user's own data, not a promise.
                """
            } else {
                detail = "No sleep forecast available."
            }
        case .goalSuggestions:
            if p.goalSuggestions.isEmpty {
                detail = "No goal suggestions available."
            } else {
                detail = p.goalSuggestions.map { s -> String in
                    let cur: String
                    let sug: String
                    switch s.metric {
                    case .sleep, .hydration, .distance:
                        cur = String(format: "%.1f", s.currentGoal)
                        sug = String(format: "%.1f", s.suggestedGoal)
                    default:
                        cur = String(format: "%.0f", s.currentGoal)
                        sug = String(format: "%.0f", s.suggestedGoal)
                    }
                    return "• \(s.metric.displayName): current goal \(cur) \(s.metric.unit) → suggested \(sug) \(s.metric.unit) (\(s.direction)), 28-day median attainment \(String(format: "%.0f", s.medianAttainmentPct))% — \(s.rationale)"
                }.joined(separator: "\n")
            }
        }
        let kindSpecificShape = whyOutputShape(for: kind)
        return """
        \(userContext)

        PREDICTION CONTEXT for the user's question (\(kind.rawValue)):
        \(detail)

        Whole snapshot for reference:
        \(predictionsSummary(p))

        TASK: Give the user a THOROUGH personalized breakdown of why this prediction looks the way it does. They tapped "Why?" — they want the full picture, not a one-liner. Walk through every contributing factor with their actual numbers, explain what each piece of data means for someone with their baseline, then close with concrete next moves.

        OUTPUT FORMAT (markdown allowed — keep it scannable):
        - Open with one bold takeaway sentence on its own line — the headline they'd read first.
        - Use `### Section heading` for each contributing factor that matters.
        - Under each heading, 2-3 short lines (or `-` bullets) that quote their data, compare to the baseline, and say what it means.
        - End with one final `Next:` line: ONE concrete action they can take in the next hour. Be specific (exact minutes, exact time, exact macro target — not "move more").

        \(kindSpecificShape)

        RULES
        - Address the user directly ("your", "you", never "the user").
        - Quote their actual numbers from the context above — don't generalize.
        - Reference their own baseline / averages where relevant ("your 7-day mean of …", "your usual …"). Population norms only if their personal baseline is empty.
        - 200-400 words total. Don't pad. Don't apologize. Don't preface ("Sure!", "Of course").
        - No JSON. No code fences. Plain markdown only.
        """
    }

    /// Per-PredictionKind structural hint so the model knows which factors
    /// to enumerate. Lives outside `whyPrompt` to keep that function readable.
    nonisolated private static func whyOutputShape(for kind: PredictionKind) -> String {
        switch kind {
        case .healthMeter:
            return """
            SHAPE FOR HEALTH METER:
            Cover ALL four sub-scores in order: Activity, Nutrition, Body composition, Vitals. For each:
            - State the sub-score out of max (e.g. "Activity: 22/30").
            - Quote 1-2 specific inputs that drove that sub-score (steps avg, dietary calories, BMI, sleep, RHR, HRV, etc.).
            - Say what that means for the user — whether it's pulling the overall score up or down.
            If the user is missing nutrition logs or height/weight, call it out as the cheapest score-boost available.
            """
        case .recovery:
            return """
            SHAPE FOR RECOVERY:
            Cover EACH input that fed the score in turn:
            ### HRV (only if available — quote ms and compare to 28-day baseline)
            ### Resting HR (only if available)
            ### Last night's sleep (always — quote hours vs baseline)
            ### Training load (acute vs chronic — explain ACWR in plain English)
            For iPhone-only users, lead with the disclaimer that HRV/RHR aren't available and the score is estimated from sleep + load. Be honest about the lower confidence.
            """
        case .nextWorkout:
            return """
            SHAPE FOR NEXT WORKOUT:
            ### The pattern
            What weekday + time window the model detected, and what activity. Quote support percentage.
            ### Why we think it
            How many of the recent 4 weeks had a workout in this bucket. Mention if it's a category-fallback (time-only) pattern.
            ### Confidence
            What support level (medium / high) and what would raise it.
            """
        case .trajectory:
            return """
            SHAPE FOR TRAJECTORY:
            ### Where you are right now
            Current value vs what you should have at this hour to be on pace (computed from 14-day baseline × elapsed-day fraction).
            ### Projected end of day
            Your projected EOD value at current pace, vs your 14-day mean EOD.
            ### What the gap is
            Spell out exactly how far behind/ahead in the metric's own units (e.g. "behind by 2,300 steps").
            ### Catch-up math
            How many minutes / how much intensity it would take to close the gap before the day ends.
            """
        case .sedentary:
            return """
            SHAPE FOR SEDENTARY:
            ### The quiet stretch
            How many hours since their last 250+ step hour, and when that hour was.
            ### How it compares
            Day total so far vs typical day total at this hour.
            ### Why it matters
            One sentence on the metabolic / circulatory cost of long sitting (without going clinical).
            ### What 5 minutes fixes
            What a single short walk now does for their day score / step count.
            """
        case .illness:
            return """
            SHAPE FOR ILLNESS WARNING:
            CRITICAL RULE: You are describing physiological strain patterns from the user's own biometric data — never diagnose, never mention illness, disease, infection, or medical conditions. Use language like "your body is working harder than usual" or "your recovery metrics are under stress."
            ### Resting Heart Rate
            Quote the exact delta (e.g. "+4 bpm above your 28-day baseline of X bpm"). Explain what elevated RHR at this level typically means for training readiness — keep it personal, not clinical.
            ### HRV
            Quote the exact percentage drop vs 28-day baseline. Explain what a drop of this magnitude suggests about the nervous system's current state.
            ### Sleep debt
            Quote the cumulative hours of deficit across the flagged window. Explain how sleep debt compounds with the other two signals.
            ### The pattern
            State how many consecutive days these signals have held. Explain why a multi-day pattern is more meaningful than a single-day blip.
            ### What this means for training
            Be direct: given all three signals together, what intensity level is appropriate right now? Use terms like "zone 1-2 only", "no new PRs", "prioritize sleep over volume". Do NOT suggest rest has anything to do with illness — frame it as optimising the body's internal repair cycle.
            NO DIAGNOSIS RULE: Never imply the user is sick. Never suggest they see a doctor unless the numbers are extreme (e.g. RHR delta > 15 bpm). Always frame as "your recovery metrics are signalling that your body is under load."
            """
        case .correlations:
            return """
            SHAPE FOR CORRELATIONS:
            CRITICAL RULE: Correlation is not causation. State this clearly but briefly once, then move on. Never say one metric "causes" another.
            For each correlation in the data (up to 3):
            ### [MetricA] and [MetricB]
            - State the Pearson r value and what it means in plain English (e.g. "r = 0.62 — a moderately strong relationship"). Use a simple scale: |r| 0.45-0.59 = moderate, 0.60-0.79 = strong, 0.80+ = very strong.
            - Explain the lag: "Same-day" vs "next-day" — which metric tends to precede the other, and what that pattern looks like in practice.
            - Quote the sample size (overlapping days) to help the user gauge how much to trust it.
            - One concrete implication: "When your X is high one day, your Y tends to be [higher/lower] the [same/next] day — so on days when X looks strong, it may be worth [specific behaviour]."
            Close with a brief note on what to do with these patterns — not an absolute rule, but a nudge toward experimentation.
            """
        case .sleepForecast:
            return """
            SHAPE FOR SLEEP FORECAST:
            HONESTY RULE: This is a tendency, not a guarantee. Say so once, briefly, then move on. Never claim the user will sleep a specific number of hours.

            ### How the forecast was made
            Explain the stratified method in plain English: the engine groups the user's past days into high-, mid-, and low-activity buckets, then reports the mean next-night sleep of whichever bucket today's activity level falls into. Quote the number of similar days the estimate is based on if it appears in the basis sentence. One sentence on why this is more honest than regression at small sample sizes.

            ### Today's activity vs your pattern
            Describe what "driver" means in context (high load / low activity / typical day) and how today compares to the user's norm. Quote the predicted and baseline hours with signs (e.g. "+0.4h above your usual 7.2h").

            ### What affects tonight
            Two or three short bullets on the levers most likely to move tonight's sleep in either direction — e.g. screen time, caffeine cutoff, room temperature, training timing. Keep them personal and concrete, not generic wellness clichés.

            ### How to use this number
            One pragmatic sentence: what to do with this forecast if it's above baseline (e.g. lean into it, plan something demanding tomorrow) vs below (e.g. start wind-down earlier).

            End with one `Next:` line: the single most effective thing to do in the next 30 minutes to support the best possible sleep tonight.
            """
        case .goalSuggestions:
            return """
            SHAPE FOR GOAL SUGGESTIONS:
            For each goal suggestion in the data:
            ### [Metric name]
            - State the current goal and the suggested goal with units.
            - Quote the 28-day median attainment percentage. Explain what it means: below 80% suggests the goal may be too ambitious; above 95% suggests headroom to push higher.
            - Explain the direction of the change (e.g. "increasing your step goal from 8,000 to 9,500") and what recent behaviour supports it.
            - One concrete implication: what would need to change day-to-day to hit the new target, expressed in specific, relatable terms (e.g. "about 10 extra minutes of walking per day").
            Close with a brief paragraph on how to decide which suggestions to apply first — prioritise by impact on health metrics, not by which are easiest.
            RULE: Never tell the user to apply the suggestion. The decision is theirs. Present the reasoning, not the instruction.
            """
        case .periodization:
            return """
            SHAPE FOR PERIODIZATION:
            DATA HONESTY RULE: The load numbers are kilocalorie estimates. When Apple Health has active-energy data from workouts, those are used directly. When energy data is absent (common without Apple Watch), load is estimated as duration-in-minutes × 8 kcal/min — a rough proxy. If the trend percentage is large but the raw kcal numbers seem low (< 200 kcal per session), call this out briefly: "these are duration-based estimates, not measured energy."

            ### Your current phase: [phase]
            Explain what this phase means in plain English. One sentence on what distinguishes it from the neighbouring phases (e.g. "Build means your week's load is climbing — you're asking more of your body than your recent average").

            ### Weekly load breakdown
            - Quote this week's load vs the 3-week baseline in kcal (e.g. "1,840 kcal this week vs your 1,420 kcal baseline").
            - Quote the trend percentage with sign (e.g. "+29%").
            - If energy data may be estimated, say so: "these figures are duration-based proxies — add a Watch or log workouts with energy data for more precision."

            ### What the trend means for your body
            Explain the Acute:Chronic Workload Ratio (ACWR) concept in one plain-English sentence without the jargon: the idea that how much you're doing this week relative to your recent average tells you how much stress you're adding. A trend above +20-25% raises injury risk; a sharp drop can mean detraining. Keep it personal, not textbook.

            ### Training recommendations for this phase
            Two or three concrete bullets:
            - For "build": how hard to push, what to watch for (soreness, sleep quality, HRV)
            - For "peak": that this is a short window, not sustainable — the ACWR signal to back off soon
            - For "deload": roughly what volume cut (e.g. "reduce total weekly volume ~30-40%") and why it makes you fitter
            - For "recover": active recovery emphasis, what to avoid, when to expect a bounce-back
            - For "steady": this is maintenance — how to avoid the plateau and when to nudge load up

            ### What to watch next week
            One specific metric or signal to track (e.g. morning RHR, sleep quality, workout performance) as a leading indicator of whether to push or back off.
            """
        }
    }
}
