import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    @AppStorage("is_logged_in") private var isLoggedIn = true
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("athlete_name") private var athleteName = "Alex Rivera"
    @AppStorage("glass_tint_color") private var glassTintColorHex = "#FFFFFF"
    @AppStorage("glass_tint_strength") private var glassTintStrength = 0.0

    @State private var showSignOutConfirm = false
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

    // Vertex AI key paste state
    @AppStorage(VertexConfig.userDefaultsKey) private var pastedVertexJSON: String = ""
    @State private var vertexJSONDraft: String = ""
    @State private var vertexStatus: VertexStatus = .unknown
    @State private var isTestingVertex = false

    enum VertexStatus: Equatable {
        case unknown
        case checking
        case ok(projectId: String, source: String)
        case error(String)
    }

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    /// "Joined Mar 2025 · 14 day streak". The joined date is read from
    /// AppStorage if set, else from HealthKit history (backfill for upgraders),
    /// else today's date. Streak is real consecutive step-goal days.
    private var joinedAndStreakLine: String {
        let joinedDate: Date = {
            if accountCreatedDate > 0 {
                return Date(timeIntervalSince1970: accountCreatedDate)
            }
            return healthKitManager.earliestHistoryDate() ?? Date()
        }()
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        let streak = healthKitManager.dayStreak()
        let streakLabel = streak == 1 ? "1 day streak" : "\(streak) day streak"
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
                healthRecordsSection
                vertexKeySection
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
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                withAnimation { isLoggedIn = false }
            }
        } message: {
            Text("You'll need to sign back in to access your data.")
        }
        .onAppear {
            glassTintColorHex = "#FFFFFF"
            vertexJSONDraft = pastedVertexJSON
            refreshVertexStatus()
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

            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 12, weight: .semibold))
                Text("Signed in with Apple")
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
            ProfileStatTile(value: "\(healthKitManager.dayStreak())", label: "Day streak", color: .orange)
            ProfileStatTile(
                value: String(format: "%.0f", healthKitManager.metricSummaries[.heartRate]?.currentValue ?? 62),
                label: "Resting HR",
                color: .red
            )
            ProfileStatTile(
                value: String(format: "%.0f", healthKitManager.metricSummaries[.hrv]?.currentValue ?? 74),
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

    /// Compact lifetime Gemini token total for the AI token usage row.
    private var tokenUsageSummary: String {
        tokenMeter.total == 0 ? "No usage yet" : "\(TokenFormat.compact(tokenMeter.total)) tokens"
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
            Button(action: { showSignOutConfirm = true }) {
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
        }
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

    // MARK: - Vertex AI Key Section
    private var vertexKeySection: some View {
        ProfileListGroup(header: "Vertex AI (Gemini)") {
            VStack(alignment: .leading, spacing: 10) {
                // Status row
                HStack(spacing: 8) {
                    Image(systemName: vertexStatusIcon)
                        .foregroundColor(vertexStatusColor)
                    Text(vertexStatusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                    Spacer()
                    if isTestingVertex {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Test") { Task { await testVertexAuth() } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .disabled(isTestingVertex)
                    }
                }

                Text("Paste a Google Cloud service-account JSON key with Vertex AI access. Stored locally on device only.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))

                TextEditor(text: $vertexJSONDraft)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 140, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        VertexConfig.setPastedJSON(vertexJSONDraft)
                        VertexAuth.shared.invalidateCache()
                        Task { await testVertexAuth() }
                    } label: {
                        Text("Save key")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(vertexJSONDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        VertexConfig.clearPastedJSON()
                        VertexAuth.shared.invalidateCache()
                        vertexJSONDraft = ""
                        refreshVertexStatus()
                    } label: {
                        Text("Use bundled key")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var vertexStatusIcon: String {
        switch vertexStatus {
        case .ok: return "checkmark.circle.fill"
        case .checking: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var vertexStatusColor: Color {
        switch vertexStatus {
        case .ok: return .green
        case .checking: return .yellow
        case .error: return .red
        case .unknown: return .secondary
        }
    }

    private var vertexStatusText: String {
        switch vertexStatus {
        case .unknown: return "Status unknown"
        case .checking: return "Checking…"
        case .ok(let projectId, let source): return "Connected · \(projectId) · \(source)"
        case .error(let msg): return shortError(msg)
        }
    }

    /// Boil long Google OAuth JSON errors down to a one-line reason.
    private func shortError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("invalid_grant") && lower.contains("account not found") {
            return "Service account not found — tap Use bundled key"
        }
        if lower.contains("invalid_grant") {
            return "Invalid grant — key may be revoked or expired"
        }
        if lower.contains("malformed") || lower.contains("decode") {
            return "JSON malformed — paste the full service-account file"
        }
        if lower.contains("forbidden") || lower.contains("403") {
            return "Project lacks Vertex AI access — enable the API in GCP"
        }
        if lower.contains("404") || lower.contains("not found") {
            return "Endpoint not found — wrong region or project"
        }
        // Fallback: first 80 chars of the raw message.
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ")
        return String(trimmed.prefix(80))
    }

    private func refreshVertexStatus() {
        do {
            let (sa, source) = try VertexConfig.current()
            vertexStatus = .ok(projectId: sa.projectId, source: source == .userPasted ? "your key" : "bundled")
        } catch {
            vertexStatus = .error(error.localizedDescription)
        }
    }

    private func testVertexAuth() async {
        isTestingVertex = true
        vertexStatus = .checking
        defer { isTestingVertex = false }
        do {
            _ = try await VertexAuth.shared.getAccessToken()
            let (sa, source) = try VertexConfig.current()
            vertexStatus = .ok(projectId: sa.projectId, source: source == .userPasted ? "your key" : "bundled")
        } catch {
            vertexStatus = .error(error.localizedDescription)
        }
    }

    private var versionFooter: some View {
        Text("Fitness Guru · 1.0 · build 248")
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
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                .tracking(-0.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
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
