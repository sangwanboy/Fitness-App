import SwiftUI
import HealthKit

// MARK: - NutritionDashboardView

public struct NutritionDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hk  = HealthKitManager.shared
    @ObservedObject private var nut = NutritionService.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var showGoalsEditor = false
    @State private var animateRings    = false
    @State private var selectedTab: Int = 0    // 0 = Today, 1 = Week
    @State private var showFoodPhotoFlow = false

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    // Convenience shorthands
    private var goals: MacroGoals { nut.macroGoals }
    private var caloriesToday: Double { hk.dietaryCaloriesToday }
    private var proteinToday:  Double { hk.dietaryProteinToday }
    private var carbsToday:    Double { nut.carbsToday }
    private var fatToday:      Double { nut.fatToday }

    public init() {}

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .bottom) {
            AdaptiveBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    headerBar
                    macroRingsSection
                    weekTrendSection
                    mealsSection
                    micronutrientsSection
                    // bottom padding so sticky bar doesn't overlap last content
                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            stickyLogBar
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showGoalsEditor) {
            MacroGoalsEditorSheet()
        }
        .fullScreenCover(isPresented: $showFoodPhotoFlow) { FoodScanView() }
        .sheet(item: $detailSummary) { summary in
            DetailedMetricView(summary: summary)
        }
        .task {
            await nut.refreshToday()
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                animateRings = true
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Nutrition")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                Text(Date(), style: .date)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }

            Spacer()

            HStack(spacing: 10) {
                // Goals gear
                Button {
                    showGoalsEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)

                // Dismiss
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Macro Rings Section

    private var macroRingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "circle.grid.2x2.fill", title: "Macros", color: accentColor)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                MacroRingCard(
                    label: "Calories",
                    unit: "kcal",
                    current: caloriesToday,
                    goal: goals.calories,
                    color: .orange,
                    icon: "flame.fill",
                    animate: animateRings
                ) {
                    if let s = hk.metricSummaries[.activeEnergy] {
                        openDetailedMetric(summary: s)
                    }
                }

                MacroRingCard(
                    label: "Protein",
                    unit: "g",
                    current: proteinToday,
                    goal: goals.protein,
                    color: Color(red: 0.36, green: 0.61, blue: 1.0),
                    icon: "bolt.fill",
                    animate: animateRings
                ) { /* protein has no DetailedMetricView type; tap shows nothing extra */ }

                MacroRingCard(
                    label: "Carbs",
                    unit: "g",
                    current: carbsToday,
                    goal: goals.carbs,
                    color: Color(.systemGreen),
                    icon: "leaf.fill",
                    animate: animateRings
                ) {}

                MacroRingCard(
                    label: "Fat",
                    unit: "g",
                    current: fatToday,
                    goal: goals.fat,
                    color: Color(.systemYellow),
                    icon: "drop.fill",
                    animate: animateRings
                ) {}
            }
        }
    }

    @State private var detailSummary: MetricSummary? = nil

    private func openDetailedMetric(summary: MetricSummary) {
        detailSummary = summary
    }

    // MARK: - 7-Day Trend Section

    private var weekTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "chart.bar.fill", title: "7-Day Calorie Trend", color: .orange)

            VStack(alignment: .leading, spacing: 8) {
                let history = hk.dietaryCalories7Day

                if history.allSatisfy({ $0 == 0 }) {
                    emptyState(message: "Log meals to see your trend")
                        .frame(height: 120)
                } else {
                    CalorieTrendChart(values: history, goalLine: goals.calories)
                        .frame(height: 120)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassCard()
        }
    }

    // MARK: - Meals Section

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "fork.knife", title: "Today's Meals", color: accentColor)

            if hk.todayFoodLog.isEmpty {
                emptyState(message: "No meals logged yet.\nTap \"Log Food with AI\" below to get started.")
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(MealBucket.allCases, id: \.self) { bucket in
                        let items = entriesFor(bucket: bucket)
                        if !items.isEmpty {
                            mealBucketSection(bucket: bucket, items: items)
                        }
                    }
                }
                .glassCard()
            }
        }
    }

    private func mealBucketSection(bucket: MealBucket, items: [FoodLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Bucket header
            HStack(spacing: 6) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(bucket.color)
                Text(bucket.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(bucket.color)
                Spacer()
                Text(totalKcal(items: items))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            .padding(.horizontal, 4)

            ForEach(items) { entry in
                FoodLogRow(entry: entry)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .overlay(alignment: .bottom) {
            if bucket != .evening {
                Divider()
                    .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .padding(.horizontal, 4)
            }
        }
    }

    private func totalKcal(items: [FoodLogEntry]) -> String {
        let sum = items.map { $0.calories }.reduce(0, +)
        return sum > 0 ? "\(Int(sum)) kcal" : ""
    }

    private func entriesFor(bucket: MealBucket) -> [FoodLogEntry] {
        hk.todayFoodLog.filter { entry in
            let hour = Calendar.current.component(.hour, from: entry.loggedAt)
            return bucket.hourRange.contains(hour)
        }
    }

    // MARK: - Micronutrients Section

    private var micronutrientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "atom", title: "Micronutrients", color: Color(.systemPurple))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                MicroChip(
                    label: "Fiber",
                    value: nut.fiberToday,
                    rdaGoal: 28,
                    unit: "g",
                    color: Color(.systemGreen),
                    icon: "leaf.fill"
                )
                MicroChip(
                    label: "Sugar",
                    value: nut.sugarToday,
                    rdaGoal: 50,
                    unit: "g",
                    color: Color(.systemPink),
                    icon: "cube.fill"
                )
                MicroChip(
                    label: "Sodium",
                    value: nut.sodiumMgToday,
                    rdaGoal: 2300,
                    unit: "mg",
                    color: Color(.systemOrange),
                    icon: "drop.fill"
                )
                MicroChip(
                    label: "Caffeine",
                    value: nut.caffeineMgToday,
                    rdaGoal: 400,
                    unit: "mg",
                    color: Color(.systemBrown),
                    icon: "cup.and.saucer.fill"
                )
            }
        }
    }

    // MARK: - Sticky Bottom Bar

    private var stickyLogBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1))

            HStack(spacing: 12) {
                // Camera scan button
                Button {
                    showFoodPhotoFlow = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Scan Meal")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [.orange, .pink],
                                                 startPoint: .leading, endPoint: .trailing))
                    )
                }
                .buttonStyle(.plain)

                // Text/AI log button
                Button {
                    ChatPrefillBus.shared.queueComposerSeed("Log food: ")
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Log with AI")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(accentColor.gradient)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            (isDark ? Color.black : Color(red: 0.97, green: 0.97, blue: 0.97))
                .opacity(0.85)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers

    private func sectionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(isDark ? .white.opacity(0.2) : .black.opacity(0.2))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Meal Bucket

private enum MealBucket: CaseIterable {
    case morning, afternoon, evening

    var label: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        }
    }

    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening:   return "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning:   return Color(.systemYellow)
        case .afternoon: return Color(.systemOrange)
        case .evening:   return Color(.systemPurple)
        }
    }

    // Hour ranges (0...23)
    var hourRange: ClosedRange<Int> {
        switch self {
        case .morning:   return 0...11
        case .afternoon: return 12...17
        case .evening:   return 18...23
        }
    }
}

