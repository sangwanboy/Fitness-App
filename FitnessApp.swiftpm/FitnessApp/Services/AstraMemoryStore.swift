import SwiftUI

/// Astra's structured long-term memory of the user — separate from (and a
/// successor to) the free-text `update_notes` blob. Two parts:
///
/// 1. `facts` — small, atomic, categorized memories ("left knee sensitive to
///    high-impact running") that the model writes one at a time via
///    `remember_fact` / removes via `forget_fact`. Capped at `maxFacts`;
///    oldest is evicted first, and the tool response always says so.
/// 2. `profile` — a handful of model-maintained prose sections (summary,
///    goals, training context, injuries/limitations, preferences, nutrition
///    notes) that Astra rewrites wholesale via `update_profile`.
///
/// Storage mirrors `ChatHistoryStore`'s pattern: one small JSON blob in
/// UserDefaults, loaded once at init, re-saved on every mutation.
///
/// "Live basics" (age, height, weight, VO2max, resting HR) are deliberately
/// NOT part of the persisted model — HealthKit / the athlete_* AppStorage
/// keys already own that data and can change at any time. `liveBasics()`
/// re-derives them at READ time so they're never stale and never duplicated.
@MainActor
public final class AstraMemoryStore: ObservableObject {
    public static let shared = AstraMemoryStore()

    /// Hard cap on stored facts. Oldest (by `createdAt`) is evicted first —
    /// `remember(category:text:)` returns the evicted fact (if any) so the
    /// caller can tell the model what was dropped.
    public static let maxFacts = 60

    /// Hard cap on one fact's text length. `remember_fact` is meant for one
    /// atomic idea, not a paragraph — truncating at write time (rather than
    /// only at render time) keeps the stored data itself bounded, so every
    /// future render/read of this fact is cheap by construction.
    public static let maxFactTextLength = 140

    /// Soft budget for `renderForSystemPrompt`'s output — keeps the per-turn
    /// memory injection to roughly 350 tokens even as facts accumulate.
    public static let systemPromptCharBudget = 1400

    private static let storageKey = "astra_memory_v1"

    /// Master toggle — Settings shows this as a switch, tools honor it before
    /// any read or write. Same key name/default the SwiftUI section binds to,
    /// so both observe the same UserDefaults value (mirrors the
    /// `@AppStorage` used directly inside `HeartRateZoneCalculator`).
    @AppStorage("astra_memory_enabled") public var isEnabled: Bool = true

    @Published public private(set) var facts: [MemoryFact] = []
    @Published public private(set) var profile: AstraUserProfile = AstraUserProfile()

    private init() {
        load()
    }

    // MARK: - Facts CRUD

    /// Append a new fact, evicting the oldest if the store is over `maxFacts`.
    /// Text longer than `maxFactTextLength` is truncated (ellipsis) before
    /// storage — the caller can tell the model it happened via `truncated`.
    @discardableResult
    public func remember(category: MemoryFact.Category, text: String) -> (fact: MemoryFact, evicted: MemoryFact?, truncated: Bool) {
        let now = Date()
        var storedText = text
        var truncated = false
        if storedText.count > Self.maxFactTextLength {
            storedText = String(storedText.prefix(Self.maxFactTextLength - 1)) + "…"
            truncated = true
        }
        let fact = MemoryFact(id: UUID(), category: category, text: storedText, createdAt: now, updatedAt: now)
        facts.append(fact)
        var evicted: MemoryFact?
        if facts.count > Self.maxFacts {
            evicted = facts.first
            facts.removeFirst()
        }
        save()
        return (fact, evicted, truncated)
    }

