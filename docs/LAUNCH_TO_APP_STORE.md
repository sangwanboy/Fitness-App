# Launching Fitness Guru to the App Store — end-to-end runbook

> The operational guide: from a clean checkout to "Waiting for Review" and beyond.
> Companion docs (don't duplicate them — this doc links out):
> - **[APP_STORE_METADATA.md](APP_STORE_METADATA.md)** — paste-ready ASC fields (name, description, keywords, privacy labels, age rating, submission-day sequence).
> - **[APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md)** — reviewer-facing notes (background audio, clinical records, SIWA).
> - **[DATA_AND_PRIVACY.md](DATA_AND_PRIVACY.md)** — the privacy architecture the labels are derived from.
> - **[BUILD_AND_DEPLOY.md](BUILD_AND_DEPLOY.md)** — day-to-day dev builds (not release).
> - **[../HANDOFF-APPSTORE-READINESS.md](../HANDOFF-APPSTORE-READINESS.md)** — the original readiness plan (mostly executed; kept for history).

App identity: **Fitness Guru** · bundle `com.tushar.fitnessapp` · team `RM42FV53FU` ·
version source of truth `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).

---

## 0. Readiness status (verified 2026-07-22)

Done — do not redo:

| Item | Where |
|---|---|
| Sign in with Apple entitlement + real release auth flow | `FitnessApp.entitlements`, `Views/LoginView.swift` |
| Email+password sign-in alongside SIWA (SIWA equal-footing, guideline 4.8) | commit `dd9111a` |
| Login gate defaults to logged-out, with migration for existing installs | `ContentView.swift:12`, `FitnessApp.swift:129` |
| Privacy manifest | `FitnessApp/PrivacyInfo.xcprivacy` (registered in pbxproj) |
| In-app account deletion (guideline 5.1.1(v)) hitting `DELETE /v1/account` | `Views/SettingsView.swift` |
| Production gateway live (Azure, https — no ATS exceptions needed) | `GatewayConfig` Release branch |
| Legal/support site live | https://sangwanboy.github.io/Fitness-App/ (+`privacy.html`, `terms.html`) |
| App icon is a real 1024² PNG | `Assets.xcassets/AppIcon.appiconset/icon.png` |
| `ITSAppUsesNonExemptEncryption=false` (skips export-compliance question) | `project.yml` |
| All usage-description strings (HealthKit ×3, Calendar, Reminders, Camera, Photos, Notifications, Microphone, Focus, Local Network) | `project.yml` |
| Version bumped past 1.0 | currently **1.0.1 (2)** |

### Outstanding blockers — must clear before submitting

1. **Rotate the GCP service-account key** (`4d33d3bc…`, project `vertexi-ai-493516`).
   Rotation was explicitly deferred by the user on 2026-07-08 and CLAUDE.md says it must be
   revisited **before any public/App Store release** — this is that moment. It's a
   backend/GCP task (the key only feeds the local dev gateway via `GCP_SA_JSON_FILE`);
   after rotating, treat the old key as burned. **Requires user approval — ask first.**
2. **Release-config end-to-end test on the physical iPhone** (the handoff's definition of
   done): fresh install → real Sign in with Apple → Astra chat with HealthKit-backed
   multi-turn tool calls (thoughtSignature round-trip) against the production gateway.
   Note the result in `agents_log.md`.
3. **Apple-side SIWA token revocation on account deletion** — server-side gateway work
   (needs the team's SIWA `.p8` key on the gateway). External dependency; the in-app
   deletion + gateway wipe already work. Ship-blocking only if review flags it; track it.
4. **User-only ASC steps**: accept agreements, create the app record, privacy labels,
   screenshots, upload approval — everything paste-ready in
   [APP_STORE_METADATA.md](APP_STORE_METADATA.md). (~1 focused hour.)

---

## 1. Prerequisites (once per machine / account)

- **Apple Developer Program** membership active for team `RM42FV53FU`; you can log into
  [App Store Connect](https://appstoreconnect.apple.com) and **all agreements are accepted**
  (ASC → Business → Agreements — a pending agreement silently blocks uploads).
- **Xcode 26+** installed and selected (`xcode-select -p` → `/Applications/Xcode.app/...`),
  signed into the Apple ID (Xcode → Settings → Accounts) so automatic signing can mint the
  **Apple Distribution** certificate and App Store provisioning profile on demand
  (`-allowProvisioningUpdates` does this from the CLI).
- **xcodegen** (`brew install xcodegen`) — the project is generated from `project.yml`.
- Capabilities in the developer portal for `com.tushar.fitnessapp`: HealthKit (+ Clinical
  Health Records), Sign in with Apple. (Already enabled; automatic signing keeps profiles
  in sync.)

---

## 2. Pre-flight (every release)

```bash
cd ~/Fitness-App

# 1. Clean tree, latest main
git pull --rebase origin main && git status --short   # expect empty

# 2. Bump the build number (every ASC upload needs a unique CURRENT_PROJECT_VERSION;
#    bump MARKETING_VERSION only for user-visible releases) — edit project.yml, then:
xcodegen --spec project.yml

# 3. Verify no secrets are anywhere near the tree (CLAUDE.md rule 1)
# (pattern uses [ ]/[_] bracket tricks so this doc line never trips the scan itself)
git diff --cached | grep -icE "PRIVATE[ ]KEY|private[_]key|AIz[a]|MII[A-Za-z0-9+/]{40}"  # expect 0

# 4. Compile gate — NEVER grep for just "BUILD" (matches failures; see agents_log Session 66)
xcodebuild -project FitnessApp.xcodeproj -scheme FitnessApp \
  -destination "generic/platform=iOS" -configuration Release build \
  DEVELOPMENT_TEAM=RM42FV53FU CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
  2>&1 | tee /tmp/release_build.log
grep -q "BUILD SUCCEEDED" /tmp/release_build.log && echo GATE-OK || echo GATE-FAIL
```

Then the on-device Release test (blocker #2 above): install the Release build on the
iPhone, delete any previous install first (fresh-install path), sign in with Apple for
real, and run a multi-turn Astra chat that triggers HealthKit tool calls. Confirm replies
stream from `https://atlas-gw-tushar.denmarkeast.cloudapp.azure.com`.

---

## 3. Screenshots

ASC requires one screenshot set at the largest iPhone size (6.9″, 1320×2868); smaller
sizes scale down automatically. Capture from the iPhone 17 Pro Max simulator:

```bash
xcrun simctl boot "iPhone 17 Pro Max"
# ... drive the app to each screen, then per shot:
xcrun simctl io booted screenshot shot-01-home.png
```

Suggested set (5–8 shots): Home with health cards → Astra chat mid-coaching (tool call
result visible) → training plan week → morning brief notification → food logging →
sleep/snore summary. No health data of a real person — use the demo account's data.
Status bar: clean device frame optional; Apple no longer requires device bezels.

---

## 4. Archive & upload

### Option A — Xcode Organizer (recommended first time)

```bash
open FitnessApp.xcodeproj
```
1. Scheme **FitnessApp**, destination **Any iOS Device (arm64)**.
2. Product → **Archive**.
3. Organizer opens → **Distribute App** → **App Store Connect** → Upload (keep
   "manage version and build number" off — `project.yml` is the source of truth).
4. Wait for "Upload Successful"; processing in ASC takes ~15 min (email arrives).

### Option B — CLI (repeatable)

```bash
ARCHIVE=/tmp/FitnessGuru.xcarchive
xcodebuild -project FitnessApp.xcodeproj -scheme FitnessApp \
  -destination "generic/platform=iOS" -configuration Release archive \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM=RM42FV53FU CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
  2>&1 | tee /tmp/archive.log
grep -q "ARCHIVE SUCCEEDED" /tmp/archive.log || { echo "archive failed"; exit 1; }

cat > /tmp/export-appstore.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>RM42FV53FU</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist /tmp/export-appstore.plist -allowProvisioningUpdates
```

(For unattended CI uploads later: create an ASC API key and pass
`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` — queued as an
optional item in agents_log Session 67.)

---

## 5. App Store Connect

Follow the **submission-day sequence** in [APP_STORE_METADATA.md](APP_STORE_METADATA.md)
— every field there is paste-ready. In short:

1. Create the app record (name/subtitle/bundle/SKU/category).
2. Fill **App Privacy** labels exactly as specified there (health data is deliberately
   NOT declared "collected" — it's transmitted per-request, never retained; the fallback
   answer if review pushes back is documented in the same section).
3. Attach the processed build, screenshots, description/keywords/promo text, URLs.
4. Age rating questionnaire (expected 12+ for medical/treatment info).
5. **Review notes**: paste [APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md) —
   it pre-answers the three things most likely to be challenged: background audio
   (snore detection, on-device, never recorded), the clinical-records entitlement,
   and SIWA login. Provide a demo Apple ID or note that any Apple ID works
   (production backend is live).

## 6. TestFlight (recommended, ~1 day)

Internal testing needs no review: TestFlight tab → add internal testers → distribute the
processed build. Run the fresh-install → SIWA → chat → tool-call loop once more from
TestFlight specifically (it uses the production entitlement set). Then submit.

## 7. Submit & during review

- Add the build to the version page → **Submit for Review**.
- Typical first-review turnaround: 1–3 days. Likely rejection themes and the prepared
  answers: 2.5.4 background audio → review notes §1; 5.1.1 health data / privacy
  policy → policy explicitly covers health data + stateless-gateway architecture;
  5.1.1(v) deletion → in-app, live-verified; 4.8 login → SIWA offered equal-footing.
- If rejected: respond in Resolution Center with the relevant review-notes section
  rather than re-uploading, unless a code change is genuinely required.

## 8. Post-approval

- Release option: manual release recommended for 1.0 (release after a final prod smoke test).
- Tag the release: `git tag v1.0.1 && git push origin v1.0.1`; log the submitted
  build number in `agents_log.md`.
- Monitor: ASC crash reports + the gateway admin dashboard (`/admin/api/health`) for
  traffic/429s on launch day.
- Rotate any remaining deferred credentials if not already done (blocker #1).

---

*Written 2026-07-22 (Session 78). Update the readiness table above as items close.*
