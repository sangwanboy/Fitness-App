import SwiftUI
import Charts
import HealthKit

// MARK: - Main Analytics Sheet

public struct WorkoutAnalyticsView: View {
    @StateObject private var engine = TrainingLoadEngine()
    @ObservedObject private var hk = HealthKitManager.shared

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @State private var showACWRInfo = false

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if engine.isComputing {
                    loadingView
                } else if hk.recentWorkouts28.isEmpty {
                    emptyStateView
                } else {
                    analyticsContent
                }
            }
            .navigationTitle("Training Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        engine.compute(from: hk.recentWorkouts28)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(accentColor)
                    }
                }
            }
        }
        .onAppear {
            engine.compute(from: hk.recentWorkouts28)
        }
        .onChange(of: hk.recentWorkouts28.count) { _, _ in
            engine.compute(from: hk.recentWorkouts28)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(accentColor)
            Text("Computing training load…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundColor(accentColor.opacity(0.7))
            Text("No Workout Data")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isDark ? .white : .black)
            Text("Complete at least one workout to see training analytics.")
                .font(.system(size: 14))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Main content

    private var analyticsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                acwrHeroCard
                loadChartSection
                weeklyVolumeSection
                personalRecordsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Section 1: ACWR Hero Card

    private var acwrHeroCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("TRAINING READINESS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .tracking(1.5)
                        Button {
                            showACWRInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        }
                        .popover(isPresented: $showACWRInfo) {
                            ACWRInfoPopover()
                        }
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", engine.acwr))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(zoneColor(engine.acwrZone))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: engine.acwr)

                        Text("ACWR")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .padding(.bottom, 6)
                    }

                    Text(engine.acwrZone.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Zone badge
                VStack(spacing: 4) {
                    Image(systemName: zoneSFSymbol(engine.acwrZone))
                        .font(.system(size: 28))
                        .foregroundColor(zoneColor(engine.acwrZone))
                    Text(engine.acwrZone.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(zoneColor(engine.acwrZone))
                }
                .padding(.top, 4)
            }

            Divider()
                .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))

            HStack(spacing: 0) {
                loadStatPill(label: "Acute (7d)", value: String(format: "%.0f", engine.acuteLoad), unit: "kcal/d")
                Spacer()
                loadStatPill(label: "Chronic (28d)", value: String(format: "%.0f", engine.chronicLoad), unit: "kcal/d")
                Spacer()
                loadStatPill(label: "Active Days", value: "\(activeDaysCount)", unit: "of 28")
            }
        }
        .padding(16)
        .glassCard()
    }

    private var activeDaysCount: Int {
        engine.dailyLoads.filter { $0.load > 0 }.count
    }

    private func loadStatPill(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                .tracking(0.5)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
    }

    // MARK: - Section 2: 28-Day Load Chart

    private struct RollingPoint: Identifiable {
        let id: Date
        let date: Date
        let acute: Double
        let chronic: Double
    }

    private var precomputedRollingSeries: [RollingPoint] {
        engine.dailyLoads.enumerated().map { idx, point in
            RollingPoint(
                id: point.date,
                date: point.date,
                acute: rollingMean(upTo: idx, window: 7),
                chronic: rollingMean(upTo: idx, window: 28)
            )
        }
    }

    private var loadChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "28-Day Training Load", icon: "chart.line.uptrend.xyaxis")

            if engine.dailyLoads.isEmpty {
                Text("No load data for this period")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            } else {
                let rollingSeries = precomputedRollingSeries
                Chart {
                    // Area fill under chronic line for depth
                    ForEach(engine.dailyLoads) { point in
                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Load", point.load)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 0))
                    }

                    // Raw daily load bars (subtle)
                    ForEach(engine.dailyLoads) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Daily Load", point.load)
                        )
                        .foregroundStyle(accentColor.opacity(0.22))
                        .cornerRadius(3)
                    }

                    // Acute line (7-day rolling) — accent color
                    ForEach(rollingSeries) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Acute (7d)", point.acute),
                            series: .value("Series", "Acute")
                        )
                        .foregroundStyle(accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    // Chronic line (28-day rolling) — gray
                    ForEach(rollingSeries) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Chronic (28d)", point.chronic),
                            series: .value("Series", "Chronic")
                        )
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                            .foregroundStyle(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                            .foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .font(.system(size: 10))
                    }
                }
                .frame(height: 170)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: engine.dailyLoads.count)

                // Legend
                HStack(spacing: 16) {
                    legendDot(color: accentColor, label: "Acute (7d)")
                    legendDot(color: .gray.opacity(0.7), label: "Chronic (28d)", dashed: true)
                    Spacer()
                    Text("kcal load")
                        .font(.system(size: 10))
                        .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func rollingMean(upTo index: Int, window: Int) -> Double {
        let loads = engine.dailyLoads
        guard index >= 0, index < loads.count else { return 0 }
        let start = max(0, index - window + 1)
        let slice = loads[start...index]
        let values = slice.map { $0.load }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Section 3: Weekly Volume Bars

    private var weeklyVolumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Weekly Volume", icon: "chart.bar.fill")

            if engine.weeklyVolumes.isEmpty {
                Text("No workout weeks recorded yet")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(engine.weeklyVolumes) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Load", week.totalLoad)
                    )
                    .foregroundStyle(
                        week.isCurrentWeek
                            ? AnyShapeStyle(accentColor.gradient)
                            : AnyShapeStyle(Color.gray.opacity(0.4))
                    )
                    .cornerRadius(5)
                    .annotation(position: .top, alignment: .center) {
                        if week.isCurrentWeek {
                            Text("Now")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accentColor)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { val in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                            .foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .font(.system(size: 10))
                    }
                }
                .frame(height: 140)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: engine.weeklyVolumes.count)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Section 4: Personal Records

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Personal Records", icon: "trophy.fill")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                spacing: 12
            ) {
                PRTile(
                    icon: "timer",
                    title: "Longest Session",
                    value: longestDurationText,
                    subtitle: longestDateText,
                    color: accentColor
                )

                PRTile(
                    icon: "flame.fill",
                    title: "Peak Calories",
                    value: highestCaloriesText,
                    subtitle: highCalDateText,
                    color: .orange
                )

                PRTile(
                    icon: "calendar.badge.checkmark",
                    title: "Active Days/Wk",
                    value: "\(engine.personalRecords.mostActiveDaysInWeek)",
                    subtitle: "best single week",
                    color: .cyan
                )

                PRTile(
                    icon: "repeat.circle.fill",
                    title: "Week Streak",
                    value: "\(engine.personalRecords.currentWeekStreak)",
                    subtitle: engine.personalRecords.currentWeekStreak == 1 ? "week in a row" : "weeks in a row",
                    color: Color(red: 0.68, green: 0.52, blue: 0.98)
                )
            }
        }
        .padding(16)
        .glassCard()
    }

    // PR value helpers
    private var longestDurationText: String {
        guard let w = engine.personalRecords.longestWorkout else { return "—" }
        let minutes = Int(w.duration / 60)
        if minutes >= 60 {
            return String(format: "%dh %dm", minutes / 60, minutes % 60)
        }
        return "\(minutes) min"
    }

    private var longestDateText: String {
        guard let w = engine.personalRecords.longestWorkout else { return "No data" }
        return shortDateLabel(w.startDate)
    }

    private var highestCaloriesText: String {
        guard let w = engine.personalRecords.highestCalories,
              let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
              kcal > 0 else { return "—" }
        return String(format: "%.0f kcal", kcal)
    }

    private var highCalDateText: String {
        guard let w = engine.personalRecords.highestCalories else { return "No data" }
        return shortDateLabel(w.startDate)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Reusable sub-views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accentColor)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                .tracking(1.0)
        }
    }

    private func legendDot(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().frame(width: 6, height: 2)
                    Rectangle().frame(width: 4, height: 2).opacity(0)
                    Rectangle().frame(width: 4, height: 2)
                }
                .foregroundColor(color)
                .frame(width: 16, height: 2)
            } else {
                Rectangle()
                    .frame(width: 16, height: 2)
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
    }

    private func zoneColor(_ zone: ACWRZone) -> Color {
        switch zone {
        case .optimal:   return .green
        case .caution:   return .orange
        case .overreach: return .red
        case .low:       return .blue
        }
    }

    private func zoneSFSymbol(_ zone: ACWRZone) -> String {
        switch zone {
        case .optimal:   return "checkmark.seal.fill"
        case .caution:   return "exclamationmark.triangle.fill"
        case .overreach: return "xmark.octagon.fill"
        case .low:       return "arrow.up.circle.fill"
        }
    }
}

// MARK: - PR Tile

private struct PRTile: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: value)
    }
}

// MARK: - ACWR Info Popover

private struct ACWRInfoPopover: View {
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What is ACWR?")
                .font(.headline)
                .foregroundColor(isDark ? .white : .black)

            VStack(alignment: .leading, spacing: 10) {
                bulletPoint(
                    number: "1",
                    text: "ACWR is the Acute:Chronic Workload Ratio — a science-backed indicator of training stress vs. fitness.",
                    color: .blue
                )
                bulletPoint(
                    number: "2",
                    text: "Acute load = your 7-day rolling average. Chronic load = your 28-day rolling average. ACWR = Acute ÷ Chronic.",
                    color: .orange
                )
                bulletPoint(
                    number: "3",
                    text: "0.8–1.3 is the optimal \"sweet spot\". Above 1.5 indicates overreach; below 0.8 suggests under-training. Adjust your schedule accordingly.",
                    color: .green
                )
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    private func bulletPoint(number: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(color)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
