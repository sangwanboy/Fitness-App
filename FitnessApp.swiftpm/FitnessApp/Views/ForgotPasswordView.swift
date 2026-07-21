import SwiftUI

/// Two-step "forgot password" flow, presented as a sheet from LoginView's
/// (and the onboarding SignInScreen's) "Forgot password?" button.
///
/// Step 1 requests a reset code by email (`v1/auth/request-password-reset`,
/// which per the gateway contract ALWAYS returns `{ok:true}` — so we always
/// advance to step 2 and show an honest, non-committal confirmation rather
/// than implying whether the email is registered).
///
/// Step 2 submits that code plus a new password (`v1/auth/reset-password`),
/// which auto-logs-in on success — same as register/login.
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("is_logged_in") private var isLoggedIn = false

    private enum Step {
        case requestCode
        case resetPassword
    }

    @State private var step: Step = .requestCode
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private var canRequestCode: Bool {
        email.contains("@") && email.contains(".")
    }
    private var canResetPassword: Bool {
        code.trimmingCharacters(in: .whitespaces).count == 6 && newPassword.count >= 8
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .requestCode:
                        requestCodeStep
                    case .resetPassword:
                        resetPasswordStep
                    }
                }
                .padding(20)
            }
            .background(AdaptiveBackground())
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Step 1: request a code

    private var requestCodeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter the email on your account and we'll send a reset code.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))

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

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButton(title: "Send reset code", disabled: !canRequestCode || isWorking) {
                Task { await requestCode() }
            }
        }
    }

    // MARK: - Step 2: submit code + new password

    private var resetPasswordStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let infoMessage {
                Text(infoMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .foregroundColor(isDark ? .white : .black)
                .tint(accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                .onChange(of: code) { _, newValue in
                    let digitsOnly = String(newValue.filter(\.isNumber).prefix(6))
                    if digitsOnly != newValue { code = digitsOnly }
                }

            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
                .foregroundColor(isDark ? .white : .black)
                .tint(accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

            Text("At least 8 characters.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButton(title: "Reset password", disabled: !canResetPassword || isWorking) {
                Task { await resetPassword() }
            }
        }
    }

    private func actionButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(title).fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(accentColor, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Actions

    private func requestCode() async {
        isWorking = true
        errorMessage = nil
        do {
            try await GatewayAuth.shared.requestPasswordReset(email: email)
            // Always advance — the endpoint always returns ok, so branching
            // on success/failure here would leak whether the email exists.
            infoMessage = "If an account exists, a code was sent to your email."
            withAnimation { step = .resetPassword }
        } catch {
            // A genuine transport/config failure (not a "does this email
            // exist" answer) — the request never reached the gateway.
            errorMessage = (error as? GatewayError)?.userMessage ?? "Couldn't send reset code. Try again."
        }
        isWorking = false
    }

    private func resetPassword() async {
        isWorking = true
        errorMessage = nil
        do {
            try await GatewayAuth.shared.resetPassword(email: email, code: code, newPassword: newPassword)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { isLoggedIn = true }
            dismiss()
        } catch {
            errorMessage = (error as? GatewayError)?.emailAuthMessage(.resetCode) ?? "Couldn't reset password. Try again."
        }
        isWorking = false
    }
}
