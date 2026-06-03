import SwiftUI

public struct DashboardView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @ObservedObject private var eventKit = EventKitManager.shared
    @ObservedObject private var widgetStore = AstraWidgetStore.shared

    // Configurations
    @AppStorage("athlete_name") private var athleteName = "Alex Rivera"
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("layout_density") private var layoutDensity = "regular"
    @AppStorage("home_cards_list") private var homeCardsList = "coach,predictions,widgets,activity,upcoming,steps,heart,tracksleep,sleep,calories,distance,meals,recovery,hydration,workouts,streak,challenge"

    let onOpenWorkout: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenSleepMode: () -> Void
    let switchToTab: (String) -> Void

    @State private var lastSleepReport: SleepSession?

    @State private var selectedMetric: HealthMetricType?
    @State private var animateWidgets = false
    @State private var showSearchSheet = false
    @State private var showMoreMetrics = false
    @State private var showBreathing = false
    @State private var showNutritionDashboard = false
    /// startOfDay for each day in last 7 that had a HK workout (drives the
    /// Workouts This Week checkmark row).
    @State private var workoutDates: Set<Date> = []
    @State private var showWorkoutAnalytics = false
    @State private var showHRZones = false
    @State private var lastRefreshed: Date? = nil
    @State private var showFoodPhotoFlow = false

    /// Tiles revealed by tapping "Show more". When the user has no Apple Watch
    /// (no HR samples in the last 7 days), the Watch-only home cards collapse
    /// into Show More instead — they'd just read "—" on the home grid otherwise.
    private var extraMetricTypes: [HealthMetricType] {
        // Show More now contains ONLY metrics without recent data. Any metric
        // with real data has already been promoted to the main grid via
        // `visibleCardIds`, so this section is purely the "No data yet" tiles.
        var list: [HealthMetricType] = [
            .restingEnergy, .flightsClimbed, .exerciseMinutes, .standHours,
            .walkingSpeed, .walkingStepLength,
            .walkingDoubleSupport, .walkingAsymmetry,
            .restingHeartRate, .bodyMass, .mindfulMinutes,
            .oxygenSaturation, .vo2Max, .headphoneAudio
        ]

        // Pull any canonical home metric that's currently hidden (no recent
        // data) into Show More so the user can still see a "No data yet"
        // tile for it.
        let allHomeIds = homeCardsList.components(separatedBy: ",").reversed()
        for id in allHomeIds {
            guard let type = Self.cardIdToMetric[id] else { continue }
            guard !Self.metricHasRecentData(type, manager: healthKitManager) else { continue }
            if !list.contains(type) {
                list.insert(type, at: 0)
            }
        }

        // Watch-class fallbacks at the top when no Watch is paired AND those
        // metrics don't already have data (they shouldn't on iPhone-only).
        if !healthKitManager.hasWatchClassData {
            for type in [HealthMetricType.heartRate, .hrv] where !list.contains(type) {
                list.insert(type, at: 0)
            }
        }

        // Filter out anything that actually has recent data — those are now
        // on the main grid, not in Show More.
        return list.filter { !Self.metricHasRecentData($0, manager: healthKitManager) }
    }

    /// Card IDs that require Watch-class data to be meaningful. Hidden from the
    /// default home grid on iPhone-only setups; the underlying metrics are still
    /// reachable via Show More.
    private static let watchOnlyHomeCardIds: Set<String> = ["activity", "heart", "recovery"]

    /// Map from home-card ID to the HealthMetricType backing it. Used to decide
    /// whether a card has meaningful data (and to push it into Show More
    /// automatically when it doesn't).
    private static let cardIdToMetric: [String: HealthMetricType] = [
        "steps":     .steps,
        "heart":     .heartRate,
        "sleep":     .sleep,
        "calories":  .activeEnergy,
        "distance":  .distance,
        "recovery":  .hrv,
        "hydration": .hydration
    ]

    /// Card IDs that are always visible regardless of underlying data. The
    /// Coach + Predictions cards render their own empty states (and the user
    /// expects them as anchor surfaces); excluding them would make the home
    /// feel hollow on a fresh install.
    private static let alwaysVisibleCardIds: Set<String> = ["coach", "predictions", "tracksleep"]

    /// Whether the given home card has meaningful data to display. For
    /// metric-backed cards a card counts as "has data" if today's currentValue
    /// OR any sample in the last 7 days of history is non-zero — so a card
    /// stays visible through one quiet day (e.g. a missed sleep night) rather
    /// than flapping in and out of Show More.
    private func cardHasData(_ id: String) -> Bool {
        if Self.alwaysVisibleCardIds.contains(id) { return true }
        if id == "activity" {
            return healthKitManager.hasWatchClassData
        }
        if id == "upcoming" {
            let now = Date()
            let cutoff = now.addingTimeInterval(24 * 3600)
            return eventKit.events.contains { $0.startDate > now && $0.startDate < cutoff }
        }
        if id == "workouts" {
            return !workoutDates.isEmpty
        }
        if id == "meals" {
            return !healthKitManager.todayFoodLog.isEmpty
        }
        if id == "widgets" {
            return !AstraWidgetStore.shared.widgets.isEmpty
        }
        if id == "streak" {
            return true
        }
        if id == "challenge" {
            return true
        }
        if let type = Self.cardIdToMetric[id] {
            return Self.metricHasRecentData(type, manager: healthKitManager)
        }
        return true
    }

    /// True when a metric has any non-zero reading in the last 7 days. Used
    /// both by `cardHasData` (to decide what stays on the home grid) and by
    /// `extraMetricTypes` (to decide which empty cards to surface in Show More).
    /// Static so call sites don't capture `self`.
    private static func metricHasRecentData(_ type: HealthMetricType,
                                            manager: HealthKitManager) -> Bool {
        guard let summary = manager.metricSummaries[type] else { return false }
        if summary.currentValue > 0 { return true }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date())) ?? Date()
        return summary.history.contains { $0.date >= cutoff && $0.value > 0 }
    }

    public init(onOpenWorkout: @escaping () -> Void,
                onOpenCalendar: @escaping () -> Void,
                onOpenSleepMode: @escaping () -> Void = {},
                switchToTab: @escaping (String) -> Void = { _ in }) {
        self.onOpenWorkout = onOpenWorkout
        self.onOpenCalendar = onOpenCalendar
        self.onOpenSleepMode = onOpenSleepMode
        self.switchToTab = switchToTab
    }
    
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    private var firstName: String { athleteName.components(separatedBy: " ").first ?? "Alex" }
    
    private var visibleCardIds: [String] {
        let all = homeCardsList.components(separatedBy: ",").filter { !$0.isEmpty }
        let watchFiltered = healthKitManager.hasWatchClassData
            ? all
            : all.filter { !Self.watchOnlyHomeCardIds.contains($0) }
        // Canonical cards that have data right now.
        let canonicalVisible = watchFiltered.filter { cardHasData($0) }

        // Promote any non-canonical metric that ACTUALLY has data in the
        // last 7 days onto the main grid as a SimpleMetricCard tile. This
        // catches show-more metrics that the user clearly tracks (resting
        // energy, walking speed, weight, etc.) so they aren't buried.
        let canonicalTypes = Set(Self.cardIdToMetric.values)
        let promoted = HealthMetricType.allCases
            .filter { !canonicalTypes.contains($0) }
            .filter { Self.metricHasRecentData($0, manager: healthKitManager) }
            .map { $0.rawValue }

        return canonicalVisible + promoted
    }
    
    private var gridSpacing: CGFloat {
        switch layoutDensity {
        case "compact": return 8
        case "comfy": return 20
        default: return 14
        }
    }
    
    private var paddingVal: CGFloat {
        switch layoutDensity {
        case "compact": return 10
        case "comfy": return 22
        default: return 16
        }
    }
    
    private var wideCardIds: Set<String> { ["coach", "predictions", "activity", "upcoming", "workouts", "meals", "widgets", "tracksleep", "challenge"] }

    // Pairs narrow cards into rows, emits wide cards on their own row.
    // Mirrors CSS grid auto-flow with grid-column: span 2 for wide cards.
    private var packedRows: [[String]] {
        var rows: [[String]] = []
        var pending: [String] = []
        for id in visibleCardIds {
            if wideCardIds.contains(id) {
                if !pending.isEmpty { rows.append(pending); pending = [] }
                rows.append([id])
            } else {
                pending.append(id)
                if pending.count == 2 { rows.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { rows.append(pending) }
        return rows
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: gridSpacing) {
                ForEach(Array(packedRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        ForEach(row, id: \.self) { cardId in
                            // A narrow card alone on its row renders in its wide
                            // layout so it fills the width instead of stretching.
                            cardView(for: cardId, isWide: row.count == 1 && !wideCardIds.contains(cardId))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .opacity(animateWidgets ? 1.0 : 0.0)
                                .offset(y: animateWidgets ? 0.0 : 15.0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Show more / Show less expandable grid of extra HealthKit tiles.
                if showMoreMetrics {
                    let pairs = stride(from: 0, to: extraMetricTypes.count, by: 2).map { i in
                        Array(extraMetricTypes[i..<min(i + 2, extraMetricTypes.count)])
                    }
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .top, spacing: gridSpacing) {
                            ForEach(pair, id: \.self) { metric in
                                // An odd last tile renders in its wide layout so
                                // it fills the row instead of being half-empty.
                                SimpleMetricCard(
                                    type: metric,
                                    summary: healthKitManager.metricSummaries[metric],
                                    isWide: pair.count == 1,
                                    action: { selectedMetric = metric }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                }

                showMoreButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveBackground())
        .refreshable {
            // Pull-to-refresh forces a fresh AI enrichment too; cold-launches keep the cache.
            healthKitManager.invalidateAIPredictionCache()
            await refreshAllData()
        }
        .navigationTitle("Hi, \(firstName)")
        .navigationSubtitle(currentDateString())
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showFoodPhotoFlow = true } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .accessibilityLabel("Scan a meal")
                Button { showSearchSheet = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: onOpenCalendar) {
                    Image(systemName: "calendar")
                }
                Button { switchToTab("profile") } label: {
                    avatarView
                }
            }
        }
        .sheet(isPresented: $showSearchSheet) { HomeSearchSheet() }
        .sheet(isPresented: $showNutritionDashboard) { NutritionDashboardView() }
        .sheet(isPresented: $showFoodPhotoFlow) { FoodScanView() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { animateWidgets = true }
            let isStale = lastRefreshed.map { Date().timeIntervalSince($0) > 300 } ?? true
            guard isStale else { return }
            lastRefreshed = Date()
            Task { await refreshAllData() }
        }
        .sheet(item: $selectedMetric) { metricType in
            if let summary = healthKitManager.metricSummaries[metricType] {
                DetailedMetricView(summary: summary)
            }
        }
        .sheet(isPresented: $showBreathing) {
            GuidedBreathingView()
        }
        .sheet(isPresented: $showHRZones) {
            HeartRateZonesView()
        }
        .sheet(isPresented: $showWorkoutAnalytics) {
            WorkoutAnalyticsView()
        }
        .fullScreenCover(item: $lastSleepReport) { s in
            SleepReportView(session: s, onClose: { lastSleepReport = nil })
        }
    }

    private var showMoreButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                showMoreMetrics.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(showMoreMetrics ? "Show less" : "Show more health data")
                Image(systemName: showMoreMetrics ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(accentColor)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [accentColor, .purple],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
            Text(avatarInitials())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Card Router
    @ViewBuilder
    private func cardView(for id: String, isWide: Bool = false) -> some View {
        switch id {
        case "coach":
            Button(action: { switchToTab("chat") }) {
                coachCardView
            }
            .buttonStyle(PlainButtonStyle())
        case "predictions":
            PredictionsCard(
                predictions: healthKitManager.predictions,
                onOpenCoach: { switchToTab("chat") },
                onTapActionChip: { switchToTab("chat") },
                onOpenBreathe: { showBreathing = true }
            )
        case "activity":
            ActivityRingsCard(action: { ExternalLink.openHealth() })
        case "upcoming":
            upcomingWorkoutCardView
        case "steps":
            StepsCard(summary: healthKitManager.metricSummaries[.steps], isWide: isWide) {
                selectedMetric = .steps
            }
        case "heart":
            HeartCard(summary: healthKitManager.metricSummaries[.heartRate], isWide: isWide) {
                selectedMetric = .heartRate
            }
            .contextMenu {
                Button {
                    showHRZones = true
                } label: {
                    Label("View HR Zones", systemImage: "waveform.path.ecg")
                }
                Button {
                    selectedMetric = .heartRate
                } label: {
                    Label("View Details", systemImage: "chart.xyaxis.line")
                }
            }
        case "sleep":
            SleepCard(summary: healthKitManager.metricSummaries[.sleep], isWide: isWide) {
                selectedMetric = .sleep
            }
        case "calories":
            CaloriesCard(summary: healthKitManager.metricSummaries[.activeEnergy], isWide: isWide) {
                selectedMetric = .activeEnergy
            }
        case "distance":
            DistanceCard(summary: healthKitManager.metricSummaries[.distance], isWide: isWide) {
                selectedMetric = .distance
            }
        case "recovery":
            RecoveryCard(summary: healthKitManager.metricSummaries[.hrv], isWide: isWide) {
                selectedMetric = .hrv
            }
        case "hydration":
            HydrationCard(summary: healthKitManager.metricSummaries[.hydration], isWide: isWide) {
                selectedMetric = .hydration
            }
        case "workouts":
            weeklyWorkoutsCardView
        case "meals":
            MealsCard(
                entries: healthKitManager.todayFoodLog,
                onAddMeal: {
                    showFoodPhotoFlow = true
                },
                onViewDetails: {
                    showNutritionDashboard = true
                }
            )
        case "widgets":
            WidgetsCard(onAskAstra: { switchToTab("chat") })
        case "tracksleep":
            SleepTrackingCard(
                onStartTracking: onOpenSleepMode,
                onOpenLast: { lastSleepReport = $0 }
            )
        case "streak":
            StreakCard(isWide: isWide)
        case "challenge":
            DailyChallengeCard()
        default:
            // Promoted show-more metric: id is the HealthMetricType.rawValue.
            // Renders as a SimpleMetricCard tile (same as in Show More) so
            // visual consistency stays — just placed inline on the home grid.
            if let type = HealthMetricType(rawValue: id) {
                SimpleMetricCard(
                    type: type,
                    summary: healthKitManager.metricSummaries[type],
                    isWide: isWide,
                    action: { selectedMetric = type }
                )
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - AI Coach Card
    private var coachCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                Text("AI COACH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .tracking(0.5)
            }
            
            Text(coachTeaserText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                .lineSpacing(4)
        }
        .padding(paddingVal)
        .glassCard(glowColor: accentColor.opacity(0.06))
    }
    
    // MARK: - Upcoming Workout (next EKEvent in the next 24h, or empty state)
    private var upcomingWorkoutCardView: some View {
        let next = eventKit.events.first { $0.startDate > Date() }
        let title: String = next?.title ?? "No events scheduled"
        let subtitle: String = {
            guard let next else { return "Plan your day" }
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            let minutes = max(0, Int(next.endDate.timeIntervalSince(next.startDate) / 60))
            return minutes > 0 ? "\(f.string(from: next.startDate)) · \(minutes) min" : f.string(from: next.startDate)
        }()
        let action: () -> Void = next == nil ? onOpenCalendar : onOpenWorkout

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 48, height: 48)

                Image(systemName: next == nil ? "calendar" : "figure.run")
                    .foregroundColor(accentColor)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
            }

            Spacer()

            Button(action: action) {
                Image(systemName: next == nil ? "calendar.badge.plus" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(accentColor)
                    .clipShape(Circle())
            }
        }
        .padding(paddingVal)
        .glassCard()
    }

    /// Reloads everything the Home grid surfaces: today's HealthKit metrics,
    /// last-7-days workouts, the next 24h of app calendar events, and the
    /// active reminders. Called from both `.onAppear` and pull-to-refresh so
    /// the user gets a true full refresh every time they pull down.
    private func refreshAllData() async {
        async let hk: Void = healthKitManager.fetchTodayData()
        async let workouts = healthKitManager.fetchRecentWorkouts(days: 7)
        _ = await hk
        let cal = Calendar.current
        workoutDates = Set(await workouts.map { cal.startOfDay(for: $0.startDate) })
        // Recompute streak after workout + step data is fresh.
        StreakEngine.shared.refresh()
        if eventKit.calendarsGranted {
            eventKit.fetchEvents(from: Date(), to: Date().addingTimeInterval(24 * 3600))
        }
        if eventKit.remindersGranted {
            await eventKit.fetchReminders()
        }
    }

    /// Computed coach preview line — deterministic, not an AI call. Mirrors the
    /// thresholds used by the Recovery tile.
    private var coachTeaserText: String {
        let hrv = healthKitManager.metricSummaries[.hrv]?.currentValue ?? 0
        let rhr = healthKitManager.metricSummaries[.restingHeartRate]?.currentValue ?? 0
        let steps = healthKitManager.metricSummaries[.steps]?.currentValue ?? 0
        let stepsGoal = healthKitManager.metricSummaries[.steps]?.goal ?? 10000

        // No Watch = no HRV / resting HR at all. Steer the message toward
        // what the user CAN see (today's activity), not toward a permission
        // dialog they don't actually need.
        if hrv == 0 && rhr == 0 {
            if !healthKitManager.hasWatchClassData {
                let pct = stepsGoal > 0 ? Int(min(steps / stepsGoal, 1) * 100) : 0
                if steps > 0 {
                    return "\(Int(steps)) steps so far — \(pct)% of today's goal. Pair an Apple Watch to unlock recovery and HRV insights."
                }
                return "iPhone-only setup. Pair an Apple Watch to unlock recovery (HRV) and heart-rate insights."
            }
            return "No recovery data yet today — make sure you wore your watch overnight."
        }
        if hrv >= 70 {
            return "Recovery is strong — HRV at \(Int(hrv)) ms. Good day to push intensity."
        }
        if hrv >= 50 {
            return "Moderate recovery (HRV \(Int(hrv)) ms). Consider a steady zone-2 session."
        }
        if hrv > 0 {
            return "Recovery low — HRV \(Int(hrv)) ms. Active recovery or rest today."
        }
        return "Resting HR \(Int(rhr)) bpm. HRV not available — wear your watch overnight for recovery insights."
    }
    
    // MARK: - Weekly Workouts Card (real HK workouts over last 7 days)
    private var weeklyWorkoutsCardView: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0..<7).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
        let symbols = cal.veryShortWeekdaySymbols // ["S","M","T","W","T","F","S"]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Workouts This Week")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isDark ? .white : .black)

            HStack(spacing: 12) {
                ForEach(days, id: \.self) { day in
                    let isCompleted = workoutDates.contains(day)
                    let weekday = cal.component(.weekday, from: day) - 1
                    VStack(spacing: 8) {
                        Text(symbols[weekday])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))

                        Circle()
                            .fill(isCompleted ? accentColor : Color.clear)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(isCompleted ? Color.clear : (isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)), lineWidth: 1.5)
                            )
                            .overlay(
                                Group {
                                    if isCompleted {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button(action: { showWorkoutAnalytics = true }) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Text("View Training Analytics")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                }
                .foregroundColor(accentColor)
                .padding(.top, 4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(paddingVal)
        .glassCard()
    }
    
    // MARK: - Helper Methods
    private func avatarInitials() -> String {
        let words = athleteName.components(separatedBy: " ")
        let initials = words.compactMap { $0.first }.map { String($0) }.joined()
        return String(initials.prefix(2)).uppercased()
    }
    
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}
