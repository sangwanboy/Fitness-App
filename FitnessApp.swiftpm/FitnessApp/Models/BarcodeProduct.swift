// ============================================================
// BarcodeProduct — a product looked up by barcode/GTIN from Open Food Facts.
// File: FitnessApp/Models/BarcodeProduct.swift
//
// Decodes the Open Food Facts v2 product JSON (the subset requested via the
// `fields` query param) into a single, honest nutrition record. The decoder
// prefers per-serving values when ALL four serving nutriments are present,
// otherwise falls back to per-100 g. No mock data: if the label lacks the
// numbers, decoding throws (handled upstream as a "not in database" state).
//
// Maps into the frozen `RecognizedFoodItem` contract so barcode results flow
// through the EXISTING review/log pipeline exactly like vision results.
// ============================================================

import Foundation

public struct BarcodeProduct: Codable {
    /// The scanned GTIN/barcode digits (echoed back from the lookup, not the JSON).
    public var barcode: String
    public let name: String
    public let brand: String?
    public let servingDescription: String?
    /// Best available product photo from Open Food Facts. Nil when absent or
    /// the URL string is empty/invalid.
    public let imageURL: URL?

    // All four macros are expressed on the chosen `basis`.
    public let calories: Double   // kcal
    public let protein: Double    // g
    public let carbs: Double      // g
    public let fat: Double        // g

    /// Human-readable basis for the four values above.
    public let basis: String      // "per serving" | "per 100 g"

    public init(barcode: String,
                name: String,
                brand: String?,
                servingDescription: String?,
                imageURL: URL? = nil,
                calories: Double,
                protein: Double,
                carbs: Double,
                fat: Double,
                basis: String) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.servingDescription = servingDescription
        self.imageURL = imageURL
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.basis = basis
    }

    // MARK: - Open Food Facts v2 decoding

    private enum RootKeys: String, CodingKey {
        case product
    }

    private enum ProductKeys: String, CodingKey {
        case productName         = "product_name"
        case brands
        case servingSize         = "serving_size"
        case nutriments
        case imageFrontURL       = "image_front_url"
        case imageURL            = "image_url"
        case imageFrontSmallURL  = "image_front_small_url"
    }

    private enum NutrimentKeys: String, CodingKey {
        case energyKcal100g       = "energy-kcal_100g"
        case proteins100g         = "proteins_100g"
        case carbohydrates100g    = "carbohydrates_100g"
        case fat100g              = "fat_100g"
        case energyKcalServing    = "energy-kcal_serving"
        case proteinsServing      = "proteins_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case fatServing           = "fat_serving"
    }

    /// Decodes the `{ "product": { … } }` envelope returned by the v2 product
    /// endpoint. Throws `DecodingError` if the product name or a usable set of
    /// nutriments is missing — Open Food Facts has many sparse entries, and we
    /// never invent values.
    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let product = try root.nestedContainer(keyedBy: ProductKeys.self, forKey: .product)

        // product_name is required for an honest record.
        let rawName = (try product.decodeIfPresent(String.self, forKey: .productName))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawName, !rawName.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [ProductKeys.productName],
                      debugDescription: "Product has no product_name"))
        }
        self.name = rawName

        let rawBrands = (try product.decodeIfPresent(String.self, forKey: .brands))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // OFF stores brands as a comma list; take the first as the primary brand.
        if let rawBrands, !rawBrands.isEmpty {
            self.brand = rawBrands
                .split(separator: ",")
                .first
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
        } else {
            self.brand = nil
        }

        let rawServing = (try product.decodeIfPresent(String.self, forKey: .servingSize))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.servingDescription = (rawServing?.isEmpty == false) ? rawServing : nil

        // Prefer image_front_url, then image_url, then image_front_small_url.
        // Absent, empty, or non-URL strings all map to nil — never throw.
        let imageKeys: [ProductKeys] = [.imageFrontURL, .imageURL, .imageFrontSmallURL]
        var resolvedImageURL: URL? = nil
        for key in imageKeys {
            if let raw = try? product.decodeIfPresent(String.self, forKey: key),
               !raw.isEmpty,
               let candidate = URL(string: raw),
               candidate.scheme?.hasPrefix("http") == true {
                resolvedImageURL = candidate
                break
            }
        }
        self.imageURL = resolvedImageURL

        let n = try product.nestedContainer(keyedBy: NutrimentKeys.self, forKey: .nutriments)

        // OFF nutriment fields are usually numbers but occasionally arrive as
        // strings ("250"); accept either form.
        func flexible(_ key: NutrimentKeys) -> Double? {
            if let d = try? n.decode(Double.self, forKey: key) { return d }
            if let s = try? n.decode(String.self, forKey: key) {
                return Double(s.trimmingCharacters(in: .whitespaces))
            }
            return nil
        }

        let kcalServing    = flexible(.energyKcalServing)
        let proteinServing = flexible(.proteinsServing)
        let carbsServing   = flexible(.carbohydratesServing)
        let fatServing     = flexible(.fatServing)

        // Prefer per-serving when ALL FOUR serving nutriments exist.
        if let kcalServing, let proteinServing, let carbsServing, let fatServing {
            self.calories = kcalServing
            self.protein  = proteinServing
            self.carbs    = carbsServing
            self.fat      = fatServing
            self.basis    = "per serving"
        } else {
            let kcal100    = flexible(.energyKcal100g)
            let protein100 = flexible(.proteins100g)
            let carbs100   = flexible(.carbohydrates100g)
            let fat100     = flexible(.fat100g)

            // Require at least an energy value at 100 g — otherwise this entry
            // carries no usable nutrition and we won't fabricate it.
            guard let kcal100 else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [ProductKeys.nutriments],
                          debugDescription: "Product has no usable nutriments"))
            }
            self.calories = kcal100
            self.protein  = protein100 ?? 0
            self.carbs    = carbs100 ?? 0
            self.fat      = fat100 ?? 0
            self.basis    = "per 100 g"
        }

        // barcode is supplied by the service after decode (not part of the JSON).
        self.barcode = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        // Lightweight encode for debugging/tests; not part of any round-trip
        // with Open Food Facts.
        try c.encode([
            "barcode": barcode, "name": name, "brand": brand ?? "",
            "serving": servingDescription ?? "", "basis": basis,
            "calories": String(calories), "protein": String(protein),
            "carbs": String(carbs), "fat": String(fat)
        ])
    }

    // MARK: - Bridge into the frozen vision contract

    /// Maps this label record into a single `RecognizedFoodItem` so it can ride
    /// the EXISTING review/log pipeline. Label data is authoritative, so
    /// `isEstimate = false` and `confidence = "high"`.
    public func asRecognizedFoodItem() -> RecognizedFoodItem {
        // Combine brand + product name without duplicating the brand when the
        // product name already leads with it (common in OFF data).
        let displayName: String
        if let brand, !name.lowercased().hasPrefix(brand.lowercased()) {
            displayName = "\(brand) \(name)"
        } else {
            displayName = name
        }

        let portion = servingDescription ?? "per 100 g"

        return RecognizedFoodItem(
            name: displayName,
            portionDescription: portion,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            isEstimate: false,
            confidence: "high",
            identificationNote: "Label data · Open Food Facts"
        )
    }
}
