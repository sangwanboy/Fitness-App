import SwiftUI
import Charts

public struct HealthTrendsView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    
    @State private var timeRange: TimeRange = .week
    @State private var selectedMetricType: HealthMetricType = .steps
    @State private var showDetailSheet = false
    
    public init() {}
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "1 Year"
        
        var id: String { self.rawValue }
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
                        ForEach(TimeRange.allCases) { range in
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    timeRange = range
                                }
                            }) {
                                Text(range.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(timeRange == range ? .semibold : .regular)
                                    .foregroundColor(timeRange == range ? .white : .white.opacity(0.85))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        ZStack {
                                            if timeRange == range {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.white.opacity(0.12))
                                                    .matchedGeometryEffect(id: "activeTab", in: namespace)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(InteractiveButtonStyle(scale: 0.95))
                        }
                    }
                    .padding(4)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
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
                        
                        Text("Your active energy expenditure increased by 14% this week. You have consistently met your steps target 5 out of 7 days, maintaining a resting heart rate average of 64 bpm.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(4)
                        
                        HStack(spacing: 16) {
                            InsightMiniStat(title: "Compliance", val: "71%", color: .teal)
                            InsightMiniStat(title: "Activity Peak", val: "840 kcal", color: .orange)
                            InsightMiniStat(title: "Avg Sleep", val: "7.4 hrs", color: .cyan)
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
                            
                            // Distance Chart
                            if let distSummary = healthKitManager.metricSummaries[.distance] {
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
                            
                            VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(.red)
                                        Text("Continuous HR Stream")
                                            .foregroundColor(.white)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                MetricChart(type: .heartRate, history: filterHistory(heartSummary.history))
                            }
                            .glassCard(glowColor: .red.opacity(0.05))
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.top)
                .padding(.bottom, 110)
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            if let summary = healthKitManager.metricSummaries[selectedMetricType] {
                DetailedMetricView(summary: summary)
            }
        }
    }
    
    private func filterHistory(_ history: [MetricValue]) -> [MetricValue] {
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
        return history.filter { $0.date >= startOfCutoff }.sorted(by: { $0.date < $1.date })
    }
    
    @Namespace private var namespace
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
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
