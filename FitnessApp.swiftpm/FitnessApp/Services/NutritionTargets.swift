import Foundation

/// Astra's own optional daily nutrition targets (protein + kcal), distinct
/// from the always-defaulted `MacroGoals` (`NutritionService`) that back the
/// Nutrition dashboard's rings. `MacroGoals` silently falls back to a
/// hardcoded 2000 kcal / 150 g the moment the app launches — useful for the
/// rings, but dishonest as a "coaching target" since the user never actually
/// chose it. `NutritionTargets` starts genuinely `nil` ("no target set") so
/// the dashboard and Astra's `set_nutrition_targets` tool can both be honest
/// about whether a real, deliberate target exists yet.
///
/// Written ONLY through the confirmation-gated `set_nutrition_targets` tool
/// (`ChatViewModel.executeWriteTool`) — never silently by the model, and
/// never inferred. `setBy` records whether the user or Astra proposed the
/// value that was ultimately confirmed, for transparency in the UI.
@MainActor
public final class NutritionTargets: ObservableObject {
    public static let shared = NutritionTargets()

    public enum SetBy: String, Codable {
        case user
        case astra
    }

    @Published public private(set) var proteinTargetG: Double?
    @Published public private(set) var kcalTarget: Double?
    @Published public private(set) var proteinSetBy: SetBy?
    @Published public private(set) var kcalSetBy: SetBy?
    @Published public private(set) var proteinSetAt: Date?
    @Published public private(set) var kcalSetAt: Date?

    /// Sane bounds — enforced again here (in addition to the tool dispatch
    /// validation) so no future caller can silently bypass them.
    public static let proteinRange: ClosedRange<Double> = 20...400
    public static let kcalRange: ClosedRange<Double> = 800...6000

    private enum Keys {
        static let proteinG     = "nutrition_target_protein_g"
        static let kcal         = "nutrition_target_kcal"
        static let proteinSetBy = "nutrition_target_protein_set_by"
        static let kcalSetBy    = "nutrition_target_kcal_set_by"
        static let proteinSetAt = "nutrition_target_protein_set_at"
        static let kcalSetAt    = "nutrition_target_kcal_set_at"
    }

    private let defaults = UserDefaults.standard

    private init() {
        if defaults.object(forKey: Keys.proteinG) != nil {
            proteinTargetG = defaults.double(forKey: Keys.proteinG)
        }
        if defaults.object(forKey: Keys.kcal) != nil {
            kcalTarget = defaults.double(forKey: Keys.kcal)
        }
        proteinSetBy = defaults.string(forKey: Keys.proteinSetBy).flatMap(SetBy.init(rawValue:))
        kcalSetBy    = defaults.string(forKey: Keys.kcalSetBy).flatMap(SetBy.init(rawValue:))
        let pAt = defaults.double(forKey: Keys.proteinSetAt)
        proteinSetAt = pAt > 0 ? Date(timeIntervalSince1970: pAt) : nil
        let kAt = defaults.double(forKey: Keys.kcalSetAt)
        kcalSetAt = kAt > 0 ? Date(timeIntervalSince1970: kAt) : nil
    }

    /// Sets whichever of the two targets is non-nil (both may be set in the
    /// same call). Values are clamped to the ranges above as a last line of
    /// defense against an out-of-bounds caller.
    public func setTargets(proteinG: Double?, kcal: Double?, setBy: SetBy) {
        let now = Date()
        if let p = proteinG {
            let clamped = min(max(p, Self.proteinRange.lowerBound), Self.proteinRange.upperBound)
            proteinTargetG = clamped
            proteinSetBy = setBy
            proteinSetAt = now
            defaults.set(clamped, forKey: Keys.proteinG)
            defaults.set(setBy.rawValue, forKey: Keys.proteinSetBy)
            defaults.set(now.timeIntervalSince1970, forKey: Keys.proteinSetAt)
        }
        if let k = kcal {
            let clamped = min(max(k, Self.kcalRange.lowerBound), Self.kcalRange.upperBound)
            kcalTarget = clamped
            kcalSetBy = setBy
            kcalSetAt = now
            defaults.set(clamped, forKey: Keys.kcal)
            defaults.set(setBy.rawValue, forKey: Keys.kcalSetBy)
            defaults.set(now.timeIntervalSince1970, forKey: Keys.kcalSetAt)
        }
    }

    /// Clears both targets back to the honest "no target set" state.
    public func clearAll() {
        proteinTargetG = nil
        kcalTarget = nil
        proteinSetBy = nil
        kcalSetBy = nil
        proteinSetAt = nil
        kcalSetAt = nil
        for key in [Keys.proteinG, Keys.kcal, Keys.proteinSetBy, Keys.kcalSetBy, Keys.proteinSetAt, Keys.kcalSetAt] {
            defaults.removeObject(forKey: key)
        }
    }
}
