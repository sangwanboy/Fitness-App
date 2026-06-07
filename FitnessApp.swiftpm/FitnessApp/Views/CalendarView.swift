import SwiftUI
import EventKit

// Calendar screen — 1:1 port of fitness-guru/project/screens-2.jsx CalendarScreen.
// Subtitle "OCTOBER 2025" + title "Calendar" on a single nav row, with Week/Month
// segmented pill + glass + (add) on the right. Week strip or month grid below,
// then a day plan list (real EKEvents) and an AI week-plan card.

public struct CalendarView: View {
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @ObservedObject private var ek = EventKitManager.shared
    @ObservedObject private var streakEngine = StreakEngine.shared

    let onBack: () -> Void
    let onOpenWorkout: () -> Void
    let onOpenChat: (() -> Void)?

    @State private var selectedDate: Date = Date()
    @State private var view: CalendarViewKind = .week
    @State private var showAddSheet = false
    @State private var newEventTitle = ""
    @State private var newEventStart = Date()
    @State private var newEventEnd = Date().addingTimeInterval(3600)

    enum CalendarViewKind: String, CaseIterable { case week = "Week", month = "Month" }

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init(onBack: @escaping () -> Void,
                onOpenWorkout: @escaping () -> Void,
                onOpenChat: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onOpenWorkout = onOpenWorkout
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        ZStack(alignment: .top) {
            AdaptiveBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if view == .week {
                        weekStrip
                    } else {
                        monthGrid
                    }

                    streakBanner
                        .padding(.top, 14)

                    sectionHeader(selectedDateLabel)
                    dayPlanCard

                    sectionHeader("This week's plan")
                    weekPlanCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 130)
                .padding(.bottom, 24)
            }
            .refreshable { reloadEvents() }

