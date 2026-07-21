import SwiftUI

/// First-launch onboarding container. Seven screens, gated by
/// `@AppStorage("is_onboarded")`. Showing this view is owned by `ContentView`
/// (it renders OnboardingView when `is_onboarded` is false). Each child screen
/// owns its own Continue/Skip buttons and calls back into this container's
/// `advance` / `finish` helpers — page-by-page state rather than swipeable
/// TabView so the flow stays linear and back-navigable without surprises.
///
/// Flow: Welcome → Sign In (real Sign in with Apple, or "Continue without AI
/// coach") → About You → Connect Health → Goals & Coach → Notifications →
/// Meet Astra. Sign In sets `is_logged_in` mid-flow, so by the time `finish()`
/// flips `is_onboarded`, ContentView lands straight on the main TabView
/// instead of showing LoginView again.
public struct OnboardingView: View {
    @AppStorage("is_onboarded") private var isOnboarded = false
    @AppStorage("account_created_date") private var accountCreatedDate: Double = 0
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var page: Int = 0
    private let totalPages = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    case 1: SignInScreen(onContinue: advance, onBack: back)
                    case 2: AboutYouScreen(onContinue: advance, onBack: back)
                    case 3: ConnectScreen(onContinue: advance, onBack: back)
                    case 4: GoalsScreen(onContinue: advance, onBack: back)
                    case 5: NotificationsScreen(onContinue: advance, onBack: back)
                    default: MeetAstraScreen(onFinish: finish, onBack: back)
                    }
                }
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: page)

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
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: page)
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
        // Mark onboarding done so ContentView swaps to the main TabView. Any
        // starter-question prompt queued by MeetAstraScreen (ChatPrefillBus)
        // was set before this call, so ContentView's own bus observer already
        // switched `selectedTab` to "chat" by the time TabView renders.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            isOnboarded = true
        }
    }
}
