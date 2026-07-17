# App Store Review Notes — Fitness Guru

App: Fitness Guru (bundle `com.tushar.fitnessapp`, team `RM42FV53FU`)
Contact: team@atlasjob.tech
For: App Review — reviewer-facing notes for this submission. Written to accompany the
release build; every claim below is sourced from the shipped app source in
`FitnessApp.swiftpm/FitnessApp/`.

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
  (`FitnessApp.swift:18-24`) drives an unrelated Focus-status poll
  (`SleepFocusDetector`), which never touches `AVAudioSession`.

**Net effect:** if the user never starts a sleep-tracking session, the app never opens an
audio session — backgrounding the app with no active session keeps the app idle like any
other app with no background modes in use. If a session is active and the app is
backgrounded, that is the feature working as designed (overnight tracking while the screen
is off); the session still ends exactly when the user taps "End sleep session" the next
morning, or when the app process terminates for any reason (in which case iOS itself tears
down the audio session with the process — no dangling state persists across launches).

**Toggle:** users can turn off the SoundAnalysis ML pipeline specifically (`Settings →
Snore detection` toggle, `sleep_snore_enabled`) while still tracking motion; the mic still
opens in that mode purely to keep the process alive for accelerometer sampling
(`SnoreDetector.swift:38-41,77-82`) — audio is captured but never classified, and the same
start/stop lifecycle above applies unchanged.

Purpose string shown to the user at the OS permission prompt
(`NSMicrophoneUsageDescription`, `project.yml:48`): "Fitness Guru listens to the room while
you sleep to detect snoring and quantify sleep quality. Audio is analyzed on-device with
Apple's Sound Analysis framework and never recorded or uploaded."

---

## 2. HealthKit clinical records (`health-records` entitlement)

**What it's for:** Fitness Guru's AI coach, Astra, personalizes fitness, food, and recovery
guidance around the user's real medical context — allergies, conditions, and medications —
so it can flag things like a food or activity that could conflict with a condition, instead
of giving generic advice that ignores it.

**Strictly opt-in, off by default.** Clinical records are never requested as part of the
standard HealthKit authorization sheet. They're requested only when the user explicitly
turns on "Health Records" in Settings, via
`HealthKitManager.requestClinicalRecordsAuthorization()` (`HealthKitManager.swift:224-241`),
which asks for `.allergyRecord`, `.conditionRecord`, `.immunizationRecord`,
`.labResultRecord`, `.medicationRecord`, `.procedureRecord`, `.vitalSignRecord` — read-only,
no write access. If the request is never made (or the user declines, or the region doesn't
support Health Records), the app has zero clinical data and behaves identically without it.

**How it's used:** when opted in, `ChatViewModel.buildSystemInstruction()` reads the
records via `HealthKitManager.readClinicalRecords()` and folds allergy/condition/medication
summaries into Astra's system prompt for that turn only
(`ViewModels/ChatViewModel.swift:1420-1426`), with an explicit instruction to the model to
treat them as safety gatekeepers and defer to a doctor for anything clinically significant.
The relevant HealthKit constants for these fields live at `HealthKitManager.swift:224` /
`:238` per the read APIs above.

**Never stored server-side.** Every AI request goes to the Atlas AI Gateway
(`Services/Gateway/`, `Services/GatewayChatClient.swift`) over HTTPS, authenticated with a
bearer token from Sign in with Apple — the app holds no Google/Vertex credentials directly.
The gateway is a stateless per-request pass-through to the underlying model: it uses the
health/clinical context only to generate that one reply and discards it immediately
afterward — nothing is persisted, logged, or used for training. This is the same promise
shown to the user before they ever sign in (`Views/LoginView.swift:144`): "Your chat
messages and health context are sent to our AI gateway only to generate that reply, and are
never stored on our servers," and restated in the in-app Privacy Policy
(`Services/Legal/LegalTexts.swift:44`): "The Gateway is a stateless pass-through: your
health and chat content lives in server memory for only as long as it takes to generate a
reply, and then it's discarded." Account-level metering on the gateway (token counts, for
the in-app usage dashboard) is metadata-only and does not include health content.

