import SwiftUI

// Cleaner iOS 26 loading: a native ProgressView sitting in a Liquid Glass capsule,
// dimmed background, "Syncing Health Data…" caption with a subtle breathing effect.
public struct GlassLoaderOverlay: View {
    @State private var breathe = false

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            HStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.regular)
                    .tint(.white)

                Text("Syncing health data…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(breathe ? 0.7 : 1.0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: .capsule)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathe.toggle()
                }
            }
        }
        .transition(.opacity)
    }
}

// Shimmer placeholder for metric cards while HealthKit data is loading.
public struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = -1

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.white.opacity(0.06))
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: geo.size.width * phase)
                .mask(RoundedRectangle(cornerRadius: 22))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}
