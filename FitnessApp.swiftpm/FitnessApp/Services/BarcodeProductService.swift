// ============================================================
// BarcodeProductService — looks up a scanned barcode/GTIN against the public
// Open Food Facts v2 product API and returns a typed BarcodeProduct.
// File: FitnessApp/Services/BarcodeProductService.swift
//
// One GET request, no retries, no fallback/mock data. If Open Food Facts has
// no record (status 0) or returns a usable-but-incomplete entry, callers get a
// typed error and show an honest "not in database" state.
// ============================================================

import Foundation

public enum BarcodeLookupError: LocalizedError {
    case notFound          // OFF status 0, or HTTP 404 — no product for this GTIN
    case network           // transport failure / non-404 HTTP error
    case malformed         // response body could not be decoded into a usable product

    public var errorDescription: String? {
        switch self {
        case .notFound:  return "Product not in the database"
        case .network:   return "Couldn't reach the product database. Check your connection and try again."
        case .malformed: return "This product's label data couldn't be read."
        }
    }
}

public actor BarcodeProductService {
    public static let shared = BarcodeProductService()
    private init() {}

    private let fields = "product_name,brands,serving_size,nutriments"
    private let userAgent = "FitnessGuru-iOS/1.0 (personal project)"

    /// Looks up a single barcode. `barcode` should be the bare GTIN digits.
    /// Throws `BarcodeLookupError`.
    public func lookup(barcode: String) async throws -> BarcodeProduct {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BarcodeLookupError.notFound }

        let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(trimmed).json?fields=\(fields)"
        guard let url = URL(string: urlStr) else { throw BarcodeLookupError.network }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BarcodeLookupError.network
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw BarcodeLookupError.notFound }
            guard (200..<300).contains(http.statusCode) else {
                throw BarcodeLookupError.network
            }
        }

        // OFF wraps the product in a status envelope: status == 0 means "no
        // product found" even on a 200 response.
        if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = envelope["status"] as? Int,
           status == 0 {
            throw BarcodeLookupError.notFound
        }

        do {
            var product = try JSONDecoder().decode(BarcodeProduct.self, from: data)
            product.barcode = trimmed
            return product
        } catch {
            // A 200 with no `product` object (or missing name/nutriments) means
            // OFF effectively has nothing usable for this code.
            throw BarcodeLookupError.notFound
        }
    }
}
