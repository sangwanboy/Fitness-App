import SwiftUI
import HealthKit
import AuthenticationServices
import UserNotifications

// MARK: - Shared building blocks

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(enabled ? accentColor : Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: enabled ? accentColor.opacity(0.3) : .clear, radius: 12, y: 6)
        }
        .disabled(!enabled)
        .buttonStyle(PlainButtonStyle())
    }
}

private struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Screen 1: Welcome

struct WelcomeScreen: View {
    let onContinue: () -> Void

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    @State private var showPrivacyPolicy = false
    @State private var showTerms = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple, .pink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 140, height: 140)
                    .shadow(color: .purple.opacity(0.4), radius: 30, y: 10)
                Image(systemName: "heart.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 36)

            OnboardingTitle(
                title: "Welcome to\nAstra",
                subtitle: "Your AI fitness coach. Personalized recovery, workouts, and nutrition guidance — powered by your real Apple Health data."
            )

            Spacer().frame(height: 14)

            // Honest one-line promise — no server-side storage claim beyond
            // what's actually true (Services/Legal/LegalTexts.swift covers the
            // full picture; this is the elevator-pitch version).
            Text("Your health data, coached by AI — nothing stored server-side.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            OnboardingPrimaryButton("Get Started", action: onContinue)
                .padding(.horizontal, 24)

            // Visible Privacy Policy / Terms links (guideline 5.1.1(i)) —
            // same sheets LoginView presents, reachable from the very first
            // screen instead of only after Sign In.
            HStack(spacing: 14) {
                Button("Privacy Policy") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showPrivacyPolicy = true
                }
                Text("·").foregroundColor(.white.opacity(0.3))
                Button("Terms of Service") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showTerms = true
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(accentColor)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(title: "Privacy Policy", text: LegalTexts.privacyPolicy)
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Terms of Service", text: LegalTexts.terms)
        }
    }
}

// MARK: - Screen 2: Sign In

