# Fitness Guru

A native **iOS 26** fitness app built in SwiftUI, centered on **Astra** — an AI fitness coach
powered by Google Vertex AI (Gemini `gemini-3.5-flash`). Fitness Guru reads your Apple Health data,
calendar, and reminders, runs a suite of **on-device prediction engines**, and turns it all into
personalized, honest coaching. Liquid Glass UI throughout; no mock data — every number is real or
shown as "—".

> Personal project, built for a single device (iPhone 17 Pro, iOS 26). Distributed via a personal
> development signature, not the App Store.

---

## Documentation

Deep-dive docs live in [`docs/`](docs/):

| Doc | What's inside |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Layer map, data flow, the HealthKit hub + single-publish pipeline, engine-vs-AI split, cross-cutting patterns |
| [Features](docs/FEATURES.md) | Complete feature catalog by tab, with entry-point files |
| [Prediction Engine](docs/PREDICTION_ENGINE.md) | Every on-device predictor — inputs, gating, math, confidence — plus the AI enrichment layer |
| [Astra / Vertex AI](docs/ASTRA_AI.md) | Auth flow, streaming, the tool catalog, system-prompt assembly, token meter |
| [Data & Privacy](docs/DATA_AND_PRIVACY.md) | HealthKit types, the `HealthMetricType` model, app-scoped EventKit, the UserDefaults key inventory, what leaves the device |
| [Build & Deploy](docs/BUILD_AND_DEPLOY.md) | XcodeGen, device/simulator build commands, pbxproj registration, troubleshooting, contributing norms |

Full per-session change history is in [`agents_log.md`](agents_log.md).

---

## Features at a glance

**AI Coach — Astra**
- Streaming chat (Vertex AI Gemini `gemini-3.5-flash`, global endpoint) with the full health picture
  injected into every turn — today's metrics, 7-day trends, predictions, nutrition, sleep pattern,
  training load, streaks, symptoms, cycle — so advice is grounded in your real data.
- **~24 function-calling tools**: log/edit food, manage reminders & calendar events, query any metric's
  history, read predictions & sleep detail, update goals, author Home widgets, render charts with
  analysis. Writes are confirmation-gated; thought-signatures round-trip per Gemini 3.x.
- On-device RSA-SHA256 JWT signing exchanges the service-account key for a short-lived Google OAuth
  token — no third-party SDK. Per-day enrichment caching + a built-in **token meter** (usage and cost
  estimate by feature).
- **Chat history** survives force-quit (continuous live-session persistence) with an archive list.

**Health dashboard**
- Live HealthKit across activity, vitals, body, nutrition, sleep, workouts, and mobility.
- Auto-arranging card grid — cards hide when a metric goes quiet for 7 days and promote back when data
  returns; Watch-only cards hide for iPhone-only users.
- Interactive Swift Charts (7-day / 30-day / 1-year), smoothed; per-metric detail views; HR zones.
- Silent background sync (15s while on-screen + on foreground) with native pull-to-refresh.

**On-device prediction engine** *(pure Swift, no AI in the numbers)*
- **Health Meter** — 0–100 composite (Activity 30 / Nutrition 30 / Body 18 / Vitals 22) with a "Why?"
  breakdown.
- **Recovery readiness**, **next-workout forecast**, **goal trajectories**, **sedentary alerts**.
- **Illness early-warning** (RHR↑ + HRV↓ + sleep debt vs your own baseline, corroborated by logged
  symptoms — never diagnoses), **correlation engine** (lagged Pearson patterns), **periodization**
  (Build/Peak/Deload/Recover/Steady), **adaptive goal suggestions**, **tonight's sleep forecast**.
- An additive **AI enrichment layer** turns these into a daily insight, action chips, anomaly
  interpretations, and streaming "Why?" deep-dives.

**Food & nutrition**
- **Photo logging** — Gemini Vision identifies dishes, estimates macros, flags estimates + confidence;
  natural-language correction chat; per-dish edit/delete before writing to Apple Health.
- **Barcode / QR scanning** — live detection → Open Food Facts → real label nutrition **and the product
  photo**; honest not-found/network fallbacks. Label data is written as authoritative (no estimate badge).
- Nutrition dashboard with macro donut, calorie trend, and an editable macro-goal sheet.

**Sleep**
- On-device tracking with snore detection (Apple Sound Analysis — audio analyzed locally, never recorded
  or uploaded), morning report, sleep-pattern model, and Sleep Focus detection.

**Engagement & planning**
- Weekly **streaks** with milestone trophies, **daily challenges**, **guided breathing**.
- **App-scoped** EventKit calendar + reminders (a dedicated "Fitness Guru" calendar/list — your personal
  events are never touched), plus inactivity nudges via local notifications.

**Astra Widget Studio** — Astra can design up to 6 live Home widgets (KPIs, rings, sparklines,
checklists, action buttons) bound to your real HealthKit data.

---

## Tech stack

