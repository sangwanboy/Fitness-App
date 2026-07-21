import Foundation

// MARK: - Models

/// One calendar day's morning brief — either Astra-written (`.astra`) or the
/// honest fallback (`.engine`) used when the gateway call failed, is still
/// backing off, or hasn't been attempted yet today. `stats` are the SAME real
/// numbers fed to the prompt as ground truth, so they double as the card's
/// stat chips — one source of truth for "what did we actually tell Astra."
public struct BriefContent: Codable, Equatable {
    public enum Source: String, Codable {
        case astra   // Gateway call succeeded — narrative/suggestion are Astra's own words.
        case engine  // Gateway call failed/backing off — no invented copy.
    }

    /// Start-of-day (local calendar) this brief is for — the cache/dedupe key.
    public let date: Date
    public var narrative: String?
    public var suggestion: String?
    /// Short chip-style facts built ONLY from real on-device numbers, e.g.
    /// "Recovery 56/100 · Steady", "Slept 9.9h", "4-week streak".
    public let stats: [String]
    public let generatedAt: Date
    public var source: Source

    public init(date: Date, narrative: String?, suggestion: String?, stats: [String],
                generatedAt: Date = Date(), source: Source) {
        self.date = date
        self.narrative = narrative
        self.suggestion = suggestion
        self.stats = stats
        self.generatedAt = generatedAt
        self.source = source
    }
}

private enum MorningBriefError: Error {
    case parseError
}

// MARK: - Engine

/// AI-side companion to the v1 engine-composed morning brief
/// (`NotificationManager.buildMorningBriefBody`). Gathers the SAME real
/// inputs that one-liner uses (recovery, sleep, training load, streak) plus
/// any nutrition target the user/Astra has set, asks Astra for a short
/// written brief grounded ONLY in those numbers, and caches the result once
/// per calendar day in Application Support.
///
/// On any failure (network, parse, rate limit) the cached entry falls back
/// to `.engine` source and `NotificationManager` keeps sending its unchanged
/// v1 one-liner — a live user never sees a blank or broken morning brief.
///
/// Mirrors `WeeklyReviewEngine`'s conventions: gateway transport via
/// `GatewayTransport.postJSON` (the same shape `PredictionAIService
/// .callGeminiJSON` uses), TokenMeter accounting under `.insights` (morning
/// brief is an insights-class feature — no dedicated `TokenSource` case
/// added, per `WeeklyReviewEngine`'s own precedent, since `TokenMeter.swift`
/// is outside this task's file ownership), and a single quiet auto-retry on
/// `rate_limited` / `quota_exceeded` before falling back to the normal
/// 5-minute backoff.
@MainActor
public final class MorningBriefEngine: ObservableObject {
    public static let shared = MorningBriefEngine()

    public enum State: Equatable {
        case idle        // no attempt yet today (no real data to ground a brief in)
        case loading
        case ready       // .astra narrative ready
        case unavailable // attempted, gateway failed — .engine fallback is what's cached
    }

    @Published public private(set) var content: BriefContent?
    @Published public private(set) var state: State = .idle

    private var lastFailureAt: Date?
    private let failureBackoff: TimeInterval = 300
    private var autoRetryScheduled = false

    /// Today's cached brief, or nil before the first attempt this calendar
    /// day has landed (whether that attempt succeeded or fell back).
    public var todaysContent: BriefContent? {
        guard let content, Calendar.current.isDateInToday(content.date) else { return nil }
        return content
    }

