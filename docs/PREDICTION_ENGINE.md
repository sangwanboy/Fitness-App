# Prediction Engine — Developer Reference

**File locations**

| Role | Path |
|------|------|
| Engine (pure math) | `Services/PredictionEngine.swift` |
| Output model types | `Models/Prediction.swift` |
| AI enrichment layer | `Services/PredictionAIService.swift` |
| Snapshot builder + caller | `HealthKitManager.swift` — `recomputePredictions()` at line 1691 |

**Build sequence at doc time:** 3004  
**Engine size:** `PredictionEngine` is a `public enum` (namespace only, no instance) of ~1 600 lines. Zero HealthKit imports — all I/O is the caller's responsibility.

---

## Table of Contents

1. [Architecture overview](#1-architecture-overview)
2. [Snapshot construction](#2-snapshot-construction)
3. [Baseline gate](#3-baseline-gate)
4. [Health Meter](#4-health-meter)
5. [Recovery Readiness](#5-recovery-readiness)
6. [Next-Workout Forecast](#6-next-workout-forecast)
7. [Goal Trajectories](#7-goal-trajectories)
8. [Sedentary Alert](#8-sedentary-alert)
9. [Illness Early-Warning](#9-illness-early-warning)
10. [Anomaly Detection](#10-anomaly-detection)
11. [Correlation Engine](#11-correlation-engine)
12. [Periodization](#12-periodization)
13. [Adaptive Goal Suggestions](#13-adaptive-goal-suggestions)
14. [Sleep Forecast](#14-sleep-forecast)
15. [AI Enrichment Layer](#15-ai-enrichment-layer)
16. [ContentSignature and merge pattern](#16-contentsignature-and-merge-pattern)
17. [Data conventions](#17-data-conventions)

---

## 1. Architecture overview

```
HealthKitManager.recomputePredictions()   ← MainActor, sync, ≤5 ms
    │  builds Snapshot from cached metric summaries
    ▼
PredictionEngine.computeAll(snapshot:)    ← pure Swift, no HK imports
    │  returns Predictions (all engine fields populated, aiEnrichmentStatus = .pending)
    ▼
ContentSignature diff check
    │  only reassigns @Published predictions when content actually changed
    ▼
kickoffAIEnrichmentIfNeeded()             ← async Task, fire-and-forget
    │  same-day disk cache check → skip Vertex on hit
    ▼
PredictionAIService.enrichPredictions()  ← three parallel Gemini calls
    │  returns EnrichmentBundle
    ▼
Predictions.merging(...)                  ← keeps all engine fields, splices in AI fields
    │  status = .complete | .cached | .failed
    ▼
@Published predictions on HealthKitManager (MainActor)
```

The deterministic engine is the authoritative source of every number. The AI layer is purely additive — the engine fields are always passed through unchanged by `merging(...)`.

---

## 2. Snapshot construction

`recomputePredictions()` in `HealthKitManager.swift` builds a `PredictionEngine.Snapshot` from already-fetched metric summaries. It does **not** issue new HealthKit queries.

### Key helper: `lastNDays(_:days:)`

Extracts a `[Double]` of daily totals for the last `N` calendar days, oldest→newest. Days with no data are **zero-filled**. This is the universal contract for all 14-, 28-, and 30-day arrays in the Snapshot: a zero means "no valid reading that day," not a real measurement of zero.

### Array fields in the Snapshot

| Field | Length | Zero-fill | Notes |
|-------|--------|-----------|-------|
| `hrvHistory28` | ≤28 (non-zero only) | No | Sparse; zeros dropped before passing |
| `rhrHistory28` | ≤28 (non-zero only) | No | Sparse; zeros dropped |
| `sleepHistory28NonZero` | ≤29 (non-zero only) | No | Today's partial-sleep slot dropped via `.dropLast()` before filtering |
| `hrvHistory30` | 30 | Yes | For illness-warning + correlation |
| `rhrHistory30` | 30 | Yes | For illness-warning + correlation |
| `sleepHistory30` | 30 | Yes | For illness-warning + correlation + sleep forecast |
| `stepsHistory30` | 30 | Yes | For correlation |
| `activeEnergyHistory30` | 30 | Yes | For correlation |
| `hydrationHistory30` | 30 | Yes | For correlation |
| `mindfulMinutesHistory30` | 30 | Yes | For correlation |
| `stepsHistory14` | 14 | Yes | For trajectory + health meter |
| `activeEnergyHistory14` | 14 | Yes | For trajectory + health meter |
| `exerciseMinutesHistory14` | 14 | Yes | For trajectory |
| `dietaryCalories7Day` | 7 | Yes | For nutrition sub-score |
| `hydration7Day` | 7 | Yes | For nutrition sub-score |
| `mindfulMinutes7Day` | 7 | Yes | (present but currently not scored) |
| `dailyKcalLoad28` | 28 | Yes | Workout kcal per day; `duration_minutes × 8` proxy when Apple Health energy is absent |
| `hourlyStepsToday` | 24 | Yes | Index = hour-of-day |
| `goalHistories28` | 28 per metric | Yes | Only `isUserConfigurableGoal` metrics populated |

### Scalar fields

| Field | Source |
|-------|--------|
| `lastNightSleepHours` | Most-recent non-zero sleep reading |
| `lastNightHRV` | Most-recent non-zero HRV reading (nil if never recorded) |
| `lastNightRHR` | Most-recent non-zero RHR reading (nil if never recorded) |
| `hasWatchClassData` | `HealthKitManager.hasWatchClassData` — true when Apple Watch HRV class data is available |
| `acuteLoadMinutes` | Sum of workout durations in the last 7 days (minutes) |
| `chronicLoadMinutes` | Sum of workout durations in the last 28 days (minutes) |
| `stepsHistoryNonZeroDayCount` | Count of calendar days with non-zero step data |
| `heightCm` / `weightKg` | UserDefaults `athlete_height_cm` / `athlete_weight_kg`; falls back to HealthKit body-mass for weight |
| `dietaryCaloriesToday`, `dietaryProteinToday` | Running totals from `NutritionService` |
| `recentSymptoms` | Last 14 days of user-logged `SymptomEntry` records (never trigger predictions, only corroborate) |
| `workouts28` | Pre-mapped `[WorkoutSample]` with `(category, weekday, hour, durationMinutes)` |

### kcal-load proxy

When a workout has no `totalEnergyBurned` from Apple Health, the snapshot builder uses `duration_minutes × 8 kcal/min` as a proxy. This matches `TrainingLoadEngine`'s convention. The Why-sheet for Periodization explicitly tells Gemini about this proxy when it explains load numbers.

### Weight sourcing

`weightKg` prefers `UserDefaults` (set in Profile / About You). If that is zero or missing, it falls back to the most recent HealthKit body-mass reading. Either way, it is stored in kg internally; display converts to lbs via `LocaleUnits`.

---

## 3. Baseline gate

`computeAll(snapshot:)` checks `stepsHistoryNonZeroDayCount` before running any predictor:

```swift
let needed = 7
let have = s.stepsHistoryNonZeroDayCount
if have < needed {
    return Predictions(generatedAt: s.now,
                       aiEnrichmentStatus: .skipped,
                       insufficientHistoryDays: needed - have)
}
```

When the gate fails, the UI renders a "Building baseline · Day N of 7" state and AI enrichment is skipped entirely (`kickoffAIEnrichmentIfNeeded` bails on `insufficientHistoryDays > 0`). No individual predictor has its own baseline gate smaller than 7 days — they may have additional per-predictor gates (see below), but the global gate ensures no engine outputs appear until at least 7 days of step history exist.

---

## 4. Health Meter

**Function:** `computeHealthMeter(snapshot:)` → `HealthMeterScore?`  
**Overall range:** 0–100 (sum of four scaled sub-scores)

### Sub-scores

| Dimension | Cap | Internal max before scaling |
|-----------|-----|----------------------------|
| Activity | 30 | 25 |
| Nutrition | 30 | 25 |
| Body composition | 18 | 15 |
| Vitals | 22 | 20 |

Each sub-score is computed on its internal scale, then scaled to its cap via:

```swift
activityFinal  = Int((Double(activityCapped) / 25.0 * 30.0).rounded())
nutritionFinal = Int((Double(nutritionScore) / 25.0 * 30.0).rounded())
bodyFinal      = Int((Double(bodyScore)      / 15.0 * 18.0).rounded())
vitalsFinal    = Int((Double(vitalsScore)    / 20.0 * 22.0).rounded())
```

### Gate

Returns `nil` when `stepsHistoryNonZeroDayCount < 5`.

### 4.1 Activity sub-score (internal 0–25)

Computed from:

- **Steps (0–14):** `stepsAvg` from last 13 complete days (today's partial slot dropped via `dropLast()`).  
  `stepsComp = clamp(stepsAvg / 10_000.0, 0, 1.2) * 14.0 / 1.2`  
  Allows up to 20% overshoot (1.2×) before capping — 12 000 steps is the hard ceiling at 14/14.

- **Active energy (0–8):** `activeAvg` from last 13 complete days.  
  `energyComp = clamp(activeAvg / 500.0, 0, 1.2) * 8.0 / 1.2`  
  500 kcal/day is the reference; 600 kcal caps at 8/8.

- **Workout volume (0–3):** `chronicLoadMinutes` (28-day sum, pre-aggregated from `acuteLoadMinutes` / `chronicLoadMinutes` fields).  
  `loadComp = clamp(chronicLoadMinutes / 600.0, 0, 1.5) * 3.0 / 1.5`  
  WHO 150 min/week moderate = 600 min/28d reference.

### 4.2 Nutrition sub-score (internal 0–25)

**Neutral credit:** When no nutrition data is available (`dietaryCalories7Day` empty and `dietaryCaloriesToday == 0`), `nutritionRaw` defaults to **12** (the "neutral" value) so the lack of meal logging doesn't punish a score that would otherwise be accurate.

**When nutrition data exists:**

1. Average intake = `mean(dietaryCalories7Day.filter { $0 > 0 })` if history available, else `dietaryCaloriesToday`.
2. TDEE estimate via `estimateTDEE(heightCm:weightKg:activeAvg:)`:
   - Mifflin-St Jeor midpoint formula (sex and age unknown): `BMR = 10*kg + 6.25*cm - 150`
   - Activity multiplier: `1.2 + min(activeAvg / 1500.0, 0.4)` — ranges from 1.2 (sedentary) to 1.6 (≥600 kcal/day burn).
   - Returns **0** when `heightCm` or `weightKg` is absent. When TDEE is 0, `nutritionRaw` stays at the neutral 12.
3. Caloric deviation scoring:

   | Deviation from TDEE | `calComp` |
   |---------------------|-----------|
   | < 15% | 16 |
   | 15–29% | 12 |
   | 30–49% | 7 |
   | ≥ 50% | 3 |

4. Protein bonus (if `weightKg` known and `dietaryProteinToday > 0`):
   - `perKg = dietaryProteinToday / weightKg`
   - ≥ 1.6 g/kg → +4 pts
   - ≥ 1.2 g/kg → +2 pts

5. Hydration component (always available): `clamp(hydAvg / 2.5, 0, 1.0) * 5` (2.5 L target).

   `nutritionScore = min(25, Int((nutritionRaw + hydComp).rounded()))`

### 4.3 Body composition sub-score (internal 0–15)

**Neutral credit:** When `heightCm` or `weightKg` is absent, `bodyScore = 8` (neutral midpoint of the 0–15 range).

When both are available:
`bmi = weightKg / (heightCm / 100)²`

| BMI range | Score |
|-----------|-------|
| 18.5–24.9 (healthy) | 15 |
| 25.0–26.9 (overweight borderline) | 12 |
| 27.0–29.9 | 8 |
| 30.0–34.9 | 5 |
| ≥ 35.0 | 2 |
| 17.0–18.5 (mild underweight) | 11 |
| 16.0–17.0 | 6 |
| < 16.0 | 3 |

### 4.4 Vitals sub-score (internal 0–20)

Components: **sleep (0–10) + RHR (0–5) + HRV (0–5)**.

**Sleep (0–10):**
- `sleepAvg = mean(sleepHistory28NonZero)`
- If no sleep data: `vitalsRaw += 5` (neutral credit).
- Otherwise: `max(-2, 10 - dev² × 1.5)` where `dev = |sleepAvg - 8.0|`. Allows slight negative to ensure 4h scores lower than 5h. Examples: 7h → 8.5/10; 6h → 4/10; 5h → −2.5 floored to −2.

**RHR (0–5):** Requires `lastNightRHR` non-nil and > 0. Neutral credit = 2.5 when unavailable.

| RHR (bpm) | Points |
|-----------|--------|
| < 50 | 5 |
| 50–59 | 5 |
| 60–69 | 4 |
| 70–79 | 2 |
| ≥ 80 | 0 |

**HRV (0–5):** `clamp(hrv / 100.0, 0, 1.0) * 5` — linear 0–100 ms → 0–5 pts. No HRV data: **0 points, no penalty** (the absence of Watch hardware should not double-penalise an iPhone-only user). This was a fairness fix: an HRV reading below 50 ms that was previously yielding negative contribution now always earns ≥ 0 because the formula never goes below zero.

`vitalsScore = min(20, max(0, Int(vitalsRaw.rounded())))`

### Overall label thresholds

| Score | Label |
|-------|-------|
| ≥ 85 | Excellent |
| 65–84 | Good |
| 45–64 | Fair |
| < 45 | Needs work |

### Confidence

Counts "missing signals" from: nutrition data, BMI data, HRV, RHR.

| Missing signals | Confidence |
|-----------------|-----------|
| 0–1 | high |
| 2 | medium |
| ≥ 3 | low |

---

## 5. Recovery Readiness

**Function:** `predictRecoveryReadiness(snapshot:)` → `RecoveryReadiness?`  
**Output range:** `score` 0–100, `label`: `.strong` (≥75) / `.moderate` (55–74) / `.low` (35–54) / `.rest` (<35)

### Gate

`sleepHistory28NonZero.count` must be ≥ 7 (Watch user) or ≥ 14 (iPhone-only). Returns `nil` otherwise.

### Components

**Sleep Z-score:**
- `sleepMean = mean(sleepHistory28NonZero)`
- `sleepStd = max(stdDev(...), 0.5)` — floored at 0.5h (30 min) to prevent hypersensitivity for tight sleepers
- `sleepZ = clamp((lastNightSleepHours - sleepMean) / sleepStd, -2, 2)` — 0 when `lastNightSleepHours == 0`

**HRV Z-score (Watch only):** requires `lastNightHRV > 0` and `≥ 5` non-zero days in `hrvHistory28`.
- `sd = max(stdDev(...), 3.0)` — 3 ms floor
- `hrvZ = clamp((lastHRV - mean) / sd, -2, 2)`

**RHR Z-score, inverted (Watch only):** requires `lastNightRHR > 0` and `≥ 5` non-zero days in `rhrHistory28`.
- `sd = max(stdDev(...), 1.5)` — 1.5 bpm floor
- `rhrZInv = clamp(-(lastRHR - mean) / sd, -2, 2)` — inverted so lower RHR = positive contribution

**Load freshness:**
- `chronicWeeklyEquivalent = max(chronicLoadMinutes / 4.0, 1.0)`
- `acwr = acuteLoadMinutes / chronicWeeklyEquivalent`
- `loadFreshness = clamp(1.0 - |acwr - 1.0| × 2.0, -2, 2)` — ACWR of 1.0 → freshness = +1.0; deviation of 0.5 → 0; deviation of 1.0 → −1.0

### Weighted blend

| Mode | Weights |
|------|---------|
| Watch (HRV+RHR+sleep+load) | `0.35×hrvZ + 0.25×rhrZInv + 0.25×sleepZ + 0.15×loadFreshness` |
| iPhone-only | `0.65×sleepZ + 0.35×loadFreshness` |

`score = Int(clamp(50.0 + 25.0 × raw, 0, 100).rounded())`

### Confidence

| Condition | Confidence |
|-----------|-----------|
| Watch user with HRV+RHR contributing | high |
| `sleepHistory28NonZero.count ≥ 21` | medium |
| Otherwise | low |

---

## 6. Next-Workout Forecast

**Function:** `predictNextWorkout(snapshot:)` → `NextWorkoutForecast?`

### Gate

Returns `nil` when `workouts28.count < 3`.

### Method

1. Determines target weekday: current weekday if before 18:00, else tomorrow's weekday.
2. Filters `workouts28` to samples matching `targetWeekday`.
3. Groups by `(hourBucket = hour / 3, category)`. Each hour bucket is a 3-hour window (e.g. bucket 6 = hours 6–8).
4. **Primary pass:** finds the `(bucket, category)` with the highest count. Emits if `count ≥ 2` and `count / 4.0 ≥ 0.5` (present in ≥ 50% of the 4 possible recent weeks).
5. **Fallback pass:** ignores category, finds the bucket with the highest any-category count. Same threshold gates.

`support = count / 4.0` (fraction of the 4 most-recent same-weekday occurrences).

| Support | Confidence |
|---------|-----------|
| ≥ 0.75 | high |
| 0.50–0.74 | medium |
| < 0.50 | not emitted |

`isCategoryFallback = true` when only the time-of-day pattern emerged; `category` is set to `.other` in that case.

### HKWorkoutActivityType → ActivityCategory mapping

| ActivityCategory | HK types |
|-----------------|---------|
| `.run` | running |
| `.walk` | walking, hiking |
| `.cycle` | cycling |
| `.strength` | traditionalStrengthTraining, functionalStrengthTraining, crossTraining |
| `.yoga` | yoga, mindAndBody, pilates, flexibility, barre |
| `.hiit` | highIntensityIntervalTraining, coreTraining |
| `.swim` | swimming, waterFitness, waterSports |
| `.other` | everything else |

---

## 7. Goal Trajectories

**Function:** `predictGoalTrajectories(snapshot:)` → `[GoalTrajectory]`  
**Metrics covered:** `.steps`, `.activeEnergy`, `.exerciseMinutes`

### Gate

`elapsedDayFraction` must be ≥ 0.20 (roughly 4:48 AM) to avoid projecting from essentially-zero data.

### Per-metric calculation

For each metric:
1. `nonZero = history14.filter { $0 > 0 }` — requires ≥ 5 non-zero days.
2. `baseline = mean(nonZero)` — 14-day average of non-zero days.
3. `expectedByNow = baseline × elapsedFraction`
4. `pace = currentValue / max(expectedByNow, 1.0)` — where pace stands vs. what the baseline predicts at this hour.
5. `projectedEOD = currentValue / max(elapsedFraction, 0.05)` — full-day projection at current rate.

| Pace | Status |
|------|--------|
| ≥ 1.10 | Ahead of pace |
| 0.90–1.09 | On pace |
| 0.60–0.89 | Behind |
| < 0.60 | Far behind |

`elapsedDayFraction = elapsed_seconds_since_midnight / 86400`, clamped to [0, 1].

**Confidence:** `nonZero.count ≥ 10` → high; otherwise medium.

---

## 8. Sedentary Alert

**Function:** `detectSedentaryAlert(snapshot:)` → `SedentaryAlert?`

### Gates (all must pass)

- `nowHour` in 8–22 (waking window only).
- `hourlyStepsToday.count == 24`.
- `dayTotal > 0` and `anyActivityRecorded` (at least one bucket with steps > 0 before now) — prevents false positives when hourly buckets haven't synced yet but the day total is non-zero.
- `dayTotal < 0.8 × baselineDayTotal` — suppressed when the user has already moved more than usual today.

### Logic

Counts consecutive completed hours ending at `nowHour - 1` where the bucket contains < 250 steps (current hour not judged — it's in progress).

| Quiet hours | Severity |
|------------|----------|
| 2–3 | moderate |
| ≥ 4 | high |

Returns `nil` if `quietHours < 2`. `lastActiveHour` is the most recent completed hour with ≥ 250 steps (searches before 8 AM if needed). Carries `dayTotalSoFar` and `baselineDayTotal` (14-day non-zero mean) for the UI and AI context.

---

## 9. Illness Early-Warning

**Function:** `computeIllnessWarning(snapshot:)` → `IllnessWarning?`

This predictor is explicitly **not a diagnosis**. Every code path that surfaces a warning includes the disclaimer "these are early strain signals, not a diagnosis."

### Watch-gate

Returns `nil` immediately if `rhrHistory30` or `hrvHistory30` contains no non-zero values. iPhone-only users never see this prediction.

### Algorithm

Uses the 30-day zero-filled arrays for `rhr`, `hrv`, and `sleep` (all must be non-empty and have length ≥ 4).

Iterates window lengths `windowLen` from 2 up to `min(n-1, 5)` (cap at 5 to always keep ≥ 1 day outside the window for baseline):

1. **Baseline:** mean of non-zero days *before* the window (requires ≥ 3 non-zero days each for RHR, HRV, sleep).
2. **For every day inside the window**, all three must be non-zero and satisfy:
   - `RHR ≥ baseline + 4 bpm`
   - `HRV ≤ baseline × (1 - 0.12)` (≥ 12% below baseline)
   - `sleep < sleepBase` (any shortfall)
3. Additionally, cumulative `sleepDebt > 1.0 h` across the window.
4. Tracks the longest `windowLen` where all conditions held.

Returns `nil` if the best window is < 2 days. Also guards `bestRhrDelta`, `bestHrvDrop`, `bestSleepDebt` for finiteness before returning.

### Severity

- Default: `.high` if `consecutiveDays ≥ 3` OR (`rhrDelta ≥ 8 bpm` AND `hrvDrop ≥ 20%`); else `.moderate`.
- `.moderate` is bumped to `.high` by symptom corroboration (see below).

### Symptom corroboration

Looks at `recentSymptoms` entries in the range `[windowStart - 2 days, today]`. Symptoms **never trigger** the warning on their own; they only corroborate an already-triggered one.

If `≥ 2 distinct days` within the flagged window have logged symptoms AND the current severity is `.moderate`, it is bumped to `.high`.

The explanation bullets include up to 3 de-duplicated, most-recent-first symptom names.

---

## 10. Anomaly Detection

**Function:** `detectAnomalies(snapshot:)` → `[Anomaly]`

Checks three metrics: sleep (low is concerning), RHR (high, Watch only), HRV (low, Watch only).

### Per-metric method

For each metric:
1. `nonZero = baselineValues.filter { $0 > 0 }` — requires ≥ 7 non-zero days.
2. `m = mean(nonZero)`, `sd = stdDev(nonZero, mean: m)` — requires `sd > 0.001` (flat baseline = no anomaly).
3. `z = (today - m) / sd`
4. Direction check: `z ≤ -1.5` (low direction) or `z ≥ 1.5` (high direction).

| |z| | Severity |
|-----|----------|
| ≥ 2.5 | high |
| 1.8–2.49 | moderate |
| 1.5–1.79 | low |

The `interpretation` field on each `Anomaly` starts as `nil` and is filled in by the AI layer.

---

## 11. Correlation Engine

**Function:** `computeCorrelations(snapshot:)` → `[MetricCorrelation]`  
Returns top 3 by `|r|`.

### Candidate pairs

| Driver | Outcome | Lag |
|--------|---------|-----|
| sleep | hrv | 1 day |
| sleep | restingHeartRate | 1 day |
| steps | sleep | 1 day |
| activeEnergy | sleep | 1 day |
| mindfulMinutes | hrv | 1 day |
| hydration | steps | 0 days (same-day) |
| sleep | steps | 1 day |

### Method

1. Aligns driver day `i` with outcome day `i + lag` from their respective 30-day zero-filled series.
2. Only pairs where **both** values are > 0 are included — zeros (missing days) are excluded after lag alignment.
3. Requires ≥ 12 valid overlapping pairs.
4. Computes Pearson `r` via `pearson(_:_:)`:
   - Returns `nil` on size mismatch, < 2 points, or near-zero variance in either series (prevents NaN in Codable output).
   - Returns `clamp(r, -1, 1)`.
5. Emits only if `|r| ≥ 0.45` and `r.isFinite`.

### Insight string

Deterministic template (no AI), e.g.:  
`"Days you sleep more, next-day HRV tends to run higher (r 0.62, 18 days)"`

The string avoids causality claims — always "tends to," never "causes."

---

## 12. Periodization

**Function:** `computePeriodization(snapshot:)` → `PeriodizationStatus?`

### Gate

- `dailyKcalLoad28.count == 28` — exact length required.
- `nonZeroDays ≥ 6`, OR (`chronicLoadMinutes > 0` AND `nonZeroDays ≥ 4`).

### Method

Chunks `dailyKcalLoad28` into four 7-day weeks (oldest→newest):

- `weekLoad = week4.reduce(0, +)` (current week)
- `baseline = mean of prior 3 weeks that carried any load` (zero-week weeks excluded from average)
- `trend = (weekLoad - baseline) / max(baseline, 1.0) × 100` (clamped to finite)
- `acwr = acuteLoadMinutes / max(chronicLoadMinutes / 4.0, 1.0)` (acute/weekly-equivalent-chronic)

### Phase classification

| Condition | Phase |
|-----------|-------|
| `trend ≥ 15%` AND `acwr ≤ 1.3` | build |
| `trend ≥ 15%` AND `acwr > 1.3` | peak |
| `trend ≤ -30%` AND `recoveryScore < 50` | recover |
| `trend ≤ -30%` | deload |
| Otherwise | steady |

`recoveryScore` is read from a fresh `predictRecoveryReadiness(snapshot:)` call for the recover vs. deload split. This is the only predictor that calls another predictor internally.

### Confidence

| Non-zero workout days | Confidence |
|----------------------|-----------|
| ≥ 10 | high |
| < 10 | medium |

---

## 13. Adaptive Goal Suggestions

**Function:** `computeGoalSuggestions(snapshot:)` → `[GoalSuggestion]`  
Returns top 3 by deviation of median attainment from 1.0.

### Gate (per metric)

- Current goal > 0 and finite.
- `goalHistories28[rawValue]` populated (only `isUserConfigurableGoal` metrics).
- `nonZero = history.filter { $0 > 0 }.count ≥ 14`.

### Logic

1. `attainments = nonZero.map { $0 / currentGoal }`
2. `medianAttain = median(attainments)`
3. Decision:
   - `medianAttain < 0.55` → direction = "lower", `suggested = percentile(nonZero, 0.70)` — the 70th-percentile daily value (a reachable stretch)
   - `medianAttain ≥ 1.25` → direction = "raise", `suggested = percentile(nonZero, 0.50)` — the median daily value
   - Between 0.55–1.24 → no suggestion
4. Direction consistency guard: suggested must actually move the goal in the stated direction (handles bimodal distributions).
5. Change threshold: `|suggested - currentGoal| ≥ 0.10 × currentGoal` (< 10% not worth surfacing).

### Rounding

Goals are rounded to metric-appropriate steps:

| Metric | Step |
|--------|------|
| steps | 500 |
| activeEnergy | 25 kcal |
| sleep | 0.25 h |
| distance | 0.25 mi |
| hydration | 0.1 L |
| exerciseMinutes | 5 min |
| standHours | 1 h |
| mindfulMinutes | 5 min |
| flightsClimbed | 1 |

**Confidence:** `nonZero.count ≥ 21` → high; else medium.

---

## 14. Sleep Forecast

**Function:** `computeSleepForecast(snapshot:)` → `SleepForecast?`

Uses a **stratified comparison** — intentionally not regression, because sample sizes are too small for regression to be honest.

### Gate

- `sleepHistory30` must be non-empty and contain at least one non-zero value.
- Must produce ≥ 10 valid `(activityScore, nextNightSleep)` pairs after alignment.

### Activity score per day

Inputs are `stepsHistory30`, `activeEnergyHistory30`, `dailyKcalLoad28` — all aligned to `sleepHistory30`'s length (zero-padded at the front if shorter).

Per-day medians (`nonZeroMedian`) are computed from each aligned series. For day `i`:

```
activityScore = mean of available ratios [steps_i/stepsMed, energy_i/energyMed, kcal_i/kcalMed]
```

Only features where both the series median and the day's value are > 0 and finite contribute to the mean. Returns `nil` when no feature is available.

### Pair building

For each day `i` in `0..<(nDays-1)`:
- `nextSleep = sleep[i+1]` — must be > 0 and finite.
- Must have a computable `activityScore`.

Requires ≥ 10 such pairs.

### Strata

- `p75 = percentile(scores, 0.75)`; `p25 = percentile(scores, 0.25)`
- Stratified only if `p75 > p25`. Degenerate case (all scores equal) falls through to the "typical day" / overall-median path.
- `highPairs`: score > p75; `lowPairs`: score < p25; `midPairs`: between p25 and p75.

Stratum mean requires ≥ 3 pairs. Falls back to `overallMedian` if the stratum is too thin.

### Classifying today

Before 16:00 (`nowHour < 16`) or when today's projected score cannot be computed: stratum = "mid", forecast = overall median.

After 16:00: today's running totals are normalized by the same medians:
- `todayScore = activityScore(stepsToday, activeEnergyToday, kcalLastIsToday ? kcalA.last : 0)`
- `projectedScore = todayScore / max(elapsedDayFraction, 0.5)` — projects partial-day score to full-day equivalent, divisor floored at 0.5 to cap amplification at 2×.

Classify by projected score vs `p25`/`p75` thresholds.

### Confidence

| Condition | Confidence |
|-----------|-----------|
| `matchedCount ≥ 6` AND `|predicted - baseline| ≥ 0.4 h` | high |
| `matchedCount ≥ 3` | medium |
| "typical day" path with ≥ 10 total pairs | low |
| Otherwise | `nil` (not emitted) |

`predictedHours` is clamped to [3.0, 12.0].

---

## 15. AI Enrichment Layer

Handled by `PredictionAIService` (`actor`), which decorates deterministic predictions with personalized language.

### Model and endpoint

```
Model:    gemini-3.5-flash
Location: global   (regional endpoints return 404 for 3.x models)
Base URL: https://aiplatform.googleapis.com/v1/projects/{projectId}/locations/global/
          publishers/google/models/gemini-3.5-flash:{method}
```

`thinkingBudget` tokens are added to every `maxOutputTokens` to prevent visible output starvation from Gemini 3.5-flash's internal reasoning step. The budget is read from `VertexGeminiClient.thinkingBudgetTokens()`.

### Three parallel sub-tasks

All three run with `async let` inside a single `Task` — they are independent.

| Sub-task | Function | Max tokens | Output |
|----------|----------|-----------|--------|
| Daily insight | `generateDailyInsight` | 220 | `DailyInsight` with `headline`, `body`, `confidence` |
| Action chips | `suggestActions` | 500 | Up to 3 `ActionSuggestion` items, title clipped at 28 chars |
| Anomaly interpretation | `interpretAnomalies` | 500 | `[UUID: String]` keyed by `Anomaly.id`, ≤ 2 sentences each |

**Partial failure tolerance:** if 1 or 2 sub-tasks fail, the bundle is still returned with those fields empty. Only if all 3 fail does `enrichPredictions` throw.

### Task deduplication

```swift
private var inflight: Task<EnrichmentBundle, Error>?
```

If `enrichPredictions` is called while a request is already in flight, both callers `await` the same `Task`. The `inflight` reference is cleared via `defer` when the task completes.

### Caching

- A same-day `EnrichmentBundle` is persisted to UserDefaults (JSON-encoded) after a successful Vertex call.
- `kickoffAIEnrichmentIfNeeded()` checks the cache first. On hit, it calls `merging(... status: .cached)` immediately without touching the network.
- Cache key is the calendar date. A new calendar day always misses.

### Why-sheet streaming

`explainPrediction(_:predictions:userContext:)` is `nonisolated` and returns an `AsyncThrowingStream<WhyStreamEvent, Error>`:

```swift
enum WhyStreamEvent {
    case text(String)
    case usage(TokenUsage)
}
```

Uses `streamGenerateContent` SSE endpoint with a 30-second timeout. Parses the JSON stream via a brace-depth scanner (same approach as `VertexGeminiClient`): increments `braceDepth` on `{`, decrements on `}`, and calls `emitTextChunk` when depth returns to 0.

Per-kind prompt shapes are injected via `whyOutputShape(for:)` — each covers which sub-scores or factors to enumerate, the output section structure, and any domain-specific rules (e.g. illness warning must never use the word "diagnose" or suggest seeing a doctor unless RHR delta > 15 bpm).

### `predictionsSummary` context string

`PredictionAIService.predictionsSummary(_:)` is `nonisolated static` and serializes every engine field into a compact multi-line string. It is used as the ground-truth context block in all three sub-task prompts and in every Why-sheet prompt. Key formatting choices:
- All values from the deterministic engine (scores, units, confidence, flags like `mealsLoggedToday`) are included verbatim.
- Load trend sign is always explicit (`+`/`-`).
- `sleepForecast` includes the pre-formatted `basis` sentence.
- `goalSuggestions` emit the direction and median attainment percentage.

---

## 16. ContentSignature and merge pattern

### Why ContentSignature exists

`PredictionEngine.computeAll` stamps a fresh `generatedAt: Date()` on every call. A plain `==` comparison of two `Predictions` values always differs because `Date` equality is nanosecond-precise. Without the signature, every recompute would trigger a full `@Published` reassignment and a whole-tree SwiftUI re-render, even when nothing meaningful changed.

```swift
if predictions?.contentSignature != newPredictions.contentSignature {
    predictions = newPredictions
}
```

### `ContentSignature` fields

`ContentSignature` is a nested `struct: Equatable` inside `Predictions`. It mirrors all fields **except** `generatedAt`. That means two `Predictions` values are considered content-equal if their engine outputs and AI enrichment status are identical, regardless of when they were computed.

### `merging(...)` method

```swift
func merging(insight: DailyInsight?,
             actions: [ActionSuggestion],
             anomalyInterpretations: [UUID: String],
             status: EnrichmentStatus) -> Predictions
```

Returns a **new** `Predictions` value with all engine fields copied unchanged and only the AI fields (`dailyInsight`, `actions`, anomaly `interpretation` strings, `aiEnrichmentStatus`) replaced. The engine's `generatedAt` is preserved. This is the only place AI content is spliced in — the engine is never re-run during enrichment.

The anomaly interpretation splice iterates `self.anomalies` by index and replaces matching `id` entries:

```swift
var newAnomalies = self.anomalies
for i in newAnomalies.indices {
    if let text = anomalyInterpretations[newAnomalies[i].id] {
        newAnomalies[i].interpretation = text
    }
}
```

### Snapshot-replacement guard in kickoffAIEnrichmentIfNeeded

```swift
let target = p.generatedAt
lastEnrichmentTargetTimestamp = target
```

When the async enrichment completes, it only applies results if `lastEnrichmentTargetTimestamp == target` and `current.generatedAt == target`. This prevents a stale Vertex response from overwriting a newer snapshot that arrived during the in-flight request.

---

## 17. Data conventions

### Units in storage vs display

All values passed in the Snapshot and stored in `Predictions` use the raw units in which HealthKit or the engine computed them:

| Metric | Stored unit | Display unit |
|--------|-------------|-------------|
| Distance | km | mi (converted via `LocaleUnits`) |
| Height | cm | ft/in or cm (locale) |
| Weight | kg | lbs or kg (locale) |
| Energy | kcal | kcal |
| Sleep | hours | "Xh Ym" formatted |
| Hydration | litres | litres |
| Steps | count | count |

Display conversion is done in the View layer via `LocaleUnits`; the engine and model types never do locale-aware formatting.

### No mock data

The engine follows the project-wide "no mock data" rule. Every predictor returns `nil` or an empty array when its data gates are not met. The UI renders honest empty states ("—", "Building baseline · Day N of 7") rather than placeholder numbers.

### Confidence levels

`PredictionConfidence` has three cases: `.low`, `.medium`, `.high`. General rules across predictors:
- `.high` requires ≥ 10–21 days of non-zero data (varies by predictor) and all optional signals present.
- `.medium` requires baseline history but missing some optional signals or thin sample.
- `.low` is rare; emitted only when the predictor can produce a defensible output but the backing data is minimal.

### EnrichmentStatus lifecycle

```
.skipped  — baseline gate failed or Vertex not configured
.pending  — computeAll returned, kickoff not yet run
.cached   — same-day bundle found on disk, spliced immediately
.complete — Vertex returned successfully
.failed   — all three sub-tasks threw; UI shows "Retry insights"
```

`retryAIEnrichment()` resets status to `.pending`, clears the cache, and calls `kickoffAIEnrichmentIfNeeded()` again.
