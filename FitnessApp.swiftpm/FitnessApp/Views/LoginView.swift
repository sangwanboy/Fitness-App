import SwiftUI
import AuthenticationServices

/// Shared by LoginView and the onboarding SignInScreen (which mirrors this
/// block) to switch the email/password form between the two gateway
/// endpoints (`v1/auth/login` vs `v1/auth/register`).
enum AuthMode {
    case signIn
    case register
}

public struct LoginView: View {
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"
    // Explicit opt-in (App Store/GDPR requirement) — default OFF everywhere
    // this key is read.
    @AppStorage("marketing_opt_in") private var marketingOptIn = false
    @State private var appeared = false
    @State private var ringProgress: Double = 0

    // Real gateway sign-in state
    @State private var isSigningIn = false
    @State private var signInError: String?
    /// Retained for the duration of the SIWA flow (release builds).
    @State private var appleSignIn = AppleSignInCoordinator()

    // Email/password sign-in state
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false

    // Legal document sheets (guideline 5.1.1(i) — visible Privacy Policy / Terms links).
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false

    public init() {}

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    /// Basic client-side shape check — real validation happens server-side;
    /// this just keeps the button disabled for obviously-wrong input.
    private var emailLooksValid: Bool {
        email.contains("@") && email.contains(".")
    }
    private var isEmailAuthValid: Bool {
        guard emailLooksValid else { return false }
        return authMode == .register ? password.count >= 8 : !password.isEmpty
    }

    public var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack {
                Spacer()

                // Centered concentric activity rings logo
                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 36)
                            .fill(Color.clear)
                            .frame(width: 130, height: 130)
                            .glassEffect(.regular, in: .rect(cornerRadius: 36))

