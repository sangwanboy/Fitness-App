import SwiftUI

/// Home card surfacing `MorningBriefEngine`'s richer, Astra-written morning
/// brief (Work Package B2). Sits above the AI Coach card / grid on
/// `DashboardView` so the day's most personalized content is the first thing
/// the user sees. Fully self-contained: reads `MorningBriefEngine.shared`
/// directly and decides its own visibility (`displayContent`) rather than
/// DashboardView deciding for it — matches the honest-empty-state rule
/// (no filler; no card at all when there's nothing real to show).
public struct MorningBriefCard: View {
    @ObservedObject private var engine = MorningBriefEngine.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    /// Callback to switch into Coach after queuing a follow-up prompt —
    /// mirrors how WidgetsCard / PredictionsCard hand off to the Coach tab.
    let onOpenCoach: () -> Void

    /// Shared with `NotificationManager.rescheduleMorningBrief`'s
    /// `chatPrompt` — both the notification tap and this card's "Ask Astra"
    /// button must land on the identical prompt.
    public static let coachPrompt = "Walk me through my morning brief"

    @State private var dismissedToday: Bool

    public init(onOpenCoach: @escaping () -> Void) {
        self.onOpenCoach = onOpenCoach
        _dismissedToday = State(initialValue: Self.isDismissedToday())
    }

    /// nil (→ hide the card entirely) before 5am, once the user dismissed
    /// today's brief, or when there's genuinely nothing real to show yet
    /// (no attempt has landed, or it landed with zero real stats).
    private var displayContent: BriefContent? {
        guard Calendar.current.component(.hour, from: Date()) >= 5 else { return nil }
        guard !dismissedToday else { return nil }
        guard let content = engine.todaysContent, !content.stats.isEmpty else { return nil }
        return content
    }

    public var body: some View {
        // A `Group` wrapper (rather than a bare `if`) so `.task` below always
        // attaches and runs — even on days the card renders nothing — instead
        // of only firing once content already exists, which would be
        // circular. `generateIfNeeded()` is the same call the BG refresh
        // handler and NotificationManager's foreground trigger already make;
        // this just covers the gap where DashboardView appears (e.g. a tab
        // switch) without a fresh "app became active" event in between.
        Group {
            if let content = displayContent {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    bodyText(content)
                    statChips(content.stats)
                    askAstraButton
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(glowColor: Color.indigo.opacity(0.06))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: dismissedToday)
        .task {
            guard Calendar.current.component(.hour, from: Date()) >= 5 else { return }
            await MorningBriefEngine.shared.generateIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("MORNING BRIEF")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .lineLimit(1)
            Spacer()
            Button(action: dismissForToday) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss today's brief")
        }
    }

    // MARK: - Body copy

    @ViewBuilder
    private func bodyText(_ content: BriefContent) -> some View {
        if content.source == .astra, let narrative = content.narrative, !narrative.isEmpty {
            Text(narrative)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let suggestion = content.suggestion, !suggestion.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                    Text(suggestion)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.indigo)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            // Honest engine-fallback state — the gateway call failed or is
            // still backing off. Never fake a narrative; the real stat chips
            // below still carry today's actual numbers.
            Text("Astra's written brief isn't ready yet \u{2014} here's what today looks like.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stat chips (2-3, straight from the same numbers fed to the prompt)

    private func statChips(_ stats: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(stats.prefix(3).enumerated()), id: \.offset) { _, stat in
                    Text(stat)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.indigo)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.indigo.opacity(0.14)))
                }
            }
        }
    }

    // MARK: - Ask Astra

    private var askAstraButton: some View {
        Button {
            ChatPrefillBus.shared.queue(Self.coachPrompt)
            onOpenCoach()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Ask Astra about today")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.indigo)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dismissal (per calendar day, UserDefaults-backed)

    private static let dismissDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dismissKey(for date: Date = Date()) -> String {
        "brief_dismissed_\(dismissDateFormatter.string(from: date))"
    }

    private static func isDismissedToday() -> Bool {
        UserDefaults.standard.bool(forKey: dismissKey())
    }

    private func dismissForToday() {
        UserDefaults.standard.set(true, forKey: Self.dismissKey())
        dismissedToday = true
    }
}