    private init() {
        let today = Calendar.current.startOfDay(for: Date())
        if let cached = loadFromDisk(day: today) {
            content = cached
            state = cached.source == .astra ? .ready : .unavailable
        }

        // Self-heal: a brief that failed while signed out (401) shouldn't sit
        // behind its backoff waiting for the next natural trigger once the
        // user signs in — mirrors WeeklyReviewEngine's own self-heal.
        NotificationCenter.default.addObserver(
            forName: .gatewaySessionEstablished, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let content = self.content,
                      content.source == .engine,
                      Calendar.current.isDateInToday(content.date) else { return }
                await self.attemptGenerate(day: content.date)
            }
        }
    }

    // MARK: - Public API

    /// Attempts today's brief if nothing has been computed for today yet.
    /// Safe to call unconditionally from the BG refresh handler — the
    /// once-per-calendar-day dedupe (plus the "don't bother the gateway with
    /// no real signal" guard inside `attemptGenerate`) makes repeat calls
    /// cheap no-ops. This method has NO internal time-of-day gate; callers
    /// that want the spec's "first foreground after 5am" behavior apply that
    /// gate themselves before calling (see `NotificationManager
    /// .appDidBecomeActive`).
    public func generateIfNeeded() async {
        // Synchronous in-flight guard (MainActor): three triggers can call
        // this in quick succession on the day's first launch (BG refresh,
        // foreground≥5am, the card's .task) — without it, the second caller
        // enters while the first is suspended in the gateway await and the
        // metered LLM call runs twice.
        guard state != .loading else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let content, Calendar.current.isDate(content.date, inSameDayAs: today) { return }
        if let cached = loadFromDisk(day: today) {
            content = cached
            state = cached.source == .astra ? .ready : .unavailable
            return
        }
        await attemptGenerate(day: today)
    }

    // MARK: - Generation

    private func attemptGenerate(day: Date) async {
        let stats = Self.gatherStats()
        // No real signal at all yet (e.g. called moments after launch,
        // before HealthKit has returned anything) — don't spend a gateway
        // call on nothing, and don't cache a hollow entry either, so a LATER
        // call this same day (once data lands) gets a real attempt instead
        // of being dedupe-blocked by an empty cache entry.
        guard !stats.isEmpty else { return }

        if let failedAt = lastFailureAt, Date().timeIntervalSince(failedAt) < failureBackoff {
            persistEngineFallback(day: day, stats: stats)
            return
        }

        state = .loading
        do {
            let (narrative, suggestion) = try await Self.generateNarrative(stats: stats)
            let result = BriefContent(date: day, narrative: narrative, suggestion: suggestion,
                                      stats: stats, source: .astra)
            content = result
            state = .ready
            lastFailureAt = nil
            autoRetryScheduled = false
            persistToDisk(result)
        } catch {
            lastFailureAt = Date()
            persistEngineFallback(day: day, stats: stats)
            // Upstream rate-limits are transient (seen live by WeeklyReviewEngine
            // on the shared Vertex project) — one quiet automatic retry instead
            // of stranding the fallback behind the 5-min backoff for the rest
            // of the day.
            switch error as? GatewayError {
            case .rateLimited(let ms), .quotaExceeded(let ms):
                scheduleAutoRetry(afterMs: ms, day: day)
            default:
                break
            }
        }
    }

    private func persistEngineFallback(day: Date, stats: [String]) {
        let result = BriefContent(date: day, narrative: nil, suggestion: nil, stats: stats, source: .engine)
        content = result
        state = .unavailable
        persistToDisk(result)
    }

    /// One automatic retry per failure episode; the flag only resets on
    /// success (or a new day), so repeated 429s fall back to the normal
    /// backoff rather than hammering the gateway. Mirrors
    /// `WeeklyReviewEngine.scheduleNarrativeAutoRetry`.
    private func scheduleAutoRetry(afterMs: Int?, day: Date) {
        guard !autoRetryScheduled else { return }
        autoRetryScheduled = true
        let delay = max(Double(afterMs ?? 30_000) / 1000.0, 30)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let current = self.content, current.source == .engine,
                  Calendar.current.isDate(current.date, inSameDayAs: day) else { return }
            await self.attemptGenerate(day: day)
        }
    }

    // MARK: - Real inputs (same sources as NotificationManager.buildMorningBriefBody)

    /// Short chip-style facts built ONLY from real on-device numbers — never
    /// invented. Empty when nothing meaningful has landed yet (mirrors
    /// `buildMorningBriefBody`'s own "nothing to say yet" guard).
    private static func gatherStats() -> [String] {
        let hk = HealthKitManager.shared
        var stats: [String] = []

        if let recovery = hk.predictions?.recovery {
            stats.append("Recovery \(recovery.score)/100 \u{00B7} \(recovery.label.headline)")
        }
        if let sleepHours = hk.metricSummaries[.sleep]?.currentValue, sleepHours > 0 {
            stats.append("Slept \(String(format: "%.1f", sleepHours))h")
        }
        let load = TrainingLoadEngine.shared
        if load.chronicLoad > 0 {
            stats.append("Training load \(load.acwrZone.label)")
        }
        // Refresh first so this reflects the latest HealthKit state even if
        // DashboardView hasn't run this session — same reasoning as
        // NotificationManager.buildMorningBriefBody's own streak read.
        StreakEngine.shared.refresh()
        let streak = StreakEngine.shared.currentStreak
        if streak > 0 {
            stats.append("\(streak)-week streak")
        }
        if let kcalTarget = NutritionTargets.shared.kcalTarget {
            stats.append("Kcal target \(Int(kcalTarget.rounded()))")
        }
        if let proteinTarget = NutritionTargets.shared.proteinTargetG {
            stats.append("Protein target \(Int(proteinTarget.rounded()))g")
        }

        // Today's planned training session (flows into both the gateway
        // prompt and the card's stat chips via `stats`). Rest days are real
        // information for a morning brief too — say so.
        if let plan = TrainingPlanStore.shared.activePlan,
           let today = plan.days.first(where: { Calendar.current.isDateInToday($0.date) }) {
            stats.append(today.kind == .rest
                         ? "Planned: rest day"
                         : "Planned: \(today.title) (\(today.durationMin) min)")
        }

        return stats
    }

    // MARK: - Gateway call (PredictionAIService.callGeminiJSON pattern)

    private static func buildPrompt(stats: [String]) -> String {
        // Astra's learned profile makes the suggestion personal (goal-aware,
        // injury-aware) — same toggle + compact render the chat surface uses.
        let profileBlock: String = {
            guard AstraMemoryStore.shared.isEnabled else { return "" }
            let rendered = AstraMemoryStore.shared.renderForSystemPrompt()
            guard !rendered.isEmpty else { return "" }
            return "\nWHAT YOU KNOW ABOUT THE USER (respect injuries/preferences; align the suggestion with their goals):\n\(rendered)\n"
        }()
        return """
        You are Astra, the user's AI fitness coach inside Fitness Guru. Write their morning brief.

        TODAY'S REAL NUMBERS (ground truth — use ONLY these, never invent or estimate a number that isn't here):
        \(stats.map { "- \($0)" }.joined(separator: "\n"))
        \(profileBlock)

        TASK: Write a short, honest morning brief in your own voice, addressing the user directly ("you"/"your").
        - "narrative": 2-3 sentences. Weave the numbers above in naturally — don't just list them back. If a metric isn't listed above, don't mention it at all.
        - "suggestion": ONE concrete, specific action for today, grounded in the numbers above (not vague like "keep it up").

        Output STRICT JSON (no markdown fences, no preamble):
        {"narrative": "...", "suggestion": "..."}
        """
    }

    /// One-shot /v1/chat call through the gateway — same shape as
    /// `PredictionAIService.callGeminiJSON` / `WeeklyReviewEngine
    /// .generateNarrative`: gateway transport, strict-JSON response,
    /// TokenMeter accounting.
    private static func generateNarrative(stats: [String]) async throws -> (narrative: String, suggestion: String) {
        let prompt = buildPrompt(stats: stats)
        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        let maxTokens = 250
        let generationConfig: [String: Any] = [
            "maxOutputTokens": maxTokens + thinkingBudget,
            "temperature": 0.6,
            "thinkingConfig": ["thinkingBudget": thinkingBudget],
            "responseMimeType": "application/json"
        ]
        let body = GatewayChatPayload.body(
            stream: false,
            system: "",
            messages: [GatewayChatPayload.message(role: "user", parts: [GatewayChatPayload.textPart(prompt)])],
            generationConfig: generationConfig
        )

        // 90s: the gateway ABSORBS upstream Vertex 429s by retrying them
        // (dashboard: "11 all absorbed"), which pushes worst-case latency
        // past 30s. This is a background call — patience beats a dead
        // socket the gateway then completes for nobody. Dead-gateway
        // fast-fail is already handled by ensureReachable's 2s probe.
        let raw = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: 90)

        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw MorningBriefError.parseError
        }
        if let usageMeta = obj["usageMetadata"] as? [String: Any],
           let usage = TokenUsage(usageMetadata: usageMeta) {
            TokenMeter.shared.record(usage, source: .insights)
        }

        guard let jsonData = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let narrative = (parsed["narrative"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let suggestion = (parsed["suggestion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !narrative.isEmpty, !suggestion.isEmpty else {
            throw MorningBriefError.parseError
        }
        return (narrative, suggestion)
    }

    // MARK: - Disk cache (Application Support, one JSON file per calendar day)

    private static let cacheDirName = "MorningBrief"
    private static let maxCachedDays = 14

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()

    private func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(Self.cacheDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheFileURL(day: Date) -> URL? {
        cacheDirectory()?.appendingPathComponent("day-\(Self.dayKeyFormatter.string(from: day)).json")
    }

    private func loadFromDisk(day: Date) -> BriefContent? {
        guard let url = cacheFileURL(day: day),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BriefContent.self, from: raw)
    }

    private func persistToDisk(_ content: BriefContent) {
        guard let url = cacheFileURL(day: content.date) else { return }
        guard let out = try? JSONEncoder().encode(content) else { return }
        try? out.write(to: url, options: .atomic)
        pruneOldCacheFiles()
    }

    /// Keep only the most recent `maxCachedDays` day files so the cache
    /// doesn't grow unbounded across app lifetime.
    private func pruneOldCacheFiles() {
        guard let dir = cacheDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }
        for url in sorted.dropFirst(Self.maxCachedDays) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
