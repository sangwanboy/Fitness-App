import SwiftUI

/// Wide Home card surfacing on-device predictions from `PredictionEngine`
/// plus the optional AI enrichment layer (`PredictionAIService`). Time-of-day
/// aware. Each section gracefully degrades when its data isn't present.
public struct PredictionsCard: View {
    public let predictions: Predictions?
    public var onOpenCoach: (() -> Void)? = nil
    /// Fires after `ChatPrefillBus.shared.queue(...)` is set — parent uses
    /// it to switch to the Coach tab.
    public var onTapActionChip: (() -> Void)? = nil
    /// Opens the Guided Breathing modal. Non-nil when the parent (DashboardView)
    /// has wired up a showBreathing toggle.
    public var onOpenBreathe: (() -> Void)? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var whyKind: PredictionKind? = nil

    public init(predictions: Predictions?,
                onOpenCoach: (() -> Void)? = nil,
                onTapActionChip: (() -> Void)? = nil,
                onOpenBreathe: (() -> Void)? = nil) {
        self.predictions = predictions
        self.onOpenCoach = onOpenCoach
        self.onTapActionChip = onTapActionChip
        self.onOpenBreathe = onOpenBreathe
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let p = predictions {
                if let waiting = p.insufficientHistoryDays, waiting > 0 {
                    baselineState(daysRemaining: waiting)
                } else if p.isEmpty {
                    quietState
                } else {
                    // Anomaly banner — top, severity-colored
                    ForEach(p.anomalies) { anomaly in
                        AnomalyBanner(anomaly: anomaly)
                    }

                    sectionsForCurrentTimeOfDay(p)

                    // AI insight row
                    if let insight = p.dailyInsight {
                        Divider().opacity(0.15)
                        DailyInsightRow(insight: insight)
                    }

                    // AI action chips
                    if !p.actions.isEmpty {
                        Divider().opacity(0.15)
                        ActionChipsRow(actions: p.actions, onTap: handleActionTap)
                    }

                    // Retry-insights chip on failed AI
                    if p.aiEnrichmentStatus == .failed {
                        Divider().opacity(0.15)
                        retryRow
                    }
                }
            } else {
                quietState
            }

            // Breathe chip — always visible when the parent wires onOpenBreathe
            if let openBreathe = onOpenBreathe {
                Divider().opacity(0.15)
                breatheChip(action: openBreathe)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .sheet(item: $whyKind) { kind in
            if let p = predictions {
                PredictionWhySheet(kind: kind, predictions: p)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("PREDICTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .tracking(0.5)
            if let p = predictions, p.aiEnrichmentStatus == .pending,
               p.insufficientHistoryDays == nil {
                PulsingThinkingLabel()
            }
            Spacer()
            if let onOpenCoach {
                Button(action: onOpenCoach) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Ask Astra about this")
            }
        }
    }

    // MARK: - Building baseline

    private func baselineState(daysRemaining: Int) -> some View {
        let totalNeeded = 7
        let have = max(0, totalNeeded - daysRemaining)
        let progress = Double(have) / Double(totalNeeded)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Building your baseline")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
            Text("Day \(have) of \(totalNeeded). Predictions unlock once we have a week of history to compare against.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                .lineSpacing(3)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.indigo)
                .padding(.top, 2)
        }
    }

    // MARK: - Quiet state

    private var quietState: some View {
        Text("All quiet. No notable signals from your last 28 days.")
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(isDark ? .white.opacity(0.65) : .black.opacity(0.65))
            .lineSpacing(3)
    }

    // MARK: - Retry row

    private var retryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("AI insights unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
            Spacer()
            Button(action: { HealthKitManager.shared.retryAIEnrichment() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    // MARK: - Breathe chip

    @ViewBuilder
    private func breatheChip(action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.teal)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Guided Breathing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text("Box · 4-7-8 · Coherent · Custom")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            Spacer()
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "lungs.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Breathe")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Time-of-day section picker

    private enum DaySlot { case morning, midday, evening, night }

    private func currentSlot() -> DaySlot {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return .morning
        case 11..<15: return .midday
        case 15..<21: return .evening
        default: return .night
        }
    }

    @ViewBuilder
    private func sectionsForCurrentTimeOfDay(_ p: Predictions) -> some View {
        let slot = currentSlot()
        let h = Calendar.current.component(.hour, from: Date())
        let blocks = orderedBlocks(for: slot, in: p, currentHour: h)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                block
                if idx < blocks.count - 1 {
                    Divider().opacity(0.15)
                }
            }
        }
    }

    /// Picks up to 4 prediction sections — Health Meter is always first
    /// (when present); the slot picker fills the rest with timely context.
    private func orderedBlocks(for slot: DaySlot,
                               in p: Predictions,
                               currentHour: Int) -> [AnyView] {
        var rows: [AnyView] = []
        let openWhy: (PredictionKind) -> Void = { kind in
            whyKind = kind
        }
        // Health Meter is the headline — always shown when available.
        if let m = p.healthMeter {
            rows.append(AnyView(HealthMeterRow(meter: m, onWhy: { openWhy(.healthMeter) })))
        }
        switch slot {
        case .morning:
            if let r = p.recovery { rows.append(AnyView(RecoveryRow(reading: r, onWhy: { openWhy(.recovery) }))) }
            if let n = p.nextWorkout { rows.append(AnyView(NextWorkoutRow(forecast: n, onWhy: { openWhy(.nextWorkout) }))) }
            if currentHour >= 9, let s = p.sedentary { rows.append(AnyView(SedentaryRow(alert: s, onWhy: { openWhy(.sedentary) }))) }
        case .midday:
            for t in p.trajectories.prefix(2) { rows.append(AnyView(TrajectoryRow(trajectory: t, onWhy: { openWhy(.trajectory) }))) }
            if let s = p.sedentary { rows.append(AnyView(SedentaryRow(alert: s, onWhy: { openWhy(.sedentary) }))) }
        case .evening:
            for t in p.trajectories.prefix(2) { rows.append(AnyView(TrajectoryRow(trajectory: t, onWhy: { openWhy(.trajectory) }))) }
            if let s = p.sedentary { rows.append(AnyView(SedentaryRow(alert: s, onWhy: { openWhy(.sedentary) }))) }
            if rows.count == 1, let r = p.recovery {
                rows.append(AnyView(RecoveryRow(reading: r, onWhy: { openWhy(.recovery) })))
            }
        case .night:
            if let n = p.nextWorkout { rows.append(AnyView(NextWorkoutRow(forecast: n, onWhy: { openWhy(.nextWorkout) }))) }
            if let r = p.recovery { rows.append(AnyView(RecoveryRow(reading: r, onWhy: { openWhy(.recovery) }))) }
        }
        return Array(rows.prefix(4))
    }

    private func handleActionTap(_ action: ActionSuggestion) {
        ChatPrefillBus.shared.queue(action.prefillPrompt)
        onTapActionChip?()
    }
}

// MARK: - "Thinking…" pulsing label (replaces the lone sparkle indicator)

private struct PulsingThinkingLabel: View {
    @State private var opacity: Double = 1.0
    var body: some View {
        Text("Thinking…")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.indigo)
            .tracking(0.3)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                    opacity = 0.35
                }
            }
            .accessibilityLabel("AI insights loading")
    }
}

