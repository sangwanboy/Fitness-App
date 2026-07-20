import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    // Matches the corrected default in ContentView/LoginView; SettingsView
    // only ever renders once isLoggedIn is already true, so this default is
    // never actually read, but it should say the same thing everywhere.
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("athlete_name") private var athleteName = "Alex Rivera"
    @AppStorage("glass_tint_color") private var glassTintColorHex = "#FFFFFF"
    @AppStorage("glass_tint_strength") private var glassTintStrength = 0.0

    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var isRequestingClinical = false
    @State private var showTokenUsage = false
    @ObservedObject private var tokenMeter = TokenMeter.shared

    // Sub-sheet state for previously dead rows
    @State private var showEditProfile = false
    @State private var showCoachPersonalitySheet = false
    @State private var showTrainingGoalsSheet = false
    @State private var showDailyGoalsSheet = false
    @AppStorage("coach_personality") private var coachPersonality: String = "Direct"
    @AppStorage("training_goals")    private var trainingGoals: String = "Endurance + strength"
    @AppStorage("account_created_date") private var accountCreatedDate: Double = 0
    @AppStorage("is_onboarded")       private var isOnboarded = true

    // Astra AI backend (gateway) state
    @AppStorage(GatewayConfig.baseURLDefaultsKey) private var gatewayBaseURLOverride: String = ""
    /// Gateway user id of the stored session; nil = signed out. Refreshed
    /// on appear and after every sign-in/out so the UI shows the real state.
    @State private var gatewaySessionUserId: String?
    @State private var isGatewayAuthWorking = false
    @State private var gatewayAuthError: String?
    @State private var gatewayTest: GatewayTestState = .idle
    @State private var showFeedbackSheet = false

    enum GatewayTestState: Equatable {
        case idle
        case testing
        case ok
        case failed(String)
    }

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    /// "Joined Mar 2025 · 14-day step streak". The joined date is read from
    /// AppStorage if set, else from HealthKit history (backfill for upgraders),
    /// else today's date. Streak is real consecutive step-goal days (distinct
    /// from the weekly activity streak shown on all other surfaces).
    private var joinedAndStreakLine: String {
        let joinedDate: Date = {
            if accountCreatedDate > 0 {
                return Date(timeIntervalSince1970: accountCreatedDate)
            }
            return healthKitManager.earliestHistoryDate() ?? Date()
        }()
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        let streak = healthKitManager.dayStreak()
        // Label explicitly says "step streak" so it is not confused with the
        // weekly activity streak shown in StreakCard / ProgressHub / Calendar.
        let streakLabel = streak == 1 ? "1-day step streak" : "\(streak)-day step streak"
        return "Joined \(f.string(from: joinedDate)) · \(streakLabel)"
    }

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                avatarHeader
                statRow
                connectedSection
                coachSection
                AstraProfileSection()
                NotificationSettingsSection()
                healthRecordsSection
                gatewaySection
                appearanceSection
                accountSection
                versionFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveBackground())
        .navigationTitle("Profile")
        .navigationSubtitle("Account & integrations")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Profile", systemImage: "person.crop.circle") { showEditProfile = true }
                    Button("Apple Health", systemImage: "heart.fill") { ExternalLink.openHealth() }
                    Button("iOS Settings", systemImage: "gearshape.fill") { ExternalLink.openAppSettings() }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
        .sheet(isPresented: $showCoachPersonalitySheet) {
            PickOneSheet(title: "Coach personality",
                         options: ["Direct", "Friendly", "Concise", "Motivational"],
                         selection: $coachPersonality)
        }
        .sheet(isPresented: $showTrainingGoalsSheet) {
            PickMultipleSheet(title: "Training goals",
                              options: ["Endurance", "Strength", "Weight loss",
                                        "Sleep better", "Stay active", "Flexibility"],
                              selection: $trainingGoals)
        }
        .sheet(isPresented: $showDailyGoalsSheet) {
            GoalsEditorSheet()
        }
        .sheet(isPresented: $showTokenUsage) {
            TokenUsageView()
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackSheet()
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                withAnimation { isLoggedIn = false }
            }
        } message: {
            Text("You'll need to sign back in to access your data.")
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Astra AI account, sessions, and usage records from our servers. Health data in Apple Health is untouched. This cannot be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK") { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .onAppear {
            glassTintColorHex = "#FFFFFF"
        }
        .task {
            gatewaySessionUserId = await GatewayAuth.shared.currentUserId
        }
    }

    // MARK: - Avatar Header
    private var avatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: accentColor.opacity(0.35), radius: 16, x: 0, y: 12)

                Text(avatarInitials())
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(-1.2)
            }

            VStack(spacing: 2) {
                Text(athleteName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .tracking(-0.6)
                Text(joinedAndStreakLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }

            // Real gateway session state — no fake badges.
            HStack(spacing: 6) {
                Image(systemName: gatewaySessionUserId != nil
                      ? "checkmark.seal.fill"
                      : "person.crop.circle.badge.xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(gatewaySessionUserId != nil
                                     ? .green
                                     : (isDark ? .white.opacity(0.55) : .black.opacity(0.55)))
                Text(gatewaySessionUserId != nil
                     ? "Astra session active"
                     : "Not signed in to Astra AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Stat Tiles Row
    private var statRow: some View {
        HStack(spacing: 10) {
            ProfileStatTile(value: "\(healthKitManager.dayStreak())", label: "Daily step streak", color: .orange)
            ProfileStatTile(
                value: {
                    let v = healthKitManager.metricSummaries[.heartRate]?.currentValue ?? 0
                    return v > 0 ? String(format: "%.0f", v) : "—"
                }(),
                label: "Resting HR",
                color: .red
            )
            ProfileStatTile(
                value: {
                    let v = healthKitManager.metricSummaries[.hrv]?.currentValue ?? 0
                    return v > 0 ? String(format: "%.0f", v) : "—"
                }(),
                label: "Recovery",
                color: accentColor
            )
        }
    }

    // MARK: - Connected Section
    private var connectedSection: some View {
        ProfileListGroup(header: "Connected") {
            ProfileListRow(icon: "heart.fill", iconColor: .red, title: "Apple Health", detail: "Open Health",
                           action: { ExternalLink.openHealth() })
            ProfileListDivider()
            ProfileListRow(icon: "applewatch", iconColor: isDark ? .white : .black, title: "Apple Watch", detail: "Pair in Settings",
                           action: { ExternalLink.openAppSettings() })
            ProfileListDivider()
            ProfileListRow(icon: "calendar", iconColor: .blue, title: "Calendar", detail: "Open Calendar",
                           action: { ExternalLink.openCalendar() })
            ProfileListDivider()
            ProfileListRow(icon: "bell.fill", iconColor: .orange, title: "Reminders", detail: "Open Reminders",
                           action: { ExternalLink.openReminders() })
        }
    }

    // MARK: - AI Coach Section
    private var coachSection: some View {
        ProfileListGroup(header: "AI Coach") {
            ProfileListRow(icon: "sparkles", iconColor: accentColor, title: "Coach personality", detail: coachPersonality,
                           action: { showCoachPersonalitySheet = true })
            ProfileListDivider()
            ProfileListRow(icon: "shield.lefthalf.filled", iconColor: .green, title: "Data permissions", detail: "Health, Calendar",
                           action: { ExternalLink.openAppSettings() })
            ProfileListDivider()
            ProfileListRow(icon: "target", iconColor: .purple, title: "Training goals", detail: trainingGoals,
                           action: { showTrainingGoalsSheet = true })
            ProfileListDivider()
            ProfileListRow(icon: "scope", iconColor: .indigo, title: "Daily goals", detail: dailyGoalsSummary,
                           action: { showDailyGoalsSheet = true })
            ProfileListDivider()
            ProfileListRow(icon: "number", iconColor: .teal, title: "AI token usage", detail: tokenUsageSummary,
                           action: { showTokenUsage = true })
        }
    }

    /// Compact lifetime Gemini token total + estimated cost for the row detail.
    private var tokenUsageSummary: String {
        tokenMeter.total == 0
            ? "No usage yet"
            : "\(TokenFormat.compact(tokenMeter.total)) · \(GeminiPricing.formatUSD(tokenMeter.totalCost))"
    }

    /// One-line summary for the Daily goals row — shows the user's three most
    /// behavioral targets so they see at-a-glance what's set without opening
    /// the editor.
    private var dailyGoalsSummary: String {
        let steps = Int(HealthKitManager.userGoal(for: .steps))
        let cals = Int(HealthKitManager.userGoal(for: .activeEnergy))
        let sleep = HealthKitManager.userGoal(for: .sleep)
        return "\(steps) steps · \(cals) kcal · \(String(format: "%.1f", sleep)) h"
    }

    // MARK: - Appearance Section (tint slider)
    private var appearanceSection: some View {
        ProfileListGroup(header: "Appearance") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tint strength")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isDark ? .white : .black)
                    Spacer()
                    Text("\(Int(glassTintStrength))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: glassTintStrength)
                }
                Slider(value: $glassTintStrength, in: 0...100, step: 5)
                    .tint(accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Account Section
    private var accountSection: some View {
        ProfileListGroup(header: "Account") {
            ProfileListRow(icon: "person.fill", iconColor: .blue, title: "Personal details",
                           action: { showEditProfile = true })
            ProfileListDivider()
            ProfileListRow(icon: "bell.fill", iconColor: .orange, title: "Notifications",
                           action: { ExternalLink.openAppSettings() })
            ProfileListDivider()
            ProfileListRow(icon: "lock.fill", iconColor: .green, title: "Privacy",
                           action: { ExternalLink.openAppSettings() })
            ProfileListDivider()
            ProfileListRow(icon: "arrow.uturn.left.circle", iconColor: .gray,
                           title: "Run setup again",
                           action: { withAnimation { isOnboarded = false } })
            ProfileListDivider()
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSignOutConfirm = true
            }) {
                HStack {
                    Text("Sign out")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())

            // Guideline 5.1.1(v) — only offered while an Astra session exists,
            // since deletion targets the gateway account.
            if gatewaySessionUserId != nil {
                ProfileListDivider()
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showDeleteAccountConfirm = true
                }) {
                    HStack {
                        Text(isDeletingAccount ? "Deleting account…" : "Delete account")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                        if isDeletingAccount {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isDeletingAccount)
            }
        }
    }

    /// Deletes the gateway account (`GatewayAuth.deleteAccount()`), then
    /// clears local account state and flips the login gate so the user lands
    /// back on LoginView. On failure (e.g. the endpoint isn't deployed yet)
    /// shows the honest `GatewayError.userMessage` and leaves the session
    /// alone — deletion is all-or-nothing.
    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil
        do {
            try await GatewayAuth.shared.deleteAccount()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            accountCreatedDate = 0
            withAnimation { isLoggedIn = false }
        } catch {
            deleteAccountError = (error as? GatewayError)?.userMessage ?? error.localizedDescription
        }
        gatewaySessionUserId = await GatewayAuth.shared.currentUserId
        if gatewaySessionUserId == nil, isLoggedIn {
            // The session died during the attempt (e.g. dead refresh token
            // wiped it) — route back to LoginView rather than stranding a
            // logged-in-but-sessionless UI.
            accountCreatedDate = 0
            withAnimation { isLoggedIn = false }
        }
        isDeletingAccount = false
    }

    // MARK: - Health Records (clinical) opt-in
    private var healthRecordsSection: some View {
        ProfileListGroup(header: "Health Records") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clinical records")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isDark ? .white : .black)
                        Text(HealthKitManager.shared.clinicalRecordsRequested ? "Authorization requested" : "Off — link providers in Apple Health first")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    }
                    Spacer()
                    if isRequestingClinical {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Connect") {
                            Task {
                                isRequestingClinical = true
                                _ = await HealthKitManager.shared.requestClinicalRecordsAuthorization()
                                isRequestingClinical = false
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                    }
                }

                Text("Apple Health Records is available in the United States, United Kingdom, Canada, and select EU countries. You'll need a linked provider account in the Health app first. If your region or provider isn't supported, Apple will silently decline.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Astra AI backend (gateway) section
    private var gatewaySection: some View {
        ProfileListGroup(header: "Astra AI backend") {
            VStack(alignment: .leading, spacing: 12) {
                // Session status row — real state, never a fake badge.
                HStack(spacing: 8) {
                    Image(systemName: gatewaySessionUserId != nil
                          ? "checkmark.circle.fill" : "person.crop.circle.badge.xmark")
                        .foregroundColor(gatewaySessionUserId != nil ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(sessionStatusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    if isGatewayAuthWorking {
                        ProgressView().controlSize(.small)
                    } else if gatewaySessionUserId != nil {
                        Button("Sign out") {
                            Task {
                                isGatewayAuthWorking = true
                                await GatewayAuth.shared.signOut()
                                gatewaySessionUserId = await GatewayAuth.shared.currentUserId
                                gatewayAuthError = nil
                                isGatewayAuthWorking = false
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                    } else {
                        #if DEBUG
                        // Fake dev-auth only exists on a local gateway started
                        // with ALLOW_FAKE_APPLE — against prod it can only 401,
                        // so hide it there (LoginView does real SIWA instead).
                        if GatewayConfig.isLocalGateway {
                        Button("Sign in (dev)") {
                            Task {
                                isGatewayAuthWorking = true
                                do {
                                    try await GatewayAuth.shared.signInDev()
                                    gatewayAuthError = nil
                                } catch {
                                    gatewayAuthError = (error as? GatewayError)?.userMessage
                                        ?? error.localizedDescription
                                }
                                gatewaySessionUserId = await GatewayAuth.shared.currentUserId
                                isGatewayAuthWorking = false
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        }
                        #endif
                    }
                }

                if let authError = gatewayAuthError {
                    Text(authError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                #if !DEBUG
                if gatewaySessionUserId == nil {
                    Text("Sign in with Apple from the welcome screen (Account → Sign out brings you there).")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif

                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(height: 0.5)

                // Base URL override + connection test.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gateway URL")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))

                    TextField("http://10.130.154.45:8787", text: $gatewayBaseURLOverride)
                        .font(.system(size: 12, design: .monospaced))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        .onChange(of: gatewayBaseURLOverride) { _, _ in
                            gatewayTest = .idle
                        }

                    HStack(spacing: 8) {
                        Text("Using: \(GatewayConfig.baseURL?.absoluteString ?? "not configured")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        switch gatewayTest {
                        case .testing:
                            ProgressView().controlSize(.small)
                        case .ok:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.green)
                        default:
                            EmptyView()
                        }
                        Button("Test connection") { Task { await testGatewayConnection() } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .disabled(gatewayTest == .testing)
                    }

                    if case .failed(let message) = gatewayTest {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ProfileListDivider()
            ProfileListRow(icon: "bubble.left.and.text.bubble.right.fill",
                           iconColor: .pink, title: "Send feedback",
                           action: { showFeedbackSheet = true })
        }
    }

    private var sessionStatusText: String {
        if let uid = gatewaySessionUserId {
            return "Signed in · \(String(uid.prefix(14)))\(uid.count > 14 ? "…" : "")"
        }
        return "Signed out"
    }

    /// GET /healthz (no auth) against the effective base URL and show an
    /// honest ✓ / error.
    private func testGatewayConnection() async {
        guard let base = GatewayConfig.baseURL else {
            gatewayTest = .failed("No gateway URL configured.")
            return
        }
        gatewayTest = .testing
        do {
            let url = base.appendingPathComponent("healthz")
            let request = URLRequest(url: url, timeoutInterval: 8)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["ok"] as? Bool) == true else {
                gatewayTest = .failed("Unexpected response from \(url.absoluteString).")
                return
            }
            gatewayTest = .ok
        } catch {
            gatewayTest = .failed(error.localizedDescription)
        }
    }

    private var versionFooter: some View {
        // Derived from the bundle so this can never drift from the real build.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return Text("Fitness Guru · \(version) · build \(build)")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            .padding(.top, 12)
    }

    private func avatarInitials() -> String {
        let words = athleteName.components(separatedBy: " ")
        let initials = words.compactMap { $0.first }.map { String($0) }.joined()
        return String(initials.prefix(2)).uppercased()
    }
}

// MARK: - Stat Tile
struct ProfileStatTile: View {
    let value: String
    let label: String
    let color: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .tracking(-0.7)
                .contentTransition(.numericText())
                .animation(.default, value: value)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                .tracking(-0.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Grouped List
struct ProfileListGroup<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
    }
}

struct ProfileListRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var detail: String? = nil
    /// Optional tap handler. When set the row is wrapped in a Button so the
    /// whole pill becomes interactive instead of just decorative.
    var action: (() -> Void)? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(PlainButtonStyle())
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isDark ? .white : .black)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ProfileListDivider: View {
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    var body: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

// MARK: - Feedback sheet (POST /v1/feedback via the gateway)

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var thumb: FeedbackService.Thumb?
    @State private var text = ""
    @State private var tag = "chat"
    @State private var isSending = false
    @State private var sendError: String?
    @State private var sent = false

    private static let tags = ["chat", "food", "sleep", "widgets", "other"]

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    private var canSend: Bool {
        thumb != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Thumb selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How is Astra doing?")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.4)
                        HStack(spacing: 12) {
                            thumbButton(.up,   icon: "hand.thumbsup.fill",   tint: .green)
                            thumbButton(.down, icon: "hand.thumbsdown.fill", tint: .red)
                        }
                    }

                    // Topic tag
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Picker("Topic", selection: $tag) {
                            ForEach(Self.tags, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Free text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details (optional)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.4)
                        TextEditor(text: $text)
                            .font(.system(size: 14))
                            .frame(minHeight: 120, maxHeight: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                    }

                    if let sendError {
                        Text(sendError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Send
                    Button {
                        Task { await send() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView().controlSize(.small).tint(.white)
                            } else if sent {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(sent ? "Sent — thank you!" : "Send feedback")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(sent ? Color.green : accentColor, in: .capsule)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!canSend || isSending || sent)
                    .opacity((!canSend && !sent) ? 0.5 : 1)
                }
                .padding(20)
            }
            .background(AdaptiveBackground())
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func thumbButton(_ value: FeedbackService.Thumb, icon: String, tint: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            thumb = (thumb == value) ? nil : value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(thumb == value ? .white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if thumb == value {
                        Capsule().fill(tint)
                    }
                }
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(value == .up ? "Thumbs up" : "Thumbs down")
    }

    private func send() async {
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await FeedbackService.send(thumb: thumb, text: text, tag: tag)
            sent = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            sendError = (error as? GatewayError)?.userMessage ?? error.localizedDescription
        }
    }
}
