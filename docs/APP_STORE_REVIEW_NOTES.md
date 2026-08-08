# App Store Review Notes — Astra: Your AI Coach

App: Astra: Your AI Coach (bundle `com.tushar.fitnessapp`, team `RM42FV53FU`)
Contact: team@atlasjob.tech
For: App Review — reviewer-facing notes for this submission. Written to accompany the
release build; every claim below is sourced from the shipped app source in
`FitnessApp.swiftpm/FitnessApp/`.

> **Note on names.** As of build **1.0.1 (4)** the names are aligned: the Store listing is
> **Astra: Your AI Coach**, the home-screen name (`CFBundleDisplayName`) is **Astra**, and the
> permission strings quoted below say **Astra**, quoted verbatim as they ship. "Fitness Guru"
> survives only as the internal project/repo name.

---

## 1. Background audio (`UIBackgroundModes: audio`) — overnight snore detection

**What it's for:** an opt-in sleep-tracking feature. When the user explicitly starts an
overnight tracking session, the app listens to the room and runs Apple's on-device
`SoundAnalysis` classifier (`SNClassifierIdentifier.version1`) to detect snoring. The
`audio` background mode exists solely so this classification can keep running while the
phone is asleep/screen-off overnight — that is the ordinary, intended use of the mode.

**Nothing is recorded or uploaded.** The microphone's PCM buffer is streamed straight into
`SNAudioStreamAnalyzer` and discarded; the app only ever keeps a `Double` confidence score
per ~1 s window (`Services/SnoreDetector.swift:148-151`), which is merged into snore
"episodes" (start/end timestamps + peak confidence, `SnoreDetector.swift:123-133`). No
audio file, buffer, or waveform is ever written to disk or sent anywhere — snore data
stays on-device in the session record.

**Lifecycle — active only during a user-initiated sleep session, torn down on stop:**

- The session starts only when the user taps "Track tonight" on the Home sleep card
  (`Views/Components/SleepTrackingCard.swift`, `onStartTracking`), which opens
  `SleepModeView` full-screen. `SleepModeView.onAppear` calls
  `SleepSessionManager.shared.start(...)` (`Views/SleepModeView.swift:106`).
- `SleepSessionManager.start()` calls `SnoreDetector.shared.start(...)`
  (`Services/SleepSessionManager.swift:78`), which is the **only** call site that activates
  `AVAudioSession` in the app (`Services/SnoreDetector.swift:49-52`,
  `.setCategory(.record, ...)` + `.setActive(true)`).
- The session ends only when the user taps "End sleep session" and confirms "End and see
  report" in the confirmation dialog (`Views/SleepModeView.swift:115-119`), which calls
  `SleepSessionManager.shared.stop()`.
- `SleepSessionManager.stop()` calls `SnoreDetector.shared.stop()`
  (`Services/SleepSessionManager.swift:101`), which removes the audio tap, stops the audio
  engine, and deactivates the session: `try? AVAudioSession.sharedInstance().setActive(false, ...)`
  (`Services/SnoreDetector.swift:89-99`).
- `SleepModeView` is a modal presented from `ContentView` (`activeModal == "sleep"`,
  `ContentView.swift:85-90`) with no swipe-to-dismiss; the confirmation dialog is the only
  UI path out of it, so there is no way to leave sleep tracking without going through
  `stop()`.
- `SnoreDetector.start()`/`stop()` are called from no other site in the codebase (verified
  by exhaustive search) — no app-launch, background-fetch, or scene-phase handler
  activates the microphone. `FitnessApp.swift`'s only `scenePhase` handler
  (`FitnessApp.swift:43-57`) drives an unrelated Focus-status poll
  (`SleepFocusDetector`), which never touches `AVAudioSession`.

**Net effect:** if the user never starts a sleep-tracking session, the app never opens an
audio session — backgrounding the app with no active session keeps the app idle like any
other app with no background modes in use. If a session is active and the app is
backgrounded, that is the feature working as designed (overnight tracking while the screen
is off); the session still ends exactly when the user taps "End sleep session" the next
morning, or when the app process terminates for any reason (in which case iOS itself tears
down the audio session with the process — no dangling state persists across launches).

**Toggle:** users can turn off the SoundAnalysis ML pipeline specifically (Home tab → sleep
card → "Snore detection" toggle, `Views/Components/SleepTrackingCard.swift:62` (label),
`:72` (`Toggle("", isOn: $snoreEnabled)`), `sleep_snore_enabled`) while still tracking
motion; the mic still opens in that mode purely to keep the process alive for accelerometer
sampling (`SnoreDetector.swift:38-41,77-82`) — audio is captured but never classified, and
the same start/stop lifecycle above applies unchanged.

