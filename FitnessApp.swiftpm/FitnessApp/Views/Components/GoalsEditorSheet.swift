import SwiftUI

/// Bottom sheet that lets the user tune their daily goals for the 9 metrics
/// that are actual behavioral targets (steps, calories, sleep, hydration,
/// etc). Reads / writes via `HealthKitManager.userGoal(for:)` and
/// `setGoal(_:for:)` so cards observing `metricSummaries` update instantly.
public struct GoalsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    @ObservedObject private var hk = HealthKitManager.shared

    private var isDark: Bool { themeMode == "dark" }

    /// Live values for sliders. Initialized from `userGoal(for:)` on appear so
    /// the slider position matches stored state. Writes go straight through
    /// `setGoal(_:for:)` so the dashboard cards animate as the user drags.
    @State private var values: [HealthMetricType: Double] = [:]
    @State private var debounceTask: Task<Void, Never>? = nil

    public init() {}

    private var editableMetrics: [HealthMetricType] {
        // Stable ordering — most user-facing first.
        let ordered: [HealthMetricType] = [
            .steps, .activeEnergy, .exerciseMinutes, .standHours,
            .sleep, .hydration, .distance, .mindfulMinutes, .flightsClimbed
        ]
        return ordered.filter { $0.isUserConfigurableGoal && $0.goalRange != nil }
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard

                    VStack(spacing: 12) {
                        ForEach(editableMetrics, id: \.rawValue) { metric in
                            goalRow(for: metric)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AdaptiveBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Daily goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { seedValues() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.indigo, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Personalize your targets")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text("Predictions, day streak, and cards all adapt instantly.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func goalRow(for metric: HealthMetricType) -> some View {
        if let range = metric.goalRange {
            GoalRowView(
                metric: metric,
                range: range,
                isDark: isDark,
                values: $values,
                onCommit: { storeVal in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        hk.setGoal(storeVal, for: metric)
                    }
                },
                onReset: { resetGoal(for: metric) }
            )
        }
    }

    private func seedValues() {
        for metric in editableMetrics {
            values[metric] = HealthKitManager.userGoal(for: metric)
        }
    }

    private func resetGoal(for metric: HealthMetricType) {
        hk.resetGoal(for: metric)
        values[metric] = metric.defaultGoal
    }
}

// MARK: - GoalRowView

/// Isolated row struct so SwiftUI can diff it without AnyView erasure.
/// All per-metric display constants are computed once at init time and stored
/// as `let` properties — they never need to recompute during a slider drag.
private struct GoalRowView: View {
    let metric: HealthMetricType
    let sliderRange: ClosedRange<Double>
    let sliderStep: Double
    let displayUnit: String
    let defaultDisplayStr: String
    let isDark: Bool
    @Binding var values: [HealthMetricType: Double]
    let onCommit: (Double) -> Void
    let onReset: () -> Void

    init(metric: HealthMetricType,
         range: (min: Double, max: Double, step: Double),
         isDark: Bool,
         values: Binding<[HealthMetricType: Double]>,
         onCommit: @escaping (Double) -> Void,
         onReset: @escaping () -> Void) {
        self.metric = metric
        self.isDark = isDark
        self._values = values
        self.onCommit = onCommit
        self.onReset = onReset

        if metric == .distance {
            let dispMin = LocaleUnits.distanceDisplay(fromMiles: range.min).value
            let dispMax = LocaleUnits.distanceDisplay(fromMiles: range.max).value
            sliderRange = dispMin...dispMax
            sliderStep = LocaleUnits.usesMetric ? 1.0 : range.step
            displayUnit = LocaleUnits.distanceUnit
            let defDisp = LocaleUnits.distanceDisplay(fromMiles: metric.defaultGoal)
            defaultDisplayStr = "\(GoalRowView.fmt(defDisp.value, for: metric)) \(LocaleUnits.distanceUnit)"
        } else {
            sliderRange = range.min...range.max
            sliderStep = range.step
            displayUnit = metric.unit
            defaultDisplayStr = "\(GoalRowView.fmt(metric.defaultGoal, for: metric)) \(metric.unit)"
        }
    }

    private var displayValue: Double {
        let stored = values[metric] ?? HealthKitManager.userGoal(for: metric)
        if metric == .distance {
            return LocaleUnits.distanceDisplay(fromMiles: stored).value
        }
        return stored
    }

    private var isOverride: Bool {
        HealthKitManager.userGoal(for: metric) != metric.defaultGoal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(metric.themeColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: metric.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(metric.themeColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                    Text("Default: \(defaultDisplayStr)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                }
                Spacer(minLength: 0)
                Text(GoalRowView.fmt(displayValue, for: metric))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(metric.themeColor)
                Text(displayUnit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }

            Slider(value: Binding(
                get: { displayValue },
                set: { newVal in
                    let storeVal = metric == .distance ? LocaleUnits.milesFromDisplay(newVal) : newVal
                    values[metric] = storeVal
                    onCommit(storeVal)
                }
            ), in: sliderRange, step: sliderStep)
                .tint(metric.themeColor)

            if isOverride {
                Button(action: onReset) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to default")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    static func fmt(_ value: Double, for metric: HealthMetricType) -> String {
        switch metric {
        case .steps, .activeEnergy, .flightsClimbed, .exerciseMinutes, .mindfulMinutes, .standHours:
            return String(format: "%.0f", value)
        case .sleep:
            return String(format: "%.1f", value)
        case .hydration:
            return String(format: "%.2f", value)
        case .distance:
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
}
