// ============================================================
// FoodVisionService — photo-based food recognition via Gemini Vision.
// File: FitnessApp/Services/FoodVisionService.swift
//
// One-shot, non-streaming call through the Atlas AI Gateway's /v1/chat
// proxy (logical model "chat"; the server maps it to a concrete Gemini
// model and holds the GCP credentials). Reuses
// GatewayChatClient.thinkingBudgetTokens(). Returns the frozen contract
// type FoodRecognitionResult, or throws a typed FoodVisionError. No mock data.
// ============================================================

import Foundation
import UIKit

public actor FoodVisionService {
    public static let shared = FoodVisionService()
    private init() {}

    private let timeout: TimeInterval = 20

    /// Resize to ≤1024px (Gemini tiles at 768px; larger adds tokens, not
    /// accuracy), JPEG q=0.7, then POST to the gateway's non-streaming
    /// /v1/chat proxy with responseMimeType: application/json and responseSchema.
    ///
    /// Throws on network error, HTTP non-2xx, JSON parse failure, or
    /// food_detected=false (callers catch and show a "No food detected" state).
    public func recognizeFood(imageData: Data) async throws -> FoodRecognitionResult {
        // 1. Downscale image
        guard let ui = UIImage(data: imageData) else {
            throw FoodVisionError.invalidImage
        }
        let resized = ui.resizedForVision(maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else {
            throw FoodVisionError.invalidImage
        }

        // 2. Build the gateway body (structured JSON output via responseSchema)
        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        let body = GatewayChatPayload.body(
            stream: false,
            system: Self.systemInstruction,
            messages: [GatewayChatPayload.message(role: "user", parts: [
                GatewayChatPayload.imagePart(data: jpeg, mimeType: "image/jpeg"),
                GatewayChatPayload.textPart(Self.userPrompt)
            ])],
            generationConfig: [
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema,
                "temperature": 0.2,
                "maxOutputTokens": 1024 + thinkingBudget,
                "thinkingConfig": ["thinkingBudget": thinkingBudget]
            ]
        )

        // 3. Execute through the shared gateway transport (bearer + 401 retry)
        let data: Data
        do {
            data = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: timeout)
        } catch let gateway as GatewayError {
            throw FoodVisionError.gateway(gateway.userMessage)
        } catch {
            throw FoodVisionError.gateway(error.localizedDescription)
        }

        // Count this scan's tokens against the food-vision bucket using Gemini's
        // built-in usage report — recorded once per call, even if the body later
        // fails to parse as food.
        if let meta = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["usageMetadata"] as? [String: Any],
           let usage = TokenUsage(usageMetadata: meta) {
            Task { @MainActor in TokenMeter.shared.record(usage, source: .foodVision) }
        }

        // 5. Extract candidates[0].content.parts[*].text (first part carrying text)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let jsonText = parts.first(where: { $0["text"] is String })?["text"] as? String,
              let jsonData = jsonText.data(using: .utf8)
        else { throw FoodVisionError.parseError }

        // 6. Decode into FoodRecognitionResult. Explicit snake_case CodingKeys
        //    on the contract types handle the mapping; no key strategy needed.
        let decoder = JSONDecoder()
        let result: FoodRecognitionResult
        do {
            result = try decoder.decode(FoodRecognitionResult.self, from: jsonData)
        } catch {
            throw FoodVisionError.parseError
        }

        // 7. Honest no-food state surfaces as a typed error, never mock data.
        guard result.foodDetected else { throw FoodVisionError.noFoodDetected }
        return result
    }

    /// Conversational correction. Given the original photo, the items currently
    /// shown to the user (as JSON), and a natural-language instruction, re-analyze
    /// and return the corrected full item list. Astra's short reply to the user is
    /// returned in `plateNote`. Does NOT throw on empty/no-food (the user may have
    /// asked to remove everything) — the caller decides what to do.
    public func refineFood(imageData: Data,
                           currentItemsJSON: String,
                           instruction: String) async throws -> FoodRecognitionResult {
        guard let ui = UIImage(data: imageData) else { throw FoodVisionError.invalidImage }
        let resized = ui.resizedForVision(maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { throw FoodVisionError.invalidImage }

        let refinePrompt = """
        You previously identified these food items from the attached photo:
        \(currentItemsJSON)

        The user is correcting you. They said:
        "\(instruction)"

        Re-examine the photo with their correction in mind and return the COMPLETE \
        corrected item list (every item that should be logged) with updated names, \
        portions, and macros. Apply the user's change precisely. Keep the other items \
        unless the user asked to remove them; if they say an item is wrong or not in \
        the photo, drop it; if they add detail (e.g. "skinless", "no oil added", \
        "2 cups"), adjust that item's macros to match.

        Put a short (≤25 word) friendly reply to the user in plate_note describing what \
        you changed. Return JSON conforming exactly to the schema. No other output.
        """

        let thinkingBudget = GatewayChatClient.thinkingBudgetTokens()
        let body = GatewayChatPayload.body(
            stream: false,
            system: Self.systemInstruction,
            messages: [GatewayChatPayload.message(role: "user", parts: [
                GatewayChatPayload.imagePart(data: jpeg, mimeType: "image/jpeg"),
                GatewayChatPayload.textPart(refinePrompt)
            ])],
            generationConfig: [
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema,
                "temperature": 0.2,
                "maxOutputTokens": 1024 + thinkingBudget,
                "thinkingConfig": ["thinkingBudget": thinkingBudget]
            ]
        )

        let data: Data
        do {
            data = try await GatewayTransport.postJSON(path: "v1/chat", body: body, timeout: timeout)
        } catch let gateway as GatewayError {
            throw FoodVisionError.gateway(gateway.userMessage)
        } catch {
            throw FoodVisionError.gateway(error.localizedDescription)
        }

        if let meta = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["usageMetadata"] as? [String: Any],
           let usage = TokenUsage(usageMetadata: meta) {
            Task { @MainActor in TokenMeter.shared.record(usage, source: .foodVision) }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let jsonText = parts.first(where: { $0["text"] is String })?["text"] as? String,
              let jsonData = jsonText.data(using: .utf8)
        else { throw FoodVisionError.parseError }

        guard let result = try? JSONDecoder().decode(FoodRecognitionResult.self, from: jsonData) else {
            throw FoodVisionError.parseError
        }
        return result
    }
}

// MARK: - Prompts (private static, not recomputed per call)

private extension FoodVisionService {
    static let systemInstruction = """
    You are a registered dietitian and nutrition scientist. Your role is to analyze \
    food images and provide calorie and macronutrient estimates. You are honest about \
    uncertainty — you always label your outputs as estimates and you never fabricate \
    precise numbers when visual evidence is insufficient. Return ONLY valid JSON \
    matching the required schema. Do not add prose, markdown, or code fences.
    """

    static let userPrompt = """
    Analyze the food in this image. For every distinct food item or dish component \
    you can identify, provide your best estimate of its nutritional content based on \
    what is visually apparent.

    Rules:
    1. Identify EACH visually distinct food item separately (e.g., rice, grilled \
    chicken, broccoli are three items — not one).
    2. For each item, estimate: calories_kcal, protein_g, carbs_g, fat_g, and a \
    human-readable portion_description (e.g. "~1 cup", "~150 g", "1 medium piece").
    3. All values are estimates from visual evidence only. Mark is_estimate as true \
    for every item, always.
    4. Assess your overall confidence in the full plate analysis: "high" (food clearly \
    visible, common dish, good lighting), "medium" (some uncertainty about ingredients \
    or portion), or "low" (dish is ambiguous, mixed, obscured, blurry, or unfamiliar).
    5. If you cannot identify any food in the image (non-food object, fully obscured, \
    or unrecognizable content), return food_detected: false and an empty items array.
    6. Provide a brief (≤20 word) identification_note per item explaining what you \
    think it is and any key uncertainty.
    7. Estimate portion sizes using visual cues: plate/bowl size relative to food, \
    utensils, hand if visible, or typical serving conventions. Do NOT default to a \
    standard serving size unless there is no other visual evidence.
    8. For hidden ingredients (oils, sauces, dressings) that are visually present but \
    unquantifiable, add them as a separate item with a note in identification_note and \
    set confidence to "low" for that item.
    9. overall_confidence must be "low" if ANY single item has confidence "low".

    Return JSON conforming exactly to the schema. No other output.
    """

    static let responseSchema: [String: Any] = [
        "type": "object",
        "required": ["food_detected", "items", "totals", "overall_confidence"],
        "additionalProperties": false,
        "properties": [
            "food_detected": [
                "type": "boolean",
                "description": "false if the image contains no identifiable food"
            ],
            "items": [
                "type": "array",
                "description": "One entry per distinct food component. Empty if food_detected is false.",
                "items": [
                    "type": "object",
                    "required": ["name","portion_description","calories_kcal","protein_g",
                                 "carbs_g","fat_g","is_estimate","confidence","identification_note"],
                    "additionalProperties": false,
                    "properties": [
                        "name": ["type": "string",
                                 "description": "Common English name of the food item"],
                        "portion_description": ["type": "string",
                                                "description": "Human-readable portion estimate"],
                        "calories_kcal": ["type": "number",
                                          "description": "Estimated kcal. Use 0 if unquantifiable."],
                        "protein_g": ["type": "number"],
                        "carbs_g": ["type": "number"],
                        "fat_g": ["type": "number"],
                        "is_estimate": ["type": "boolean",
                                        "description": "Always true. Never false."],
                        "confidence": ["type": "string",
                                       "enum": ["high","medium","low"],
                                       "description": "Per-item confidence in identification and portion"],
                        "identification_note": ["type": "string",
                                                "description": "≤20 words. Key uncertainty for this item."]
                    ]
                ]
            ],
            "totals": [
                "type": "object",
                "required": ["calories_kcal","protein_g","carbs_g","fat_g"],
                "additionalProperties": false,
                "description": "Sum of all items. Client recomputes after user edits.",
                "properties": [
                    "calories_kcal": ["type": "number"],
                    "protein_g": ["type": "number"],
                    "carbs_g": ["type": "number"],
                    "fat_g": ["type": "number"]
                ]
            ],
            "overall_confidence": [
                "type": "string",
                "enum": ["high","medium","low"],
                "description": "Single rating for the entire plate. Low if ANY item is low."
            ],
            "plate_note": [
                "type": "string",
                "description": "Optional. ≤30 words describing a key caveat about the overall meal."
            ]
        ]
    ]
}

// MARK: - UIImage resize helper
// Local to this file. Distinct name from ChatView's `resizedForUpload`, so the
// two additive extensions never collide.

private extension UIImage {
    func resizedForVision(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Error type

public enum FoodVisionError: LocalizedError {
    case invalidImage
    case parseError
    case noFoodDetected
    /// Transport / auth / rate-limit failure from the gateway — carries the
    /// GatewayError's honest user-facing message (e.g. "Astra is catching
    /// its breath — try again in ~5s.").
    case gateway(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage:        return "Could not process image."
        case .parseError:          return "Could not read AI response."
        case .noFoodDetected:      return "No food detected in this photo."
        case .gateway(let message): return message
        }
    }
}
