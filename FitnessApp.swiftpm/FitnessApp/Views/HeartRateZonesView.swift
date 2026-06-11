import SwiftUI
import HealthKit

// MARK: - HeartRateZonesView

public struct HeartRateZonesView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var hk = HealthKitManager.shared
    @ObservedObject private var zoneCalc = HeartRateZoneCalculator.shared

    @AppStorage("theme_mode")   private var themeMode   = "dark"
    @AppStorage("accent_color") private var accentHex   = "#30D158"
    @AppStorage("athlete_dob")  private var athleteDobTs: Double = 0
    @AppStorage("max_hr_override") private var maxHROverride: Int = 0

    @State private var animateEntry      = false
    @State private var showThresholds    = false
    @State private var maxHRStepper      = 180
    @State private var hasInitStepper    = false

    private var isDark:      Bool  { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentHex) }

    private var userAge: Int {
        guard athleteDobTs > 0 else { return 30 }
        let dob = Date(timeIntervalSince1970: athleteDobTs)
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 30
    }

    private var thresholds: ZoneThresholds { zoneCalc.makeThresholds(userAge: userAge) }

    // Workouts with at least 1 HR sample (has a non-empty breakdown).
    private var zonesWithData: [WorkoutZoneBreakdown] {
        zoneCalc.breakdowns.filter { !$0.durationByZone.isEmpty }
    }

    // This-week workouts (Mon–Sun).
    private let currentWeekStart: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
            ?? Date().addingTimeInterval(-7 * 86400)
    }()

    private var weeklyBreakdowns: [WorkoutZoneBreakdown] {
        return zonesWithData.filter { $0.workoutDate >= currentWeekStart }
    }

    // Aggregate seconds per zone across the current week.
    private var weeklyZoneTotals: [HRZone: TimeInterval] {
        var totals: [HRZone: TimeInterval] = [:]
        for bd in weeklyBreakdowns {
            for (zone, secs) in bd.durationByZone {
                totals[zone, default: 0] += secs
            }
        }
        return totals
    }

    private var weeklyTotalSeconds: TimeInterval {
        weeklyZoneTotals.values.reduce(0, +)
    }

    // MARK: - Body

    public init() {}

    public var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    headerBar
                        .padding(.horizontal)
                        .padding(.top, 16)

                    if zoneCalc.isLoading {
                        loadingState
                    } else if zonesWithData.isEmpty {
                        emptyState
                    } else {
                        weeklyRingSection
                            .padding(.horizontal)

                        perWorkoutSection
                            .padding(.horizontal)
                    }

                    thresholdEditorSection
                        .padding(.horizontal)
                        .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            if !hasInitStepper {
                maxHRStepper = maxHROverride > 0 ? maxHROverride : (220 - userAge)
                hasInitStepper = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animateEntry = true
            }
            Task {
                await zoneCalc.computeZoneBreakdowns(
                    for: hk.recentWorkouts28,
                    userAge: userAge
                )
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("HR Zones")
                        .font(.title2.bold())
                        .foregroundColor(isDark ? .white : .black)
                    Text("28-day workout analysis")
                        .font(.caption)
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Loading / Empty

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(accentColor)
            Text("Analysing HR zones…")
                .font(.caption)
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            Text("No HR Data Found")
                .font(.headline)
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
            Text("Complete workouts with an Apple Watch or heart-rate monitor. HR samples are required for zone analysis.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Section 1: Weekly Zone Ring

    private var weeklyRingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "This Week's Zone Distribution",
                          subtitle: weeklyTotalSeconds > 0
                            ? formattedDuration(weeklyTotalSeconds) + " total active"
                            : "No workouts this week")

            if weeklyTotalSeconds > 0 {
                HStack(alignment: .center, spacing: 24) {
                    // Concentric arc ring
                    ZoneRingView(
                        zoneTotals: weeklyZoneTotals,
                        totalSeconds: weeklyTotalSeconds,
                        animated: animateEntry
                    )
                    .frame(width: 140, height: 140)

                    // Legend
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(HRZone.allCases) { zone in
                            let secs = weeklyZoneTotals[zone] ?? 0
                            let pct = weeklyTotalSeconds > 0
                                ? secs / weeklyTotalSeconds
                                : 0

                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zone.color)
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(zone.displayName)  \(zone.description)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                                    Text(secs > 0 ? "\(formattedDuration(secs))  ·  \(Int((pct * 100).rounded()))%" : "—")
                                        .font(.system(size: 10))
                                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            } else {
                Text("Complete a workout this week to see zone distribution.")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                    .padding(.vertical, 8)
            }
        }
        .glassCard()
        .opacity(animateEntry ? 1 : 0)
        .offset(y: animateEntry ? 0 : 20)
    }

    // MARK: - Section 2: Per-Workout Zone Bars

    private var perWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Workout Breakdown",
                          subtitle: "\(zonesWithData.count) workout\(zonesWithData.count == 1 ? "" : "s") with HR data")

            LazyVStack(spacing: 12) {
                ForEach(zonesWithData.prefix(20)) { bd in
                    WorkoutZoneRowView(breakdown: bd, isDark: isDark)
                }
            }
        }
        .glassCard()
        .opacity(animateEntry ? 1 : 0)
        .offset(y: animateEntry ? 0 : 15)
    }

    // MARK: - Section 3: Threshold Editor

    private var thresholdEditorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showThresholds) {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        .padding(.top, 4)

                    // Max HR stepper
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max Heart Rate Override")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                            Text(maxHROverride > 0
                                 ? "Manual: \(maxHROverride) bpm"
                                 : "Auto: 220 − \(userAge) = \(220 - userAge) bpm")
                                .font(.caption)
                                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                        Spacer()
                        Stepper("", value: $maxHRStepper, in: 140...220)
                            .labelsHidden()
                            .onChange(of: maxHRStepper) { _, newVal in
                                let defaultVal = 220 - userAge
                                maxHROverride = newVal == defaultVal ? 0 : newVal
                                zoneCalc.maxHROverride = maxHROverride
                                Task {
                                    await zoneCalc.computeZoneBreakdowns(
                                        for: hk.recentWorkouts28,
                                        userAge: userAge
                                    )
                                }
                            }

                        Text("\(maxHRStepper)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                            .frame(width: 38, alignment: .trailing)
                    }

                    // Zone BPM ranges
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zone BPM Ranges")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                            .tracking(1.2)

                        ForEach(HRZone.allCases) { zone in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(zone.color)
                                    .frame(width: 8, height: 8)

                                Text("\(zone.displayName) — \(zone.description)")
                                    .font(.system(size: 13))
                                    .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.75))

                                Spacer()

                                Text(thresholds.rangeLabel(for: zone))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(zone.color)
                            }
                        }
                    }
                    .padding(.top, 4)

                    // Resting HR note
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                        let rhrDisplay: String = {
                            if let rhr = hk.metricSummaries[.restingHeartRate]?.currentValue, rhr > 0 {
                                return "\(Int(rhr.rounded())) bpm"
                            }
                            return "— (estimated)"
                        }()
                        Text("Resting HR: \(rhrDisplay)  ·  Formula: Karvonen")
                            .font(.caption2)
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(accentColor)
                    Text("Zone Thresholds")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                }
            }
            .accentColor(accentColor)
        }
        .glassCard()
        .opacity(animateEntry ? 1 : 0)
        .offset(y: animateEntry ? 0 : 10)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isDark ? .white : .black)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
    }

    private func formattedDuration(_ secs: TimeInterval) -> String {
        let m = Int(secs / 60)
        if m < 60 { return "\(m) min" }
        let h = m / 60; let rem = m % 60
        return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
    }
}

