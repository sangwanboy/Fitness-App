import SwiftUI
import Charts

public struct MetricChart: View {
    public let type: HealthMetricType
    public let history: [MetricValue]
    
    @State private var rawSelectedDate: Date?
    
    public init(type: HealthMetricType, history: [MetricValue]) {
        self.type = type
        self.history = history
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
            
            // Swift Chart drawing
            Chart {
                ForEach(chartData) { item in
                    switch type {
                    case .steps, .activeEnergy, .hydration:
                        BarMark(
                            x: .value("Date", item.date, unit: history.count > 31 ? .month : .day),
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
                            x: .value("Date", item.date, unit: history.count > 31 ? .month : .day),
                            y: .value("Hours", item.value)
                        )
                        .foregroundStyle(type.themeColor.gradient)
                        .cornerRadius(6)
                        
                    case .distance:
                        AreaMark(
                            x: .value("Date", item.date, unit: history.count > 31 ? .month : .day),
                            y: .value("Miles", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [type.themeColor.opacity(0.25), type.themeColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("Date", item.date, unit: history.count > 31 ? .month : .day),
                            y: .value("Miles", item.value)
                        )
                        .foregroundStyle(type.themeColor)
                        .symbol {
                            Circle().strokeBorder(type.themeColor, lineWidth: 2)
                        }
                        .symbolSize(40)
                        .interpolationMethod(.catmullRom)

                    default:
                        // Show-more tiles render as a simple line chart in their detail view.
                        LineMark(
                            x: .value("Date", item.date, unit: history.count > 31 ? .month : .day),
                            y: .value("Value", item.value)
                        )
                        .foregroundStyle(type.themeColor)
                        .interpolationMethod(.catmullRom)
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
                } else if history.count <= 7 {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.weekday(.short))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else if history.count <= 31 {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                } else {
                    AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
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
    
    // Aggregates data by month for 1-Year charts to avoid cluttering the view
    private var chartData: [MetricValue] {
        if type == .heartRate || history.count <= 31 {
            return history
        }
        
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history) { item -> DateComponents in
            calendar.dateComponents([.year, .month], from: item.date)
        }
        
        let aggregated = grouped.compactMap { (components, items) -> MetricValue? in
            guard let firstDate = calendar.date(from: components), !items.isEmpty else { return nil }
            let totalValue = items.map { $0.value }.reduce(0, +)
            let avgValue = totalValue / Double(items.count)
            return MetricValue(date: firstDate, value: avgValue)
        }
        
        return aggregated.sorted(by: { $0.date < $1.date })
    }
    
    // Find matching metric value closest to the dragged date
    private var currentSelectedPoint: MetricValue? {
        guard let selectedDate = rawSelectedDate else { return nil }
        
        if type == .heartRate {
            return chartData.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) })
        } else if history.count > 31 {
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
        } else if history.count > 31 {
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
        }
        return formatter.string(from: date)
    }
}
