import SwiftUI

/// Progress-hub card surfacing `WeeklyReviewEngine`'s trailing-7-day
/// aggregates + Astra's narrative. Visual/animation conventions mirror
/// `ProgressHubView`'s existing hub cards (`.glassCard()`, the
/// `theme_mode` AppStorage `isDark` pattern) and the delta-arrow convention
/// already used by `WidgetsCard.DeltaBlockView` / `SleepReportView.deltaStat`
/// / `ToolCards`' delta callout (green up / red down, flipped by
/// `lowerIsBetter`).
public struct WeeklyReviewCard: View {
    @ObservedObject private var engine = WeeklyReviewEngine.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { themeMode == "dark" }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let days = engine.insufficientDataDays {
                insufficientDataState(days: days)
            } else if let data = engine.data {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(data.stats) { stat in
                        statRow(stat)
                    }
                }

                Divider().opacity(0.15)

                narrativeSection(data)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: engine.narrativeState)

                actionButtons
            } else {
                loadingPlaceholder
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { engine.refreshIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.indigo, .purple],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 24, height: 24)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("WEEKLY REVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .tracking(0.5)
                    .lineLimit(1)
                if let data = engine.data {
                    Text(Self.weekRangeLabel(data))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.35) : .black.opacity(0.35))
                }
            }
            Spacer()
            Button(action: { engine.forceRefresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh weekly review")
        }
    }

    private static func weekRangeLabel(_ data: WeeklyReviewData) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(df.string(from: data.weekStart)) \u{2013} \(df.string(from: data.weekEnd))"
    }

    // MARK: - Insufficient data state

    private func insufficientDataState(days: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not enough data yet \u{2014} check back after a few days")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(days), total: 3)
                .progressViewStyle(.linear)
                .tint(.indigo)
            Text("\(days) of 3 days tracked this week")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
        }
    }

    // MARK: - Loading placeholder (brief — before the first synchronous compute lands)

    private var loadingPlaceholder: some View {
        Text("Loading weekly review\u{2026}")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
    }

    // MARK: - Stat rows

    private func statRow(_ stat: WeeklyMetricStat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: stat.metric.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(stat.metric.themeColor)
                .frame(width: 20)
            Text(stat.metric.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(displayValue(stat))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .monospacedDigit()
                .lineLimit(1)
            deltaChip(stat)
        }
    }

    private func displayValue(_ stat: WeeklyMetricStat) -> String {
        guard stat.dataDays > 0 else { return "\u{2014}" }
        switch stat.metric {
        case .steps:
            return "\(Int(stat.thisWeekAverage.rounded()))/day"
        case .activeEnergy:
            return "\(Int(stat.thisWeekTotal.rounded())) kcal"
        case .exerciseMinutes:
            return "\(Int(stat.thisWeekTotal.rounded())) min"
        case .sleep:
            return String(format: "%.1fh avg", stat.thisWeekAverage)
        case .restingHeartRate:
            return "\(Int(stat.thisWeekAverage.rounded())) bpm avg"
        default:
            return String(format: "%.1f", stat.thisWeekAverage)
        }
    }

    @ViewBuilder
    private func deltaChip(_ stat: WeeklyMetricStat) -> some View {
        if stat.dataDays == 0 {
            Text("No data")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.35) : .black.opacity(0.35))
        } else if stat.priorWeekAverage <= 0 {
            Text("New")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
        } else {
            let raw = stat.deltaPct
            let flat = abs(raw) < 1
            let goodDirection = stat.lowerIsBetter ? (raw <= 0) : (raw >= 0)
            let color: Color = flat ? .gray : (goodDirection ? .green : .red)
            HStack(spacing: 3) {
                Image(systemName: flat ? "minus" : (raw > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 9, weight: .bold))
                Text("\(raw >= 0 ? "+" : "")\(String(format: "%.0f", raw))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
        }
    }

    // MARK: - Narrative

    @ViewBuilder
    private func narrativeSection(_ data: WeeklyReviewData) -> some View {
        switch engine.narrativeState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Astra is reviewing your week\u{2026}")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
        case .ready:
            if let narrative = engine.narrative {
                VStack(alignment: .leading, spacing: 8) {
                    Text(narrative.summary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.indigo)
                        Text(narrative.focus)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.indigo)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .unavailable:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Narrative unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                Button(action: { engine.retryNarrative() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        Button(action: {
            ChatPrefillBus.shared.queue("Walk me through my weekly review and what to focus on next week.")
        }) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Discuss with Astra")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