| Area | Detail |
|---|---|
| UI | SwiftUI, iOS 26 native **Liquid Glass** (`.glassEffect`), `NavigationStack`, native `TabView` / Swift Charts |
| Health | HealthKit (read + write), clinical records opt-in |
| Planning | EventKit / EventKitUI, UserNotifications |
| AI | Google Vertex AI — Gemini `gemini-3.5-flash` via the **global** endpoint, streaming |
| Food data | Open Food Facts (barcode lookup), Gemini Vision (photo) |
| Audio | Sound Analysis (on-device snore/sleep detection) |
| Auth | On-device RSA-SHA256 JWT → Google OAuth2 (Apple `Security` framework) |
| Build | XcodeGen (`project.yml`), `xcodebuild`, `devicectl` |
| Localization | `LocaleUnits` — distance/speed/length display follows `Locale.measurementSystem` (km for UK/metric) |
| Min target | iOS 26.0 · iPhone only |

Five tabs: **Home**, **Coach** (Astra), **Reminders**, **Progress**, **Profile**.

---

## Project structure

```
FitnessApp.swiftpm/FitnessApp/
├── FitnessApp.swift          # App entry point
├── ContentView.swift         # Root TabView (Liquid Glass) + modal/prefill routing
├── HealthKitManager.swift    # Central data hub — Apple Health read/write, single-publish pipeline
├── Models/                   # HealthMetric, Prediction, ToolCall, ChatMessage, AstraWidget, Sleep*, …
├── Services/                 # Vertex client/auth, prediction/sleep/streak/load engines, food vision, barcode
├── ViewModels/               # ChatViewModel, ChatPrefillBus
└── Views/                    # Dashboard, Chat, FoodScan, Sleep, Onboarding, Progress, Settings, Components/

project.yml                   # XcodeGen spec — source of truth for plist/permissions/signing
docs/                         # Developer documentation (see table above)
agents_log.md                 # Full change history & per-session handoffs
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full module map and data flow.

---

## Build & deploy

The Xcode project is **generated from `project.yml`** by XcodeGen. Full instructions, the pbxproj
registration fallback, and troubleshooting are in [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md).

```bash
xcodegen --spec project.yml          # regenerate after adding/removing Swift files

# Build to device
xcodebuild -project FitnessApp.xcodeproj -scheme FitnessApp \
  -destination "id=<DEVICE_UDID>" \
  DEVELOPMENT_TEAM=RM42FV53FU CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build

# Install + launch
xcrun devicectl device install app --device "<DEVICE_UDID>" \
  "<DerivedData>/Build/Products/Debug-iphoneos/FitnessApp.app"
xcrun devicectl device process launch --device "<DEVICE_UDID>" com.tushar.fitnessapp

# Fast compile check — append:
-destination "platform=iOS Simulator,id=<SIMULATOR_UDID>"
```

> After renewing a personal development certificate, trust the profile on-device:
> **Settings → General → VPN & Device Management → Developer App → Trust**.

---

## Configuration — Vertex AI credentials

Astra needs a Google Cloud service-account key for Vertex AI. **Credentials are never committed.**

- A `vertex-service-account.json` may live on disk as a bundled resource (gitignored), **or**
- Paste the JSON key in-app under **Settings → AI Coach** (stored in `UserDefaults`, takes precedence
  over the bundled file).

`.gitignore` blocks `*service-account*.json`, `*.pem`, `*.p12`, `.env`, `.env.*`. Never force-add a
credential, and scan staged diffs for `PRIVATE KEY` / `private_key` / `AIza` / `MII…` blobs before
committing. See [docs/DATA_AND_PRIVACY.md](docs/DATA_AND_PRIVACY.md).

---

## Conventions

Firm project rules (details in [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md)):

- **iOS 26 native only** — real `.glassEffect(.regular.interactive(), in: …)`, `NavigationStack`,
  native `TabView` / Charts. No fake glass (`.background` + `.overlay(stroke)`).
- **No mock data anywhere** — honest empty states (`—`, "No data yet").
- **Every clickable element does something** — no empty `Button(action: {})`.
- AI replies stay brief and structured. Logged food carries `is_estimate` + a confidence; Astra never
  claims a write it didn't perform, and never hallucinates an Apple Watch for iPhone-only users.
- Gemini is `gemini-3.5-flash` via the **global** endpoint only (regional endpoints 404 for 3.x);
  thought-signatures round-trip for tool calls; `thinkingConfig` lives only inside `generationConfig`.
- **Units**: stored values stay imperial (HealthKit-native); display converts via `LocaleUnits` keyed
  off the device region. Week math uses the ISO-8601 (Monday-start) calendar.

---

## Privacy

Fitness Guru reads sensitive Health, calendar, reminder, camera, photo, microphone, and Focus data
strictly to power coaching on your own device. Sleep audio is analyzed on-device and never recorded or
uploaded. Health context sent to Vertex AI is only what's needed to answer your prompts; barcode lookups
hit Open Food Facts with a product code. Permission purpose strings are defined in `project.yml`. Full
breakdown in [docs/DATA_AND_PRIVACY.md](docs/DATA_AND_PRIVACY.md).
