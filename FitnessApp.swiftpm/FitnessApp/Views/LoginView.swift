import SwiftUI
import AuthenticationServices

public struct LoginView: View {
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"
    @State private var appeared = false
    @State private var ringProgress: Double = 0

    // Real gateway sign-in state
    @State private var isSigningIn = false
    @State private var signInError: String?
    /// Retained for the duration of the SIWA flow (release builds).
    @State private var appleSignIn = AppleSignInCoordinator()

    // Legal document sheets (guideline 5.1.1(i) — visible Privacy Policy / Terms links).
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false

    public init() {}

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

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

                    // Sign-up copy (guideline 5.1.1(i)) — explains what the
                    // account is for and the never-stored-server-side promise.
                    Text("Signing in creates your AI coach account through Apple — no email required. Your chat messages and health context are sent to our AI gateway only to generate that reply, and are never stored on our servers.")
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
                try await GatewayAuth.shared.signInDev()
                #else
                let identityToken = try await appleSignIn.requestIdentityToken()
                try await GatewayAuth.shared.signIn(appleIdentityToken: identityToken)
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

/// Wraps ASAuthorizationController in an async call that returns the raw
/// Apple identity token (JWT) for the gateway's /v1/auth/apple exchange.
/// NOTE: requires the Sign in with Apple entitlement
/// (`com.apple.developer.applesignin`, paid team RM42FV53FU) — that
/// entitlement is now present in FitnessApp.entitlements. If provisioning
/// ever drops the capability the request fails and LoginView surfaces the
/// error honestly.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    func requestIdentityToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            // Identity token only — no name/email scopes needed; the gateway
            // keys the account off the token's stable `sub`.
            request.requestedScopes = []
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
        continuation?.resume(returning: token)
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