Purpose string shown to the user at the OS permission prompt
(`NSMicrophoneUsageDescription`, `project.yml:63`): "Astra listens to the room while
you sleep to detect snoring and quantify sleep quality. Audio is analyzed on-device with
Apple's Sound Analysis framework and never recorded or uploaded."

---

## 2. HealthKit clinical records (`health-records` entitlement)

**What it's for:** Astra, the app's AI coach, personalizes fitness, food, and recovery
guidance around the user's real medical context — allergies, conditions, and medications —
so it can flag things like a food or activity that could conflict with a condition, instead
of giving generic advice that ignores it.

**Strictly opt-in, off by default.** Clinical records are never requested as part of the
standard HealthKit authorization sheet. They're requested only when the user explicitly
turns on "Health Records" in Settings, via
`HealthKitManager.requestClinicalRecordsAuthorization()` (`HealthKitManager.swift:293-313`),
which asks for `.allergyRecord`, `.conditionRecord`, `.immunizationRecord`,
`.labResultRecord`, `.medicationRecord`, `.procedureRecord`, `.vitalSignRecord` — read-only,
no write access. If the request is never made (or the user declines, or the region doesn't
support Health Records), the app has zero clinical data and behaves identically without it.

**How it's used:** when opted in, `ChatViewModel.buildSystemInstruction()`
(`ViewModels/ChatViewModel.swift:1934`) reads the records via
`HealthKitManager.readClinicalRecords()` (`ChatViewModel.swift:1992`) and folds
allergy/condition/medication summaries into Astra's system prompt for that turn only, with
an explicit instruction to the model to treat them as safety gatekeepers and defer to a
doctor for anything clinically significant (`ChatViewModel.swift:1998`).
The relevant HealthKit constants for these fields live at `HealthKitManager.swift:298-299`
per the read APIs above.

**Never stored server-side.** Every AI request goes to the Atlas AI Gateway
(`Services/Gateway/`, `Services/GatewayChatClient.swift`) over HTTPS, authenticated with a
bearer token from the user's gateway session (Sign in with Apple or email/password) — the app
holds no Google/Vertex credentials directly.
The gateway is a stateless per-request pass-through to the underlying model: it uses the
health/clinical context only to generate that one reply and discards it immediately
afterward — nothing is persisted, logged, or used for training. This is the same promise
shown to the user before they ever sign in (`Views/LoginView.swift:260`): "Your chat
messages and health context are sent to our AI gateway only to generate that reply, and are
never stored on our servers," and restated in the in-app Privacy Policy
(`Services/Legal/LegalTexts.swift:44`): "The Gateway is a stateless pass-through: your
health and chat content lives in server memory for only as long as it takes to generate a
reply, and then it's discarded." Account-level metering on the gateway (token counts, for
the in-app usage dashboard) is metadata-only and does not include health content.

Purpose string shown to the user (`NSHealthClinicalHealthRecordsShareUsageDescription`,
`project.yml:55`): "Astra can read your clinical records (allergies, conditions, lab
results) to give the AI coach a complete picture of your health context."

---

## 3. Signing in — Sign in with Apple, email/password, and how to test

The app offers two native sign-in / account-creation paths — there is no third-party or
social login of any kind: **Sign in with Apple**
(`com.apple.developer.applesignin` in `FitnessApp.swiftpm/FitnessApp.entitlements`; UI in
`Views/LoginView.swift`, `AppleSignInCoordinator`), and **email/password**
(`Views/LoginView.swift:183-239`, mirrored in onboarding at
`Views/Onboarding/OnboardingScreens.swift`). Guideline 4.8's requirement to offer Sign in
with Apple wherever a third-party/social login exists doesn't strictly apply here — there's
no third-party login to begin with — but Apple sign-in is offered as a full first-class
option regardless.

For Sign in with Apple, sign-up and sign-in are the same flow: the first successful Apple
identity-token exchange (`POST /v1/auth/apple` against the Atlas AI Gateway,
`Services/Gateway/GatewayAuth.swift:135-140`) both creates and authenticates the gateway
account, with no separate registration step. Email/password is a distinct two-mode flow
instead: a segmented control switches between "Sign In" (`POST /v1/auth/login`) and "Create
Account" (8-character minimum password, `POST /v1/auth/register`;
`Services/Gateway/GatewayAuth.swift:147-160`, `LoginView.swift:48-51,184-187`); a "Forgot
password?" link drives an email-code reset via `POST /v1/auth/reset-password`
(`Services/Gateway/GatewayAuth.swift:164-170`, `ForgotPasswordView.swift`).

