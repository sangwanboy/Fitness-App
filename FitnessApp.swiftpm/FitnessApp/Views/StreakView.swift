import SwiftUI

/// Full-screen detail sheet for the Weekly Activity Streak feature.
/// Three sections:
///   1. Hero — animated flame + current / longest streak numbers
///   2. 12-week calendar grid
///   3. Trophy Shelf — horizontal scroll of earned + locked badges
public struct StreakView: View {
    @ObservedObject private var engine = StreakEngine.shared

    @AppStorage("theme_mode")   private var themeMode  = "dark"
    @AppStorage("accent_color") private var accentHex  = "#30D158"
    @AppStorage("athlete_name") private var athleteName = "Alex Rivera"

    @Environment(\.dismiss) private var dismiss

    @State private var flameScale: CGFloat    = 0.7
    @State private var flameOpacity: Double   = 0.0
    @State private var contentOffset: CGFloat = 30
    @State private var contentOpacity: Double = 0

    private var isDark: Bool    { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentHex) }
    private var firstName: String  { athleteName.components(separatedBy: " ").first ?? "you" }

    /// Flame color tied to streak size.
    private var flameColor: Color {
        let s = engine.currentStreak
        if s == 0  { return .gray.opacity(0.5) }
        if s < 4   { return .orange.opacity(0.8) }
        if s < 13  { return .orange }
        return Color(red: 1.0, green: 0.45, blue: 0.1)
    }

    /// 12 most-recent weeks for the calendar grid, oldest → newest.
    private var last12Weeks: [WeekActivity?] {
        let sorted = engine.weeklyActivity.sorted { $0.weekStart < $1.weekStart }
        let real   = Array(sorted.suffix(12))
        // Pad with nils at the front if we have fewer than 12.
        let padding = Array(repeating: nil as WeekActivity?, count: max(0, 12 - real.count))
        return padding + real.map { Optional($0) }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        heroSection
                            .transition(.scale(scale: 0.92).combined(with: .opacity))

                        calendarGrid
                            .offset(y: contentOffset)
                            .opacity(contentOpacity)

                        trophyShelf
                            .offset(y: contentOffset)
                            .opacity(contentOpacity)

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Activity Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.05)) {
                flameScale   = 1.0
                flameOpacity = 1.0
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.18)) {
                contentOffset  = 0
                contentOpacity = 1
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 20) {
            // Animated flame icon
            ZStack {
                Circle()
                    .fill(flameColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                    .blur(radius: 18)

                Circle()
                    .fill(flameColor.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "flame.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: engine.currentStreak > 0
                                ? [Color.yellow.opacity(0.9), flameColor]
                                : [.gray.opacity(0.4), .gray.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: flameColor.opacity(engine.currentStreak > 0 ? 0.55 : 0), radius: 14, x: 0, y: 4)
            }
            .scaleEffect(flameScale)
            .opacity(flameOpacity)

            // Streak count
            VStack(spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(engine.currentStreak)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .tracking(-2)
                        .foregroundColor(engine.currentStreak > 0 ? flameColor : (isDark ? .white.opacity(0.25) : .black.opacity(0.25)))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: engine.currentStreak)

                    Text("week streak")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                        .padding(.bottom, 6)
                }

                Text(heroSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
            }

            // Longest streak chip
            if engine.longestStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("Best: \(engine.longestStreak) week\(engine.longestStreak == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.vertical, 16)
    }

    private var heroSubtitle: String {
        switch engine.currentStreak {
        case 0:    return "Complete 3 workout days or 4 step-goal days in a week to start your streak."
        case 1:    return "Great start, \(firstName)! Keep it going next week."
        case 2...3: return "Building momentum — stay consistent!"
        case 4...7: return "A full month of active weeks. You're on fire."
        case 8...12: return "Two months and counting. This is a real habit now."
        case 13...25: return "Over three months of consistency. Incredible."
        case 26...51: return "Half a year of active weeks. You're in the top 1%."
        default:    return "A full year of weekly activity. Legend status."
        }
    }

    // MARK: - 12-Week Calendar Grid

    private var calendarGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "calendar", title: "Past 12 Weeks", color: accentColor)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<12, id: \.self) { i in
                    weekCell(for: last12Weeks[i])
                }
            }

            // Legend
            HStack(spacing: 14) {
                legendDot(color: accentColor, label: "Active")
                legendDot(color: isDark ? .white.opacity(0.12) : .black.opacity(0.1), label: "Quiet")
                Spacer()
                Text("Tap a cell for details")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.35) : .black.opacity(0.35))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func weekCell(for activity: WeekActivity?) -> some View {
        let isActive  = activity?.isActive ?? false
        let wDays     = activity?.workoutDays ?? 0
        let cal       = Calendar(identifier: .gregorian)
        let todayMon  = mondayOfCurrentWeek(cal: cal)
        let isThisWk  = activity.map { cal.startOfDay(for: $0.weekStart) == cal.startOfDay(for: todayMon) } ?? false

        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    activity == nil
                        ? (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
                        : isActive
                            ? accentColor.opacity(0.85)
                            : (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                )
            if isThisWk {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor.opacity(0.8), lineWidth: 1.5)
            }

            VStack(spacing: 4) {
                if let act = activity {
                    // Workout day count
                    Text("\(wDays > 0 ? wDays : act.stepGoalDays)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? .white : (isDark ? .white.opacity(0.5) : .black.opacity(0.45)))
                    Text(isActive ? (wDays > 0 ? "days" : "goal") : "quiet")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isActive ? .white.opacity(0.8) : (isDark ? .white.opacity(0.3) : .black.opacity(0.3)))
                        .tracking(0.3)
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white.opacity(0.15) : .black.opacity(0.12))
                }
            }
        }
        .frame(height: 52)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isActive)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
        }
    }

    // MARK: - Trophy Shelf

    private var trophyShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "trophy.fill", title: "Trophy Shelf", color: .yellow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StreakEngine.milestoneMilestones, id: \.self) { milestone in
                        badgeCard(milestone: milestone)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func badgeCard(milestone: Int) -> some View {
        let badge    = engine.earnedBadges.first(where: { $0.id == milestone })
        let earned   = badge != nil
        let placeholder = StreakBadge(id: milestone, earnedDate: Date())

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    earned
                        ? placeholder.badgeColor.opacity(0.15)
                        : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                )
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .frame(width: 100, height: 118)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(earned ? placeholder.badgeColor.opacity(0.2) : (isDark ? .white.opacity(0.07) : .black.opacity(0.06)))
                        .frame(width: 46, height: 46)
                    Image(systemName: placeholder.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(earned ? placeholder.badgeColor : (isDark ? .white.opacity(0.22) : .black.opacity(0.18)))
                }

                Text(placeholder.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(earned ? (isDark ? .white : .black) : (isDark ? .white.opacity(0.35) : .black.opacity(0.3)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 82)

                if let b = badge {
                    Text(badgeDateString(b.earnedDate))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.4))
                } else {
                    Text("\(milestone)w")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.25) : .black.opacity(0.2))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)

            // Lock overlay for unearned badges
            if !earned {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.clear)
                    .frame(width: 100, height: 118)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.25) : .black.opacity(0.2))
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.7))
                            )
                        ,alignment: .topTrailing
                    )
                    .padding(6)
            }
        }
        .opacity(earned ? 1.0 : 0.4)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: earned)
    }

    private func badgeDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    // MARK: - Helpers

    private func mondayOfCurrentWeek(cal: Calendar) -> Date {
        var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        c.weekday = 2
        return cal.date(from: c) ?? Date()
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .tracking(0.5)
            Spacer()
        }
    }
}
