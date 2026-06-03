import SwiftUI

public struct ContentView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @ObservedObject private var prefillBus = ChatPrefillBus.shared

    @AppStorage("is_onboarded") private var isOnboarded = false
    @AppStorage("is_logged_in") private var isLoggedIn = true
    @AppStorage("theme_mode") private var themeMode = "dark"

    @State private var selectedTab: String = "home"
    @State private var activeModal: String? = nil
    @State private var didFinishInitialLoad = false

    @Environment(\.scenePhase) private var scenePhase
    /// Polls HealthKit every 15s while the app is on-screen. Silent — fetchTodayData
    /// no longer toggles any loading overlay, so this never shows a spinner.
    private let healthSyncTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var isDark: Bool { themeMode == "dark" }

    public init() {}

    public var body: some View {
        ZStack {
            if !isOnboarded {
                OnboardingView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !isLoggedIn {
                LoginView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // iOS 26 native TabView — auto-applies Liquid Glass to the tab bar
                TabView(selection: $selectedTab) {
                    Tab("Home", systemImage: "house.fill", value: "home") {
                        NavigationStack {
                            DashboardView(
                                onOpenWorkout: {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        activeModal = "workout"
                                    }
                                },
                                onOpenCalendar: {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        activeModal = "calendar"
                                    }
                                },
                                onOpenSleepMode: {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        activeModal = "sleep"
                                    }
                                },
                                switchToTab: { tab in selectedTab = tab }
                            )
                        }
                    }

                    Tab("Coach", systemImage: "brain.head.profile", value: "chat") {
                        NavigationStack { ChatView() }
                    }

                    Tab("Reminders", systemImage: "bell.fill", value: "reminders") {
                        NavigationStack { RemindersView() }
                    }

                    Tab("Progress", systemImage: "chart.bar.fill", value: "progress") {
                        NavigationStack { ProgressHubView() }
                    }

                    Tab("Profile", systemImage: "person.fill", value: "profile") {
                        NavigationStack { SettingsView() }
                    }
                }

                if activeModal == "workout" {
                    WorkoutTrackerView(onBack: {
                        withAnimation { activeModal = nil }
                    })
                    .transition(.move(edge: .bottom))
                    .zIndex(50)
                } else if activeModal == "sleep" {
                    SleepModeView(onClose: {
                        withAnimation { activeModal = nil }
                    })
                    .transition(.move(edge: .bottom))
                    .zIndex(50)
                } else if activeModal == "calendar" {
                    CalendarView(onBack: {
                        withAnimation { activeModal = nil }
                    }, onOpenWorkout: {
                        withAnimation { activeModal = "workout" }
                    }, onOpenChat: {
                        withAnimation { activeModal = nil }
                        ChatPrefillBus.shared.queueComposerSeed("Plan my day — add some events to my calendar")
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedTab = "chat"
                        }
                    })
                    .transition(.move(edge: .bottom))
                    .zIndex(50)
                }
            }

            if !didFinishInitialLoad {
                AppLoadingScreen()
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .onChange(of: prefillBus.pendingPrompt) { newValue in
            // A prediction-card action chip or Why-sheet quick action queued a
            // prompt. If the user isn't on Coach, switch — ChatView's onAppear
            // observer will then consume the bus and auto-send.
            if newValue != nil && selectedTab != "chat" {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedTab = "chat"
                }
            }
        }
        .onChange(of: prefillBus.composerSeed) { newValue in
            // Why-sheet "Continue in Coach" — pre-fill composer (no auto-send).
            // Also need to switch tabs so ChatView's onAppear consumes the seed.
            if newValue != nil && selectedTab != "chat" {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedTab = "chat"
                }
            }
        }
        .task {
            let launchedAt = Date()

            // Skip HK / EK auth and data fetches while onboarding is showing —
            // its Connect screen owns the prompts.
            if isOnboarded {
                // Only ask HK on the very first post-onboarding launch; otherwise just fetch data.
                // Re-asking every launch can briefly flash the system consent sheet.
                if !UserDefaults.standard.bool(forKey: "hk_requested_once") {
                    _ = await healthKitManager.requestAuthorization()
                    UserDefaults.standard.set(true, forKey: "hk_requested_once")
                }
                // Sync health data once on open (silent — no overlay).
                await healthKitManager.fetchTodayData()
                await EventKitManager.shared.requestAccess()
                if EventKitManager.shared.remindersGranted {
                    await EventKitManager.shared.fetchReminders()
                }
                // One-shot: stamp `account_created_date` for upgraders who never
                // saw onboarding. Earliest non-empty HK history sample is the best
                // approximation; fall back to today if no history exists.
                if UserDefaults.standard.double(forKey: "account_created_date") == 0 {
                    let stamp = healthKitManager.earliestHistoryDate() ?? Date()
                    UserDefaults.standard.set(stamp.timeIntervalSince1970, forKey: "account_created_date")
                }
            }

            // Minimum brand-moment hold so the animation always reads, even when
            // data is already cached and the fetches resolve instantly.
            let minHold: TimeInterval = 1.7
            let elapsed = Date().timeIntervalSince(launchedAt)
            if elapsed < minHold {
                try? await Task.sleep(nanoseconds: UInt64((minHold - elapsed) * 1_000_000_000))
            }
            withAnimation(.easeOut(duration: 0.55)) {
                didFinishInitialLoad = true
            }
        }
        // Periodic silent health-data sync every 15s while the app is on-screen.
        .onReceive(healthSyncTimer) { _ in
            guard isOnboarded, isLoggedIn, didFinishInitialLoad, scenePhase == .active else { return }
            Task { await healthKitManager.fetchTodayData() }
        }
        // Also sync the moment the app returns to the foreground.
        .onChange(of: scenePhase) { phase in
            guard phase == .active, isOnboarded, isLoggedIn, didFinishInitialLoad else { return }
            Task { await healthKitManager.fetchTodayData() }
        }
    }
}
