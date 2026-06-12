import SwiftUI
import UIKit

// MARK: - Meal scan flow
// Opens straight into the live camera panel (FoodCameraView). Capture or upload
// a photo -> analyzing -> editable review -> writes to HealthKit.

public struct FoodScanView: View {
    public init() {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private enum ScanPhase {
        case camera
        case analyzing(UIImage)
        case lookingUpProduct(String)        // barcode lookup in flight
        case review(UIImage, FoodRecognitionResult)
        case error(UIImage?, String)
        case noFood(UIImage?)
        case productNotFound                 // OFF has no record for this code
        case productError(String, String)    // (message, barcode) — retryable
    }

    @State private var phase: ScanPhase = .camera
    @State private var analyzeTask: Task<Void, Never>? = nil
    @State private var lookupTask: Task<Void, Never>? = nil

    private var isCameraPhase: Bool {
        if case .camera = phase { return true }
        return false
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                (isDark ? Color.black : Color(red: 0.97, green: 0.97, blue: 0.97))
                    .ignoresSafeArea()

                switch phase {
                case .camera:
                    FoodCameraView(
                        onImage: { img in handlePickedImage(img) },
                        onCancel: { analyzeTask?.cancel(); lookupTask?.cancel(); dismiss() },
                        onBarcode: { code in handleBarcode(code) }
                    )

                case .analyzing(let image):
                    FoodAnalyzingView(image: image) {
                        analyzeTask?.cancel()
                        analyzeTask = nil
                        phase = .camera
                    }

                case .lookingUpProduct:
                    productLookupCard()

                case .review(let image, let result):
                    FoodReviewSheet(image: image, result: result) {
                        dismiss()
                    } onRetake: {
                        phase = .camera
                    }

                case .error(let image, let message):
                    errorCard(image: image, message: message)

                case .noFood(let image):
                    noFoodCard(image: image)

                case .productNotFound:
                    productNotFoundCard()

                case .productError(let message, let barcode):
                    productErrorCard(message: message, barcode: barcode)
                }
            }
            .navigationTitle(isCameraPhase ? "" : "Scan Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isCameraPhase ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if !isCameraPhase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            analyzeTask?.cancel()
                            lookupTask?.cancel()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error state

    private func errorCard(image: UIImage?, message: String) -> some View {
        VStack(spacing: 24) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .opacity(0.6)
            }

            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                Text("Something went wrong")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Try Again") { phase = .camera }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Enter Food Manually") {
                    ChatPrefillBus.shared.queue("Log food: ")
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - No food detected state

    private func noFoodCard(image: UIImage?) -> some View {
        VStack(spacing: 24) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .opacity(0.6)
            }

            VStack(spacing: 8) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No food detected")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text("We couldn't find food in this photo. Try a clearer shot or search manually.")
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Retake Photo") { phase = .camera }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [.orange, .pink],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Search Food Manually") {
                    ChatPrefillBus.shared.queue("Log food: ")
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Barcode lookup

    private func handleBarcode(_ code: String) {
        // Only act from the camera (a fresh scan) or the retryable error state.
        // Ignores stray reads once we've moved into lookup/review/etc.
        switch phase {
        case .camera, .productError:
            break
        default:
            return
        }
        lookupTask?.cancel()
        phase = .lookingUpProduct(code)

        lookupTask = Task {
            do {
                let product = try await BarcodeProductService.shared.lookup(barcode: code)
                guard !Task.isCancelled else { return }

                // Download product photo while still in the loading state.
                // fetchProductImage is best-effort with a 10 s timeout; falls
                // back to the placeholder on any failure.
                let reviewImage: UIImage
                if let imgURL = product.imageURL {
                    let downloaded = await BarcodeProductService.shared.fetchProductImage(url: imgURL)
                    guard !Task.isCancelled else { return }
                    reviewImage = downloaded ?? Self.barcodePlaceholderImage()
                } else {
                    reviewImage = Self.barcodePlaceholderImage()
                }

                // Build a single-item result so the EXISTING review pipeline
                // handles it exactly like a vision result.
                let item = product.asRecognizedFoodItem()
                let result = FoodRecognitionResult(
                    foodDetected: true,
                    items: [item],
                    overallConfidence: "high",
                    plateNote: nil
                )
                await MainActor.run {
                    phase = .review(reviewImage, result)
                }
            } catch let error as BarcodeLookupError {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    switch error {
                    case .notFound:
                        phase = .productNotFound
                    case .network, .malformed:
                        phase = .productError(error.localizedDescription, code)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    phase = .productError(
                        BarcodeLookupError.network.localizedDescription, code)
                }
            }
        }
    }

    /// A neutral placeholder shown in the review sheet's photo slot for barcode
    /// results (there's no captured photo). Honest — a barcode glyph, not a
    /// fabricated meal image.
    private static func barcodePlaceholderImage() -> UIImage {
        let size = CGSize(width: 600, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cfg = UIImage.SymbolConfiguration(pointSize: 96, weight: .regular)
            if let glyph = UIImage(systemName: "barcode.viewfinder", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 0.55, alpha: 1), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - glyph.size.width) / 2,
                                     y: (size.height - glyph.size.height) / 2)
                glyph.draw(at: origin)
            }
        }
    }

    // MARK: - Product lookup loading state

    private func productLookupCard() -> some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .tint(.orange)
                .scaleEffect(1.4)
            Text("Looking up product…")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isDark ? .white : .black)
            Text("Fetching nutrition from Open Food Facts")
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    // MARK: - Product not found state

    private func productNotFoundCard() -> some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            VStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Product not in the database")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text("Open Food Facts doesn't have this item yet. Try scanning again, or take a photo of the food instead.")
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Scan Again") { phase = .camera }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [.orange, .pink],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Take a Photo Instead") { phase = .camera }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Product lookup error state (retryable)

    private func productErrorCard(message: String, barcode: String) -> some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                Text("Lookup failed")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Retry") { handleBarcode(barcode) }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Take a Photo Instead") { phase = .camera }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Image processing + API call

    private func handlePickedImage(_ raw: UIImage) {
        // Move to the analyzing screen immediately so the UI responds; the
        // CPU-bound downscale + JPEG encode then run off the main actor inside
        // the task rather than blocking before the transition.
        phase = .analyzing(raw)

        analyzeTask = Task {
            // Downscale to ≤1200px JPEG q=0.7 — same pipeline as ChatView.stageImage.
            let staged: (UIImage, Data?) = await Task.detached(priority: .userInitiated) {
                let resized = raw.resizedForUpload(maxDimension: 1200)
                return (resized, resized.jpegData(compressionQuality: 0.7))
            }.value
            let resized = staged.0
            guard let jpeg = staged.1 else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    phase = .error(resized, "Couldn't process that photo. Please try again.")
                }
                return
            }

            do {
                let result = try await FoodVisionService.shared.recognizeFood(imageData: jpeg)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if result.foodDetected && !result.items.isEmpty {
                        phase = .review(resized, result)
                    } else {
                        phase = .noFood(resized)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    phase = .error(resized, error.localizedDescription)
                }
            }
        }
    }
}
