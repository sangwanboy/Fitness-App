import SwiftUI
import EventKit

public struct RemindersView: View {
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    @ObservedObject private var ek = EventKitManager.shared
    @State private var showAddSheet = false
    @State private var newTitle = ""
    @State private var newDueDate = Date()

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    private var dueTodayCount: Int { todayItems.filter { !$0.isCompleted }.count }

    private var todayItems: [EKReminder] {
        ek.reminders.filter { r in
            guard let date = r.dueDateComponents?.date else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }
    private var tomorrowItems: [EKReminder] {
        ek.reminders.filter { r in
            guard let date = r.dueDateComponents?.date else { return false }
            return Calendar.current.isDateInTomorrow(date)
        }
    }
    private var laterItems: [EKReminder] {
        ek.reminders.filter { r in
            guard let date = r.dueDateComponents?.date else { return true } // no-date → scheduled
            return !Calendar.current.isDateInToday(date) && !Calendar.current.isDateInTomorrow(date)
        }
    }

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if !ek.remindersGranted {
                    permissionPrompt
                }

                section(title: "Today", items: todayItems)
                section(title: "Tomorrow", items: tomorrowItems)
                section(title: "Scheduled", items: laterItems)

                categoriesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveBackground())
        .refreshable { await ek.fetchReminders() }
        .navigationTitle("Reminders")
        .navigationSubtitle(dueTodayCount == 0 ? "All caught up" : "\(dueTodayCount) due today")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(accentColor)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addReminderSheet
        }
        .task {
            if ek.remindersGranted { await ek.fetchReminders() }
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reminders access required")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
            Text("Grant access in Settings → Privacy → Reminders to see and add reminders here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            Button("Grant access") {
                Task { await ek.requestRemindersAccess(); await ek.fetchReminders() }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(accentColor)
            .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func section(title: String, items: [EKReminder]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.calendarItemIdentifier) { idx, item in
                        EKReminderRowView(
                            reminder: item,
                            isLast: idx == items.count - 1,
                            onToggle: {
                                _ = ek.toggleCompletion(item)
                                Task { await ek.fetchReminders() }
                            }
                        )
                    }
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, 4)

            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                CategoryTile(icon: "bolt.fill", count: categoryCount("workout"), label: "Workouts", color: accentColor)
                CategoryTile(icon: "drop.fill", count: categoryCount("water") + categoryCount("hydrat"), label: "Hydration", color: .cyan)
                CategoryTile(icon: "pills.fill", count: categoryCount("supplement") + categoryCount("vitamin"), label: "Supplements", color: .orange)
                CategoryTile(icon: "moon.fill", count: categoryCount("sleep") + categoryCount("wind"), label: "Sleep", color: .purple)
            }
        }
    }

    private func categoryCount(_ keyword: String) -> Int {
        ek.reminders.filter { ($0.title ?? "").localizedCaseInsensitiveContains(keyword) }.count
    }

    // MARK: - Add reminder sheet
    private var addReminderSheet: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $newTitle)
                DatePicker("Due", selection: $newDueDate)
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                            _ = ek.addReminder(title: newTitle, dueDate: newDueDate)
                            newTitle = ""
                            showAddSheet = false
                            Task { await ek.fetchReminders() }
                        }
                    }
                    .bold()
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Real EKReminder row
struct EKReminderRowView: View {
    let reminder: EKReminder
    let isLast: Bool
    let onToggle: () -> Void

    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("theme_mode") private var themeMode = "dark"

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private var inferredIcon: (icon: String, color: Color, tag: String) {
        let title = (reminder.title ?? "").lowercased()
        if title.contains("water") || title.contains("hydrat") { return ("drop.fill", .cyan, "HYDRATION") }
        if title.contains("vitamin") || title.contains("supplement") || title.contains("magnesium") { return ("pills.fill", .orange, "SUPPLEMENT") }
        if title.contains("sleep") || title.contains("wind") { return ("moon.fill", .purple, "SLEEP") }
        if title.contains("run") || title.contains("workout") || title.contains("strength") || title.contains("ride") { return ("bolt.fill", .green, "WORKOUT") }
        return ("bell.fill", accentColor, "")
    }

    private var timeText: String {
        guard let date = reminder.dueDateComponents?.date else { return "" }
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
            fmt.dateFormat = "h:mm a"
        } else {
            fmt.dateFormat = "EEE h:mm a"
        }
        return fmt.string(from: date)
    }

    var body: some View {
        let meta = inferredIcon
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .stroke(reminder.isCompleted ? accentColor : (isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.25)), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        if reminder.isCompleted {
                            Circle().fill(accentColor).frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title ?? "Untitled")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(reminder.isCompleted ? (isDark ? .white.opacity(0.5) : .black.opacity(0.5)) : (isDark ? .white : .black))
                        .strikethrough(reminder.isCompleted, color: isDark ? .white.opacity(0.3) : .black.opacity(0.3))

                    HStack(spacing: 6) {
                        Image(systemName: meta.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(meta.color)
                        if !timeText.isEmpty {
                            Text(timeText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                        }
                        if !meta.tag.isEmpty {
                            Text(meta.tag)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(meta.color)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(meta.color.opacity(0.18))
                                .clipShape(Capsule())
                                .tracking(0.3)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !isLast {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 50)
            }
        }
    }
}

// MARK: - Category Tile (unchanged)
struct CategoryTile: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .tracking(-0.6)
                Spacer()
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isDark ? .white : .black)
                .tracking(-0.2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}
