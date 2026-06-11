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

    /// True when the heart-rate history spans more than ~36 hours (weekly view).
    /// Used to switch the x-axis and bucketing strategy.
    private let isHRMultiDay: Bool

    /// Clean, sorted plotting data — one point per bucket. Same-day samples are
    /// collapsed (averaged; legitimate daily statistics are identical so this just
    /// de-dupes) so the line is always monotonic in x and can't tangle.
    /// Derived once in init for the same reason as `isYearScale`.
    private let chartData: [MetricValue]

    public init(type: HealthMetricType, history: [MetricValue]) {
        self.type = type
        self.history = history

        // --- isYearScale: true when the history spans more than ~31 days. ---
        let sorted = history.sorted { $0.date < $1.date }
        let spanSeconds = sorted.last.map { $0.date.timeIntervalSince(sorted.first!.date) } ?? 0
        let yearScale = spanSeconds > 31 * 86_400
        self.isYearScale = yearScale

        // --- isHRMultiDay: true when heart-rate history spans more than ~36 hours. ---
        let hrMultiDay = (type == .heartRate || type == .hrv) && spanSeconds > 36 * 3_600
        self.isHRMultiDay = hrMultiDay

        // --- chartData: clean, sorted, one point per bucket. ---
        if type == .heartRate || type == .hrv {
            if hrMultiDay {
                // Weekly+ view: bucket into fixed windows so we land at ~40-80 pts.
                // <=3 days → 1-hour buckets; >3 days → 3-hour buckets.
                let bucketHours: Int = spanSeconds <= 3 * 86_400 ? 1 : 3
                let bucketSecs = Double(bucketHours * 3_600)
                guard let epoch = sorted.first?.date else {
                    self.chartData = []
                    return
                }
                let grouped = Dictionary(grouping: sorted) { item -> Date in
                    let offset = item.date.timeIntervalSince(epoch)
                    let bucket = floor(offset / bucketSecs) * bucketSecs
                    return epoch.addingTimeInterval(bucket)
                }
                self.chartData = grouped.compactMap { bucketDate, items -> MetricValue? in
                    guard !items.isEmpty else { return nil }
                    return MetricValue(date: bucketDate, value: items.map(\.value).reduce(0, +) / Double(items.count))
                }
                .sorted { $0.date < $1.date }
            } else {
                // Intraday view — keep each reading, just sorted.
                self.chartData = sorted
            }
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
                        .interpolationMethod(.monotone)

                        if chartData.count > 40 {
                            LineMark(
                                x: .value("Time", item.date),
                                y: .value("BPM", item.value)
                            )
                            .foregroundStyle(type.themeColor)
                            .interpolationMethod(.monotone)
                        } else {
                            LineMark(
                                x: .value("Time", item.date),
                                y: .value("BPM", item.value)
                            )
                            .foregroundStyle(type.themeColor)
                            .symbol(.circle)
                            .symbolSize(30)
                            .interpolationMethod(.monotone)
                        }

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
                if (type == .heartRate || type == .hrv) && isHRMultiDay {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.weekday(.short))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else if type == .heartRate || type == .hrv {
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

        if type == .heartRate || type == .hrv {
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
        if (type == .heartRate || type == .hrv) && isHRMultiDay {
            formatter.dateFormat = "EEE MMM d, ha"
        } else if type == .heartRate || type == .hrv {
            formatter.dateFormat = "MMM d, h:mm a"
        } else if isYearScale {
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
        }
        return formatter.string(from: date)
    }
}
