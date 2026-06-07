import SwiftUI

// Direct SwiftUI ports of the design's metric cards (metrics.jsx).
// Layout, sizes, colors, typography mirror the JSX 1:1.

// MARK: - Shared helpers
enum MetricCardHelpers {
    /// Most-recent 7 values from the metric's history, oldest → newest.
    /// Empty array if no history yet (so callers can hide their chart).
    static func last7(_ summary: MetricSummary?) -> [Double] {
        let sorted = (summary?.history ?? []).sorted { $0.date < $1.date }
        return Array(sorted.suffix(7)).map { $0.value }
    }

    /// Day-of-week single letter for the last N days ending today.
    static func weekLabels(_ count: Int) -> [String] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "EEEEE"
        let today = Date()
        return (0..<count).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { f.string(from: $0) }
        }
    }
}

// MARK: - Chart Primitives

struct SparkChart: View {
    let values: [Double]
    let color: Color
    var dots: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = values.max() ?? 1
            let minV = values.min() ?? 0
            let range = max(maxV - minV, 1)
            let pts = values.enumerated().map { (i, v) -> CGPoint in
                let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                let y = h - CGFloat((v - minV) / range) * (h - 10) - 5
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Fill under line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: pts.last?.x ?? w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))

                // Line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if dots, let last = pts.last {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .position(last)
                }
            }
        }
    }
}

struct BarsChart: View {
    let values: [Double]
    let labels: [String]?
    let color: Color
    var highlight: Int = -1

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxV = values.max() ?? 1
                let bw = w / CGFloat(values.count)
                let inner = bw * 0.55

                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let bh = max(CGFloat(v / maxV) * (h - 4), 4)
                        let isHl = (highlight == -1 ? i == values.count - 1 : i == highlight)
                        RoundedRectangle(cornerRadius: inner / 2)
                            .fill(isHl ? color : (isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)))
                            .frame(width: inner, height: bh)
                            .offset(x: CGFloat(i) * bw + (bw - inner) / 2, y: h - bh)
                    }
                }
            }
            if let labels {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                        Text(l)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Common bits

struct CardHead: View {
    let icon: String
    let title: String
    let color: Color
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct BigNum: View {
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var color: Color? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundColor(color ?? (isDark ? .white : .black))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
        }
    }
}

/// Adaptive header + value block shared by the metric cards.
/// - Narrow (half-width tile): title row on top, big value below (the classic look).
/// - Wide (card is alone on its row): title on the left, value pushed to the
///   right so the card fills the width on purpose instead of looking stretched.
/// Any chart / progress bar the card draws goes *below* this block and spans the
/// full width in both modes.
struct MetricHeaderValue: View {
    let isWide: Bool
    let icon: String
    let title: String
    let color: Color
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var valueColor: Color? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var titleLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func valueBlock(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundColor(valueColor ?? (isDark ? .white : .black))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
        }
    }

    var body: some View {
        if isWide {
            HStack(alignment: .center, spacing: 12) {
                titleLabel
                Spacer(minLength: 8)
                valueBlock(.trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) { titleLabel; Spacer(minLength: 0) }
                valueBlock(.leading)
            }
        }
    }
}

// MARK: - Steps

struct StepsCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    @State private var tapped = false

    var body: some View {
        let value = summary?.currentValue ?? 0
        let pct = Int((summary?.percentComplete ?? 0) * 100)
        let series = MetricCardHelpers.last7(summary)
        return Button(action: { tapped.toggle(); action() }) {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeaderValue(isWide: isWide, icon: "figure.walk", title: "Steps", color: .orange,
                                  value: formatSteps(value),
                                  caption: value > 0 ? "\(pct)% of goal" : "No data yet")
                if !series.isEmpty {
                    BarsChart(values: series, labels: MetricCardHelpers.weekLabels(series.count),
                              color: .orange).frame(height: 42)
                } else if !isWide {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                        .frame(height: 42)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard(cornerRadius: 22)
        }
        .buttonStyle(PlainButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
    }

    private func formatSteps(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))"
    }
}

// MARK: - Heart

