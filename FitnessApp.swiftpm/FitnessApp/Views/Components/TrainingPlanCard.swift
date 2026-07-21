import SwiftUI

/// Progress-hub card for the Astra-authored weekly training plan
/// (`TrainingPlanStore`) — "this week at a glance": 7 day chips (initial +
/// kind icon, filled when completed, today highlighted), the next planned
/// session, an adherence ring, and a one-tap "Mark done" for today's
/// session. Visual conventions mirror `WeeklyReviewCard` (`.glassCard()`,
/// the `theme_mode` `isDark` pattern, reduce-motion-gated animation) so it
/// reads as the same family of hub card.
public struct TrainingPlanCard: View {
    @ObservedObject private var store = TrainingPlanStore.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if store.activePlan == nil {
                emptyState
            } else {
                weekChipsRow
                Divider().opacity(0.15)
                nextSessionRow
                if let today = todaySession, !today.completed {
                    markDoneButton(for: today)
                } else if let today = todaySession, today.completed {
                    doneTodayLabel
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("TRAINING PLAN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .tracking(0.5)
                    .lineLimit(1)
                if let plan = store.activePlan {
                    Text(Self.weekLabel(plan.weekStart))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.35) : .black.opacity(0.35))
                }
            }
            Spacer()
            if let adherence {
                adherenceRing(adherence)
            }
        }
    }

    private static func weekLabel(_ weekStart: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(f.string(from: weekStart)) \u{2013} \(f.string(from: end))"
    }

    // MARK: - Empty state (honest — no plan authored yet)

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
            Text("No plan yet \u{2014} ask Astra to build your week")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Week chips (Monday...Sunday, always 7 — honest gaps for unplanned days)

    private var weekChipsRow: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monday = TrainingPlanStore.mondayOfWeek(containing: Date(), calendar: cal)
        let plannedByDay: [Date: TrainingPlanStore.PlannedDay] = Dictionary(
            uniqueKeysWithValues: store.currentWeekDays.map { (cal.startOfDay(for: $0.date), $0) }
        )
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: monday) ?? monday
                dayChip(date: date,
                       day: plannedByDay[cal.startOfDay(for: date)],
                       isToday: cal.isDate(date, inSameDayAs: today))
            }
        }
    }

    private func dayChip(date: Date, day: TrainingPlanStore.PlannedDay?, isToday: Bool) -> some View {
        let color = day.map { kindColor($0.kind) } ?? Color.gray
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(day?.completed == true ? color : color.opacity(day == nil ? 0.08 : 0.15))
                    .frame(width: 30, height: 30)
                if isToday {
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
                if let day {
                    Image(systemName: day.kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(day.completed ? .white : color)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: day?.completed)
            Text(Self.weekdayInitial(date))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
    }

    private static func weekdayInitial(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: date)
    }

    private func kindColor(_ kind: TrainingPlanStore.PlannedDay.Kind) -> Color {
        switch kind {
        case .strength: return .red
        case .cardio:   return .orange
        case .mobility: return .teal
        case .rest:     return .indigo
        }
    }

    // MARK: - Next session

    private var nextPlannedSession: TrainingPlanStore.PlannedDay? {
        guard let plan = store.activePlan else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return plan.days
            .filter { $0.kind != .rest && !$0.completed && cal.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
            .first
    }

    private var todaySession: TrainingPlanStore.PlannedDay? {
        guard let plan = store.activePlan else { return nil }
        let cal = Calendar.current
        return plan.days.first { cal.isDateInToday($0.date) && $0.kind != .rest }
    }

    @ViewBuilder
    private var nextSessionRow: some View {
        if let next = nextPlannedSession {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: next.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(kindColor(next.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next: \(next.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(Self.dayLabel(next.date)) \u{00B7} \(next.durationMin) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                Spacer()
            }
        } else if let plan = store.activePlan, !plan.days.filter({ $0.kind != .rest }).isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                Text("All planned sessions are done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.8) : .black.opacity(0.8))
            }
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }

    // MARK: - Mark done (today's session — instant, same convention as the
    // widget checklist tap-to-toggle: a direct local mutation, no confirm
    // sheet, since this is a UI-driven action rather than an LLM tool call).

    private func markDoneButton(for day: TrainingPlanStore.PlannedDay) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                _ = store.markCompleted(date: day.date)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                Text("Mark today's session done")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var doneTodayLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Today's session marked done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.green)
        }
    }

    // MARK: - Adherence ring

    private var adherence: TrainingPlanStore.Adherence? {
        guard let plan = store.activePlan else { return nil }
        return store.adherence(for: plan.weekStart)
    }

    private func adherenceRing(_ a: TrainingPlanStore.Adherence) -> some View {
        ZStack {
            Circle()
                .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(a.pct / 100))
                .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: a.pct)
            Text("\(Int(a.pct.rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
        }
        .frame(width: 34, height: 34)
    }
}
