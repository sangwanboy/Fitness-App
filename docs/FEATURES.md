# Fitness Guru — Feature Catalog

> Build sequence 3004 · ~30 k LOC · 79 Swift files · iOS 26 Liquid Glass · Target: iPhone 17 Pro

This document is a reference for engineers maintaining the app. Every entry is
grounded in actual source code; no feature is inferred. File paths are relative
to `FitnessApp.swiftpm/FitnessApp/`.

---

## Table of Contents

1. [App shell & navigation](#1-app-shell--navigation)
2. [Home dashboard](#2-home-dashboard)
3. [Astra Coach (chat)](#3-astra-coach-chat)
4. [Food logging](#4-food-logging)
5. [Workouts](#5-workouts)
6. [Sleep](#6-sleep)
7. [Predictions card](#7-predictions-card)
8. [Astra Widget Studio](#8-astra-widget-studio)
9. [Progress hub](#9-progress-hub)
10. [Calendar](#10-calendar)
11. [Reminders](#11-reminders)
12. [Onboarding](#12-onboarding)
13. [Settings / Profile](#13-settings--profile)
14. [Supporting services](#14-supporting-services)

---

## 1. App shell & navigation

**Entry point:** `ContentView.swift`

| Detail | Value |
|---|---|
| Tab bar | iOS 26 native `TabView` — auto-applies Liquid Glass to bar |
| Tabs | Home · Coach · Reminders · Progress · Profile |
| Auth guard | `@AppStorage("is_onboarded")` / `@AppStorage("is_logged_in")` gate tabs |
| Modals | `WorkoutTrackerView`, `SleepModeView`, `CalendarView` overlay as fullscreen slides (`.zIndex(50)`), not sheets, so the tab bar stays hidden |
| Loading screen | `AppLoadingScreen` sits at `.zIndex(200)`; minimum 1.7 s brand hold, then fades |
| Periodic sync | Silent `Timer.publish(every: 15)` re-runs `fetchTodayData()` while app is active |
| Foreground sync | `scenePhase == .active` also triggers a fetch so data is always fresh after switching apps |
| Prefill bus | `ChatPrefillBus.shared` lets any view queue a Gemini prompt or composer seed; `ContentView` watches it and switches to the Coach tab automatically |

---

## 2. Home dashboard

**Entry point:** `Views/DashboardView.swift`

### 2.1 Card grid system

The home is a single `ScrollView` containing a `GlassEffectContainer` (native iOS 26 backdrop-coalescing). Cards are arranged in packed rows — narrow cards pair into two-column rows; wide cards span the full row. Width decisions are computed by `packedRows` (mirrors CSS `grid-column: span 2`).

**Wide card IDs:** `coach`, `predictions`, `activity`, `upcoming`, `workouts`, `meals`, `widgets`, `tracksleep`, `challenge`

**Ordered card list** (stored in `@AppStorage("home_cards_list")`):
```
coach, predictions, widgets, activity, upcoming, steps, heart,
tracksleep, sleep, calories, distance, meals, recovery, hydration,
workouts, streak, challenge
```

### 2.2 Auto-hide / promote logic

- `cardHasData(_:)` decides whether each card renders in the primary grid.
- Cards with no recent data are hidden from the grid and pushed into **Show More** (`showMoreMetrics` toggle). "Recent" = any non-zero sample in the last 7 days, or today's value > 0.
- **Always-visible cards** (never hidden): `coach`, `predictions`, `tracksleep`.
- **Watch-gated cards** (`activity`, `heart`, `recovery`): hidden entirely when `HealthKitManager.hasWatchClassData` is false — shown in Show More instead with "No data yet" tiles.
- **Auto-promote:** any non-canonical metric that *does* have recent 7-day data (e.g. weight, walking speed) is appended to the grid automatically via `HealthMetricType.allCases` scan.

### 2.3 Card types

| Card ID | SwiftUI component | Data source |
|---|---|---|
| `coach` | Inline `coachCardView` | Deterministic HRV/RHR/steps teaser text — no AI call |
| `predictions` | `PredictionsCard` | `HealthKitManager.predictions` |
| `widgets` | `WidgetsCard` | `AstraWidgetStore.shared` |
| `activity` | `ActivityRingsCard` | Deep-links to Apple Health |
| `upcoming` | Inline `upcomingWorkoutCardView` | `EventKitManager.events` (next 24 h) |
| `workouts` | Inline `weeklyWorkoutsCardView` | `workoutDates` Set (last 7 days HK workouts) |
| `meals` | `MealsCard` | `HealthKitManager.todayFoodLog` |
| `tracksleep` | `SleepTrackingCard` | `SleepSessionStore.shared` + `SleepFocusDetector.shared` |
| `streak` | `StreakCard` | `StreakEngine.shared` |
| `challenge` | `DailyChallengeCard` | `ChallengeEngine.shared` |
| `steps` | `StepsCard` | `metricSummaries[.steps]` |
| `heart` | `HeartCard` | `metricSummaries[.heartRate]` |
| `sleep` | `SleepCard` | `metricSummaries[.sleep]` |
| `calories` | `CaloriesCard` | `metricSummaries[.activeEnergy]` |
| `distance` | `DistanceCard` | `metricSummaries[.distance]` |
| `recovery` | `RecoveryCard` | `metricSummaries[.hrv]` |
| `hydration` | `HydrationCard` | `metricSummaries[.hydration]` |
| promoted metrics | `SimpleMetricCard` | `metricSummaries[type]` |

### 2.4 Toolbar

- **Camera** (`camera.viewfinder`): opens `FoodScanView` fullscreen
- **Search** (`magnifyingglass`): `HomeSearchSheet`
- **Calendar**: calls `onOpenCalendar` → overlays `CalendarView`
- **Avatar**: switches to Profile tab

### 2.5 Refresh

Pull-to-refresh calls `healthKitManager.invalidateAIPredictionCache()` then `refreshAllData()`. `refreshAllData()` is also called on `.onAppear` if data is stale (>5 min since last refresh). A `fg.workout.saved` notification forces a re-fetch immediately.

### 2.6 Detail drill-down

Tapping a metric card sets `selectedMetric: HealthMetricType?`, which presents `DetailedMetricView` as a sheet. `HeartCard` also has a context menu to open `HeartRateZonesView`.

---

## 3. Astra Coach (chat)

**Entry point:** `Views/ChatView.swift`  
**ViewModel:** `ViewModels/ChatViewModel.swift`

### 3.1 Streaming chat

- `ChatViewModel.sendMessage(_:imageData:)` calls `VertexGeminiClient.shared.streamGenerateContent(...)` using model `gemini-3.5-flash` via the **global** Vertex AI endpoint.
- Streaming chunks are typed as `ChatChunk`: `.text(delta)`, `.toolCall(call)`, `.usage(TokenUsage)`, `.thoughtSignature(sig)`.
- Text is flushed to the message bubble at most every 50 ms (`streamFlushInterval = 0.05 s`) to avoid O(n²) markdown re-parses per streaming delta.
- Thought signatures round-trip on tool calls; `thinkingConfig` only lives inside `generationConfig`.

### 3.2 Suggestion chips

Four static chips displayed above the composer when idle: "How was my sleep?", "Plan tomorrow", "Why am I tired?", "Suggest a workout". Tap sends the chip text as a message.

### 3.3 Image attachment (photo + camera)

- Camera button opens a `confirmationDialog` → **Take Photo** (presents `CameraImagePicker` fullscreen) or **Choose from Library** (`PhotosPicker`).
- Selected image is downscaled to ≤1200 px, JPEG q=0.7 off the main actor, then staged as a preview bubble.
- Staged image is sent to Gemini as an inline part alongside the text prompt.
- Default prompt for image-only messages: `"What is this? Give me full details."`.

### 3.4 Message rendering

`ChatMessageRow` renders each message:
- **User bubble**: gradient background (accent → purple), renders attached image thumbnail (decoded once per row via `.task(id:)` to avoid re-render cost).
- **Model bubble**: Liquid Glass `glassEffect(.regular.interactive())`, parses markdown via `StructuredMarkdownText`.
- Markdown rendered via `AttributedString(markdown:)` with `interpretedSyntax: .full`.

### 3.5 Tool call cards

When the model emits a `.toolCall`, `ToolCallCard` renders inline with a Confirm / Cancel pair. Read tools (list_reminders, list_calendar_events, get_predictions, list_food_log, etc.) **auto-execute** (`call.producesPayload == true`) without user confirmation, then immediately fire a follow-up Gemini turn. Write tools (log_food, add_reminder, add_calendar_event, etc.) wait for explicit user confirmation. Tool execution is bounded by a 60 s timeout (`withTimeout`).

**Full tool list (from `ChatViewModel`):**

| Tool | Kind | What it does |
|---|---|---|
| `list_reminders` | read | Returns app-scoped reminders (active/completed/all filter) |
| `list_calendar_events` | read | Returns app calendar events for N days ahead |
| `get_predictions` | read | Serializes `HealthKitManager.predictions` snapshot |
| `list_food_log` | read | Today's HealthKit dietary samples |
| `update_notes` | read (write side-effect) | Saves Astra's notes to `UserDefaults("astra_notes")` |
| `get_sleep_pattern` | read | Structured per-user sleep pattern + last 5 sessions |
| `list_widgets` | read | Current widget slots + remaining capacity |
| `show_metric_chart` | read | Stats for a metric's N-day history (used by chart ToolCards) |
| `show_comparison_chart` | read | Period A vs B stats for a metric |
| `render_card` | read | Acknowledges card render |
| `get_metric_history` | read | Daily bucketed history for any HealthKit metric |
| `get_sleep_sessions` | read | Last N on-device tracked sleep sessions |
| `log_food` | write | Writes dietary sample to HealthKit |
| `add_reminder` | write | Creates EKReminder in app calendar |
| `add_calendar_event` | write | Creates EKEvent in app calendar |
| `update_goal` | write | Updates a metric goal via `HealthKitManager.setGoal` |
| `create_widget` | write | Appends a new `AstraWidget` to `AstraWidgetStore` |

### 3.6 Retry

Error bubbles (`message.isError == true`) surface a "Retry" button that calls `viewModel.retryLast()`, re-sending the last user message.

### 3.7 Token chips

Completed model bubbles show `TokenUsageChip` beneath the text: thinking tokens · output tokens · Σ total, rendered at 10 pt. Source is `message.tokenUsage: TokenUsage` populated from Gemini's `usageMetadata`.

### 3.8 Chat history

Toolbar "clock" button opens `ChatHistorySheet` (from `ChatHistoryStore.shared`). Sessions listed newest-first, swipe-to-delete. Tapping a session loads it read-only via `viewModel.loadSession(_:)`. The live conversation is persisted to a "live slot" whenever a turn settles; archived sessions go to `ChatHistoryStore`. Backgrounding or leaving the tab calls `viewModel.archiveCurrent()`.

### 3.9 Thinking level

Toolbar "brain" icon opens a `Picker` with four levels: Minimal / Low / Medium / High. Stored in `@AppStorage("thinking_level")` and injected into `generationConfig.thinkingConfig` on each request.

### 3.10 Prefill bus

`ChatPrefillBus.shared` has two channels:
- `queue(_:)` — auto-sends the prompt immediately when `ChatView` appears.
- `queueComposerSeed(_:)` — pre-fills the composer text field, focuses the keyboard; user reviews before sending.

---

## 4. Food logging

**Entry points:**
- `Views/FoodScan/FoodScanView.swift` — fullscreen coordinator
- `Views/FoodScan/FoodCameraView.swift` — camera + barcode scanner
- `Views/FoodScan/FoodAnalyzingView.swift` — analyzing spinner
- `Views/FoodScan/FoodReviewSheet.swift` — editable review + Astra correction
- `Views/NutritionDashboardView.swift` — full nutrition analytics

### 4.1 Photo vision logging

`FoodScanView` is a state machine with phases:

```
.camera → .analyzing(image) → .review(image, result) → [logged]
                                    ↓
                              .noFood(image)
                              .error(image, message)
```

1. User captures or picks a photo in `FoodCameraView`.
2. Image is downscaled to ≤1200 px JPEG q=0.7 (same pipeline as chat).
3. `FoodVisionService.shared.recognizeFood(imageData:)` sends the JPEG to Gemini and returns `FoodRecognitionResult` (array of `RecognizedFoodItem` each with name, portion, kcal, protein, carbs, fat, confidence, `is_estimate`).
4. `FoodReviewSheet` shows each item as an editable row: checkbox to include/exclude, pencil to open `ItemEditSheet`, trash to delete.
5. Macro totals update live from checked items.
6. "Log This Meal" writes each included item to HealthKit via `HealthKitManager.logFood(...)`, then calls `refreshDietaryNow()` so `MealsCard` and Health Meter update immediately.

### 4.2 Barcode / QR scanning

`FoodCameraView` runs a `AVCaptureMetadataOutput` pipeline in parallel with the photo flow. On a successful scan:

1. Phase transitions to `.lookingUpProduct(code)`.
2. `BarcodeProductService.shared.lookup(barcode:)` hits the **Open Food Facts** API.
3. If a product photo URL exists, `fetchProductImage(url:)` downloads it (10 s timeout, best-effort).
4. Result is wrapped into a `FoodRecognitionResult` and flows through the same `FoodReviewSheet` as a vision result.

**Error states:**
- `.productNotFound` — product not in Open Food Facts DB.
- `.productError(message, barcode)` — network/malformed; retryable with original barcode.

### 4.3 Astra correction chat

Inside `FoodReviewSheet`, an inline "Ask Astra to fix it" chat box calls `FoodVisionService.shared.refineFood(imageData:currentItemsJSON:instruction:)`. This re-runs Gemini with the original photo + current item JSON + the user's plain-English correction ("the chicken is skinless", "remove the tacos"). The returned `FoodRecognitionResult` replaces `editableItems` in-place with animation.

### 4.4 Nutrition dashboard

`NutritionDashboardView` is a sheet launched from the Home `MealsCard` or the Progress Hub. It shows:
- Animated macro rings (calories, protein, carbs, fat) vs `MacroGoals`
- Today / Week tab selector
- 7-day trend chart
- Today's logged meals list (from `HealthKitManager.todayFoodLog`)
- Micronutrients section
- Sticky "Scan Meal" / "Log Manually" bar at the bottom
- "Edit goals" opens `MacroGoalsEditorSheet`

---

## 5. Workouts

**Entry points:**
- `Views/WorkoutTrackerView.swift` — live tracker
- `Views/WorkoutAnalyticsView.swift` — training load analytics
- `Views/HeartRateZonesView.swift` — HR zone breakdown

### 5.1 Workout tracker

`WorkoutTrackerView` is a fullscreen modal (overlaid at `.zIndex(50)` in `ContentView`).

- **Type picker:** Outdoor Run, Cycling, Power Walk, Strength — each with a theme color.
- **Live HR:** An `HKAnchoredObjectQuery` on a local `HKHealthStore` streams real Watch-sourced heart rate samples. Displays current BPM, peak BPM, average BPM, and sample count. Shows "—" when no samples arrive (never synthesizes values).
- **Timer:** `Timer.publish(every: 1)` drives `secondsElapsed`. Estimated calories and distance are computed from duration and workout type (no Watch required).
- **Save:** Writes an `HKWorkout` to HealthKit and posts `NotificationCenter` notification `fg.workout.saved`, which triggers a dashboard refresh.
- **Sheets from tracker:** "View Training Analytics" → `WorkoutAnalyticsView`; "HR Zones" → `HeartRateZonesView`; after save → summary sheet.

### 5.2 Training load analytics

`WorkoutAnalyticsView` reads from `TrainingLoadEngine.shared` (populated by `HealthKitManager` after each workout fetch). Displays:
- Acute (7-day) vs chronic (28-day) load in kcal/day
- ACWR (Acute:Chronic Workload Ratio) and zone label (optimal / under-training / high-risk)
- Weekly workout minutes (bar chart, native `Charts`)
- Per-workout breakdown from `recentWorkouts28`

`TrainingLoadEngine` is also the source for the Predictions card's Periodization row and the Coach system prompt.

### 5.3 HR zones

`HeartRateZonesView` reads from `HeartRateZoneCalculator.shared`:
- Five Karvonen zones computed from user age (from `athlete_dob`) and resting HR.
- Optional `maxHROverride` stored in `@AppStorage("max_hr_override")`.
- Per-workout duration-in-zone breakdown (`WorkoutZoneBreakdown` array).
- Weekly zone totals (Mon–Sun) with total active seconds.
- Zone threshold table toggleable via `showThresholds`.

---

## 6. Sleep

**Entry points:**
- `Views/SleepModeView.swift` — fullscreen overnight mode
- `Views/SleepReportView.swift` — morning summary
- `Views/Components/SleepTrackingCard.swift` — Home card
- `Services/SleepSessionManager.swift` — session controller
- `Services/SnoreDetector.swift` — on-device snore detection
- `Services/SleepFocusDetector.swift` — iOS Focus Mode inference
- `Services/SleepPatternAnalyzer.swift` — pattern computation

### 6.1 Sleep tracking card

`SleepTrackingCard` (Home, wide) shows:
- Focus banner when `SleepFocusDetector.sleepFocusLikely` or `isWithinBedtimeWindow` is true.
- Pattern row (typical bedtime, duration) when `pattern.hasEnoughHistory` (≥3 sessions).
- Last session summary row if the last session ended today or yesterday.
- Snore detection toggle (default ON).
- "Track tonight" button → opens `SleepModeView`.

### 6.2 Sleep mode (overnight)

`SleepModeView` is a fullscreen modal that:
- Dims to `brightness = 0.04` after 30 s idle; blanks to `0.0` (OLED saves power). Tap anywhere restores.
- Shows live clock, tracked duration, snore episode count, stillness percentage.
- Runs `SleepSessionManager.shared` to record motion events (CMMotionManager accelerometer), compute restlessness score, and track onset latency.
- Optionally runs `SnoreDetector.shared` (AVAudioEngine + Apple SoundAnalysis `SNClassifierIdentifier.version1`, `NSFocusStatusUsageDescription` not required; needs `NSMicrophoneUsageDescription`). Confidence threshold 0.55; episodes merged within 10 s window.
- On "End session" — saves `SleepSession` to `SleepSessionStore`, presents `SleepReportView`.

### 6.3 Sleep report

`SleepReportView` (fullscreen cover from `SleepTrackingCard.onOpenLast`):
- Header with session date/time.
- Duration card (large number).
- Pattern comparison card (vs prior sessions, shown only when `pattern.hasEnoughHistory`).
- Snore card: episode count, total snore minutes.
- Motion timeline: restlessness score visualization.
- Stage breakdown: deep / light / awake hours (from `SleepSession.stageBreakdown`).
- "Ask Astra" button queues a prefill prompt via `ChatPrefillBus`.
- Save to HealthKit / Discard buttons.

### 6.4 Sleep pattern analysis

`SleepPatternAnalyzer.compute(from:)` (called by cards and system prompt builder):
- Requires ≥3 sessions for stable output (`hasEnoughHistory`).
- Outputs: typical bedtime/wake hour, median duration, best duration, median restlessness, median snore episodes/minutes, consistency score (0–100), weekend delay minutes, weekly trend (vs prior week).

### 6.5 Sleep Focus detector

`SleepFocusDetector` polls `INFocusStatusCenter` every 60 s (cooperative Swift `Task`, cancelled on background). Combines `isInFocus` with a bedtime-window check (median bedtime – 30 min through wake + 30 min) to produce `sleepFocusLikely`. Injected into Astra's system prompt.

---

## 7. Predictions card

**Entry points:**
- `Views/Components/PredictionsCard.swift` — Home card renderer
- `Views/Components/PredictionWhySheet.swift` — Gemini-powered "Why?" sheet
- `Services/PredictionEngine.swift` — pure-math on-device engine (no HealthKit import)
- `Services/PredictionAIService.swift` — AI enrichment layer
- `Models/Prediction.swift` — data models

### 7.1 Engine overview

`PredictionEngine` is a **pure Swift enum with static functions** — no HealthKit imports, no side effects. `HealthKitManager` assembles a `PredictionEngine.Snapshot` (HK data pre-collected) and passes it to the engine. This design makes it unit-testable and fast.

The engine requires ≥7 non-zero step days; shows "Building baseline" progress bar until then (`insufficientHistoryDays`).

### 7.2 Prediction modules

| Module | Model type | How computed |
|---|---|---|
| **Health Meter** | `HealthMeterScore` (0–100) | Composite: Activity/30 + Nutrition/30 + Body/18 + Vitals/22. Degrades gracefully: no meals → neutral nutrition estimate; no height/weight → neutral body score |
| **Recovery** | `RecoveryReadiness` (0–100) | HRV + RHR vs 28-day baselines; falls back to sleep + training load estimate when Watch data absent |
| **Next workout** | `NextWorkoutForecast` | Weekday + hour pattern from last 28 workouts; support = fraction of recent weeks with a workout on that day |
| **Trajectories** | `[GoalTrajectory]` | Linear pace projection from today's pace vs 14-day average EOD baseline |
| **Sedentary alert** | `SedentaryAlert` | Consecutive hours with < 250 steps from `hourlyStepsToday`; moderate ≥2 h, high ≥4 h |
| **Illness warning** | `IllnessWarning` | RHR > 28-day baseline by threshold AND HRV drop AND sleep debt, sustained N consecutive days |
| **Correlations** | `[MetricCorrelation]` | On-device Pearson r across 30-day zero-filled daily arrays (pairs: HRV-sleep, steps-activeEnergy, etc.) |
| **Periodization** | `PeriodizationStatus` | Weekly kcal-load vs 3-week average → phase: build / peak / deload / recover |
| **Goal suggestions** | `[GoalSuggestion]` | 28-day attainment vs current goal → nudge up/down if consistently above/below |
| **Sleep forecast** | `SleepForecast` | Tonight's predicted hours from activity level, training load, and sleep debt vs 14-day baseline |
| **Anomalies** | `[Anomaly]` | Z-score deviation from 28-day baseline for key metrics |

### 7.3 AI enrichment

After the deterministic engine runs, `PredictionAIService` calls Gemini to produce:
- `dailyInsight` — `DailyInsight(headline, body)` shown in the card.
- `actions` — `[ActionSuggestion]` with `prefillPrompt` to pre-fill Coach.
- `anomaly.interpretation` — prose explanation for each anomaly banner.

AI enrichment status is `pending` (pulsing "Thinking…" label), `done`, or `failed` (Retry chip shown).

### 7.4 Time-of-day layout

`orderedBlocks(for:in:currentHour:)` picks up to 4 rows based on the current slot:

| Slot | Hours | Priority order |
|---|---|---|
| Morning | 5–10 | Health Meter, Recovery, Periodization, Next Workout, (Sedentary after 9 AM), Goals, Correlations |
| Midday | 11–14 | Health Meter, Trajectories (×2), Sedentary, Goals, Correlations |
| Evening | 15–20 | Health Meter, Sleep Forecast, Trajectories (×2), Sedentary, Recovery, Goals, Periodization, Correlations |
| Night | 21–4 | Health Meter, Sleep Forecast, Next Workout, Recovery, Periodization, Goals, Correlations |

Illness warning and anomaly banners render above the time-of-day rows regardless of slot.

### 7.5 Why? sheets

Each prediction row has a `WhyButton` that sets `whyKind: PredictionKind?`, presenting `PredictionWhySheet`. The sheet:
- Streams a Gemini explanation specific to the prediction kind and current snapshot values.
- Shows `TokenUsageChip` on completion.
- Has error state with Retry.
- "Continue in Coach" queues a composer seed via `ChatPrefillBus.queueComposerSeed(_:)`.

### 7.6 Action chips

`ActionChipsRow` renders AI-authored chips (from `predictions.actions`). Tapping a chip calls `ChatPrefillBus.shared.queue(action.prefillPrompt)` then `onTapActionChip()` (which switches to the Coach tab in `DashboardView`).

### 7.7 Goal suggestions (inline apply)

`GoalSuggestionRow` shows each suggestion with an "Apply" button. Tap triggers a `confirmationDialog`; confirming calls `HealthKitManager.shared.setGoal(_:for:)` and shows an animated checkmark.

### 7.8 Guided Breathing chip

Always shown at the bottom of the Predictions card when `onOpenBreathe` is wired. Tap opens `GuidedBreathingView` as a sheet.

---

## 8. Astra Widget Studio

**Entry points:**
- `Models/AstraWidget.swift` — data model + block primitives
- `Services/AstraWidgetStore.swift` — persistence (UserDefaults JSON)
- `Views/Components/WidgetsCard.swift` — Home card renderer

### 8.1 Slot capacity

`AstraWidgetStore.maxWidgets` = 6. Remaining slots are returned to Gemini in `list_widgets` payloads so the model knows when the board is full.

### 8.2 Widget authoring (by Astra)

Two authoring modes:

**Legacy preset:** Astra picks a `WidgetLayout` and fills scalar fields.

| Layout | Description |
|---|---|
| `kpi` | Big number + optional caption |
| `narrative` | Headline + body paragraph |
| `list` | Up to 5 bullets |
| `progress` | Value + goal denominator + progress bar |

**Composable blocks (supersedes legacy when `blocks != nil`):** Astra picks 2–4 blocks and orders them. Block types:

| Block type | Description |
|---|---|
| `metric_value` | Live metric reading or literal number |
| `ring` | Animated progress ring (spring-fills on appear) |
| `sparkline` | 14-day line sparkline with draw-in animation |
| `mini_bars` | Last N daily bars, color-graded vs average |
| `comparison` | Two-period side-by-side bars + delta |
| `delta` | Single "+12% vs last 7 days" chip |
| `bullets` | Up to 5 bulleted lines |
| `text` | Prose paragraph |
| `chip_row` | Small status pills (e.g. "Goal hit · Recovery up") |
| `quote` | Italic motivational aphorism |
| `checklist` | Interactive to-do list; checked state persists across launches |
| `button_row` | Action buttons: `coach_prompt` (queues Astra message) or `log_water` (writes to HealthKit) |

### 8.3 Interactive widgets

Widgets containing `checklist` or `buttonRow` blocks set `isInteractive = true`. The Home grid renders these without an outer `Button` wrapper so inner controls receive taps directly. A tap on the tile background still opens the detail sheet.

### 8.4 Metric bindings

`AstraWidget.knownMetricRefs` lists the 18 metric IDs Astra can bind widgets to:
`steps`, `heart_rate`, `active_energy`, `resting_energy`, `sleep`, `distance`, `hydration`, `hrv`, `resting_hr`, `exercise_minutes`, `stand_hours`, `mindful_minutes`, `flights`, `vo2_max`, `walking_speed`, `step_length`, `body_mass`, `health_meter`, `recovery_score`.

Unrecognized refs are silently ignored at render time.

### 8.5 Tool round-trip

`WidgetBlock.from(dict:)` decodes Gemini's loose `[String: Any]` arg shape. `WidgetBlock.asDict` re-encodes for `list_widgets` payloads. `AstraWidget` is `Codable` for UserDefaults persistence.

---

## 9. Progress hub

**Entry point:** `Views/ProgressHubView.swift`

The 4th tab. Staggered card-reveal animation (spring, 6 sequential delays). Sections:

| Section | Card | Opens |
|---|---|---|
| Quick stats row | Step compliance days, HRV, sleep avg | — |
| Activity | `streakHubCard` | `StreakView` |
| Activity | `challengeHubCard` | `DailyChallengeView` |
| Health Analytics | `hrZonesHubCard` | `HeartRateZonesView` |
| Health Analytics | `workoutAnalyticsHubCard` | `WorkoutAnalyticsView` |
| Nutrition | `nutritionHubCard` | `NutritionDashboardView` |
| Mindfulness | `breathingHubCard` | `GuidedBreathingView` |

### 9.1 Weekly streaks & milestones

`StreakView.swift` (opened from streak card):
- Hero section: animated flame (color scales with streak length — gray → orange → deep orange).
- 12-week calendar grid showing which weeks had ≥1 workout.
- Trophy shelf: horizontal scroll of earned badges + locked (grayed) future milestones.
- `StreakEngine.shared` computes `currentStreak`, `longestStreak`, `weeklyActivity`, `earnedBadges` from `HealthKitManager.recentWorkouts28` and today's steps.

### 9.2 Daily challenges

`DailyChallengeView.swift` (opened from challenge card):
- Hero ring with animated `trim` progress and countdown to midnight.
- How-to section explaining the metric target.
- Challenge history list.
- `ChallengeEngine.shared` picks a daily challenge from templates (seeded by date hash for determinism). Dynamic targets (e.g. HRV × 1.1) adjust to the user's baseline. Completion is auto-detected from `HealthKitManager` metric values and triggers a local notification.

### 9.3 Guided breathing

`GuidedBreathingView.swift` (sheet from Progress Hub, Predictions breathe chip, or Coach):
- Built-in protocols: **Box** (4-4-4-4), **4-7-8**, **Coherent** (5.5-5.5), **Custom**.
- Custom phase durations stored in `@AppStorage`: `custom_breath_in`, `custom_breath_hold`, `custom_breath_out`.
- Animated orb (scale 0.7 → 1.0 on inhale, reverse on exhale) with ripple bursts on each phase transition.
- Respects `accessibilityReduceMotion`.
- Managed by `BreathingSessionManager.shared`.

---

## 10. Calendar

**Entry point:** `Views/CalendarView.swift`

Fullscreen modal (overlaid from Home/Dashboard). Backed by `EventKitManager.shared`.

| Feature | Detail |
|---|---|
| View modes | Week strip / Month grid (segmented pill toggle) |
| Day plan | List of `EKEvent` objects for the selected date |
| Weekly plan card | AI-generated suggestions (queued via Coach prefill) |
| Streak banner | Shows current activity streak inline |
| Add event | Sheet with title / start / end — writes `EKEvent` to app-scoped calendar |
| Pull-to-refresh | Re-fetches events for the selected date window |
| "Plan with Astra" | `onOpenChat` callback → queues "Plan my day — add some events to my calendar" in composer seed |

Events and reminders are **app-scoped**: the app creates its own EKCalendar on first access and reads/writes only to that calendar (never touches the user's personal calendars).

---

## 11. Reminders

**Entry point:** `Views/RemindersView.swift`

The 3rd tab. Backed by `EventKitManager.shared`.

| Feature | Detail |
|---|---|
| Sections | Today / Tomorrow / Scheduled (no-date items appear in Scheduled) |
| Categories | Tag-based grouping below sections |
| Add reminder | Sheet with title + due date → writes `EKReminder` to app-scoped reminders list |
| Complete | Tap row → `EventKitManager.complete(reminder:)` |
| Navigation subtitle | "N due today" or "All caught up" |
| Permission prompt | Shown inline when `remindersGranted == false`; links to iOS Settings |
| Astra integration | `list_reminders` / `add_reminder` tools in Coach can read and create reminders |

---

## 12. Onboarding

**Entry point:** `Views/Onboarding/OnboardingView.swift`  
**Screens:** `Views/Onboarding/OnboardingScreens.swift`

Five linear screens; progress dots animate width (active → 22 pt capsule). Navigation is page-by-page (not swipeable `TabView`). Back button on screens 2–5. All screens are dark-mode forced.

| Screen | Name | Content |
|---|---|---|
| 0 | `WelcomeScreen` | App branding, "Get Started" |
| 1 | `AboutYouScreen` | Name, date of birth, height, weight — stored as `AppStorage` |
| 2 | `ConnectScreen` | HealthKit authorization request (`requestAuthorization()`), EventKit |
| 3 | `GoalsScreen` | Training goals multi-select + coach personality picker |
| 4 | `MeetAstraScreen` | Introduces Astra; "Finish" sets `is_onboarded = true` and stamps `account_created_date` |

`OnboardingView` stamps `account_created_date` using `healthKitManager.earliestHistoryDate()` as a backdated value for returning users (upgraders who never saw onboarding).

---

## 13. Settings / Profile

**Entry point:** `Views/SettingsView.swift`

The 5th tab (`NavigationStack { SettingsView() }`).

### 13.1 Sections

| Section | Content |
|---|---|
| Avatar header | Initials avatar, athlete name, "Joined MMM yyyy · N-day step streak" |
| Stat row | Workouts (28 d), HRV (avg 7 d), step streak |
| Connected | HealthKit status + "Re-connect" button; EventKit |
| Coach | Personality picker (Direct / Friendly / Concise / Motivational), Training goals picker |
| Health Records | Clinical records authorization request |
| Vertex AI key | Paste service account JSON; inline status chip (checking / ok / error); test button |
| Appearance | Theme (dark / light toggle), accent color wheel, glass tint + strength |
| Token usage | Taps `TokenUsageView` |
| Account | Sign out |
| Version footer | App version + build |

### 13.2 Goal editor

`GoalsEditorSheet` (from Settings → Daily goals or Profile):
- 9 editable metrics with sliders: steps, active energy, exercise minutes, stand hours, sleep, hydration, distance, mindful minutes, flights climbed.
- Reads from `HealthKitManager.userGoal(for:)`, writes via `setGoal(_:for:)`. Dashboard cards animate live as the slider moves.

### 13.3 Token meter

`TokenUsageView` (Settings → AI token usage):
- Lifetime totals: input, output, thinking tokens.
- Estimated USD cost at gemini-3.5-flash list prices: input $1.50/M, output $9.00/M, thinking $9.00/M (thinking billed at output rate).
- Breakdown card: bar chart by `TokenSource` (Coach chat, Insights & predictions, Food photo scan, Other).
- Reset button (requires confirmation).

### 13.4 Vertex AI key configuration

`VertexConfig` loads credentials in priority order:
1. **User-pasted JSON** (`UserDefaults("vertex_service_account_json")`)
2. **Bundled** `vertex-service-account.json` (gitignored; not in repo)

The Settings section shows which source is active. The JSON paste field validates on "Test Connection" before saving.

### 13.5 Locale units

`LocaleUnits` converts stored imperial values (miles, mph) for display in the current locale. The storage layer is always imperial; display converts via `LocaleUnits.speedDisplay(fromMph:)` and analogous helpers. This is referenced in the Coach system prompt (`bodyGaitBlock()`) and in metric cards.

---

## 14. Supporting services

| Service | File | Purpose |
|---|---|---|
| `HealthKitManager` | `HealthKitManager.swift` | Central HK façade: auth, fetch, write, `metricSummaries`, prediction snapshot assembly |
| `EventKitManager` | `Services/EventKitManager.swift` | App-scoped EKCalendar + EKReminders CRUD |
| `VertexGeminiClient` | `Services/VertexGeminiClient.swift` | `AsyncThrowingStream<ChatChunk>` from Vertex AI global endpoint; 120 s watchdog |
| `VertexAuth` | `Services/VertexAuth.swift` | OAuth 2.0 service-account JWT + token refresh |
| `VertexConfig` | `Services/VertexConfig.swift` | Credential source resolution (pasted > bundled) |
| `FoodVisionService` | `Services/FoodVisionService.swift` | `recognizeFood` + `refineFood` Gemini calls |
| `BarcodeProductService` | `Services/BarcodeProductService.swift` | Open Food Facts lookup + product photo fetch |
| `PredictionEngine` | `Services/PredictionEngine.swift` | Pure-math on-device engine; no HealthKit import |
| `PredictionAIService` | `Services/PredictionAIService.swift` | AI enrichment: daily insight, action chips, anomaly interpretation |
| `TrainingLoadEngine` | `Services/TrainingLoadEngine.swift` | Acute/chronic load, ACWR, periodization phase |
| `HeartRateZoneCalculator` | `Services/HeartRateZoneCalculator.swift` | Karvonen zone thresholds; per-workout zone breakdown |
| `SleepSessionManager` | `Services/SleepSessionManager.swift` | Accelerometer-based sleep recording + restlessness scoring |
| `SnoreDetector` | `Services/SnoreDetector.swift` | AVAudioEngine + SoundAnalysis ML snore detection |
| `SleepFocusDetector` | `Services/SleepFocusDetector.swift` | INFocusStatusCenter poll + bedtime-window inference |
| `SleepPatternAnalyzer` | `Services/SleepPatternAnalyzer.swift` | Aggregate pattern stats from N sessions |
| `StreakEngine` | `Services/StreakEngine.shared` | Weekly activity streak, badges, 12-week grid |
| `ChallengeEngine` | `Services/ChallengeEngine.swift` | Date-seeded daily challenge + completion detection |
| `BreathingSessionManager` | `Services/BreathingSessionManager.swift` | Breathing phase timer + protocol registry |
| `TokenMeter` | `Services/TokenMeter.swift` | Lifetime token accumulator by `TokenSource` |
| `ChatHistoryStore` | `Services/ChatHistoryStore.swift` | Session archive + live slot persistence |
| `AstraWidgetStore` | `Services/AstraWidgetStore.swift` | Widget CRUD + checklist item toggle persistence |
| `NutritionService` | `Services/NutritionService.swift` | Macro goals, carbs/fat aggregation |
| `NotificationManager` | `Services/NotificationManager.swift` | Local notification scheduling (challenges, reminders) |

---

*Last updated: build sequence 3004.*