            // Custom header — back chevron on the left, title block centered-left,
            // compact view toggle + add on the right. All on one row.
            headerBar
        }
        .sheet(isPresented: $showAddSheet) { addEventSheet }
        .task { reloadEvents() }
        .onChange(of: selectedDate) { _ in reloadEvents() }
    }

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(monthLabel.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)
                    Text("Calendar")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                // Week / Month menu — compact glass pill, native Menu UI
                Menu {
                    ForEach(CalendarViewKind.allCases, id: \.self) { v in
                        Button(v.rawValue) { view = v }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(view.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(isDark ? .white : .black)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Helpers
    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedDate)
    }
    private var selectedDateLabel: String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(selectedDate) {
            f.dateFormat = "'Today,' MMM d"
        } else {
            f.dateFormat = "EEEE, MMM d"
        }
        return f.string(from: selectedDate)
    }

    private func reloadEvents() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate)
        let end = cal.date(byAdding: .day, value: 30, to: selectedDate) ?? selectedDate
        ek.fetchEvents(from: start, to: end)
    }

    private var eventsForSelectedDay: [EKEvent] {
        ek.events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
    }

    private var weekEvents: [Int] {
        // Returns event counts for each day of the current week (M..S)
        let cal = Calendar.current
        let weekDates = (0..<7).compactMap { i in
            cal.date(byAdding: .day, value: i - (cal.component(.weekday, from: selectedDate) - cal.firstWeekday), to: selectedDate)
        }
        return weekDates.map { d in
            ek.events.filter { cal.isDate($0.startDate, inSameDayAs: d) }.count
        }
    }

    // MARK: - Streak helpers

    /// Active week starts from StreakEngine (start-of-day, local).
    private var activeWeekStarts: Set<Date> {
        let cal = Calendar(identifier: .gregorian)
        return Set(
            streakEngine.weeklyActivity
                .filter { $0.isActive }
                .map { cal.startOfDay(for: $0.weekStart) }
        )
    }

    /// True if `date` falls within a week that counts toward the streak.
    private func isInStreakWeek(_ date: Date) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        // Find Monday on or before this date.
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2
        guard let monday = cal.date(from: comps) else { return false }
        return activeWeekStarts.contains(cal.startOfDay(for: monday))
    }

    /// Flame color matching StreakCard logic.
    private var flameColor: Color {
        let s = streakEngine.currentStreak
        if s == 0 { return .gray.opacity(0.5) }
        if s < 4  { return .orange.opacity(0.85) }
        if s < 13 { return .orange }
        return Color(red: 1.0, green: 0.45, blue: 0.1)
    }

    // MARK: - Streak banner

    private var streakBanner: some View {
        HStack(spacing: 12) {
            // Flame icon
            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(flameColor)

            // Current streak
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(streakEngine.currentStreak)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(streakEngine.currentStreak > 0 ? flameColor : (isDark ? .white.opacity(0.35) : .black.opacity(0.35)))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: streakEngine.currentStreak)
                    Text("week\(streakEngine.currentStreak == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                Text("Current streak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }

            Spacer(minLength: 8)

            // Best / longest streak
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("\(streakEngine.longestStreak)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: streakEngine.longestStreak)
                    Text("wk")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                Text("Best")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    // MARK: - Subviews
    private var weekStrip: some View {
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: selectedDate) - cal.firstWeekday), to: selectedDate) ?? selectedDate
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }

        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { date in
                let isSel = cal.isDate(date, inSameDayAs: selectedDate)
                let dayEvents = ek.events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
                Button { selectedDate = date } label: {
                    VStack {
                        VStack(spacing: 2) {
                            Text(weekdayLabel(date))
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.3)
                            Text("\(cal.component(.day, from: date))")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .tracking(-0.6)
                        }
                        .foregroundColor(isSel ? .white : (isDark ? .white : .black))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(0..<min(dayEvents.count, 3), id: \.self) { _ in
                                Circle()
                                    .fill(isSel ? Color.white : accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .frame(height: 80)
                    .background(
                        Group {
                            if isSel {
                                RoundedRectangle(cornerRadius: 14).fill(accentColor)
                            } else {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.clear)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, 4)
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let monthRange = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<32
        let firstWeekday = cal.component(.weekday, from: monthStart) - cal.firstWeekday
        let totalCells = 42
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .tracking(0.4)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<totalCells, id: \.self) { i in
                    let dayNumber = i - firstWeekday + 1
                    if dayNumber < 1 || dayNumber > monthRange.count {
                        Color.clear.frame(height: 44)
                    } else if let date = cal.date(byAdding: .day, value: dayNumber - 1, to: monthStart) {
                        let isSel = cal.isDate(date, inSameDayAs: selectedDate)
                        let isToday = cal.isDateInToday(date)
                        let dayEvents = ek.events.filter { cal.isDate($0.startDate, inSameDayAs: date) }
                        let isStreak = isInStreakWeek(date)
                        Button { selectedDate = date } label: {
                            VStack(spacing: 2) {
                                Text("\(dayNumber)")
                                    .font(.system(size: 14, weight: (isToday || isSel) ? .bold : .medium))
                                    .foregroundColor(isSel ? .white : (isDark ? .white : .black))
                                HStack(spacing: 2) {
                                    if isStreak && !isSel {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 5, weight: .bold))
                                            .foregroundColor(flameColor.opacity(0.8))
                                    }
                                    ForEach(0..<min(dayEvents.count, 2), id: \.self) { _ in
                                        Circle()
                                            .fill(isSel ? Color.white : accentColor)
                                            .frame(width: 3, height: 3)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Group {
                                    if isSel {
                                        RoundedRectangle(cornerRadius: 10).fill(accentColor)
                                    } else if isToday {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(accentColor, lineWidth: 1.5)
                                    } else if isStreak {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(flameColor.opacity(0.10))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .padding(.leading, 4)
    }

    private var dayPlanCard: some View {
        VStack(spacing: 0) {
            if eventsForSelectedDay.isEmpty {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing scheduled")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(isDark ? .white : .black)
                            Text("Tap + to add an event manually.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                        Spacer()
                    }
                    if let onOpenChat {
                        Button {
                            onBack()
                            onOpenChat()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Ask Astra to plan this day")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(colors: [accentColor, accentColor.opacity(0.75)],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(16)
            } else {
                ForEach(Array(eventsForSelectedDay.enumerated()), id: \.element.calendarItemIdentifier) { idx, ev in
                    DayEventRow(event: ev,
                                isLast: idx == eventsForSelectedDay.count - 1,
                                accentColor: accentColor)
                }
            }
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var weekPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(accentColor)
                Text("AI-built · Endurance block")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
                Spacer()
                Text("\(weekEvents.reduce(0, +)) sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }

            BarsChart(values: weekEvents.map { Double($0) },
                      labels: ["M","T","W","T","F","S","S"],
                      color: accentColor,
                      highlight: -1)
                .frame(height: 56)
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private func weekdayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }

    // MARK: - Add event sheet
    private var addEventSheet: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $newEventTitle)
                DatePicker("Start", selection: $newEventStart)
                DatePicker("End", selection: $newEventEnd)
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        if !newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                            _ = ek.addEvent(title: newEventTitle, startDate: newEventStart, endDate: newEventEnd)
                            newEventTitle = ""
                            showAddSheet = false
                            reloadEvents()
                        }
                    }
                    .bold()
                    .disabled(newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - DayEvent row
struct DayEventRow: View {
    let event: EKEvent
    let isLast: Bool
    let accentColor: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var color: Color {
        let cg: CGColor? = event.calendar.cgColor
        return cg.map { Color(cgColor: $0) } ?? accentColor
    }

    private var icon: String {
        let title = event.title.lowercased()
        if title.contains("run") || title.contains("workout") || title.contains("ride") { return "bolt.fill" }
        if title.contains("sleep") || title.contains("wind") { return "moon.fill" }
        if title.contains("standup") || title.contains("meeting") || title.contains("call") { return "calendar" }
        if title.contains("mobility") || title.contains("yoga") || title.contains("stretch") { return "arrow.clockwise.heart" }
        return "calendar"
    }

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: event.startDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 12)
                    .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        .tracking(0.3)
                    Text(event.title ?? "Untitled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .lineLimit(1)
                }
                .padding(.vertical, 10)

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(color.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                .padding(.trailing, 14)
            }
            if !isLast {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 30)
            }
        }
    }
}
