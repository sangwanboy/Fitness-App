import Foundation
import SwiftUI
import HealthKit

// MARK: - MacroGoals

public struct MacroGoals {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public static let defaults = MacroGoals(calories: 2000, protein: 150, carbs: 225, fat: 67)
}

// MARK: - NutritionService

@MainActor
public final class NutritionService: ObservableObject {
    public static let shared = NutritionService()

    private let healthStore = HKHealthStore()

    // MARK: Published macro totals (today)

    @Published public var carbsToday: Double = 0
    @Published public var fatToday: Double = 0
    @Published public var fiberToday: Double = 0
    @Published public var sugarToday: Double = 0
    @Published public var sodiumMgToday: Double = 0
    @Published public var caffeineMgToday: Double = 0

    @Published public var isLoading: Bool = false

    // MARK: Macro goals (backed by AppStorage-style UserDefaults)

    public var macroGoals: MacroGoals {
        get {
            MacroGoals(
                calories: readGoal(key: "goal_macro_calories", default: MacroGoals.defaults.calories),
                protein:  readGoal(key: "goal_macro_protein",  default: MacroGoals.defaults.protein),
                carbs:    readGoal(key: "goal_macro_carbs",    default: MacroGoals.defaults.carbs),
                fat:      readGoal(key: "goal_macro_fat",      default: MacroGoals.defaults.fat)
            )
        }
        set {
            UserDefaults.standard.set(newValue.calories, forKey: "goal_macro_calories")
            UserDefaults.standard.set(newValue.protein,  forKey: "goal_macro_protein")
            UserDefaults.standard.set(newValue.carbs,    forKey: "goal_macro_carbs")
            UserDefaults.standard.set(newValue.fat,      forKey: "goal_macro_fat")
            objectWillChange.send()
        }
    }

    private func readGoal(key: String, default def: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : def
    }

    private init() {}

    // MARK: - Refresh

    /// Fetch all micro / macro values for today from HealthKit. Mirrors the
    /// pattern used in HealthKitManager.fetchTodayData() — one concurrent
    /// task group, main-actor writes.
    public func refreshToday() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isLoading = true
        defer { isLoading = false }

        async let carbs    = fetchTodaySum(hkID: .dietaryCarbohydrates, unit: .gram())
        async let fat      = fetchTodaySum(hkID: .dietaryFatTotal,      unit: .gram())
        async let fiber    = fetchTodaySum(hkID: .dietaryFiber,         unit: .gram())
        async let sugar    = fetchTodaySum(hkID: .dietarySugar,         unit: .gram())
        async let sodium   = fetchTodaySum(hkID: .dietarySodium,        unit: .gram())   // HK stores sodium in grams
        async let caffeine = fetchTodaySum(hkID: .dietaryCaffeine,      unit: .gram())   // HK stores caffeine in grams

        let (c, fa, fi, su, so, ca) = await (carbs, fat, fiber, sugar, sodium, caffeine)

        carbsToday       = c
        fatToday         = fa
        fiberToday       = fi
        sugarToday       = su
        sodiumMgToday    = so * 1000   // convert g → mg
        caffeineMgToday  = ca * 1000   // convert g → mg
    }

    // MARK: - Goal persistence helpers (public for the goals editor)

    public func setCaloriesGoal(_ v: Double) { UserDefaults.standard.set(v, forKey: "goal_macro_calories"); objectWillChange.send() }
    public func setProteinGoal(_ v: Double)  { UserDefaults.standard.set(v, forKey: "goal_macro_protein");  objectWillChange.send() }
    public func setCarbsGoal(_ v: Double)    { UserDefaults.standard.set(v, forKey: "goal_macro_carbs");    objectWillChange.send() }
    public func setFatGoal(_ v: Double)      { UserDefaults.standard.set(v, forKey: "goal_macro_fat");      objectWillChange.send() }

    // MARK: - Private HK helpers

    private func fetchTodaySum(hkID: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: hkID) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: v)
            }
            healthStore.execute(q)
        }
    }
}
