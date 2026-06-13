# Build, Deploy, and Contributing — Fitness Guru

Reference for any engineer working on the app. Covers prerequisites, project generation, build and install commands, the git safety protocol, firm code conventions, and the multi-agent workflow norms used to build the app.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository layout](#2-repository-layout)
3. [Project generation from project.yml](#3-project-generation-from-projectyml)
4. [register_pbx.py — fallback when XcodeGen is absent](#4-register_pbxpy--fallback-when-xcodegen-is-absent)
5. [Build commands](#5-build-commands)
6. [Install and launch](#6-install-and-launch)
7. [databaseSequenceNumber — tracking deploys](#7-databasesequencenumber--tracking-deploys)
8. [Troubleshooting](#8-troubleshooting)
9. [Git safety protocol](#9-git-safety-protocol)
10. [Firm code conventions](#10-firm-code-conventions)
11. [Multi-agent workflow norms](#11-multi-agent-workflow-norms)
12. [Outstanding action items](#12-outstanding-action-items)

---

## 1. Prerequisites

| Requirement | Value |
|---|---|
| Xcode | 26 (ships with Swift 6.3.2) |
| Target OS | iOS 26.0 |
| XcodeGen | Recommended; binary at `/tmp/XcodeGen/.build/arm64-apple-macosx/release/xcodegen` if Homebrew is unavailable |
| Development Team | `RM42FV53FU` |
| Physical device UDID | `6EBFD630-1768-512E-95E3-EC7D76AA8CDD` (Tushar's iPhone 17 Pro) |
| Simulator UDID | `FF8921FE-10E6-4CAE-8722-D4BBD505DA98` (iPhone 17 Pro, iOS 26.5) |
| GitHub remote | https://github.com/sangwanboy/Fitness-App (branch `main`) |

Homebrew is broken on macOS 26 (`/opt/homebrew` permissions + unsupported OS version). The `gh` CLI 2.93.0 binary lives at `~/.local/bin/gh`; `$PATH` must include that directory (`export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`).

The real Google Cloud service-account credential `vertex-service-account.json` lives at `FitnessApp.swiftpm/FitnessApp/vertex-service-account.json` on disk. It is gitignored and must never be committed (see Section 9).

---

## 2. Repository layout

```
Fitness App/                          ← repo root
├── project.yml                       ← XcodeGen spec (source of truth for plist/permissions/signing)
├── FitnessApp.xcodeproj/             ← generated; do not hand-edit unless using register_pbx.py
├── FitnessApp.swiftpm/
│   └── FitnessApp/
│       ├── FitnessApp.swift          ← @main, app lifecycle, migration hooks
│       ├── ContentView.swift         ← root TabView + onboarding gate + scenePhase hooks
│       ├── HealthKitManager.swift    ← singleton, all HK reads/writes
│       ├── Models/
│       ├── Services/
│       ├── ViewModels/
│       └── Views/
│           ├── Components/
│           ├── FoodScan/
│           └── Onboarding/
├── agents_log.md                     ← full session history; read before large changes
├── CLAUDE.md                         ← agent instructions
└── docs/                             ← this directory
```

All Swift sources are under `FitnessApp.swiftpm/FitnessApp`. The `project.yml` sources glob covers this entire tree, so XcodeGen discovers files automatically. Explicit `PBXFileReference` registration is only needed when XcodeGen is unavailable.

---

## 3. Project generation from project.yml

`project.yml` is the **single source of truth** for:

- Deployment target (`26.0`)
- Framework dependencies (`HealthKit.framework`, `EventKit.framework`, `EventKitUI.framework`, `UserNotifications.framework`)
- Signing (`DEVELOPMENT_TEAM: RM42FV53FU`, `CODE_SIGN_STYLE: Automatic`)
- Entitlements file (`FitnessApp.swiftpm/FitnessApp.entitlements`)
- All `Info.plist` keys — every privacy usage description string and `UIBackgroundModes`

XcodeGen overwrites `FitnessApp.swiftpm/AppInfo.plist` on every run. Never hand-edit the plist; edit `project.yml` and regenerate.

**After adding or removing any Swift file:**

```bash
/tmp/XcodeGen/.build/arm64-apple-macosx/release/xcodegen --spec project.yml
```

If XcodeGen is not installed, use the fallback described in Section 4.

### Key project.yml settings that have caused build failures in the past

`project.yml` must explicitly include both of the following in `settings.base`, because recent versions of XcodeGen stopped emitting them automatically — their absence caused "Multiple commands produce '…/FitnessApp.app'" Xcode errors:

```yaml
settings:
  base:
    PRODUCT_NAME: FitnessApp
    SWIFT_VERSION: "5.0"
```

Both are already present in the file; do not remove them.

---

## 4. register_pbx.py — fallback when XcodeGen is absent

`/tmp/register_pbx.py` is an idempotent Python 3 script that inserts a single Swift file into `FitnessApp.xcodeproj/project.pbxproj`. It is the correct fallback when XcodeGen is unavailable or when adding a single file is faster than a full regen.

**Usage:**

```bash
python3 /tmp/register_pbx.py <GroupName> <FileName.swift> [<GroupName> <FileName.swift> ...]
```

Example — register two new files:

```bash
python3 /tmp/register_pbx.py Services FoodVisionService.swift Models FoodVisionModels.swift
```

### What it does per file

The script generates deterministic 24-hex UUIDs seeded from the filename (`hashlib.md5`) so reruns produce the same UUIDs and are therefore no-ops for already-registered files. For each file it:

1. **PBXBuildFile section** — inserts `<UUID> /* <file> in Sources */ = {isa = PBXBuildFile; fileRef = <fref>; };`
2. **PBXFileReference section** — inserts `<fref> /* <file> */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = <file>; sourceTree = "<group>"; };`
3. **PBXGroup `children`** — appends the `fref` UUID into the named group's children list (the group must already exist; common groups: `Models`, `Services`, `Views`, `Components`, `FoodScan`, `Onboarding`)
4. **PBXSourcesBuildPhase `files`** — appends the build-file UUID

After running, validate with `plutil -lint FitnessApp.xcodeproj/project.pbxproj` (should print `OK`).

The script operates on the hardcoded path `/Users/tushar/projects/Fitness App/FitnessApp.xcodeproj/project.pbxproj`. When `/tmp` is cleared between sessions the script is gone but easily recreated from the agents_log.md Session 20 or Session 16 entries.

---

## 5. Build commands

### Device build (signed, for physical iPhone 17 Pro)

```bash
xcodebuild \
  -project FitnessApp.xcodeproj \
  -scheme FitnessApp \
  -destination "id=6EBFD630-1768-512E-95E3-EC7D76AA8CDD" \
  DEVELOPMENT_TEAM=RM42FV53FU \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  build
```

The built `.app` lands in DerivedData. The path printed near the end of a successful build looks like:

```
/Users/tushar/Library/Developer/Xcode/DerivedData/FitnessApp-cgccfihxnploywdpzdyhwsixlfzh/Build/Products/Debug-iphoneos/FitnessApp.app
```

The DerivedData UUID segment varies; grep the build log or use:

```bash
find ~/Library/Developer/Xcode/DerivedData -name "FitnessApp.app" -path "*/Debug-iphoneos/*" | head -1
```

### Simulator fast compile-check (no signing, no device required)

```bash
xcodebuild \
  -project FitnessApp.xcodeproj \
  -scheme FitnessApp \
  -destination "platform=iOS Simulator,id=FF8921FE-10E6-4CAE-8722-D4BBD505DA98" \
  -configuration Debug \
  build
```

Use this for rapid compile verification before committing. It does not require the phone and is significantly faster than a device build.

---

## 6. Install and launch

### Install on physical device

```bash
xcrun devicectl device install app \
  --device "6EBFD630-1768-512E-95E3-EC7D76AA8CDD" \
  "<absolute-path-to>/FitnessApp.app"
```

The output includes `databaseSequenceNumber` — record it in `agents_log.md`.

### Launch on physical device

```bash
xcrun devicectl device process launch \
  --device "6EBFD630-1768-512E-95E3-EC7D76AA8CDD" \
  com.tushar.fitnessapp
```

### Simulator install and launch

```bash
# Install
xcrun simctl install FF8921FE-10E6-4CAE-8722-D4BBD505DA98 \
  "<absolute-path-to>/FitnessApp.app"

# Launch
xcrun simctl launch FF8921FE-10E6-4CAE-8722-D4BBD505DA98 com.tushar.fitnessapp
```

---

## 7. databaseSequenceNumber — tracking deploys

Every `xcrun devicectl device install app` call prints a `databaseSequenceNumber` in its output. This is a CoreDevice installation database counter maintained by the device. It is the canonical way to identify which build is installed on Tushar's iPhone.

**What to do with it:**

1. After every device install, copy the number from the terminal.
2. Log it in `agents_log.md` under the relevant session entry (e.g. `- **databaseSequenceNumber**: 2668`).
3. Append it to the git commit message when that commit corresponds to a deployed build.

The counter incremented through the app's history: `2436` → `2444` → … → `4077` → (device DB appeared to reset) → `2148` → … → `2668` (current as of the last recorded session). The absolute value is not meaningful; it just lets you confirm whether a particular code state has reached the device.

---

## 8. Troubleshooting

### "iPhone may need to be unlocked" during xcodebuild

The device build succeeds but the install step fails. Unlock the phone, then rerun the install command. Do not need to rebuild.

### Device shows as "unavailable"

The phone is asleep, disconnected, or mid-lock. Ensure it is unlocked and the USB cable (or wireless link) is active. If using Xcode's wireless device pairing, verify pairing has not expired. Retry the build/install command after the device is reachable.

### "Multiple commands produce '…/FitnessApp.app'"

This Xcode error means `project.pbxproj` or the build settings are malformed. The known cause is missing `PRODUCT_NAME` or `SWIFT_VERSION` in `project.yml` (see Section 3). Run `xcodegen --spec project.yml` to regenerate, or verify those keys are present in `project.yml` before filing another cause.

### Swift type-checker bails on a large @ViewBuilder switch

Swift's type-checker has a practical limit of around 15 cases per `@ViewBuilder` switch before compile times explode or the check fails entirely. Fix: extract a subset of cases into a private `@ViewBuilder` helper method. See `ToolCards.widgetToolCardBody` and the DashboardView 17-case split (Session 34) as precedents.

### ENOSPC — no disk space

The largest source of disk bloat is DerivedData. Purge it first:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

Do not touch `~/Library/Application Support/Claude/` without explicit user permission. That directory can hold gigabytes of VM bundles but belongs to the Claude agent runtime.

### "trust the profile" / provisioning errors

If xcodebuild exits with a provisioning-related error and the device is a first-time connection to this Mac, open Xcode, navigate to the Devices window, and trust the certificate on both the Mac and the iPhone. Rerun with `-allowProvisioningUpdates`.

### Token Verification: "thought_signature" 400 error from Vertex

Gemini 3.x (including `gemini-3.5-flash`) requires every `functionCall` part in the conversation history to carry a `thoughtSignature` blob. If you add new code paths that construct `functionCall` parts directly (bypassing the existing history serializer in `VertexGeminiClient`), every tool followup will return HTTP 400 INVALID_ARGUMENT. Always route new tool-call code through `ChatMessage.thoughtSignature` and the existing `VertexGeminiClient` history serializer.

---

## 9. Git safety protocol

Follow this sequence for every codebase change, in order.

### Step 1 — Secret scan (mandatory before staging)

Verify the Google Cloud credential stays out of git:

```bash
git check-ignore FitnessApp.swiftpm/FitnessApp/vertex-service-account.json
```

This must print the filename (meaning it is gitignored). The `.gitignore` patterns that cover credentials:

```
vertex-service-account.json
*service-account*.json
*.pem
*.p12
.env
.env.*
```

Never run `git add -f` on an ignored file.

After staging but before committing, scan the staged diff for secret material:

```bash
git diff --cached -- '*.swift' '*.json' '*.plist' \
  | grep -iE "PRIVATE KEY|private_key|AIza|MII[A-Za-z0-9+/]{40}"
```

This command must produce no output. Abort the commit if it matches anything.

Markers that indicate a leaked credential:
- `BEGIN ... PRIVATE KEY`
- `"private_key"` (JSON field)
- `AIza...` (Google API key prefix)
- Long `MII...` base64 blob (DER-encoded key material)

### Step 2 — Stage explicit paths

Prefer staging named files over `git add -A` or `git add .`:

```bash
git add FitnessApp.swiftpm/FitnessApp/Services/SomeService.swift agents_log.md
```

### Step 3 — Update agents_log.md

Update `agents_log.md` with what changed and (when applicable) the new `databaseSequenceNumber`. Stage the log file in the same commit as the code change it documents. Never create a log-only commit just to push it.

### Step 4 — Commit

Use Conventional Commits (`feat:` / `fix:` / `perf:` / `docs:`). Include the `databaseSequenceNumber` at the end of the message when the commit corresponds to a device deploy.

### Step 5 — Push

```bash
git push origin main
```

Push after every logical change. Do not batch unrelated changes into one commit.

---

## 10. Firm code conventions

These have been enforced since the beginning of the project. Violations have been explicitly rejected by the user on multiple occasions.

### iOS 26 native Liquid Glass — no fake glass

Every container that needs glass must use the native modifier:

```swift
.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
.glassEffect(.regular.interactive(), in: .circle)
.glassEffect(.regular.interactive(), in: .capsule)
```

The pattern `.background(...).overlay(Circle().stroke(...))` or any manual transparent layer is forbidden. If a fixer agent introduces fake glass, revert it.

Group multiple glass cards on the same screen under a `GlassEffectContainer` to coalesce backdrop passes (performance).

### No mock data

No seeded defaults, no placeholder numbers, no `setupDefaultData` functions. When HealthKit returns nothing, display `"—"` or `"No data yet"`. Every card initializes with zero values and populates from real fetches. This applies to WorkoutTrackerView, DetailedMetricView, and all other metric surfaces.

### Every clickable element must do something

No `Button(action: {})`. Audit with:

```bash
grep -rn "action: {}" FitnessApp.swiftpm/FitnessApp/
```

This must return zero hits.

### AI replies are brief and structured

Token cap is `2500 + thinkingBudget`. The system prompt enforces TAKEAWAY → sections → bullets → `Next:` action line. Do not remove or weaken the brevity constraints.

### Logged food carries is_estimate and confidence

Every `HealthKitManager.logFood(...)` call must pass `isEstimate: Bool` and `confidence: String?` ("low" / "medium" / "high"). HealthKit metadata keys `HKMetadataKeyWasUserEntered` and `FitnessGuruEstimateConfidence` must be written alongside the dietary samples.

### Gemini 3.5-flash via the global endpoint only

The model is `gemini-3.5-flash`. Every regional endpoint (`us-central1`, `us-east4`, any region) returns 404 for this model. The correct URL pattern:

```
https://aiplatform.googleapis.com/v1/projects/vertexi-ai-493516/locations/global/publishers/google/models/gemini-3.5-flash:streamGenerateContent
```

Both `VertexGeminiClient` and `PredictionAIService` use this form. Do not change the location string to a regional value.

### thinkingConfig placement

`thinkingConfig` must be nested inside `generationConfig`:

```json
{
  "generationConfig": {
    "maxOutputTokens": 3524,
    "thinkingConfig": {
      "thinkingBudget": 1024
    }
  }
}
```

Placing it at the top level of the request body causes HTTP 400 INVALID_ARGUMENT from Vertex. The budget token count comes from `VertexGeminiClient.thinkingBudgetTokens()`, which reads the `thinking_level` AppStorage key.

### Thought signatures round-trip on tool calls

Gemini 3.x emits a `thoughtSignature` alongside every `functionCall` part. The app stores it in `ChatMessage.thoughtSignature` and the `VertexGeminiClient` history serializer re-injects it on every followup turn. Any code path that builds a `functionCall` part manually (without going through the serializer) will cause all tool followup turns to fail with HTTP 400.

### Storage stays imperial; display converts via LocaleUnits

Internal storage and HealthKit reads use imperial units where applicable. Display conversion is handled at the view layer through locale-aware formatting, not stored as metric.

### App-scoped EventKit

The "Fitness Guru" calendar and reminder list are owned by the app and created lazily by `EventKitManager`. Astra and the app may only read and write items on those app-owned resources. `fetchEvents` and `fetchReminders` predicates are scoped to these collections; personal user events and reminders never appear in the app's UI.

### No clinical records at startup

Requesting HealthKit clinical records at launch triggers a repeating "Add provider account" system sheet. Clinical records are opt-in only, toggled by the user in Settings. The entitlement `com.apple.developer.healthkit.access = [health-records]` is present but the auth request is never fired automatically.

---

## 11. Multi-agent workflow norms

The app has been built by a series of orchestrated multi-agent workflows. These norms emerged from experience and are enforced to prevent build breaks and lost work.

### Frozen contracts before parallel implementation

When multiple agents implement different parts of the same feature, the orchestrator must define and freeze the shared API surface before dispatching agents. Agents receive the contract as part of their prompt and must not deviate from it. Example from Session 34:

```swift
func logMetricValue(type: HealthMetricType, value: Double, start: Date, end: Date) async -> Bool
```

All 10 parallel fixer agents were given this signature before any of them started editing.

### Agents edit files; the orchestrator builds, commits, and deploys

Subagents write Swift files and nothing else. They must not run `git`, `xcodebuild`, `xcrun`, or `xcodegen`. The orchestrator (the session doing the git commit) is the only actor that:

1. Runs `xcodegen --spec project.yml` or `register_pbx.py`
2. Runs `xcodebuild`
3. Runs `xcrun devicectl device install app`
4. Runs `git add` / `git commit` / `git push`
5. Records the new `databaseSequenceNumber`

This norm was codified after Session 32, where fixer agents auto-ran `git commit` and `git push`, pushing two compile-broken commits that required forward repairs.

### Disjoint file clusters

In parallel workflows, each agent is assigned a disjoint set of files. No two agents write the same file. The orchestrator verifies disjointness before dispatching.

### Review every diff before building

The orchestrator reviews each agent's diff against the frozen contract and the source before merging or building. Half-done edits (session-rate-limit kill in mid-edit) must be completed or reverted — never built in a partial state.

### Register new files before building

When an agent creates a new Swift file, the orchestrator runs `xcodegen --spec project.yml` (or `register_pbx.py`) to register it in the Xcode project before attempting a build. Forgetting this is a silent compile error: the file compiles only if it is already included via a directory glob; otherwise the symbols are undefined.

---

## 12. Outstanding action items

### Rotate GCP service account key

**Action required:** Rotate the Google Cloud service account key with ID starting `4d33d3bc…` for project `vertexi-ai-493516`.

Background: the credential file (`vertex-service-account.json`) existed in a local git commit before the first push to GitHub. The file was removed via `git commit --amend` before any push (Session 14) and fully purged from local git storage via `git gc --prune=now --aggressive` (Session 19). The remote has never contained the key. However, because the private key material existed in a local git object store (even if transiently), the key should be considered potentially exposed and rotated as a precaution.

Steps:
1. Open Google Cloud Console.
2. Navigate to IAM & Admin → Service Accounts.
3. Find the service account for project `vertexi-ai-493516`.
4. Delete the key with ID starting `4d33d3bc…`.
5. Create a new key (JSON format).
6. Save the new JSON to `FitnessApp.swiftpm/FitnessApp/vertex-service-account.json` on disk (gitignored).
7. Optionally paste the new JSON into Settings → AI Coach → Vertex AI config in the app UI (stored in UserDefaults `vertex_service_account_json`, takes precedence over the bundled file).

The file on disk is not tracked by git and will not be affected by any git operation. The `.gitignore` patterns (`vertex-service-account.json`, `*service-account*.json`) ensure it stays untracked permanently.

### Open functional items (as of last recorded session)

| Item | Status |
|---|---|
| Hydration logging: if the +-menu appears but water does not write, grant Water write permission in Settings > Health. If the +-menu does not appear at all, the hit-testing on the ZStack overlay in `HydrationCard` is the suspect. | Needs one unlocked-device observation |
| Dashboard workout-ring staleness: after saving a workout, `workoutDates` can lag up to 5 minutes (behind the 5-min gate on `refreshAllData`). Proposed fix: after workout save, call `refreshAllData()` directly or nil the `lastRefreshed` gate. | Deferred, low risk |
| On-device verification of WorkoutTrackerView Analytics and HR Zones sheets (fixed in Session 34 via `ActiveSheet` enum; code-green but unverified on device with a live workout). | Pending |
