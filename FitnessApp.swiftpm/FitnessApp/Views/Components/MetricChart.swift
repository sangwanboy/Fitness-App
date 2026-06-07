import SwiftUI
import Charts

public struct MetricChart: View {
    public let type: HealthMetricType
    public let history: [MetricValue]

    @State private var rawSelectedDate: Date?

    /// True when the history spans more than ~31 days (the 1-year detail view).
    /// Derived once in init — `history` is a `let` and never mutates for a view
    /// instance, so this never needs recomputing across renders/drag ticks.
    private let isYearScale: Bool

    /// Clean, sorted plotting data — one point per bucket. Same-day samples are
    /// collapsed (averaged; legitimate daily statistics are identical so this just
    /// de-dupes) so the line is always monotonic in x and can't tangle.
    /// Derived once in init for the same reason as `isYearScale`.
    private let chartData: [MetricValue]

    public init(type: HealthMetricType, history: [MetricValue]) {
        self.type = type
        self.history = history

        // --- isYearScale: true when the history spans more than ~31 days. ---
        let yearScale: Bool
        if let first = history.map(\.date).min(),
           let last = history.map(\.date).max() {
            yearScale = last.timeIntervalSince(first) > 31 * 86_400
        } else {
            yearScale = false
        }
        self.isYearScale = yearScale

        // --- chartData: clean, sorted, one point per bucket. ---
        if type == .heartRate {
            // Heart rate is an intraday trace — keep each reading, just sorted.
            self.chartData = history.sorted { $0.date < $1.date }
        } else {
            let cal = Calendar.current
            if yearScale {
                let grouped = Dictionary(grouping: history) { cal.dateComponents([.year, .month], from: $0.date) }
                self.chartData = grouped.compactMap { comps, items -> MetricValue? in
                    guard let d = cal.date(from: comps), !items.isEmpty else { return nil }
                    return MetricValue(date: d, value: items.map(\.value).reduce(0, +) / Double(items.count))
                }
                .sorted { $0.date < $1.date }
            } else {
                // Daily buckets: one clean point per calendar day.
                let grouped = Dictionary(grouping: history) { cal.startOfDay(for: $0.date) }
                self.chartData = grouped.map { day, items in
                    MetricValue(date: day, value: items.map(\.value).reduce(0, +) / Double(items.count))
                }
                .sorted { $0.date < $1.date }
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected point tooltip display
            if let selectedPoint = currentSelectedPoint {
                HStack(spacing: 8) {
                    Text(formatSelectedDate(selectedPoint.date))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.95))

                    Spacer()

                    Text("\(String(format: (type == .sleep || type == .hydration) ? "%.1f" : type == .distance ? "%.2f" : "%.0f", selectedPoint.value)) \(type.unit)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(type.themeColor)
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .scale))
            } else {
                Text("Drag on chart to inspect values")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
            }

            // Swift Chart drawing. `chartData` is always cleaned to one point per
            // bucket (day, or month on the 1-year scale) and sorted, so the line
            // never crosses itself even if the source history has duplicate or
            // out-of-order same-day samples.
            Chart {
                ForEach(chartData) { item in
                    switch type {
                    case .steps, .activeEnergy, .hydration:
                        BarMark(
                            x: .value("Date", item.date, unit: isYearScale ? .month : .day),
                            y: .value("Value", item.value)
                        )
                        .foregroundStyle(type.themeColor.gradient)
                        .cornerRadius(4)

                    case .heartRate, .hrv:
                        AreaMark(
                            x: .value("Time", item.date),
                            y: .value("BPM", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [type.themeColor.opacity(0.3), type.themeColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", item.date),
                            y: .value("BPM", item.value)
                        )
                        .foregroundStyle(type.themeColor)
                        .symbol(.circle)
                        .symbolSize(30)
                        .interpolationMethod(.catmullRom)

                    case .sleep:
                        BarMark(
                            x: .value("Date", item.date, unit: isYearScale ? .month : .day),
                            y: .value("Hours", item.value)
                        )
                        .foregroundStyle(type.themeColor.gradient)
                        .cornerRadius(6)

                    case .distance:
                        AreaMark(
                            x: .value("Date", item.date),
                            y: .value("Miles", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [type.themeColor.opacity(0.25), type.themeColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Miles", item.value)
                        )
                        .foregroundStyle(type.themeColor)
                        .symbol {
                            Circle().strokeBorder(type.themeColor, lineWidth: 2)
                        }
                        .symbolSize(40)
                        .interpolationMethod(.monotone)

                    default:
                        // Show-more tiles render as a simple line chart in their detail view.
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Value", item.value)
                        )
                        .foregroundStyle(type.themeColor)
                        .interpolationMethod(.monotone)
                    }
                }

                // Selected item cursor line vertical rule (outside ForEach to prevent duplicates)
                if let selectedDate = rawSelectedDate {
                    RuleMark(x: .value("Selected Date", selectedDate))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                if type == .heartRate {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else if isYearScale {
                    AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else if chartData.count <= 7 {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.weekday(.short))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.white.opacity(0.90))
                }
            }
            .chartXSelection(value: $rawSelectedDate)
            .frame(height: 180)
            .padding(.top, 4)
        }
    }

    // Find matching metric value closest to the dragged date
    private var currentSelectedPoint: MetricValue? {
        guard let selectedDate = rawSelectedDate else { return nil }

        if type == .heartRate {
            return chartData.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) })
        } else if isYearScale {
            let calendar = Calendar.current
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return chartData.first { item in
                calendar.component(.month, from: item.date) == selectedMonth &&
                calendar.component(.year, from: item.date) == selectedYear
            }
        } else {
            return chartData.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        }
    }

    private func formatSelectedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if type == .heartRate {
            formatter.dateFormat = "MMM d, h:mm a"
        } else if isYearScale {
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
        }
        return formatter.string(from: date)
    }
}
