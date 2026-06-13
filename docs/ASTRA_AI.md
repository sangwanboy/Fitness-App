# ASTRA / VERTEX AI INTEGRATION

Developer reference for the AI coaching layer of Fitness Guru. Covers every component
from credential loading through the streaming pipeline, tool execution, system-prompt
assembly, history persistence, and token accounting.

**Source files referenced throughout:**
- `Services/VertexConfig.swift`
- `Services/VertexAuth.swift`
- `Services/VertexGeminiClient.swift`
- `Services/PredictionAIService.swift`
- `Services/TokenMeter.swift`
- `ViewModels/ChatViewModel.swift`
- `Models/ToolCall.swift`
- `Models/ChatMessage.swift`
- `Services/ChatHistoryStore.swift`

---

## Table of Contents

1. [Auth Flow](#1-auth-flow)
2. [Model and Endpoint Facts](#2-model-and-endpoint-facts)
3. [Streaming Pipeline](#3-streaming-pipeline)
4. [Tool Registry](#4-tool-registry)
5. [Confirm / Cancel / Follow-up Flow](#5-confirm--cancel--follow-up-flow)
6. [System-Prompt Assembly](#6-system-prompt-assembly)
7. [Chat History Persistence](#7-chat-history-persistence)
8. [Token Meter](#8-token-meter)
9. [PredictionAIService](#9-predictionaiservice)
10. [Safety Rails](#10-safety-rails)
11. [Invariants: Never-Fake-Writes and No-Watch-Hallucination](#11-invariants-never-fake-writes-and-no-watch-hallucination)

---

## 1. Auth Flow

### Credential sources (`Services/VertexConfig.swift`)

`VertexConfig.current()` loads a `ServiceAccount` struct (fields: `project_id`,
`client_email`, `private_key`, `token_uri`) from one of two sources in priority order:

| Priority | Source | Storage |
|---|---|---|
| 1 (wins) | User-pasted JSON | `UserDefaults` key `vertex_service_account_json` |
| 2 (fallback) | Bundled file | `vertex-service-account.json` in the app bundle |

The returned tuple is `(ServiceAccount, Source)` where `Source` is `.userPasted`,
`.bundled`, or `.none`. When the pasted JSON is present but malformed, `current()` throws
immediately with a descriptive error instead of silently falling through to the bundle.
Both `VertexAuth` and `VertexGeminiClient` call `VertexConfig.current()` independently so
they always agree on which credentials are active.

Helper API: `VertexConfig.setPastedJSON(_:)`, `clearPastedJSON()`, `hasPastedJSON`.

### JWT creation and OAuth2 exchange (`Services/VertexAuth.swift`)

`VertexAuth.shared` is a `class` (not an actor). Thread safety on the cache fields is
provided by a `private let cacheLock = NSLock()` that is **never held across an `await`**.

```
getAccessToken()
  → VertexConfig.current()          // determine which SA to use
  → cacheLock.lock() / unlock()     // check cached token
  → if valid → return cached
  → refreshAccessToken(sa)
       → createJWT(...)
       → POST sa.tokenUri (Google OAuth2)
       → cacheLock.lock() / unlock() // write cache
```

**JWT construction** (`createJWT`):
- Header: `{"alg":"RS256","typ":"JWT"}`
- Claims: `iss` = `clientEmail`, `scope` = `https://www.googleapis.com/auth/cloud-platform`,
  `aud` = `tokenUri`, `iat` = now, `exp` = now + 3600
- Signing: `SecKeyCreateSignature` with `.rsaSignatureMessagePKCS1v15SHA256`

**PKCS#8 → PKCS#1 stripping** (`loadPrivateKey` / `extractPKCS1RSAKey`):
Google service-account JSON files embed the private key as a PKCS#8 PEM block
(`-----BEGIN PRIVATE KEY-----`). `SecKeyCreateWithData` with `kSecAttrKeyTypeRSA` expects
raw PKCS#1. `VertexAuth` detects the wrapper by checking for the `BEGIN PRIVATE KEY` header
and, if present, walks the DER ASN.1 tree to extract the inner OCTET STRING. If the key
already starts with `BEGIN RSA PRIVATE KEY` it is used as-is. The code also normalises
literal `\n` escape sequences that some JSON serializers produce inside the `private_key`
field.

**Token cache invalidation**: the cache stores `cachedClientEmail` alongside the token.
`getAccessToken()` treats a cache hit as a miss when `cachedClientEmail != sa.clientEmail`,
so switching credentials (pasting a new key) transparently re-exchanges. The public
`invalidateCache()` method lets the Settings UI force an immediate refresh.

**Token expiry**: the cached token expires at `expiresIn - 60` seconds (one-minute buffer)
to avoid using a token in the last seconds of its lifetime.

---

## 2. Model and Endpoint Facts

| Property | Value |
|---|---|
| Model ID | `gemini-3.5-flash` |
| Endpoint host | `aiplatform.googleapis.com` |
| Location segment | `global` |
| Streaming method | `streamGenerateContent` |
| One-shot method | `generateContent` |

**Why `global` only**: the 3.x Gemini model family is not published on regional Vertex AI
endpoints (us-central1, europe-west1, etc.) — those return `404 NOT_FOUND`. This is noted
in both `VertexGeminiClient` and `PredictionAIService` as a confirmed-by-direct-API-ping
constraint. The full URL pattern is:

```
https://aiplatform.googleapis.com/v1/projects/{projectId}/locations/global/publishers/google/models/gemini-3.5-flash:streamGenerateContent
```

**Thinking / reasoning configuration**:

`gemini-3.5-flash` has on-device reasoning enabled by default. The user configures the
budget via a "thinking level" picker that writes the key `thinking_level` into
`UserDefaults`. `VertexGeminiClient.thinkingBudgetTokens()` (a `nonisolated static func`)
reads it at request time:

| `thinking_level` value | Budget tokens |
|---|---|
| `"minimal"` / `"off"` / `"none"` / `"zero"` | 0 |
| `"low"` | 256 |
| `"medium"` (default) | 1024 |
| `"high"` | 4096 |

`PredictionAIService.streamGeminiSSE` and `callGeminiJSON` call this same static helper so
all three call sites share one budget-resolution path.

**`thinkingConfig` placement**: the config is nested **inside** `generationConfig`:

```json
{
  "generationConfig": {
    "temperature": 0.4,
    "maxOutputTokens": 2500,
    "thinkingConfig": { "thinkingBudget": 1024 }
  }
}
```

Placing `thinkingConfig` at the top level of the request body is invalid and will be
rejected by the API.

**`maxOutputTokens`**: always set to `2500 + thinkingBudget` in the chat client. This
ensures the budget for internal thoughts does not consume the visible-output quota. Both
`PredictionAIService` sub-calls follow the same `maxTokens + thinkingBudget` pattern.

---

## 3. Streaming Pipeline

### Request construction (`VertexGeminiClient.performStreamingRequest`)

The request body is built as `[String: Any]` (not `Codable`) so that the tool manifest —
a deeply nested dictionary — can be embedded without bridging layers. Key body fields:

| Field | Value |
|---|---|
| `contents` | Serialized history + new user turn |
| `generationConfig` | temperature 0.4, maxOutputTokens, thinkingConfig |
| `tools` | `[toolsManifest]` (the full 24-tool `functionDeclarations` array) |
| `systemInstruction` | `{"parts": [{"text": "..."}]}` (omitted if empty) |

`URLRequest.timeoutInterval` is set to 60 seconds (idle per-connection timeout). A separate
120-second wall-clock watchdog `Task` is started via `continuation.onTermination` and
cancels the work task if it is still running. The watchdog cancels itself when the stream
terminates normally.

### History serialization

Each `ChatMessage` in `history` is serialized role-by-role:

- **User messages**: `{"role": "user", "parts": [{"text": "..."}]}`. Image attachments are
  inlined as `{"inlineData": {"mimeType": "image/jpeg", "data": "<base64>"}}`.
- **Model messages**: `{"role": "model", "parts": [{"text": "..."}]}`. When the message
  carries a `toolCall`, the part gains a `functionCall` entry with `name` and `args`
  (reconstructed via `ToolCall.asFunctionCallPayload`). The `thoughtSignature` is attached
  as a sibling key on the same part when non-nil (see below).
- **Synthetic `functionResponse` turns**: after any model message whose `toolStatus` is
  `.done`, `.failed`, or `.cancelled`, a synthetic `{"role": "user", "parts": [{"functionResponse": {...}}]}` turn is inserted. For read tools that produced a JSON
  payload (`toolResultJSON`), the payload dict is merged into the `functionResponse.response`
  object so the model can reason on the actual items.

### SSE brace-scanner

`performStreamingRequest` does not use standard SSE (`data:` / `event:` framing). The
Vertex streaming endpoint returns a JSON array split across HTTP chunks. The scanner
extracts complete JSON objects using brace depth counting with correct string-escape
handling:

```swift
var braceDepth = 0; var buffer = ""; var inString = false; var escaped = false
// For each byte:
//   if in string: handle escape / closing quote
//   else: { → depth++, buffer start; } → depth--; at depth==0 → emit
```

Each complete object is passed to `emitChunks(from:into:)`.

### `ChatChunk` enum (`Models/ToolCall.swift`)

```swift
public enum ChatChunk {
    case text(String)              // incremental text delta
    case toolCall(ToolCall)        // parsed function call
    case usage(TokenUsage)         // usageMetadata from last chunk
    case thoughtSignature(String)  // blob that must round-trip on followups
}
```

`emitChunks` walks `candidates[].content.parts[]`. Each part is examined:

- `"text"` key present and non-empty → `.text(delta)`
- `"functionCall"` key present → capture sibling `"thoughtSignature"` first (`.thoughtSignature(sig)`), then parse `ToolCall.fromFunctionCall(name:args:)` → `.toolCall(call)`
- Top-level `"usageMetadata"` → `TokenUsage(usageMetadata:)` → `.usage(usage)`, then
  immediately posts to `TokenMeter.shared.record(usage, source: .coach)` via a
  `Task { @MainActor in … }`.

### THOUGHT-SIGNATURE round-trip requirement

Gemini 3.x attaches a `thoughtSignature` blob to any `functionCall` part that involved
internal reasoning. Vertex returns `400 INVALID_ARGUMENT` on any subsequent turn that
references that `functionCall` without re-sending the signature.

The flow:
1. Stream emits `.thoughtSignature(sig)` immediately before `.toolCall(call)`.
2. `ChatViewModel` stores `sig` on `messages[idx].thoughtSignature`.
3. On the next history serialization, `VertexGeminiClient` re-attaches `"thoughtSignature": sig` as a sibling key on the `"functionCall"` part for that message.

The signature is **not** shown in the UI. It is stripped on archive (only text and imageData survive in `SessionMessage`).

---

## 4. Tool Registry

All 24 tools are declared in `VertexGeminiClient.toolsManifest` as `functionDeclarations`
following the OpenAPI-flavored JSON schema Vertex AI expects. The typed Swift counterparts
live in `ToolCall` (Models/ToolCall.swift).

### Tool table

| Tool name | Needs confirmation | Produces payload / followup |
|---|---|---|
| `log_food` | Yes | No |
| `add_reminder` | Yes | No |
| `add_calendar_event` | Yes | No |
| `update_reminder` | Yes | No |
| `update_calendar_event` | Yes | No |
| `delete_reminder` | Yes | No |
| `delete_calendar_event` | Yes | No |
| `update_food_log` | Yes | No |
| `delete_food_log` | Yes | No |
| `create_widget` | Yes | No |
| `update_widget` | Yes | No |
| `delete_widget` | Yes | No |
| `update_goal` | Yes | No |
| `show_metric_chart` | No | Yes (series stats) |
| `show_comparison_chart` | No | Yes (per-period stats + delta_pct) |
| `render_card` | No | Yes (render ack) |
| `list_reminders` | No | Yes (items array) |
| `list_calendar_events` | No | Yes (items array) |
| `get_predictions` | No | Yes (full predictions JSON) |
| `list_food_log` | No | Yes (items array) |
| `list_widgets` | No | Yes (items array + remaining_slots) |
| `update_notes` | No | Yes (success + saved_length) |
| `get_sleep_pattern` | No | Yes (pattern + last-5-sessions JSON) |
| `get_metric_history` | No | Yes (daily values + stats) |
| `get_sleep_sessions` | No | Yes (per-night breakdown) |

`ToolCall.needsConfirmation` and `ToolCall.producesPayload` are computed properties that
drive the branching logic in `ChatViewModel`.

### Notable tool details

**`log_food`**: `is_estimate` defaults to `true` in `fromFunctionCall` even if the model
omits the field. The `confidence` field (`low`/`medium`/`high`) is required when
`is_estimate` is `true`. A multi-item plate should produce one `log_food` call per distinct
item. Tags, highlights, and cautions are all modelled as `[String]` in the Swift enum.

**`create_widget`**: supports two authoring modes — legacy preset layouts (`kpi`,
`narrative`, `list`, `progress`) and composable blocks (`layout: "composed"` with a
`blocks` array). When `blocks` is non-nil, the `executeWriteTool` path forces `layout`
to `.composed` regardless of what the model passed. Maximum 6 widgets; the oldest is
dropped when the cap is exceeded. Widget `metric_ref` values must be one of 19 enumerated
live-binding strings (`steps`, `heart_rate`, `active_energy`, `resting_energy`, `sleep`,
`distance`, `hydration`, `hrv`, `resting_hr`, `exercise_minutes`, `stand_hours`,
`mindful_minutes`, `flights`, `vo2_max`, `walking_speed`, `step_length`, `body_mass`,
`health_meter`, `recovery_score`).

**`update_notes`**: Astra's cross-session memory. Auto-executes without confirmation. The
full notes blob is stored at `UserDefaults` key `"astra_notes"` (max ~500 words). The model
overwrites the entire blob on each call; partial updates are not supported.

**`update_goal`**: write-gated with user confirmation. The metric string is resolved
through `historyMetricType(from:)` to a `HealthMetricType`, validated against
`isUserConfigurableGoal`, and clamped to the type's `goalRange` before calling
`HealthKitManager.shared.setGoal(_:for:)`. Valid metric keys: `steps`, `activeEnergy`,
`sleep`, `distance`, `hydration`, `exerciseMinutes`, `standHours`, `mindfulMinutes`,
`flightsClimbed`.

**`get_metric_history`**: daily history for any of 24 tracked HealthKit types, clamped to
90 days. The payload includes `daily` (array of `{date, value}`), `avg`, `min`, `max`,
`latest`, and `change_pct`. Returns `{available: false, reason: ...}` when the user has no
data for that type.

**EventKit scoping**: `listReminders`, `listCalendarEvents`, `updateReminder`,
`updateCalendarEvent`, `deleteReminder`, and `deleteCalendarEvent` operate exclusively on
the app's own "Fitness Guru" reminder list and calendar via `EventKitManager`. Astra
cannot read or modify the user's personal events or reminders.

---

## 5. Confirm / Cancel / Follow-up Flow

### Tool call lifecycle (`ToolCall.Status`)

```
.pending       // model emitted the call; waiting for user tap
.confirmed     // user tapped Confirm; side-effect executing
.done          // side-effect succeeded
.failed        // side-effect threw or timed out
.cancelled     // user tapped Cancel
.autoExecuted  // read tools that skip confirmation
```

### Path for write tools (confirmation required)

1. `ChatViewModel.sendMessage` receives `.toolCall(call)` from the stream.
2. `messages[idx].toolStatus = .pending`. The stream loop returns (`return`), stopping
   text accumulation.
3. UI renders the tool card with Confirm / Cancel buttons.
4. **Confirm** → `confirmToolCall(messageId:)` sets `.confirmed`, calls
   `executeWriteTool(call)` wrapped in a 60-second `withTimeout`, sets `.done` or
   `.failed`, then calls `sendFollowup()`.
5. **Cancel** → `cancelToolCall(messageId:)` sets `.cancelled`, then calls
   `sendFollowup()` (only if `!isGenerating`).

### Path for read tools (auto-execute, produces payload)

1. `ChatViewModel.sendMessage` receives `.toolCall(call)` where `call.producesPayload == true`.
2. `messages[idx].toolStatus = .autoExecuted`. Stream loop returns.
3. `autoExecuteReadTool(messageId:)` calls `executeReadTool(call)`, encodes the result JSON
   to `messages[idx].toolResultJSON`, sets `.done`, then calls `sendFollowup()`.

### `sendFollowup()`

Re-invokes `VertexGeminiClient.shared.streamGenerateContent` with an empty prompt. The
history serializer injects the matching `functionResponse` part (with the payload if
applicable). The model streams a short acknowledgment as a new model message. If the
follow-up itself produces another `.toolCall`, the same pending/confirmation loop
re-enters — allowing chained tool sequences (e.g., `list_reminders` → model picks an id →
`delete_reminder`).

If the follow-up stream produces no text and no tool call, the empty placeholder bubble
is removed from `messages` to avoid blank bubbles.

### Retry (`retryLast()`)

Finds the most recent `.isError` bubble. If the message before it was a model turn with a
terminal-state tool call, re-fires `sendFollowup()` to retry the acknowledgment. Otherwise
finds the most recent user message and re-fires the full `sendMessage` flow with the same
prompt and imageData.

---

## 6. System-Prompt Assembly

`ChatViewModel.buildSystemInstruction()` is an `async` function called at the start of
every `sendMessage`, `sendFollowup`, and `retryLast` invocation. It first calls
`HealthKitManager.shared.refreshIfStale(maxAgeMinutes: 5)` to ensure the prediction
snapshot is current before reading it.

The assembled string is approximately 9.5k tokens. Its sections in order:

| Section | Content |
|---|---|
| **Identity** | "You are Astra…" — role, tone, brevity directive |
| **USER PROFILE** | Name, sex, DOB/age, height (cm + in), weight (kg + lb), blood type, coach personality, training goals — all from `UserDefaults`; DOB falls back to HealthKit characteristics |
| **YOUR MEMORY** | `UserDefaults["astra_notes"]` — the full blob Astra wrote via `update_notes`. "No notes yet" when empty |
| **MEDICAL PROFILE** | Allergies, conditions, medications from `HealthKitManager.readClinicalRecords()`. "None known" when absent. Includes a gating directive when conditions/meds are present |
| **LOCALE** | `TimeZone.current.identifier`, metric vs. imperial label |
| **TODAY'S METRICS** | Live values for steps/goal, active cal/goal, sleep/goal, distance/goal, latest HR, RHR, HRV, VO₂ max, SpO₂. "—" for any missing metric |
| **PREDICTIONS** | Full structured breakdown from `predictionsFullBlock(hk.predictions)` — health meter (4 sub-scores + bullets), recovery (score + bullets + watch-tag), next-likely-workout, trajectories, sedentary alert, anomalies, illness early-warning, cross-metric correlations, periodization phase, tonight's sleep forecast, goal suggestions with advisory note |
| **SLEEP PATTERN** | Inline block from `sleepPatternInlineBlock()` — session count, summary, restlessness baseline, snore baseline, consistency, weekend delay, weekly trend, current focus-state |
| **NUTRITION TODAY** | `nutritionBlock(calories:protein:log:goals:)` — daily goals line, per-item list with name/time/kcal, or explicit "No meals logged yet today" when empty |
| **LAST 7 DAYS** | Day-by-day history for steps, active calories, sleep, distance, heart rate, resting HR, HRV (via `historySummary(for:)`) — distance and speed values are locale-converted before injection |
| **STREAK & CHALLENGE** | `streakChallengeBlock()` — current and longest workout-week streak, badge count, today's challenge title and completion percentage |
| **BODY & GAIT 7-DAY** | `bodyGaitBlock()` — latest body mass, 7-day walking speed avg, 7-day asymmetry avg (only when data exists) |
| **HYDRATION & MINDFUL 7-DAY** | `hydrationMindfulBlock()` — 7-day avg hydration (L/day), 7-day avg mindful minutes (only when data exists) |
| **RECENT WORKOUTS** | `recentWorkoutsBlock()` — last 3 workouts of the 28-day window: activity type, date, duration, kcal |
| **TRAINING LOAD** *(conditional)* | `trainingLoadBlock()` — acute (7d) vs chronic (28d) kcal-load/day, ACWR, zone label, workout minutes last 7d. Omitted when both values are 0 |
| **HR ZONES** *(conditional)* | `hrZonesLine(userAge:)` — five personalised Karvonen Z1–Z5 BPM ranges (RHR and max HR stated). Omitted when no Watch/HR data |
| **CYCLE** *(conditional)* | `cycleBlock()` — last period start date, days ago, median cycle length. Omitted when no menstrual-flow samples |
| **SYMPTOMS** *(conditional)* | `symptomsBlock()` — last 5 of 14-day HealthKit symptom entries with severity and recency. Omitted when none |
| **DATA SEMANTICS** | Rules for interpreting "—", 0, and Watch-class metric absence |
| **PERSONAL BASELINES** | Instruction to prefer the user's 7-day mean over universal cutoffs; 1.5× SD flag rule |
| **SAFETY RAILS** | (see Section 10) |
| **ALLERGY HANDLING** | "None known" semantics; cross-check `log_food` cautions against listed allergies; generic common-allergen notes when list is empty |
| **TOOLS** | Per-tool directives (see Section 4 for the table; the system prompt adds usage guidance, sequence requirements, and brevity constraints for each) |
| **WIDGET STUDIO** | Detailed composition rules for `create_widget` — both authoring modes, all block types, live metric ref list, hard limits |
| **NEVER FAKE WRITES** | (see Section 11) |
| **SCOPE / DECISIVENESS / MULTI-TOOL / TREND-AWARE** | Behavioural directives |
| **OUTPUT FORMAT** | Markdown structure — opening takeaway sentence, `### Section` headings, bullet style, bold for numbers, required `Next:` line, ~600 token budget |
| **BREVITY / IMAGE HANDLING / EXAMPLE SHAPE** | Trim priority order and food/equipment image protocols |

---

## 7. Chat History Persistence

### Live session slot (`Services/ChatHistoryStore.swift`)

The live (on-screen) conversation is persisted to `UserDefaults` key
`"chat_live_session_v1"` after every settled turn (message append, stream end, tool status
change). This is done via `persistLiveSnapshot()` in `ChatViewModel`, which is guarded by
`isViewingArchivedSession` — a read-only replay cannot overwrite the live slot.

On launch, `ChatViewModel.init()` calls `ChatHistoryStore.shared.loadLive()`. If the
result is non-empty, the conversation is restored (`messages = restored.map { $0.toChatMessage() }`). Empty result → fresh greeting message.

### Archives

When the user taps "New Chat" or loads a past session:
1. `archiveCurrent()` is called if `hasArchivableConversation` (at least one user turn,
   not viewing an archived session).
2. `ChatHistoryStore.archive(messages:)` converts to `[SessionMessage]`, checks whether
   the current conversation is an extension of the most-recently-archived session (dedupe
   by message-ID prefix), and inserts or updates accordingly.
3. Archive is capped to 30 sessions (`maxSessions`); oldest entries are dropped.
4. The archive is stored as a JSON-encoded `[ChatSession]` in `UserDefaults` key
   `"astra_chat_history_v1"`.

### `SessionMessage` (compact archive format)

Only `id`, `role`, `text`, `createdAt`, and `imageData` survive archiving. The following
fields are intentionally stripped on archive:

- `toolCall` and `toolStatus` — tool cards are not re-playable
- `toolResultJSON` — payload is ephemeral
- `tokenUsage` — not needed for display
- `thoughtSignature` — only valid for the live API round-trip

A `SessionMessage` with empty text and no `imageData` is dropped during `compactMap`
(e.g., bare tool-card placeholder bubbles).

### Session title derivation

The title is the first non-empty user message text, trimmed to 40 characters with a
trailing ellipsis if longer. Falls back to `"New chat"`.

---

## 8. Token Meter

### `TokenUsage` (`Models/ChatMessage.swift`)

```swift
public struct TokenUsage: Codable, Equatable {
    public let prompt: Int     // promptTokenCount
    public let output: Int     // candidatesTokenCount
    public let thoughts: Int   // thoughtsTokenCount (0 for non-reasoning models)
    public let total: Int      // totalTokenCount
}
```

Parsed from `usageMetadata` in the last SSE chunk. Returns `nil` when all counts are zero
(errored turns).

### `TokenMeter` (`Services/TokenMeter.swift`)

`@MainActor public final class TokenMeter: ObservableObject`. Singleton at `TokenMeter.shared`.

Tracks lifetime totals across four `TokenSource` values:

| Source | Description |
|---|---|
| `.coach` | Chat turns via `VertexGeminiClient` |
| `.insights` | `PredictionAIService` (daily insight, action chips, anomaly text, "Why?" sheet) |
| `.foodVision` | Food photo scan via `FoodVisionService` |
| `.other` | Reserved |

Per call to `record(_ usage: TokenUsage, source: TokenSource)`, the meter increments:

- Aggregate: `prompt`, `output`, `thoughts`, `total`, `calls`
- Per-source dicts: `bySource`, `callsBySource`, `promptBySource`, `outputBySource`,
  `thoughtsBySource`

All data is persisted as a `Snapshot` struct in `UserDefaults` key `"token_meter_v1"`. The
schema is forward-compatible: the per-type prompt/output/thoughts breakdowns were added
later and are `Optional` in the `Snapshot` so older stored blobs still decode.

### Cost estimation (`GeminiPricing`)

```swift
public enum GeminiPricing {
    public static let inputPerMillion: Double  = 1.50  // $/M input tokens
    public static let outputPerMillion: Double = 9.00  // $/M output tokens
    public static let thinkingPerMillion: Double = 9.00 // thoughts billed at output rate
}
```

Source: Google list pricing for gemini-3.5-flash, May 2026. These are estimates — actual
billing can differ (caching, batch discounts, taxes). `GeminiPricing.cost(prompt:output:thoughts:)` is used by `TokenMeter.totalCost` and `cost(for:)`. Displayed in
`Views/TokenUsageView.swift`.

`TokenFormat.compact(_:)` formats token counts as `"12.3K"` / `"1.2M"` for chips.

---

## 9. PredictionAIService

`public actor PredictionAIService` (`Services/PredictionAIService.swift`). Uses the same
model (`gemini-3.5-flash`) and `global` location as the chat client. Timeout: 12 seconds
for one-shot JSON calls.

### `enrichPredictions(_:userContext:)`

Runs three sub-tasks in parallel via `async let`:

| Sub-task | API call type | Output |
|---|---|---|
| `generateDailyInsight` | `generateContent` + `responseMimeType: "application/json"` | `DailyInsight?` (headline, body, confidence) |
| `suggestActions` | `generateContent` + JSON | `[ActionSuggestion]` (up to 3 tappable chips) |
| `interpretAnomalies` | `generateContent` + JSON | `[UUID: String]` (per-anomaly explanation) |

If all three sub-tasks fail, the method throws (signals a transport problem). If 1–2 fail,
the bundle is returned with the successful fields; the failed sections are nil or empty.

In-flight deduplication: a concurrent call while one is already running `await`s the same
`Task` instead of hitting the API twice.

### `explainPrediction(_:predictions:userContext:)`

A `nonisolated` function returning `AsyncThrowingStream<WhyStreamEvent, Error>`. Calls
`streamGeminiSSE(prompt:maxTokens:continuation:)` with a `maxTokens: 2000` budget. The
stream yields `.text(String)` deltas and a trailing `.usage(TokenUsage)` event recorded to
`TokenMeter` with source `.insights`.

The prompt is built by `whyPrompt(kind:predictions:userContext:)` and includes a
per-`PredictionKind` output shape (from `whyOutputShape(for:)`) that instructs the model
on which contributing factors to enumerate and in which order. Supported kinds: `.recovery`,
`.nextWorkout`, `.trajectory`, `.sedentary`, `.healthMeter`, `.illness`, `.correlations`,
`.periodization`, `.sleepForecast`, `.goalSuggestions`.

### `callGeminiJSON`

One-shot `generateContent` helper. When `responseJSON: true`, sets
`generationConfig.responseMimeType = "application/json"`. Respects the shared
`thinkingBudget` so the thinking token cost doesn't starve the visible JSON payload.
Records usage to `TokenMeter` with source `.insights`.

---

## 10. Safety Rails

The following directives are enforced via the system prompt (assembled in
`buildSystemInstruction()`):

| Rail | Trigger | Astra behaviour |
|---|---|---|
| Acute injury / pain | User mentions pain during exercise | Stop session, no push-through; suggest clinician for recurring/severe pain |
| Out-of-range backstops | RHR > 100 sustained; sleep < 4 h; HR ≥ 90% estimated max at rest | Flag explicitly; Tanaka formula (208 − 0.7 × age) for estimated max unless measured |
| HRV flagging | HRV notably below user's own 7-day baseline | Flag; avoid absolute cutoffs |
| Disordered eating | Aggressive deficit > 1%/week body weight, fasting > 24 h, restriction-coded requests | Refuse; redirect to sustainable habits |
| Overtraining | High 7-day load + HRV trending down or RHR trending up | Prioritize recovery |
| Cardiac condition | In MEDICAL PROFILE | Cap zone 3+; defer to cardiology |
| Asthma | In MEDICAL PROFILE | Environmental cues |
| Pregnancy | Disclosed by user (may not be in records) | Avoid contraindicated movements; recommend OB consult |
| Diabetes | In MEDICAL PROFILE | Fueling around insulin / meds |
| Beta-blockers | In MEDICAL PROFILE medications | Use RPE instead of HR-zone targets |
| Diuretics | In MEDICAL PROFILE medications | Flag hydration risk |
| Anticoagulants | In MEDICAL PROFILE medications | Flag contact-sport risk |
| Minors (age < 18) | Derived from DOB | No caloric deficits; conservative volume; adult/clinician oversight |
| Illness early-warning | `illnessWarning` in predictions snapshot | Describe as "physiological strain" — NEVER diagnose; no illness/disease/infection language |
| Allergy cross-check | `log_food` tool call | Match against MEDICAL PROFILE allergies; surface conflicts in `cautions` |
| Generic allergen disclosure | `log_food` when allergy list is empty | Note common allergens (peanuts, tree nuts, shellfish, dairy, gluten, soy, eggs) in `cautions` without claiming safety either way |
| Standing disclaimer | When advice is clinical or diagnostic | One line: "I'm not a medical professional — confirm with your doctor." |

---

## 11. Invariants: Never-Fake-Writes and No-Watch-Hallucination

These two rules are explicitly stated in the system prompt and are architectural
requirements, not soft guidelines.

### NEVER FAKE WRITES

The system prompt contains:

> You can ONLY claim to have updated / logged / deleted / scheduled something if you
> actually invoked the matching tool in THIS turn and the tool's confirmation state
> was `.done`.

This applies to all write tools: `log_food`, `update_food_log`, `delete_food_log`,
`add_reminder`, `update_reminder`, `delete_reminder`, `add_calendar_event`,
`update_calendar_event`, `delete_calendar_event`. If Astra hasn't called the tool and
received `.done`, it must say it will perform the action — not that it has.

The `confirmToolCall(messageId:)` path enforces this at the app layer: the tool-card UI
only transitions to `.done` after `executeWriteTool` returns `true`. The follow-up Gemini
turn receives a `functionResponse` with `success: true` only then, so the model's
acknowledgment is grounded in the actual result.

### NO WATCH HALLUCINATION

From the DATA SEMANTICS block in the system prompt:

> Watch-class metrics (HR, HRV, RHR, exercise/stand minutes, VO₂max, SpO₂) require a
> Watch / wearable. If those are all "—" you're iPhone-only — coach around steps /
> distance / sleep / nutrition.

Astra must not invent or imply Watch-derived values when HealthKit returned "—". The system
prompt further states:

> "—" or null = HealthKit returned no record. NEVER invent or imply a value.

The recovery score in the predictions block carries a `watchTag` note ("estimated from
sleep + load (no Watch HRV/RHR)") when `!usedHRV && !usedRHR`, which surfaces this
limitation in both the inline PREDICTIONS block and the `get_predictions` payload.

Similarly, `PredictionAIService.whyPrompt` for the `.healthMeter` kind includes an
explicit guard:

```
"m.usedNutrition && !m.mealsLoggedToday"
  ? " — score is from the last 7 days; the user has NOT logged any food today,
      never claim they did"
  : ""
```

This prevents the model from claiming the user logged food today when the nutrition score
is carried over from historical data.
