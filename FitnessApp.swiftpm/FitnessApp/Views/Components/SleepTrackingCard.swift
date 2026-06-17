import SwiftUI

/// Home card surfacing the on-device sleep tracker. Shows last night's
/// session summary if there is one; tapping the big "Track tonight" pill
/// opens `SleepModeView` fullscreen.
public struct SleepTrackingCard: View {
    @ObservedObject private var store = SleepSessionStore.shared
    @ObservedObject private var focus = SleepFocusDetector.shared
    let onStartTracking: () -> Void
    let onOpenLast: (SleepSession) -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("sleep_snore_enabled") private var snoreEnabled = true
    private var isDark: Bool { themeMode == "dark" }

    @State private var pattern: SleepPattern = .empty

    public init(onStartTracking: @escaping () -> Void,
                onOpenLast: @escaping (SleepSession) -> Void) {
        self.onStartTracking = onStartTracking
        self.onOpenLast = onOpenLast
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if focus.sleepFocusLikely || focus.isWithinBedtimeWindow {
                focusBanner
            }
            if pattern.hasEnoughHistory {
                patternRow
            }
            if let last = store.mostRecent, Calendar.current.isDateInToday(last.endedAt) ||
                Calendar.current.isDateInYesterday(last.endedAt) {
                lastSessionRow(last)
            }
            snoreToggleRow
            startButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .onAppear {
            pattern = SleepPatternAnalyzer.compute(from: store.sessions)
        }
        .onChange(of: store.sessions.count) { _, _ in
            pattern = SleepPatternAnalyzer.compute(from: store.sessions)
        }
    }

    /// Toggle row above the start button. Defaults to ON (snore detection).
    /// Turning it off skips the SoundAnalysis ML pipeline, saving roughly
    /// 1–2% battery over a full night — the mic + audio session still run
    /// (required for the audio background mode that keeps the app alive).
    private var snoreToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: snoreEnabled ? "waveform" : "waveform.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(snoreEnabled ? .purple : (isDark ? .white.opacity(0.5) : .black.opacity(0.5)))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Snore detection")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)
                Text(snoreEnabled ? "On-device classifier (Apple Sound Analysis)" : "Off · saves ~1–2% battery / night")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $snoreEnabled).labelsHidden().tint(.indigo)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    /// Banner that appears when Sleep Focus is likely on OR we're inside the
    /// learned bedtime window. Tappable — taps start tracking immediately.
    private var focusBanner: some View {
        Button(action: onStartTracking) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.indigo.opacity(0.2)).frame(width: 28, height: 28)
                    Image(systemName: focus.sleepFocusLikely ? "moon.fill" : "moon.haze.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.sleepFocusLikely ? "Sleep Focus is on" : "You're in your bedtime window")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(bedtimeWindowSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.indigo)
            }
            .padding(10)
            .glassEffect(.regular.tint(Color.indigo.opacity(0.10)).interactive(), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// One-line pattern summary — appears once user has 3+ tracked nights.
    private var patternRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.6))
            Text(pattern.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
    }

    private var bedtimeWindowSubtitle: String {
        if focus.sleepFocusLikely {
            return "Tap to start sleep tracking now"
        }
        if let bh = pattern.typicalBedtimeHour, let bm = pattern.typicalBedtimeMinute,
           let wh = pattern.typicalWakeHour, let wm = pattern.typicalWakeMinute {
            return "You usually sleep \(formatHM(bh, bm))–\(formatHM(wh, wm))"
        }
        return "Tap to start tracking"
    }

    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private func formatHM(_ h: Int, _ m: Int) -> String {
        var c = DateComponents(); c.hour = h; c.minute = m
        return Calendar.current.date(from: c).map { Self.hmFormatter.string(from: $0) } ?? "\(h):\(String(format: "%02d", m))"
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("SLEEP TRACKER")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .lineLimit(1)
            Spacer()
            Text("ON-DEVICE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.6))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((isDark ? Color.white : Color.black).opacity(0.06)))
        }
    }

    private func lastSessionRow(_ s: SleepSession) -> some View {
        Button { onOpenLast(s) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LAST NIGHT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.6))
                        .lineLimit(1)
                    Text(durationText(s))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.indigo)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                miniStat(value: "\(s.restlessnessScore)%", label: "restless")
                miniStat(value: "\(s.snoreEpisodes.count)", label: "snores")
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var startButton: some View {
        Button(action: onStartTracking) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Track tonight")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(snoreEnabled ? "Mic + motion · auto-saves to Health" : "Motion · battery saver")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                .lineLimit(1)
        }
    }

    private func durationText(_ s: SleepSession) -> String {
        let secs = Int(s.totalDurationSeconds)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
