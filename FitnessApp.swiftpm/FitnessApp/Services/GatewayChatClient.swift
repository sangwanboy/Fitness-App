import Foundation

/// Astra's chat client, now speaking to the Atlas AI Gateway's /v1/chat
/// proxy instead of Vertex AI directly. The gateway holds the Google
/// credentials server-side; the app sends the logical model name "chat"
/// and receives Vertex-shaped streaming chunks over SSE, so ChatChunk
/// emission, the tool loop, and TokenMeter accounting are unchanged.
public actor GatewayChatClient {
    public static let shared = GatewayChatClient()

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
        model: String = GatewayConfig.chatModel
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        let capturedSelf = self
        // "chat" is a logical name — the gateway maps it to the concrete
        // Gemini model server-side. No silent fallback to older models: if
        // the backend can't serve it, the error surfaces to the user.

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
            // onTermination fires on finish, error, AND early consumer drop (e.g.
            // the view model returning on a tool call), so the watchdog never
            // outlives the stream it guards.
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled, !work.isCancelled else { return }
                work.cancel()
                continuation.finish(throwing: NSError(
                    domain: "GatewayChatClient", code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "LLM timed out after 2 minutes."]))
            }

            continuation.onTermination = { _ in
                work.cancel()
                watchdog.cancel()
            }
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
                    "description": "Render a rich food info card and let the user confirm logging it to today's diet in Apple Health. Always emit this when the user uploads a food photo OR asks to log/identify a food item — fill in tags/highlights/cautions when relevant. ALWAYS set is_estimate=true and pick a confidence level unless the user gave you exact label nutrition data (then is_estimate=false). Multi-item plates → one call per distinct item. Supports BACKDATING: pass days_ago when the user says 'yesterday' / 'this morning' / 'on Tuesday' / 'N days ago' instead of quietly logging it to today.",
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
                            "confidence":  ["type": "string", "description": "low | medium | high — required when is_estimate is true."],
                            "days_ago":   ["type": "integer", "description": "0 = today (default). 1 = yesterday, up to 7. Use when the user is backdating a meal instead of logging it now."]
                        ],
                        "required": ["name", "calories", "is_estimate"]
                    ]
                ],
                [
                    "name": "log_water",
                    "description": "Log a hydration amount to today's (or a recent day's) Apple Health water total. The user must confirm before it writes. This is the real tool to call whenever the user asks in chat to log water/hydration — distinct from a one-tap button on an Astra-authored widget. Supports BACKDATING via days_ago (0-7) for 'I drank 500ml yesterday' style requests.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "amount_ml": ["type": "number", "description": "Amount of water in millilitres, e.g. 250 for a glass, 500 for a bottle."],
                            "days_ago":  ["type": "integer", "description": "0 = today (default). 1 = yesterday, up to 7."]
                        ],
                        "required": ["amount_ml"]
                    ]
                ],
                [
                    "name": "log_sleep",
                    "description": "Log a sleep session the user reports in chat ('I slept 1:30 to 9', 'napped 2h', 'I slept from 1:30 to now') to Apple Health. The user must confirm before it writes. Use whenever the user states they slept and no matching tracked session exists (check get_sleep_sessions / get_sleep_pattern first if unsure) — do NOT lecture about device tracking or invent an explanation instead of just logging it. Rejected (honestly, no write) if the range is implausible: end not after start, longer than 16h, end in the future, or start more than 7 days ago.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "start": ["type": "string", "description": "ISO8601 date-time (user's TZ) they fell asleep / went to bed — same conversion convention as add_reminder/add_calendar_event."],
                            "end":   ["type": "string", "description": "ISO8601 date-time they woke up. Omit for 'still asleep' / 'until now' phrasing — defaults to right now."]
                        ],
                        "required": ["start"]
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
                    "description": "Render a sparkline chart for a metric over the past N days. Auto-executes — no confirmation needed. Feeds the plotted series stats (points, avg, min, max, latest, change_pct_first_to_last) back via functionResponse: follow up with a brief grounded analysis (2-3 sentences max — trend, notable high/low, one actionable takeaway, quoting the actual numbers). Never re-list the chart's data points.",
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
                    "description": "Compare a metric across two periods, e.g. 'this week vs last week'. App fetches both series from HealthKit and renders side-by-side bars + averages. Auto-executes and feeds per-period stats (avg, min, max, points) plus delta_pct back via functionResponse: follow up with a brief grounded analysis (2-3 sentences max — which period won, by how much, one actionable takeaway, quoting the actual numbers).",
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
                    "description": "Render a custom glass card with title, optional headline, bullets, and value tiles. Auto-executes; a render acknowledgment comes back via functionResponse — follow up with a SINGLE-sentence takeaway. Never re-list the card's contents.",
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
                    "description": "Pin a custom widget to the user's Home screen. This is YOUR creative studio — you have FULL CREATIVE LICENSE over composition, color, icon, and copy. Be bold, varied, and surprising-but-useful: mix block types freely, combine checklist + buttons + metrics + sparklines, and invent layouts the user hasn't seen. Pick from the legacy preset layouts OR (preferred) compose your own widget from primitive blocks. Max 6 widgets at once (oldest is dropped when full). User must confirm.\n\n==== TWO MODES — pick ONE ====\n\nMODE A — Legacy preset layout. Set `layout` to one of:\n- 'kpi': big number + caption. `headline` = big value, `body` = caption.\n- 'narrative': headline + body. Best for observations / motivation.\n- 'list': up to 5 bullets.\n- 'progress': value + goal + bar. `headline` = current value, `goal_value` = target.\n\nMODE B — COMPOSABLE BLOCKS (this is where the magic lives — favor it). Set `layout` to 'composed' and provide a `blocks` array — each block is one primitive. Order matters; they render top-to-bottom. 2-4 blocks per widget is the sweet spot. Combine block types in unexpected, fitting ways — a checklist over a ring, a metric_value + sparkline + delta trio, a quote + mini_bars, a comparison + chip_row + button_row.\n\nBlock types:\n- {type: 'metric_value', metric_ref?, value?, label?, unit?} — big number; binds live when metric_ref set\n- {type: 'ring', metric_ref?, current?, goal_value?, label?} — animated progress ring; fills on appear\n- {type: 'sparkline', metric_ref, days?} — N-day line of metric history; draws in left→right\n- {type: 'mini_bars', metric_ref, days?} — last N days as bars, color-graded vs avg\n- {type: 'comparison', metric_ref, period_a_days?, period_b_days?, label_a?, label_b?} — twin-bar A-vs-B with delta\n- {type: 'delta', metric_ref, vs_days?} — '+12% vs last 7 days' chip\n- {type: 'bullets', items: [string]} — short list\n- {type: 'text', text} — paragraph\n- {type: 'chip_row', chips: [string]} — small status pills\n- {type: 'quote', text} — italic motivational line\n- {type: 'checklist', items: [string]} — an INTERACTIVE to-do / habit checklist. Each item renders with a tappable checkbox the user ticks off; the checked state persists. THIS is how you make a 'to-do style' health card — daily routines, recovery checklists, habit stacks. 2-6 items.\n- {type: 'button_row', buttons: [{label, icon?, action, value?}]} — one or more tappable action buttons. action MUST be 'coach_prompt' (value = the message sent to you when tapped, e.g. value:'How is my hydration trending?') or 'log_water' (value = millilitres logged to Apple Health, e.g. value:'250'). icon is an optional SF Symbol. Use for quick one-tap actions on a card.\n\nTo-do card example:\n{layout: 'composed', blocks: [\n  {type: 'text', text: 'Today's recovery routine'},\n  {type: 'checklist', items: ['10-min mobility', '2L water', '8h sleep window', '5-min breathing']},\n  {type: 'button_row', buttons: [{label: 'Log a glass', icon: 'drop.fill', action: 'log_water', value: '250'}]}\n]}\n\nExample composed widget:\n{layout: 'composed', blocks: [\n  {type: 'metric_value', metric_ref: 'steps', label: 'Today'},\n  {type: 'sparkline', metric_ref: 'steps', days: 14},\n  {type: 'delta', metric_ref: 'steps', vs_days: 7}\n]}\n\n==== LIVE METRIC REFS (use ONLY these) ====\nAllowed metric_ref values: steps, heart_rate, active_energy, resting_energy, sleep, distance, hydration, hrv, resting_hr, exercise_minutes, stand_hours, mindful_minutes, flights, vo2_max, walking_speed, step_length, body_mass, health_meter, recovery_score.\n\n==== STYLE — GO BOLD ====\n- Icons: pick expressive, fitting SF Symbol names — 'flame.fill' for streaks, 'moon.zzz' for sleep, 'drop.fill' for hydration, 'bolt.heart' for cardio, 'leaf.fill' for recovery, 'sunrise' for morning, 'chart.line.uptrend.xyaxis' for trends, and reach for unexpected, on-topic symbols too.\n- Colors: pick from {accent, red, orange, yellow, green, blue, indigo, purple, pink, cyan, gray}. VARY WIDELY across widgets so no two look alike — rotate the palette, don't reuse one color.\n- FAVOR composed blocks and MIX them — that's where the visual variety and delight come from. A single metric_value alone is a missed opportunity.\n\n==== HARD LIMITS (fixed — everything else is yours) ====\n- Max 6 widgets; user confirms every create. Use only the block types and metric_ref values listed above.",
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
                    "description": "Legacy free-text cross-session notes blob — superseded by remember_fact / update_profile. Do NOT use this for new information; call remember_fact (one atomic fact) or update_profile (full section rewrite) instead. Kept only for continuity with notes saved before the structured-memory migration.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "notes": ["type": "string", "description": "Full updated notes blob — replaces whatever was there. Plain text, bullet points preferred, max 500 words."]
                        ],
                        "required": ["notes"]
                    ]
                ],
                [
                    "name": "remember_fact",
                    "description": "Store a durable, atomic fact about the user in structured long-term memory: a goal, injury/limitation, preference, schedule habit, nutrition note, or other lasting context worth recalling in future sessions. Call it whenever the user shares something lasting or corrects a prior assumption. Do NOT use it for trivia or one-off numbers HealthKit already tracks (today's steps, a single workout, this meal) — those are live data, not memory. ONLY store what the user explicitly stated or confirmed — never your own inference, guess, or explanation for something you don't actually know. Schedule/temporary facts (shift patterns, travel, a short-term injury) MUST state their timeframe in the text itself, e.g. 'on night shift through Thursday' — the stored fact shows its own noted date, but not an end date, so the text has to carry that. One idea per call. Auto-executes silently, no user confirmation. Response confirms what was saved and names any older fact evicted (hard cap of 60 facts, oldest dropped first).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "category": ["type": "string", "description": "goal | injury | preference | schedule | nutrition | context"],
                            "text":     ["type": "string", "description": "The fact itself, concise — e.g. 'Left knee sensitive to high-impact running, avoid box jumps.'"]
                        ],
                        "required": ["category", "text"]
                    ]
                ],
                [
                    "name": "forget_fact",
                    "description": "Remove a previously stored memory fact that's outdated, wrong, or the user asked you to forget. Pass a short query describing it — matched by substring against stored fact text (e.g. 'left knee', 'HIIT'). Auto-executes silently. Response says exactly what was removed, or that nothing matched.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string", "description": "Words identifying the fact to remove"]
                        ],
                        "required": ["query"]
                    ]
                ],
                [
                    "name": "update_profile",
                    "description": "Rewrite one section of the user's long-term profile: summary | goals | trainingContext | injuriesLimitations | preferences | nutritionNotes. Replaces the FULL section content, not a diff — call get_profile first if you need to see what's already there before editing. Use this for durable, structured personalization; use remember_fact instead for a single standalone fact. ONLY include statements the user explicitly made or confirmed — never your own inferences or speculation dressed up as fact. Any schedule/temporary detail folded in here must state its own timeframe. Auto-executes silently, no user confirmation.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "section": ["type": "string", "description": "summary | goals | trainingContext | injuriesLimitations | preferences | nutritionNotes"],
                            "content": ["type": "string", "description": "Full replacement text for this section — a few sentences or short bullet lines, not a wall of text."]
                        ],
                        "required": ["section", "content"]
                    ]
                ],
                [
                    "name": "get_profile",
                    "description": "Read the user's full long-term profile (every section) plus every stored memory fact and live basics (age, height, weight, VO2max, resting HR from Apple Health). Auto-executes and feeds it back via functionResponse. Call this before update_profile when you want to see current content, or when the user asks what you remember about them.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "get_metric_history",
                    "description": "Daily history for ANY tracked HealthKit metric over the last N days (max 90). Auto-executes and feeds {metric, unit, days, daily: [{date, value}], avg, min, max, latest, change_pct} back via functionResponse — ground your answer in those numbers. Returns available:false when the user has no data for that metric (say so honestly). Call this for any metric question the inline system-prompt blocks don't already answer. Valid metric values: steps, heart_rate, active_energy, sleep, distance, hrv, hydration, resting_heart_rate, body_mass, flights_climbed, exercise_minutes, stand_hours, mindful_minutes, oxygen_saturation, vo2_max, resting_energy, walking_speed, walking_step_length, walking_double_support, walking_asymmetry, headphone_audio.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "metric": ["type": "string", "description": "One of the valid metric values listed in the tool description."],
                            "days":   ["type": "integer", "description": "1-90 (default 30)"]
                        ],
                        "required": ["metric"]
                    ]
                ],
                [
                    "name": "get_sleep_pattern",
                    "description": "Returns the user's full on-device sleep pattern (typical bedtime, wake, median duration, restlessness baseline, snore profile, consistency, weekend delay, weekly trend) PLUS the last 5 tracked sessions with motion + snore details. Call this whenever the user asks anything sleep-related — 'how's my sleep', 'am I getting enough', 'should I sleep more', 'why am I tired' — so your answer can cite real per-user numbers instead of universal thresholds. Auto-executes. Returns 'available: false' if the user hasn't tracked any nights yet.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "update_goal",
                    "description": "Update one of the user's daily goals. Confirmation-gated — the user approves the change on a card before anything is written; streaks, challenges, and pace predictions adapt instantly after. Use it when the user agrees to adjust a goal or explicitly asks for a new target. Deterministic goal suggestions (with current goal, suggested goal, and median 28-day attainment) appear inline in the PREDICTIONS system-prompt block — propose them via this tool ONLY when the user engages with goals; never apply unprompted.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "metric": ["type": "string",
                                       "enum": ["steps", "activeEnergy", "sleep", "distance", "hydration",
                                                "exerciseMinutes", "standHours", "mindfulMinutes", "flightsClimbed"],
                                       "description": "Which user-configurable goal to change."],
                            "value":  ["type": "number", "description": "The new daily goal in the metric's native unit (steps, kcal, hours, mi, L, min, hrs, min, flights respectively). Clamped to the metric's allowed range."]
                        ],
                        "required": ["metric", "value"]
                    ]
                ],
                [
                    "name": "set_date_of_birth",
                    "description": "Update the user's stored birth date. Call this whenever the user states their birth date in chat — this is the ONLY way a conversational birthday reaches the structured store that HR-zone math and the Live Basics profile card read, so skipping this call leaves the user with two disagreeing ages. Confirmation-gated: the user approves the change on a card before anything writes, since it affects heart-rate zone targets. Rejects (honestly, no write) if the derived age would be outside 5-120 years — double-check the date with the user in that case rather than guessing which part they meant.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "date": ["type": "string", "description": "Birth date as YYYY-MM-DD, e.g. '1998-03-04'."]
                        ],
                        "required": ["date"]
                    ]
                ],
                [
                    "name": "set_nutrition_targets",
                    "description": "Set Astra's own daily protein and/or calorie coaching target(s) — shown against today's actual intake on the Nutrition dashboard. Confirmation-gated: the user approves before anything is saved, so NEVER call this to silently apply a number — only after the user agrees to a specific target you proposed, or asks you to set one directly. For hypertrophy / muscle-gain goals, suggest an evidence-based protein target (roughly 1.6-2.2 g/kg bodyweight/day) using the user's weight from Live Basics when they ask about nutrition or protein, then offer to set it via this tool. Pass only the field(s) that changed — at least one of protein_g / kcal is required.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "protein_g": ["type": "number", "description": "Daily protein target in grams. Sane range 20-400."],
                            "kcal":      ["type": "number", "description": "Daily calorie target in kcal. Sane range 800-6000."]
                        ]
                    ]
                ],
                [
                    "name": "get_sleep_sessions",
                    "description": "Per-night detail for the user's last N on-device tracked sleep sessions, newest first. Auto-executes and feeds {nights: [{date, duration_h, onset (minutes to fall asleep), restlessness_pct, snore_episodes, snore_total_min, stages {deep_h, light_h, awake_h}}]} back via functionResponse. Call when the user asks about a specific night or wants night-by-night detail beyond the aggregate SLEEP PATTERN block / get_sleep_pattern. Returns available:false when no sessions are tracked yet.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "nights": ["type": "integer", "description": "1-14 (default 7)"]
                        ]
                    ]
                ],
                [
                    "name": "get_training_plan",
                    "description": "Read the user's active Astra-authored weekly training plan (this week, and next week if authored) plus per-day completed flags and adherence. Auto-executes and feeds it back via functionResponse. Returns an honest 'no plan set yet' when nothing has been authored. Call this before proposing any plan so your suggestion is grounded in what was actually done vs planned — and whenever the user asks what's on their schedule.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ],
                [
                    "name": "set_training_plan",
                    "description": "Author (or replace) the user's active weekly training plan. Confirmation-gated — the user reviews a preview of the whole week before anything is written. Replaces whatever plan currently exists (its previously-created calendar events are removed first, only ones this app made). PROPOSE a plan ONLY when the user asks for one, or accepts your offer during a weekly-review discussion — grounded in the TRAINING LOAD block, the user's goals/profile, and recent adherence from get_training_plan. NEVER call this unprompted. For each non-rest day the app creates a Calendar event automatically at a sensible default time; if calendar access is denied the plan still saves and the functionResponse carries a `note` field explaining events were skipped — relay that honestly, never claim events were created when they weren't.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "week_start": ["type": "string", "description": "Monday of the plan's first week, YYYY-MM-DD."],
                            "days": [
                                "type": "array",
                                "description": "1-14 days (covers the current week and optionally next). Plan every day of the week explicitly, including rest days (kind='rest') — don't just omit off days.",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "date":         ["type": "string",  "description": "YYYY-MM-DD"],
                                        "title":        ["type": "string",  "description": "Short session title, e.g. 'Push — chest focus'"],
                                        "detail":       ["type": "string",  "description": "The session's full prescription, max ~700 characters. Strength/mobility days MUST list every exercise with sets×reps, semicolon-separated (e.g. 'Incline DB press 3×8-10; Cable flyes 3×12; Push-ups 3×AMRAP; rest 90s between sets'). Cardio: modality + zone/intensity + structure (e.g. 'Zone 2 cycling, 40 min steady, HR 120-135'). Rest days: recovery focus (sleep, hydration, protein). Never a vague summary — the user trains directly from this text."],
                                        "kind":         ["type": "string",  "description": "strength | cardio | mobility | rest"],
                                        "duration_min": ["type": "integer", "description": "10-240"]
                                    ],
                                    "required": ["date", "title", "detail", "kind", "duration_min"]
                                ]
                            ]
                        ],
                        "required": ["week_start", "days"]
                    ]
                ],
                [
                    "name": "mark_workout_done",
                    "description": "Mark a planned training-plan day complete. Confirmation-gated. Requires an active plan with a day matching the given date — call get_training_plan first if you're unsure what's scheduled.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "date": ["type": "string", "description": "YYYY-MM-DD — the planned day to mark complete."]
                        ],
                        "required": ["date"]
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
        // Build the gateway messages array. History serialization is
        // tool-aware: each ChatMessage may carry a toolCall (model emits a
        // `functionCall` part) and a tool status that, when terminal, gets
        // re-injected as a synthetic user-role `functionResponse` turn so the
        // model can attach its acknowledgment to a specific tool.
        var messages: [[String: Any]] = []
        for msg in history {
            var parts: [[String: Any]] = []
            if !msg.text.isEmpty { parts.append(GatewayChatPayload.textPart(msg.text)) }
            if msg.role == .model, let call = msg.toolCall {
                // Round-trip the thoughtSignature Gemini emitted with this
                // call — required by 3.x; followups without it fail with 400
                // INVALID_ARGUMENT. Part-level sibling, functionCall parts only.
                parts.append(GatewayChatPayload.functionCallPart(
                    name: call.name,
                    args: call.asFunctionCallPayload,
                    thoughtSignature: msg.thoughtSignature
                ))
            }
            if parts.isEmpty { continue }
            messages.append(GatewayChatPayload.message(role: msg.role.apiRoleName, parts: parts))

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
                messages.append(GatewayChatPayload.message(
                    role: "user",
                    parts: [GatewayChatPayload.functionResponsePart(name: call.name, response: response)]
                ))
            }
        }
        var userParts: [[String: Any]] = []
        if !prompt.isEmpty { userParts.append(GatewayChatPayload.textPart(prompt)) }
        if let imageData {
            userParts.append(GatewayChatPayload.imagePart(data: imageData, mimeType: imageMimeType))
        }
        // On tool-follow-up turns the new prompt is empty — the trailing
        // functionResponse already serves as the "user" content for this turn,
        // so don't pad with an empty text part that confuses the model.
        if !userParts.isEmpty {
            messages.append(GatewayChatPayload.message(role: "user", parts: userParts))
        }

        // The chat model has reasoning enabled by default — `thoughtsTokenCount`
        // is consumed from `maxOutputTokens` before any visible text is emitted.
        // Read the user's `thinking_level` preference (set from the Coach picker)
        // and translate to a token budget. Medium is the default. Bump the
        // overall cap so visible output always has room AFTER thoughts.
        let thinkingBudget = Self.thinkingBudgetTokens()
        let body = GatewayChatPayload.body(
            model: model,
            stream: true,
            system: systemInstruction,
            messages: messages,
            tools: [toolsManifest],
            generationConfig: [
                "temperature": 0.4,
                "maxOutputTokens": 2500 + thinkingBudget,
                "thinkingConfig": ["thinkingBudget": thinkingBudget]
            ]
        )

        // Idle timeout 90s (was 60): this also bounds the wait for the FIRST
        // byte, and the gateway absorbs upstream Vertex 429s by retrying
        // internally — first-token latency can legitimately reach 45-90s
        // during a quota burst (same class as the one-shot timeout fixes).
        // There is NO separate wall-clock watchdog in the caller (an older
        // comment here claimed one); this idle timeout is the only bound.
        // Each yielded element is one Vertex-shaped JSON chunk — the SSE
        // framing is handled inside GatewayTransport.
        let events = try await GatewayTransport.streamChat(body: body, idleTimeout: 90)
        for try await eventData in events {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            emitChunks(from: eventData, into: continuation)
        }
    }

    /// Inspect a parsed candidate chunk and emit either text or toolCall chunks.
    /// Translate the user's `thinking_level` AppStorage preference to a
    /// concrete token budget for `thinkingConfig.thinkingBudget`. The Coach
    /// header picker writes "minimal" / "low" / "medium" / "high" into this
    /// key; medium is the default if absent.
    /// Mapping is deliberately conservative — flash-class reasoning is
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

    private func emitChunks(from data: Data,
                            into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

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
            // cachedContentTokenCount is the slice of promptTokenCount Gemini's
            // implicit prompt caching served from cache — a SUBSET of
            // `parsed.prompt`, not an additional charge. `TokenUsage` doesn't
            // carry this field (its Codable shape lives in Models/ChatMessage.swift,
            // out of scope for this change), so read it straight off the raw
            // dict and thread it through as TokenMeter's own counter.
            let cachedTokens = (usage["cachedContentTokenCount"] as? Int) ?? 0
            Task { @MainActor in TokenMeter.shared.record(parsed, source: .coach, cachedTokens: cachedTokens) }
        }
    }
}
