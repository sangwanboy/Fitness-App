import SwiftUI

// MARK: - ProgressHubView

/// Central hub that surfaces all new features in a scrollable, card-based layout.
/// Presented as the 4th tab ("Progress") in the main TabView.
public struct ProgressHubView: View {

    @ObservedObject private var hk             = HealthKitManager.shared
    @ObservedObject private var streakEngine   = StreakEngine.shared
    @ObservedObject private var challengeEngine = ChallengeEngine.shared

    @AppStorage("theme_mode")   private var themeMode     = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("athlete_name") private var athleteName   = "Alex Rivera"

    @State private var showStreak        = false
    @State private var showChallenge     = false
    @State private var showHRZones       = false
    @State private var showNutrition     = false
    @State private var showWorkoutAnalytics = false
    @State private var showBreathing     = false
    @State private var animateCards      = false

    private var isDark: Bool    { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    private var firstName: String  { athleteName.components(separatedBy: " ").first ?? "you" }

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Quick-stats row at the top
                quickStatsRow
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 14)

                // Section: Activity
                sectionLabel(icon: "flame.fill", title: "Activity", color: .orange)

                streakHubCard
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 18)

                challengeHubCard
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 22)

                // Section: Health Analytics
                sectionLabel(icon: "heart.text.square.fill", title: "Health Analytics", color: .red)

                HStack(alignment: .top, spacing: 14) {
                    hrZonesHubCard
                    workoutAnalyticsHubCard
                }
                .opacity(animateCards ? 1 : 0)
                .offset(y: animateCards ? 0 : 26)

                // Section: Nutrition
                sectionLabel(icon: "fork.knife", title: "Nutrition", color: .green)

                nutritionHubCard
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 30)

                // Section: Mindfulness
                sectionLabel(icon: "wind", title: "Mindfulness", color: .teal)

                breathingHubCard
                    .opacity(animateCards ? 1 : 0)
                    .offset(y: animateCards ? 0 : 34)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveBackground())
        .navigationTitle("Progress")
        .navigationSubtitle(currentDateString())
        .toolbarTitleDisplayMode(.inlineLarge)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                animateCards = true
            }
            Task { try? await hk.fetchTodayData() }
        }
        // --- Sheets ---
        .sheet(isPresented: $showStreak)           { StreakView() }
        .sheet(isPresented: $showChallenge)        { DailyChallengeView() }
        .sheet(isPresented: $showHRZones)          { HeartRateZonesView() }
        .sheet(isPresented: $showNutrition)        { NutritionDashboardView() }
        .sheet(isPresented: $showWorkoutAnalytics) { WorkoutAnalyticsView() }
        .sheet(isPresented: $showBreathing)        { GuidedBreathingView() }
    }

    // MARK: - Quick Stats Row

    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            quickStatPill(
                icon: "flame.fill",
                value: "\(streakEngine.currentStreak)",
                label: "wk streak",
                color: streakEngine.currentStreak > 0 ? .orange : .gray
            )
            quickStatPill(
                icon: "figure.run",
                value: "\(hk.recentWorkouts28.count)",
                label: "workouts",
                color: accentColor
            )
            quickStatPill(
                icon: "bolt.fill",
                value: challengeProgressLabel,
                label: "challenge",
                color: .yellow
            )
        }
    }

    private var challengeProgressLabel: String {
        guard let c = challengeEngine.activeChallenge else { return "—" }
        let pct = Int(challengeEngine.progress * 100)
        let _ = c  // suppress unused warning
        return "\(pct)%"
    }

    private func quickStatPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Section Label

    private func sectionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Streak Hub Card

    private var streakHubCard: some View {
        Button(action: { showStreak = true }) {
            HStack(spacing: 16) {
                // Flame icon circle
                ZStack {
                    Circle()
                        .fill(streakColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: streakEngine.currentStreak > 0
                                    ? [Color.yellow.opacity(0.9), streakColor]
                                    : [.gray.opacity(0.4), .gray.opacity(0.3)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Streak")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)

                    HStack(spacing: 6) {
                        Text("\(streakEngine.currentStreak)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(streakEngine.currentStreak > 0 ? streakColor : (isDark ? .white.opacity(0.4) : .black.opacity(0.4)))
                            .monospacedDigit()
                        Text("week\(streakEngine.currentStreak == 1 ? "" : "s") active")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }

                    if streakEngine.longestStreak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("Best: \(streakEngine.longestStreak)w")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        }
                    }
                }

                Spacer()

                // Mini dot row (last 5 weeks)
                HStack(spacing: 5) {
                    let weeks = Array(streakEngine.weeklyActivity
                        .sorted { $0.weekStart < $1.weekStart }
                        .suffix(5))
                    ForEach(0..<5, id: \.self) { i in
                        let active = (i < weeks.count) ? weeks[i].isActive : false
                        Circle()
                            .fill(active ? streakColor : (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)))
                            .frame(width: 10, height: 10)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var streakColor: Color {
        let s = streakEngine.currentStreak
        if s == 0  { return .gray.opacity(0.5) }
        if s < 4   { return .orange.opacity(0.8) }
        if s < 13  { return .orange }
        return Color(red: 1.0, green: 0.45, blue: 0.1)
    }

    // MARK: - Challenge Hub Card

    private var challengeHubCard: some View {
        Button(action: { showChallenge = true }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(challengeIconColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: challengeEngine.activeChallenge?.icon ?? "star.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(challengeIconColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Challenge")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)

                    if let c = challengeEngine.activeChallenge {
                        Text(c.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                            .lineLimit(1)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(challengeIconColor)
                                    .frame(width: geo.size.width * min(challengeEngine.progress, 1.0), height: 5)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: challengeEngine.progress)
                            }
                        }
                        .frame(height: 5)
                    } else {
                        Text("Loading challenge...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(challengeEngine.progress * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(challengeIconColor)
                        .monospacedDigit()

                    if challengeEngine.progress >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var challengeIconColor: Color {
        guard let c = challengeEngine.activeChallenge else { return accentColor }
        return ThemeHelper.color(from: c.colorHex)
    }

    // MARK: - HR Zones Hub Card

    private var hrZonesHubCard: some View {
        Button(action: { showHRZones = true }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HR Zones")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDark ? .white : .black)
                        Text("Breakdown")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }

                // Zone bar strip
                HStack(spacing: 2) {
                    ForEach([Color.blue, Color.green, Color.yellow, Color.orange, Color.red], id: \.self) { c in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(c.opacity(0.8))
                            .frame(height: 6)
                    }
                }

                Text("This week's training")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Workout Analytics Hub Card

    private var workoutAnalyticsHubCard: some View {
        Button(action: { showWorkoutAnalytics = true }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Training")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDark ? .white : .black)
                        Text("Analytics")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }

                // Workout count summary
                let count = hk.recentWorkouts28.count
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .monospacedDigit()
                    Text("workouts")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                }

                Text("Last 28 days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Nutrition Hub Card

    private var nutritionHubCard: some View {
        Button(action: { showNutrition = true }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Macro Nutrition")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)

                    Text("Calories, protein, carbs & fat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))

                    // Calories today pill
                    let cals = Int(hk.dietaryCaloriesToday)
                    if cals > 0 {
                        Text("\(cals) kcal today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Breathing Hub Card

    private var breathingHubCard: some View {
        Button(action: { showBreathing = true }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "wind")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.teal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Guided Breathing")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)

                    Text("Box · 4-7-8 · Coherent · Custom")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))

                    HStack(spacing: 6) {
                        Image(systemName: "lungs.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.teal.opacity(0.8))
                        Text("Writes mindful minutes to Health")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                    }
                }

                Spacer()

                Text("Breathe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.teal)
                    .clipShape(Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func currentDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }
}
