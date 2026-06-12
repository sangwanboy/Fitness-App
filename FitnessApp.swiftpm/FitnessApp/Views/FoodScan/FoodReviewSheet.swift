import SwiftUI

struct FoodReviewSheet: View {
    let image: UIImage
    let result: FoodRecognitionResult
    let onLogged: () -> Void
    let onRetake: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    // Mutable copies of items so the user can edit name/portion/macros
    @State private var editableItems: [EditableItem] = []
    @State private var isLogging = false
    @State private var logError: String? = nil
    @State private var editingItemID: UUID? = nil

    // Astra correction chat
    @State private var astraInput: String = ""
    @State private var isRefining = false
    @State private var astraMessages: [AstraMsg] = []

    struct AstraMsg: Identifiable { let id = UUID(); let isUser: Bool; let text: String }

    struct EditableItem: Identifiable {
        var id: UUID
        var included: Bool = true
        var name: String
        var portionDescription: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        let isEstimate: Bool
        let confidence: String
        let identificationNote: String

        init(from item: RecognizedFoodItem) {
            id = item.id; name = item.name
            portionDescription = item.portionDescription
            calories = item.calories; protein = item.protein
            carbs = item.carbs; fat = item.fat
            isEstimate = item.isEstimate
            confidence = item.confidence
            identificationNote = item.identificationNote
        }
    }

