import SwiftUI
import Charts

public struct HealthTrendsView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    
    @State private var timeRange: TimeRange = .week
    @State private var detailMetric: HealthMetricType?
    
    public init() {}
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "1 Year"
        
        var id: String { self.rawValue }
    }
    
    // MARK: - Computed weekly insight values

    /// Number of days in the last 7 with steps >= goal (denominator is always 7).
    private var weeklyStepComplianceDays: Int? {
        guard let summary = healthKitManager.metricSummaries[.steps] else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let startOfCutoff = calendar.startOfDay(for: cutoff)
        let recentHistory = summary.history.filter { $0.date >= startOfCutoff }
        guard !recentHistory.isEmpty else { return nil }
        let goal = summary.goal > 0 ? summary.goal : HealthMetricType.steps.defaultGoal
        return recentHistory.filter { $0.value >= goal }.count
    }

    /// Max active energy (kcal) from the last 7 days, or nil if no data.
    private var weeklyActivityPeak: Double? {
        guard let summary = healthKitManager.metricSummaries[.activeEnergy] else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let startOfCutoff = calendar.startOfDay(for: cutoff)
        let recentHistory = summary.history.filter { $0.date >= startOfCutoff }
        guard !recentHistory.isEmpty else { return nil }
        return recentHistory.map(\.value).max()
    }

    /// Average sleep (hrs) from the last 7 days, or nil if no data.
    private var weeklyAvgSleep: Double? {
        guard let summary = healthKitManager.metricSummaries[.sleep] else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let startOfCutoff = calendar.startOfDay(for: cutoff)
        let recentHistory = summary.history.filter { $0.date >= startOfCutoff }
        guard !recentHistory.isEmpty else { return nil }
        return recentHistory.map(\.value).reduce(0, +) / Double(recentHistory.count)
    }

    /// Human-readable compliance label e.g. "5/7 days" or "-".
    private var complianceLabel: String {
        guard let days = weeklyStepComplianceDays else { return "-" }
        return "\(days)/7 days"
    }

    /// Human-readable activity peak e.g. "840 kcal" or "-".
    private var activityPeakLabel: String {
        guard let peak = weeklyActivityPeak else { return "-" }
        return "\(Int(peak.rounded())) kcal"
    }

    /// Human-readable avg sleep e.g. "7.4 hrs" or "-".
    private var avgSleepLabel: String {
        guard let avg = weeklyAvgSleep else { return "-" }
        return String(format: "%.1f hrs", avg)
    }

    /// Narrative summary for the insight card.
    private var insightNarrative: String {
        var parts: [String] = []
        if let days = weeklyStepComplianceDays {
            parts.append("You met your steps goal \(days) out of 7 days this week.")
        }
        if let peak = weeklyActivityPeak {
            parts.append("Peak active energy was \(Int(peak.rounded())) kcal.")
        }
        if let avg = weeklyAvgSleep {
            parts.append(String(format: "Average sleep was %.1f hrs.", avg))
        }
        return parts.isEmpty
            ? "No health data available for the past 7 days."
            : parts.joined(separator: " ")
    }

    public var body: some View {
        ZStack {
            SystemGlassBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Title
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Health Trends")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Long term health analytics")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.95))
                        }
                        Spacer()

                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)

                    // Native Picker for Time Range (Glass Tab style)
                    HStack(spacing: 0) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            let isSelected = timeRange == range
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    timeRange = range
                                }
                            } label: {
                                Text(range.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        if isSelected {
                                            Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                                        }
                                    }
                            }
                            .buttonStyle(InteractiveButtonStyle(scale: 0.95))
                        }
                    }
                    .padding(4)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    .padding(.horizontal)

                    // Key Insight Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.title2)
                                .foregroundColor(.orange)

                            Text("Weekly Insight")
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        Text(insightNarrative)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(4)

                        HStack(spacing: 16) {
                            InsightMiniStat(title: "Compliance", val: complianceLabel, color: .teal)
                            InsightMiniStat(title: "Activity Peak", val: activityPeakLabel, color: .orange)
                            InsightMiniStat(title: "Avg Sleep", val: avgSleepLabel, color: .cyan)
                        }
                    }
                    .glassCard(glowColor: .orange.opacity(0.06))
                    .padding(.horizontal)
                    
                    // Metric Comparison Charts
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Steps vs. Distance Compare")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        VStack(spacing: 16) {
                            // Steps Chart
                            if let stepsSummary = healthKitManager.metricSummaries[.steps] {
                                Button {
                                    detailMetric = .steps
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "figure.walk")
                                                .foregroundColor(.teal)
                                            Text("Daily Steps Trend")
                                                .foregroundColor(.white)
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                        MetricChart(type: .steps, history: filterHistory(stepsSummary.history))
                                    }
                                    .padding(.bottom, 12)
                                }
                                .buttonStyle(.plain)
                            }

                            // Distance Chart
                            if let distSummary = healthKitManager.metricSummaries[.distance] {
                                Button {
                                    detailMetric = .distance
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                                .foregroundColor(.green)
                                            Text("Walking & Running Distance")
                                                .foregroundColor(.white)
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                        MetricChart(type: .distance, history: filterHistory(distSummary.history))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .glassCard()
                        .padding(.horizontal)
                    }
                    
                    // Heart Rate Recovery Trend
                    if let heartSummary = healthKitManager.metricSummaries[.heartRate] {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Heart Rate Range (Last 12h)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            Button {
                                detailMetric = .heartRate
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(.red)
                                        Text("Continuous HR Stream")
                                            .foregroundColor(.white)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                    MetricChart(type: .heartRate, history: filterHistory(heartSummary.history, maxSamples: 200))
                                }
                            }
                            .buttonStyle(.plain)
                            .glassCard(glowColor: .red.opacity(0.05))
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.top)
                .padding(.bottom, 110)
            }
        }
        .sheet(item: $detailMetric) { type in
            if let summary = healthKitManager.metricSummaries[type] {
                DetailedMetricView(summary: summary)
            }
        }
    }
    
    private func filterHistory(_ history: [MetricValue], maxSamples: Int? = nil) -> [MetricValue] {
        let calendar = Calendar.current
        let now = Date()
        let cutoffDate: Date

        switch timeRange {
        case .week:
            cutoffDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        case .month:
            cutoffDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        case .year:
            cutoffDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86400)
        }

        let startOfCutoff = calendar.startOfDay(for: cutoffDate)
        let filtered = history.filter { $0.date >= startOfCutoff }.sorted(by: { $0.date < $1.date })
        if let cap = maxSamples, filtered.count > cap {
            return Array(filtered.suffix(cap))
        }
        return filtered
    }
}

struct InsightMiniStat: View {
    let title: String
    let val: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.95))
            Text(val)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
