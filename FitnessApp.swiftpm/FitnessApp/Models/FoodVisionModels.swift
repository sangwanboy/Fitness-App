// ============================================================
// FROZEN SHARED CONTRACT — all three agents code against this verbatim.
// File: FitnessApp/Models/FoodVisionModels.swift  (created by Agent 1)
//
// Photo-based food logging: typed results returned by FoodVisionService
// (Gemini Vision) and consumed by FoodScanView / FoodReviewSheet (Agent 2)
// and the entry-point sheet (Agent 3). No mock data lives here.
// ============================================================

import Foundation

// MARK: - Per-item result from Gemini Vision

/// One distinct food component identified in a photo. `id` is generated
/// client-side (Gemini never sends it). All numeric values are honest
/// estimates — `isEstimate` is always true per the prompt contract.
public struct RecognizedFoodItem: Identifiable, Codable {
    public var id: UUID = UUID()          // client-generated; not from Gemini
    public var name: String
    public var portionDescription: String // e.g. "~150 g / 1 medium piece"
    public var calories: Double           // kcal
    public var protein: Double            // g
    public var carbs: Double              // g
    public var fat: Double                // g
    public let isEstimate: Bool           // always true per prompt contract
    public let confidence: String         // "high" | "medium" | "low"
    public let identificationNote: String // ≤20-word AI note

    /// Convenience init for Agent 2 previews and Agent 3 tests. In production
    /// items are produced exclusively via Codable decoding of Gemini output;
    /// this init exists only for #if DEBUG blocks / SwiftUI previews / tests.
    public init(id: UUID = UUID(),
                name: String,
                portionDescription: String,
                calories: Double,
                protein: Double,
                carbs: Double,
                fat: Double,
                isEstimate: Bool = true,
                confidence: String,
                identificationNote: String) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isEstimate = isEstimate
        self.confidence = confidence
        self.identificationNote = identificationNote
    }

    // Map Swift camelCase <-> Gemini snake_case JSON. `id` is intentionally
    // absent: it is synthesized client-side, never decoded from Gemini.
    private enum CodingKeys: String, CodingKey {
        case name
        case portionDescription = "portion_description"
        case calories           = "calories_kcal"
        case protein            = "protein_g"
        case carbs              = "carbs_g"
        case fat                = "fat_g"
        case isEstimate         = "is_estimate"
        case confidence
        case identificationNote = "identification_note"
    }

    /// Custom decode: always mint a fresh `id`, then pull the rest from JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name               = try c.decode(String.self, forKey: .name)
        self.portionDescription = try c.decode(String.self, forKey: .portionDescription)
        self.calories           = try c.decode(Double.self, forKey: .calories)
        self.protein            = try c.decode(Double.self, forKey: .protein)
        self.carbs              = try c.decode(Double.self, forKey: .carbs)
        self.fat                = try c.decode(Double.self, forKey: .fat)
        self.isEstimate         = try c.decode(Bool.self,   forKey: .isEstimate)
        self.confidence         = try c.decode(String.self, forKey: .confidence)
        self.identificationNote = try c.decode(String.self, forKey: .identificationNote)
    }

    /// Encode mirrors the snake_case keys (id stays client-only).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,               forKey: .name)
        try c.encode(portionDescription, forKey: .portionDescription)
        try c.encode(calories,           forKey: .calories)
        try c.encode(protein,            forKey: .protein)
        try c.encode(carbs,              forKey: .carbs)
        try c.encode(fat,                forKey: .fat)
        try c.encode(isEstimate,         forKey: .isEstimate)
        try c.encode(confidence,         forKey: .confidence)
        try c.encode(identificationNote, forKey: .identificationNote)
    }
}

// MARK: - Full plate result

/// The complete analysis of one photo. `foodDetected == false` means Gemini
/// found no identifiable food (callers show a "No food detected" state).
public struct FoodRecognitionResult: Codable {
    public let foodDetected: Bool
    public let items: [RecognizedFoodItem]
    public let overallConfidence: String  // "high" | "medium" | "low"
    public let plateNote: String?         // optional caveat from model

    /// Convenience init for previews / tests (no mock data in production).
    public init(foodDetected: Bool,
                items: [RecognizedFoodItem],
                overallConfidence: String,
                plateNote: String?) {
        self.foodDetected = foodDetected
        self.items = items
        self.overallConfidence = overallConfidence
        self.plateNote = plateNote
    }

    // Map Swift camelCase <-> Gemini snake_case JSON. The `totals` object the
    // model returns is intentionally ignored here — the client recomputes
    // totals after user edits, so it is not part of this decoded contract.
    private enum CodingKeys: String, CodingKey {
        case foodDetected      = "food_detected"
        case items
        case overallConfidence = "overall_confidence"
        case plateNote         = "plate_note"
    }
}
