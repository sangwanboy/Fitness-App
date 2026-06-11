import SwiftUI

/// Dashboard card surfacing the daily challenge with glass aesthetic,
/// animated progress bar, and confetti-burst completion state.
public struct DailyChallengeCard: View {

    @ObservedObject private var engine = ChallengeEngine.shared
    @ObservedObject private var hk = HealthKitManager.shared

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @State private var showDetail = false
    @State private var completionScale: CGFloat = 0
    @State private var completionOpacity: Double = 0
    @State private var confettiDots: [ConfettiDot] = []
    @State private var animatedProgress: Double = 0

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init() {}

    public var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            DailyChallengeView()
        }
    }

    // MARK: - Card Body

    @ViewBuilder
    private var cardContent: some View {
        if let challenge = engine.activeChallenge {
            let challengeColor = ThemeHelper.color(from: challenge.colorHex)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow(challenge: challenge, color: challengeColor)
                    progressSection(challenge: challenge, color: challengeColor)
                    footerRow(challenge: challenge, color: challengeColor)
                }
                .padding(16)

                // Confetti canvas layer
                if !confettiDots.isEmpty {
                    Canvas { ctx, size in
                        for dot in confettiDots {
                            let rect = CGRect(
                                x: dot.x * size.width,
                                y: dot.y * size.height,
                                width: dot.size,
                                height: dot.size
                            )
                            ctx.fill(Path(ellipseIn: rect), with: .color(dot.color))
                        }
                    }
                    .allowsHitTesting(false)
                }

                // Completion checkmark overlay
                if engine.progress >= 1.0 {
                    completionBadge
                        .scaleEffect(completionScale)
                        .opacity(completionOpacity)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(challengeColor.opacity(0.12)).interactive(),
                in: .rect(cornerRadius: 20)
            )
            .onChange(of: engine.progress) { _, newValue in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animatedProgress = newValue
                }
                if newValue >= 1.0 {
                    triggerCompletionAnimation()
                }
            }
            .onAppear {
                animatedProgress = engine.progress
                if engine.progress >= 1.0 {
                    completionScale = 1
                    completionOpacity = 1
                }
            }
        } else {
            emptyState
        }
    }

    // MARK: - Header

    private func headerRow(challenge: Challenge, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: challenge.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Challenge")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.45))
                    .textCase(.uppercase)
                    .kerning(0.5)

                Text(challenge.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.35) : .black.opacity(0.3))
        }
    }

    // MARK: - Progress

    private func progressSection(challenge: Challenge, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * CGFloat(animatedProgress), 0), height: 8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animatedProgress)
                }
            }
            .frame(height: 8)

            progressLabel(challenge: challenge, color: color)
        }
    }

    private func progressLabel(challenge: Challenge, color: Color) -> some View {
        let current = hk.metricSummaries[challenge.metric]?.currentValue ?? 0
        let target = challenge.targetValue
        let unit = challenge.metric.unit
        let isComplete = engine.progress >= 1.0

        return HStack {
            if isComplete {
                Label("Completed!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            } else {
                Text(progressText(current: current, target: target, unit: unit))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.6))
            }
            Spacer()
            Text("\(Int(engine.progress * 100))%")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
    }

    private func progressText(current: Double, target: Double, unit: String) -> String {
        let fmt: (Double) -> String = { v in
            if v >= 1000 { return String(format: "%.0f", v) }
            if v < 10 { return String(format: "%.1f", v) }
            return String(format: "%.0f", v)
        }
        return "\(fmt(current)) / \(fmt(target)) \(unit)"
    }

    // MARK: - Footer

    private func footerRow(challenge: Challenge, color: Color) -> some View {
        HStack {
            Label(timeRemaining(until: challenge.expiresAt), systemImage: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.35))
            Spacer()
            Text("View Details")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color.opacity(0.9))
        }
    }

    private func timeRemaining(until date: Date) -> String {
        let diff = max(date.timeIntervalSinceNow, 0)
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        return "\(h)h \(m)m left"
    }

    // MARK: - Completion badge

    private var completionBadge: some View {
        ZStack {
            Circle()
                .fill(.green.opacity(0.25))
                .frame(width: 36, height: 36)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.green)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(accentColor)
            Text("Loading today's challenge…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.5))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Completion Animation

    private func triggerCompletionAnimation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            completionScale = 1.0
            completionOpacity = 1.0
        }
        spawnConfetti()
    }

    private func spawnConfetti() {
        let colors: [Color] = [.green, .yellow, .cyan, .orange, .pink, .purple]
        confettiDots = (0..<28).map { _ in
            ConfettiDot(
                x: Double.random(in: 0.05...0.95),
                y: Double.random(in: 0.05...0.75),
                size: Double.random(in: 4...9),
                color: colors.randomElement()!.opacity(Double.random(in: 0.55...0.95))
            )
        }
        // Fade out after a moment
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.8)) {
                confettiDots = []
            }
        }
    }
}

// MARK: - Confetti Model

private struct ConfettiDot {
    var x: Double
    var y: Double
    var size: Double
    var color: Color
}