struct HeartCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    var body: some View {
        let v = summary?.currentValue ?? 0
        let series = MetricCardHelpers.last7(summary)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeaderValue(isWide: isWide, icon: "heart.fill", title: "Heart", color: .red,
                                  value: v > 0 ? String(format: "%.0f", v) : "—",
                                  unit: v > 0 ? "BPM" : nil,
                                  caption: v > 0 ? "Latest reading" : "No data yet",
                                  valueColor: .red)
                if !series.isEmpty {
                    SparkChart(values: series, color: .red).frame(height: 42)
                } else if !isWide {
                    Color.clear.frame(height: 42)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sleep

struct SleepCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    /// Most recent non-zero history entry — i.e. the night the current value
    /// is from. nil if we never saw any sleep across the 365-day history.
    private var mostRecentNight: MetricValue? {
        summary?.history.last(where: { $0.value > 0 })
    }

    /// Friendly label for when the displayed sleep happened. Today's `Date()`
    /// is when the user is *checking*; sleep that "ended this morning" is
    /// bucketed under today's date by HealthKitManager.
    private func nightLabel(for date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day else {
            return ""
        }
        switch daysAgo {
        case 0: return "Last night"
        case 1: return "Night before"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: date) + " night"
        default:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("MMM d")
            return "Night of " + f.string(from: date)
        }
    }

