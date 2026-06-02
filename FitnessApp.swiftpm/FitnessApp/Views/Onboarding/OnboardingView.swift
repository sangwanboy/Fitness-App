import SwiftUI

/// First-launch onboarding container. Five screens, gated by
/// `@AppStorage("is_onboarded")`. Showing this view is owned by `ContentView`
/// (it renders OnboardingView when `is_onboarded` is false). Each child screen
/// owns its own Continue/Skip buttons and calls back into this container's
/// `advance` / `finish` helpers — page-by-page state rather than swipeable
/// TabView so the flow stays linear and back-navigable without surprises.
public struct OnboardingView: View {
    @AppStorage("is_onboarded") private var isOnboarded = false
    @AppStorage("account_created_date") private var accountCreatedDate: Double = 0
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var page: Int = 0
    private let totalPages = 5

    public init() {}

    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public var body: some View {
        ZStack {
            AdaptiveBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                ZStack {
                    switch page {
                    case 0: WelcomeScreen(onContinue: advance)
                    case 1: AboutYouScreen(onContinue: advance, onBack: back)
                    case 2: ConnectScreen(onContinue: advance, onBack: back)
                    case 3: GoalsScreen(onContinue: advance, onBack: back)
                    default: MeetAstraScreen(onFinish: finish, onBack: back)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)
                .animation(.easeInOut(duration: 0.28), value: page)

                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == page ? accentColor : Color.white.opacity(0.18))
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)
            }
        }
    }

    private func advance() {
        guard page < totalPages - 1 else { finish(); return }
        page += 1
    }

    private func back() {
        guard page > 0 else { return }
        page -= 1
    }

    private func finish() {
        if accountCreatedDate == 0 {
            accountCreatedDate = Date().timeIntervalSince1970
        }
        // Mark onboarding done so ContentView swaps to the main TabView.
        withAnimation(.easeInOut(duration: 0.35)) {
            isOnboarded = true
        }
    }
}
