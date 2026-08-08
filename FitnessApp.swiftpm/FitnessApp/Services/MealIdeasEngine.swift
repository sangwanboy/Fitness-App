import Foundation

// MARK: - Models

/// One AI-suggested meal — a full recipe, not just a name. Nutrition numbers
/// are always estimates (never claimed exact); `confidence` is Astra's own
/// read on how solid the estimate is, same vocabulary as the food-photo flow.
public struct MealIdea: Identifiable, Codable, Hashable {
    public let id: UUID          // generated at parse time — never round-tripped from the model
    public let name: String
    public let summary: String   // one sentence
    public let kcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let prepMinutes: Int
    public let slot: String      // breakfast | lunch | dinner | snack | any
    public let tags: [String]
    public let ingredients: [String]
    public let steps: [String]
    public let confidence: String // low | medium | high
}

/// One "ask" and the set of ideas Astra returned for it. Only the single
/// most recent set is cached — this is a scratch surface, not a history.
public struct MealIdeaSet: Codable {
    public let request: String    // what the user asked, verbatim
    public let generatedAt: Date
    public let ideas: [MealIdea]
}

private enum MealIdeasError: Error {
    case parseError
    case noValidIdeas
}

// MARK: - Engine

/// One-shot AI meal-idea + recipe generator — asks Astra for a handful of
/// meal suggestions (with full ingredients/steps) grounded in the SAME real
/// numbers the rest of the app already surfaces: today's eaten macros
/// (`HealthKitManager` / `NutritionService`), any Astra-set targets
/// (`NutritionTargets`), and today's food log (so it doesn't suggest a
/// near-duplicate of something already eaten). Mirrors `MorningBriefEngine`'s
/// conventions: gateway transport via `GatewayTransport.postJSON`, thought-safe
/// extraction via `GatewayChatPayload`, TokenMeter accounting under
/// `.insights` (same precedent as morning brief — no dedicated `TokenSource`
/// case added for this feature).
///
/// Unlike `MorningBriefEngine` this isn't a once-per-day cache — it's a
/// user-driven "ask anything" surface, so there's no calendar-day dedupe:
/// every `generate(request:)` call is a fresh gateway round-trip, gated only
/// by the in-flight guard (no double-submits) and a non-empty request.
@MainActor
public final class MealIdeasEngine: ObservableObject {
    public static let shared = MealIdeasEngine()

    public enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var latest: MealIdeaSet?

    /// The most recent ask — kept so the failed-state "Try again" button can
    /// re-run the identical request without the caller re-supplying it.
    private var lastRequest: String?

    private init() {
        if let cached = loadFromDisk() {
            latest = cached
            state = .ready
        }
    }

    // MARK: - Public API

    /// Asks Astra for meal ideas matching `request`. Safe to call repeatedly —
    /// the in-flight guard makes a double-tap on the submit button (or a
    /// second chip tap while the first is still loading) a cheap no-op,
    /// mirroring `MorningBriefEngine.generateIfNeeded`'s own double-generation
    /// fix.
    public func generate(request: String) async {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard state != .loading else { return }

        lastRequest = trimmed
        state = .loading
        do {
            let set = try await Self.generateIdeas(request: trimmed)
            latest = set
            state = .ready
            persistToDisk(set)
        } catch {
            state = .failed(Self.errorMessage(for: error))
        }
    }

    /// Re-runs the last ask — backs the failed-state "Try again" affordance.
    public func retryLast() async {
        guard let lastRequest else { return }
        await generate(request: lastRequest)
    }

    // MARK: - Prompt construction

    /// Assembles every section from data that actually exists — never
    /// fabricates a number or profile fact. Sections with nothing real to
    /// say (no profile, no logged food yet, no targets set) are simply
    /// omitted rather than padded out.
    static func buildPrompt(request: String) -> String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let todayLine = "TODAY IS \(ChatViewModel.todayLine()), current time \(timeFmt.string(from: Date()))."

        // Astra's learned profile — same toggle + compact render the chat
        // surface and MorningBriefEngine use.
        let profileBlock: String = {
            guard AstraMemoryStore.shared.isEnabled else { return "" }
            let rendered = AstraMemoryStore.shared.renderForSystemPrompt()
            guard !rendered.isEmpty else { return "" }
            return "\nWHAT YOU KNOW ABOUT THE USER (respect dietary preferences, allergies, injuries, goals):\n\(rendered)\n"
        }()