    var body: some View {
        let hrs = summary?.currentValue ?? 0
        let goal = summary?.goal ?? 8
        let hours = Int(hrs)
        let mins = Int((hrs - Double(hours)) * 60)
        let score = goal > 0 ? Int(min(hrs / goal, 1.0) * 100) : 0
        let hasData = hrs > 0
        let nightDate = mostRecentNight?.date

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                CardHead(icon: "moon.fill", title: "Sleep", color: .purple)
                HStack(spacing: 12) {
                    if isWide { Spacer(minLength: 0) }
                    ZStack {
                        Circle()
                            .stroke(Color.purple.opacity(0.18), lineWidth: 7)
                            .frame(width: 64, height: 64)
                        if hasData {
                            Circle()
                                .trim(from: 0, to: CGFloat(score) / 100)
                                .stroke(Color.purple, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .frame(width: 64, height: 64)
                                .rotationEffect(.degrees(-90))
                            Text("\(score)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white : .black)
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasData ? "\(hours)h \(mins)m" : "No sleep logged")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isDark ? .white : .black)
                        if hasData, let nightDate {
                            Text(nightLabel(for: nightDate))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.purple.opacity(0.85))
                                .lineLimit(1)
                        }
                        Text("Goal: \(Int(goal))h")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Calories

struct CaloriesCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        let v = summary?.currentValue ?? 0
        let goal = summary?.goal ?? 600
        let pct = goal > 0 ? min(v / goal, 1.0) : 0
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeaderValue(isWide: isWide, icon: "bolt.fill", title: "Active Energy", color: .orange,
                                  value: v > 0 ? String(format: "%.0f", v) : "—",
                                  unit: v > 0 ? "KCAL" : nil,
                                  caption: v > 0 ? "Goal \(Int(goal)) kcal" : "No data yet",
                                  valueColor: .orange)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 6)
                Text(v > 0 ? "\(Int(pct * 100))% of goal" : "Burn calories to see progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Today's Meals (wide card)

struct MealsCard: View {
    let entries: [FoodLogEntry]
    let onAddMeal: () -> Void
    var onViewDetails: (() -> Void)? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var totalKcal: Double { entries.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { entries.reduce(0) { $0 + $1.protein } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.orange, .pink],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 24, height: 24)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("TODAY'S MEALS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .tracking(0.5)
                Spacer()
                if let onViewDetails {
                    Button(action: onViewDetails) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(6)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel("View nutrition details")
                }
                Button(action: onAddMeal) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Log a meal")
            }

            if entries.isEmpty {
                Text("No meals logged yet today. Tap + or ask Astra to log one.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .lineSpacing(3)
            } else {
                // Totals
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(totalKcal.rounded()))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("kcal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                    if totalProtein > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(totalProtein.rounded()))")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.pink)
                            Text("g protein")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Items (most recent first)
                VStack(spacing: 0) {
                    ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { idx, entry in
                        if idx > 0 { Divider().opacity(0.15) }
                        MealRow(entry: entry)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}

private struct MealRow: View {
    let entry: FoodLogEntry
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: entry.loggedAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(timeString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    if entry.protein > 0 || entry.carbs > 0 || entry.fat > 0 {
                        Text("·")
                            .foregroundColor(.gray)
                        Text("P \(Int(entry.protein.rounded()))g · C \(Int(entry.carbs.rounded()))g · F \(Int(entry.fat.rounded()))g")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(Int(entry.calories.rounded())) kcal")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.orange)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Distance

struct DistanceCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        let v = summary?.currentValue ?? 0
        let goal = summary?.goal ?? 5.0
        let pct = goal > 0 ? min(v / goal, 1.0) : 0
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeaderValue(isWide: isWide, icon: "arrow.triangle.turn.up.right.diamond.fill", title: "Distance", color: .green,
                                  value: v > 0 ? String(format: "%.2f", v) : "—",
                                  unit: v > 0 ? "MI" : nil,
                                  caption: v > 0 ? "Goal \(String(format: "%.1f", goal)) mi" : "Walk + run combined",
                                  valueColor: .green)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        Capsule()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 6)
                Text(v > 0 ? "\(Int(pct * 100))% of goal" : "Move outside to see progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Hydration

struct HydrationCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        let liters = summary?.currentValue ?? 0
        let goal = summary?.goal ?? 3.0
        // Round instead of truncate — a single 250 ml glass (0.67 of the 8-box
        // visualisation) was rendering as "0 of 8 glasses" before this fix.
        let cups = goal > 0 ? Int(((liters / goal) * 8).rounded()) : 0
        let total = 8

        // ZStack overlay so the quick-add Menu sits on top of the card without
        // interfering with the outer card tap (SwiftUI routes the tap to the
        // innermost interactive view).
        return ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    MetricHeaderValue(isWide: isWide, icon: "drop.fill", title: "Hydration", color: .cyan,
                                      value: liters > 0 ? String(format: "%.1f", liters) : "—",
                                      unit: liters > 0 ? "L" : nil,
                                      caption: liters > 0 ? "\(cups) of \(total) glasses" : "No data yet",
                                      valueColor: .cyan)
                    HStack(spacing: 4) {
                        ForEach(0..<total, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(i < cups ? Color.cyan : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)))
                                .frame(height: 22)
                                .opacity(i < cups ? (0.4 + Double(i) / Double(max(cups, 1)) * 0.6) : 1)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
            .buttonStyle(PlainButtonStyle())

            Menu {
                Button { Task { await log(0.25) } } label: { Label("Glass · 250 ml", systemImage: "cup.and.saucer") }
                Button { Task { await log(0.5)  } } label: { Label("Bottle · 500 ml", systemImage: "waterbottle") }
                Button { Task { await log(1.0)  } } label: { Label("Large · 1 L",    systemImage: "drop.fill") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.cyan)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(10)
        }
    }

    /// Writes a `dietaryWater` quantity sample via HealthKitManager. The
    /// manager's `logMetricValue` re-runs `fetchTodayData()` on success so the
    /// card updates without a manual reload.
    private func log(_ liters: Double) async {
        _ = await HealthKitManager.shared.logMetricValue(type: .hydration, value: liters)
    }
}

// MARK: - Recovery (HRV)

struct RecoveryCard: View {
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        let hrv = summary?.currentValue ?? 0
        let score = Int(min(hrv / 100 * 100, 100))
        let hasData = hrv > 0
        let status: String = {
            if !hasData { return "Awaiting data" }
            if hrv >= 70 { return "Ready to train" }
            if hrv >= 50 { return "Maintain effort" }
            return "Recover today"
        }()

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                CardHead(icon: "arrow.clockwise.heart", title: "Recovery", color: .green)
                HStack(spacing: 12) {
                    if isWide { Spacer(minLength: 0) }
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.18), lineWidth: 7)
                            .frame(width: 64, height: 64)
                        if hasData {
                            Circle()
                                .trim(from: 0, to: CGFloat(score) / 100)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .frame(width: 64, height: 64)
                                .rotationEffect(.degrees(-90))
                            Text("\(score)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white : .black)
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasData ? "HRV \(Int(hrv))ms" : "HRV unavailable")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                            .tracking(0.4)
                        Text(status)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white : .black)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Generic tile used by the "Show more" expansion
// Renders any HealthMetricType with a colored CardHead + BigNum + caption.
// Stretches to row height like the rest so empty + populated tiles match.
struct SimpleMetricCard: View {
    let type: HealthMetricType
    let summary: MetricSummary?
    var isWide: Bool = false
    let action: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var value: Double { summary?.currentValue ?? 0 }
    private var hasData: Bool { value > 0 }
    private var pct: Int {
        let p = summary?.percentComplete ?? 0
        return Int(p * 100)
    }

    private var displayValue: String {
        guard hasData else { return "—" }
        switch type {
        case .bodyMass, .vo2Max,
             .walkingSpeed, .walkingDoubleSupport, .walkingAsymmetry:
            return String(format: "%.1f", value)
        case .oxygenSaturation, .restingEnergy, .walkingStepLength, .headphoneAudio:
            return String(format: "%.0f", value)
        default: return String(format: "%.0f", value)
        }
    }

    private var caption: String {
        guard hasData else { return "No data yet" }
        switch type {
        case .restingHeartRate: return "30-day avg"
        case .bodyMass:         return "Latest"
        case .oxygenSaturation: return "Avg today"
        case .vo2Max:           return "Most recent"
        case .mindfulMinutes:   return "Today"
        case .standHours, .exerciseMinutes, .flightsClimbed: return "\(pct)% of goal"
        case .restingEnergy:    return "Today"
        case .walkingSpeed,
             .walkingStepLength,
             .walkingDoubleSupport,
             .walkingAsymmetry: return "Avg today"
        case .headphoneAudio:   return "Avg today"
        default: return "Today"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeaderValue(isWide: isWide, icon: type.icon, title: type.displayName, color: type.themeColor,
                                  value: displayValue, unit: hasData ? type.unit : nil,
                                  caption: caption, valueColor: type.themeColor)
                if !isWide { Spacer(minLength: 0) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Activity (Move/Exercise/Stand rings)

struct ActivityRingsCard: View {
    let action: () -> Void
    @ObservedObject var hk: HealthKitManager = .shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        // All three rings now pull from real HealthKit values populated by
        // HealthKitManager.fetchTodayData (move = activeEnergy, exercise =
        // appleExerciseTime, stand = appleStandTime). Each ring fills to
        // current / goal; labels show "—" when the value is 0 so users without
        // an Apple Watch see an honest empty state instead of fake zeros.
        let move = hk.metricSummaries[.activeEnergy]?.currentValue ?? 0
        let moveGoal = hk.metricSummaries[.activeEnergy]?.goal ?? 600
        let moveProgress = moveGoal > 0 ? min(move / moveGoal, 1.0) : 0

        let exercise = hk.metricSummaries[.exerciseMinutes]?.currentValue ?? 0
        let exerciseGoal = hk.metricSummaries[.exerciseMinutes]?.goal ?? 30
        let exerciseProgress = exerciseGoal > 0 ? min(exercise / exerciseGoal, 1.0) : 0

        let stand = hk.metricSummaries[.standHours]?.currentValue ?? 0
        let standGoal = hk.metricSummaries[.standHours]?.goal ?? 12
        let standProgress = standGoal > 0 ? min(stand / standGoal, 1.0) : 0

        let exerciseColor = Color(red: 0.62, green: 0.91, blue: 0.19)
        let standColor = Color(red: 0, green: 0.83, blue: 1)

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                CardHead(icon: "flame.fill", title: "Activity", color: .red)
                HStack(spacing: 18) {
                    ZStack {
                        ringTrack(diameter: 110, color: .red)
                        ringFill(diameter: 110, color: .red, progress: moveProgress)
                        ringTrack(diameter: 82, color: exerciseColor)
                        ringFill(diameter: 82, color: exerciseColor, progress: exerciseProgress)
                        ringTrack(diameter: 54, color: standColor)
                        ringFill(diameter: 54, color: standColor, progress: standProgress)
                    }
                    .frame(width: 110, height: 110)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: moveProgress)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: exerciseProgress)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: standProgress)

                    VStack(alignment: .leading, spacing: 10) {
                        ringRow(label: "MOVE",
                                value: move > 0 ? String(format: "%.0f", move) : "—",
                                unit: "/ \(Int(moveGoal)) CAL",
                                color: .red)
                        ringRow(label: "EXERCISE",
                                value: exercise > 0 ? String(format: "%.0f", exercise) : "—",
                                unit: "/ \(Int(exerciseGoal)) MIN",
                                color: exerciseColor)
                        ringRow(label: "STAND",
                                value: stand > 0 ? String(format: "%.0f", stand) : "—",
                                unit: "/ \(Int(standGoal)) HR",
                                color: standColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func ringTrack(diameter: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(color.opacity(0.18), lineWidth: 10)
            .frame(width: diameter, height: diameter)
    }

    private func ringFill(diameter: CGFloat, color: Color, progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(progress))
            .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(-90))
    }

    private func ringRow(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .tracking(0.5)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .tracking(-0.4)
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                Spacer()
            }
        }
    }
}
