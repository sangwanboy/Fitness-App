import SwiftUI

/// Full-screen detail sheet for the active daily challenge.
/// Three sections: hero ring + countdown, how-to context, challenge history.
public struct DailyChallengeView: View {

    @ObservedObject private var engine = ChallengeEngine.shared
    @ObservedObject private var hk = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @State private var countdown = ""
    @State private var ringProgress: Double = 0
    @State private var shareItem: [Any]? = nil
    @State private var showShareSheet = false

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                AdaptiveBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        if let challenge = engine.activeChallenge {
                            heroSection(challenge)
                            howToSection(challenge)
                            historySection
                        } else {
                            loadingView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Daily Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        renderShareImage()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .foregroundColor(accentColor)
                }
            }
        }
        .onAppear {
            ringProgress = engine.progress
            updateCountdown()
        }
        .sheet(isPresented: $showShareSheet) {
            if let items = shareItem {
                ShareSheetView(activityItems: items)
            }
        }
        .task {
            while !Task.isCancelled {
                updateCountdown()
                ringProgress = engine.progress
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Hero Section

    private func heroSection(_ challenge: Challenge) -> some View {
        let color = ThemeHelper.color(from: challenge.colorHex)

        return VStack(spacing: 20) {
            // Arc progress ring
            ZStack {
                ArcRing(progress: 1.0, color: color.opacity(0.15), lineWidth: 16)
                    .frame(width: 180, height: 180)

                ArcRing(progress: ringProgress, color: color, lineWidth: 16)
                    .frame(width: 180, height: 180)
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: ringProgress)

                VStack(spacing: 6) {
                    Image(systemName: challenge.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(color)

                    Text("\(Int(ringProgress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)

                    if engine.progress >= 1.0 {
                        Label("Completed!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(challenge.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                    .multilineTextAlignment(.center)

                Text(challenge.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Countdown timer pill
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                Text(countdown)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.12).clipShape(Capsule()))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24)
    }

    // MARK: - How-To Section

    private func howToSection(_ challenge: Challenge) -> some View {
        let color = ThemeHelper.color(from: challenge.colorHex)
        let current = hk.metricSummaries[challenge.metric]?.currentValue ?? 0
        let remaining = max(challenge.targetValue - current, 0)
        let unit = challenge.metric.unit

        return VStack(alignment: .leading, spacing: 14) {
            Text("How to Complete")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isDark ? .white : .black)

            VStack(alignment: .leading, spacing: 10) {
                contextRow(
                    icon: "chart.bar.fill",
                    color: color,
                    label: "Your progress",
                    value: "\(formatValue(current, metric: challenge.metric)) \(unit)"
                )
                contextRow(
                    icon: "target",
                    color: color,
                    label: "Target",
                    value: "\(formatValue(challenge.targetValue, metric: challenge.metric)) \(unit)"
                )
                contextRow(
                    icon: "arrow.right.circle.fill",
                    color: engine.progress >= 1.0 ? .green : color,
                    label: engine.progress >= 1.0 ? "Challenge done" : "Still needed",
                    value: engine.progress >= 1.0
                        ? "You crushed it!"
                        : "\(formatValue(remaining, metric: challenge.metric)) \(unit) more"
                )
            }

            Divider().opacity(0.2)

            tipText(for: challenge.metric, color: color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func contextRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.65) : .black.opacity(0.55))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
        }
    }

    @ViewBuilder
    private func tipText(for metric: HealthMetricType, color: Color) -> some View {
        let tip = challengeTip(for: metric)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(color)
                .padding(.top, 2)
            Text(tip)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.5))
                .lineSpacing(3)
        }
    }

    private func challengeTip(for metric: HealthMetricType) -> String {
        switch metric {
        case .steps:
            return "Take short walking breaks every hour. A 5-minute stroll each hour adds up fast."
        case .activeEnergy:
            return "Mix cardio with daily movement — stairs, brisk walks, and active chores all count."
        case .sleep:
            return "Wind down 30 minutes before bed. Dim lights and avoid screens for better sleep quality."
        case .hydration:
            return "Drink a glass of water with every meal and one first thing in the morning."
        case .hrv:
            return "Manage stress and prioritize sleep tonight. HRV rises naturally with good recovery."
        case .distance:
            return "Break the distance into smaller segments throughout the day — morning, lunch, evening."
        case .exerciseMinutes:
            return "Any activity that raises your heart rate counts. Even a brisk walk qualifies."
        case .mindfulMinutes:
            return "Use Apple's Mindfulness app or try box breathing: 4s in, 4s hold, 4s out."
        default:
            return "Stay consistent throughout the day. Small efforts accumulate into big results."
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Challenge History")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isDark ? .white : .black)

            if engine.completedChallenges.isEmpty {
                emptyHistory
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(engine.completedChallenges) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Complete your first challenge to start your history.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func historyRow(_ entry: CompletedChallenge) -> some View {
        let color = ThemeHelper.color(from: entry.colorHex)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text(relativeDate(entry.completedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundColor(color)
        }
        .padding(12)
        .background(color.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 14)))
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(accentColor)
                .scaleEffect(1.3)
            Text("Loading challenge…")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Helpers

    private func updateCountdown() {
        guard let exp = engine.activeChallenge?.expiresAt else {
            countdown = "--:--:--"
            return
        }
        let diff = max(exp.timeIntervalSinceNow, 0)
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        let s = Int(diff) % 60
        countdown = String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func formatValue(_ value: Double, metric: HealthMetricType) -> String {
        switch metric {
        case .steps, .activeEnergy, .hrv, .exerciseMinutes, .mindfulMinutes:
            return String(format: "%.0f", value)
        case .sleep, .hydration, .distance:
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Share

    private func renderShareImage() {
        guard let challenge = engine.activeChallenge else { return }
        let renderer = ImageRenderer(content:
            ShareCard(
                challenge: challenge,
                progress: engine.progress,
                accentColorHex: accentColorHex
            )
            .frame(width: 360, height: 360)
        )
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            shareItem = [uiImage]
            showShareSheet = true
        }
    }
}

// MARK: - Arc Ring

struct ArcRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = (min(geo.size.width, geo.size.height) - lineWidth) / 2
            let startAngle: Double = -90
            let endAngle: Double = startAngle + 360 * min(progress, 1.0)

            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round
                )
            )
        }
    }
}

// MARK: - Share Card

private struct ShareCard: View {
    let challenge: Challenge
    let progress: Double
    let accentColorHex: String

    private var challengeColor: Color { ThemeHelper.color(from: challenge.colorHex) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [challengeColor.opacity(0.25), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 200
            )

            VStack(spacing: 16) {
                ZStack {
                    ArcRing(progress: 1.0, color: challengeColor.opacity(0.15), lineWidth: 14)
                        .frame(width: 140, height: 140)
                    ArcRing(progress: min(progress, 1.0), color: challengeColor, lineWidth: 14)
                        .frame(width: 140, height: 140)
                    VStack(spacing: 4) {
                        Image(systemName: challenge.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(challengeColor)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                VStack(spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Daily Challenge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .kerning(1)
                }

                if progress >= 1.0 {
                    Label("Completed!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }

                Text("FitnessApp")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
