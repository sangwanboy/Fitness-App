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
        case review(UIImage, FoodRecognitionResult)
        case error(UIImage?, String)
        case noFood(UIImage?)
    }

    @State private var phase: ScanPhase = .camera
    @State private var analyzeTask: Task<Void, Never>? = nil

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
                        onCancel: { analyzeTask?.cancel(); dismiss() }
                    )

                case .analyzing(let image):
                    FoodAnalyzingView(image: image) {
                        analyzeTask?.cancel()
                        analyzeTask = nil
                        phase = .camera
                    }

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

    // MARK: - Image processing + API call

    private func handlePickedImage(_ raw: UIImage) {
        // Downscale to ≤1200px JPEG q=0.7 — same pipeline as ChatView.stageImage
        let resized = raw.resizedForUpload(maxDimension: 1200)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return }

        phase = .analyzing(resized)

        analyzeTask = Task {
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
