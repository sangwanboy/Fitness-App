import SwiftUI
import UIKit

// Centralised handlers for opening native apps & system settings — used by the
// Profile / Home rows that previously did nothing.
enum ExternalLink {
    static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
    static func openAppSettings() {
        openURL(UIApplication.openSettingsURLString)
    }
    /// Apple Health main view. iOS supports the x-apple-health scheme since iOS 16.
    static func openHealth()    { openURL("x-apple-health://") }
    /// System Calendar app today view.
    static func openCalendar()  { openURL("calshow://") }
    /// System Reminders app.
    static func openReminders() { openURL("x-apple-reminderkit://") }
}

// MARK: - Edit Profile sheet
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("athlete_name")     private var athleteName: String = "Alex Rivera"
    @AppStorage("athlete_dob")      private var athleteDOBInterval: Double = 0      // 0 = unset
    @AppStorage("athlete_height_cm") private var athleteHeightCm: Double = 0
    @AppStorage("athlete_weight_kg") private var athleteWeightKg: Double = 0

    @State private var name: String = ""
    @State private var dob: Date = Date()
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name)
                    DatePicker("Date of birth", selection: $dob, displayedComponents: .date)
                }
                Section("Body") {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(heightCm)) cm").foregroundStyle(.secondary)
                    }
                    Slider(value: $heightCm, in: 120...220, step: 1)
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f kg", weightKg)).foregroundStyle(.secondary)
                    }
                    Slider(value: $weightKg, in: 30...200, step: 0.5)
                }
                Section {
                    Text("Weight is written back to Apple Health as a body mass sample when you save.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .bold()
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = athleteName
                if athleteDOBInterval > 0 { dob = Date(timeIntervalSince1970: athleteDOBInterval) }
                if athleteHeightCm > 0 { heightCm = athleteHeightCm }
                if athleteWeightKg > 0 { weightKg = athleteWeightKg }
            }
        }
    }

    private func save() async {
        saving = true
        athleteName = name.trimmingCharacters(in: .whitespaces)
        athleteDOBInterval = dob.timeIntervalSince1970
        athleteHeightCm = heightCm
        athleteWeightKg = weightKg
        // Best-effort write to Apple Health so the value isn't only in AppStorage.
        _ = await HealthKitManager.shared.logBodyMass(kilograms: weightKg)
        _ = await HealthKitManager.shared.logHeight(centimeters: heightCm)
        saving = false
        dismiss()
    }
}

// MARK: - Pick-one sheet (used for Coach personality + Training goals)
struct PickOneSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { opt in
                    Button {
                        selection = opt
                        dismiss()
                    } label: {
                        HStack {
                            Text(opt).foregroundColor(.primary)
                            Spacer()
                            if opt == selection {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }
}

// MARK: - Pick-multiple sheet (used for Training goals, etc.)
// Binds to a comma-joined String so an existing single-value @AppStorage key
// can migrate without a schema rewrite.
struct PickMultipleSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { opt in
                    Button {
                        if picked.contains(opt) { picked.remove(opt) } else { picked.insert(opt) }
                    } label: {
                        HStack {
                            Text(opt).foregroundColor(.primary)
                            Spacer()
                            if picked.contains(opt) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selection = picked.sorted().joined(separator: ", ")
                        dismiss()
                    }.bold()
                }
            }
            .onAppear {
                picked = Set(selection
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
            }
        }
    }
}

// MARK: - Home search sheet
struct HomeSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @ObservedObject private var hk = HealthKitManager.shared

    private var results: [(label: String, value: String, icon: String, color: Color)] {
        let all: [(String, String, String, Color)] = HealthMetricType.allCases.map { t in
            let s = hk.metricSummaries[t]
            return (t.displayName,
                    s?.displayValueString ?? "—",
                    t.icon,
                    t.themeColor)
        }
        guard !query.isEmpty else { return all }
        return all.filter { $0.0.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.label) { r in
                HStack(spacing: 12) {
                    Image(systemName: r.icon)
                        .foregroundColor(r.color)
                        .frame(width: 28)
                    Text(r.label)
                    Spacer()
                    Text(r.value).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search your metrics")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
