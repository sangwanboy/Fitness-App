import SwiftUI

/// Branded cold-launch animation — glass-heart logo at the center of two
/// counter-rotating neon orbital rings, with the "Fitness Guru" wordmark
/// fading in below. Mirrors the app icon (glass bubble heart + orbits).
///
/// Uses `AdaptiveBackground` so the theme/accent the user has selected
/// stays consistent from launch into the main app — no visual jolt at handoff.
public struct AppLoadingScreen: View {
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @State private var outerRingAngle: Double = 0
    @State private var middleRingAngle: Double = 0
    @State private var innerRingAngle: Double = 0
    @State private var heartScale: CGFloat = 0.55
    @State private var heartGlow: Double = 0.35
    @State private var titleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var dotsPhase: Int = 0

    public init() {}

    private var accent: Color { ThemeHelper.color(from: accentColorHex) }
    private var isDark: Bool { themeMode == "dark" }

    public var body: some View {
        ZStack {
            AdaptiveBackground().ignoresSafeArea()

            // Soft halo behind the logo so the rings glow against the gradient
            RadialGradient(
                colors: [accent.opacity(0.28), .purple.opacity(0.18), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()
            .blur(radius: 24)
            .allowsHitTesting(false)

            VStack(spacing: 36) {
                Spacer(minLength: 0)

                ZStack {
                    // Outer ring — dashed angular gradient, slow clockwise
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [accent, .purple, .pink, accent.opacity(0.3), accent],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [70, 28])
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(outerRingAngle))
                        .shadow(color: accent.opacity(0.55), radius: 18)

                    // Middle ring — faster counter-clockwise, thinner
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.pink.opacity(0.7), accent, .clear, .pink.opacity(0.7)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [44, 18])
                        )
                        .frame(width: 170, height: 170)
                        .rotationEffect(.degrees(middleRingAngle))
                        .shadow(color: .pink.opacity(0.35), radius: 12)

                    // Inner subtle ring for depth
                    Circle()
                        .stroke(
                            Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 8])
                        )
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(innerRingAngle))

                    // Glass capsule + pulsing heart
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isDark ? 0.04 : 0.5))
                            .frame(width: 108, height: 108)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.35), .clear, .white.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )

                        Image(systemName: "heart.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.pink, Color(red: 1.0, green: 0.32, blue: 0.45), .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(heartScale)
                            .shadow(color: .pink.opacity(heartGlow), radius: 24)
                            .symbolEffect(.pulse.byLayer, options: .repeating)
                    }
                }
                .frame(height: 240)

                VStack(spacing: 10) {
                    Text("Fitness Guru")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDark
                                    ? [.white, .white.opacity(0.7)]
                                    : [.black, .black.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(titleOpacity)

                    Text("Powered by Astra")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.5)
                        .textCase(.uppercase)
                        .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .opacity(taglineOpacity)
                }

                Spacer(minLength: 0)

                // Three breathing dots at the bottom — matches the typing indicator
                // pattern used elsewhere in the app for visual consistency.
                HStack(spacing: 7) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .opacity(dotsPhase == i ? 1.0 : 0.25)
                            .scaleEffect(dotsPhase == i ? 1.0 : 0.75)
                    }
                }
                .opacity(taglineOpacity)
                .padding(.bottom, 56)
            }
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
            outerRingAngle = 360
        }
        withAnimation(.linear(duration: 13).repeatForever(autoreverses: false)) {
            middleRingAngle = -360
        }
        withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
            innerRingAngle = 360
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.08)) {
            heartScale = 1.0
        }
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
            heartGlow = 0.95
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.3)) {
            titleOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.65)) {
            taglineOpacity = 1.0
        }
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 380_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    dotsPhase = (dotsPhase + 1) % 3
                }
            }
        }
    }
}

#Preview {
    AppLoadingScreen()
        .preferredColorScheme(.dark)
}