// MARK: - Why button (per-row trigger)

private struct WhyButton: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                Text("Why?")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.indigo)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Why this prediction")
    }
}

// MARK: - Health Meter row (composite wellness score)

private struct HealthMeterRow: View {
    let meter: HealthMeterScore
    let onWhy: () -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    @State private var ringProgress: CGFloat = 0

    private var labelColor: Color {
        switch meter.label {
        case .excellent: return .green
        case .good:      return Color(red: 0.62, green: 0.91, blue: 0.19)
        case .fair:      return .orange
        case .needsWork: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(labelColor.opacity(0.18), lineWidth: 7)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: ringProgress * CGFloat(meter.score) / 100)
                        .stroke(labelColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    Text("\(meter.score)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Health Meter")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.indigo)
                        Text("·")
                            .foregroundColor(.gray)
                        Text(meter.label.headline)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(labelColor)
                        Spacer()
                        WhyButton(onTap: onWhy)
                    }
                    if let first = meter.explanation.bullets.first {
                        Text(first)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 4) {
                        Text(meter.confidence.displayLabel.lowercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                        if !meter.usedNutrition {
                            Text("· no meals logged")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                        }
                        if !meter.usedBMI {
                            Text("· no height/weight")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            // Sub-score breakdown — stacked tiny bars so the user sees which
            // dimension is contributing what.
            VStack(spacing: 4) {
                SubScoreBar(label: "Activity", value: meter.activityScore, max: 30, color: .orange)
                SubScoreBar(label: "Nutrition", value: meter.nutritionScore, max: 30, color: .green)
                SubScoreBar(label: "Body", value: meter.bodyScore, max: 18, color: .purple)
                SubScoreBar(label: "Vitals", value: meter.vitalsScore, max: 22, color: .pink)
            }
            .padding(.top, 2)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1)) {
                ringProgress = 1
            }
        }
    }
}

