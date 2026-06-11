import SwiftUI

public struct DetailedMetricView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    
    @AppStorage("theme_mode") private var themeMode = "dark"
    
    public let summary: MetricSummary
    
    @State private var animateEntry  = false
    @State private var showHRZones   = false

    private var isDark: Bool { themeMode == "dark" }
    
    public init(summary: MetricSummary) {
        self.summary = summary
    }
    
    public var body: some View {
        ZStack {
            // Elegant background blur & dynamic gradient glow
            SystemGlassBackground()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Bar
                    HStack {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(summary.type.themeColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: summary.type.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(summary.type.themeColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.type.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(isDark ? .white : .black)
                                
                                Text("Overview & Trends")
                                    .font(.caption)
                                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                        }
                        
                        Spacer()
                        
                        // Glass Close button
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .accessibilityLabel("Close")
                        .buttonStyle(InteractiveButtonStyle(scale: 0.9))
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // Large Main Stat Card
                    VStack(spacing: 12) {
                        Text(mainStatLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .tracking(1.5)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(summary.displayValueString)
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white : .black)
                            
                            Text(summary.type.unit)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                                .padding(.bottom, 8)
                        }
                        
                        // Status indicator
                        if summary.type.isUserConfigurableGoal {
                            HStack(spacing: 8) {
                                Image(systemName: summary.percentComplete >= 1.0 ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                                    .foregroundColor(summary.percentComplete >= 1.0 ? .green : summary.type.themeColor)

                                Text(summary.percentComplete >= 1.0 ? "Daily goal achieved!" : "\(String(format: "%.0f%%", (1.0 - summary.percentComplete) * 100)) remaining to goal")
                                    .font(.caption)
                                    .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .glassEffect(.regular, in: .capsule)
                        } else if summary.type == .heartRate {
                            HStack(spacing: 10) {
                                Text(restingHRLabel)
                                    .font(.caption)
                                    .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))

                                Button(action: { showHRZones = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Zones")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular.tint(.red.opacity(0.12)).interactive(), in: .capsule)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else {
                            Text(hrvRangeLabel)
                                .font(.caption)
                                .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 8)
                    .opacity(animateEntry ? 1.0 : 0.0)
                    .offset(y: animateEntry ? 0 : 20)
                    
                    // Chart Component
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly Analytics")
                            .font(.headline)
                            .foregroundColor(isDark ? .white : .black)
                        
                        MetricChart(type: summary.type, history: weeklyHistory)
                    }
                    .glassCard(glowColor: summary.type.themeColor.opacity(0.1))
                    .padding(.horizontal)
                    .opacity(animateEntry ? 1.0 : 0.0)
                    .offset(y: animateEntry ? 0 : 15)

                    
                    // Secondary stats list
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Historical Insights")
                            .font(.headline)
                            .foregroundColor(isDark ? .white : .black)
                        
                        Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        
                        HStack {
                            Label("Weekly Average", systemImage: "chart.bar.fill")
                                .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                            Spacer()
                            Text("\(formattedMetricValue(weeklyAverage)) \(summary.type.unit)")
                                .fontWeight(.semibold)
                                .foregroundColor(isDark ? .white : .black)
                        }

                        HStack {
                            Label("Weekly Peak", systemImage: "arrow.up.right.circle.fill")
                                .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                            Spacer()
                            Text("\(formattedMetricValue(weeklyPeak)) \(summary.type.unit)")
                                .fontWeight(.semibold)
                                .foregroundColor(isDark ? .white : .black)
                        }
                    }
                    .glassCard()
                    .padding(.horizontal)
                    .opacity(animateEntry ? 1.0 : 0.0)
                    .offset(y: animateEntry ? 0 : 5)
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateEntry = true
            }
        }
        .sheet(isPresented: $showHRZones) {
            HeartRateZonesView()
        }
    }
    
    /// Header label for the main stat card — metric-aware.
    private var mainStatLabel: String {
        switch summary.type {
        // Cumulative daily totals
        case .steps, .activeEnergy, .restingEnergy, .distance, .hydration,
             .flightsClimbed, .exerciseMinutes, .standHours, .mindfulMinutes:
            return "TODAY'S TOTAL"
        case .sleep:
            return "LAST NIGHT"
        // Intraday averages
        case .heartRate, .walkingSpeed, .walkingStepLength,
             .walkingDoubleSupport, .walkingAsymmetry, .headphoneAudio,
             .oxygenSaturation:
            return "TODAY'S AVERAGE"
        // Point-in-time / physiological readings
        case .hrv:
            return "LATEST READING"
        case .restingHeartRate:
            return "TODAY'S AVERAGE"
        case .bodyMass, .vo2Max:
            return "LATEST READING"
        }
    }

    /// Label shown under the heart-rate main stat.
    /// Uses the resting-HR summary's currentValue (populated by HealthKit's .restingHeartRate query).
    private var restingHRLabel: String {
        if let rhr = healthKitManager.metricSummaries[.restingHeartRate]?.currentValue, rhr > 0 {
            return "Resting avg: \(Int(rhr.rounded())) bpm"
        }
        return "Resting avg: —"
    }

    /// Label shown under the HRV main stat.
    /// Computes the user's actual 28-day min/max from summary.history.
    private var hrvRangeLabel: String {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date().addingTimeInterval(-28 * 86400)
        let recent = summary.history.filter { $0.date >= cutoff }.map { $0.value }
        guard let minVal = recent.min(), let maxVal = recent.max() else {
            return "Your range: —"
        }
        return "Your range: \(Int(minVal.rounded())) – \(Int(maxVal.rounded())) ms"
    }

    private var weeklyHistory: [MetricValue] {
        let calendar = Calendar.current
        let now = Date()
        let cutoffDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let startOfCutoff = calendar.startOfDay(for: cutoffDate)
        
        return summary.history.filter { $0.date >= startOfCutoff }.sorted(by: { $0.date < $1.date })
    }
    
    private var weeklyAverage: Double {
        let hist = summary.type == .sleep
            ? weeklyHistory.filter { $0.value > 0 }
            : weeklyHistory
        guard !hist.isEmpty else { return 0 }
        return hist.map { $0.value }.reduce(0, +) / Double(hist.count)
    }

    private func formattedMetricValue(_ value: Double) -> String {
        switch summary.type {
        case .sleep, .hydration, .vo2Max, .walkingSpeed,
             .walkingDoubleSupport, .walkingAsymmetry:
            return String(format: "%.1f", value)
        case .distance, .bodyMass:
            return String(format: "%.2f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
    
    private var weeklyPeak: Double {
        weeklyHistory.map { $0.value }.max() ?? 0
    }
}
