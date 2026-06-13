# Data Model, Storage, and Privacy

Reference document for engineers maintaining Fitness Guru (build seq 3004, iOS 26).
All claims verified against source in `FitnessApp.swiftpm/FitnessApp/`.

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
10. [GCP Credential Handling](#10-gcp-credential-handling)

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

### What is sent to Vertex AI (Gemini)

Each Astra chat turn and each food-vision request sends an HTTPS POST to:

```
https://aiplatform.googleapis.com/v1/projects/<projectId>/locations/global/publishers/google/models/gemini-3.5-flash:streamGenerateContent
```

The request body includes:

- **System prompt** — a structured text block built in `ChatViewModel.buildSystemInstruction()`. Contains the full athlete profile, today's metric values, 7-day histories, prediction snapshot, today's food log, training goals, coach personality, clinical record strings (when opted in), and the contents of `astra_notes`.
- **Conversation history** — prior `ChatMessage` turns in the session.
- **User message text** — the user's typed input.
- **Image data (optional)** — JPEG-encoded image bytes (base64) for food photo or fitness-gear photo uploads, resized to ≤1200 px (chat uploads) or ≤1024 px (FoodVisionService).

OAuth 2.0 Bearer tokens for authentication are obtained via a JWT assertion signed with the GCP service-account private key. Token exchange goes to `oauth2.googleapis.com`. No token or private key leaves except as part of that exchange.

### What is NOT sent to any server

| Data | Where it stays |
|---|---|
| Microphone audio (snore detection) | On-device only. Classified by Apple's `SNAudioStreamAnalyzer`; only the classification confidence value (a `Double`) is ever used. The PCM buffer is never stored or transmitted. |
| Raw HealthKit samples | Remain in HealthKit; only processed summaries (numbers + dates) enter the system prompt string. |
| Sleep session raw motion samples | Stored in `sleep_sessions_v1` UserDefaults only; never sent anywhere. |
| Chat history | Stored in `astra_chat_history_v1` UserDefaults only. |
| GCP private key | In-memory only during JWT signing; loaded from `vertex-service-account.json` (not in git) or from `vertex_service_account_json` UserDefaults (user-pasted). Never logged. |

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

## 10. GCP Credential Handling

Source: `Services/VertexConfig.swift`, `Services/VertexAuth.swift`.

### Credential Sources (priority order)

1. **User-pasted JSON** — stored as a raw string in UserDefaults key `vertex_service_account_json`. Loaded by `VertexConfig.current()` first.
2. **Bundled file** — `vertex-service-account.json` in the app bundle. Fallback when no pasted JSON is present.

### Git Safety Rules (from CLAUDE.md — enforced by policy, not code)

- `vertex-service-account.json` is covered by `.gitignore` patterns `*service-account*.json`, `*.pem`, `*.p12`. Running `git check-ignore vertex-service-account.json` must report it ignored before any commit.
- A staged-diff scan for `PRIVATE KEY`, `private_key`, `AIza`, or long `MII...` base64 blobs must be clean.
- The real service account in use (GCP project `vertexi-ai-493516`, key `4d33d3bc…`) is flagged for rotation in `agents_log.md`.

### OAuth Token Lifecycle

`VertexAuth.shared.getAccessToken()` issues a RS256-signed JWT (1-hour expiry) to `oauth2.googleapis.com/token` and caches the returned OAuth 2.0 Bearer token in memory. The cache is invalidated on expiry (with a 60-second safety margin) or when the user pastes a new service account key. The private key is held in memory only during the `SecKeyCreateWithData` / `SecKeyCreateSignature` call and is not persisted to Keychain.

### Pasted JSON Flow

Settings → AI Coach → paste JSON → `VertexConfig.setPastedJSON(_:)` writes to `vertex_service_account_json` → `VertexAuth.shared.invalidateCache()` is called → next API call uses the new credential. Clearing the field removes the key and reverts to the bundled fallback.