        let numberLines = realNumbersLines()
        let numbersBlock = numberLines.isEmpty
            ? ""
            : "\nTODAY'S REAL NUMBERS (ground truth — use ONLY these, never invent numbers not listed):\n\(numberLines.map { "- \($0)" }.joined(separator: "\n"))\n"

        return """
        You are Astra, the user's fitness coach inside the Astra app. Suggest meals with full recipes.

        \(todayLine)
        \(profileBlock)\(numbersBlock)
        USER REQUEST: \(request)

        RULES:
        - Healthy by default: whole foods, vegetables, lean protein, realistic portions and prep.
        - Fit suggestions to remaining macros when targets are listed above.
        - Respect every dietary preference/allergy/injury in the user's profile above.
        - If the user explicitly asks for something indulgent, give them what they asked for (optionally one lighter variation) — never lecture or moralize.
        - Keep summaries to one sentence.
        - Ingredients with rough quantities; steps short and in numbered order.
        - All nutrition numbers are estimates.

        OUTPUT: Return ONLY valid JSON, no prose:
        {"ideas":[{"name":"...","summary":"...","kcal":0,"protein_g":0,"carbs_g":0,"fat_g":0,"prep_minutes":0,"slot":"breakfast|lunch|dinner|snack|any","tags":["..."],"ingredients":["..."],"steps":["..."],"confidence":"low|medium|high"}]}
        Return 3 ideas (2 is acceptable if the request is very specific, 4 max).
        """
    }

    /// Ground-truth bullet lines — eaten-so-far macros, Astra-set targets
    /// (+ remaining-vs-target when a target exists), and today's already
    /// logged meal names (so Astra avoids suggesting a near-duplicate).
    private static func realNumbersLines() -> [String] {
        let hk = HealthKitManager.shared
        let nut = NutritionService.shared
        let targets = NutritionTargets.shared
        var lines: [String] = []

        let eatenKcal = hk.dietaryCaloriesToday
        let eatenProtein = hk.dietaryProteinToday
        let eatenCarbs = nut.carbsToday
        let eatenFat = nut.fatToday

        if eatenKcal > 0 { lines.append("Eaten so far today: \(Int(eatenKcal.rounded())) kcal") }
        if eatenProtein > 0 { lines.append("Protein eaten so far: \(Int(eatenProtein.rounded()))g") }
        if eatenCarbs > 0 { lines.append("Carbs eaten so far: \(Int(eatenCarbs.rounded()))g") }
        if eatenFat > 0 { lines.append("Fat eaten so far: \(Int(eatenFat.rounded()))g") }

        if let kcalTarget = targets.kcalTarget {
            lines.append("Kcal target (Astra-set): \(Int(kcalTarget.rounded()))")
            let remaining = kcalTarget - eatenKcal
            if remaining > 0 {
                lines.append("~\(Int(remaining.rounded())) kcal remaining today")
            }
        }
        if let proteinTarget = targets.proteinTargetG {
            lines.append("Protein target (Astra-set): \(Int(proteinTarget.rounded()))g")
            let remaining = proteinTarget - eatenProtein
            if remaining > 0 {
                lines.append("~\(Int(remaining.rounded()))g protein remaining today")
            }
        }

        let loggedNames = hk.todayFoodLog.map(\.name)
        if !loggedNames.isEmpty {
            lines.append("Already eaten today: \(loggedNames.joined(separator: ", ")) — avoid suggesting near-duplicates of these")
        }

        return lines
    }

    // MARK: - Gateway call (MorningBriefEngine.generateNarrative pattern)

    private static func generateIdeas(request: String) async throws -> MealIdeaSet {
        let prompt = buildPrompt(request: request)
        // Fixed budget + headroom — decoupled from the chat Thinking Level
        // picker; see MorningBriefEngine.generateNarrative for the rationale
        // (budget 0 starved the JSON answer).
        let thinkingBudget = 512
        let maxTokens = 2400       // recipes are long: 3–4 full recipes with steps can exceed 2k tokens
        let generationConfig: [String: Any] = [
            "maxOutputTokens": maxTokens + thinkingBudget + 1024,
            "temperature": 0.7,
            "thinkingConfig": ["thinkingBudget": thinkingBudget],
            "responseMimeType": "application/json"
        ]
        let body = GatewayChatPayload.body(
            stream: false,
            system: "",
            messages: [GatewayChatPayload.message(role: "user", parts: [GatewayChatPayload.textPart(prompt)])],
            generationConfig: generationConfig
        )

        // 90s: the gateway absorbs upstream Vertex 429s by retrying them,
        // which pushes worst-case latency past 30s — same reasoning as
        // MorningBriefEngine's own call.
        let raw = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: 90)

        // Thought-part-safe extraction — see GatewayChatPayload.responseText.
        guard let (text, usageMeta) = GatewayChatPayload.responseText(fromBody: raw) else {
            throw MealIdeasError.parseError
        }
        if let usageMeta, let usage = TokenUsage(usageMetadata: usageMeta) {
            TokenMeter.shared.record(usage, source: .insights)
        }

        guard let jsonData = GatewayChatPayload.strippedJSONText(text).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let ideaDicts = parsed["ideas"] as? [[String: Any]] else {
            throw MealIdeasError.parseError
        }

        // Defensive per-idea parsing: malformed entries are skipped rather
        // than failing the whole batch; the result is capped at 4 valid ideas.
        let ideas = Array(ideaDicts.compactMap(parseIdea).prefix(4))
        guard !ideas.isEmpty else { throw MealIdeasError.noValidIdeas }

        return MealIdeaSet(request: request, generatedAt: Date(), ideas: ideas)
    }

    /// Requires a non-empty name and kcal > 0; everything else defaults to a
    /// safe zero/empty/"any"/"medium" rather than dropping the whole idea.
    private static func parseIdea(_ dict: [String: Any]) -> MealIdea? {
        guard let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        let kcal = numericValue(dict["kcal"])
        guard kcal > 0 else { return nil }

        let summary = (dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let proteinG = numericValue(dict["protein_g"])
        let carbsG = numericValue(dict["carbs_g"])
        let fatG = numericValue(dict["fat_g"])
        let prepMinutes = Int(numericValue(dict["prep_minutes"]))

        let validSlots: Set<String> = ["breakfast", "lunch", "dinner", "snack", "any"]
        let slotRaw = (dict["slot"] as? String)?.lowercased() ?? "any"
        let slot = validSlots.contains(slotRaw) ? slotRaw : "any"

        let tags = Array(((dict["tags"] as? [String]) ?? []).prefix(3))
        let ingredients = (dict["ingredients"] as? [String]) ?? []
        let steps = (dict["steps"] as? [String]) ?? []

        let validConfidence: Set<String> = ["low", "medium", "high"]
        let confidenceRaw = (dict["confidence"] as? String)?.lowercased() ?? "medium"
        let confidence = validConfidence.contains(confidenceRaw) ? confidenceRaw : "medium"

        return MealIdea(
            id: UUID(),
            name: name,
            summary: summary,
            kcal: kcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            prepMinutes: prepMinutes,
            slot: slot,
            tags: tags,
            ingredients: ingredients,
            steps: steps,
            confidence: confidence
        )
    }

    /// Gemini sometimes emits a numeric field as a JSON number OR a numeric
    /// string — tolerate both rather than dropping the whole idea over it.
    private static func numericValue(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String, let d = Double(s) { return d }
        return 0
    }

    /// Short, honest failure text. Gateway errors already carry a
    /// user-presentable message (`GatewayError.userMessage`); a timed-out
    /// request (bare `URLError` or one wrapped inside `.network`) gets its
    /// own wording since "took too long" is more actionable than the
    /// generic connectivity message.
    private static func errorMessage(for error: Error) -> String {
        if let gatewayError = error as? GatewayError {
            if case .network(let underlying) = gatewayError, (underlying as? URLError)?.code == .timedOut {
                return "The AI gateway took too long — try again."
            }
            return gatewayError.userMessage
        }
        if (error as? URLError)?.code == .timedOut {
            return "The AI gateway took too long — try again."
        }
        if error is MealIdeasError {
            return "Astra couldn't produce meal ideas for that ask — try rephrasing."
        }
        return "Astra couldn't produce meal ideas for that ask — try rephrasing."
    }

    // MARK: - Disk cache (Application Support — single "latest ask" file)

    private static let cacheDirName = "MealIdeas"

    private func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(Self.cacheDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheFileURL() -> URL? {
        cacheDirectory()?.appendingPathComponent("latest.json")
    }

    private func loadFromDisk() -> MealIdeaSet? {
        guard let url = cacheFileURL(), let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MealIdeaSet.self, from: raw)
    }

    private func persistToDisk(_ set: MealIdeaSet) {
        guard let url = cacheFileURL() else { return }
        guard let out = try? JSONEncoder().encode(set) else { return }
        try? out.write(to: url, options: .atomic)
    }
}
