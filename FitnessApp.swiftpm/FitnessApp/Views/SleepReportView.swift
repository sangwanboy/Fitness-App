import SwiftUI

/// Morning report after a sleep session ends. Big duration number, restlessness
/// score, snore episodes count, motion timeline, stage breakdown. The user
/// can save to HealthKit or discard.
public struct SleepReportView: View {
    let session: SleepSession
    let onClose: () -> Void

    @State private var saving = false
    @State private var saved = false
    @State private var appeared = false
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    private var isDark: Bool { themeMode == "dark" }
    private var accent: Color { ThemeHelper.color(from: accentColorHex) }

    /// Pattern is computed from all *other* sessions so the comparison
    /// excludes the night the user is currently looking at.
    private var pattern: SleepPattern {
        let others = SleepSessionStore.shared.sessions.filter { $0.id != session.id }
        return SleepPatternAnalyzer.compute(from: others)
    }

    public init(session: SleepSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    durationCard
                    if pattern.hasEnoughHistory {
                        patternComparisonCard
                    }
                    snoreCard
                    motionTimelineCard
                    stageBreakdownCard
                    askAstraButton
                    actionRow
                }
                .padding(20)
                .padding(.top, 24)
                .padding(.bottom, 60)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.1)) {
                        appeared = true
                    }
                }
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }

    /// "Compared to your pattern" — shows duration delta, restlessness delta,
    /// snore delta against the user's rolling median. Only renders once we
    /// have ≥3 sessions of history.
    private var patternComparisonCard: some View {
        let durMin = Int(session.totalDurationSeconds / 60)
        let dDur = durMin - pattern.medianDurationMinutes
        let dRest = session.restlessnessScore - pattern.medianRestlessness
        let dSnore = session.snoreEpisodes.count - pattern.medianSnoreEpisodes
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.cyan)
                Text("Compared to your pattern")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.cyan)
                Spacer()
                Text("\(pattern.sessionCount) nights")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }
            HStack(spacing: 14) {
                deltaStat(label: "Duration",   delta: dDur,   unit: "min", lowerIsBetter: false)
                deltaStat(label: "Restless",   delta: dRest,  unit: "%",   lowerIsBetter: true)
                deltaStat(label: "Snores",     delta: dSnore, unit: "",    lowerIsBetter: true)
            }
            if let trend = pattern.weeklyTrendMinutes {
                Text(trend >= 0
                     ? "Your 7-day median is up **+\(trend) min** vs the prior week."
                     : "Your 7-day median is down **\(trend) min** vs the prior week.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    /// Quick handoff into Astra with last night's report queued as a follow-up
    /// prompt. ChatPrefillBus routes the user to the Coach tab automatically.
    private var askAstraButton: some View {
        Button {
            let prompt = """
            I just finished a sleep tracking session — \(formatDuration(session.totalDurationSeconds)) total. \
            Restlessness \(session.restlessnessScore)%, \(session.snoreEpisodes.count) snore episodes (\(Int(session.totalSnoreSeconds / 60)) min). \
            Walk me through what went well, what's off, and what to change tonight.
            """
            ChatPrefillBus.shared.queue(prompt)
            onClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                Text("Ask Astra about this night")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [.indigo, .purple],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func deltaStat(label: String, delta: Int, unit: String, lowerIsBetter: Bool) -> some View {
        let good = lowerIsBetter ? (delta <= 0) : (delta >= 0)
        let color: Color = delta == 0 ? .gray : (good ? .green : .red)
        let sign = delta >= 0 ? "+" : ""
        return VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            HStack(spacing: 2) {
                Image(systemName: delta == 0 ? "minus" : (delta > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 10, weight: .bold))
                Text("\(sign)\(delta)\(unit)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ s: Double) -> String {
        let secs = Int(s)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("GOOD MORNING")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                Text("Last night's sleep")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .tracking(-0.5)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(durationText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.indigo)
                    .tracking(-1)
                Text("asleep")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            HStack(spacing: 18) {
                miniLabel("In bed", inBedText)
                miniLabel("To sleep", onsetLatencyText)
                miniLabel("Restless", "\(session.restlessnessScore)%")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var snoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.purple)
                Text("Snoring")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.purple)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                bigStat("\(session.snoreEpisodes.count)", "episodes", color: .purple)
                bigStat(snoreDurText, "total", color: .purple.opacity(0.7))
                if let peak = session.snoreEpisodes.map(\.peakConfidence).max() {
                    bigStat("\(Int(peak * 100))%", "peak", color: .purple.opacity(0.5))
                }
            }
            if session.snoreEpisodes.isEmpty {
                Text("Quiet night — no snoring detected.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var motionTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.indigo)
                Text("Movement timeline")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.indigo)
                Spacer()
            }
            MotionTimelineChart(session: session, accent: .indigo)
                .frame(height: 64)
            HStack {
                Text(session.startedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                Spacer()
                Text(session.endedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var stageBreakdownCard: some View {
        let stages = session.stageBreakdown
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.cyan)
                Text("Stages (motion-inferred)")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.cyan)
                Spacer()
            }
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.cyan.opacity(0.9))
                        .frame(width: geo.size.width * fraction(stages.deep))
                    Rectangle().fill(Color.cyan.opacity(0.55))
                        .frame(width: geo.size.width * fraction(stages.light))
                    Rectangle().fill(Color.orange.opacity(0.8))
                        .frame(width: geo.size.width * fraction(stages.awake))
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack(spacing: 18) {
                legendDot("Deep",  "\(stages.percent(stages.deep))%",  .cyan.opacity(0.9))
                legendDot("Light", "\(stages.percent(stages.light))%", .cyan.opacity(0.55))
                legendDot("Awake", "\(stages.percent(stages.awake))%", .orange.opacity(0.8))
            }
            Text("Inferred from motion only — without a Watch, REM can't be separated. Treat the deep/light split as a movement-based proxy.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    saving = true
                    await SleepSessionManager.shared.persist(session, writeToHealthKit: true)
                    saving = false
                    saved = true
                }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().controlSize(.small).tint(.white) }
                    else if saved { Image(systemName: "checkmark") }
                    else { Image(systemName: "heart.text.square.fill") }
                    Text(saved ? "Saved to Health" : "Save to Apple Health")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [.indigo, .purple],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
            }
            .disabled(saving || saved)
            .buttonStyle(PlainButtonStyle())

            Button {
                Task {
                    await SleepSessionManager.shared.persist(session, writeToHealthKit: false)
                    onClose()
                }
            } label: {
                Text("Keep in app only")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    private var durationText: String {
        let s = Int(session.totalDurationSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private var inBedText: String {
        let s = Int(session.inBedSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private var onsetLatencyText: String {
        let s = Int(session.onsetLatencySeconds)
        return s < 60 ? "<1m" : "\(s / 60)m"
    }
    private var snoreDurText: String {
        let s = Int(session.totalSnoreSeconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m"
    }

    private func fraction(_ x: Double) -> CGFloat {
        let t = session.stageBreakdown.total
        return t > 0 ? CGFloat(x / t) : 0
    }

    private func miniLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
        }
    }

    private func bigStat(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendDot(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(value)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
    }
}

// MARK: - Motion timeline

private struct MotionTimelineChart: View {
    let session: SleepSession
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let samples = session.motionSamples
            let maxRMS = max(samples.map(\.rms).max() ?? 1, 1)
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .leading) {
                // Onset marker
                if !samples.isEmpty {
                    let onsetFrac = onsetFraction(samples: samples)
                    Rectangle()
                        .fill(Color.yellow.opacity(0.5))
                        .frame(width: 1, height: h)
                        .offset(x: w * onsetFrac)
                }
                // Bars per sample
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                        let frac = CGFloat(s.rms / maxRMS)
                        let color: Color = {
                            switch s.kind {
                            case .stillness: return accent.opacity(0.4)
                            case .micro:     return accent.opacity(0.7)
                            case .gross:     return Color.orange
                            }
                        }()
                        Capsule()
                            .fill(color)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, h * frac))
                    }
                }
                // Snore episode dots along the top
                ForEach(session.snoreEpisodes) { ep in
                    let frac = snoreFraction(ep: ep)
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 5, height: 5)
                        .offset(x: w * frac - 2, y: -h * 0.5 + 4)
                }
            }
        }
    }

    private func onsetFraction(samples: [MotionSample]) -> CGFloat {
        let total = session.endedAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(session.onsetAt.timeIntervalSince(session.startedAt) / total)
    }

    private func snoreFraction(ep: SnoreEpisode) -> CGFloat {
        let total = session.endedAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(ep.startedAt.timeIntervalSince(session.startedAt) / total)
    }
}
