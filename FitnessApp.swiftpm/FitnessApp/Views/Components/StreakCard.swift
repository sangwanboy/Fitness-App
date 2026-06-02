import SwiftUI

/// Compact Dashboard tile showing the user's current weekly activity streak.
/// Tapping opens `StreakView` as a sheet.
public struct StreakCard: View {
    @ObservedObject private var engine = StreakEngine.shared

    @AppStorage("theme_mode")  private var themeMode     = "dark"
    @AppStorage("accent_color") private var accentHex    = "#30D158"

    @State private var showStreak = false
    @State private var flameScale: CGFloat = 1.0

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentHex) }

    /// Flame color: gray when streak is 0, interpolates to orange as it grows.
    private var flameColor: Color {
        let streak = engine.currentStreak
        if streak == 0 { return .gray.opacity(0.5) }
        if streak < 4  { return .orange.opacity(0.75) }
        if streak < 13 { return .orange }
        return Color(red: 1.0, green: 0.45, blue: 0.1)
    }

    /// The most-recent 7 weekly-activity buckets (oldest → newest).
    private var last7Weeks: [WeekActivity] {
        let sorted = engine.weeklyActivity.sorted { $0.weekStart < $1.weekStart }
        return Array(sorted.suffix(7))
    }

    public init() {}

    public var body: some View {
        Button { showStreak = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(flameColor)
                        .scaleEffect(flameScale)
                        .animation(
                            engine.currentStreak > 0
                                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                                : .default,
                            value: flameScale
                        )
                    Text("Streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(flameColor)
                    Spacer()
                    if engine.longestStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("\(engine.longestStreak)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                        }
                    }
                }

                // Big streak number
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(engine.currentStreak)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .foregroundColor(engine.currentStreak > 0 ? flameColor : (isDark ? .white.opacity(0.35) : .black.opacity(0.35)))
                        .monospacedDigit()
                    Text("week\(engine.currentStreak == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }

                // 7-week mini dot row
                weekDotRow
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if engine.currentStreak > 0 {
                withAnimation {
                    flameScale = 1.12
                }
            }
        }
        .onChange(of: engine.currentStreak) { _, newVal in
            if newVal > 0 {
                withAnimation {
                    flameScale = 1.12
                }
            } else {
                flameScale = 1.0
            }
        }
        .sheet(isPresented: $showStreak) {
            StreakView()
        }
    }

    // MARK: - 7-week dot row

    private var weekDotRow: some View {
        let weeks = last7Weeks
        let cal   = Calendar(identifier: .gregorian)
        let todayMonday = {
            var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            c.weekday = 2
            return cal.date(from: c) ?? Date()
        }()

        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let week: WeekActivity? = (i < weeks.count) ? weeks[max(0, weeks.count - 7 + i)] : nil
                let isThisWeek = week.map { cal.startOfDay(for: $0.weekStart) == cal.startOfDay(for: todayMonday) } ?? false
                let isActive   = week?.isActive ?? false
                let isEmpty    = week == nil

                ZStack {
                    Circle()
                        .fill(
                            isEmpty    ? (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)) :
                            isActive   ? flameColor :
                                        (isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.13))
                        )
                        .frame(width: 22, height: 22)
                    if isThisWeek && !isActive {
                        Circle()
                            .stroke(flameColor.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    }
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
