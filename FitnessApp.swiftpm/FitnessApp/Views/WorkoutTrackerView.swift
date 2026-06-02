import SwiftUI
import Combine
import HealthKit

public struct WorkoutTrackerView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    // Configurations
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    let onBack: () -> Void

    // Workout session states
    @State private var selectedWorkoutType: WorkoutType = .run
    @State private var isRunning = false
    @State private var secondsElapsed = 0
    @State private var currentHeartRate = 0
    @State private var estimatedCalories = 0.0
    @State private var estimatedDistance = 0.0
    @State private var showSaveAlert = false
    @State private var showSummary = false
    @State private var recentWorkouts: [HKWorkout] = []
    @State private var showHRZones  = false
    @State private var showAnalytics = false

    // Timer publisher
    @State private var timer: Timer.TimerPublisher = Timer.publish(every: 1, on: .main, in: .common)
    @State private var cancellable: Any?
    
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    
    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }
    
    enum WorkoutType: String, CaseIterable, Identifiable {
        case run = "Outdoor Run"
        case cycle = "Cycling"
        case walk = "Power Walk"
        case strength = "Strength"
        
        var id: String { self.rawValue }
        
        var themeColor: Color {
            switch self {
            case .run: return Color(.systemGreen)
            case .walk: return Color(.systemTeal)
            case .cycle: return Color(.systemOrange)
            case .strength: return Color(.systemIndigo)
            }
        }
        
        var icon: String {
            switch self {
            case .run: return "figure.run"
            case .cycle: return "figure.outdoor.cycle"
            case .walk: return "figure.walk"
            case .strength: return "figure.strengthtraining.functional"
            }
        }
        
        var calorieMultiplier: Double {
            switch self {
            case .run: return 12.0 // kcal per minute
            case .cycle: return 8.5
            case .walk: return 5.0
            case .strength: return 6.0
            }
        }
        
        var speedMultiplier: Double {
            switch self {
            case .run: return 0.12 // miles per minute
            case .cycle: return 0.25
            case .walk: return 0.05
            case .strength: return 0.0
            }
        }

        var healthKitActivityType: HKWorkoutActivityType {
            switch self {
            case .run: return .running
            case .cycle: return .cycling
            case .walk: return .walking
            case .strength: return .functionalStrengthTraining
            }
        }
    }
    
    public var body: some View {
        ZStack {
            AdaptiveBackground()
            
            VStack(spacing: 0) {
                // Header Nav
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(accentColor)
                        .fontWeight(.semibold)
                    }
                    Spacer()
                    
                    Text("Workout Detail")
                        .font(.headline)
                        .foregroundColor(isDark ? .white : .black)
                    
                    Spacer()
                    Text("Back").opacity(0) // Dummy to align center
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // Selector (Horizontal list)
                        if !isRunning {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(WorkoutType.allCases) { type in
                                        let isSelected = selectedWorkoutType == type
                                        Button(action: { selectedWorkoutType = type }) {
                                            VStack(spacing: 12) {
                                                Image(systemName: type.icon)
                                                    .font(.title2)
                                                    .foregroundColor(isSelected ? type.themeColor : (isDark ? .white.opacity(0.8) : .black.opacity(0.8)))
                                                
                                                Text(type.rawValue)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(isSelected ? (isDark ? .white : .black) : (isDark ? .white.opacity(0.6) : .black.opacity(0.6)))
                                            }
                                            .frame(width: 100, height: 90)
                                            .glassCard(glowColor: isSelected ? type.themeColor.opacity(0.12) : nil)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Stopwatch / Current Session stats
                        VStack(spacing: 16) {
                            Text(selectedWorkoutType.rawValue.uppercased())
                                 .font(.system(size: 11, weight: .bold))
                                 .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                                 .tracking(2.0)
                            
                            Text(timeString(from: secondsElapsed))
                                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                                .foregroundColor(isDark ? .white : .black)
                                .shadow(color: selectedWorkoutType.themeColor.opacity(0.2), radius: 10)
                            
                            HStack(spacing: 24) {
                                // Estimated Calories
                                VStack(spacing: 4) {
                                    Text("ACTIVE ENERGY")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                                        Text(String(format: "%.0f", estimatedCalories))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                        Text("kcal")
                                            .font(.caption2)
                                            .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    }
                                }
                                
                                // Current Heart Rate
                                VStack(spacing: 4) {
                                    Text("HEART RATE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                                        Text(currentHeartRate > 0 ? "\(currentHeartRate)" : "—")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                        Text("bpm")
                                            .font(.caption2)
                                            .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    }
                                }
                                
                                // Distance
                                if selectedWorkoutType != .strength {
                                    VStack(spacing: 4) {
                                        Text("DISTANCE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                                            Text(String(format: "%.2f", estimatedDistance))
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            Text("mi")
                                                .font(.caption2)
                                                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 24)
                        .glassCard(glowColor: isRunning ? selectedWorkoutType.themeColor.opacity(0.12) : nil)
                        .padding(.horizontal, 20)
                        
                        // Play / Pause / Finish controls
                        HStack(spacing: 20) {
                            if !isRunning {
                                Button(action: startWorkout) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Start Activity")
                                    }
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(selectedWorkoutType.themeColor)
                                    .cornerRadius(14)
                                    .shadow(color: selectedWorkoutType.themeColor.opacity(0.3), radius: 8)
                                }
                            } else {
                                Button(action: pauseWorkout) {
                                    HStack {
                                        Image(systemName: "pause.fill")
                                        Text("Pause")
                                    }
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isDark ? .white : .black)
                                    .frame(width: 120, height: 50)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                }
                                
                                Button(action: { showSaveAlert = true }) {
                                    HStack {
                                        Image(systemName: "stop.fill")
                                        Text("Finish")
                                    }
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.red)
                                    .cornerRadius(12)
                                    .shadow(color: Color.red.opacity(0.3), radius: 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // History list
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Recent Activities")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(isDark ? .white : .black)

                                Spacer()

                                Button(action: { showHRZones = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Zones")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button(action: { showAnalytics = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Analytics")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(accentColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))

                            if recentWorkouts.isEmpty {
                                Text("No workouts yet — start one above.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(recentWorkouts, id: \.uuid) { w in
                                    WorkoutRecordRowView(
                                        title: workoutTitle(w),
                                        date: workoutDateLabel(w),
                                        kcal: workoutCaloriesLabel(w),
                                        duration: workoutDurationLabel(w),
                                        dist: workoutDistanceLabel(w),
                                        isDark: isDark
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .glassCard()
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .onReceive(timer) { _ in
            if isRunning {
                secondsElapsed += 1
                updateWorkoutStats()
            }
        }
        .alert("End Workout", isPresented: $showSaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { discardWorkout() }
            Button("Save Workout") { saveWorkout() }
        } message: {
            Text("Do you want to save this workout details to Apple Health?")
        }
        .sheet(isPresented: $showAnalytics) {
            WorkoutAnalyticsView()
        }
        .sheet(isPresented: $showHRZones) {
            HeartRateZonesView()
        }
        .sheet(isPresented: $showSummary) {
            WorkoutSummaryView(
                type: selectedWorkoutType,
                duration: timeString(from: secondsElapsed),
                calories: estimatedCalories,
                distance: estimatedDistance
            ) {
                showSummary = false
                resetWorkout()
            }
        }
        .task {
            // Seed heart-rate from latest HK reading; refresh recent workouts.
            currentHeartRate = Int(healthKitManager.metricSummaries[.heartRate]?.currentValue ?? 0)
            recentWorkouts = await healthKitManager.fetchRecentWorkouts(days: 7)
        }
    }

    // MARK: - Recent workouts row formatting

    private func workoutTitle(_ w: HKWorkout) -> String {
        switch w.workoutActivityType {
        case .running: return "Outdoor Run"
        case .walking: return "Walk"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining: return "Strength"
        case .hiking: return "Hike"
        case .swimming: return "Swim"
        case .yoga: return "Yoga"
        case .mindAndBody: return "Mindful"
        default: return "Workout"
        }
    }

    private func workoutDateLabel(_ w: HKWorkout) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: w.startDate)
    }

    private func workoutDurationLabel(_ w: HKWorkout) -> String {
        let minutes = Int(w.duration / 60)
        return "\(minutes) min"
    }

    private func workoutCaloriesLabel(_ w: HKWorkout) -> String {
        let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        return kcal > 0 ? String(format: "%.0f kcal", kcal) : "—"
    }

    private func workoutDistanceLabel(_ w: HKWorkout) -> String? {
        guard let d = w.totalDistance?.doubleValue(for: .mile()), d > 0 else { return nil }
        return String(format: "%.1f mi", d)
    }
    
    private func startWorkout() {
        isRunning = true
        timer = Timer.publish(every: 1, on: .main, in: .common)
        let pub = timer.connect()
        cancellable = pub
    }
    
    private func pauseWorkout() {
        isRunning = false
        if let con = cancellable as? Cancellable {
            con.cancel()
        }
    }
    
    private func updateWorkoutStats() {
        let minutes = Double(secondsElapsed) / 60.0
        estimatedCalories = minutes * selectedWorkoutType.calorieMultiplier
        estimatedDistance = minutes * selectedWorkoutType.speedMultiplier
        
        if secondsElapsed < 60 {
            currentHeartRate = Int(72.0 + (Double(secondsElapsed) * 0.8))
        } else {
            let heartRateFluctuation = sin(Double(secondsElapsed) / 10.0) * 5.0
            currentHeartRate = Int(120.0 + heartRateFluctuation + Double.random(in: -2...2))
        }
    }
    
    private func saveWorkout() {
        isRunning = false
        if let con = cancellable as? Cancellable {
            con.cancel()
        }

        let end = Date()
        let start = end.addingTimeInterval(-Double(secondsElapsed))
        let activity = selectedWorkoutType.healthKitActivityType
        let calories = estimatedCalories
        let distance = selectedWorkoutType == .strength ? 0 : estimatedDistance
        let stepsToLog = (selectedWorkoutType == .run || selectedWorkoutType == .walk)
            ? Double(secondsElapsed) * 2.2 : 0

        Task {
            // Primary write: a proper HKWorkout so Apple Health's Activity /
            // Workouts sections show a single entry rather than orphan samples.
            _ = await healthKitManager.logWorkout(
                activityType: activity,
                start: start,
                end: end,
                calories: calories,
                distanceMiles: distance
            )
            // Step count isn't part of HKWorkout's totals; write separately for
            // run / walk so the daily steps tile reflects the activity.
            if stepsToLog > 0 {
                _ = await healthKitManager.logMetricValue(type: .steps, value: stepsToLog, date: end)
            }
            showSummary = true
        }
    }
    
    private func discardWorkout() {
        resetWorkout()
    }
    
    private func resetWorkout() {
        isRunning = false
        if let con = cancellable as? Cancellable {
            con.cancel()
        }
        secondsElapsed = 0
        currentHeartRate = Int(healthKitManager.metricSummaries[.heartRate]?.currentValue ?? 0)
        estimatedCalories = 0.0
        estimatedDistance = 0.0
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// Workout Record Row
struct WorkoutRecordRowView: View {
    let title: String
    let date: String
    let kcal: String
    let duration: String
    let dist: String?
    let isDark: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text(date)
                    .font(.caption2)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(kcal)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                
                HStack(spacing: 6) {
                    Text(duration)
                        .font(.caption2)
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    
                    if let d = dist {
                        Circle()
                            .fill(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            .frame(width: 3, height: 3)
                        Text(d)
                            .font(.caption2)
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Workout Summary View
struct WorkoutSummaryView: View {
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    
    let type: WorkoutTrackerView.WorkoutType
    let duration: String
    let calories: Double
    let distance: Double
    let onDismiss: () -> Void
    
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    
    var body: some View {
        ZStack {
            AdaptiveBackground()
            
            VStack(spacing: 24) {
                // Done indicator
                ZStack {
                    Circle()
                        .stroke(type.themeColor.opacity(0.15), lineWidth: 8)
                        .frame(width: 90, height: 90)
                    
                    Circle()
                        .trim(from: 0.0, to: 1.0)
                        .stroke(
                            LinearGradient(
                                colors: [type.themeColor, type.themeColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(type.themeColor)
                }
                .padding(.top, 40)
                
                VStack(spacing: 8) {
                    Text("Workout Completed!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                    
                    Text("Nice job! Your stats have been saved.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                
                // Stats Card Grid
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        SummaryStatTile(title: "Activity", value: type.rawValue, icon: type.icon, color: type.themeColor, isDark: isDark)
                        SummaryStatTile(title: "Duration", value: duration, icon: "timer", color: .purple, isDark: isDark)
                    }
                    
                    HStack(spacing: 12) {
                        SummaryStatTile(title: "Calories", value: String(format: "%.0f kcal", calories), icon: "flame.fill", color: .orange, isDark: isDark)
                        if type != .strength {
                            SummaryStatTile(title: "Distance", value: String(format: "%.2f mi", distance), icon: "figure.walk", color: .green, isDark: isDark)
                        } else {
                            SummaryStatTile(title: "Intensity", value: "High", icon: "bolt.fill", color: .red, isDark: isDark)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Done Button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(accentColor)
                        .cornerRadius(14)
                        .shadow(color: accentColor.opacity(0.3), radius: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// Summary Stat Card Component
struct SummaryStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isDark: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .textCase(.uppercase)
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}