// MARK: - MacroRingCard

private struct MacroRingCard: View {
    let label: String
    let unit: String
    let current: Double
    let goal: Double
    let color: Color
    let icon: String
    let animate: Bool
    let onTap: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1.0)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Ring
                ZStack {
                    // Track
                    Circle()
                        .stroke(
                            color.opacity(0.18),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: animate ? progress : 0)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.75), value: animate)

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }

                // Value
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(formattedValue)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(isDark ? .white : .black)
                            .monospacedDigit()
                        Text(unit)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))

                    Text("\(Int(progress * 100))% of \(Int(goal))\(unit)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(color.opacity(0.85))
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var formattedValue: String {
        if current <= 0 { return "—" }
        return unit == "kcal"
            ? String(format: "%.0f", current)
            : String(format: "%.0f", current)
    }
}

// MARK: - CalorieTrendChart

private struct CalorieTrendChart: View {
    let values: [Double]
    let goalLine: Double

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private static let dayLetters: [String] = {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "EEEEE"
        let today = Date()
        return (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { f.string(from: $0) }
        }
    }()

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxV = max(values.max() ?? 1, goalLine, 1)
                let count = values.count
                guard count > 0 else { return AnyView(EmptyView()) }

                let pts: [CGPoint] = values.enumerated().map { (i, v) in
                    let x = CGFloat(i) / CGFloat(max(count - 1, 1)) * w
                    let y = h - CGFloat(v / maxV) * h
                    return CGPoint(x: x, y: y)
                }

                let goalY = h - CGFloat(goalLine / maxV) * h