    /// Remove every fact whose text contains `query` (case-insensitive).
    /// Returns the facts that were removed (empty when nothing matched) so
    /// the caller can report exactly what went away.
    @discardableResult
    public func forget(matching query: String) -> [MemoryFact] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let matches = facts.filter { $0.text.lowercased().contains(needle) }
        guard !matches.isEmpty else { return [] }
        let ids = Set(matches.map(\.id))
        facts.removeAll { ids.contains($0.id) }
        save()
        return matches
    }

    /// UI-driven single-fact delete (swipe-to-delete in Settings) — exact id,
    /// no fuzzy matching.
    public func deleteFact(id: UUID) {
        guard facts.contains(where: { $0.id == id }) else { return }
        facts.removeAll { $0.id == id }
        save()
    }

    // MARK: - Profile

    /// Replace one profile section's full content and stamp `lastUpdated`.
    /// Empty content clears the section (renders as "not set" in the UI and
    /// is skipped by `renderForSystemPrompt`).
    public func updateProfileSection(_ section: AstraUserProfile.Section, content: String) {
        profile.set(section, text: content.trimmingCharacters(in: .whitespacesAndNewlines))
        save()
    }

    // MARK: - Reset

    /// Wipe everything — facts and every profile section, PLUS the legacy
    /// `astra_notes` blob (the pre-structured-memory cross-session store).
    /// The user's "clear my memory" intent has to cover every store Astra
    /// writes cross-session data into, not just the newer one — otherwise
    /// "Clear all" silently leaves the old notes behind. Does not touch the
    /// enabled toggle.
    public func clearAll() {
        facts = []
        profile = AstraUserProfile()
        UserDefaults.standard.removeObject(forKey: "astra_notes")
        save()
    }

    // MARK: - System-prompt rendering

    public var isEmpty: Bool { facts.isEmpty && profile.isEmpty }

    /// Compact text block for injection into the system prompt: non-empty
    /// profile sections first (always included in full), then facts grouped
    /// by category (one line per category, semicolon-joined), added
    /// newest-first until `systemPromptCharBudget` runs out — so budget
    /// pressure drops the OLDEST memories, not whatever the model just wrote
    /// this session. When facts get cut, one trailing line notes how many
    /// were omitted so the model knows its memory isn't fully in view. The
    /// empty string is returned when there's nothing to say.
    public func renderForSystemPrompt() -> String {
        var profileLines: [String] = []
        for section in AstraUserProfile.Section.allCases {
            let text = profile.get(section).text
            guard !text.isEmpty else { continue }
            profileLines.append("- \(section.displayName): \(text)")
        }
        let profileBlock = profileLines.isEmpty ? "" : "PROFILE\n" + profileLines.joined(separator: "\n")

        let newestFirst = facts.sorted { $0.createdAt > $1.createdAt }
        var remainingBudget = Self.systemPromptCharBudget - profileBlock.count
        var includedByCategory: [MemoryFact.Category: [String]] = [:]
        var omittedCount = 0
        for fact in newestFirst {
            let cost = fact.text.count + 2 // rough "; "-separator overhead
            guard remainingBudget - cost > 0 else { omittedCount += 1; continue }
            includedByCategory[fact.category, default: []].append(fact.text)
            remainingBudget -= cost
        }

        var factLines: [String] = []
        for category in MemoryFact.Category.allCases {
            guard let texts = includedByCategory[category], !texts.isEmpty else { continue }
            // Selection above walked newest-first; restore oldest-first for
            // display so a category's line still reads in chronological order.
            factLines.append("- \(category.displayName): " + texts.reversed().joined(separator: "; "))
        }
        if omittedCount > 0 {
            factLines.append("(\(omittedCount) older memor\(omittedCount == 1 ? "y" : "ies") omitted for space)")
        }
        let factsBlock = factLines.isEmpty ? "" : "MEMORIES\n" + factLines.joined(separator: "\n")

        return [profileBlock, factsBlock].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // MARK: - get_profile tool payload

    /// Full structured dump (profile + facts + live basics) for the
    /// `get_profile` tool so the model can review current state before
    /// calling `update_profile` / `remember_fact`.
    public func fullPayload() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var profileDict: [String: Any] = [:]
        for section in AstraUserProfile.Section.allCases {
            let content = profile.get(section)
            guard !content.text.isEmpty else { continue }
            var d: [String: Any] = ["content": content.text]
            if let updated = content.lastUpdated { d["last_updated"] = iso.string(from: updated) }
            profileDict[section.rawValue] = d
        }
        let factsArray: [[String: Any]] = facts.map { fact in
            [
                "id": fact.id.uuidString,
                "category": fact.category.rawValue,
                "text": fact.text,
                "created_at": iso.string(from: fact.createdAt),
                "updated_at": iso.string(from: fact.updatedAt)
            ]
        }
        var payload: [String: Any] = [
            "success": true,
            "enabled": true,
            "profile": profileDict,
            "facts": factsArray,
            "fact_count": facts.count,
            "max_facts": Self.maxFacts
        ]
        payload["live_basics"] = Self.liveBasics().asDict
        return payload
    }

    // MARK: - Live basics (derived at read time — never stored)

    /// Snapshot of the athlete's basics pulled live from HealthKit +
    /// AppStorage every time it's requested. Mirrors the exact fallback
    /// chain `ChatViewModel.buildSystemInstruction` already uses for age /
    /// height / weight, plus VO2max and resting HR straight from
    /// `HealthKitManager.metricSummaries`. Never cached on this store.
    public struct LiveBasics {
        public let age: Int?
        public let heightCm: Double?
        public let weightKg: Double?
        public let vo2Max: Double?
        public let restingHR: Double?

        var asDict: [String: Any] {
            var d: [String: Any] = [:]
            if let age { d["age"] = age }
            if let heightCm { d["height_cm"] = heightCm }
            if let weightKg { d["weight_kg"] = weightKg }
            if let vo2Max { d["vo2_max"] = vo2Max }
            if let restingHR { d["resting_hr"] = restingHR }
            return d
        }
    }

    public static func liveBasics() -> LiveBasics {
        let ud = UserDefaults.standard
        let hk = HealthKitManager.shared

        let dobInterval = ud.double(forKey: "athlete_dob")
        let (hkDob, _, _) = hk.readMedicalIdCharacteristics()
        let dobDate: Date? = dobInterval > 0 ? Date(timeIntervalSince1970: dobInterval) : hkDob
        // Implausible DOB (future, or age < 5 — e.g. a date picker that
        // defaulted to "today" and got saved) is bad data, not a fact.
        // Presenting "Age 0" as truth broke the honesty rule on-device;
        // omit age entirely instead so Astra never sees it.
        let age: Int? = dobDate.flatMap {
            let years = Calendar.current.dateComponents([.year], from: $0, to: Date()).year ?? 0
            return (5...120).contains(years) ? years : nil
        }

        let storedHeight = ud.double(forKey: "athlete_height_cm")
        let heightCm: Double? = storedHeight > 0 ? storedHeight : nil

        let storedWeight = ud.double(forKey: "athlete_weight_kg")
        let hkWeight = hk.metricSummaries[.bodyMass]?.currentValue ?? 0
        let weightKg: Double? = storedWeight > 0 ? storedWeight : (hkWeight > 0 ? hkWeight : nil)

        let vo2Raw = hk.metricSummaries[.vo2Max]?.currentValue ?? 0
        let rhrRaw = hk.metricSummaries[.restingHeartRate]?.currentValue ?? 0

        return LiveBasics(
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            vo2Max: vo2Raw > 0 ? vo2Raw : nil,
            restingHR: rhrRaw > 0 ? rhrRaw : nil
        )
    }

    // MARK: - Persistence

    private struct StoredState: Codable {
        var facts: [MemoryFact]
        var profile: AstraUserProfile
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(StoredState.self, from: data) else { return }
        facts = decoded.facts
        profile = decoded.profile
    }

    private func save() {
        let state = StoredState(facts: facts, profile: profile)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Models

/// A single atomic memory — one idea, one category. Written by `remember_fact`,
/// removed by `forget_fact` (fuzzy) or a Settings swipe-delete (exact id).
public struct MemoryFact: Identifiable, Codable, Equatable {
    public let id: UUID
    public let category: Category
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, category: Category, text: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.category = category
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public enum Category: String, Codable, CaseIterable, Identifiable {
        case goal
        case injury
        case preference
        case schedule
        case nutrition
        case context

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .goal: return "Goal"
            case .injury: return "Injury/Limitation"
            case .preference: return "Preference"
            case .schedule: return "Schedule"
            case .nutrition: return "Nutrition"
            case .context: return "Context"
            }
        }

        public var icon: String {
            switch self {
            case .goal: return "target"
            case .injury: return "bandage.fill"
            case .preference: return "heart.text.square.fill"
            case .schedule: return "clock.fill"
            case .nutrition: return "fork.knife"
            case .context: return "person.text.rectangle.fill"
            }
        }
    }
}

