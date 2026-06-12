import SwiftUI

public struct LoginView: View {
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"
    @State private var appeared = false
    @State private var ringProgress: Double = 0

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
                
                // Login Buttons
                VStack(spacing: 12) {
                    // Get started button
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { isLoggedIn = true }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 20))
                                .accessibilityHidden(true)
                            Text("Get started — it's free")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: accentColor.opacity(0.4), radius: 14, x: 0, y: 6)
                    }
                    .padding(.horizontal, 24)
                    
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(height: 0.5)
                        Text("OR CONTINUE WITH")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                            .tracking(1)
                        Rectangle()
                            .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(height: 0.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                    
                    // Continue with Apple
                    Button(action: {
                        withAnimation { isLoggedIn = true }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Continue with Apple")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isDark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(isDark ? Color.white : Color.black)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 24)
                    
                    // Continue with Google (native glass)
                    Button(action: {
                        withAnimation { isLoggedIn = true }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 18))
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isDark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)

                    // Face ID
                    Button(action: {
                        withAnimation { isLoggedIn = true }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .font(.system(size: 20))
                                .foregroundColor(accentColor)
                            Text("Face ID")
                                .fontWeight(.semibold)
                                .foregroundColor(isDark ? .white : .black)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }
                    .accessibilityLabel("Sign in with Face ID")
                    .padding(.horizontal, 24)
                    
                    Text("By continuing you agree to our Terms and Privacy Policy. We never sell your health data.")
                        .font(.system(size: 11))
                        .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 8)
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
    }
}
