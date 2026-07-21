# App Store Connect — submission pack (Fitness Guru 1.0.1)

> Everything below is paste-ready for App Store Connect. URLs assume the legal
> site at `https://sangwanboy.github.io/Fitness-App/` (served from this repo's docs/ via GitHub Pages).

## App record
- **Name:** Fitness Guru
- **Subtitle** (30 chars): `AI coach for your health data`
- **Bundle ID:** com.tushar.fitnessapp · **SKU:** fitness-guru-001
- **Primary category:** Health & Fitness · Secondary: none
- **Price:** Free

## URLs
- **Support URL:** https://sangwanboy.github.io/Fitness-App/
- **Marketing URL:** (same, optional)
- **Privacy Policy URL:** https://sangwanboy.github.io/Fitness-App/privacy.html
- **Terms (EULA):** standard Apple EULA + in-app terms; link https://sangwanboy.github.io/Fitness-App/terms.html

## Promotional text (170 chars)
Astra reads your real Apple Health data and coaches you like it knows you — because it does. Morning briefs, training plans, honest insights. Nothing stored server-side.

## Description
Fitness Guru puts an AI coach — Astra — on top of your real Apple Health data.

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

Fitness Guru is not a medical device and does not provide medical advice.

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
- 1.0.1 (2)+, Release config → production gateway (live). ITSAppUsesNonExemptEncryption=false set.
- Upload: Xcode Organizer → Distribute App → App Store Connect (or ASC API key for CLI).

## Submission-day sequence
1. Accept agreements (ASC → Business). 2. Create app record (fields above).
3. Privacy labels (§ above). 4. Upload build, wait ~15 min processing.
5. Attach build + screenshots + metadata. 6. TestFlight internal round (recommended, 1 day).
7. Submit for review with the review notes.