/// Real gateway sign-in, reusing the exact flow `LoginView` uses so there is
/// only one Sign in with Apple implementation in the app. `AppleSignInCoordinator`
/// and `GatewayAuth`/`GatewayConfig` are defined in Views/LoginView.swift and
/// Services/Gateway/ respectively — this screen calls them, it doesn't
/// reimplement them. LoginView itself still exists as a fallback (e.g. after
/// a sign-out), but a fresh install now signs in here and never sees it.
struct SignInScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    // Explicit opt-in (App Store/GDPR requirement) — default OFF everywhere
    // this key is read; same key LoginView and SettingsView bind to.
    @AppStorage("marketing_opt_in") private var marketingOptIn = false
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    @State private var isSigningIn = false
    @State private var signInError: String?
    /// Retained for the duration of the SIWA flow (release builds) — same
    /// pattern as LoginView's `@State private var appleSignIn`.
    @State private var appleSignIn = AppleSignInCoordinator()
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false

    // Email/password sign-in state — mirrors LoginView's block exactly.
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false

    private var emailLooksValid: Bool {
        email.contains("@") && email.contains(".")
    }
    private var isEmailAuthValid: Bool {
        guard emailLooksValid else { return false }
        return authMode == .register ? password.count >= 8 : !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 108, height: 108)
                Image(systemName: "apple.logo")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 28)

            OnboardingTitle(
                title: "Sign In",
                subtitle: "Create your Astra account with Apple, or with your email and a password."
            )

            Spacer()

            VStack(spacing: 12) {
                // Continue with Apple → gateway session.
                // DEBUG + local gateway: dev fake-auth. Otherwise: real Sign
                // in with Apple, exactly mirroring LoginView.signInTapped.
                Button(action: signInTapped) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                        }
                        Text("Continue with Apple")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .cornerRadius(16)
                }
                .disabled(isSigningIn)

                // "or" divider into the email/password alternative.
                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                    Text("or")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                }

                // Email/password — mirrors LoginView's block exactly.
                VStack(spacing: 10) {
                    Picker("", selection: $authMode) {
                        Text("Sign In").tag(AuthMode.signIn)
                        Text("Create Account").tag(AuthMode.register)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: authMode) { _, _ in signInError = nil }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .tint(accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                    SecureField("Password", text: $password)
                        .textContentType(authMode == .register ? .newPassword : .password)
                        .foregroundColor(.white)
                        .tint(accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                    Button(action: emailAuthTapped) {
                        HStack(spacing: 8) {
                            if isSigningIn {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text(authMode == .signIn ? "Sign In" : "Create Account")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accentColor, in: .rect(cornerRadius: 14))
                    }
                    .disabled(isSigningIn || !isEmailAuthValid)
                    .opacity(isEmailAuthValid ? 1 : 0.5)

                    if authMode == .signIn {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showForgotPassword = true
                        }) {
                            Text("Forgot password?")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        .disabled(isSigningIn)
                    }
                }

                // Compact marketing consent row — same key + explicit
                // opt-in-only default as LoginView's toggle.
                Toggle(isOn: $marketingOptIn) {
                    Text("Email me tips & product updates")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .tint(accentColor)
                .onChange(of: marketingOptIn) { _, _ in
                    UserDefaults.standard.set(true, forKey: "marketing_opt_in_touched")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                // Sign-up copy (guideline 5.1.1(i)) — what the account is for,
                // accurate for BOTH auth paths (Apple can hide the email;
                // email/password is stored on the gateway account), and the
                // never-stored promise for chat/health context sent per-request.
                Text("With Apple, your email is Apple's to share or hide. With email sign-up, the email and password you give us are sent to our gateway to create your account. Chat messages and health context are sent to our AI gateway only to generate that one reply, and are never stored on our servers.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)

                if let signInError {
                    Text(signInError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Honest escape hatch — mirrors LoginView's skip path exactly:
                // sets the same `is_logged_in` flag without a gateway session.
                // HealthKit features still work; only Astra needs the session.
                Button(action: continueWithoutAI) {
                    Text("Continue without AI coach")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .disabled(isSigningIn)

                HStack(spacing: 14) {
                    Button("Privacy Policy") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showPrivacyPolicy = true
                    }
                    Text("·").foregroundColor(.white.opacity(0.3))
                    Button("Terms of Service") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showTerms = true
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accentColor)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(title: "Privacy Policy", text: LegalTexts.privacyPolicy)
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Terms of Service", text: LegalTexts.terms)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }

    /// Email/password sign-in or account creation — identical shape to
    /// LoginView.emailAuthTapped, just calling `onContinue()` on success
    /// instead of relying on the caller to react to `isLoggedIn` flipping.
    private func emailAuthTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        signInError = nil
        isSigningIn = true
        let enteredEmail = email
        Task {
            do {
                if authMode == .signIn {
                    try await GatewayAuth.shared.signInWithEmail(email: enteredEmail, password: password)
                } else {
                    try await GatewayAuth.shared.registerWithEmail(email: enteredEmail, password: password)
                }
                UserDefaults.standard.set(enteredEmail, forKey: "account_email")
                isSigningIn = false
                isLoggedIn = true
                onContinue()
            } catch {
                let context: EmailAuthContext = authMode == .signIn ? .login : .register
                signInError = (error as? GatewayError)?.emailAuthMessage(context) ?? "Sign-in failed. Try again."
                isSigningIn = false
            }
        }
    }

    /// Identical branch structure to LoginView.signInTapped: dev fake-auth
    /// only compiles in when both DEBUG and the local/LAN gateway are active;
    /// every other configuration (release builds, or DEBUG against the prod
    /// gateway) goes through real Sign in with Apple.
    private func signInTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        signInError = nil
        isSigningIn = true
        Task {
            do {
                #if DEBUG
                if GatewayConfig.isLocalGateway {
                    try await GatewayAuth.shared.signInDev()
                } else {
                    let result = try await appleSignIn.requestSignIn()
                    try await GatewayAuth.shared.signIn(appleIdentityToken: result.identityToken)
                    persistAppleSignInResult(result)
                }
                #else
                let result = try await appleSignIn.requestSignIn()
                try await GatewayAuth.shared.signIn(appleIdentityToken: result.identityToken)
                persistAppleSignInResult(result)
                #endif
                isSigningIn = false
                isLoggedIn = true
                onContinue()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // User dismissed the Apple sheet — stay on this screen, no error text.
                isSigningIn = false
            } catch {
                signInError = (error as? GatewayError)?.userMessage
                    ?? "Couldn't sign in: \(error.localizedDescription)"
                isSigningIn = false
            }
        }
    }

    private func continueWithoutAI() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isLoggedIn = true
        onContinue()
    }
}

// MARK: - Screen 3: About You

struct AboutYouScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @AppStorage("athlete_name")     private var athleteName = ""
    @AppStorage("athlete_dob")      private var athleteDOBInterval: Double = 0
    @AppStorage("athlete_sex")      private var athleteSex = ""
    @AppStorage("athlete_height_cm") private var athleteHeightCm: Double = 170
    @AppStorage("athlete_weight_kg") private var athleteWeightKg: Double = 70

    @State private var name = ""
    // Default to ~25 years ago instead of today's date — otherwise derived age
    // is 0 and the safety rails would treat the user as a minor.
    @State private var dob: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var sex = ""
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    // Same honesty rule as dobTouched: untouched slider defaults (170/70)
    // are placeholders, not facts — never persisted, never written to Health.
    @State private var bodyTouched = false
    // Save-guard (same pattern as EditProfileSheet in ProfileSheets.swift):
    // only persist the wheel's value if the user actually touched it, or a
    // real DOB already existed. Saving the untouched -25y default as if it
    // were a real answer is the same class of bug as the "born today" one —
    // an honest empty state (unset athlete_dob) beats a fabricated one.
    @State private var dobTouched = false

    private let sexOptions = ["Female", "Male", "Other", "Prefer not to say"]

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTitle(
                        title: "About You",
                        subtitle: "We'll use this to personalize your goals and recovery scoring."
                    )
                    .padding(.top, 12)

                    VStack(spacing: 14) {
                        formField("Name") {
                            TextField("e.g. Alex", text: $name)
                                .textInputAutocapitalization(.words)
                                // iOS autocorrect happily turns "Tushar" into
                                // "Tisha's" — proper names should never be
                                // auto-corrected.
                                .autocorrectionDisabled()
                                .textContentType(.givenName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        formField("Date of birth") {
                            // Cap at today so users can't set a future DOB.
                            DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .onChange(of: dob) { _, _ in dobTouched = true }
                        }

                        formField("Sex") {
                            Picker("Sex", selection: $sex) {
                                Text("Select").tag("")
                                ForEach(sexOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                        }

                        sliderField("Height", value: $heightCm, range: 120...220, step: 1, suffix: "cm") {
                            "\(Int(heightCm)) cm"
                        }
                        .onChange(of: heightCm) { _, _ in bodyTouched = true }

                        sliderField("Weight", value: $weightKg, range: 30...200, step: 0.5, suffix: "kg") {
                            String(format: "%.1f kg", weightKg)
                        }
                        .onChange(of: weightKg) { _, _ in bodyTouched = true }
                    }
                    .padding(.horizontal, 20)

                    // Why this data helps — one honest line, not a wall of legal text.
                    Text("This powers your heart-rate zones and Live Basics recovery score — it's never sent anywhere except to generate an Astra reply.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                }
                .padding(.bottom, 100)
            }

            OnboardingPrimaryButton("Continue", enabled: canContinue) {
                save()
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            name = athleteName
            if athleteDOBInterval > 0 {
                dob = Date(timeIntervalSince1970: athleteDOBInterval)
                dobTouched = true
            }
            sex = athleteSex
            if athleteHeightCm > 0 { heightCm = athleteHeightCm }
            if athleteWeightKg > 0 { weightKg = athleteWeightKg }
        }
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(0.8)
            HStack { content(); Spacer() }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func sliderField(_ label: String,
                             value: Binding<Double>,
                             range: ClosedRange<Double>,
                             step: Double,
                             suffix: String,
                             display: @escaping () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.8)
                Spacer()
                Text(display())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Slider(value: value, in: range, step: step)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
    }

    private func save() {
        athleteName = name.trimmingCharacters(in: .whitespaces)
        // Only persist if the user actually touched the wheel (or a real DOB
        // was already on file) — an untouched wheel must never stamp the
        // -25y placeholder into athlete_dob as if it were a real answer.
        if dobTouched { athleteDOBInterval = dob.timeIntervalSince1970 }
        athleteSex = sex
        // Untouched sliders must not stamp 170cm/70kg into the profile (and
        // definitely not into Apple Health) as if the user said so — same
        // fabricated-data class as the DOB "born today" bug.
        if bodyTouched || athleteHeightCm > 0 || athleteWeightKg > 0 {
            athleteHeightCm = heightCm
            athleteWeightKg = weightKg
            Task {
                _ = await HealthKitManager.shared.logBodyMass(kilograms: weightKg)
                _ = await HealthKitManager.shared.logHeight(centimeters: heightCm)
            }
        }
    }
}

// MARK: - Screen 4: Connect & Permissions

struct ConnectScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @ObservedObject private var hk = HealthKitManager.shared
    @ObservedObject private var ek = EventKitManager.shared

    @State private var requestingHealth = false
    @State private var hkGrantedFlag = false   // local UI flag; HK has no public auth-status read
    @AppStorage("athlete_dob") private var athleteDOBInterval: Double = 0
    @AppStorage("athlete_sex") private var athleteSex = ""

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTitle(
                        title: "Connect",
                        subtitle: "Grant access so your coach can read real data instead of guessing."
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    connectCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Apple Health",
                        description: "Read steps, heart rate, HRV, sleep, workouts, body measurements.",
                        granted: hkGrantedFlag,
                        loading: requestingHealth,
                        connectLabel: "Connect"
                    ) {
                        Task { await connectHealth() }
                    }

                    connectCard(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Calendar & Reminders",
                        description: "Plan workouts around your day; create hydration & supplement reminders.",
                        granted: ek.calendarsGranted || ek.remindersGranted,
                        loading: false,
                        connectLabel: "Connect"
                    ) {
                        Task { await ek.requestAccess() }
                    }

                    connectCard(
                        icon: "cross.case.fill",
                        iconColor: .pink,
                        title: "Medical ID",
                        description: "Pre-filled from Apple Health (date of birth, sex). Optional.",
                        granted: athleteDOBInterval > 0 && !athleteSex.isEmpty,
                        loading: false,
                        connectLabel: "Sync"
                    ) {
                        syncMedicalId()
                    }

                    // Honest scoping line — clinical records (FHIR: allergies,
                    // conditions, medications, labs) are a materially bigger
                    // ask than the summaries above, so they stay a distinct,
                    // separate opt-in later rather than bundled into onboarding.
                    Text("Clinical records — allergies, conditions, medications, lab results — are a separate opt-in. Turn them on later in Profile → Health Records.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            OnboardingPrimaryButton("Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func connectCard(icon: String,
                             iconColor: Color,
                             title: String,
                             description: String,
                             granted: Bool,
                             loading: Bool,
                             connectLabel: String,
                             action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer()
            if loading {
                ProgressView().controlSize(.small).tint(.white)
            } else if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text(connectLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private func connectHealth() async {
        requestingHealth = true
        let granted = await hk.requestAuthorization()
        // Onboarding's single source of HK first-prompt — ContentView's .task
        // checks this flag and skips re-asking.
        UserDefaults.standard.set(true, forKey: "hk_requested_once")
        hkGrantedFlag = granted
        // After auth, opportunistically pre-fill Medical ID values if blank.
        syncMedicalId()
        requestingHealth = false
    }

    private func syncMedicalId() {
        let (dob, sex, _) = hk.readMedicalIdCharacteristics()
        if athleteDOBInterval == 0, let dob {
            athleteDOBInterval = dob.timeIntervalSince1970
        }
        if athleteSex.isEmpty, let sex {
            switch sex {
            case .female: athleteSex = "Female"
            case .male:   athleteSex = "Male"
            case .other:  athleteSex = "Other"
            default: break
            }
        }
    }
}

// MARK: - Screen 5: Goals & Coach

struct GoalsScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @AppStorage("training_goals") private var trainingGoals: String = ""
    @AppStorage("coach_personality") private var coachPersonality: String = "Direct"
    @State private var selected: Set<String> = []
    @State private var showDailyGoals = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options: [(String, String)] = [
        ("Endurance", "figure.run"),
        ("Strength", "dumbbell.fill"),
        ("Weight loss", "scalemass.fill"),
        ("Sleep better", "bed.double.fill"),
        ("Stay active", "figure.walk"),
        ("Flexibility", "figure.cooldown")
    ]

    // One-line descriptions kept in sync with the behavioral contracts in
    // ChatViewModel.personalityDirective(_:) — same four options Settings'
    // Coach personality picker offers, so onboarding never invents a fifth.
    private let personalities: [(name: String, icon: String, description: String)] = [
        ("Direct", "bolt.fill", "No pleasantries — the number, then the instruction."),
        ("Friendly", "face.smiling.fill", "Warm and encouraging, celebrates every win."),
        ("Concise", "text.alignleft", "Minimum words — just the numbers."),
        ("Motivational", "flame.fill", "High energy, ties every reply to your goals.")
    ]

    private var canContinue: Bool { !selected.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 20) {
                        OnboardingTitle(
                            title: "Pick Your Goals",
                            subtitle: "Choose one or more. Your coach focuses recommendations on what matters to you."
                        )
                        .padding(.top, 12)

                        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(options, id: \.0) { (label, icon) in
                                Button {
                                    if selected.contains(label) { selected.remove(label) } else { selected.insert(label) }
                                } label: {
                                    goalTile(label: label, icon: icon, picked: selected.contains(label))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showDailyGoals = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "target")
                                    .foregroundColor(accentColor)
                                Text("Customize daily goals — steps, sleep, hydration & more")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding(14)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("COACH PERSONALITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(0.8)
                            .padding(.horizontal, 20)

                        VStack(spacing: 10) {
                            ForEach(personalities, id: \.name) { option in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    coachPersonality = option.name
                                } label: {
                                    personalityRow(option: option, picked: coachPersonality == option.name)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 120)
            }

            OnboardingPrimaryButton("Continue", enabled: canContinue) {
                trainingGoals = selected.sorted().joined(separator: ", ")
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            selected = Set(trainingGoals
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
        .sheet(isPresented: $showDailyGoals) {
            GoalsEditorSheet()
        }
    }

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private func personalityRow(option: (name: String, icon: String, description: String), picked: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((picked ? accentColor : Color.white).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: option.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(picked ? accentColor : .white.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(option.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if picked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(accentColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(picked ? accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private func goalTile(label: String, icon: String, picked: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(picked ? accentColor : .white.opacity(0.75))
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(picked ? accentColor : Color.clear, lineWidth: 2)
        )
        // Visible bounce so the tap registers immediately, even before the
        // green border animates in. Pairs with a selection-class haptic so
        // the user feels the toggle on physical devices.
        .scaleEffect(reduceMotion ? 1.0 : (picked ? 1.02 : 1.0))
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: picked)
        .sensoryFeedback(.selection, trigger: picked)
    }
}

// MARK: - Screen 6: Notifications

/// Proactive-notification opt-in. Never fires the system permission sheet on
/// appear — only `requestThenContinue()`, wired to the "Enable Notifications"
/// tap, calls `NotificationManager.shared.requestPermissionIfNeeded()`. The
/// morning-brief time picker writes straight to the same `notif_morning_time`
/// UserDefaults key `NotificationManager.rescheduleMorningBrief()` reads
/// (default 480 = 8:00 AM, matching that default exactly — same as
/// Views/Components/NotificationSettingsSection.swift's Settings row).
struct NotificationsScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    // Same AppStorage key + default (8:00 AM) NotificationManager.rescheduleMorningBrief()
    // falls back to, and the same key Settings' NotificationTimeRow writes —
    // one source of truth, read/written directly rather than mirrored.
    @AppStorage("notif_morning_time") private var morningMinutes: Int = 8 * 60

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    private var isAuthorized: Bool {
        authStatus == .authorized || authStatus == .provisional || authStatus == .ephemeral
    }

    /// Date-picker view onto the minutes-from-midnight AppStorage value — same
    /// conversion NotificationSettingsSection's private `NotificationTimeRow`
    /// uses. Writes immediately as the wheel moves; no separate "touched"
    /// save-guard is needed here since 8:00 AM is a real, honest default,
    /// not a placeholder like AboutYouScreen's -25y DOB.
    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = morningMinutes / 60
                comps.minute = morningMinutes % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                morningMinutes = (c.hour ?? 8) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTitle(
                        title: "Stay in the Loop",
                        subtitle: "A daily morning brief, plus honest nudges built from your real data."
                    )
                    .padding(.top, 12)

                    kindsCard

                    VStack(alignment: .leading, spacing: 8) {
                        Text("MORNING BRIEF TIME")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(0.8)
                        HStack {
                            DatePicker("", selection: morningTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .colorScheme(.dark)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)

                    Text("Illness early warning, streak saves, and your weekly review all come from your real HealthKit data — every one of them is toggleable later in Profile → Notifications.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 120)
            }

            VStack(spacing: 12) {
                if isAuthorized {
                    OnboardingPrimaryButton("Continue", action: onContinue)
                } else {
                    OnboardingPrimaryButton(isRequesting ? "Requesting…" : "Enable Notifications",
                                            enabled: !isRequesting,
                                            action: requestThenContinue)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onContinue()
                    }) {
                        Text("Not now")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task {
            // Read-only status check — never requests. If the OS permission
            // was already granted (or denied) from a prior install/restore,
            // this reflects that honestly instead of showing a stale ask.
            authStatus = await NotificationManager.shared.currentAuthorizationStatus()
        }
    }

    private var kindsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            kindRow(icon: "sun.max.fill", color: .orange, title: "Morning brief",
                    description: "Recovery, sleep, and training load — every day.")
            kindRow(icon: "cross.case.fill", color: .red, title: "Illness early warning",
                    description: "A heads-up when resting HR, HRV, and sleep drift together.")
            kindRow(icon: "flame.fill", color: .orange, title: "Streak saves",
                    description: "An evening nudge if today hasn't kept your streak alive yet.")
            kindRow(icon: "calendar.badge.clock", color: .blue, title: "Weekly review",
                    description: "A weekly recap of your training and recovery trends.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private func kindRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    /// Only place in this screen that calls `requestPermissionIfNeeded()` —
    /// gated entirely behind the user's own tap, never `.onAppear`/`.task`.
    private func requestThenContinue() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isRequesting = true
        Task {
            await NotificationManager.shared.requestPermissionIfNeeded()
            authStatus = await NotificationManager.shared.currentAuthorizationStatus()
            isRequesting = false
            if isAuthorized {
                // Arm the morning brief + event nudges immediately instead of
                // waiting for the next foreground/HK refresh — same pattern
                // NotificationPermissionRow uses in Settings.
                NotificationManager.shared.rescheduleMorningBrief()
                NotificationManager.shared.evaluateProactiveNudges()
            }
            onContinue()
        }
    }
}

// MARK: - Screen 7: Meet Astra

struct MeetAstraScreen: View {
    let onFinish: () -> Void
    let onBack: () -> Void

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    // Deep-links into Coach via ChatPrefillBus — ContentView already switches
    // to the Coach tab the moment a prompt is queued (see its
    // `onChange(of: prefillBus.pendingPrompt)` handler), so tapping one of
    // these both finishes onboarding AND lands the user on Coach with the
    // question already sent.
    private let starterPrompts: [(text: String, icon: String)] = [
        ("What should I eat today?", "fork.knife"),
        ("Build me a training plan for this week", "figure.strengthtraining.traditional"),
        ("How did I sleep last night?", "moon.zzz.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    ZStack {
                        Circle()
                            .fill(AngularGradient(colors: [.indigo, .purple, .pink, .indigo], center: .center))
                            .frame(width: 130, height: 130)
                            .blur(radius: 1)
                            .shadow(color: .purple.opacity(0.5), radius: 30, y: 10)
                        Image(systemName: "sparkles")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer().frame(height: 32)

                    OnboardingTitle(
                        title: "Meet Astra",
                        subtitle: "Your AI coach remembers you — goals, history, and patterns, all kept in your profile. Astra builds training plans, logs meals from a photo, and writes your morning brief, grounded in your real data."
                    )

                    Spacer().frame(height: 28)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TRY ASKING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(0.8)

                        ForEach(starterPrompts, id: \.text) { prompt in
                            Button {
                                startChat(with: prompt.text)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: prompt.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(accentColor)
                                        .frame(width: 22)
                                    Text(prompt.text)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(14)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }

            OnboardingPrimaryButton("Get Started", action: onFinish)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
    }

    /// Queue the starter prompt BEFORE finishing — `finish()` flips
    /// `is_onboarded`, and ContentView's bus observer switches to the Coach
    /// tab as soon as `pendingPrompt` changes regardless of which branch of
    /// its body is currently on screen.
    private func startChat(with prompt: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ChatPrefillBus.shared.queue(prompt)
        onFinish()
    }
}
