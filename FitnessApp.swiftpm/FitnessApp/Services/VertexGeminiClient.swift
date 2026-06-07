import Foundation

public actor VertexGeminiClient {
    public static let shared = VertexGeminiClient()

    private init() {}

    // MARK: - Public stream API
    /// Streams a ChatChunk sequence: text deltas interleaved with tool calls.
    /// Caller is expected to pause text appending when a .toolCall lands and
    /// drive the tool's UI flow (confirm + execute).
    public func streamGenerateContent(
        prompt: String,
        history: [ChatMessage],
        systemInstruction: String,
        imageData: Data? = nil,
        imageMimeType: String = "image/jpeg",
        model: String = "gemini-3.5-flash"
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        let capturedSelf = self
        // gemini-3.5-flash only — no silent fallback to older models. If 3.5
        // isn't available the request surfaces the error to the user instead
        // of degrading quality without notice.

        return AsyncThrowingStream<ChatChunk, Error>(ChatChunk.self) { continuation in
            let work = Task {
                do {
                    try await capturedSelf.performStreamingRequest(
                        prompt: prompt,
                        history: history,
                        systemInstruction: systemInstruction,
                        imageData: imageData,
                        imageMimeType: imageMimeType,
                        model: model,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Total wall-clock timeout: if the request task is still running 120s
            // after it started, cancel it. Combined with the 60s idle timeout on the
            // URLRequest, this means the LLM cannot pin the chat open indefinitely.
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if !work.isCancelled {
                    work.cancel()
                    continuation.finish(throwing: NSError(
                        domain: "VertexGeminiClient", code: 408,
                        userInfo: [NSLocalizedDescriptionKey: "LLM timed out after 2 minutes."]))
                }
            }

            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - Tools manifest
    /// Function declarations sent to Gemini so it knows what it can call.
    /// Schema follows OpenAPI-flavored JSON used by Vertex AI.
    private var toolsManifest: [String: Any] {
        return [
            "functionDeclarations": [
                [
                    "name": "log_food",
                    "description": "Render a rich food info card and let the user confirm logging it to today's diet in Apple Health. Always emit this when the user uploads a food photo OR asks to log/identify a food item — fill in tags/highlights/cautions when relevant. ALWAYS set is_estimate=true and pick a confidence level unless the user gave you exact label nutrition data (then is_estimate=false). Multi-item plates → one call per distinct item.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "name":     ["type": "string",  "description": "Food name"],
                            "calories": ["type": "number",  "description": "Total kcal for this serving"],
                            "protein":  ["type": "number",  "description": "Grams"],
                            "carbs":    ["type": "number",  "description": "Grams"],
                            "fat":      ["type": "number",  "description": "Grams"],
                            "serving":  ["type": "string",  "description": "Description of serving size, e.g. '1 medium (118g)'"],
                            "tags":       ["type": "array", "items": ["type": "string"], "description": "Short capsules — e.g. 'high protein', 'gluten free', 'vegan'"],
                            "highlights": ["type": "array", "items": ["type": "string"], "description": "Positive nutritional notes — one short bullet each"],
                            "cautions":   ["type": "array", "items": ["type": "string"], "description": "Warnings — high sodium, allergens, added sugar, etc. Cross-check against the user's allergies in the system prompt."],
                            "is_estimate": ["type": "boolean", "description": "TRUE when macros are guessed from a photo/description; FALSE only when user supplied exact label nutrition."],
                            "confidence":  ["type": "string", "description": "low | medium | high — required when is_estimate is true."]
                        ],
                        "required": ["name", "calories", "is_estimate"]
                    ]
                ],
                [
                    "name": "add_reminder",
                    "description": "Create a Reminders.app reminder. The user must confirm before it writes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title":    ["type": "string"],
                            "due_at":   ["type": "string", "description": "ISO8601 date-time; omit for 'someday'"],
                            "category": ["type": "string", "description": "workout | hydration | supplement | sleep | other"]
                        ],
                        "required": ["title"]
                    ]
                ],
                [
                    "name": "add_calendar_event",
                    "description": "Create a Calendar event. The user must confirm before it writes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title":     ["type": "string"],
                            "starts_at": ["type": "string", "description": "ISO8601 start"],
                            "ends_at":   ["type": "string", "description": "ISO8601 end"],
                            "notes":     ["type": "string"]
                        ],
                        "required": ["title", "starts_at", "ends_at"]
                    ]
                ],
                [
                    "name": "show_metric_chart",
                    "description": "Render a sparkline chart for a metric over the past N days. Auto-executes — no confirmation needed.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "metric": ["type": "string", "description": "steps | heart_rate | sleep | active_energy | distance | hrv | hydration"],
                            "days":   ["type": "integer", "description": "1-365"]
                        ],
                        "required": ["metric"]
                    ]
                ],
                [
                    "name": "show_comparison_chart",
                    "description": "Compare a metric across two periods, e.g. 'this week vs last week'. App fetches both series from HealthKit and renders side-by-side bars + averages.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title":    ["type": "string", "description": "Card heading e.g. 'Steps · this week vs last'"],
                            "metric":   ["type": "string", "description": "steps | heart_rate | sleep | active_energy | distance | hrv | hydration"],
                            "period_a": ["type": "string", "description": "today | yesterday | this_week | last_week | this_month | last_month | last_7_days | previous_7_days"],
                            "period_b": ["type": "string", "description": "same enum as period_a"]
                        ],
                        "required": ["metric", "period_a", "period_b"]
                    ]
                ],
                [
                    "name": "render_card",
                    "description": "Render a custom glass card with title, optional headline, bullets, and value tiles. Auto-executes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title":    ["type": "string"],
                            "icon":     ["type": "string", "description": "SF Symbol name, e.g. sparkles, flame.fill"],
                            "color":    ["type": "string", "description": "accent | red | green | blue | orange | purple | cyan | yellow"],
                            "headline": ["type": "string", "description": "Short summary line"],
                            "bullets":  ["type": "array", "items": ["type": "string"]],
                            "stats":    [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "label": ["type": "string"],
                                        "value": ["type": "string"]
                                    ],
                                    "required": ["label", "value"]
                                ]
                            ]
                        ],
                        "required": ["title"]
                    ]
                ],
                [
                    "name": "list_reminders",
                    "description": "List reminders the app has created in its own 'Fitness Guru' reminder list. Auto-executes and feeds the items (id, title, due_at, completed) back via functionResponse so you can pick one to update/delete by id. Use this BEFORE update_reminder or delete_reminder.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "filter": ["type": "string", "description": "all | active | completed (default: active)"]
                        ]
                    ]
                ],
                [
                    "name": "list_calendar_events",
                    "description": "List upcoming events in the app's own 'Fitness Guru' calendar over the next N days. Auto-executes and feeds (id, title, starts_at, ends_at, notes) back via functionResponse. Use BEFORE update_calendar_event or delete_calendar_event.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "days_ahead": ["type": "integer", "description": "1-30 (default: 14)"]
                        ]
                    ]
                ],
                [
                    "name": "update_reminder",
                    "description": "Modify an app-created reminder. Requires id from list_reminders. Only non-nil fields are changed. User confirms before the write.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":      ["type": "string"],
                            "title":   ["type": "string"],
                            "due_at":  ["type": "string", "description": "ISO8601, omit to leave unchanged"],
                            "notes":   ["type": "string"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "update_calendar_event",
                    "description": "Modify an app-created calendar event. Requires id from list_calendar_events. Only non-nil fields are changed. User confirms before the write.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":        ["type": "string"],
                            "title":     ["type": "string"],
                            "starts_at": ["type": "string", "description": "ISO8601"],
                            "ends_at":   ["type": "string", "description": "ISO8601"],
                            "notes":     ["type": "string"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "delete_reminder",
                    "description": "Remove an app-created reminder by id. Pass the title too so the confirmation card shows the user what's about to be deleted. User confirms before the delete.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":    ["type": "string"],
                            "title": ["type": "string", "description": "Reminder title (shown on the confirm card)"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "delete_calendar_event",
                    "description": "Remove an app-created calendar event by id. Pass the title too so the confirmation card shows the user what's about to be deleted.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":    ["type": "string"],
                            "title": ["type": "string", "description": "Event title (shown on the confirm card)"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "get_predictions",
                    "description": "On-device prediction snapshot. Returns recovery readiness (0-100 score + label + confidence + why-bullets), next-likely-workout forecast (activity + time window + confidence), goal trajectories (steps/calories/exercise at current pace vs 14-day baseline), and any active sedentary alert. Auto-executes and feeds JSON back via functionResponse. Call FIRST when the user asks 'how should I train', 'am I recovered', 'should I rest', 'on track for goals'. Always surface the confidence + why-bullets — do NOT quote raw numbers as gospel.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "list_food_log",
                    "description": "List meals the user has logged today (via this app's log_food or any other HealthKit-writing nutrition app). Auto-executes and feeds (id, name, calories, protein, carbs, fat, logged_at) back via functionResponse so you can pick a meal to update or delete BY ID. Use this BEFORE update_food_log / delete_food_log — NEVER guess an id.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "update_food_log",
                    "description": "Correct a logged meal in HealthKit. Requires id from list_food_log. Only non-nil fields change (so you can fix just the name, or just the macros, or both). User confirms before the write. The app deletes the existing 4 dietary samples and re-writes fresh ones at the same timestamp.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":       ["type": "string", "description": "Dietary energy sample UUID from list_food_log"],
                            "name":     ["type": "string", "description": "New food name (e.g. 'Potato Waffle Wrap'). Omit to keep existing."],
                            "calories": ["type": "number", "description": "New kcal. Omit to keep existing."],
                            "protein":  ["type": "number", "description": "New protein in grams. Omit to keep existing."],
                            "carbs":    ["type": "number", "description": "New carbs in grams. Omit to keep existing."],
                            "fat":      ["type": "number", "description": "New fat in grams. Omit to keep existing."]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "delete_food_log",
                    "description": "Delete a logged meal from HealthKit by id (from list_food_log). Removes all 4 dietary samples (kcal + protein + carbs + fat) at once. Pass the meal name too so the confirmation card shows the user what's about to be deleted. User confirms before the delete.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":   ["type": "string", "description": "Dietary energy sample UUID from list_food_log"],
                            "name": ["type": "string", "description": "Meal name (shown on the confirm card)"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "create_widget",
                    "description": "Pin a custom widget to the user's Home screen. This is YOUR creative studio — pick from the legacy preset layouts OR compose your own widget from primitive blocks. Max 6 widgets at once (oldest is dropped when full). User must confirm.\n\n==== TWO MODES — pick ONE ====\n\nMODE A — Legacy preset layout. Set `layout` to one of:\n- 'kpi': big number + caption. `headline` = big value, `body` = caption.\n- 'narrative': headline + body. Best for observations / motivation.\n- 'list': up to 5 bullets.\n- 'progress': value + goal + bar. `headline` = current value, `goal_value` = target.\n\nMODE B — COMPOSABLE BLOCKS (preferred for variety). Set `layout` to 'composed' and provide a `blocks` array — each block is one primitive. Order matters; they render top-to-bottom. 2-4 blocks per widget is the sweet spot.\n\nBlock types:\n- {type: 'metric_value', metric_ref?, value?, label?, unit?} — big number; binds live when metric_ref set\n- {type: 'ring', metric_ref?, current?, goal_value?, label?} — animated progress ring; fills on appear\n- {type: 'sparkline', metric_ref, days?} — N-day line of metric history; draws in left→right\n- {type: 'mini_bars', metric_ref, days?} — last N days as bars, color-graded vs avg\n- {type: 'comparison', metric_ref, period_a_days?, period_b_days?, label_a?, label_b?} — twin-bar A-vs-B with delta\n- {type: 'delta', metric_ref, vs_days?} — '+12% vs last 7 days' chip\n- {type: 'bullets', items: [string]} — short list\n- {type: 'text', text} — paragraph\n- {type: 'chip_row', chips: [string]} — small status pills\n- {type: 'quote', text} — italic motivational line\n- {type: 'checklist', items: [string]} — an INTERACTIVE to-do / habit checklist. Each item renders with a tappable checkbox the user ticks off; the checked state persists. THIS is how you make a 'to-do style' health card — daily routines, recovery checklists, habit stacks. 2-6 items.\n- {type: 'button_row', buttons: [{label, icon?, action, value?}]} — one or more tappable action buttons. action MUST be 'coach_prompt' (value = the message sent to you when tapped, e.g. value:'How is my hydration trending?') or 'log_water' (value = millilitres logged to Apple Health, e.g. value:'250'). icon is an optional SF Symbol. Use for quick one-tap actions on a card.\n\nTo-do card example:\n{layout: 'composed', blocks: [\n  {type: 'text', text: 'Today's recovery routine'},\n  {type: 'checklist', items: ['10-min mobility', '2L water', '8h sleep window', '5-min breathing']},\n  {type: 'button_row', buttons: [{label: 'Log a glass', icon: 'drop.fill', action: 'log_water', value: '250'}]}\n]}\n\nExample composed widget:\n{layout: 'composed', blocks: [\n  {type: 'metric_value', metric_ref: 'steps', label: 'Today'},\n  {type: 'sparkline', metric_ref: 'steps', days: 14},\n  {type: 'delta', metric_ref: 'steps', vs_days: 7}\n]}\n\n==== LIVE METRIC REFS ====\nAllowed metric_ref values: steps, heart_rate, active_energy, resting_energy, sleep, distance, hydration, hrv, resting_hr, exercise_minutes, stand_hours, mindful_minutes, flights, vo2_max, walking_speed, step_length, body_mass, health_meter, recovery_score.\n\n==== STYLE ====\n- Icons: thematic SF Symbol names — 'flame.fill' for streaks, 'moon.zzz' for sleep, 'drop.fill' for hydration, 'bolt.heart' for cardio, 'leaf.fill' for recovery, 'sunrise' for morning, 'chart.line.uptrend.xyaxis' for trends.\n- Colors: pick from {accent, red, orange, yellow, green, blue, indigo, purple, pink, cyan, gray}. VARY across widgets — don't always reach for indigo.\n- PREFER composed blocks over the legacy preset menu when the widget needs more than one element. That's where the visual variety lives.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title":       ["type": "string", "description": "Short label shown at the top of the widget. Max ~28 chars."],
                            "icon":        ["type": "string", "description": "SF Symbol name."],
                            "color":       ["type": "string", "description": "One of: accent, red, orange, yellow, green, blue, indigo, purple, pink, cyan, gray"],
                            "layout":      ["type": "string", "description": "One of: kpi, narrative, list, progress, composed"],
                            "headline":    ["type": "string"],
                            "body":        ["type": "string"],
                            "bullets":     ["type": "array", "items": ["type": "string"]],
                            "metric_ref":  ["type": "string"],
                            "goal_value":  ["type": "number"],
                            "blocks": [
                                "type": "array",
                                "description": "Required when layout='composed'. 2-4 ordered primitive blocks. See description for shape.",
                                "items": ["type": "object"]
                            ]
                        ],
                        "required": ["title", "icon", "color", "layout"]
                    ]
                ],
                [
                    "name": "list_widgets",
                    "description": "List the Astra widgets currently pinned to the user's Home. Auto-executes and feeds (id, title, icon, color, layout, headline, body, bullets, metric_ref, goal_value, created_at) back via functionResponse. Use this BEFORE update_widget or delete_widget — you cannot guess an id. Also useful when you want to see what's already pinned before adding more.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "update_widget",
                    "description": "Modify an existing widget by id (from list_widgets). Only non-nil fields change — so you can swap just the color, rewrite just the body, or replace the entire blocks array. User confirms before the write.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":          ["type": "string", "description": "Widget UUID from list_widgets"],
                            "title":       ["type": "string"],
                            "icon":        ["type": "string"],
                            "color":       ["type": "string"],
                            "layout":      ["type": "string"],
                            "headline":    ["type": "string"],
                            "body":        ["type": "string"],
                            "bullets":     ["type": "array", "items": ["type": "string"]],
                            "metric_ref":  ["type": "string"],
                            "goal_value":  ["type": "number"],
                            "blocks": [
                                "type": "array",
                                "description": "Replace the whole blocks array. See create_widget for block shapes.",
                                "items": ["type": "object"]
                            ]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "delete_widget",
                    "description": "Remove a widget from Home by id (from list_widgets). Pass `title` too so the confirmation card shows what's about to go. User confirms before the delete.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id":    ["type": "string"],
                            "title": ["type": "string", "description": "Widget title (shown on the confirm card)"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "update_notes",
                    "description": "Write to your cross-session memory. Call this whenever you learn something worth remembering for future conversations: the user's injury history, preferred workout times, dietary preferences, goals, recurring patterns, or any coaching decision you'd otherwise forget. Overwrite the full blob — include everything you want to remember, not just the new item. Call silently at the end of any turn where you learned something lasting. Examples: 'User prefers morning workouts, has a left knee issue, targets 10 km/week running, dislikes HIIT.' Keep it under 500 words and use bullet points for scannability.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "notes": ["type": "string", "description": "Full updated notes blob — replaces whatever was there. Plain text, bullet points preferred, max 500 words."]
                        ],
                        "required": ["notes"]
                    ]
                ],
                [
                    "name": "get_sleep_pattern",
                    "description": "Returns the user's full on-device sleep pattern (typical bedtime, wake, median duration, restlessness baseline, snore profile, consistency, weekend delay, weekly trend) PLUS the last 5 tracked sessions with motion + snore details. Call this whenever the user asks anything sleep-related — 'how's my sleep', 'am I getting enough', 'should I sleep more', 'why am I tired' — so your answer can cite real per-user numbers instead of universal thresholds. Auto-executes. Returns 'available: false' if the user hasn't tracked any nights yet.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Request
    private func performStreamingRequest(
        prompt: String,
        history: [ChatMessage],
        systemInstruction: String,
        imageData: Data?,
        imageMimeType: String,
        model: String,
        continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
    ) async throws {
        let token = try await VertexAuth.shared.getAccessToken()
        let (sa, _) = try VertexConfig.current()
        let projectId = sa.projectId

        // gemini-3.5-flash is only available via the global routing endpoint
        // — every regional endpoint (us-central1, europe-west1, etc.) returns
        // 404 NOT_FOUND for the 3.x family. Confirmed via direct API ping.
        let urlString = "https://aiplatform.googleapis.com/v1/projects/\(projectId)/locations/global/publishers/google/models/\(model):streamGenerateContent"
        guard let requestURL = URL(string: urlString) else {
            throw NSError(domain: "VertexGeminiClient", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid request URL."])
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Idle timeout: if the connection sits silent for more than 60s mid-stream,
        // URLSession will abort. Total wall-clock cap is enforced separately below.
        request.timeoutInterval = 60

        // Build body as [String: Any] so we can embed the tools manifest (deep nested).
        // History serialization is tool-aware: each ChatMessage may carry a toolCall
        // (model emits a `functionCall` part) and a tool status that, when terminal,
        // gets re-injected as a synthetic user-role `functionResponse` turn so the
        // model can attach its acknowledgment to a specific tool.
        var contents: [[String: Any]] = []
        for msg in history {
            var parts: [[String: Any]] = []
            if !msg.text.isEmpty { parts.append(["text": msg.text]) }
            if msg.role == .model, let call = msg.toolCall {
                var fcPart: [String: Any] = [
                    "functionCall": [
                        "name": call.name,
                        "args": call.asFunctionCallPayload
                    ]
                ]
                // Round-trip the signature Vertex emitted with this call.
                // Required by Gemini 3.x — followups without it fail with
                // 400 INVALID_ARGUMENT.
                if let sig = msg.thoughtSignature, !sig.isEmpty {
                    fcPart["thoughtSignature"] = sig
                }
                parts.append(fcPart)
            }
            if parts.isEmpty { continue }
            contents.append(["role": msg.role.apiRoleName, "parts": parts])

            // After a model message that emitted a tool call, inject a synthetic
            // user-role `functionResponse` whenever the tool reached a terminal state.
            if msg.role == .model, let call = msg.toolCall, let status = msg.toolStatus,
               status == .done || status == .failed || status == .cancelled {
                var response: [String: Any]
                switch status {
                case .done:      response = ["success": true,  "summary": "Action completed successfully."]
                case .failed:    response = ["success": false, "summary": "The action failed to execute."]
                case .cancelled: response = ["success": false, "summary": "The user cancelled this action."]
                default:         response = ["success": false]
                }
                // Merge any structured payload from list-style read tools so the
                // model can reason on the actual items (id, title, due_at, …).
                if let json = msg.toolResultJSON,
                   let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                    response.merge(parsed) { _, new in new }
                }
                contents.append([
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "name": call.name,
                            "response": response
                        ]
                    ]]
                ])
            }
        }
        var userParts: [[String: Any]] = []
        if !prompt.isEmpty { userParts.append(["text": prompt]) }
        if let imageData {
            userParts.append([
                "inlineData": [
                    "mimeType": imageMimeType,
                    "data": imageData.base64EncodedString()
                ]
            ])
        }
        // On tool-follow-up turns the new prompt is empty — the trailing
        // functionResponse already serves as the "user" content for this turn,
        // so don't pad with an empty text part that confuses the model.
        if !userParts.isEmpty {
            contents.append(["role": "user", "parts": userParts])
        }

        // gemini-3.5-flash has reasoning enabled by default — `thoughtsTokenCount`
        // is consumed from `maxOutputTokens` before any visible text is emitted.
        // Read the user's `thinking_level` preference (set from the Coach picker)
        // and translate to a token budget. Medium is the default. Bump the
        // overall cap so visible output always has room AFTER thoughts.
        let thinkingBudget = Self.thinkingBudgetTokens()
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 2500 + thinkingBudget,
                "thinkingConfig": ["thinkingBudget": thinkingBudget]
            ],
            "tools": [toolsManifest]
        ]
        if !systemInstruction.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemInstruction]]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VertexGeminiClient", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from Vertex AI API."])
        }

        guard httpResponse.statusCode == 200 else {
            var responseBody = ""
            do {
                for try await byte in bytes {
                    let scalar = UnicodeScalar(byte)
                    responseBody.append(Character(scalar))
                }
            } catch {}
            print("Vertex AI Error Code \(httpResponse.statusCode): \(responseBody)")
            throw NSError(domain: "VertexGeminiClient", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Vertex AI API error \(httpResponse.statusCode): \(responseBody)"])
        }

        // Brace-matching scanner — extract complete JSON objects from stream
        var braceDepth = 0
        var buffer = ""
        var inString = false
        var escaped = false

        for try await byte in bytes {
            if Task.isCancelled {
                continuation.finish()
                return
            }

            let char = Character(UnicodeScalar(byte))

            if braceDepth > 0 { buffer.append(char) }

            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                switch char {
                case "\"": inString = true
                case "{":
                    braceDepth += 1
                    if braceDepth == 1 { buffer = "{" }
                case "}":
                    braceDepth -= 1
                    if braceDepth == 0 {
                        emitChunks(from: buffer, into: continuation)
                        buffer = ""
                    }
                default: break
                }
            }
        }
    }

    /// Inspect a parsed candidate chunk and emit either text or toolCall chunks.
    /// Translate the user's `thinking_level` AppStorage preference to a
    /// concrete token budget for `thinkingConfig.thinkingBudget`. The Coach
    /// header picker writes "minimal" / "low" / "medium" / "high" into this
    /// key; medium is the default if absent.
    /// Mapping is deliberately conservative — gemini-3.5-flash reasoning is
    /// cheap but high budgets can add seconds to first-token latency.
    nonisolated static func thinkingBudgetTokens() -> Int {
        let level = UserDefaults.standard.string(forKey: "thinking_level") ?? "medium"
        switch level.lowercased() {
        case "minimal", "off", "none", "zero":  return 0
        case "low":                              return 256
        case "high":                             return 4096
        default:                                 return 1024  // medium
        }
    }

    private func emitChunks(from jsonStr: String,
                            into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) {
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let candidates = obj["candidates"] as? [[String: Any]] {
            for cand in candidates {
                guard let content = cand["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else { continue }
                for part in parts {
                    if let text = part["text"] as? String, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                    if let fc = part["functionCall"] as? [String: Any],
                       let name = fc["name"] as? String {
                        let args = (fc["args"] as? [String: Any]) ?? [:]
                        // Capture the sibling `thoughtSignature` — Gemini 3.x
                        // requires it round-trips on every followup that
                        // references this functionCall, else Vertex returns
                        // 400 INVALID_ARGUMENT.
                        if let sig = part["thoughtSignature"] as? String, !sig.isEmpty {
                            continuation.yield(.thoughtSignature(sig))
                        }
                        if let call = ToolCall.fromFunctionCall(name: name, args: args) {
                            continuation.yield(.toolCall(call))
                        }
                    }
                }
            }
        }

        // usageMetadata typically lands in the very last chunk. Yield it as a
        // dedicated .usage event so the view model can attach it to the
        // current model message without parsing JSON itself.
        if let usage = obj["usageMetadata"] as? [String: Any],
           let parsed = TokenUsage(usageMetadata: usage) {
            continuation.yield(.usage(parsed))
            Task { @MainActor in TokenMeter.shared.record(parsed, source: .coach) }
        }
    }
}
