# Fitness Guru

A native **iOS 26** fitness app built in SwiftUI, centered on **Astra** — an AI fitness coach
powered by Google Vertex AI (Gemini). Fitness Guru reads your Apple Health data, calendar, and
reminders, runs on-device prediction and sleep engines, and turns it all into personalized,
honest coaching. Liquid Glass UI throughout; no mock data — every number is real or shown as "—".

> Personal project, built for a single device (iPhone 17 Pro, iOS 26). Distributed via a personal
> development signature, not the App Store.

---

## Features

**AI Coach — Astra**
- Streaming chat (Vertex AI Gemini, `gemini-3.5-flash`) with live HealthKit context injected into
  every conversation, so advice is grounded in your real steps, sleep, heart rate, and nutrition.
- Tool calling — Astra can read predictions, log food, set reminders, and surface health insights.
- On-device JWT signing (`Security` framework, RSA-SHA256) exchanges the service-account key for a
  short-lived Google OAuth token. No third-party SDK.
- Per-day caching of AI enrichment to keep token usage (and cost) low; a built-in **token meter**
  tracks spend by feature.

**Health dashboard**
- Live Apple HealthKit integration — activity, vitals, body, nutrition, sleep, workouts, mobility.
- **Health Meter**: a 0–100 composite score across Activity (30) / Nutrition (30) / Body (18) /
  Vitals (22), with a "why" breakdown.
- Interactive Swift Charts trends (7-day / 30-day / 1-year), detailed per-metric views, and
  heart-rate zone analysis.
- Silent background sync (every 15s while on-screen + on foreground) with native pull-to-refresh.

**Food vision**
- Snap a photo of a meal; Gemini identifies dishes, estimates macros, and flags each as an
  estimate with a confidence score.
- Natural-language correction chat ("the chicken is skinless", "remove the tacos") that re-runs
  recognition with the photo + current items as full context.
- Per-dish editing and delete in the review sheet before logging to Apple Health.

**Sleep**
- On-device sleep tracking with snore detection (Apple's Sound Analysis framework — audio is
  analyzed locally and never recorded or uploaded).
- Sleep-pattern analysis, Sleep Focus detection, and a morning sleep report.
- Guided breathing sessions.

**Predictions & engines (on-device)**
- Prediction engine, training-load engine, streak/challenge engines, and recovery scoring.
- Daily challenges and streak tracking.

**Planning**
- EventKit calendar + reminders integration to plan workouts, hydration, supplements, and recovery
  around your day.
- Inactivity nudges via local notifications.

---

## Tech stack

| Area | Detail |
|---|---|
| UI | SwiftUI, iOS 26 native **Liquid Glass** (`.glassEffect`), `NavigationStack`, native `TabView` / Swift Charts |
| Health | HealthKit (read + write), incl. clinical records |
| Planning | EventKit / EventKitUI, UserNotifications |
| AI | Google Vertex AI — Gemini `gemini-3.5-flash` via the global endpoint, streaming |
| Audio | Sound Analysis (on-device snore/sleep detection) |
| Auth | On-device RSA-SHA256 JWT → Google OAuth2 (Apple `Security` framework) |
| Build | XcodeGen (`project.yml`), `xcodebuild`, `devicectl` |
| Min target | iOS 26.0 · iPhone only |

The app is structured around five tabs: **Home**, **Coach** (Astra), **Reminders**, **Progress**,
and **Profile**.

---

## Project structure

```
FitnessApp.swiftpm/FitnessApp/
├── FitnessApp.swift          # App entry point
├── ContentView.swift         # Root TabView (Liquid Glass tab bar)
├── HealthKitManager.swift    # Apple Health read/write
├── Models/                   # HealthMetric, ChatMessage, Prediction, Sleep*, ToolCall, …
├── Services/                 # Vertex AI client/auth, prediction/sleep/streak engines, food vision
├── ViewModels/               # ChatViewModel, ChatPrefillBus
└── Views/                    # Dashboard, Chat, FoodScan, Sleep, Onboarding, Settings, …

project.yml                   # XcodeGen spec — source of truth for plist/permissions/signing
agents_log.md                 # Full change history & per-session handoffs
```

---

## Build & deploy

The Xcode project is **generated from `project.yml`** by XcodeGen. After adding or removing Swift
files, regenerate it:

```bash
xcodegen --spec project.yml
```

**Build to the device:**

```bash
xcodebuild -project FitnessApp.xcodeproj -scheme FitnessApp \
  -destination "id=<DEVICE_UDID>" \
  DEVELOPMENT_TEAM=RM42FV53FU CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build
```

**Install + launch:**

```bash
xcrun devicectl device install app --device "<DEVICE_UDID>" \
  "<DerivedData>/Build/Products/Debug-iphoneos/FitnessApp.app"

xcrun devicectl device process launch --device "<DEVICE_UDID>" com.tushar.fitnessapp
```

**Fast compile check** (no signing/device) — append:

```bash
-destination "platform=iOS Simulator,id=<SIMULATOR_UDID>"
```

> After renewing a personal development certificate, the first launch is blocked until you trust the
> profile on-device: **Settings → General → VPN & Device Management → Developer App → Trust**.

---

## Configuration — Vertex AI credentials

Astra needs a Google Cloud service-account key for Vertex AI. **Credentials are never committed.**

- A `vertex-service-account.json` may live on disk as a bundled resource (gitignored), **or**
- You can paste the JSON key in-app under **Settings → AI Coach** (stored in `UserDefaults`,
  takes precedence over the bundled file).

`.gitignore` blocks `*service-account*.json`, `*.pem`, `*.p12`, `.env`, and `.env.*`. Never
force-add a credential, and scan staged diffs for `PRIVATE KEY` / `private_key` / `AIza` / `MII…`
blobs before committing.

---

## Conventions

These are firm project rules:

- **iOS 26 native only** — real `.glassEffect(.regular.interactive(), in: …)`, `NavigationStack`,
  native `TabView` / Charts. No fake glass (`.background` + `.overlay(stroke)`).
- **No mock data anywhere** — honest empty states (`—`, "No data yet").
- **Every clickable element does something** — no empty `Button(action: {})`.
- AI replies stay brief and structured. Logged food carries `is_estimate` + a confidence.
- Gemini is `gemini-3.5-flash` via the **global** endpoint only (regional endpoints 404 for 3.x);
  thought-signatures round-trip for tool calls; `thinkingConfig` lives only inside `generationConfig`.

---

## Privacy

Fitness Guru reads sensitive Health, calendar, reminder, camera, photo, microphone, and Focus data
strictly to power coaching on your own device. Sleep audio is analyzed on-device and never recorded
or uploaded. Health context sent to Vertex AI is what's needed to answer your prompts. Permission
purpose strings are defined in `project.yml`.