// MARK: - ZoneRingView (five concentric arcs via Canvas)

private struct ZoneRingView: View {
    let zoneTotals:   [HRZone: TimeInterval]
    let totalSeconds: TimeInterval
    let animated:     Bool

    @State private var progress: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - 2
            let strokeWidth: CGFloat = 10
            let gap: CGFloat = 4

            for (ringIdx, zone) in HRZone.allCases.reversed().enumerated() {
                let r = outerRadius - CGFloat(ringIdx) * (strokeWidth + gap)
                guard r > 0 else { continue }

                let secs  = zoneTotals[zone] ?? 0
                let ratio = totalSeconds > 0 ? min(secs / totalSeconds, 1) * progress : 0

                // Background track
                let trackPath = Path { p in
                    p.addArc(center: center, radius: r,
                             startAngle: .degrees(-90),
                             endAngle: .degrees(270),
                             clockwise: false)
                }
                ctx.stroke(trackPath,
                           with: .color(zone.color.opacity(0.15)),
                           style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

                if ratio > 0 {
                    let endAngle = -90 + 360 * ratio
                    let fillPath = Path { p in
                        p.addArc(center: center, radius: r,
                                 startAngle: .degrees(-90),
                                 endAngle: .degrees(endAngle),
                                 clockwise: false)
                    }
                    ctx.stroke(fillPath,
                               with: .color(zone.color),
                               style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                }
            }
        }
        .onChange(of: animated) { _, newVal in
            if newVal {
                withAnimation(.easeOut(duration: 1.1)) {
                    progress = 1
                }
            }
        }
        .onAppear {
            if animated {
                withAnimation(.easeOut(duration: 1.1)) {
                    progress = 1
                }
            }
        }
    }
}

