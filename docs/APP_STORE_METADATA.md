# App Store Connect — submission pack (Astra: Your AI Coach 1.0.1)

> Everything below is paste-ready for App Store Connect. URLs assume the legal
> site at `https://sangwanboy.github.io/Fitness-App/` (served from this repo's docs/ via GitHub Pages).
>
> **Naming (updated 2026-08-08):** the Store name is **Astra: Your AI Coach**, NOT "Fitness
> Guru" — that name was already taken on the Store, so the ASC record was created in Session 81
> and the description body re-branded to match. The home-screen name is **Astra**. "Fitness
> Guru" survives only as the internal project name (CLAUDE.md, repo, docs titles). Do not paste
> "Fitness Guru" into any ASC field. See the naming-consistency note under **## Build**.

## App record
- **Name:** Astra: Your AI Coach  *(“Fitness Guru” unavailable on the Store)*
- **Subtitle** (30 chars): `AI coach for your health data`
- **Bundle ID:** com.tushar.fitnessapp · **SKU:** fitness-guru-001
- **Primary category:** Health & Fitness · **Secondary:** Lifestyle
- **Price:** Free · **Availability:** United Kingdom only (base country UK/GBP; widen any
  time without a version bump)

## URLs
- **Support URL:** https://sangwanboy.github.io/Fitness-App/
- **Marketing URL:** (same, optional)
- **Privacy Policy URL:** https://sangwanboy.github.io/Fitness-App/privacy.html
- **Terms (EULA):** standard Apple EULA + in-app terms; link https://sangwanboy.github.io/Fitness-App/terms.html

## Promotional text (170 chars)
Astra reads your real Apple Health data and coaches you like it knows you — because it does. Morning briefs, training plans, honest insights. Nothing stored server-side.

## Description
Astra: Your AI Coach puts an AI coach — Astra — on top of your real Apple Health data.

ASTRA KNOWS YOUR NUMBERS
Chat about your sleep, heart rate, workouts, nutrition, and trends. Astra answers from YOUR data — never generic advice — and remembers what matters: your goals, injuries, and preferences (visible and editable any time).

A PLAN THAT ADAPTS
Ask for a weekly training plan and get one built around your goals and recovery state, synced to your calendar, with full exercise prescriptions. Mark sessions done and watch adherence feed next week's plan.

PROACTIVE, NOT NOSY
A morning brief written for your day. An early heads-up when resting heart rate, HRV, and sleep drift together. A nudge before your streak breaks. Every notification is built from your real data and every type can be switched off.

LOG FOOD IN SECONDS
Snap a photo or scan a barcode — calories and macros estimated honestly, always labeled as estimates.

SLEEP, TRACKED ON DEVICE
Overnight sleep tracking with snore detection analyzed entirely on your iPhone. Audio is never recorded or uploaded.

PRIVACY BY ARCHITECTURE
Your health context is processed per-request to generate Astra's replies and is never stored on our servers. Metering is metadata-only. Sign in with Apple or email; delete your account in-app any time.

Astra is not a medical device and does not provide medical advice.

## Keywords (100 chars)
`ai coach,fitness,health,workout plan,nutrition,sleep tracker,hrv,recovery,macros,training`

## Age rating questionnaire — answers
- Unrestricted web access: **No** · Gambling/contests: **No** · Violence/mature themes: **None**
- Medical/Treatment Information: **Infrequent/Mild** (health insights, not-medical-advice disclaimed)
- → Expected rating: **12+** (medical/treatment info) — accept whatever ASC computes.

## App Privacy labels (from docs/DATA_AND_PRIVACY.md §12, cross-checked against
`FitnessApp.swiftpm/FitnessApp/PrivacyInfo.xcprivacy` — the manifest is the binding
artifact and this section must not contradict it; re-verify both before submitting since
either can change independently of this doc)
Data collected (linked to you, NOT used for tracking, purpose App Functionality unless noted):
1. **Identifiers → User ID** (gateway account identifier, assigned on registration via
   either Sign in with Apple or email/password — not solely an Apple `sub`)
2. **Contact Info → Email Address** — collected two ways: (a) from Sign in with Apple, only
   when Apple discloses it on first authorization, or (b) submitted directly by the user at
   signup for email/password accounts (`Views/LoginView.swift:184-238`,
   `Services/Gateway/GatewayAuth.swift` → `v1/auth/register`) — App Functionality + Marketing
   (only for users who explicitly opt in)