private struct SubScoreBar: View {
    let label: String
    let value: Int
    let max: Int
    let color: Color
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    @State private var barScale: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: Swift.max(4, geo.size.width * CGFloat(value) / CGFloat(max) * barScale))
                }
            }
            .frame(height: 5)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25)) {
                    barScale = 1
                }
            }
            Text("\(value)/\(max)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Recovery row

private struct RecoveryRow: View {
    let reading: RecoveryReadiness
    let onWhy: () -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    @State private var ringProgress: CGFloat = 0

    private var labelColor: Color {
        switch reading.label {
        case .strong: return .green
        case .moderate: return Color(red: 0.62, green: 0.91, blue: 0.19)
        case .low: return .orange
        case .rest: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(labelColor.opacity(0.18), lineWidth: 6)
                    .frame(width: 54, height: 54)
                Circle()
                    .trim(from: 0, to: ringProgress * CGFloat(reading.score) / 100)
                    .stroke(labelColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(-90))
                Text("\(reading.score)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Recovery")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                    Text("·")
                        .foregroundColor(.gray)
                    Text(reading.label.headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(labelColor)
                    Spacer()
                    WhyButton(onTap: onWhy)
                }
                if let first = reading.explanation.bullets.first {
                    Text(first)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                        .lineLimit(2)
                        .lineSpacing(2)
                }
                if !reading.usedHRV && !reading.usedRHR {
                    Text("Estimated from sleep + load · \(reading.confidence.displayLabel.lowercased())")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.75).delay(0.15)) {
                ringProgress = 1
            }
        }
    }
}

// MARK: - Next workout row

private struct NextWorkoutRow: View {
    let forecast: NextWorkoutForecast
    let onWhy: () -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .hour, value: forecast.startHour, to: today) ?? today
        let end = cal.date(byAdding: .hour, value: forecast.endHour, to: today) ?? today
        return "\(f.string(from: start))–\(f.string(from: end))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: forecast.category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.indigo)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Likely workout · \(forecast.weekdayLabel)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                    Spacer()
                    WhyButton(onTap: onWhy)
                }
                Text(forecast.isCategoryFallback
                     ? "You usually train around \(timeLabel)"
                     : "\(forecast.category.displayName) · \(timeLabel)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                Text("\(forecast.confidence.displayLabel) · \(Int(forecast.support * 100))% of recent weeks")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Goal trajectory row

private struct TrajectoryRow: View {
    let trajectory: GoalTrajectory
    let onWhy: () -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var statusColor: Color {
        switch trajectory.status {
        case .aheadOfPace: return .green
        case .onPace: return Color(red: 0.62, green: 0.91, blue: 0.19)
        case .behind: return .orange
        case .farBehind: return .red
        }
    }

    private func format(_ v: Double, for metric: HealthMetricType) -> String {
        switch metric {
        case .steps, .activeEnergy, .exerciseMinutes:
            return String(format: "%.0f", v)
        default:
            return String(format: "%.1f", v)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(trajectory.metric.themeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: trajectory.metric.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(trajectory.metric.themeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trajectory.metric.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(trajectory.metric.themeColor)
                    Text("·")
                        .foregroundColor(.gray)
                    Text(trajectory.status.headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)
                    Spacer()
                    WhyButton(onTap: onWhy)
                }
                Text("Projected \(format(trajectory.projectedEOD, for: trajectory.metric)) \(trajectory.metric.unit) · avg \(format(trajectory.baselineEOD, for: trajectory.metric))")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sedentary alert row

private struct SedentaryRow: View {
    let alert: SedentaryAlert
    let onWhy: () -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var severityColor: Color {
        switch alert.severity {
        case .moderate: return .orange
        case .high: return .red
        }
    }

    private var headline: String {
        "\(alert.quietHours)h since your last walk"
    }

    private var subtext: String {
        if let h = alert.lastActiveHour {
            let f = DateFormatter()
            f.dateFormat = "h a"
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let when = cal.date(byAdding: .hour, value: h, to: today) ?? today
            return "Last 250+ step hour: \(f.string(from: when)). A 5-min walk now keeps the streak."
        }
        return "Quiet morning. A short walk now sets the tone."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(severityColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Move reminder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(severityColor)
                    Spacer()
                    WhyButton(onTap: onWhy)
                }
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text(subtext)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Anomaly banner

private struct AnomalyBanner: View {
    let anomaly: Anomaly
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var color: Color {
        switch anomaly.severity {
        case .high: return .red
        case .moderate: return .orange
        case .low: return .yellow
        }
    }

    private var headline: String {
        let dir = anomaly.direction == "low" ? "below" : "above"
        return "\(anomaly.metric.displayName) is \(dir) your usual"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                if let text = anomaly.interpretation {
                    Text(text)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                        .lineSpacing(2)
                } else {
                    Text("Today: \(String(format: "%.1f", anomaly.today)) \(anomaly.metric.unit) · 28-day baseline: \(String(format: "%.1f", anomaly.baseline)) \(anomaly.metric.unit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Daily insight (AI)

private struct DailyInsightRow: View {
    let insight: DailyInsight
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's insight")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
                Text(insight.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Action chips (AI)

private struct ActionChipsRow: View {
    let actions: [ActionSuggestion]
    let onTap: (ActionSuggestion) -> Void
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private func color(for category: ActionCategory) -> Color {
        switch category {
        case .workout: return .blue
        case .nutrition: return .orange
        case .recovery: return .purple
        case .planning: return .indigo
        case .other: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested moves")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.indigo)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button(action: { onTap(action) }) {
                            HStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(color(for: action.category))
                                Text(action.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isDark ? .white : .black)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
