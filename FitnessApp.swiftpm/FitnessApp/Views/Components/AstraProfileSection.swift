import SwiftUI

/// "Astra's profile of you" — a self-contained Settings section surfacing
/// everything `AstraMemoryStore` knows: the model-maintained profile
/// sections (read-only, with last-updated stamps), live basics pulled fresh
/// from Apple Health on every render, a memories summary that opens the
/// full swipe-to-delete list, the master toggle, and a destructive
/// "Clear all". Reuses `ProfileListGroup` / `ProfileListRow` /
/// `ProfileListDivider` from SettingsView so it reads as native to the
/// screen rather than a bolt-on.
///
/// Disabling the toggle only stops Astra from reading/writing memory going
/// forward — previously stored data stays visible here until the user
/// explicitly clears it, so nothing silently vanishes.
public struct AstraProfileSection: View {
    @ObservedObject private var memory = AstraMemoryStore.shared

    // Own @AppStorage binding (not routed through the ObservableObject) so
    // the Toggle participates directly in SwiftUI's dependency tracking —
    // an @AppStorage property nested inside a plain class doesn't reliably
    // trigger a re-render through @ObservedObject alone. Same UserDefaults
    // key as AstraMemoryStore.isEnabled, so both always agree.
    @AppStorage("astra_memory_enabled") private var memoryEnabled: Bool = true

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"

    @State private var showMemoriesSheet = false
    @State private var showClearAllConfirm = false

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    public init() {}

    public var body: some View {
        ProfileListGroup(header: "Astra's profile of you") {
            toggleRow
            ProfileListDivider()
            liveBasicsRow
            ProfileListDivider()
            if memory.isEmpty {
                emptyStateRow
            } else {
                profileSectionsRows
                ProfileListDivider()
                memoriesRow
            }
            ProfileListDivider()
            clearAllRow
        }
        .sheet(isPresented: $showMemoriesSheet) {
            AstraMemoriesSheet(accentColor: accentColor, isDark: isDark)
        }
        .confirmationDialog("Clear Astra's memory?", isPresented: $showClearAllConfirm, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                withAnimation { memory.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every profile section and memory fact Astra has saved about you. This can't be undone.")
        }
    }

    // MARK: - Toggle

    private var toggleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                Text("Remember me across chats")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isDark ? .white : .black)
                Spacer()
                Toggle("", isOn: $memoryEnabled)
                    .labelsHidden()
                    .tint(accentColor)
                    .accessibilityLabel("Astra long-term memory")
            }
            if !memoryEnabled {
                Text("Off — Astra won't read or update this until you turn it back on. Anything already saved stays put.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 42)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Live basics (derived fresh from HealthKit on every render)

    private var liveBasicsRow: some View {
        let basics = AstraMemoryStore.liveBasics()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
                Text("LIVE BASICS · FROM APPLE HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            HStack(spacing: 4) {
                basicTile("Age", basics.age.map { "\($0)" } ?? "—")
                basicTile("Height", basics.heightCm.map { String(format: "%.0f cm", $0) } ?? "—")
                basicTile("Weight", basics.weightKg.map { String(format: "%.1f kg", $0) } ?? "—")
                basicTile("VO₂max", basics.vo2Max.map { String(format: "%.1f", $0) } ?? "—")
                basicTile("RHR", basics.restingHR.map { String(format: "%.0f", $0) } ?? "—")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func basicTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Profile sections (read-only, model-maintained)

    @ViewBuilder
    private var profileSectionsRows: some View {
        let nonEmpty = AstraUserProfile.Section.allCases.filter { !memory.profile.get($0).text.isEmpty }
        if nonEmpty.isEmpty {
            Text("Astra hasn't written a profile summary yet.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nonEmpty.enumerated()), id: \.element) { index, section in
                    profileSectionRow(section)
                    if index < nonEmpty.count - 1 {
                        ProfileListDivider()
                    }
                }
            }
        }
    }

    private func profileSectionRow(_ section: AstraUserProfile.Section) -> some View {
        let content = memory.profile.get(section)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(section.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                Spacer()
                if let updated = content.lastUpdated {
                    Text(Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                }
            }
            Text(content.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Memories summary row → sheet

    private var memoriesRow: some View {
        ProfileListRow(
            icon: "brain.head.profile",
            iconColor: .indigo,
            title: "Memories",
            detail: memory.facts.isEmpty ? "None yet" : "\(memory.facts.count) saved",
            action: { showMemoriesSheet = true }
        )
    }

    // MARK: - Clear all

    private var clearAllRow: some View {
        Button(action: {
            guard !memory.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showClearAllConfirm = true
        }) {
            HStack {
                Text("Clear all")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(memory.isEmpty ? .secondary : .red)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(memory.isEmpty)
    }

    // MARK: - Empty state

    private var emptyStateRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            Text("Astra hasn't learned anything yet — it builds this as you chat.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

// MARK: - Full memories list (swipe-to-delete, grouped by category)

/// Presented from the "Memories" row. A real `List` (not a hand-rolled
/// gesture) so swipe-to-delete is native and reliable — mirrors
/// `ChatHistorySheet`'s List + `.onDelete` pattern in ChatView.swift.
private struct AstraMemoriesSheet: View {
    @ObservedObject private var memory = AstraMemoryStore.shared
    @Environment(\.dismiss) private var dismiss

    let accentColor: Color
    let isDark: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if memory.facts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(MemoryFact.Category.allCases) { category in
                            let inCategory = memory.facts.filter { $0.category == category }
                            if !inCategory.isEmpty {
                                Section(category.displayName) {
                                    ForEach(inCategory) { fact in
                                        factRow(fact)
                                    }
                                    .onDelete { offsets in
                                        let idsToDelete = offsets.map { inCategory[$0].id }
                                        withAnimation {
                                            for id in idsToDelete { memory.deleteFact(id: id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AdaptiveBackground())
            .navigationTitle("Astra's memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func factRow(_ fact: MemoryFact) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fact.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? .white : .black)
            Text(Self.dateFormatter.string(from: fact.createdAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No memories yet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
            Text("Astra saves facts here as it learns lasting things about you.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