/// Model-maintained prose profile — a handful of named sections, each
/// rewritten wholesale by `update_profile`. Read-only from the UI's
/// perspective (Settings shows it; only Astra edits it).
public struct AstraUserProfile: Codable, Equatable {
    public struct SectionContent: Codable, Equatable {
        public var text: String = ""
        public var lastUpdated: Date?
    }

    public var summary = SectionContent()
    public var goals = SectionContent()
    public var trainingContext = SectionContent()
    public var injuriesLimitations = SectionContent()
    public var preferences = SectionContent()
    public var nutritionNotes = SectionContent()

    public enum Section: String, Codable, CaseIterable, Identifiable {
        case summary
        case goals
        case trainingContext
        case injuriesLimitations
        case preferences
        case nutritionNotes

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .summary: return "Summary"
            case .goals: return "Goals"
            case .trainingContext: return "Training context"
            case .injuriesLimitations: return "Injuries & limitations"
            case .preferences: return "Preferences"
            case .nutritionNotes: return "Nutrition notes"
            }
        }

        public var icon: String {
            switch self {
            case .summary: return "text.alignleft"
            case .goals: return "target"
            case .trainingContext: return "figure.run"
            case .injuriesLimitations: return "bandage.fill"
            case .preferences: return "heart.text.square.fill"
            case .nutritionNotes: return "fork.knife"
            }
        }
    }

    public mutating func set(_ section: Section, text: String) {
        let content = SectionContent(text: text, lastUpdated: Date())
        switch section {
        case .summary: summary = content
        case .goals: goals = content
        case .trainingContext: trainingContext = content
        case .injuriesLimitations: injuriesLimitations = content
        case .preferences: preferences = content
        case .nutritionNotes: nutritionNotes = content
        }
    }

    public func get(_ section: Section) -> SectionContent {
        switch section {
        case .summary: return summary
        case .goals: return goals
        case .trainingContext: return trainingContext
        case .injuriesLimitations: return injuriesLimitations
        case .preferences: return preferences
        case .nutritionNotes: return nutritionNotes
        }
    }

    public var isEmpty: Bool {
        Section.allCases.allSatisfy { get($0).text.isEmpty }
    }
}