Purpose string shown to the user (`NSHealthClinicalHealthRecordsShareUsageDescription`,
`project.yml:40`): "Fitness Guru can read your clinical records (allergies, conditions, lab
results) to give the AI coach a complete picture of your health context."

---

## 3. Sign in with Apple — the only login, and how to test

Sign in with Apple is the app's sole account-creation and sign-in method
(`com.apple.developer.applesignin` in `FitnessApp.swiftpm/FitnessApp.entitlements`; UI in
`Views/LoginView.swift`, `AppleSignInCoordinator`). There are no other social logins and no
email/password path, consistent with guideline 4.8. Sign-up and sign-in are the same
flow — the first successful Apple identity-token exchange
(`POST /v1/auth/apple` against the Atlas AI Gateway) both creates and authenticates the
gateway account; there is no separate registration step.

**To test:**
1. Fresh install → launch → complete onboarding (HealthKit permission prompts are part of
   onboarding, not login).
2. The app presents the Sign in with Apple screen. Tap "Sign in with Apple" and complete
   Apple's native authorization sheet.
3. On success the app exchanges the Apple identity token with the gateway and lands on the
   main tab bar. Open the "Coach" tab to chat with Astra, the AI coach.
4. A "Continue without AI coach" option is also present on the sign-in screen — HealthKit
   dashboard, sleep tracking, workout tracking, and reminders all work without signing in;
   only the AI coach (chat, meal-photo recognition, AI-generated insights) requires a
   gateway session.

**Dependency reviewers should know about:** Astra (the AI coach) requires the app to reach
the Atlas AI Gateway backend. As of this submission the gateway's production HTTPS
deployment (Azure) is still pending — see `Services/Gateway/GatewayConfig.swift`, which
resolves no backend URL in a Release build until that deployment lands
(`GatewayConfig.baseURL` returns `nil` outside `DEBUG`). If AI chat is unreachable during
review, the app fails honestly with a "AI backend not configured" style error rather than
faking a response or crashing — every other feature (HealthKit dashboard, HealthKit-backed
sleep/workout tracking, reminders, calendar) is fully functional independent of the
gateway. We will ensure the production gateway URL is wired into the Release configuration
before this build is submitted for review.

Privacy Policy and Terms of Service are linked directly on the sign-in screen (opened
in-app via `LegalDocumentSheet`, `Views/LoginView.swift:187-195`) and are also submitted as
the App Store Connect privacy policy / terms URLs.

---

## 4. Not medical advice

Fitness Guru and Astra are positioned throughout the app as general fitness and wellness
information, not medical advice, diagnosis, or treatment:

- The in-app Privacy Policy and Terms of Service both carry an explicit medical disclaimer:
  "Fitness Guru and Astra provide general fitness and wellness information for personal
  use. They are not a medical device and do not provide medical advice, diagnosis, or
  treatment, and are not a substitute for professional medical care. Always talk to a
  qualified healthcare provider about your health... If you are experiencing a medical
  emergency, call your local emergency number immediately."
  (`Services/Legal/LegalTexts.swift:70`, restated at `:96`).
- Astra's own system prompt carries a standing instruction never to diagnose and to direct
  the user to a clinician for anything persistent or severe, both for HealthKit-derived
  "early warning" signals (`ViewModels/ChatViewModel.swift:685`, `:905`) and for
  clinical-record-gated advice (`ChatViewModel.swift:1426`), plus an explicit one-line
  disclaimer the model is instructed to surface whenever its advice turns
  clinical/diagnostic: "I'm not a medical professional — confirm with your doctor."
  (`ChatViewModel.swift:1595`).

No part of the app claims to detect, diagnose, or treat any medical condition. Sleep
tracking (including snore detection) and HealthKit-derived "illness early-warning" signals
are explicitly framed as wellness/informational signals, not diagnoses.
