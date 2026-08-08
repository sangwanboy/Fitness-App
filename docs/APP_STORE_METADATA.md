# App Store Connect — submission pack (Astra AI Coach 1.0.1)

> Everything below is paste-ready for App Store Connect. URLs assume the legal
> site at `https://sangwanboy.github.io/Fitness-App/` (served from this repo's docs/ via GitHub Pages).
>
> **Naming (updated 2026-08-08):** the Store name is **Astra AI Coach**, NOT "Fitness Guru" —
> that name was already taken on the Store, so the ASC record was created as Astra AI Coach in
> Session 81 and the description body re-branded to match. "Fitness Guru" survives only as the
> internal project name (CLAUDE.md, repo, docs titles). Do not paste "Fitness Guru" into any
> ASC field. See the naming-consistency warning under **## Build** before submitting.

## App record
- **Name:** Astra AI Coach  *(“Fitness Guru” unavailable on the Store)*
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
Astra AI Coach puts an AI coach — Astra — on top of your real Apple Health data.

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
Your health context is processed per-request to generate Astra's replies and is never stored on our servers. Metering is metadata-only. Sign in with Apple; delete your account in-app any time.

Astra AI Coach is not a medical device and does not provide medical advice.

## Keywords (100 chars)
`ai coach,fitness,health,workout plan,nutrition,sleep tracker,hrv,recovery,macros,training`

## Age rating questionnaire — answers
- Unrestricted web access: **No** · Gambling/contests: **No** · Violence/mature themes: **None**
- Medical/Treatment Information: **Infrequent/Mild** (health insights, not-medical-advice disclaimed)
- → Expected rating: **12+** (medical/treatment info) — accept whatever ASC computes.

## App Privacy labels (from docs/DATA_AND_PRIVACY.md §12)
Data collected (linked to you, NOT used for tracking, purpose App Functionality unless noted):
1. **Identifiers → User ID** (gateway account from Sign in with Apple `sub`)
2. **Contact Info → Name** (from Sign in with Apple, only when Apple discloses it) — App Functionality + Marketing (only for users who explicitly opt in)
3. **Contact Info → Email Address** (from Sign in with Apple, only when Apple discloses it) — App Functionality + Marketing (only for users who explicitly opt in)
4. **Usage Data → Product Interaction** (request/token metering, metadata only)
Do NOT declare Health & Fitness as "collected": health data is transmitted per-request and never retained (Apple's definition of collect = retained). Fallback if review pushes back: add Health & Fitness / linked / App Functionality.
- "Data is encrypted in transit": yes (TLS). · "You can request deletion": yes (in-app).

## Review notes (paste from docs/APP_STORE_REVIEW_NOTES.md)
Covers: background-audio justification (2.5.4), clinical-records entitlement rationale,
SIWA-only login (reviewer can sign in with any Apple ID — production backend is live),
not-medical-advice positioning.

## Build
- **Submit 1.0.1 (3)** — `APP_STORE_ELIGIBLE`, `processingState: VALID`, already passed Beta App
  Review, code-identical to `main`. Release config → production gateway (live).
  `ITSAppUsesNonExemptEncryption=false` set, so the export-compliance question is skipped.
- Do NOT submit 1.0.1 (2): `buildAudienceType: INTERNAL_ONLY` is permanent per-build and makes it
  structurally ineligible for review.
- Upload: Xcode Organizer → Distribute App → App Store Connect (or ASC API key for CLI). CLI
  `-exportArchive` upload does **not** work on this Mac — Xcode has no Apple ID in Accounts, so
  it fails with "Failed to find an account with App Store Connect access for team RM42FV53FU".

### ⚠️ Naming consistency — open risk (raised 2026-08-08, guideline 2.3.7)
The app currently presents **three different names**, which a reviewer sees all at once:

| Surface | Name | Source |
|---|---|---|
| Store listing | Astra AI Coach | ASC record |
| Home-screen icon | **FitnessApp** | `CFBundleName` — `PRODUCT_NAME` in `project.yml:21`; no `CFBundleDisplayName` is set at all |
| Every permission dialog | **Fitness Guru** | the 12 `*UsageDescription` strings, `project.yml:52-63` |

Fixing it requires a code change + rebuild + re-upload as build **4** (`CFBundleDisplayName:
"Astra AI Coach"`, and ideally re-wording the usage strings — note
`docs/APP_STORE_REVIEW_NOTES.md` §1/§2/§4 quote those strings verbatim and must be updated in
the same pass). Submitting build 3 as-is is possible but carries real 2.3.7 rejection risk.

## Submission-day sequence
1. ~~Accept agreements (ASC → Business)~~ — **done**.
2. ~~Create app record~~ — **done** (Session 81, as "Astra AI Coach").
3. Privacy labels (§ above) — **status unverified**, confirm before submitting.
4. ~~Upload build~~ — **done**, 1.0.1 (3) uploaded and VALID.
5. Attach build + screenshots + metadata — **screenshots status unverified**; App Store requires
   at least one 6.9" iPhone set (1320×2868). Real-device captures are ideal: the app shows honest
   empty states with no HealthKit data, so simulator captures would look bare.
6. ~~TestFlight round~~ — **done**, both internal and external (external implies a passed Beta
   App Review).
7. Submit for review, pasting `docs/APP_STORE_REVIEW_NOTES.md` into the review-notes field.
