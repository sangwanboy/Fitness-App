import SwiftUI

/// Bottom sheet that streams Gemini's per-prediction "Why?" explanation for
/// a single prediction kind. Loading state + error retry + graceful cancel.
public struct PredictionWhySheet: View {
    public let kind: PredictionKind
    public let predictions: Predictions

    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var text: String = ""
    @State private var isLoading: Bool = true
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String? = nil
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var tokenUsage: TokenUsage? = nil

    private var title: String {
        switch kind {
        case .recovery:     return "Why your recovery is \(predictions.recovery?.label.headline ?? "—")"
        case .nextWorkout:  return "Why this workout time"
        case .trajectory:   return "Why this pace projection"
        case .sedentary:    return "Why this move reminder"
        case .healthMeter:  return "Why your health is \(predictions.healthMeter?.label.headline.lowercased() ?? "—")"
        }
    }

    private var subtitle: String {
        switch kind {
        case .recovery:    return "Personalized read on today's recovery"
        case .nextWorkout: return "What your 4-week pattern looks like"
        case .trajectory:  return "Today vs your 14-day baseline"
        case .sedentary:   return "Quiet stretches vs your usual day"
        case .healthMeter: return "What's driving your wellness score"
        }
    }

    public init(kind: PredictionKind, predictions: Predictions) {
        self.kind = kind
        self.predictions = predictions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Group {
                    if isLoading && text.isEmpty {
                        loadingView
                    } else if let err = errorMessage, text.isEmpty {
                        errorView(message: err)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            StructuredMarkdownText(text: text, isDark: isDark, accentColor: .indigo)
                                .lineSpacing(4)
                            if isStreaming {
                                StreamingDots()
                            }
                            if let usage = tokenUsage {
                                TokenUsageChip(usage: usage, isDark: isDark)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))

                // Always-available handoff into Coach — user can ask follow-ups
                // with full prediction context already in the system prompt.
                continueInCoachButton

                // Contextual quick actions — what to actually DO with this insight.
                // These are deterministic per PredictionKind so they're always
                // present, even before the AI text finishes streaming.
                let quickActions = quickActionsForKind()
                if !quickActions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DO THIS NOW")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        VStack(spacing: 8) {
                            ForEach(quickActions) { action in
                                Button(action: { fire(action) }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: action.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(action.color)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(action.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(isDark ? .white : .black)
                                            Text(action.subtitle)
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.indigo)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AdaptiveBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { startStream() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - Quick actions

    private struct QuickAction: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let prompt: String
    }

    private func quickActionsForKind() -> [QuickAction] {
        switch kind {
        case .trajectory:
            // Only surface fix actions when the user is meaningfully behind.
            guard let steps = predictions.trajectories.first(where: { $0.metric == .steps }) else { return [] }
            switch steps.status {
            case .behind, .farBehind:
                let deficit = Int(max(0, steps.baselineEOD - steps.projectedEOD).rounded())
                return [
                    QuickAction(
                        icon: "figure.walk",
                        color: .blue,
                        title: "Add a 20-min walk now",
                        subtitle: "Closes about \(deficit) steps of the gap",
                        prompt: "Add a 20-minute walk to my calendar starting in 30 minutes so I can catch up on today's step goal."
                    ),
                    QuickAction(
                        icon: "bell.fill",
                        color: .orange,
                        title: "Remind me hourly to move",
                        subtitle: "Until 7 PM",
                        prompt: "Set hourly reminders from now until 7 PM to take a quick 5-minute walk."
                    )
                ]
            case .aheadOfPace, .onPace:
                return []
            }
        case .sedentary:
            guard let s = predictions.sedentary else { return [] }
            return [
                QuickAction(
                    icon: "figure.walk.motion",
                    color: .orange,
                    title: "5-minute walk reminder",
                    subtitle: "Right now — break the \(s.quietHours)h quiet stretch",
                    prompt: "Add a reminder for me to take a 5-minute walk right now."
                ),
                QuickAction(
                    icon: "drop.fill",
                    color: .cyan,
                    title: "Log a glass of water",
                    subtitle: "While you're up, hydrate too",
                    prompt: "Log 250 ml of water for hydration."
                )
            ]
        case .recovery:
            guard let r = predictions.recovery else { return [] }
            switch r.label {
            case .strong:
                return [
                    QuickAction(
                        icon: "figure.run",
                        color: .green,
                        title: "Plan a hard session today",
                        subtitle: "Your recovery is in the green zone",
                        prompt: "Plan a hard interval workout for me today — my recovery is strong."
                    )
                ]
            case .moderate:
                return [
                    QuickAction(
                        icon: "figure.strengthtraining.traditional",
                        color: .blue,
                        title: "Plan a steady workout",
                        subtitle: "Push moderate, save intensity for tomorrow",
                        prompt: "Plan a steady-state workout for me today — recovery is moderate so nothing too hard."
                    )
                ]
            case .low, .rest:
                return [
                    QuickAction(
                        icon: "leaf.fill",
                        color: .purple,
                        title: "Plan a recovery day",
                        subtitle: "Mobility + walk only",
                        prompt: "Plan a recovery-focused day for me with mobility work and a light walk only."
                    ),
                    QuickAction(
                        icon: "bed.double.fill",
                        color: .indigo,
                        title: "Earlier bedtime reminder",
                        subtitle: "10:30 PM tonight",
                        prompt: "Add a reminder for me to start winding down at 10:30 PM tonight so I can get to bed earlier."
                    )
                ]
            }
        case .nextWorkout:
            guard let n = predictions.nextWorkout else { return [] }
            let f = DateFormatter(); f.dateFormat = "h a"
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let start = cal.date(byAdding: .hour, value: n.startHour, to: today) ?? today
            let timeStr = f.string(from: start)
            return [
                QuickAction(
                    icon: "calendar.badge.plus",
                    color: .indigo,
                    title: "Add this to my calendar",
                    subtitle: "\(n.category.displayName) at \(timeStr) \(n.weekdayLabel)",
                    prompt: "Add a \(n.category.displayName.lowercased()) workout to my calendar for \(n.weekdayLabel) at \(timeStr) for 45 minutes."
                )
            ]
        case .healthMeter:
            guard let m = predictions.healthMeter else { return [] }
            // Surface 1-2 actions targeted at the WEAKEST sub-score.
            let subscores: [(String, Int, Int, [QuickAction])] = [
                ("Activity", m.activityScore, 30, [
                    QuickAction(icon: "figure.run", color: .orange,
                                title: "Plan today's workout",
                                subtitle: "Activity is your lowest sub-score",
                                prompt: "Plan a workout for me today that fits my current recovery and goals.")
                ]),
                ("Nutrition", m.nutritionScore, 30, [
                    QuickAction(icon: "fork.knife", color: .green,
                                title: "Log my last meal",
                                subtitle: "Logging meals raises this score",
                                prompt: "I want to log my most recent meal — help me capture it."),
                    QuickAction(icon: "drop.fill", color: .cyan,
                                title: "Log a glass of water",
                                subtitle: "Quick hydration win",
                                prompt: "Log 250 ml of water for hydration.")
                ]),
                ("Body", m.bodyScore, 18, [
                    QuickAction(icon: "person.crop.circle", color: .purple,
                                title: m.usedBMI ? "Plan body comp changes" : "Add height + weight",
                                subtitle: m.usedBMI ? "Within range matters most" : "Profile → Personal details",
                                prompt: m.usedBMI
                                    ? "Help me plan a 4-week routine to improve my body composition."
                                    : "How do I add my height and weight to the app?")
                ]),
                ("Vitals", m.vitalsScore, 22, [
                    QuickAction(icon: "bed.double.fill", color: .indigo,
                                title: "Set bedtime reminder",
                                subtitle: "Sleep is the biggest vitals lever",
                                prompt: "Add a reminder for me to start winding down at 10:30 PM tonight.")
                ])
            ]
            // Pick the weakest non-perfect sub-score; surface its actions.
            let weakest = subscores
                .filter { Double($0.1) / Double($0.2) < 0.9 }
                .min(by: { Double($0.1) / Double($0.2) < Double($1.1) / Double($1.2) })
            return weakest?.3 ?? []
        }
    }

    private func fire(_ action: QuickAction) {
        ChatPrefillBus.shared.queue(action.prompt)
        dismiss()
    }

    // MARK: - Continue in Coach

    /// Per-kind seed text that pre-fills the Coach composer. User can send
    /// as-is or edit before sending. Astra has full prediction context via
    /// the system prompt + the get_predictions tool so follow-ups work
    /// regardless of what the user types.
    private var composerSeedForKind: String {
        switch kind {
        case .healthMeter:
            let scoreFragment = predictions.healthMeter.map { "(\($0.score)/100, \($0.label.headline))" } ?? ""
            return "Let's go deeper on my Health Meter \(scoreFragment). Walk me through what I should change first to bump it up, and ask me anything you need to know."
        case .recovery:
            let scoreFragment = predictions.recovery.map { "\($0.score)/100, \($0.label.headline)" } ?? ""
            return "Talk to me about my recovery today (\(scoreFragment)). I want a clear plan for whether to train hard, easy, or rest — feel free to ask follow-ups."
        case .nextWorkout:
            let cat = predictions.nextWorkout?.category.displayName.lowercased() ?? "workout"
            return "Let's plan today's \(cat). Suggest the exact time, duration, and intensity that fits my recovery and goals."
        case .trajectory:
            return "Let's talk about my pace today. What's the most realistic way to close the gap before the day's over, and what would you do in my shoes?"
        case .sedentary:
            return "I've been sitting too long. Help me plan the rest of the day so I break it up properly — feel free to ask about my schedule."
        }
    }

    private var continueInCoachButton: some View {
        Button(action: handoffToCoach) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Continue in Coach")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                    Text("Open a chat with Astra about this — edit and send.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func handoffToCoach() {
        ChatPrefillBus.shared.queueComposerSeed(composerSeedForKind)
        dismiss()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("INSIGHT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.indigo)
                .controlSize(.small)
            Text("Astra is thinking…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't fetch this insight")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                .lineSpacing(2)
            Button(action: { startStream() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try again")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.top, 4)
        }
    }

    private func startStream() {
        // Cancel any in-flight before starting again.
        streamTask?.cancel()
        text = ""
        tokenUsage = nil
        errorMessage = nil
        isLoading = true
        isStreaming = true

        let userContext = HealthKitManager.shared.aiUserContextForWhySheet()
        let stream = PredictionAIService.shared.explainPrediction(
            kind,
            predictions: predictions,
            userContext: userContext
        )
        streamTask = Task {
            do {
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .text(let delta):
                        await MainActor.run {
                            text += delta
                            isLoading = false
                        }
                    case .usage(let usage):
                        await MainActor.run {
                            tokenUsage = usage
                        }
                    }
                }
                await MainActor.run {
                    isLoading = false
                    isStreaming = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoading = false
                    isStreaming = false
                    errorMessage = (error as? PredictionAIService.AIError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Streaming indicator (three pulsing dots)

private struct StreamingDots: View {
    @State private var phase: Int = 0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.indigo)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        phase = (phase + 1) % 3
                    }
                }
            }
        }
    }
}