// MARK: - WorkoutZoneRowView

private struct WorkoutZoneRowView: View {
    let breakdown: WorkoutZoneBreakdown
    let isDark:    Bool

    private var workoutTitle: String {
        switch breakdown.workout.workoutActivityType {
        case .running:
            return "Outdoor Run"
        case .walking:
            return "Walk"
        case .cycling:
            return "Cycling"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining,
             .crossTraining:
            return "Strength"
        case .hiking:
            return "Hike"
        case .swimming:
            return "Swim"
        case .yoga:
            return "Yoga"
        default:
            return "Workout"
        }
    }

    private var workoutIcon: String {
        switch breakdown.workout.workoutActivityType {
        case .running:    return "figure.run"
        case .walking:    return "figure.walk"
        case .cycling:    return "figure.outdoor.cycle"
        case .hiking:     return "figure.hiking"
        case .swimming:   return "figure.open.water.swim"
        case .yoga:       return "figure.yoga"
        default:          return "figure.strengthtraining.functional"
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: breakdown.workoutDate)
    }

    private var durationLabel: String {
        let m = Int(breakdown.workout.duration / 60)
        return "\(m) min"
    }

    private var dominantColor: Color {
        breakdown.dominantZone?.color ?? .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(dominantColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: workoutIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(dominantColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let dom = breakdown.dominantZone {
                        Text(dom.description)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(dom.color)
                    }
                    Text(durationLabel)
                        .font(.caption2)
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }

            // Segmented zone bar
            ZoneSegmentBar(breakdown: breakdown)
                .frame(height: 10)
                .clipShape(Capsule())

            // Zone time mini-legend
            HStack(spacing: 0) {
                ForEach(HRZone.allCases) { zone in
                    let secs = breakdown.durationByZone[zone] ?? 0
                    if secs > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 5, height: 5)
                            Text(miniDuration(secs))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        }
                        .padding(.trailing, 8)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func miniDuration(_ secs: TimeInterval) -> String {
        let m = Int(secs / 60)
        if m == 0 { return "<1m" }
        return "\(m)m"
    }
}

// MARK: - ZoneSegmentBar

private struct ZoneSegmentBar: View {
    let breakdown: WorkoutZoneBreakdown

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                let total = breakdown.totalActiveSeconds
                ForEach(HRZone.allCases) { zone in
                    let secs = breakdown.durationByZone[zone] ?? 0
                    if secs > 0 {
                        let fraction = total > 0 ? secs / total : 0
                        Rectangle()
                            .fill(zone.color)
                            .frame(width: max(geo.size.width * CGFloat(fraction), 2))
                    }
                }
            }
        }
    }
}

// MARK: - WorkoutZoneSummaryCard (compact card for WorkoutTrackerView list)

/// Embeddable zone summary card for a single workout. Used inside
/// WorkoutTrackerView's history list alongside `WorkoutRecordRowView`.
public struct WorkoutZoneSummaryCard: View {
    public let breakdown: WorkoutZoneBreakdown
    public let isDark:    Bool

    public init(breakdown: WorkoutZoneBreakdown, isDark: Bool) {
        self.breakdown = breakdown
        self.isDark    = isDark
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Mini segmented bar
            ZoneSegmentBar(breakdown: breakdown)
                .frame(height: 8)
                .clipShape(Capsule())

            // Zone chips row
            HStack(spacing: 6) {
                ForEach(HRZone.allCases) { zone in
                    let secs = breakdown.durationByZone[zone] ?? 0
                    if secs > 0 {
                        Text("\(zone.displayName) \(miniMin(secs))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(zone.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(zone.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func miniMin(_ secs: TimeInterval) -> String {
        let m = Int(secs / 60)
        return m == 0 ? "<1m" : "\(m)m"
    }
}
