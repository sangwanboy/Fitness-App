# Handoff: Fitness Guru → App Store ready (SIWA entitlement + privacy manifest + release hardening)

> Written 2026-07-17 by the Atlas AI Gateway orchestrator session (backend repo:
> `~/Multi App Ai Backend`). Read alongside this repo's `CLAUDE.md` and the tail
> of `agents_log.md`; log your session there per repo protocol.
>
> **SCOPE — this repo (`~/projects/Fitness App`) only.** Do NOT edit the
> backend repo (`~/Multi App Ai Backend`) or the Cookery repo (`~/CokkeryDev`)
> — each has its own agent and handoff. Where an item below depends on backend
> work (production URL, `DELETE /v1/account`, key-rotation coordination on the
> gateway side), treat it as an external dependency: note it as blocked in
> `agents_log.md` and move on — don't build it yourself. Exception: if you
> *move* `vertex-service-account.json` out of this tree (item 4), updating the
> path in the backend's `.claude/launch.json` is allowed — that one line only.

## Where things stand (verified 2026-07-17)

The **Atlas Gateway migration is done** (commit `06ff4dc`) — do not redo it.
`Services/GatewayChatClient.swift` + `Services/Gateway/*` front all AI calls;
no direct Google/Vertex call remains in Swift. The full acceptance path was
live-tested against the real backend today: streaming `/v1/chat` on
`gemini-3.5-flash` → `functionCall` emitted with a `thoughtSignature` →
on-device tool result → follow-up with the signature echoed → final coached
reply, token-exact metering. The 25-tool loop design is sound server-side.

Sign in with Apple **UI code also already exists** (`Views/LoginView.swift`,
`AppleSignInCoordinator` at :220; DEBUG uses `GatewayAuth.signInDev()` fake
auth, Release uses the real ASAuthorization flow). What blocks release is the
list below.

## Mission, in priority order

### 1. Make release auth actually work
- Add `com.apple.developer.applesignin` to `FitnessApp.swiftpm/FitnessApp.entitlements`
  (currently HealthKit-only; `LoginView.swift:216-218` says the entitlement was
  deliberately deferred). Enable the capability for `com.tushar.fitnessapp`
  (team `RM42FV53FU`) and regenerate provisioning.
- Fix the first-run gate: `ContentView.swift:8` has
  `@AppStorage("is_logged_in") = true` — fresh installs skip `LoginView`
  entirely, so no gateway session is ever created and every AI call throws
  `.notSignedIn`. Default must be `false` (handle migration for existing
  installs).

#### Account screens — App Store guideline requirements
With Sign in with Apple, sign-up and sign-in are the **same flow** — the first
`/v1/auth/apple` exchange creates the gateway account. `LoginView` exists;
bring it up to guideline level:
- **Sign-up copy (guideline 5.1.1(i))**: on `LoginView`, explain what the
  account is for and that chat/health data is processed per-request and **never
  stored** server-side; add visible **privacy policy** and **terms** links
  (both URLs are also mandatory in App Store Connect — given clinical-records
  access, the privacy policy must explicitly cover health data).
- **SIWA-only login is compliant** with guideline 4.8; don't add social logins
  without keeping SIWA equal-footing.