                return AnyView(
                    ZStack {
                        // Area fill
                        Path { p in
                            guard let first = pts.first else { return }
                            p.move(to: CGPoint(x: first.x, y: h))
                            p.addLine(to: first)
                            for pt in pts.dropFirst() { p.addLine(to: pt) }
                            if let last = pts.last {
                                p.addLine(to: CGPoint(x: last.x, y: h))
                            }
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Line
                        Path { p in
                            guard let first = pts.first else { return }
                            p.move(to: first)
                            for pt in pts.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Goal dashed line
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: goalY))
                            p.addLine(to: CGPoint(x: w, y: goalY))
                        }
                        .stroke(
                            Color.orange.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )

                        // Goal label
                        Text("Goal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.orange.opacity(0.7))
                            .position(x: w - 16, y: max(goalY - 7, 8))
                    }
                )
            }
            .frame(height: 90)

            // Day labels
            HStack(spacing: 0) {
                ForEach(Array(Self.dayLetters.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - FoodLogRow

private struct FoodLogRow: View {
    let entry: FoodLogEntry

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Food name + time
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)
                Text(entry.loggedAt, style: .time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }

            Spacer()

            // Calorie badge
            if entry.calories > 0 {
                Text("\(Int(entry.calories))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color.orange)
                + Text(" kcal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
        }

        // Compact P/C/F bar
        if entry.protein > 0 || entry.carbs > 0 || entry.fat > 0 {
            MacroMiniBar(protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
                .frame(height: 5)
                .padding(.top, 3)
        }
    }
}

// MARK: - MacroMiniBar

private struct MacroMiniBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        let total = max(protein + carbs + fat, 0.001)
        GeometryReader { geo in
            let w = geo.size.width
            let pW = CGFloat(protein / total) * w
            let cW = CGFloat(carbs   / total) * w
            let fW = CGFloat(fat     / total) * w

            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.36, green: 0.61, blue: 1.0))
                    .frame(width: pW, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGreen))
                    .frame(width: cW, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemYellow))
                    .frame(width: fW, height: 5)
            }
        }
    }
}

// MARK: - MicroChip

private struct MicroChip: View {
    let label: String
    let value: Double
    let rdaGoal: Double
    let unit: String
    let color: Color
    let icon: String

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var progress: Double {
        guard rdaGoal > 0 else { return 0 }
        return min(value / rdaGoal, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                    Spacer()
                    if value > 0 {
                        Text(formattedValue)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                        + Text(" \(unit)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(Int(progress * 100))% of RDA")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private var formattedValue: String {
        value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - MacroGoalsEditorSheet

public struct MacroGoalsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var nut = NutritionService.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    // Local draft state — applied on Done
    @State private var calories: Double = 0
    @State private var protein: Double  = 0
    @State private var carbs: Double    = 0
    @State private var fat: Double      = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard

                    goalStepper(
                        label: "Daily Calories",
                        unit: "kcal",
                        value: $calories,
                        range: 800...5000,
                        step: 50,
                        color: .orange,
                        icon: "flame.fill"
                    )
                    goalStepper(
                        label: "Protein",
                        unit: "g",
                        value: $protein,
                        range: 30...400,
                        step: 5,
                        color: Color(red: 0.36, green: 0.61, blue: 1.0),
                        icon: "bolt.fill"
                    )
                    goalStepper(
                        label: "Carbohydrates",
                        unit: "g",
                        value: $carbs,
                        range: 50...600,
                        step: 5,
                        color: Color(.systemGreen),
                        icon: "leaf.fill"
                    )
                    goalStepper(
                        label: "Fat",
                        unit: "g",
                        value: $fat,
                        range: 20...250,
                        step: 5,
                        color: Color(.systemYellow),
                        icon: "drop.fill"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AdaptiveBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Macro Goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { resetToDefaults() }
                        .foregroundColor(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { applyAndDismiss() }
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
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Set your daily macro targets")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text("Rings and percentages update to match your goals.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func goalStepper(
        label: String,
        unit: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        color: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                }
                Spacer(minLength: 0)
                // Stepper control
                HStack(spacing: 2) {
                    Button {
                        let newVal = max(range.lowerBound, value.wrappedValue - step)
                        value.wrappedValue = newVal
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(value.wrappedValue))")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                        .frame(minWidth: 54, alignment: .center)
                        .monospacedDigit()

                    Button {
                        let newVal = min(range.upperBound, value.wrappedValue + step)
                        value.wrappedValue = newVal
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }

                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                    .frame(width: 28, alignment: .leading)
            }

            Slider(value: value, in: range, step: step)
                .tint(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func seedValues() {
        let g = nut.macroGoals
        calories = g.calories
        protein  = g.protein
        carbs    = g.carbs
        fat      = g.fat
    }

    private func applyAndDismiss() {
        nut.setCaloriesGoal(calories)
        nut.setProteinGoal(protein)
        nut.setCarbsGoal(carbs)
        nut.setFatGoal(fat)
        dismiss()
    }

    private func resetToDefaults() {
        calories = MacroGoals.defaults.calories
        protein  = MacroGoals.defaults.protein
        carbs    = MacroGoals.defaults.carbs
        fat      = MacroGoals.defaults.fat
    }
}
