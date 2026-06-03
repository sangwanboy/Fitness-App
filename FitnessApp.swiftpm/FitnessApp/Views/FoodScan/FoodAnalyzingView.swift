import SwiftUI

struct FoodAnalyzingView: View {
    let image: UIImage
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var shimmerPhase: CGFloat = -1
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo background (top portion)
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.55)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            // Bottom card slides up
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.orange)
                        .scaleEffect(1.2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(elapsed > 6 ? "Taking a little longer than usual…" : "Analyzing your meal…")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isDark ? .white : .black)
                            .animation(.easeInOut, value: elapsed > 6)

                        Text("Identifying ingredients and estimating nutrition")
                            .font(.system(size: 13))
                            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    }
                }

                // Three shimmer placeholder rows
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        shimmerRow(width: i == 0 ? 0.8 : i == 1 ? 0.65 : 0.5)
                    }
                }

                Button("Cancel") { onCancel() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
            .background(
                (isDark ? Color.black : Color(red: 0.97, green: 0.97, blue: 0.97))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
            )
            .padding(.horizontal, 0)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
            // Elapsed timer to show "taking longer" message after 6s
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsed += 1
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func shimmerRow(width: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            (isDark ? Color.white : Color.black).opacity(0.06),
                            (isDark ? Color.white : Color.black).opacity(0.14),
                            (isDark ? Color.white : Color.black).opacity(0.06)
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.5, y: 0),
                        endPoint: UnitPoint(x: shimmerPhase + 0.5, y: 0)
                    )
                )
                .frame(width: geo.size.width * width, height: 14)
        }
        .frame(height: 14)
    }
}