3. **Contact Info → Name** — collected from Sign in with Apple's `.fullName` scope
   (`AppleSignInCoordinator`, `Views/LoginView.swift:443`), disclosed only on the first
   authorization for a given Apple ID. When present, `persistAppleSignInResult()` saves it
   locally and `Services/Gateway/GatewayProfileSync.swift` POSTs it to `v1/me/profile`, which
   retains it in the gateway's per-user account record — the same transmitted-and-retained
   pattern as Email above, so it meets Apple's "collected" definition — App Functionality +
   Marketing (only for users who explicitly opt in). `PrivacyInfo.xcprivacy` declares
   `NSPrivacyCollectedDataTypeName` (linked, not used for tracking, App Functionality) to match.
4. **Usage Data → Other Usage Data** (request/token metering, metadata only)
Do NOT declare Health & Fitness as "collected": health data is transmitted per-request and never retained (Apple's definition of collect = retained). Fallback if review pushes back: add Health & Fitness / linked / App Functionality.
- "Data is encrypted in transit": yes (TLS). · "You can request deletion": yes (in-app).

## Review notes (paste from docs/APP_STORE_REVIEW_NOTES.md)
Covers: background-audio justification (2.5.4), clinical-records entitlement rationale,
sign-in (Sign in with Apple with any Apple ID, or email/password — no third-party/social
login of any kind; production backend is live), not-medical-advice positioning.

## Build
- **Submit 1.0.1 (4)** — cut specifically to fix the three-way name inconsistency below
  (`CFBundleDisplayName: "Astra"` + all `*UsageDescription` strings re-worded to lead with
  "Astra"). Release config → production gateway (live).
  `ITSAppUsesNonExemptEncryption=false` set, so the export-compliance question is skipped.
- Do NOT submit 1.0.1 (3): it is `APP_STORE_ELIGIBLE`/`VALID` and passed Beta App Review, but it
  carries the old three-way name mismatch (listing "Astra AI Coach" / home screen "FitnessApp" /
  permission dialogs "Fitness Guru") — that is exactly what build 4 exists to fix.
- Do NOT submit 1.0.1 (2): `buildAudienceType: INTERNAL_ONLY` is permanent per-build and makes it
  structurally ineligible for review.
- Upload: Xcode Organizer → Distribute App → App Store Connect (or ASC API key for CLI). CLI
  `-exportArchive` upload does **not** work on this Mac — Xcode has no Apple ID in Accounts, so
  it fails with "Failed to find an account with App Store Connect access for team RM42FV53FU".

### ✅ Three-way name mismatch — fixed in build 4 (raised 2026-08-08, guideline 2.3.7)
Through build 3 the app presented **three different names**, which a reviewer would have seen
all at once. Build 4 aligns them — this part is a verified fact, not a judgment call:

| Surface | Was (build 3) | Now (build 4) |
|---|---|---|
| Store listing | Astra AI Coach | **Astra: Your AI Coach** (ASC record) |
| Home-screen icon | **FitnessApp** (`CFBundleName`/`PRODUCT_NAME`, no `CFBundleDisplayName` set) | **Astra** (`CFBundleDisplayName`) |
| Every permission dialog | **Fitness Guru** | **Astra** (the 13 `*UsageDescription` strings) |

`docs/APP_STORE_REVIEW_NOTES.md` §1/§2 quote those permission strings verbatim and were updated
in the same pass. Separately — and this part is our judgment about Apple's review behavior,
not a verified fact — we expect the home-screen name "Astra" being a prefix of the listing
name "Astra: Your AI Coach" to read as the standard, accepted App Store pattern (long listing
name, short icon label), so we don't expect it to draw a 2.3.7 objection on its own. That is a
reasoned expectation based on common App Store practice, not a guarantee; if a reviewer flags
it anyway, be ready to explain the naming rationale rather than treat it as pre-cleared.

## Submission-day sequence
1. ~~Accept agreements (ASC → Business)~~ — **done**.
2. ~~Create app record~~ — **done** (Session 81, created as "Astra AI Coach"; the listing name is
   now **Astra: Your AI Coach** — update the Name field in ASC if it still reads the old name).
3. Privacy labels (§ above) — **status unverified**, confirm before submitting.
4. Upload build — **1.0.1 (4) still to upload** via Xcode Organizer (see upload note above).
   1.0.1 (3) is already uploaded and VALID but must not be submitted.
5. Attach build + screenshots + metadata — **screenshots status unverified**; App Store requires
   at least one 6.9" iPhone set (1320×2868). Real-device captures are ideal: the app shows honest
   empty states with no HealthKit data, so simulator captures would look bare.
6. ~~TestFlight round~~ — **done**, both internal and external (external implies a passed Beta
   App Review).
7. Submit for review, pasting `docs/APP_STORE_REVIEW_NOTES.md` into the review-notes field.