    // Live totals from checked items
    private var totalCalories: Double { editableItems.filter(\.included).reduce(0) { $0 + $1.calories } }
    private var totalProtein:  Double { editableItems.filter(\.included).reduce(0) { $0 + $1.protein } }
    private var totalCarbs:    Double { editableItems.filter(\.included).reduce(0) { $0 + $1.carbs } }
    private var totalFat:      Double { editableItems.filter(\.included).reduce(0) { $0 + $1.fat } }
    private var checkedCount:  Int    { editableItems.filter(\.included).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Photo thumbnail
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()

                // Confidence banner (medium or low only)
                if result.overallConfidence != "high" {
                    confidenceBanner
                }

                // Items list
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("ITEMS DETECTED")
                        .padding(.top, 20)
                        .padding(.horizontal, 16)

                    ForEach($editableItems) { $item in
                        itemRow(item: $item)
                        Divider()
                            .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1))
                            .padding(.leading, 16)
                    }

                    // Plate note from model
                    if let note = result.plateNote, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                }
                .padding(.bottom, 12)

                // Totals card
                totalsCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Astra correction chat
                astraBox
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Retake button (secondary)
                Button("Retake Photo") { onRetake() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Primary CTA
                logButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(AdaptiveBackground())
        .onAppear {
            editableItems = result.items.map { EditableItem(from: $0) }
        }
        // Inline edit sheet
        .sheet(item: $editingItemID) { id in
            if let idx = editableItems.firstIndex(where: { $0.id == id }) {
                ItemEditSheet(item: $editableItems[idx])
            }
        }
        .alert("Logging failed", isPresented: Binding(
            get: { logError != nil },
            set: { if !$0 { logError = nil } }
        )) {
            Button("OK") { logError = nil }
        } message: {
            Text(logError ?? "")
        }
    }

    // MARK: - Confidence banner

    private var confidenceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: result.overallConfidence == "low"
                  ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(result.overallConfidence == "low" ? .red : .orange)
            Text(result.overallConfidence == "low"
                 ? "We couldn't get a clear read on this meal. Check each item carefully before logging."
                 : "Review and adjust portions below — estimates are approximate.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (result.overallConfidence == "low" ? Color.red : Color.orange).opacity(0.12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Item row

    @ViewBuilder
    private func itemRow(item: Binding<EditableItem>) -> some View {
        let i = item.wrappedValue
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                item.included.wrappedValue.toggle()
            } label: {
                Image(systemName: i.included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(i.included ? accentColor : (isDark ? .white.opacity(0.3) : .black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(i.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDark ? .white : .black)
                        .strikethrough(!i.included, color: .secondary)

                    confidenceDot(i.confidence)
                    Spacer()

                    // Portion
                    Text(i.portionDescription)
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                }

                // Macros line
                Text("~\(Int(i.calories)) kcal · \(formatted(i.protein))g P · \(formatted(i.carbs))g C · \(formatted(i.fat))g F")
                    .font(.system(size: 13))
                    .foregroundColor(isDark ? .white.opacity(0.65) : .black.opacity(0.65))

                // Identification note
                Text(i.identificationNote)
                    .font(.system(size: 11))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .lineLimit(2)
            }

            // Edit + delete
            VStack(spacing: 8) {
                Button {
                    editingItemID = i.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .padding(8)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)

                Button {
                    deleteItem(i.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(8)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(i.name)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(i.included ? 1 : 0.45)
    }

    // MARK: - Confidence dot

    private func confidenceDot(_ confidence: String) -> some View {
        Circle()
            .fill(confidence == "high" ? Color.green : confidence == "medium" ? Color.orange : Color.red)
            .frame(width: 7, height: 7)
    }

    // MARK: - Totals card

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTALS (estimated)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                .tracking(0.5)

            HStack(spacing: 0) {
                macroColumn("~\(Int(totalCalories))", "kcal", .orange)
                Spacer()
                macroColumn("\(formatted(totalProtein))g", "protein", .blue)
                Spacer()
                macroColumn("\(formatted(totalCarbs))g", "carbs", .yellow)
                Spacer()
                macroColumn("\(formatted(totalFat))g", "fat", .pink)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func macroColumn(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 11)).foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
    }

    // MARK: - Log button

    private var logButton: some View {
        Button {
            guard checkedCount > 0 else { return }
            guard !isLogging else { return }
            isLogging = true
            Task {
                await logCheckedItems()
                isLogging = false
            }
        } label: {
            HStack(spacing: 10) {
                if isLogging {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isLogging ? "Logging…" : "Log This Meal (\(checkedCount) item\(checkedCount == 1 ? "" : "s"))")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                checkedCount > 0
                    ? LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(checkedCount == 0 || isLogging)
    }

    // MARK: - HealthKit write

    private func logCheckedItems() async {
        let toLog = editableItems.filter(\.included)
        var allOk = true
        for item in toLog {
            let ok = await HealthKitManager.shared.logFood(
                name: item.name,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                isEstimate: item.isEstimate,
                confidence: item.confidence
            )
            if !ok { allOk = false }
        }
        // Refresh diet data so MealsCard and Health Meter update immediately
        await HealthKitManager.shared.refreshDietaryNow()
        if allOk {
            await MainActor.run { onLogged() }
        } else {
            await MainActor.run {
                logError = "Some items could not be saved to Health. Check HealthKit permissions in Settings."
            }
        }
    }

    // MARK: - Astra correction chat

    private var canSend: Bool { !astraInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var secondaryColor: Color { isDark ? .white.opacity(0.55) : .black.opacity(0.55) }

    private var astraBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
                Text("Ask Astra to fix it")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
            }
            Text("Tell Astra what's wrong in plain words — e.g. “the chicken is skinless”, “potatoes are 2 cups”, or “remove the tacos”. It sees your photo and these items.")
                .font(.system(size: 12))
                .foregroundColor(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            if !astraMessages.isEmpty {
                VStack(spacing: 8) {
                    ForEach(astraMessages) { m in
                        HStack {
                            if m.isUser { Spacer(minLength: 36) }
                            Text(m.text)
                                .font(.system(size: 13))
                                .foregroundColor(isDark ? .white : .black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    m.isUser
                                        ? accentColor.opacity(0.22)
                                        : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            if !m.isUser { Spacer(minLength: 36) }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Tell Astra what to change…", text: $astraInput, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 14))

                Button {
                    Task { await askAstra() }
                } label: {
                    if isRefining {
                        ProgressView().tint(accentColor).frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(canSend ? accentColor : (isDark ? .white.opacity(0.25) : .black.opacity(0.25)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isRefining)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func askAstra() async {
        let text = astraInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRefining else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
        astraMessages.append(AstraMsg(isUser: true, text: text))
        astraInput = ""
        isRefining = true
        let json = currentItemsJSON()
        do {
            let updated = try await FoodVisionService.shared.refineFood(
                imageData: jpeg, currentItemsJSON: json, instruction: text)
            await MainActor.run {
                withAnimation {
                    editableItems = updated.items.map { EditableItem(from: $0) }
                }
                let reply = (updated.plateNote?.isEmpty == false)
                    ? updated.plateNote!
                    : "Updated — review the items above."
                astraMessages.append(AstraMsg(isUser: false, text: reply))
                isRefining = false
            }
        } catch {
            await MainActor.run {
                astraMessages.append(AstraMsg(isUser: false, text: "Sorry, I couldn't update that — try rephrasing."))
                isRefining = false
            }
        }
    }

    /// Compact JSON of the items currently shown, sent to Astra as context.
    private func currentItemsJSON() -> String {
        let arr: [[String: Any]] = editableItems.map { i in
            ["name": i.name, "portion": i.portionDescription,
             "calories_kcal": i.calories, "protein_g": i.protein,
             "carbs_g": i.carbs, "fat_g": i.fat, "confidence": i.confidence]
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr),
           let s = String(data: data, encoding: .utf8) { return s }
        return "[]"
    }

    private func deleteItem(_ id: UUID) {
        withAnimation { editableItems.removeAll { $0.id == id } }
    }

    // MARK: - Helpers

    private func formatted(_ v: Double) -> String { String(format: "%.1f", v) }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            .tracking(0.5)
    }
}

// MARK: - ItemEditSheet (inline sub-sheet for editing a single item)

private struct ItemEditSheet: View {
    @Binding var item: FoodReviewSheet.EditableItem
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    // Local editing state — commit on "Done"
    @State private var name: String = ""
    @State private var portion: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Portion", text: $portion)
                }
                Section("Macros (estimated)") {
                    HStack {
                        Text("Calories (kcal)")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Carbs (g)")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Fat (g)")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section {
                    HStack(spacing: 6) {
                        confidenceDot(item.confidence)
                        Text("Confidence: \(item.confidence.capitalized)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    Text(item.identificationNote)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitEdits(); dismiss() }
                }
            }
        }
        .onAppear {
            name = item.name
            portion = item.portionDescription
            calories = formatted(item.calories)
            protein = formatted(item.protein)
            carbs = formatted(item.carbs)
            fat = formatted(item.fat)
        }
    }

    private func commitEdits() {
        item.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? item.name : name.trimmingCharacters(in: .whitespaces)
        item.portionDescription = portion.trimmingCharacters(in: .whitespaces).isEmpty ? item.portionDescription : portion.trimmingCharacters(in: .whitespaces)
        if let v = Double(calories), v >= 0 { item.calories = v }
        if let v = Double(protein),  v >= 0 { item.protein = v }
        if let v = Double(carbs),    v >= 0 { item.carbs = v }
        if let v = Double(fat),      v >= 0 { item.fat = v }
    }

    private func formatted(_ v: Double) -> String { String(format: "%.1f", v) }

    private func confidenceDot(_ confidence: String) -> some View {
        Circle()
            .fill(confidence == "high" ? Color.green : confidence == "medium" ? Color.orange : Color.red)
            .frame(width: 8, height: 8)
    }
}

// Make UUID conform to Identifiable for .sheet(item: $editingItemID)
extension UUID: @retroactive Identifiable { public var id: UUID { self } }
