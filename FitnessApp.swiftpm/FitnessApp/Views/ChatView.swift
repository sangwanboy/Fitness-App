import SwiftUI
import Charts
import PhotosUI

public struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @ObservedObject private var prefillBus = ChatPrefillBus.shared
    @State private var inputText: String = ""
    @State private var showClearAlert = false
    @FocusState private var isInputFocused: Bool

    // Camera/photo picker state
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var pendingImagePreview: UIImage?
    @State private var showImageSourceDialog = false
    @State private var showCameraSheet = false
    @State private var showLibraryPicker = false
    @State private var cameraImage: UIImage?
    
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("glass_strength") private var glassStrength = "moderate"
    @AppStorage("thinking_level") private var thinkingLevel = "medium"
    
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    
    private let suggestionChips = [
        "How was my sleep?",
        "Plan tomorrow",
        "Why am I tired?",
        "Suggest a workout"
    ]
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(
                                message: message,
                                accentColor: accentColor,
                                isDark: isDark,
                                onConfirmTool: { id in Task { await viewModel.confirmToolCall(messageId: id) } },
                                onCancelTool:  { id in viewModel.cancelToolCall(messageId: id) },
                                onRetry:       { Task { await viewModel.retryLast() } }
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        if viewModel.isGenerating {
                            TypingIndicatorView().id("typing_indicator")
                        }
                        Color.clear.frame(height: 12).id("bottom_anchor")
                    }
                    .padding(.horizontal, 20)
                    // Clearance for the floating overlay. When the keyboard is
                    // up, only the composer (~90pt) sits above it. When unfocused
                    // both the suggestion chips bar AND the composer overlay the
                    // scroll — combined ~160pt. Earlier 100pt was occluding the
                    // tail of every model reply after a tool confirm.
                    .padding(.bottom, isInputFocused ? 90 : 160)
                }
                .scrollContentBackground(.hidden)
                .background(AdaptiveBackground())
                .onChange(of: viewModel.messages.count) { _ in scrollToBottom(proxy: proxy) }
                .onChange(of: viewModel.isGenerating) { _ in scrollToBottom(proxy: proxy) }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                    consumePrefillIfAny()
                    consumeComposerSeedIfAny()
                }
                .onChange(of: prefillBus.pendingPrompt) { _ in
                    consumePrefillIfAny()
                }
                .onChange(of: prefillBus.composerSeed) { _ in
                    consumeComposerSeedIfAny()
                }
            }
            
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    if !viewModel.isGenerating {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestionChips, id: \.self) { chip in
                                    Button(action: { sendPrompt(chip) }) {
                                        Text(chip)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(isDark ? .white : .black)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Composer — native TextField wrapped in Apple Liquid Glass.
                    // Mic was swapped for a camera button so users can upload food/fitness photos.
                    VStack(spacing: 8) {
                        if let preview = pendingImagePreview {
                            HStack(spacing: 8) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text("Photo attached — ask anything")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    pendingImagePreview = nil
                                    pendingImageData = nil
                                    photoItem = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }

                        HStack(alignment: .bottom, spacing: 12) {
                            Button { showImageSourceDialog = true } label: {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(accentColor)
                                    .frame(width: 32, height: 32)
                            }
                            .disabled(viewModel.isGenerating)
                            .opacity(viewModel.isGenerating ? 0.4 : 1)

                            TextField(pendingImageData == nil ? "Ask about your health…" : "Add a note (optional)…",
                                      text: $inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .lineLimit(1...5)
                                .focused($isInputFocused)
                                .tint(accentColor)
                                .submitLabel(.send)
                                .onSubmit { if !viewModel.isGenerating { sendPrompt(inputText) } }
                                .disabled(viewModel.isGenerating)
                                .padding(.vertical, 4)  // align baseline w/ 32pt buttons

                            // Send / progress button — visually reflects the lock state:
                            //   • generating     → small spinner, faded, disabled
                            //   • empty input    → gray arrow, disabled
                            //   • ready          → accent-colored arrow, enabled
                            Button(action: { sendPrompt(inputText) }) {
                                ZStack {
                                    if viewModel.isGenerating {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .controlSize(.small)
                                            .tint(.secondary)
                                    } else {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(canSend ? accentColor : Color.secondary)
                                    }
                                }
                                .frame(width: 32, height: 32)
                            }
                            .disabled(!canSend || viewModel.isGenerating)
                            .opacity(viewModel.isGenerating ? 0.5 : 1)
                            .animation(.easeInOut(duration: 0.15), value: viewModel.isGenerating)
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isInputFocused ? 10 : 20)
                    .animation(.easeOut(duration: 0.25), value: isInputFocused)
                }
            }
        }
        .navigationTitle("Coach")
        .navigationSubtitle("AI · Always learning your body")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Thinking Level", selection: $thinkingLevel) {
                        Text("Minimal").tag("minimal")
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                } label: {
                    Image(systemName: "brain")
                        .foregroundStyle(accentColor)
                }

                Button(action: { showClearAlert = true }) {
                    Image(systemName: "trash")
                }
            }
        }
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    stageImage(ui)
                }
            }
        }
        .onChange(of: cameraImage) { newImage in
            if let newImage { stageImage(newImage); cameraImage = nil }
        }
        .confirmationDialog("Add a photo", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") { showCameraSheet = true }
            Button("Choose from Library") { showLibraryPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraSheet) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $photoItem, matching: .images, photoLibrary: .shared())
        .alert("Clear Chat?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                withAnimation { viewModel.clearChat() }
            }
        } message: {
            Text("This will erase all messages in the current session.")
        }
    }
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty || pendingImageData != nil
    }

    /// Common pipeline for both camera- and library-sourced images:
    /// downscale to ≤1200px, JPEG q=0.7, stage as the next outgoing attachment.
    private func stageImage(_ ui: UIImage) {
        let resized = ui.resizedForUpload(maxDimension: 1200)
        pendingImageData = resized.jpegData(compressionQuality: 0.7)
        pendingImagePreview = resized
    }

    private func sendPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImageData
        guard !trimmed.isEmpty || img != nil else { return }
        inputText = ""
        pendingImageData = nil
        pendingImagePreview = nil
        photoItem = nil
        isInputFocused = false
        Task { await viewModel.sendMessage(trimmed, imageData: img) }
    }

    /// Pull any prompt queued by a Predictions card action chip and auto-fire it.
    /// Bus is cleared atomically so SwiftUI re-renders don't double-send.
    private func consumePrefillIfAny() {
        guard let prompt = prefillBus.consume() else { return }
        Task { await viewModel.sendPrefilledPrompt(prompt) }
    }

    /// Pull any composer seed queued by "Continue in Coach". Pre-fills the
    /// text field and focuses it — user reviews + edits + sends manually.
    private func consumeComposerSeedIfAny() {
        guard let seed = prefillBus.consumeComposerSeed() else { return }
        inputText = seed
        // Small delay so the tab transition animation finishes before the
        // keyboard slides up — otherwise the composer can jitter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isInputFocused = true
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            proxy.scrollTo("bottom_anchor", anchor: .bottom)
        }
    }
}