- **Account deletion (guideline 5.1.1(v)) — REQUIRED, currently impossible:**
  in-app "Delete account" (Settings/Profile) behind a confirmation, and Apple
  requires SIWA apps to **revoke the Apple token** on deletion
  (`appleid.apple.com/auth/revoke`). ✅ The gateway endpoint **exists and is
  live-verified** (2026-07-17): `DELETE /v1/account`, bearer-authenticated, no
  body, returns `204` — deletes the user + all sessions + feedback and unlinks
  usage (health data is never stored server-side to begin with); see backend
  `docs/API.md` §3.8. After a 204, clear the Keychain token pair and flip the
  login gate. ⚠️ Still outstanding **server-side**: Apple's own token
  revocation (needs the team's SIWA .p8 key on the gateway) — external
  dependency, not yours to build.
- **Sign-out** should exist wherever the account surface lives, clearing the
  Keychain token pair (`KeychainStore`) and flipping the login gate.

### 2. Privacy manifest — missing entirely (high risk with clinical data)
There is **no `PrivacyInfo.xcprivacy` anywhere** in this repo. This app reads
HealthKit **including clinical records** (allergies, conditions, medications —
`HealthKitManager.swift:224/:238`) and injects them plus cycle, symptoms, and
body metrics into the chat system prompt every turn
(`ChatViewModel.buildSystemInstruction()` :1362, clinical at :1420). Create the
privacy manifest (health data types, required-reason APIs like UserDefaults),
and make App Store privacy labels + `docs/DATA_AND_PRIVACY.md` state plainly:
health data is sent per-request to the Atlas Gateway for AI processing and is
**never stored there** — the gateway is a stateless pass-through; metering is
metadata-only (backend `docs/SPEC.md`, CLAUDE.md rule 1). Expect review to
scrutinize the `health-records` entitlement — prepare the justification.

### 3. Production gateway URL
`Services/Gateway/GatewayConfig.swift` — DEBUG hardcodes LAN IP
`http://10.130.154.45:8787` (:35), **Release returns `nil`** (:37): an App
Store build has no backend. The Azure VM deployment (ADR-007) hasn't happened
yet — coordinate with the backend repo; wire the https prod URL when it exists
and keep it out of DEBUG. ATS is already narrow (`NSAllowsLocalNetworking`
only) — prod must be https so no new exceptions are needed.

### 4. Credential hygiene (before any public build)
`FitnessApp.swiftpm/FitnessApp/vertex-service-account.json` is a **real GCP
private key** (project `vertexi-ai-493516`) sitting in the working tree.
Today it's gitignored and bundle-excluded (`project.yml:12-13`) and only feeds
the local dev gateway — but repo CLAUDE.md itself says rotation was deferred
and must be revisited before release. Move it out of the app source tree
(the backend reads it via `GCP_SA_JSON_FILE` — any path works; update the
backend's `.claude/launch.json` if you move it), then **rotate the key in GCP**
and treat the old one as burned.

### 5. Remaining compliance punch list
- App icon: `Assets.xcassets/AppIcon.appiconset/icon.png` is **JPEG data with a
  .png extension** — re-export as real PNG (1024², no alpha).
- `UIBackgroundModes: [audio]` (snore detection) — commonly challenged in
  review; write the reviewer note justifying it and make sure the audio session
  only runs during sleep tracking.
- Version is 1.0 (1) — bump for submission.
- Usage-description strings are already complete (all three HealthKit strings,
  Calendar, Reminders, Camera, Photos, Notifications, Microphone, Focus) — keep
  them in `project.yml` (source of truth), regenerate with XcodeGen.

## Gateway contract — what this client must keep honoring

(Current code already does all of this — listed so nobody regresses it.)

- App identity comes **only** from the Apple identity token's bundle ID at
  `POST /v1/auth/apple`; `/v1/*` calls carry only `Authorization: Bearer`.
- `POST /v1/auth/refresh` rotates both tokens; reuse of an old refresh token
  revokes the family → on refresh 401, force a fresh Sign in with Apple.
- `model` stays the logical `"chat"` (`GatewayConfig.chatModel`) — concrete
  Gemini models are switched globally from the gateway dashboard; never
  hardcode a Gemini id (the "gemini-3.5-flash" string in `TokenUsageView.swift:238`
  is display copy — update it if the server model map changes, or better,
  derive from `/v1/usage`'s `byModel`).
- Strict request part shapes: `{text}` / `{image:{mimeType,data}}` (never
  `inlineData` in requests) / `{functionCall}` / `{functionResponse}`, with
  `thoughtSignature` as a **part-level sibling** — echoed back byte-exact on
  follow-ups (`GatewayChatPayload.swift:31-41`, `GatewayChatClient.swift:441-475`
  already do this; Vertex 400s without it). Never "clean" history.
- SSE events are **CRLF-delimited** (`\r\n\r\n`) — current parser copes; keep it.
- On 429 (`rate_limited`/`quota_exceeded`) back off `retryAfterMs`; 403
  `forbidden_capability` is not retryable; 502/503 are upstream/ops.
- Tool calls are pure passthrough — the gateway never executes tools; all 25
  run on-device. Follow-up turns re-send tools + history + `functionResponse`.

## Definition of done
Release-configuration build on a physical device: fresh install → real Sign in
with Apple → Astra chat with HealthKit-backed tool calls (multi-turn, signature
round-trip) against the deployed gateway → privacy manifest + labels accurate →
GCP key rotated out of the tree → archive validates clean. This app's tool loop
is the gateway's passthrough acceptance test — run it on-device before
submission and note the result in `agents_log.md`.
