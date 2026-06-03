import SwiftUI
import PhotosUI

// MARK: - Entry point presented by Agent 3 as .sheet(isPresented:) { FoodScanView() }

public struct FoodScanView: View {
    public init() {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    // State machine
    private enum ScanPhase {
        case camera                          // show camera / photo picker UI
        case analyzing(UIImage)              // show FoodAnalyzingView
        case review(UIImage, FoodRecognitionResult)  // show FoodReviewSheet
        case error(UIImage?, String)         // error card
        case noFood(UIImage?)                // no food detected card
    }

    @State private var phase: ScanPhase = .camera
    @State private var showCameraSheet = false
    @State private var showLibraryPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var analyzeTask: Task<Void, Never>? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                (isDark ? Color.black : Color(red: 0.97, green: 0.97, blue: 0.97))
                    .ignoresSafeArea()

                switch phase {
                case .camera:
                    cameraEntryView

                case .analyzing(let image):
                    FoodAnalyzingView(image: image) {
                        // Cancel tapped
                        analyzeTask?.cancel()
                        analyzeTask = nil
                        phase = .camera
                    }

                case .review(let image, let result):
                    FoodReviewSheet(image: image, result: result) {
                        // After successful log, dismiss the whole sheet
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
            .navigationTitle("Scan Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        analyzeTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        // Camera sheet — reuses existing CameraImagePicker component
        .fullScreenCover(isPresented: $showCameraSheet) {
            CameraImagePicker(image: Binding(
                get: { nil },
                set: { img in
                    showCameraSheet = false
                    if let img { handlePickedImage(img) }
                }
            ))
            .ignoresSafeArea()
        }
        // Photo library picker
        .photosPicker(isPresented: $showLibraryPicker,
                      selection: $photoItem,
                      matching: .images,
                      photoLibrary: .shared())
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                handlePickedImage(img)
                photoItem = nil
            }
        }
    }

    // MARK: - Camera entry view (phase == .camera)

    private var cameraEntryView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon + instruction
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, .pink],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("Photograph your meal")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)

                Text("For best results: shoot from ~45°, include a fork for scale, keep it well-lit.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Primary action buttons
            VStack(spacing: 14) {
                Button {
                    showCameraSheet = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [.orange, .pink],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button {
                    showLibraryPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
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

        // Transition immediately to analyzing state with the resized preview
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
