import SwiftUI

// MARK: - MealIdeasView

/// Sheet-presented "ask Astra for meal ideas" surface. A free-text ask bar
/// (plus quick chips for common asks) drives `MealIdeasEngine`; results
/// render as one `.glassCard()` per `MealIdea`, each opening a full-recipe
/// detail sheet with ingredients, steps, and a one-tap "Log this meal" write
/// to HealthKit. Mirrors `NutritionDashboardView` / `TrainingPlanCard`
/// idioms: glassCard rows, the composer-bar convention from `ChatView`, and
/// `.sheet(item:)` for the detail (see `TrainingPlanCard.workoutDetailSheet`).
public struct MealIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = MealIdeasEngine.shared

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var askText: String = ""
    @State private var selectedIdea: MealIdea?
    @FocusState private var askFieldFocused: Bool

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public init() {}

    /// Label shown on the chip + the request string it sends. Requests are
    /// deliberately generic ("a healthy X idea") — the engine's own prompt
    /// grounds the specifics (targets, what's already eaten) at generate time.
    private static let quickChips: [(label: String, request: String)] = [
        ("Breakfast", "A healthy breakfast idea"),
        ("Lunch", "A healthy lunch idea"),
        ("Dinner", "A healthy dinner idea"),
        ("Snack", "A healthy snack idea"),
        ("High protein", "A healthy high-protein meal"),
        ("Quick (≤15 min)", "A healthy meal that takes 15 minutes or less to prep"),
        ("Vegetarian", "A healthy vegetarian meal idea")
    ]

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    askBar
                    quickChipsRow
                    contentByState
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(AdaptiveBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Meal Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                            .padding(8)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
        }
        .sheet(item: $selectedIdea) { idea in
            RecipeDetailSheet(idea: idea)
        }
    }

    // MARK: - Ask bar (mirrors ChatView's composer capsule)

    private var canSend: Bool {
        !askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLoading: Bool { engine.state == .loading }

    private var askBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask for any meal — \u{201C}high-protein dinner\u{201D}, \u{201C}light veg lunch\u{201D}\u{2026}",
                      text: $askText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineLimit(1...3)
                .focused($askFieldFocused)
                .tint(accentColor)
                .submitLabel(.send)
                .onSubmit(submitAsk)
                .disabled(isLoading)

            // Send button — reflects loading/empty/ready exactly like
            // ChatView's own composer send button.
            Button(action: submitAsk) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.secondary)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? accentColor : Color.secondary)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isLoading)
            .accessibilityLabel("Ask Astra")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func submitAsk() {
        let text = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        askText = ""
        askFieldFocused = false
        Task { await engine.generate(request: text) }
    }

    // MARK: - Quick chips

    private var quickChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickChips, id: \.label) { chip in
                    Button {
                        askFieldFocused = false
                        Task { await engine.generate(request: chip.request) }
                    } label: {
                        Text(chip.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Content by state

    @ViewBuilder
    private var contentByState: some View {
        switch engine.state {
        case .idle:
            if let latest = engine.latest {
                resultsSection(latest)
            } else {
                emptyState
            }
        case .loading:
            VStack(spacing: 16) {
                loadingRow
                if let latest = engine.latest {
                    resultsSection(latest)
                        .opacity(0.4)
                        .allowsHitTesting(false)
                }
            }
        case .failed(let message):
            VStack(spacing: 16) {
                failedState(message)
                if let latest = engine.latest {
                    resultsSection(latest)
                        .opacity(0.4)
                        .allowsHitTesting(false)
                }
            }
        case .ready:
            if let latest = engine.latest {
                resultsSection(latest)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty / loading / failed states

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundColor(isDark ? .white.opacity(0.2) : .black.opacity(0.2))
            Text("No meal ideas yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
            Text("Ask for anything — Astra tailors suggestions to your goals, targets and what you've already eaten today.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Asking Astra\u{2026}")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.top, engine.latest == nil ? 40 : 0)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await engine.retryLast() }
            } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(accentColor.opacity(0.4)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, engine.latest == nil ? 40 : 12)
        .padding(.horizontal, 24)
    }

    // MARK: - Results

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func resultsSection(_ set: MealIdeaSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                Text("\u{201C}\(set.request)\u{201D} \u{00B7} \(Self.relativeFormatter.localizedString(for: set.generatedAt, relativeTo: Date()))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            VStack(spacing: 12) {
                ForEach(set.ideas) { idea in
                    ideaCard(idea)
                }
            }
        }
    }

    private func ideaCard(_ idea: MealIdea) -> some View {
        Button {
            selectedIdea = idea
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(idea.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !idea.summary.isEmpty {
                    Text(idea.summary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.65) : .black.opacity(0.65))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text("~\(Int(idea.kcal.rounded())) kcal")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                    Text("\u{00B7}")
                        .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                    Text("P \(Int(idea.proteinG.rounded()))g \u{00B7} C \(Int(idea.carbsG.rounded()))g \u{00B7} F \(Int(idea.fatG.rounded()))g")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 6) {
                    if idea.prepMinutes > 0 {
                        tagChip(icon: "clock", text: "\(idea.prepMinutes) min")
                    }
                    tagChip(icon: Self.slotIcon(idea.slot), text: idea.slot.capitalized)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private func tagChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(accentColor.opacity(0.14)))
    }

    private static func slotIcon(_ slot: String) -> String {
        switch slot {
        case "breakfast": return "sunrise.fill"
        case "lunch":     return "sun.max.fill"
        case "dinner":    return "moon.fill"
        case "snack":     return "leaf.fill"
        default:          return "fork.knife"
        }
    }
}

// MARK: - RecipeDetailSheet

/// Full-recipe detail — name, summary, macro row (marked as estimates), prep
/// time, ingredients, numbered steps, and a "Log this meal" write to
/// HealthKit. Presentation mirrors `TrainingPlanCard.workoutDetailSheet`
/// (NavigationStack, medium/large detents, drag indicator).
private struct RecipeDetailSheet: View {
    let idea: MealIdea
    @Environment(\.dismiss) private var dismiss

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private enum LogState: Equatable {
        case idle
        case logging
        case success
        case failure(String)
    }
    @State private var logState: LogState = .idle

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    macroCard
                    if !idea.ingredients.isEmpty { ingredientsSection }
                    if !idea.steps.isEmpty { stepsSection }
                    logSection
                }
                .padding(20)
            }
            .background(AdaptiveBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(idea.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .fixedSize(horizontal: false, vertical: true)
            if !idea.summary.isEmpty {
                Text(idea.summary)
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if idea.prepMinutes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(idea.prepMinutes) min prep")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentColor)
            }
        }
    }

    // MARK: - Macro row (estimates)

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                macroStat(label: "kcal", value: "\(Int(idea.kcal.rounded()))", color: .orange)
                macroStat(label: "protein", value: "\(Int(idea.proteinG.rounded()))g", color: Color(red: 0.36, green: 0.61, blue: 1.0))
                macroStat(label: "carbs", value: "\(Int(idea.carbsG.rounded()))g", color: Color(.systemGreen))
                macroStat(label: "fat", value: "\(Int(idea.fatG.rounded()))g", color: Color(.systemYellow))
            }
            Text("Estimates \u{2014} confidence: \(idea.confidence)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func macroStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ingredients / Steps

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(idea.ingredients, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(accentColor.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(idea.steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                        Text(step)
                            .font(.system(size: 14))
                            .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Log this meal (real HealthKit write, honest per-outcome feedback)

    @ViewBuilder
    private var logSection: some View {
        if logState == .success {
            Label("Logged to Apple Health \u{2713}", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 8) {
                Button(action: logMeal) {
                    HStack(spacing: 8) {
                        if logState == .logging {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Log this meal")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .glassEffect(.regular.tint(accentColor.opacity(0.4)).interactive(), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(logState == .logging)

                if case .failure(let reason) = logState {
                    Text(reason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func logMeal() {
        logState = .logging
        Task {
            let outcome = await HealthKitManager.shared.logFoodDetailed(
                name: idea.name,
                calories: idea.kcal,
                protein: idea.proteinG,
                carbs: idea.carbsG,
                fat: idea.fatG,
                date: Date(),
                isEstimate: true,
                confidence: idea.confidence
            )
            if outcome.succeeded {
                await HealthKitManager.shared.refreshDietaryNow()
                logState = .success
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } else {
                logState = .failure(outcome.failureReason ?? "Couldn't log this meal \u{2014} try again.")
            }
        }
    }
}
