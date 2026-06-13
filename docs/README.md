# Fitness Guru — Documentation

Developer documentation for **Fitness Guru**, a native iOS 26 SwiftUI AI fitness app
(build seq 3004, ~30k LOC, 79 Swift files). Start with the root [README](../README.md) for the
project overview; these documents go deep on each subsystem.

| Document | Read it when you need to… |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Understand the layer map, the five-tab shell, how `HealthKitManager`'s single-publish pipeline feeds the engines and UI, the engine-vs-AI split, and the cross-cutting patterns (frozen contracts, glass-only, imperial storage). Includes the data-flow diagram. |
| [FEATURES.md](FEATURES.md) | Find what a feature is and which view implements it — every tab and area, with entry-point files and one-line "how it works". |
| [PREDICTION_ENGINE.md](PREDICTION_ENGINE.md) | Work on the on-device predictors — inputs, gating thresholds, exact math, and confidence for the Health Meter, recovery, trajectories, sedentary, illness warning, correlations, periodization, goal suggestions, and sleep forecast — plus the AI enrichment layer and the `Snapshot`/`ContentSignature` patterns. |
| [ASTRA_AI.md](ASTRA_AI.md) | Touch anything Vertex/Gemini — the on-device auth flow, the streaming + thought-signature pipeline, the ~24-tool registry and confirm/follow-up flow, system-prompt assembly, chat-history persistence, and the token meter. |
| [DATA_AND_PRIVACY.md](DATA_AND_PRIVACY.md) | Reason about data — HealthKit read/write type lists, the `HealthMetricType` model, `LocaleUnits`, app-scoped EventKit, the full UserDefaults/`@AppStorage` key inventory, what leaves the device, and credential handling. |
| [BUILD_AND_DEPLOY.md](BUILD_AND_DEPLOY.md) | Build, deploy, or contribute — XcodeGen, the `register_pbx.py` fallback, exact device/simulator commands, troubleshooting, the git secret-scan protocol, firm conventions, and the multi-agent workflow norms. |

## Conventions these docs assume

- **iOS 26 native Liquid Glass only** — `.glassEffect(...)`, `NavigationStack`, native `TabView`/Charts.
- **No mock data** — honest `—` / empty states everywhere.
- **Gemini `gemini-3.5-flash` via the Vertex global endpoint**; thought-signatures round-trip on tool calls.
- **Storage stays imperial / HealthKit-native; display converts via `LocaleUnits`.**
- The full chronological change history (48 sessions) is in [`../agents_log.md`](../agents_log.md).