                        // Internal glowing gradient backing
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.8), Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 82, height: 82)
                            .shadow(color: accentColor.opacity(0.45), radius: 16, x: 0, y: 8)
                            .overlay(
                                // Specular highlight
                                RadialGradient(
                                    colors: [.white.opacity(0.35), .clear],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 30
                                )
                            )

                        // Rings overlay (Move / Exercise / Stand representation)
                        ZStack {
                            // Steps/Move ring
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 3.5)
                                .frame(width: 44, height: 44)
                            Circle()
                                .trim(from: 0, to: ringProgress * 0.78)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees(-90))

                            // Exercise ring
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 3.5)
                                .frame(width: 31, height: 31)
                            Circle()
                                .trim(from: 0, to: ringProgress * 0.62)
                                .stroke(Color.white.opacity(0.78), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .frame(width: 31, height: 31)
                                .rotationEffect(.degrees(-90))

                            // Stand ring
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                                .frame(width: 18, height: 18)
                            Circle()
                                .trim(from: 0, to: ringProgress * 0.92)
                                .stroke(Color.white.opacity(0.58), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .frame(width: 18, height: 18)
                                .rotationEffect(.degrees(-90))
                        }
                    }

                    VStack(spacing: 8) {
                        Text("Fitness Guru")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(isDark ? .white : .black)
                            .tracking(-1.2)

                        Text("Your AI training partner. Connected to your health, calendar, and goals.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.65) : .black.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .padding(.horizontal, 28)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                // Sign-in actions — every button here does real work.
                VStack(spacing: 12) {
                    // Continue with Apple → gateway session.
                    // DEBUG: dev fake-auth against the local gateway.
                    // Release: real Sign in with Apple, backed by the
                    // com.apple.developer.applesignin entitlement.
                    Button(action: signInTapped) {
                        HStack(spacing: 8) {
                            if isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(isDark ? .black : .white)
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18))
                            }
                            Text("Continue with Apple")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isDark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(isDark ? Color.white : Color.black)
                        .cornerRadius(16)
                    }
                    .disabled(isSigningIn)
                    .padding(.horizontal, 24)

                    // "or" divider into the email/password alternative.
                    HStack(spacing: 10) {
                        Rectangle().fill(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12))
                            .frame(height: 1)
                        Text("or")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        Rectangle().fill(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)

                    // Email/password — the alternative to Apple for anyone
                    // who'd rather not use Sign in with Apple.
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
                            .foregroundColor(isDark ? .white : .black)
                            .tint(accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                        SecureField("Password", text: $password)
                            .textContentType(authMode == .register ? .newPassword : .password)
                            .foregroundColor(isDark ? .white : .black)
                            .tint(accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                        Button(action: emailAuthTapped) {
                            HStack(spacing: 8) {
                                if isSigningIn {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
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
                    .padding(.horizontal, 24)

                    // Compact marketing consent row — explicit opt-in only,
                    // never defaulted on.
                    Toggle(isOn: $marketingOptIn) {
                        Text("Email me tips & product updates")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    .tint(accentColor)
                    .onChange(of: marketingOptIn) { _, _ in
                        UserDefaults.standard.set(true, forKey: "marketing_opt_in_touched")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 24)

                    // Sign-up copy (guideline 5.1.1(i)) — explains what the
                    // account is for and the never-stored-server-side promise.
                    Text("Create your AI coach account with Apple, or with your email and a password. Your chat messages and health context are sent to our AI gateway only to generate that reply, and are never stored on our servers.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, 2)

                    if let signInError {
                        Text(signInError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 28)
                    }

                    // Honest escape hatch: HealthKit features work without an
                    // AI session — only Astra needs the gateway sign-in.
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation { isLoggedIn = true }
                    }) {
                        Text("Continue without AI coach")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .disabled(isSigningIn)
                    .padding(.horizontal, 24)

                    Text("By continuing you agree to our Terms and Privacy Policy. We never sell your health data.")
                        .font(.system(size: 11))
                        .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 8)

                    // Visible, tappable policy links (App Store Connect requires
                    // both URLs; guideline 5.1.1(i) requires them in-app too).
                    HStack(spacing: 14) {
                        Button("Privacy Policy") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showPrivacyPolicy = true
                        }
                        Text("·")
                            .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                        Button("Terms of Service") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showTerms = true
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                    .padding(.top, 4)
                }
                .padding(.bottom, 36)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.35)) {
                ringProgress = 1
            }
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

    /// Email/password sign-in or account creation against the Atlas AI
    /// Gateway. Same success/failure shape as `signInTapped` below — an
    /// honest inline error on failure, never a crash, never a logged
    /// credential.
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
                // We know this email with certainty (unlike Apple's private
                // relay, which only discloses one on the first ever
                // authorization) — keep Settings' Email row honest right away
                // rather than waiting on the profile-sync round trip.
                UserDefaults.standard.set(enteredEmail, forKey: "account_email")
                withAnimation { isLoggedIn = true }
            } catch {
                let context: EmailAuthContext = authMode == .signIn ? .login : .register
                signInError = (error as? GatewayError)?.emailAuthMessage(context) ?? "Sign-in failed. Try again."
            }
            isSigningIn = false
        }
    }

    /// Sign in against the Atlas AI Gateway, then enter the app.
    /// Failure keeps the user on this screen with an honest inline error and
    /// the "Continue without AI coach" fallback right below.
    private func signInTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        signInError = nil
        isSigningIn = true
        Task {
            do {
                #if DEBUG
                // Real Sign in with Apple against the production gateway;
                // the fake dev-auth only works on a local gateway started
                // with ALLOW_FAKE_APPLE (prod rejects it by design).
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
                withAnimation { isLoggedIn = true }
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // User dismissed the Apple sheet — not an error worth shouting about.
            } catch {
                signInError = (error as? GatewayError)?.userMessage
                    ?? "Couldn't sign in: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }
}

// MARK: - Sign in with Apple coordinator

/// Result of a completed Sign in with Apple authorization: the identity
/// token for the gateway's /v1/auth/apple exchange, plus whatever profile
/// info Apple disclosed on THIS authorization. `fullName`/`email` are
/// non-nil only on the very first authorization for a given Apple ID —
/// every later authorization returns nil for both by design. Callers must
/// handle that nil silently (no fallback prompt asking the user to re-enter
/// what Apple already decided not to share again).
struct AppleSignInResult {
    let identityToken: String
    let fullName: PersonNameComponents?
    let email: String?
}

/// Wraps ASAuthorizationController in an async call that returns the Apple
/// identity token (JWT) for the gateway's /v1/auth/apple exchange, plus any
/// name/email Apple discloses. NOTE: requires the Sign in with Apple
/// entitlement (`com.apple.developer.applesignin`, paid team RM42FV53FU) —
/// that entitlement is now present in FitnessApp.entitlements. If
/// provisioning ever drops the capability the request fails and LoginView
/// surfaces the error honestly.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    func requestSignIn() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            // Full name + email so the account this creates can carry a
            // human profile — the gateway still keys the account off the
            // token's stable `sub`; this is purely profile capture.
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: GatewayError.badRequest("Apple did not return an identity token."))
            continuation = nil
            return
        }
        continuation?.resume(returning: AppleSignInResult(identityToken: token,
                                                            fullName: credential.fullName,
                                                            email: credential.email))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

/// Persist whatever Apple gave us on a completed authorization, then kick a
/// fire-and-forget gateway profile sync. Shared by every Sign in with Apple
/// call site (LoginView, onboarding SignInScreen, SettingsView) since they
/// all funnel through the same `AppleSignInCoordinator`.
@MainActor
func persistAppleSignInResult(_ result: AppleSignInResult) {
    if let fullName = result.fullName {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty {
            let ud = UserDefaults.standard
            let existingName = ud.string(forKey: "athlete_name") ?? ""
            if existingName.isEmpty || existingName == "Alex Rivera" {
                ud.set(formatted, forKey: "athlete_name")
            }
        }
    }
    if let email = result.email, !email.isEmpty {
        UserDefaults.standard.set(email, forKey: "account_email")
    }
    Task { await GatewayProfileSync.shared.syncNow() }
}
