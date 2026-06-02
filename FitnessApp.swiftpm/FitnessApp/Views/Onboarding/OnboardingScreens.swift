import SwiftUI
import HealthKit

// MARK: - Shared building blocks

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(enabled ? accentColor : Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: enabled ? accentColor.opacity(0.3) : .clear, radius: 12, y: 6)
        }
        .disabled(!enabled)
        .buttonStyle(PlainButtonStyle())
    }
}

private struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Screen 1: Welcome

struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple, .pink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 140, height: 140)
                    .shadow(color: .purple.opacity(0.4), radius: 30, y: 10)
                Image(systemName: "heart.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 36)

            OnboardingTitle(
                title: "Welcome to\nFitness Guru",
                subtitle: "Your AI fitness coach. Personalized recovery, workouts, and nutrition guidance — powered by your real Apple Health data."
            )

            Spacer()

            OnboardingPrimaryButton("Get Started", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
    }
}

// MARK: - Screen 2: About You

struct AboutYouScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @AppStorage("athlete_name")     private var athleteName = ""
    @AppStorage("athlete_dob")      private var athleteDOBInterval: Double = 0
    @AppStorage("athlete_sex")      private var athleteSex = ""
    @AppStorage("athlete_height_cm") private var athleteHeightCm: Double = 170
    @AppStorage("athlete_weight_kg") private var athleteWeightKg: Double = 70

    @State private var name = ""
    // Default to ~25 years ago instead of today's date — otherwise derived age
    // is 0 and the safety rails would treat the user as a minor.
    @State private var dob: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var sex = ""
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70

    private let sexOptions = ["Female", "Male", "Other", "Prefer not to say"]

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTitle(
                        title: "About You",
                        subtitle: "We'll use this to personalize your goals and recovery scoring."
                    )
                    .padding(.top, 12)

                    VStack(spacing: 14) {
                        formField("Name") {
                            TextField("e.g. Alex", text: $name)
                                .textInputAutocapitalization(.words)
                                // iOS autocorrect happily turns "Tushar" into
                                // "Tisha's" — proper names should never be
                                // auto-corrected.
                                .autocorrectionDisabled()
                                .textContentType(.givenName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        formField("Date of birth") {
                            // Cap at today so users can't set a future DOB.
                            DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .colorScheme(.dark)
                        }

                        formField("Sex") {
                            Picker("Sex", selection: $sex) {
                                Text("Select").tag("")
                                ForEach(sexOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                        }

                        sliderField("Height", value: $heightCm, range: 120...220, step: 1, suffix: "cm") {
                            "\(Int(heightCm)) cm"
                        }

                        sliderField("Weight", value: $weightKg, range: 30...200, step: 0.5, suffix: "kg") {
                            String(format: "%.1f kg", weightKg)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 100)
            }

            OnboardingPrimaryButton("Continue", enabled: canContinue) {
                save()
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            name = athleteName
            if athleteDOBInterval > 0 { dob = Date(timeIntervalSince1970: athleteDOBInterval) }
            sex = athleteSex
            if athleteHeightCm > 0 { heightCm = athleteHeightCm }
            if athleteWeightKg > 0 { weightKg = athleteWeightKg }
        }
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(0.8)
            HStack { content(); Spacer() }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func sliderField(_ label: String,
                             value: Binding<Double>,
                             range: ClosedRange<Double>,
                             step: Double,
                             suffix: String,
                             display: @escaping () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.8)
                Spacer()
                Text(display())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Slider(value: value, in: range, step: step)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
    }

    private func save() {
        athleteName = name.trimmingCharacters(in: .whitespaces)
        athleteDOBInterval = dob.timeIntervalSince1970
        athleteSex = sex
        athleteHeightCm = heightCm
        athleteWeightKg = weightKg
        Task {
            _ = await HealthKitManager.shared.logBodyMass(kilograms: weightKg)
            _ = await HealthKitManager.shared.logHeight(centimeters: heightCm)
        }
    }
}

// MARK: - Screen 3: Connect & Permissions

struct ConnectScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @ObservedObject private var hk = HealthKitManager.shared
    @ObservedObject private var ek = EventKitManager.shared

    @State private var requestingHealth = false
    @State private var hkGrantedFlag = false   // local UI flag; HK has no public auth-status read
    @AppStorage("athlete_dob") private var athleteDOBInterval: Double = 0
    @AppStorage("athlete_sex") private var athleteSex = ""

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTitle(
                        title: "Connect",
                        subtitle: "Grant access so your coach can read real data instead of guessing."
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    connectCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Apple Health",
                        description: "Read steps, heart rate, HRV, sleep, workouts, body measurements.",
                        granted: hkGrantedFlag,
                        loading: requestingHealth,
                        connectLabel: "Connect"
                    ) {
                        Task { await connectHealth() }
                    }

                    connectCard(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Calendar & Reminders",
                        description: "Plan workouts around your day; create hydration & supplement reminders.",
                        granted: ek.calendarsGranted || ek.remindersGranted,
                        loading: false,
                        connectLabel: "Connect"
                    ) {
                        Task { await ek.requestAccess() }
                    }

                    connectCard(
                        icon: "cross.case.fill",
                        iconColor: .pink,
                        title: "Medical ID",
                        description: "Pre-filled from Apple Health (date of birth, sex). Optional.",
                        granted: athleteDOBInterval > 0 && !athleteSex.isEmpty,
                        loading: false,
                        connectLabel: "Sync"
                    ) {
                        syncMedicalId()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            OnboardingPrimaryButton("Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func connectCard(icon: String,
                             iconColor: Color,
                             title: String,
                             description: String,
                             granted: Bool,
                             loading: Bool,
                             connectLabel: String,
                             action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer()
            if loading {
                ProgressView().controlSize(.small).tint(.white)
            } else if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text(connectLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private func connectHealth() async {
        requestingHealth = true
        let granted = await hk.requestAuthorization()
        // Onboarding's single source of HK first-prompt — ContentView's .task
        // checks this flag and skips re-asking.
        UserDefaults.standard.set(true, forKey: "hk_requested_once")
        hkGrantedFlag = granted
        // After auth, opportunistically pre-fill Medical ID values if blank.
        syncMedicalId()
        requestingHealth = false
    }

    private func syncMedicalId() {
        let (dob, sex, _) = hk.readMedicalIdCharacteristics()
        if athleteDOBInterval == 0, let dob {
            athleteDOBInterval = dob.timeIntervalSince1970
        }
        if athleteSex.isEmpty, let sex {
            switch sex {
            case .female: athleteSex = "Female"
            case .male:   athleteSex = "Male"
            case .other:  athleteSex = "Other"
            default: break
            }
        }
    }
}

// MARK: - Screen 4: Goals

struct GoalsScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @AppStorage("training_goals") private var trainingGoals: String = ""
    @State private var selected: Set<String> = []

    private let options: [(String, String)] = [
        ("Endurance", "figure.run"),
        ("Strength", "dumbbell.fill"),
        ("Weight loss", "scalemass.fill"),
        ("Sleep better", "bed.double.fill"),
        ("Stay active", "figure.walk"),
        ("Flexibility", "figure.cooldown")
    ]

    private var canContinue: Bool { !selected.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            VStack(spacing: 20) {
                OnboardingTitle(
                    title: "Pick Your Goals",
                    subtitle: "Choose one or more. Your coach focuses recommendations on what matters to you."
                )
                .padding(.top, 12)

                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(options, id: \.0) { (label, icon) in
                        Button {
                            if selected.contains(label) { selected.remove(label) } else { selected.insert(label) }
                        } label: {
                            goalTile(label: label, icon: icon, picked: selected.contains(label))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }

            OnboardingPrimaryButton("Continue", enabled: canContinue) {
                trainingGoals = selected.sorted().joined(separator: ", ")
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            selected = Set(trainingGoals
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
    }

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private func goalTile(label: String, icon: String, picked: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(picked ? accentColor : .white.opacity(0.75))
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(picked ? accentColor : Color.clear, lineWidth: 2)
        )
        // Visible bounce so the tap registers immediately, even before the
        // green border animates in. Pairs with a selection-class haptic so
        // the user feels the toggle on physical devices.
        .scaleEffect(picked ? 1.02 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: picked)
        .sensoryFeedback(.selection, trigger: picked)
    }
}

// MARK: - Screen 5: Meet Astra

struct MeetAstraScreen: View {
    let onFinish: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBackButton(action: onBack)
                .padding(.top, 4)

            Spacer()

            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.indigo, .purple, .pink, .indigo], center: .center))
                    .frame(width: 130, height: 130)
                    .blur(radius: 1)
                    .shadow(color: .purple.opacity(0.5), radius: 30, y: 10)
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 32)

            OnboardingTitle(
                title: "Meet Astra",
                subtitle: "Your AI fitness coach. Ask anything — log meals, plan workouts, get recovery advice, all grounded in your real data."
            )

            Spacer()

            OnboardingPrimaryButton("Get Started", action: onFinish)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
    }
}