**To test:**
1. Fresh install → launch → complete onboarding (HealthKit permission prompts are part of
   onboarding, not login).
2. The app presents the sign-in screen. Either (a) tap "Continue with Apple"
   (`LoginView.swift:147-165`) and complete Apple's native authorization sheet, or (b) fill
   in "Create Account" with any email address and an 8+ character password
   (`LoginView.swift:183-226`) — both are real, independent paths to a working session.
3. On success the app exchanges the credential with the gateway and lands on the main tab
   bar. Open the "Coach" tab to chat with Astra, the AI coach.
4. A "Continue without AI coach" option is also present on the sign-in screen
   (`LoginView.swift:279-291`) — HealthKit dashboard, sleep tracking, workout tracking, and
   reminders all work without signing in; only the AI coach (chat, meal-photo recognition,
   AI-generated insights) requires a gateway session.
5. To remove a test account afterward: Settings → "Delete account" (shown only while signed
   into a gateway session, per guideline 5.1.1(v); `SettingsView.swift:437-445`) → confirm
   "Delete Account" in the dialog (`SettingsView.swift:178-185`) → this calls
   `DELETE /v1/account`, which permanently deletes the gateway account, its sessions, and
   its usage records (`Services/Gateway/GatewayAuth.swift:208-221`, function body
   `SettingsView.swift:577-587`).

**Backend status:** the Atlas AI Gateway's production deployment on Azure has been live
since 2026-07-21 and is the default backend for every build configuration — Debug and
Release alike. There is no pending deployment and no `DEBUG`-only gate on it.
`GatewayConfig.baseURL` (`Services/Gateway/GatewayConfig.swift:25-34`) always resolves to a
URL: it checks for a user-set override in Settings first, and otherwise falls back to the
hardcoded production endpoint, `https://atlas-gw-tushar.denmarkeast.cloudapp.azure.com`
(`Services/Gateway/GatewayConfig.swift:33`) — it is never `nil` in ordinary use, so Astra
should simply work during review with no configuration steps needed. Every other feature
(HealthKit dashboard, HealthKit-backed sleep/workout tracking, reminders, calendar) is fully
functional independent of the gateway regardless.

Privacy Policy and Terms of Service are linked directly on the sign-in screen (opened
in-app via `LegalDocumentSheet`, buttons at `Views/LoginView.swift:302-313`, sheets at
`:331-336`) and are also submitted as the App Store Connect privacy policy / terms URLs.

---

## 4. Not medical advice

Astra is positioned throughout the app as general fitness and wellness information, not
medical advice, diagnosis, or treatment:

- The in-app Privacy Policy carries an explicit medical disclaimer:
  "Astra provides general fitness and wellness information for personal use. It is not a
  medical device and does not provide medical advice, diagnosis, or treatment, and is not a
  substitute for professional medical care. Always talk to a qualified healthcare provider
  about your health, especially before making decisions related to any condition,
  medication, or symptom Astra discusses with you. If you are experiencing a medical
  emergency, call your local emergency number immediately." (`Services/Legal/LegalTexts.swift:74`).
  The Terms of Service carry an equivalent disclaimer in its own wording:
  "Astra is for general fitness and wellness information only. Nothing in the app is
  medical advice, diagnosis, or treatment, and the app is not a substitute for a qualified
  healthcare professional. Always consult a doctor or other qualified provider before
  acting on anything Astra tells you, especially anything related to a medical condition,
  medication, symptom, or injury. If you are having a medical emergency, call your local
  emergency number (for example, 911 in the US) immediately — do not rely on this app."
  (`Services/Legal/LegalTexts.swift:100`).
- Astra's own system prompt carries a standing instruction never to diagnose and to direct
  the user to a clinician for anything persistent or severe, both for HealthKit-derived
  "early warning" signals (`ViewModels/ChatViewModel.swift:897`, `:1147`) and for
  clinical-record-gated advice (`ChatViewModel.swift:1998`), plus an explicit one-line
  disclaimer the model is instructed to surface whenever its advice turns
  clinical/diagnostic: "I'm not a medical professional — confirm with your doctor."
  (`ChatViewModel.swift:2289`).

No part of the app claims to detect, diagnose, or treat any medical condition. Sleep
tracking (including snore detection) and HealthKit-derived "illness early-warning" signals
are explicitly framed as wellness/informational signals, not diagnoses.