// MARK: - Chat Message Row
struct ChatMessageRow: View {
    let message: ChatMessage
    let accentColor: Color
    let isDark: Bool
    var onConfirmTool: (UUID) -> Void = { _ in }
    var onCancelTool:  (UUID) -> Void = { _ in }
    var onRetry: () -> Void = {}

    var isUser: Bool { message.role == .user }

    /// Parse the LLM's markdown (bold/italic/code/lists/links) into an AttributedString
    /// so it renders with proper styling instead of showing raw `**asterisks**`.
    private var renderedAttributedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: message.text, options: options) {
            return attr
        }
        return AttributedString(message.text)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 48) }
                
                // Bubble Content
                VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                    // Show user's attached image inside their bubble
                    if isUser, let data = message.imageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if !message.text.isEmpty {
                        StructuredMarkdownText(
                            text: message.text,
                            isDark: isDark,
                            accentColor: isUser ? .white : accentColor,
                            bubbleColor: isUser ? .white : nil
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if isUser {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [accentColor, Color.purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.clear)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                                }
                            }
                        )
                    } // end if !message.text.isEmpty

                    // Astra's tool call lands here as an interactive card.
                    // Legacy keyword-matched cards (Sleep / Workout / HR / Food regex) are
                    // gone — they showed hardcoded fake data and have been fully replaced
                    // by the function-calling tool system.
                    if !isUser, let call = message.toolCall {
                        ToolCallCard(
                            messageId: message.id,
                            call: call,
                            status: message.toolStatus ?? .pending,
                            accentColor: accentColor,
                            onConfirm: { onConfirmTool(message.id) },
                            onCancel:  { onCancelTool(message.id) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Retry button on error bubbles re-fires the last
                    // sendMessage / sendFollowup via viewModel.retryLast().
                    if !isUser && message.isError {
                        Button(action: onRetry) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Token counter — visible only on completed model bubbles.
                    // Renders below the text/tool card; tappable for the full
                    // breakdown is a future polish (kept inline + compact here).
                    if !isUser, let usage = message.tokenUsage {
                        TokenUsageChip(usage: usage, isDark: isDark)
                            .padding(.top, 2)
                    }
                }
                
                if !isUser { Spacer(minLength: 48) }
            }
        }
    }
}

/// Tiny per-message token counter shown under completed model bubbles.
/// Displays `thoughts → output → total` so the user can see how much
/// reasoning the model spent vs how much surfaced as text.
struct TokenUsageChip: View {
    let usage: TokenUsage
    let isDark: Bool

    private func short(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1fk", Double(n) / 1000) }
        if n >= 1_000  { return String(format: "%.2fk", Double(n) / 1000) }
        return String(n)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 9, weight: .semibold))
            Text("\(short(usage.thoughts))")
            dot
            Image(systemName: "text.alignleft")
                .font(.system(size: 9, weight: .semibold))
            Text("\(short(usage.output))")
            dot
            Text("Σ \(short(usage.total))")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
        )
        .accessibilityLabel("Token usage: \(usage.thoughts) thinking, \(usage.output) output, \(usage.total) total")
    }

    private var dot: some View {
        Circle()
            .fill(isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.25))
            .frame(width: 2, height: 2)
    }
}

// Resize helper used by the camera picker to keep upload payloads small.
extension UIImage {
    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var dot1Scale: CGFloat = 0.5
    @State private var dot2Scale: CGFloat = 0.5
    @State private var dot3Scale: CGFloat = 0.5
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotScale(for: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

            Spacer(minLength: 40)
        }
        .onAppear { animateDots() }
    }
    
    private func dotScale(for index: Int) -> CGFloat {
        switch index {
        case 0: return dot1Scale
        case 1: return dot2Scale
        case 2: return dot3Scale
        default: return 0.5
        }
    }
    
    private func animateDots() {
        let animation = Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        withAnimation(animation.delay(0)) { dot1Scale = 1.0 }
        withAnimation(animation.delay(0.2)) { dot2Scale = 1.0 }
        withAnimation(animation.delay(0.4)) { dot3Scale = 1.0 }
    }
}
