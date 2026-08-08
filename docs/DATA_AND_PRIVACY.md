# Data Model, Storage, and Privacy

Reference document for engineers maintaining Fitness Guru (iOS 26).
All claims verified against source in `FitnessApp.swiftpm/FitnessApp/`.

> **2026-07-17 update:** Sections 8 and 10 are rewritten for the Atlas AI
> Gateway migration (commit `06ff4dc`) — the app no longer holds Google/Vertex
> credentials or calls Vertex directly; all AI traffic now goes through the
> gateway. Sections 11–13 are new, written for App Store readiness Work
> Package 2 (privacy manifest + legal documents): `PrivacyInfo.xcprivacy`
> now ships at `FitnessApp.swiftpm/FitnessApp/PrivacyInfo.xcprivacy`, and
> `Services/Legal/LegalTexts.swift` / `docs/PRIVACY_POLICY.md` /
> `docs/TERMS_OF_SERVICE.md` hold the privacy policy and terms text.

---

## Table of Contents

1. [HealthKit Types — Read Authorization](#1-healthkit-types--read-authorization)
2. [HealthKit Types — Write Authorization](#2-healthkit-types--write-authorization)
3. [Clinical Records (Opt-In)](#3-clinical-records-opt-in)
4. [HealthMetricType Enum](#4-healthmetrictype-enum)
5. [LocaleUnits — Storage vs Display](#5-localeunits--storage-vs-display)
6. [EventKit Scoping](#6-eventkit-scoping)
7. [UserDefaults / @AppStorage Key Inventory](#7-userdefaults--appstorage-key-inventory)
8. [What Leaves the Device](#8-what-leaves-the-device)
9. [Permission Purpose Strings (Info.plist)](#9-permission-purpose-strings-infoplist)
10. [GCP Credential Handling (Local Dev Gateway Only)](#10-gcp-credential-handling-local-dev-gateway-only)
11. [Atlas AI Gateway — Privacy Architecture](#11-atlas-ai-gateway--privacy-architecture)
12. [App Store Privacy Labels — Guidance](#12-app-store-privacy-labels--guidance)
13. [Privacy Manifest — Required-Reason APIs](#13-privacy-manifest--required-reason-apis)

---

## 1. HealthKit Types — Read Authorization

Requested on first launch in `HealthKitManager.requestAuthorization()`. All types are requested together; the OS presents a single sheet. Source: `HealthKitManager.swift` lines 122–183.

### Activity & Vitals (HKQuantityType)

| HKQuantityTypeIdentifier | Description |
|---|---|
| `stepCount` | Daily step count |
| `heartRate` | Instantaneous HR (last 1 h used for "live" display) |
| `restingHeartRate` | Average resting HR |
| `walkingHeartRateAverage` | Average HR during walks |
| `heartRateVariabilitySDNN` | HRV (SDNN, ms) |
| `oxygenSaturation` | SpO₂ (%) |
| `respiratoryRate` | Breaths/min |
| `bodyTemperature` | Core body temp |
| `basalBodyTemperature` | BBT (menstrual tracking) |
| `activeEnergyBurned` | Active calories burned |
| `basalEnergyBurned` | Resting/basal calories |
| `distanceWalkingRunning` | Walk + run distance |
| `distanceCycling` | Cycling distance |
| `distanceSwimming` | Swimming distance |
| `flightsClimbed` | Floors climbed |
| `pushCount` | Wheelchair push count |
| `swimmingStrokeCount` | Swimming strokes |
| `appleExerciseTime` | Exercise ring minutes |
| `appleStandTime` | Stand ring hours |
| `appleMoveTime` | Move ring |
| `vo2Max` | VO₂ max (ml/kg·min) |
| `runningSpeed` | Running speed |
| `runningPower` | Running power (watts) |
| `runningStrideLength` | Running stride length |
| `walkingSpeed` | Average walking speed (mi/hr stored) |
| `walkingStepLength` | Step length (inches stored) |
| `walkingAsymmetryPercentage` | Left/right step asymmetry (%) |
| `walkingDoubleSupportPercentage` | Double-support time (%) |
| `sixMinuteWalkTestDistance` | 6-min walk test (m) |
| `stairAscentSpeed` | Stair climb speed |
| `stairDescentSpeed` | Stair descent speed |
| `environmentalAudioExposure` | Ambient sound level (dBASPL) |
| `headphoneAudioExposure` | Headphone output level (dBASPL) |

### Body Measurements (HKQuantityType)

| HKQuantityTypeIdentifier | Storage unit |
|---|---|
| `bodyMass` | kg |
| `bodyMassIndex` | BMI (no unit) |
| `bodyFatPercentage` | % |
| `leanBodyMass` | kg |
| `height` | cm |
| `waistCircumference` | m |

### Nutrition (HKQuantityType)

| HKQuantityTypeIdentifier | HK native unit |
|---|---|
| `dietaryEnergyConsumed` | kcal |
| `dietaryProtein` | g |
| `dietaryCarbohydrates` | g |
| `dietaryFatTotal` | g |
| `dietarySugar` | g |
| `dietaryFiber` | g |
| `dietaryCaffeine` | g (converted → mg for display) |
| `dietaryWater` | L |
| `dietaryCholesterol` | g |
| `dietarySodium` | g (converted → mg for display) |
| `dietaryPotassium` | g |
| `dietaryCalcium` | g |
| `dietaryIron` | g |
| `dietaryVitaminC` | g |
| `dietaryVitaminD` | g |

### Blood / Clinical Vitals (HKQuantityType)

| HKQuantityTypeIdentifier |
|---|
| `bloodGlucose` |
| `bloodAlcoholContent` |
| `bloodPressureSystolic` |
| `bloodPressureDiastolic` |
| `peripheralPerfusionIndex` |
| `forcedExpiratoryVolume1` |
| `peakExpiratoryFlowRate` |

### Category Samples (HKCategoryType)

| HKCategoryTypeIdentifier | Used for |
|---|---|
| `sleepAnalysis` | Sleep card, SleepSessionManager write-back |
| `mindfulSession` | Mindful minutes tile |
| `menstrualFlow` | Cycle-phase context for predictions (60-day window) |
| `ovulationTestResult` | Menstrual context |
| `sexualActivity` | Menstrual context |
| `intermenstrualBleeding` | Menstrual context |
| `lowHeartRateEvent` | HR anomaly context |
| `highHeartRateEvent` | HR anomaly context |
| `irregularHeartRhythmEvent` | HR anomaly context |
| `audioExposureEvent` | Noise exposure events |
| `toothbrushingEvent` | Hygiene |
| `handwashingEvent` | Hygiene |
| `appleStandHour` | Stand ring detail |
| `appleWalkingSteadinessEvent` | Fall-risk context |
| `environmentalAudioExposureEvent` | Noise events |
| `headphoneAudioExposureEvent` | Headphone noise events |
| `abdominalCramps`, `bloating`, `constipation`, `diarrhea`, `heartburn`, `nausea`, `vomiting` | Symptom tracking (14-day window fed to PredictionEngine) |
| `acne`, `dizziness`, `fatigue`, `fever`, `headache`, `hotFlashes`, `moodChanges`, `sleepChanges` | Symptom tracking |

### Workouts & Series

- `HKObjectType.workoutType()` — all workouts
- `HKSeriesType.workoutRoute()` — GPS route series (iOS 16+)
- `HKSeriesType.heartbeat()` — heartbeat interval series (iOS 16+)

### Characteristic Types (Medical ID)

These are read-once from the Health Profile (not queried repeatedly):

| HKCharacteristicTypeIdentifier | Used in system prompt |
|---|---|
| `biologicalSex` | Astra sex label |
| `bloodType` | Astra blood-type label |
| `dateOfBirth` | Age calculation |
| `fitzpatrickSkinType` | Read but not currently surfaced |
| `wheelchairUse` | Walk/run metric context |
| `activityMoveMode` | Activity ring interpretation |

---

## 2. HealthKit Types — Write Authorization

Requested in the same `requestAuthorization()` call. Source: `HealthKitManager.swift` lines 191–208.

| Type | Written by |
|---|---|
| `stepCount` | Manual log (`logMetricValue`) |
| `heartRate` | Manual log |
| `activeEnergyBurned` | Manual log; `logWorkout` builder |
| `distanceWalkingRunning` | Manual log; `logWorkout` builder (miles) |
| `dietaryWater` | Manual log (`logMetricValue` for hydration) |
| `bodyMass` | `logBodyMass(kilograms:)` — called from EditProfileSheet |
| `bodyFatPercentage` | Manual log |
| `height` | `logHeight(centimeters:)` — called from EditProfileSheet |
| `dietaryEnergyConsumed` | `logFood(...)` — AI vision + manual log |
| `dietaryProtein` | `logFood(...)` |
| `dietaryCarbohydrates` | `logFood(...)` |
| `dietaryFatTotal` | `logFood(...)` |
| `mindfulSession` (category) | Guided Breathing session completion |
| `sleepAnalysis` (category) | `writeSleepSession(_:)` after user confirms a tracked night |
| `HKWorkoutType` | `logWorkout(...)` via `HKWorkoutBuilder` |

### Food Logging Metadata

Every `logFood` write tags each HK sample with:

```swift
HKMetadataKeyFoodType: name           // food name string
HKMetadataKeyWasUserEntered: !isEstimate  // false for AI vision
"FitnessGuruEstimateConfidence": confidence  // "low" | "medium" | "high" (AI logs only)
```

This lets other apps (and the app's own `fetchTodayFoodLog`) distinguish exact label entries from AI estimates.

---

## 3. Clinical Records (Opt-In)

Clinical records are **not** requested at startup. They are requested only when the user explicitly enables "Health Records" in Settings, via `requestClinicalRecordsAuthorization()`. Source: `HealthKitManager.swift` lines 224–248.

Types requested when opted in (read-only, no write):

| HKClinicalTypeIdentifier |
|---|
| `allergyRecord` |
| `conditionRecord` |
| `immunizationRecord` |
| `labResultRecord` |
| `medicationRecord` |
| `procedureRecord` |
| `vitalSignRecord` |

After granting, the flag `clinical_records_requested` is written to UserDefaults. The `readClinicalRecords()` method supplies allergies, conditions, and medications into the Astra system prompt as plain-text strings. When no records are present, the system prompt uses `"None known"` — this is explicitly called out as "we don't have a record", not "user has none".

---

## 4. HealthMetricType Enum

All 21 cases. Source: `Models/HealthMetric.swift`.

### Always-On Tiles

| Case | `rawValue` | HK mapping | Storage unit | Display unit | `defaultGoal` | `isUserConfigurableGoal` |
|---|---|---|---|---|---|---|
| `steps` | `"steps"` | `stepCount` | count | count | 10 000 | true |
| `heartRate` | `"heartRate"` | `heartRate` (last 1 h most-recent) | count/min | bpm | 120 | false |
| `activeEnergy` | `"activeEnergy"` | `activeEnergyBurned` | kcal | kcal | 600 | true |
| `sleep` | `"sleep"` | `sleepAnalysis` (most-recent non-zero night, 30-day back-scan) | hours | hrs | 8 | true |
| `distance` | `"distance"` | `distanceWalkingRunning` | miles | mi or km (LocaleUnits) | 5.0 | true |
| `hrv` | `"hrv"` | `heartRateVariabilitySDNN` (last 24 h most-recent) | ms | ms | 100 | false |
| `hydration` | `"hydration"` | `dietaryWater` | liters | L | 3.0 | true |

### Show-More Tiles (revealed by toggle on Home)

| Case | `rawValue` | HK mapping | Storage unit | Display unit | `defaultGoal` | `isUserConfigurableGoal` |
|---|---|---|---|---|---|---|
| `restingHeartRate` | `"restingHeartRate"` | `restingHeartRate` (30-day avg) | count/min | bpm | 60 | false |
| `bodyMass` | `"bodyMass"` | `bodyMass` (most-recent 30 days) | kg | kg | 70 | false |
| `flightsClimbed` | `"flightsClimbed"` | `flightsClimbed` (today sum) | count | flights | 10 | true |
| `exerciseMinutes` | `"exerciseMinutes"` | `appleExerciseTime` (today sum; 90-day history for predictions) | min | min | 30 | true |
| `standHours` | `"standHours"` | `appleStandTime` (today sum) | hours | hrs | 12 | true |
| `mindfulMinutes` | `"mindfulMinutes"` | `mindfulSession` (today category sum) | min | min | 10 | true |
| `oxygenSaturation` | `"oxygenSaturation"` | `oxygenSaturation` (30-day avg × 100) | % | % | 100 | false |
| `vo2Max` | `"vo2Max"` | `vo2Max` (most-recent 30 days) | ml/kg·min | ml/kg·min | 40 | false |

### Additional iPhone-Trackable Show-More Tiles

| Case | `rawValue` | HK mapping | Storage unit | Display unit | `defaultGoal` | `isUserConfigurableGoal` |
|---|---|---|---|---|---|---|
| `restingEnergy` | `"restingEnergy"` | `basalEnergyBurned` (today sum) | kcal | kcal | 1600 | false |
| `walkingSpeed` | `"walkingSpeed"` | `walkingSpeed` (30-day avg) | **mi/hr** | mi/hr or km/h (LocaleUnits) | 3.0 | false |
| `walkingStepLength` | `"walkingStepLength"` | `walkingStepLength` (30-day avg) | **inches** | in or cm (LocaleUnits) | 28 | false |
| `walkingDoubleSupport` | `"walkingDoubleSupport"` | `walkingDoubleSupportPercentage` (30-day avg × 100) | % | % | 24 | false |
| `walkingAsymmetry` | `"walkingAsymmetry"` | `walkingAsymmetryPercentage` (30-day avg × 100) | % | % | 0 | false |
| `headphoneAudio` | `"headphoneAudio"` | `headphoneAudioExposure` (30-day avg) | dBASPL | dB | 75 | false |

### Goals Editor Ranges

Only `isUserConfigurableGoal == true` metrics appear in the Goals Editor sheet. Ranges:

| Metric | Min | Max | Step |
|---|---|---|---|
| steps | 3 000 | 20 000 | 500 |
| activeEnergy | 200 | 1 200 | 50 |
| sleep | 5.0 h | 10.0 h | 0.5 |
| distance | 1.0 | 15.0 | 0.5 (mi stored) |
| hydration | 1.0 L | 5.0 L | 0.25 |
| exerciseMinutes | 15 | 120 | 5 |
| standHours | 6 | 16 | 1 |
| mindfulMinutes | 5 | 60 | 5 |
| flightsClimbed | 3 | 40 | 1 |

---

## 5. LocaleUnits — Storage vs Display

Source: `Models/HealthMetric.swift` (top of file), `enum LocaleUnits`.

**Rule:** All values in HealthKit, all goal overrides in UserDefaults, all internal math — **imperial**. Display converts on read.

| Metric | Stored as | Metric-region display | `LocaleUnits` helper |
|---|---|---|---|
| Distance | miles | km (× 1.60934) | `distanceDisplay(fromMiles:)` |
| Walking speed | mi/hr | km/h (× 1.60934) | `speedDisplay(fromMph:)` |
| Step length | inches | cm (× 2.54) | `stepLengthDisplay(fromInches:)` |

`LocaleUnits.usesMetric` returns `true` when `Locale.current.measurementSystem == .metric`.

The Goals Editor uses `milesFromDisplay(_:)` to convert slider values back to stored miles before writing to UserDefaults.

---

## 6. EventKit Scoping

Source: `Services/EventKitManager.swift`.

### App-Owned Containers

All reads and writes are scoped to a single **"Fitness Guru"** calendar (events) and a single **"Fitness Guru"** reminder list. The user's personal calendars and reminder lists are never touched.

| Container | UserDefaults key | Lazy creation |
|---|---|---|
| Events calendar | `app_event_calendar_id` | First call to `ensureAppEventCalendar()` |
| Reminders list | `app_reminder_list_id` | First call to `ensureAppReminderList()` |

Source preference for both: iCloud (calDAV) → local. The identifier is persisted after creation so the same calendar is reused across launches. If the user deletes the calendar externally, a new one is created on the next write.

### Ownership Enforcement

Every LLM-facing mutation (`updateAppEvent`, `deleteAppEvent`, `updateAppReminder`, `deleteAppReminder`) checks that the target item's calendar identifier matches the stored app-calendar identifier before performing the write. Items on any other calendar are refused silently (returns `false`).

```swift
guard ev.calendar.calendarIdentifier == appCal.calendarIdentifier else { return false }
```

The read path (`listAppEvents`, `listAppReminders`) passes only the app calendar as the predicate, so responses to Astra never expose personal events.

### Authorization

- Calendar: `EKEventStore.requestFullAccessToEvents()` (iOS 17+) or `requestAccess(to: .event)` (earlier).
- Reminders: `EKEventStore.requestFullAccessToReminders()` (iOS 17+) or `requestAccess(to: .reminder)`.
- Each is requested once; subsequent launches check `EKEventStore.authorizationStatus` and skip the sheet if a decision is already recorded.

---

## 7. UserDefaults / @AppStorage Key Inventory

All keys use the standard app container (no app groups, no suite name). Sources verified across all 79 Swift files.

### User Identity & Onboarding

| Key | Type | Default | Meaning |
|---|---|---|---|
| `is_onboarded` | Bool | `false` | Whether the onboarding flow has completed |
| `is_logged_in` | Bool | `true` | Simple in-app "logged in" state (no auth server) |
| `account_created_date` | Double | `0` | `timeIntervalSince1970` of first launch after onboarding |
| `hk_requested_once` | Bool | `false` | Whether HealthKit permission has been requested this install |

### Account & Gateway Profile Sync (WP-L)

Written/read by `GatewayProfileSync` and both sign-in flows (Sign in with
Apple and email/password). The non-internal values here are the only identity
fields synced off-device — to the Atlas AI Gateway's `/v1/me` account record
(see §12 for the label mapping).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `account_email` | String | `""` | Email address for the signed-in account: submitted directly for email/password accounts, or from Sign in with Apple (only populated when Apple discloses it — first authorization only), or backfilled from the gateway's `GET /v1/me`. Shown in Settings; `""` renders as "—". |
| `marketing_opt_in` | Bool | `false` | User's opt-in to marketing/product-update emails. Explicit opt-in (defaults off); synced to the gateway as `marketingOptIn` only once the user has touched the toggle. |
| `marketing_opt_in_touched` | Bool | `false` | Whether the user has changed the marketing toggle on this install. Gates whether local consent is sent to the gateway vs. hydrated from the server — prevents a reinstall's default-`false` from clobbering a server-side opt-in. |
| `profile_sync_pending` | Bool | `false` | Internal retry flag (not user-facing). Set when a `POST /v1/me/profile` sync fails (e.g. offline, endpoint not yet deployed); a pending sync is retried on the next sign-in or app-foreground. |

### Athlete Profile

| Key | Type | Default | Meaning |
|---|---|---|---|
| `athlete_name` | String | `"Alex Rivera"` | User's display name (used in system prompt and notifications) |
| `athlete_dob` | Double | `0` | Date of birth as `timeIntervalSince1970`; 0 = unset |
| `athlete_sex` | String | `""` | `"Male"` / `"Female"` / `"Other"` / `""` (falls back to HK characteristic) |
| `athlete_height_cm` | Double | `0` | Height in centimetres; 0 = unset |
| `athlete_weight_kg` | Double | `0` | Weight in kilograms; 0 = unset |

### Metric Goals

| Key | Type | Default | Meaning |
|---|---|---|---|
| `goal_<rawValue>` | Double | `type.defaultGoal` | Per-metric goal override for each `HealthMetricType.rawValue` (e.g. `goal_steps`, `goal_sleep`). Read by `HealthKitManager.userGoal(for:)`; written by `setGoal(_:for:)`. Absent key means "use defaultGoal". |
| `goal_macro_calories` | Double | `2000` | Daily calorie intake goal (NutritionService) |
| `goal_macro_protein` | Double | `150` | Daily protein goal in grams |
| `goal_macro_carbs` | Double | `225` | Daily carbohydrates goal in grams |
| `goal_macro_fat` | Double | `67` | Daily fat goal in grams |

### AI Coach (Astra)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `astra_notes` | String | `""` | Persistent cross-session memory written by the `update_notes` tool. Injected verbatim into every system prompt. |
| `coach_personality` | String | `"Direct"` | Astra's tone, selected in Settings |
| `training_goals` | String | `""` | Free-text user training goals injected into system prompt |
| `thinking_level` | String | `"medium"` | Gemini thinking budget: `"low"` / `"medium"` / `"high"`. Read by `VertexGeminiClient` to set `thinkingBudget` tokens. |

### Chat History

| Key | Type | Meaning |
|---|---|---|
| `astra_chat_history_v1` | Data (JSON) | Array of `ChatSession` (up to 30 sessions). Each session contains compact `SessionMessage` structs: id, role, text, createdAt, optional JPEG imageData. |
| `chat_live_session_v1` | Data (JSON) | Current on-screen conversation as `[SessionMessage]`. Written after every settled turn; cleared when the user starts a new chat. Survives force-quit. |

### Astra Widgets

| Key | Type | Meaning |
|---|---|---|
| `astra_widgets_v1` | Data (JSON) | Array of up to 6 `AstraWidget` objects pinned to Home. Written by the `create_widget` / `update_widget` / `delete_widget` tools. |

### HealthKit State

| Key | Type | Default | Meaning |
|---|---|---|---|
| `has_watch_class_data` | Bool | `false` | Cached result of whether any HR sample exists in the last 7 days (Watch/chest strap present). Drives Home tile visibility. |
| `clinical_records_requested` | Bool | `false` | Whether the user has explicitly opted in to clinical records access. |

### EventKit Container IDs

| Key | Type | Meaning |
|---|---|---|
| `app_event_calendar_id` | String | `EKCalendar.calendarIdentifier` for the "Fitness Guru" events calendar |
| `app_reminder_list_id` | String | `EKCalendar.calendarIdentifier` for the "Fitness Guru" reminder list |

### Token Meter

| Key | Type | Meaning |
|---|---|---|
| `token_meter_v1` | Data (JSON) | Lifetime Gemini API token accounting (prompt, output, thinking counts by source). Persists across launches. Reset resets this key. |

### Sleep Tracking

| Key | Type | Meaning |
|---|---|---|
| `sleep_sessions_v1` | Data (JSON) | Array of `SleepSession` structs (most recent first, capped at 10). Each contains motion samples and snore episodes. Written by `SleepSessionStore`. |
| `sleep_snore_enabled` | Bool (`true`) | Whether the snore detector (microphone) is active during sleep tracking. |

### Streak & Challenges

| Key | Type | Meaning |
|---|---|---|
| `streak_longest` | Int | All-time longest active-week streak. |
| `streak_badges_v1` | Data (JSON) | Array of earned `StreakBadge` (milestone week counts). |
| `active_challenge_v1` | Data (JSON) | The current active `Challenge` (single object or null). |
| `completed_challenges_v1` | Data (JSON) | Array of `CompletedChallenge` objects. |

### Breathing Sessions

| Key | Type | Meaning |
|---|---|---|
| `breathing_sessions_today` | Data (JSON) | Today's completed breathing sessions (keyed by date string `"YYYY-MM-DD"`). Resets on new day automatically. |
| `custom_breath_in` | Double (`4.0`) | Custom inhale duration (seconds) |
| `custom_breath_hold` | Double (`0.0`) | Custom hold-after-inhale duration |
| `custom_breath_out` | Double (`6.0`) | Custom exhale duration |

### Appearance & Layout

| Key | Type | Default | Meaning |
|---|---|---|---|
| `theme_mode` | String | `"dark"` | `"dark"` / `"light"` / `"system"` |
| `accent_color` | String | `"#30D158"` | Hex string for the app tint color |
| `glass_strength` | String | `"moderate"` | Liquid Glass intensity: `"subtle"` / `"moderate"` / `"strong"` |
| `glass_tint_color` | String | `"#FFFFFF"` | Hex string for glass tint overlay color |
| `glass_tint_strength` | Double | `0.0` | Alpha for the glass tint (0.0 = off) |
| `layout_density` | String | `"regular"` | Home grid density: `"compact"` / `"regular"` |
| `home_cards_list` | String | (comma-separated list) | Ordered list of Home card IDs, comma-separated. Default: `"coach,predictions,widgets,activity,upcoming,steps,heart,tracksleep,sleep,calories,distance,meals,recovery,hydration,workouts,streak,challenge"`. Migrated idempotently on each launch by `FitnessApp.migrateHomeCardsList()`. |

### Credential

| Key | Type | Meaning |
|---|---|---|
| `vertex_service_account_json` | String | Raw JSON text of a GCP service account key, pasted by the user in Settings → AI Coach. Takes priority over the bundled `vertex-service-account.json`. Cleared with `VertexConfig.clearPastedJSON()`. |

### HR Zones

| Key | Type | Default | Meaning |
|---|---|---|---|
| `max_hr_override` | Int | `0` | Manual max-HR override for zone calculation. `0` = use age-based formula (220 − age). |

---

## 8. What Leaves the Device

> **Superseded by the Atlas AI Gateway migration (commit `06ff4dc`).** The app
> no longer calls `aiplatform.googleapis.com` or holds Google credentials.
> This section now describes the current (gateway) request path. See
> §11 for the privacy-relevant architecture summary (stateless pass-through,
> metadata-only metering).

### What is sent to the Atlas AI Gateway

Each Astra chat turn and each food-vision request sends an HTTPS POST to the
gateway's `/v1/chat` endpoint (`GatewayChatClient.swift`,
`GatewayConfig.baseURL` — DEBUG points at the local dev gateway on the Mac's
LAN IP; Release has no URL configured yet, see `HANDOFF-APPSTORE-READINESS.md`
item 3). Every `/v1/*` call is authenticated with `Authorization: Bearer
<gateway access token>` (`GatewayAuth.swift`) — no Google credential of any
kind travels with the request, because the app doesn't hold one.

The request body includes:

- **System prompt** — a structured text block built in `ChatViewModel.buildSystemInstruction()`. Contains the full athlete profile, today's metric values, 7-day histories, prediction snapshot, today's food log, training goals, coach personality, clinical record strings (when opted in), and the contents of `astra_notes`.
- **Conversation history** — prior `ChatMessage` turns in the session.
- **User message text** — the user's typed input.
- **Image data (optional)** — JPEG-encoded image bytes (base64) for food photo or fitness-gear photo uploads, resized to ≤1200 px (chat uploads) or ≤1024 px (FoodVisionService), sent as `{"image":{"mimeType","data"}}` per the gateway's strict part shapes (never `inlineData`).

The model is always requested as the logical name `"chat"` (`GatewayConfig.chatModel`) — the gateway maps that to a concrete Gemini model server-side; the app never names a Gemini model in a request.

### What the gateway does with it

Per the gateway's own architecture (backend `docs/SPEC.md`; confirmed by the
Atlas AI Gateway migration handoff and CLAUDE.md rule 1): the gateway is a
**stateless pass-through**. Health context, chat text, and image bytes are
held in server memory only for the duration of generating that one reply,
then discarded — never written to a database, a log file, or used to train
or fine-tune any model. What the gateway retains afterward is metering
metadata only: the account's user ID, prompt/output/thinking token counts,
timestamp, latency, and request status (used to enforce fair-use limits and
for the in-app Token Meter / `TokenUsageView`). See §11 for detail.

### What is NOT sent to any server

| Data | Where it stays |
|---|---|
| Microphone audio (snore detection) | On-device only. Classified by Apple's `SNAudioStreamAnalyzer`; only the classification confidence value (a `Double`) is ever used. The PCM buffer is never stored or transmitted. |
| Raw HealthKit samples | Remain in HealthKit; only processed summaries (numbers + dates) enter the system prompt string. |
| Sleep session raw motion samples | Stored in `sleep_sessions_v1` UserDefaults only; never sent anywhere. |
| Chat history | Stored in `astra_chat_history_v1` UserDefaults only. |
| Gateway access/refresh tokens | Stored in the iOS Keychain (`KeychainStore.swift`, gateway-prefixed keys), never UserDefaults, never logged. |
| Google/Vertex credentials | None exist on-device anymore. The bundled `vertex-service-account.json` and the `vertex_service_account_json` UserDefaults paste-in path from §10 (pre-migration) are both gone from the shipped app; the key now lives only on the developer's Mac, feeding the local dev gateway (see §10). |

### Barcode Lookups

Scanned barcodes are sent as a GET request to the **Open Food Facts** public API:

```
https://world.openfoodfacts.org/api/v2/product/<barcode>.json
```

The GTIN digits and a `User-Agent: FitnessGuru-iOS/1.0 (personal project)` header are the only information transmitted. No user identity or health data is included. Source: `Services/BarcodeProductService.swift`.

---

## 9. Permission Purpose Strings (Info.plist)

Defined in `project.yml` under `info.properties`. The plist is generated by XcodeGen from this file.

| Permission key | Purpose string |
|---|---|
| `NSHealthShareUsageDescription` | "Fitness Guru reads your full Apple Health profile — body, vitals, nutrition, sleep, workouts, mobility, mindfulness, and Medical ID — so the AI coach can personalize plans." |
| `NSHealthUpdateUsageDescription` | "Fitness Guru writes workouts, hydration, mindfulness sessions, and body measurements you log in the app back to Apple Health." |
| `NSHealthClinicalHealthRecordsShareUsageDescription` | "Fitness Guru can read your clinical records (allergies, conditions, lab results) to give the AI coach a complete picture of your health context." |
| `NSCalendarsFullAccessUsageDescription` | "Fitness Guru reads, updates, and adds events to your calendar to plan workouts around your day." |
| `NSCalendarsUsageDescription` | Same as above (legacy key for pre-iOS 17) |
| `NSRemindersFullAccessUsageDescription` | "Fitness Guru reads, completes, and creates reminders for hydration, workouts, supplements, and recovery." |
| `NSRemindersUsageDescription` | Same as above (legacy key) |
| `NSCameraUsageDescription` | "Fitness Guru opens the camera so you can snap a photo of food or fitness equipment and have the AI coach identify it." |
| `NSPhotoLibraryUsageDescription` | "Fitness Guru reads photos you pick to identify food or fitness gear with the AI coach." |
| `NSUserNotificationsUsageDescription` | "Fitness Guru sends you a nudge when it detects prolonged inactivity, so you can move before sedentary time affects your health score." |
| `NSMicrophoneUsageDescription` | "Fitness Guru listens to the room while you sleep to detect snoring and quantify sleep quality. Audio is analyzed on-device with Apple's Sound Analysis framework and never recorded or uploaded." |
| `NSFocusStatusUsageDescription` | "Fitness Guru reads your Focus state to know when Sleep Focus is on — that lets the app surface sleep tracking at the right moment and align stats to your iOS bedtime schedule." |

Background mode `audio` is declared in `UIBackgroundModes` so the sleep-tracking audio session continues while the screen is off.

---

## 10. GCP Credential Handling (Local Dev Gateway Only)

> **Superseded by the Atlas AI Gateway migration (commit `06ff4dc`).**
> `Services/VertexConfig.swift`, `Services/VertexAuth.swift`, and the
> Settings → AI Coach "paste JSON" UI described in the previous version of
> this section **no longer exist in the app** — confirmed by source grep
> (`grep -rln "VertexConfig\|VertexAuth" FitnessApp.swiftpm/FitnessApp` finds
> nothing) and by CLAUDE.md's rule that no raw Gemini/Vertex call may be made
> from the client. The app holds zero Google credentials, on-device or in
> UserDefaults. Settings → "Astra AI backend" now exposes only the gateway
> base-URL override (`GatewayConfig.baseURLDefaultsKey` = `gateway_base_url`),
> not a credential field.

### Where the GCP key still lives

`vertex-service-account.json` (GCP project `vertexi-ai-493516`, key
`4d33d3bc…`) remains on disk in this repo's working tree — gitignored, never
bundled into the app (`project.yml` excludes it from `sources`) — and now
feeds **only the local dev gateway process** (`~/Multi App Ai Backend`,
started with `GCP_SA_JSON_FILE=".../vertex-service-account.json"` per
CLAUDE.md's local-dev command). The key never travels to the phone or the
simulator; the client only ever talks to the gateway's HTTPS API, which is
the one process that reads the key from disk and holds the resulting OAuth
token in its own memory. In production, the equivalent credential will live
on the deployed gateway host, not in this repository at all.

### Git Safety Rules (from CLAUDE.md — enforced by policy, not code)

- `vertex-service-account.json` is covered by `.gitignore` patterns `*service-account*.json`, `*.pem`, `*.p12`. Running `git check-ignore vertex-service-account.json` must report it ignored before any commit.
- A staged-diff scan for `PRIVATE KEY`, `private_key`, `AIza`, or long `MII...` base64 blobs must be clean.
- The real service account in use (GCP project `vertexi-ai-493516`, key `4d33d3bc…`) is flagged for rotation in `agents_log.md`; rotation was explicitly deferred by the user on 2026-07-08 and must be revisited before any public/App Store release (`HANDOFF-APPSTORE-READINESS.md` item 4).

---

## 11. Atlas AI Gateway — Privacy Architecture

This section is the canonical privacy-relevant description of how the app
talks to its AI backend, written for App Store readiness (Work Package 2).
It underpins both `PrivacyInfo.xcprivacy`'s `NSPrivacyCollectedDataTypes`
declaration and the App Store Connect privacy label answers in §12.

### The three things that matter

1. **Stateless pass-through.** The gateway (`github.com/sangwanboy/atlas-ai-gateway`,
   local dev copy at `~/Multi App Ai Backend`) proxies each `/v1/chat` request
   to Gemini and streams the reply back. Message content — the system prompt
   (athlete profile, HealthKit summaries, clinical record strings, chat
   history, image bytes) — passes through server memory for the lifetime of
   that one request/response cycle and is never written to disk, a log
   stream, a cache, or an analytics/training pipeline. There is no
   conversation datastore on the gateway.
2. **Metadata-only metering.** The only durable record the gateway keeps per
   request is: gateway user ID, prompt/output/thinking token counts,
   timestamp, latency, and status (success/error code). This powers rate
   limiting, the fair-use quota, and the in-app Token Meter
   (`Services/TokenMeter.swift`, `Views/TokenUsageView.swift`). It contains
   no message text, no health values, and no image data.
3. **No credential ever ships on-device.** The app authenticates to the
   gateway with a short-lived bearer token obtained via the user's gateway
   session (Sign in with Apple or email/password, `GatewayAuth.swift`); the
   gateway authenticates to Google with the GCP
   service-account key, which lives only on the gateway host (§10). The app
   binary and its UserDefaults/Keychain contain no Google/Vertex credential
   of any kind.

### Account data the gateway stores (server-side, outside this app's control)

Per the Sign in with Apple exchange (`POST /v1/auth/apple`), the email/password
exchanges (`POST /v1/auth/register`, `POST /v1/auth/login`), and confirmed by
`GatewayAuth.swift`'s wire types (`AuthResponse`: `userId`, `appId`, token
pair), plus `AppleSignInCoordinator.requestSignIn()` requesting
`request.requestedScopes = [.fullName, .email]` (`Views/LoginView.swift`):

| Field | Notes |
|---|---|
| Apple `sub` (stable anonymous identifier) | The primary identity signal for the account. |
| Name and Email, when Apple discloses them | Apple discloses `fullName`/`email` only on the first authorization for a given Apple ID (nil on every later one). When present, `persistAppleSignInResult()` saves them locally and `GatewayProfileSync.swift` POSTs them to `v1/me/profile`, which retains them in the account record — see §12 for the resulting privacy-label declaration. |
| Account/session timestamps | Created-at, last-active. |
| Usage counters | Token counts, request counts, for fair-use metering — same data described in point 2 above. |

No HealthKit data, chat text, or image bytes are part of the account record.

### Why this matters for the privacy manifest and labels

Apple's data-collection definition (used throughout `PrivacyInfo.xcprivacy`
and App Store Connect's privacy questionnaire) is: data is "collected" only
if it is **transmitted off the device and retained** longer than needed to
service the request. Health/chat content is transmitted (point 1) but not
retained (also point 1) — so, by that definition, it is not "collected" and
must not be listed as a collected data type. User ID and usage/metering data
*are* retained (point 2) and so *are* declared as collected. See §12 for the
exact label mapping and the fallback position if App Review disagrees with
this reading.

---

## 12. App Store Privacy Labels — Guidance

Source of truth for what to enter in App Store Connect → App Privacy. Keep
this in sync with `PrivacyInfo.xcprivacy`'s `NSPrivacyCollectedDataTypes` —
the two must not contradict each other.

### Labels to declare

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| User ID | Yes | Yes | No | App Functionality |
| Name | Yes | Yes | No | App Functionality; Marketing (opted-in users only) |
| Email Address | Yes | Yes | No | App Functionality; Marketing (opted-in users only) |
| Other Usage Data (token/request metering) | Yes | Yes | No | App Functionality |
| Health & Fitness | **No** (see reasoning below) | — | — | — |
| Everything else (contacts, location, financial, browsing history, search history, identifiers beyond User ID, diagnostics, etc.) | No | — | — | — |

**Name and Email Address (added in WP-L).** Name is captured only via Sign in
with Apple — on the first authorization for the Apple ID (Apple discloses
`fullName` once, or never if the user declined at that point). Email is
captured two ways: via the same Sign in with Apple disclosure (where it may be
an Apple private-relay address), or submitted directly by the user at signup
for email/password accounts (`POST /v1/auth/register`,
`Views/LoginView.swift`). Both are synced to and retained by the
Atlas AI Gateway's per-user account record (`POST /v1/me/profile`), which is why
they ARE declared as collected (unlike Health data, they are stored server-side —
see §11 reasoning). "Marketing" is listed as a purpose ONLY for users who
explicitly opt in (`marketing_opt_in`, default off, §7); for everyone else the
sole purpose is App Functionality. Deletable via in-app account deletion
(`DELETE /v1/account`). Keep this row consistent with the Sign in with Apple
disclosure in `PRIVACY_POLICY.md` / `privacy.html` / `LegalTexts.swift` and the
labels block in `APP_STORE_METADATA.md`.

**"Data Used to Track You": None.** There is no ad SDK, no analytics/attribution
framework, no data broker sharing, and no cross-app/cross-site linkage
anywhere in this codebase (verified by dependency list in `project.yml`,
which declares only Apple system frameworks — HealthKit, EventKit,
EventKitUI, UserNotifications — no third-party packages at all).

### Why Health & Fitness is NOT declared as "collected"

This is the highest-scrutiny call in the whole privacy label set, given the
app requests `health-records` (clinical data) entitlement. The reasoning,
spelled out for reviewers and for whoever fills in App Store Connect:

- Health/clinical/cycle/symptom data is read from HealthKit on-device and
  assembled into the Astra system prompt (`ChatViewModel.buildSystemInstruction()`).
- It is transmitted off-device exactly once per chat turn, to the Atlas AI
  Gateway, solely to generate that turn's reply (§11, point 1).
- The gateway does not persist it — no database row, no log line, no cache
  entry, no training corpus inclusion. It is present in server memory only
  for the duration of generating the response, which is the definition of
  "not retained."
- Per Apple's own collection definition (App Privacy Details on the App
  Store, "Data Not Collected" guidance: data transmitted but not stored, and
  used only to service that one request, does not count as collected), this
  means Health & Fitness data should NOT appear in the collected-data list.

**Fallback if App Review pushes back:** if a reviewer disagrees with this
reading during review, the safe fallback is to add a **Health & Fitness →
Collected, Linked to user, App Functionality only (not used for tracking)**
label — that is a strictly more conservative declaration and would still be
accurate (it would just be over-declaring, not under-declaring). Do NOT
under-declare to get past review; if in doubt, add the label rather than
omit it. Whoever handles the App Store Connect submission should hold this
fallback in reserve rather than pre-emptively applying it, since the current
architecture genuinely does not retain the data.

### Other App Store Connect surfaces that must match

- **Privacy Policy URL** — must point at the hosted `docs/PRIVACY_POLICY.md`
  content (mirrors `LegalTexts.privacyPolicy`).
- **App description / review notes** — should mention that Health Records
  (clinical data) access is opt-in via Settings, off by default, and that
  health data is processed per-request and never stored server-side; see
  `HANDOFF-APPSTORE-READINESS.md` item 2 for the reviewer-facing framing.

---

## 13. Privacy Manifest — Required-Reason APIs

`PrivacyInfo.xcprivacy` (`FitnessApp.swiftpm/FitnessApp/PrivacyInfo.xcprivacy`)
declares `NSPrivacyAccessedAPITypes` based on an exhaustive source scan run
2026-07-17. Only one required-reason API category is actually used:

| Category | Reason code | Evidence |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (access info from the app's own container, not used to send it off-device or fingerprint) | Pervasive: 61 direct `UserDefaults.standard...` call sites and 177 `@AppStorage` property declarations across the 79-file target — see §7's key inventory for the full list. Representative sites: `ViewModels/ChatViewModel.swift:1370` (`let ud = UserDefaults.standard`), `ContentView.swift:7-13` (`@AppStorage("is_onboarded")`, `@AppStorage("is_logged_in")`, `@AppStorage("theme_mode")`), `HealthKitManager.swift:239` (`UserDefaults.standard.set(true, forKey: "clinical_records_requested")`). |

The following required-reason categories were checked and found **not
applicable** — omitted from the manifest rather than declared speculatively:

| Category | Checked for | Result |
|---|---|---|
| File timestamp APIs (`NSPrivacyAccessedAPICategoryFileTimestamp`) | `creationDate`, `modificationDate`, `contentModificationDate`, `fileModificationDate`, `attributesOfItem`, `resourceValues`, `FileAttributeKey`, raw `stat`/`getattrlist` | No matches anywhere in `FitnessApp.swiftpm/FitnessApp` |
| System boot time (`NSPrivacyAccessedAPICategorySystemBootTime`) | `systemUptime`, `mach_absolute_time`, `CACurrentMediaTime`, `ProcessInfo` uptime usage | No matches |
| Disk space (`NSPrivacyAccessedAPICategoryDiskSpace`) | `volumeAvailableCapacity`, `volumeTotalCapacity`, `systemFreeSize`, `NSFileSystemFreeSize` | No matches |

If any of these are introduced later (e.g. a "storage used" debug screen, or
switching `sleep_sessions_v1` / `astra_chat_history_v1` to file-based storage
with timestamp inspection), the manifest must be updated in the same PR —
this is a common App Store rejection reason (missing or stale required-reason
declarations) and easy to silently drift out of sync with the code.
