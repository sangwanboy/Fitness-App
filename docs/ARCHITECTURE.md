# Fitness Guru — Architecture Reference

> Build sequence: 3004 | ~30 k LOC | 79 Swift files | iOS 26 minimum
> Target device: iPhone 17 Pro (`6EBFD630-1768-512E-95E3-EC7D76AA8CDD`)

---

## Table of Contents

1. [Layer Map](#1-layer-map)
2. [Five-Tab Structure and ContentView Wiring](#2-five-tab-structure-and-contentview-wiring)
3. [HealthKitManager — Central Data Hub](#3-healthkitmanager--central-data-hub)
4. [On-Device Engines vs the AI Layer](#4-on-device-engines-vs-the-ai-layer)
5. [Singletons and Shared State](#5-singletons-and-shared-state)
6. [Recompute and Refresh Cadence](#6-recompute-and-refresh-cadence)
7. [Cross-Cutting Patterns](#7-cross-cutting-patterns)
8. [Data-Flow Diagram](#8-data-flow-diagram)

---

## 1. Layer Map

The source tree under `FitnessApp.swiftpm/FitnessApp/` is partitioned into five first-class layers. Each layer has a clear ownership contract; the boundaries are enforced by convention, not by Swift packages.

```
FitnessApp/
├── FitnessApp.swift          # @main entry point, app-lifecycle hooks
├── ContentView.swift         # Root view: tab bar + modals + prefill bus wiring
├── HealthKitManager.swift    # Central data hub (2 121 lines)
│
├── Models/                   # Pure value types and protocols. No I/O, no UI.
├── Services/                 # Singletons that own I/O or long-lived state.
├── ViewModels/               # Observable objects bridging Services → Views.
├── Views/
│   ├── *.swift               # Full-screen tab views and modal flows.
│   ├── Components/           # Reusable sub-views (cards, overlays, sheets).
│   ├── FoodScan/             # Food photo flow (camera → analysis → review).
│   └── Onboarding/           # First-launch walkthrough.
└── Assets.xcassets
```

### Models (`Models/`)

Codable/Equatable value types and enums only. No HealthKit imports, no network calls, no `@Published`.

| File | What it defines |
|---|---|
| `HealthMetric.swift` | `HealthMetricType` enum (23 cases), `MetricSummary`, `MetricValue`, `LocaleUnits` |
| `Prediction.swift` | All prediction output types: `RecoveryReadiness`, `NextWorkoutForecast`, `GoalTrajectory`, `SedentaryAlert`, `HealthMeterScore`, `Predictions`, `SymptomEntry`, `ActivityCategory`, etc. |
| `ChatMessage.swift` | `ChatMessage`, `MessageRole`, streaming and tool-status fields |
| `ToolCall.swift` | `ToolCall` enum — one case per Gemini function declaration (18 cases) |
| `SleepSession.swift` | `SleepSession`, `MotionSample`, `MotionKind` |
| `SleepPattern.swift` | `SleepPattern` — derived bedtime/wake statistics |
| `AstraWidget.swift` | `AstraWidget`, `WidgetLayout`, `WidgetBlock` |
| `BarcodeProduct.swift` | Barcode-scan result shape |
| `FoodVisionModels.swift` | `FoodRecognitionResult`, `FoodVisionError`, frozen contract for vision API |
| `ThemeHelper.swift` | `ThemeHelper.color(from:)` hex → `Color` helper |

### Services (`Services/`)

Singletons (`static let shared`) that own I/O, persistence, or long-lived computation. All `@MainActor` or explicit `actor` isolation.

| File | Responsibility |
|---|---|
| `VertexConfig.swift` | Credential loading: UserDefaults pasted JSON > bundled `vertex-service-account.json` |
| `VertexAuth.swift` | JWT mint + OAuth token cache (NSLock-guarded) |
| `VertexGeminiClient.swift` | Streaming `AsyncThrowingStream<ChatChunk>` + tools manifest + 120 s watchdog |
| `PredictionEngine.swift` | Pure-math on-device prediction. No HealthKit import. |
| `PredictionAIService.swift` | AI enrichment layer: daily insight, action chips, anomaly text via Gemini |
| `TrainingLoadEngine.swift` | ACWR, daily/weekly kcal load, personal records from `HKWorkout` array |
| `StreakEngine.swift` | Weekly activity streaks, milestone badges, local notifications |
| `ChallengeEngine.swift` | Active challenge generation + progress tracking |
| `AstraWidgetStore.swift` | Astra-authored Home widgets (UserDefaults JSON, cap = 6) |
| `ChatHistoryStore.swift` | Live slot + archived session store (UserDefaults JSON, cap = 30) |
| `EventKitManager.swift` | Calendar + Reminders CRUD; writes only to "Fitness Guru" list/calendar |
| `NotificationManager.swift` | UNUserNotificationCenter wrapper: permissions, sedentary alerts, HRV nudges |
| `NutritionService.swift` | Extended macro totals (carbs, fat, fiber, sugar, sodium, caffeine) |
| `FoodVisionService.swift` | Non-streaming Gemini Vision call; returns `FoodRecognitionResult` |
| `BarcodeProductService.swift` | Open Food Facts lookup by barcode |
| `SleepSessionManager.swift` | In-app sleep tracker: CoreMotion 1 Hz accel, 30 s windows, onset detection |
| `SleepPatternAnalyzer.swift` | Derives `SleepPattern` (median bedtime/wake) from `SleepSession` history |
| `SleepFocusDetector.swift` | `INFocusStatusCenter` + time-of-day bedtime window → `sleepFocusLikely` |
| `SnoreDetector.swift` | AVAudioEngine microphone tap; counts snore episodes during sleep |
| `BreathingSessionManager.swift` | Guided breathing phases + HRV-triggered nudge scheduling |
| `HeartRateZoneCalculator.swift` | HR zones from age/max-HR formula; no HealthKit dependency |
| `TokenMeter.swift` | Cumulative Gemini token + cost tracking by `TokenSource` |

### ViewModels (`ViewModels/`)

Only two files; most views observe singletons directly via `@ObservedObject`.

| File | Role |
|---|---|
| `ChatViewModel.swift` | `@MainActor` class driving Astra chat: streaming, tool confirmation, flush throttle (50 ms), live-session persistence |
| `ChatPrefillBus.swift` | Singleton cross-screen channel for prompt queuing (`pendingPrompt`) and composer pre-fill (`composerSeed`) |

### Views — Full-screen (`Views/`)

Each tab or modal owns one file:

`DashboardView` · `ChatView` · `RemindersView` · `ProgressHubView` · `SettingsView`
`WorkoutTrackerView` · `SleepModeView` · `CalendarView` · `DetailedMetricView`
`HealthTrendsView` · `NutritionDashboardView` · `WorkoutAnalyticsView`
`HeartRateZonesView` · `GuidedBreathingView` · `SleepReportView` · `StreakView`
`DailyChallengeView` · `TokenUsageView` · `LoginView`

Food scan has its own sub-folder: `FoodScan/{FoodScanView, FoodCameraView, FoodAnalyzingView, FoodReviewSheet}`.
Onboarding lives in `Onboarding/{OnboardingView, OnboardingScreens}`.

### Views — Components (`Views/Components/`)

Reusable cards and overlays consumed by multiple full-screen views:

`GlassCard` · `GlassLoaderOverlay` · `MetricCards` · `MetricChart` · `PredictionsCard`
`PredictionWhySheet` · `SleepTrackingCard` · `StreakCard` · `DailyChallengeCard`
`WidgetsCard` · `ToolCards` · `GoalsEditorSheet` · `ProfileSheets`
`StructuredMarkdownText` · `AnimatedButton` · `AppLoadingScreen` · `CameraImagePicker`

---

## 2. Five-Tab Structure and ContentView Wiring

`ContentView` (`ContentView.swift`) is the root view rendered by the `WindowGroup`. It owns:

- The iOS 26 native `TabView` (no custom tab-bar implementation; the system auto-applies Liquid Glass).
- A single `activeModal: String?` state variable that drives three full-screen modals layered above the tab bar at `zIndex(50)`.
- Two `@ObservedObject` references: `HealthKitManager.shared` and `ChatPrefillBus.shared`.
- The 15-second silent poll timer (`healthSyncTimer`).

### Tab declarations

```swift
Tab("Home",      systemImage: "house.fill",            value: "home")      → DashboardView
Tab("Coach",     systemImage: "brain.head.profile",    value: "chat")      → ChatView
Tab("Reminders", systemImage: "bell.fill",             value: "reminders") → RemindersView
Tab("Progress",  systemImage: "chart.bar.fill",        value: "progress")  → ProgressHubView
Tab("Profile",   systemImage: "person.fill",           value: "profile")   → SettingsView
```

Each tab is wrapped in a `NavigationStack`. Navigation within a tab is pushed by sub-views via `.navigationDestination` or imperative presentation via `@State`.

### Modal overlay pattern

Three modals are expressed as `if/else if` blocks above `ZIndex(50)` that slide in from the bottom:

| `activeModal` value | View presented |
|---|---|
| `"workout"` | `WorkoutTrackerView(onBack:)` |
| `"sleep"` | `SleepModeView(onClose:)` |
| `"calendar"` | `CalendarView(onBack:onOpenWorkout:onOpenChat:)` |

`DashboardView` receives three closures (`onOpenWorkout`, `onOpenCalendar`, `onOpenSleepMode`) and a `switchToTab` closure. These are the only external entry points — `DashboardView` never mutates tab or modal state directly.

The `CalendarView`'s `onOpenChat` closure shows a cross-layer flow: it (1) closes the calendar modal, (2) calls `ChatPrefillBus.shared.queueComposerSeed(...)` with a canned prompt, and (3) switches the tab to `"chat"`.

### ChatPrefillBus wiring

`ContentView` observes two `@Published` properties on `ChatPrefillBus.shared`:

- `pendingPrompt` — set by Predictions card action chips. On change: switch to `"chat"` tab. `ChatView.onAppear` consumes it via `consume()` and auto-sends to `ChatViewModel`.
- `composerSeed` — set by the Why-sheet "Continue in Coach" button. On change: switch to `"chat"` tab. `ChatView.onAppear` consumes it via `consumeComposerSeed()` and pre-fills the input without auto-sending.

The bus is a `@MainActor` singleton because `ChatView` owns its `ChatViewModel` via `@StateObject` — callers outside the Coach tab cannot reach the view model directly.

### Loading screen

`AppLoadingScreen` is overlaid at `zIndex(200)` and removed after a minimum brand-hold of 1.7 seconds plus the time for the initial `fetchTodayData()` + EventKit fetch to settle. The `didFinishInitialLoad` flag gates the sync timer and foreground-refresh handler so they never fire during the loading state.

### App lifecycle

`FitnessApp.swift` (`@main`) manages two lifecycle concerns:

1. **`migrateHomeCardsList()`** — idempotent on-launch migration that splices missing card IDs (`predictions`, `distance`, `meals`, `widgets`, `tracksleep`) into the `home_cards_list` UserDefaults string. Each migration block keys off the *absence* of its target ID, so re-running is always safe.
2. **`SleepFocusDetector`** — started when the scene becomes `.active`, stopped when it moves to `.background`. This prevents the 60-second poll loop from running when the app is not on-screen.

---

## 3. HealthKitManager — Central Data Hub

`HealthKitManager` (`HealthKitManager.swift`, ~2 121 lines) is the single source of truth for all HealthKit data. It is `@MainActor`, `ObservableObject`, and accessed everywhere as `HealthKitManager.shared`.

### Published properties

| Property | Type | Purpose |
|---|---|---|
| `metricSummaries` | `[HealthMetricType: MetricSummary]` | Primary data dictionary for all 23 metric types |
| `predictions` | `Predictions?` | Latest on-device prediction snapshot |
| `recentWorkouts28` | `[HKWorkout]` | 28-day workout cache for prediction engine and training load |
| `hourlyStepsToday` | `[Double]` | 24-element hourly step buckets for sedentary detection |
| `dietaryCaloriesToday` | `Double` | Running kcal sum from HK |
| `dietaryProteinToday` | `Double` | Running protein sum (g) |
| `dietaryCalories7Day` | `[Double]` | 7-day daily kcal history |
| `todayFoodLog` | `[FoodLogEntry]` | Grouped food log entries, oldest-to-newest |
| `recentSymptoms14` | `[SymptomEntry]` | 14-day symptom samples |
| `menstrualFlowDays60` | `[Date]` | 60-day flow day list |
| `hasWatchClassData` | `Bool` | Whether HR samples exist in last 7 days; persisted to UserDefaults |

### Single-publish render pipeline (Session 29 performance work)

Before Session 29, each of the ~45–50 HK queries called `self.metricSummaries[type] = ...` individually inside a callback, causing ~45 SwiftUI publishes per 15-second tick. The current implementation collapses this into at most one:

**Step 1 — Local copy.** At the start of `fetchTodayData()`, a mutable local dictionary is seeded from the current `self.metricSummaries`, preserving user-set goals and any keys not touched in this cycle.

**Step 2 — `MetricFetchResult` facet type.** Each child task returns an optional `MetricFetchResult: Sendable`:

```swift
private struct MetricFetchResult: Sendable {
    let type: HealthMetricType
    let value: Double?      // nil = history-only fetch
    let history: [MetricValue]?  // nil = value-only fetch
}
```

Value-only queries (today's step sum) and history-only queries (365-day step history) for the same metric type are independent tasks; the drain loop merges both facets into the one `MetricSummary` for that type.

**Step 3 — `withTaskGroup` parallel execution.** All ~45 query tasks are added to a single `withTaskGroup(of: MetricFetchResult?.self)`. "Side-channel" tasks that update their own `@Published` properties (workouts, hourly steps, dietary, symptoms, menstrual) return `nil` and write themselves exactly once on the `MainActor` inside the task body.

**Step 4 — Single drain loop.** After `await withTaskGroup` completes (all tasks have returned), the drain loop accumulates every non-nil result into `newSummaries`:

```swift
for await result in group {
    guard let result, var summary = newSummaries[result.type] else { continue }
    if let value = result.value { summary.currentValue = value }
    if let history = result.history { summary.history = history }
    newSummaries[result.type] = summary
}
```

**Step 5 — Equality gate.** The dictionary is written back to `self.metricSummaries` only if it differs from the current value. `MetricSummary` and `MetricValue` are both `Equatable`. An unchanged 15-second poll emits zero publishes:

```swift
if newSummaries != self.metricSummaries {
    self.metricSummaries = newSummaries
}
```

**Step 6 — Post-fetch work.** After the single dict write, `recomputePredictions()` and `kickoffAIEnrichmentIfNeeded()` are called. HRV nudge scheduling and `ChallengeEngine.shared.refreshProgress()` follow.

### Storage and unit conventions

All numeric values stored in `MetricSummary.currentValue` and `history` use **imperial units** (miles, mi/hr, inches) or SI units as specified by the HK API (grams, liters, milliseconds). The `LocaleUnits` enum in `HealthMetric.swift` provides display-only conversion helpers. UK/metric users see km, km/h, and cm on-screen; the stored value is always the imperial/SI original.

### Write paths

The manager owns all HK write paths:

- `logMetricValue(type:value:start:end:)` — generic write for the 7 always-on types
- `logFood(name:calories:protein:carbs:fat:date:isEstimate:confidence:)` — writes 4 dietary quantity samples with `HKMetadataKeyFoodType`, `HKMetadataKeyWasUserEntered`, and optional `FitnessGuruEstimateConfidence` metadata
- `logBodyMass(kilograms:)` / `logHeight(centimeters:)` — single-sample writes for About You
- `logWorkout(activityType:start:end:calories:distanceMiles:)` — uses `HKWorkoutBuilder` (legacy `HKWorkout(activityType:...)` was deprecated in iOS 17)
- `writeSleepSession(_:)` — writes in-bed + segmented asleep samples from an on-device `SleepSession`

---

## 4. On-Device Engines vs the AI Layer

The app maintains a strict split between deterministic on-device computation and AI-driven enrichment.

### On-device prediction: `PredictionEngine`

`PredictionEngine` (`Services/PredictionEngine.swift`) is a pure-Swift enum with no HealthKit import:

```swift
public enum PredictionEngine {
    public static func computeAll(snapshot s: Snapshot) -> Predictions
}
```

It takes a pre-built `Snapshot` value type assembled by `HealthKitManager.recomputePredictions()` and returns a `Predictions` value. No fetches, no side effects. This makes it independently testable and trivially fast (sub-millisecond on device).

The `Snapshot` struct carries ~35 fields covering every input the engine needs:

- Last-night sleep, HRV, and RHR (most-recent-non-zero)
- 28-day and 30-day history arrays for HRV, RHR, sleep, steps, active energy, hydration, mindful minutes
- 14-day history for steps, active energy, exercise minutes
- Today's running totals
- Acute/chronic load minutes and 28-day per-day kcal-load array
- 28 `WorkoutSample` structs (category, weekday, hour, duration)
- 24 hourly step buckets
- Body composition (height/weight) and 7-day nutrition history
- VO2 max, walking speed/asymmetry
- 14-day symptom entries
- Per-metric 28-day goal histories and current goals

`computeAll` runs a baseline gate (7 days of non-zero step history required) then calls five sub-predictors:

| Predictor | Output type |
|---|---|
| `predictRecoveryReadiness` | `RecoveryReadiness` — 0-100 score, label, HRV/RHR signal flags |
| `predictNextWorkout` | `NextWorkoutForecast` — weekday-hour pattern from 28-day workout history |
| `predictGoalTrajectories` | `[GoalTrajectory]` — projected EOD value vs 14-day baseline per metric |
| `detectSedentaryAlert` | `SedentaryAlert?` — fired when ≥3 consecutive sub-250-step hours detected |
| (additional predictors) | `HealthMeterScore`, anomaly detection, goal suggestions, illness early-warning, periodization, cross-metric correlations |

The `Predictions` struct carries a `contentSignature` (everything except `generatedAt`). `HealthKitManager.recomputePredictions()` diffs by signature before publishing:

```swift
if predictions?.contentSignature != newPredictions.contentSignature {
    predictions = newPredictions
}
```

### AI enrichment: `PredictionAIService`

`PredictionAIService` (`Services/PredictionAIService.swift`) is an `actor` (not `@MainActor`) that wraps Gemini calls dedicated to enriching deterministic outputs with natural-language content. It is purely additive — the deterministic engine remains canonical.

On a cache miss, three sub-calls run in parallel:

```swift
async let insightTask = self.generateDailyInsight(...)
async let actionsTask = self.suggestActions(...)
async let anomalyTask = self.interpretAnomalies(...)
```

Returns an `EnrichmentBundle`:

```swift
public struct EnrichmentBundle: Codable {
    public let insight: DailyInsight?
    public let actions: [ActionSuggestion]
    public let anomalyInterpretations: [UUID: String]
}
```

If all three calls fail, the function throws (transport problem). If any one fails, the others still populate; the card renders without the missing section. In-flight task deduplication prevents duplicate API hits when `enrichPredictions` is called concurrently.

`kickoffAIEnrichmentIfNeeded()` in `HealthKitManager` is fire-and-forget: it reads a cache first and only hits Vertex on a miss, then updates `predictions` a second time when the bundle lands.

### AI Coach: `VertexGeminiClient` + `ChatViewModel`

The Coach (`ChatView`) has its own AI path independent of prediction enrichment:

- `VertexGeminiClient` is a singleton `actor` that manages the streaming `AsyncThrowingStream<ChatChunk, Error>`. The stream is guarded by a 120-second wall-clock watchdog task that cancels the request and surfaces a timeout error.
- `ChatViewModel` is `@MainActor`, owns the message list, and throttles streaming-text flushes to ~20/sec (50 ms `streamFlushInterval`) to avoid O(n²) markdown re-parse per delta.
- The tools manifest (`toolsManifest` in `VertexGeminiClient`) declares 18 Gemini function declarations. Thought-signatures from Gemini's thinking mode round-trip in the `ToolCall` struct so the model can correlate multi-turn tool calls.
- `thinkingConfig` is always placed inside `generationConfig`, never at the top level of the request body.
- All Gemini calls use `gemini-3.5-flash` on the **global** endpoint (`generativelanguage.googleapis.com` routing); regional endpoints return 404 for 3.x models.

### Food Vision: `FoodVisionService`

`FoodVisionService` is a separate `actor` that uses the non-streaming `generateContent` endpoint (not the streaming path). It resizes images to ≤ 1024 px, JPEG q=0.7, and posts with `responseMimeType: application/json` + `responseSchema` for structured output. Reuses `VertexAuth.shared` for credentials.

---

## 5. Singletons and Shared State

All singletons are accessed as `static let shared`. No dependency injection framework is used.

### Data singletons (primary observables)

| Singleton | Isolation | Primary consumers |
|---|---|---|
| `HealthKitManager.shared` | `@MainActor` | `ContentView`, `DashboardView`, `ChatViewModel`, `PredictionEngine` snapshot assembly, all metric cards |
| `EventKitManager.shared` | `@MainActor` | `ContentView`, `DashboardView`, `RemindersView`, `CalendarView`, `ChatViewModel` tool execution |
| `AstraWidgetStore.shared` | `@MainActor` | `DashboardView` (WidgetsCard), `ChatViewModel` widget tool handlers |
| `ChatHistoryStore.shared` | `@MainActor` | `ChatViewModel`, history sheet |
| `NutritionService.shared` | `@MainActor` | `NutritionDashboardView`, `ChatViewModel` system prompt |

### Engine singletons (compute, no primary published UI state)

| Singleton | Isolation | Trigger |
|---|---|---|
| `TrainingLoadEngine.shared` | `@MainActor` (class) | Called from inside `fetchTodayData()` workout task: `TrainingLoadEngine.shared.compute(from: workouts)` |
| `StreakEngine.shared` | `@MainActor` | `DashboardView.refreshAllData()`, `ProgressHubView` |
| `ChallengeEngine.shared` | `@MainActor` | End of `HealthKitManager.fetchTodayData()` + `DashboardView.refreshAllData()` |
| `BreathingSessionManager.shared` | `@MainActor` | HRV nudge scheduling at end of `fetchTodayData()` |
| `SleepSessionManager.shared` | `@MainActor` | `SleepModeView` start/stop |
| `SleepFocusDetector.shared` | `@MainActor` | `FitnessApp` scene-phase changes |
| `SleepPatternAnalyzer` | static methods | `SleepFocusDetector`, `SleepModeView` |

### Service singletons (I/O, no UI state)

| Singleton | Isolation |
|---|---|
| `VertexGeminiClient.shared` | `actor` |
| `PredictionAIService.shared` | `actor` |
| `FoodVisionService.shared` | `actor` |
| `VertexAuth.shared` | `class` (NSLock internal) |
| `NotificationManager.shared` | `@MainActor` |
| `TokenMeter.shared` | `@MainActor` |
| `BarcodeProductService.shared` | `actor` (or class) |

### Cross-screen bus

| Singleton | Role |
|---|---|
| `ChatPrefillBus.shared` | `@MainActor` `ObservableObject` with `pendingPrompt: String?` and `composerSeed: String?`. Both `ContentView` and `ChatView` observe it. Callers queue; `ChatView.onAppear` consumes atomically. |

### AppStorage keys (persisted preferences)

Key user-configurable `AppStorage` keys used across multiple views:

| Key | Type | Default | Consumers |
|---|---|---|---|
| `is_onboarded` | Bool | false | `ContentView` |
| `is_logged_in` | Bool | true | `ContentView`, `SettingsView` |
| `theme_mode` | String | `"dark"` | Most views |
| `accent_color` | String | `"#30D158"` | Most views |
| `athlete_name` | String | `"Alex Rivera"` | `DashboardView`, `ProgressHubView`, coach system prompt |
| `home_cards_list` | String | comma-separated card IDs | `DashboardView` |
| `coach_personality` | String | `"Direct"` | `ChatViewModel` system prompt |
| `training_goals` | String | — | `ChatViewModel` system prompt |
| `hk_requested_once` | Bool | false | `ContentView` (one-shot HK auth gate) |
| `thinking_level` | String | `"medium"` | `ChatView`, `VertexGeminiClient` |
| `has_watch_class_data` | Bool | false | `HealthKitManager` (persisted across launches) |

---

## 6. Recompute and Refresh Cadence

### 15-second silent poll

`ContentView` owns a `Timer.publish(every: 15, on: .main, in: .common).autoconnect()`. Each tick calls:

```swift
Task { await healthKitManager.fetchTodayData() }
```

The timer fires only when `isOnboarded && isLoggedIn && didFinishInitialLoad && scenePhase == .active`. It is "silent" in that `fetchTodayData()` no longer toggles any global loading flag, so periodic refreshes never show a spinner on Home or Progress.

### Foreground-return sync

A separate `ContentView.onChange(of: scenePhase)` triggers `fetchTodayData()` the moment the app becomes `.active`. This ensures data is current immediately after the user switches back from another app.

### `refreshAllData` gate (DashboardView)

`DashboardView.refreshAllData()` is the pull-to-refresh handler. It calls `healthKitManager.fetchTodayData()`, then also explicitly refreshes:

- `StreakEngine.shared` (requires HK workout + step history already loaded)
- `ChallengeEngine.shared`
- Local workout dates for the "Workouts This Week" row
- `lastSleepReport` (most recent `SleepSession` from the on-device store)

### `recomputePredictions()`

Called at the end of every `fetchTodayData()`, and also when the user edits a goal (`setGoal(_:for:)`). It:

1. Assembles the `PredictionEngine.Snapshot` from the already-loaded `metricSummaries`, `recentWorkouts28`, `hourlyStepsToday`, dietary fields, and symptom/menstrual data.
2. Calls `PredictionEngine.computeAll(snapshot:)`.
3. Diffs by `contentSignature`; publishes only if something changed.
4. Schedules or cancels the sedentary local notification via `NotificationManager`.

### `refreshIfStale(maxAgeMinutes:)`

`ChatViewModel.buildSystemInstruction()` calls this before building the system prompt for each Gemini request, ensuring the prediction summary in the prompt is not stale. If `predictions?.generatedAt` is older than `maxAgeMinutes * 60`, a full `fetchTodayData()` is triggered.

### AI enrichment scheduling

`kickoffAIEnrichmentIfNeeded()` is fire-and-forget inside `fetchTodayData()`. It checks a cache keyed by the prediction's `contentSignature`; on a miss it calls `PredictionAIService.shared.enrichPredictions(_:userContext:)` and, when the bundle returns, updates `self.predictions` with the enrichment fields. The in-flight deduplication in `PredictionAIService` prevents duplicate Vertex calls when multiple ticks land before the first enrichment resolves.

---

## 7. Cross-Cutting Patterns

### Liquid Glass only — no fake glass

Every card uses `GlassBackgroundModifier`, which applies:

```swift
.glassEffect(glassEffectStyle(), in: .rect(cornerRadius: cornerRadius))
```

The `glassEffectStyle()` method returns `.clear.interactive()` or `.regular.interactive()` (with optional tint) depending on `AppStorage("glass_strength")`. The old pattern of `.background + .overlay(stroke)` is explicitly banned. `GlassEffectContainer` in `DashboardView` coalesces the per-card backdrop/blur passes into one container render (iOS 26 native optimization).

### Honest empty states — no mock data

When a metric has no real data, `MetricSummary.currentValue` is `0.0` and `history` is empty. Cards render "—" for values that are zero. No placeholder or sample numbers are ever shown. The `PredictionEngine` requires at least 7 days of non-zero step history before producing any prediction; below that threshold it returns a `Predictions` value with `insufficientHistoryDays` set, and the `PredictionsCard` renders a "Building baseline" state.

### Frozen-contract parallel development

Service contracts (notably `FoodVisionModels.swift`) are defined as frozen structs/enums agreed upon before implementation. This allows the vision flow's four files (`FoodScanView`, `FoodCameraView`, `FoodAnalyzingView`, `FoodReviewSheet`) to be developed independently of `FoodVisionService` against the same contract, with no cross-dependency until integration.

### `@ViewBuilder` switch size limit

SwiftUI's `@ViewBuilder` `switch` statement cannot have more than ~10 cases before the type-checker times out. The `ToolCards.swift` view breaks the `ToolCall` switch across multiple private helpers (one per logical tool group) to stay within the limit.

### Imperial storage / locale display

Stored and HealthKit values never change unit based on locale. `LocaleUnits` provides display-time conversion:

```swift
// Storage: miles. Display: km for metric locales.
LocaleUnits.distanceDisplay(fromMiles: miles) -> (value: Double, unit: String)
// Inverse: goal-editor slider writes back imperial
LocaleUnits.milesFromDisplay(sliderValue) -> Double
```

Affected types: `.distance` (mi), `.walkingSpeed` (mi/hr), `.walkingStepLength` (in).

### Vertex credential resolution

`VertexConfig.current()` is the single authority for credentials. Pasted JSON in UserDefaults wins over the bundled `vertex-service-account.json`. `VertexAuth` caches the OAuth token and invalidates it on `clientEmail` change. The real `vertex-service-account.json` is gitignored (`*service-account*.json` in `.gitignore`); only a placeholder or the bundled file ships in the repo.

### Token accounting

Every Gemini call (chat, prediction enrichment, food vision) reports token usage to `TokenMeter.shared` under the appropriate `TokenSource` case. Settings → Token Usage surfaces cumulative input/output tokens and estimated USD cost per source.

---

## 8. Data-Flow Diagram

```
Apple HealthKit
     │
     │  HKStatisticsQuery / HKSampleQuery / HKStatisticsCollectionQuery
     │  (parallel withTaskGroup, ~45 tasks)
     ▼
HealthKitManager.fetchTodayData()
     │
     ├─ MetricFetchResult facets ──► newSummaries (local dict)
     │                                     │
     │  Side-channel (own @Published):      │
     ├─ recentWorkouts28 ──────────────────┤
     ├─ hourlyStepsToday ──────────────────┤
     ├─ dietaryCaloriesToday / protein / 7d┤
     ├─ todayFoodLog ──────────────────────┤
     ├─ recentSymptoms14 ──────────────────┤
     └─ menstrualFlowDays60 ───────────────┤
                                           │
                             Single write: │
                      metricSummaries = newSummaries
                      (only if changed — Equatable gate)
                                           │
                                           ▼
                            recomputePredictions()
                                           │
                          PredictionEngine.Snapshot ──► PredictionEngine.computeAll()
                                           │
                                    Predictions value
                                           │
                          contentSignature diff gate
                                           │
                            self.predictions = newPredictions
                                    │               │
                                    │               └──► NotificationManager
                                    │                    (sedentary alert)
                                    ▼
                         kickoffAIEnrichmentIfNeeded()  ─── (fire-and-forget)
                                    │
                         PredictionAIService.enrichPredictions()
                         (3 parallel Gemini calls: insight / actions / anomalies)
                                    │
                         self.predictions updated with EnrichmentBundle
                                    │
            ┌───────────────────────┼─────────────────────────────────┐
            ▼                       ▼                                 ▼
     PredictionsCard          ChatViewModel                    ProgressHubView
     (Home tab)              buildSystemInstruction()          (HealthMeterScore,
     action chips            → refreshIfStale()                TrainingLoad,
     → ChatPrefillBus        → Gemini stream                   Streak, Challenge)
     → ContentView tab       → ToolCall execution
       switch → ChatView     → HealthKitManager write
```

The right side of the diagram covers the Coach tab's independent path: `ChatViewModel` triggers `refreshIfStale()` before building the Gemini system prompt, then streams through `VertexGeminiClient`. Tool-call execution in `ChatViewModel` writes back to `HealthKitManager` (e.g., `logFood`, `logMetricValue`), which in turn calls `fetchTodayData()` to keep the displayed metrics current.
