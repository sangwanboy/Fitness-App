import SwiftUI

/// Map an Astra-emitted color name to a SwiftUI Color. Used by widget tool
/// cards + the WidgetsCard at render time so both surfaces stay in sync on
/// the palette the LLM can choose from.
func toolColor(name: String?) -> Color {
    switch (name ?? "").lowercased() {
    case "red":    return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green":  return .green
    case "blue":   return .blue
    case "indigo": return .indigo
    case "purple": return .purple
    case "pink":   return .pink
    case "cyan":   return .cyan
    case "gray", "grey": return .gray
    case "accent", "": return .indigo
    default: return .indigo
    }
}

// Cards rendered inline in chat when Astra makes a function call.
// Three flavors:
// * Write actions (log_food, add_reminder, add_calendar_event) → Confirm / Cancel
// * Read actions (show_metric_chart, render_card) → auto-rendered, no buttons

// Inline markdown parser used for any LLM-authored text inside a tool card.
// Tool cards came after the StructuredMarkdownText work and used plain Text,
// so **bold** in render_card bullets was leaking through as raw asterisks.
private func inlineMD(_ s: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
}

struct ToolCallCard: View {
    let messageId: UUID
    let call: ToolCall
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        switch call {
        case .logFood(let name, let cal, let p, let c, let f, let serving, let tags, let highlights, let cautions, let isEstimate, let confidence):
            FoodToolCard(name: name, calories: cal, protein: p, carbs: c, fat: f, serving: serving,
                         tags: tags, highlights: highlights, cautions: cautions,
                         isEstimate: isEstimate, confidence: confidence,
                         status: status, accentColor: accentColor, onConfirm: onConfirm, onCancel: onCancel)
        case .addReminder(let title, let due, let category):
            ReminderToolCard(title: title, dueAt: due, category: category,
                             status: status, accentColor: accentColor, onConfirm: onConfirm, onCancel: onCancel)
        case .addCalendarEvent(let title, let start, let end, let notes):
            EventToolCard(title: title, startsAt: start, endsAt: end, notes: notes,
                          status: status, accentColor: accentColor, onConfirm: onConfirm, onCancel: onCancel)
        case .showMetricChart(let metric, let days):
            MetricChartToolCard(metric: metric, days: days, accentColor: accentColor)
        case .showComparisonChart(let metric, let pa, let pb, let title):
            ComparisonChartToolCard(metric: metric, periodA: pa, periodB: pb, title: title, accentColor: accentColor)
        case .renderCard(let title, let icon, let color, let headline, let bullets, let stats):
            CustomToolCard(title: title, icon: icon, colorName: color, headline: headline,
                           bullets: bullets, stats: stats, accentColor: accentColor)
        case .listReminders(let filter):
            ListSummaryCard(icon: "bell.fill", color: .orange,
                            title: "Looked up reminders",
                            subtitle: subtitleForListFilter(filter))
        case .listCalendarEvents(let days):
            ListSummaryCard(icon: "calendar", color: .blue,
                            title: "Looked up calendar",
                            subtitle: "Next \(days) day\(days == 1 ? "" : "s")")
        case .updateReminder(_, let title, let due, let notes):
            MutationConfirmCard(icon: "bell.badge", color: .orange,
                                title: "Update reminder",
                                summary: title ?? "Reminder",
                                detail: updateDetailLine(title: title, due: due, notes: notes),
                                confirmLabel: "Update",
                                status: status, accentColor: accentColor,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .updateCalendarEvent(_, let title, let start, let end, let notes):
            MutationConfirmCard(icon: "calendar.badge.clock", color: .blue,
                                title: "Update event",
                                summary: title ?? "Event",
                                detail: eventUpdateDetail(title: title, start: start, end: end, notes: notes),
                                confirmLabel: "Update",
                                status: status, accentColor: accentColor,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .deleteReminder(_, let title):
            MutationConfirmCard(icon: "bell.slash.fill", color: .red,
                                title: "Delete reminder",
                                summary: title ?? "Reminder",
                                detail: "This will remove it from the Fitness Guru list.",
                                confirmLabel: "Delete",
                                status: status, accentColor: .red,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .deleteCalendarEvent(_, let title):
            MutationConfirmCard(icon: "calendar.badge.minus", color: .red,
                                title: "Delete event",
                                summary: title ?? "Event",
                                detail: "This will remove it from the Fitness Guru calendar.",
                                confirmLabel: "Delete",
                                status: status, accentColor: .red,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .getPredictions:
            ListSummaryCard(icon: "chart.line.uptrend.xyaxis", color: .indigo,
                            title: "Checked predictions",
                            subtitle: "Recovery · next workout · pace · sedentary")
        case .listFoodLog:
            ListSummaryCard(icon: "fork.knife", color: .orange,
                            title: "Looked up today's meals",
                            subtitle: "Picking the right entry")
        case .updateFoodLog(_, let name, let cals, let p, let c, let f):
            MutationConfirmCard(icon: "fork.knife.circle.fill", color: .orange,
                                title: "Update meal",
                                summary: name ?? "Logged meal",
                                detail: foodUpdateDetail(name: name, cals: cals, p: p, c: c, f: f),
                                confirmLabel: "Update",
                                status: status, accentColor: accentColor,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .deleteFoodLog(_, let name):
            MutationConfirmCard(icon: "trash.fill", color: .red,
                                title: "Delete meal",
                                summary: name ?? "Logged meal",
                                detail: "Removes the kcal + protein + carbs + fat samples from HealthKit.",
                                confirmLabel: "Delete",
                                status: status, accentColor: .red,
                                onConfirm: onConfirm, onCancel: onCancel)
        case .updateNotes:
            ListSummaryCard(icon: "brain", color: .indigo,
                            title: "Memory updated",
                            subtitle: "Astra saved a note for future sessions")
        case .getSleepPattern:
            ListSummaryCard(icon: "moon.zzz.fill", color: .indigo,
                            title: "Checked your sleep pattern",
                            subtitle: "Bedtime · duration · restlessness · snore baseline")
        case .createWidget, .listWidgets, .updateWidget, .deleteWidget:
            // Extracted to a helper — keeps the main @ViewBuilder switch
            // under Swift's type-checker complexity limit. 4 widget cases
            // were pushing it over.
            widgetToolCardBody
        }
    }

    @ViewBuilder
    private var widgetToolCardBody: some View {
        switch call {
        case .createWidget(let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            let layoutEnum: WidgetLayout = {
                if blocks?.isEmpty == false { return .composed }
                return WidgetLayout(rawValue: layout) ?? .narrative
            }()
            let preview = AstraWidget(
                title: title, icon: icon, colorName: color, layout: layoutEnum,
                headline: headline, body: body, bullets: bullets ?? [],
                metricRef: metricRef, goalValue: goalValue, blocks: blocks
            )
            WidgetPreviewConfirmCard(
                previewWidget: preview,
                headerTitle: "Pin widget to Home",
                confirmLabel: "Pin",
                doneLabel: "Pinned to Home",
                status: status, accentColor: accentColor,
                onConfirm: onConfirm, onCancel: onCancel
            )
        case .listWidgets:
            ListSummaryCard(icon: "square.grid.2x2.fill", color: .indigo,
                            title: "Looked up pinned widgets",
                            subtitle: "Picking the right one")
        case .updateWidget(let id, let title, let icon, let color, let layout, let headline, let body, let bullets, let metricRef, let goalValue, let blocks):
            let preview = buildUpdatePreview(id: id, title: title, icon: icon, color: color,
                                              layout: layout, headline: headline, body: body,
                                              bullets: bullets, metricRef: metricRef,
                                              goalValue: goalValue, blocks: blocks)
            WidgetPreviewConfirmCard(
                previewWidget: preview,
                headerTitle: "Update widget",
                confirmLabel: "Update",
                doneLabel: "Updated",
                status: status, accentColor: accentColor,
                onConfirm: onConfirm, onCancel: onCancel
            )
        case .deleteWidget(_, let title):
            MutationConfirmCard(icon: "square.grid.2x2", color: .red,
                                title: "Remove widget",
                                summary: title ?? "Pinned widget",
                                detail: "Removes it from your Home screen. You can ask Astra to pin a new one any time.",
                                confirmLabel: "Remove",
                                status: status, accentColor: .red,
                                onConfirm: onConfirm, onCancel: onCancel)
        default:
            EmptyView()
        }
    }

    /// Merge proposed update args onto the existing persisted widget (if found)
    /// to produce a preview. Falls back to a placeholder widget when the id
    /// isn't in the store yet (shouldn't happen in normal flow).
    private func buildUpdatePreview(id: String,
                                    title: String?,
                                    icon: String?,
                                    color: String?,
                                    layout: String?,
                                    headline: String?,
                                    body: String?,
                                    bullets: [String]?,
                                    metricRef: String?,
                                    goalValue: Double?,
                                    blocks: [WidgetBlock]?) -> AstraWidget {
        var w: AstraWidget = AstraWidgetStore.shared.widget(idString: id)
            ?? AstraWidget(title: title ?? "Widget",
                           icon: icon ?? "square.grid.2x2.fill",
                           colorName: color ?? "indigo",
                           layout: .narrative)
        if let title    { w.title    = title }
        if let icon     { w.icon     = icon }
        if let color    { w.colorName = color }
        if let layout, let l = WidgetLayout(rawValue: layout) {
            w.layout = l
            if l != .composed { w.blocks = nil }
        }
        if let headline  { w.headline  = headline }
        if let body      { w.body      = body }
        if let bullets   { w.bullets   = bullets }
        if let metricRef { w.metricRef = metricRef.isEmpty ? nil : metricRef }
        if let goalValue { w.goalValue = goalValue }
        if let blocks {
            w.blocks = blocks.isEmpty ? nil : blocks
            if !blocks.isEmpty { w.layout = .composed }
        }
        return w
    }

    private func widgetDetail(layout: String?, headline: String?, body: String?, bullets: [String]?, metricRef: String?) -> String {
        var parts: [String] = []
        if let layout, !layout.isEmpty { parts.append(layout.capitalized) }
        if let headline, !headline.isEmpty { parts.append("\"\(headline)\"") }
        if let body, !body.isEmpty {
            let trimmed = body.count > 80 ? String(body.prefix(77)) + "…" : body
            parts.append(trimmed)
        }
        if let bullets, !bullets.isEmpty {
            parts.append("\(bullets.count) bullet\(bullets.count == 1 ? "" : "s")")
        }
        if let metricRef, !metricRef.isEmpty {
            parts.append("→ live \(metricRef)")
        }
        return parts.isEmpty ? "Widget" : parts.joined(separator: " · ")
    }

    private func foodUpdateDetail(name: String?, cals: Double?, p: Double?, c: Double?, f: Double?) -> String {
        var parts: [String] = []
        if let name { parts.append("Name → \(name)") }
        if let cals { parts.append("\(Int(cals.rounded())) kcal") }
        if let p { parts.append("\(Int(p.rounded()))g P") }
        if let c { parts.append("\(Int(c.rounded()))g C") }
        if let f { parts.append("\(Int(f.rounded()))g F") }
        return parts.isEmpty ? "No changes specified." : parts.joined(separator: " · ")
    }

    private func subtitleForListFilter(_ filter: String?) -> String {
        switch (filter ?? "active").lowercased() {
        case "completed": return "Completed only"
        case "all":       return "All reminders"
        default:          return "Active reminders"
        }
    }

    private func updateDetailLine(title: String?, due: Date?, notes: String?) -> String {
        var parts: [String] = []
        if title != nil { parts.append("title") }
        if let due {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
            parts.append("due \(f.string(from: due))")
        }
        if notes != nil { parts.append("notes") }
        return parts.isEmpty ? "No changes specified." : "Changing: \(parts.joined(separator: ", "))"
    }

    private func eventUpdateDetail(title: String?, start: Date?, end: Date?, notes: String?) -> String {
        var parts: [String] = []
        if title != nil { parts.append("title") }
        if let start {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
            parts.append("starts \(f.string(from: start))")
        }
        if let end {
            let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
            parts.append("ends \(f.string(from: end))")
        }
        if notes != nil { parts.append("notes") }
        return parts.isEmpty ? "No changes specified." : "Changing: \(parts.joined(separator: ", "))"
    }
}

// MARK: - Simple read-tool acknowledgement card
private struct ListSummaryCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Generic update/delete confirmation card
private struct MutationConfirmCard: View {
    let icon: String
    let color: Color
    let title: String
    let summary: String
    let detail: String
    let confirmLabel: String
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .tracking(0.6)
                    Text(summary)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isDark ? .white : .black)
                }
                Spacer()
            }
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
            ConfirmFooterShim(status: status, accentColor: accentColor,
                              confirmLabel: confirmLabel, onConfirm: onConfirm, onCancel: onCancel)
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

// Bridge to the file-private ConfirmFooter without exposing it. Same shape.
private struct ConfirmFooterShim: View {
    let status: ToolCall.Status
    let accentColor: Color
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var body: some View {
        Group {
            switch status {
            case .done:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("Done").font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .failed:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("Failed").font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .cancelled:
                HStack(spacing: 6) {
                    Image(systemName: "xmark").foregroundColor(.secondary)
                    Text("Cancelled").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .confirmed:
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 36)
            case .pending, .autoExecuted:
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button(action: onConfirm) {
                        Text(confirmLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: status)
    }
}

// MARK: - Shared confirm/cancel footer
private struct ConfirmFooter: View {
    let status: ToolCall.Status
    let accentColor: Color
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch status {
        case .done:
            label("Added", icon: "checkmark", color: .green)
        case .failed:
            label("Failed", icon: "exclamationmark.triangle.fill", color: .red)
        case .cancelled:
            label("Cancelled", icon: "xmark", color: .secondary)
        case .confirmed:
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .frame(height: 36)
        case .pending, .autoExecuted:
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.system(size: 13, weight: .bold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(color)
        .clipShape(Capsule())
    }
}

// MARK: - Food (enriched)
private struct FoodToolCard: View {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let serving: String
    let tags: [String]
    let highlights: [String]
    let cautions: [String]
    let isEstimate: Bool
    let confidence: String?
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    /// Visual signal to the user that the macros are model-guessed, not label-
    /// verified. Estimate macros render dimmed; the badge says what they are.
    private var estimateBadgeText: String? {
        guard isEstimate else { return nil }
        switch (confidence ?? "").lowercased() {
        case "low":    return "EST · LOW CONFIDENCE"
        case "medium": return "EST · ±20%"
        case "high":   return "EST · CLOSE"
        default:       return "ESTIMATE"
        }
    }

    private var macroOpacity: Double { isEstimate ? 0.7 : 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isDark ? .white : .black)
                if let badge = estimateBadgeText {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
                Spacer()
                if !serving.isEmpty {
                    Text(serving)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                }
            }

            // Tag capsules
            if !tags.isEmpty {
                FlexibleHStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accentColor.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
            }

            // Macros grid (dimmed when estimated — clearer "these are guesses" signal).
            HStack(spacing: 12) {
                macro("KCAL", String(format: "%.0f", calories), .orange)
                macro("PROTEIN", gramString(protein), .red)
                macro("CARBS", gramString(carbs), .yellow)
                macro("FAT", gramString(fat), .purple)
            }
            .opacity(macroOpacity)

            // Highlights (positive bullet list)
            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(highlights, id: \.self) { h in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                            Text(inlineMD(h))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Cautions (warnings)
            if !cautions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cautions, id: \.self) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                            Text(inlineMD(c))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            ConfirmFooter(status: status, accentColor: accentColor,
                          confirmLabel: "Add to today's diet",
                          onConfirm: onConfirm, onCancel: onCancel)
        }
        .padding(14).frame(maxWidth: 320)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func gramString(_ v: Double) -> String {
        v >= 10 ? String(format: "%.0fg", v) : String(format: "%.1fg", v)
    }
    private func macro(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color).tracking(0.4)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : .black).tracking(-0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget preview confirm card

/// Confirm card that renders the actual AstraWidgetTile as a live preview,
/// identical to how it appears on the Home screen. Replaces the generic
/// text-summary confirm card for create_widget and update_widget.
private struct WidgetPreviewConfirmCard: View {
    let previewWidget: AstraWidget
    let headerTitle: String
    let confirmLabel: String
    let doneLabel: String
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var hk = HealthKitManager.shared
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    private var color: Color { toolColor(name: previewWidget.colorName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: previewWidget.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(headerTitle.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                Spacer()
                if status == .done {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                        Text(doneLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }

            // Live widget tile — same component as the Home Astra Studio card
            AstraWidgetTile(widget: previewWidget, hk: hk)

            // Confirm/cancel buttons (hidden once terminal)
            switch status {
            case .pending, .autoExecuted, .confirmed:
                ConfirmFooterShim(status: status, accentColor: accentColor,
                                  confirmLabel: confirmLabel,
                                  onConfirm: onConfirm, onCancel: onCancel)
            case .failed:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("Failed to pin").font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                }
            case .cancelled:
                HStack(spacing: 6) {
                    Image(systemName: "xmark").foregroundColor(.secondary)
                    Text("Cancelled").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                }
            case .done:
                EmptyView()
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

// Simple wrapping HStack used by tag capsules
private struct FlexibleHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        // SwiftUI doesn't ship a built-in wrapping HStack pre-iOS 16; iOS 16+
        // Layout-based wrap. We'll just use a HStack with .fixedSize and let it overflow
        // since tag counts are small.
        FlowLayout(spacing: spacing) { content() }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        return CGSize(width: maxWidth, height: totalHeight + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Comparison chart (auto-execute)
private struct ComparisonChartToolCard: View {
    let metric: String
    let periodA: String
    let periodB: String
    let title: String?
    let accentColor: Color

    @ObservedObject private var hk = HealthKitManager.shared
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var metricType: HealthMetricType? {
        switch metric.lowercased() {
        case "steps": return .steps
        case "heart_rate", "heart": return .heartRate
        case "sleep": return .sleep
        case "active_energy", "calories": return .activeEnergy
        case "distance": return .distance
        case "hrv": return .hrv
        case "hydration", "water": return .hydration
        default: return nil
        }
    }
    private var color: Color { metricType?.themeColor ?? accentColor }

    /// Resolves a period name to a date range (start...end inclusive).
    private func resolve(_ period: String) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func days(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: today) ?? today }
        switch period.lowercased() {
        case "today":             return (today, today)
        case "yesterday":         return (days(1), days(1))
        case "this_week":         return (days(6), today)
        case "last_week":         return (days(13), days(7))
        case "last_7_days":       return (days(6), today)
        case "previous_7_days":   return (days(13), days(7))
        case "this_month":        return (days(29), today)
        case "last_month":        return (days(59), days(30))
        default:                  return (days(6), today)
        }
    }

    private func values(for period: String) -> [Double] {
        guard let t = metricType, let s = hk.metricSummaries[t] else { return [] }
        let (start, end) = resolve(period)
        return s.history.filter { $0.date >= start && $0.date <= end }.map { $0.value }
    }
    private func avg(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private func label(for period: String) -> String {
        period.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        let aValues = values(for: periodA)
        let bValues = values(for: periodB)
        let aAvg = avg(aValues)
        let bAvg = avg(bValues)
        let delta = bAvg == 0 ? 0 : ((aAvg - bAvg) / bAvg) * 100
        let unit = metricType?.unit ?? ""

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title ?? "\(metricType?.displayName ?? metric.capitalized) · \(label(for: periodA)) vs \(label(for: periodB))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }

            // Two stacked bar groups, side by side, scaled relative to max
            let maxAll = max(aValues.max() ?? 0, bValues.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 14) {
                seriesBars(values: aValues, color: color, max: maxAll, label: label(for: periodA), avg: aAvg, unit: unit)
                seriesBars(values: bValues, color: color.opacity(0.4), max: maxAll, label: label(for: periodB), avg: bAvg, unit: unit)
            }
            .frame(height: 80)

            // Delta callout
            HStack(spacing: 6) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(delta >= 0 ? .green : .red)
                Text(String(format: "%@%.0f%% vs %@", delta >= 0 ? "+" : "", delta, label(for: periodB)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(delta >= 0 ? .green : .red)
            }
        }
        .padding(14).frame(maxWidth: 320)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func seriesBars(values: [Double], color: Color, max: Double, label: String, avg: Double, unit: String) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                if values.isEmpty {
                    Text("—").foregroundColor(.secondary).font(.system(size: 13))
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: 7, height: CGFloat(v / max) * 60)
                    }
                }
            }
            .frame(height: 60, alignment: .bottom)
            VStack(spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .tracking(0.3)
                Text("\(formatNumber(avg)) \(unit)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatNumber(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        if v >= 100 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

// MARK: - Reminder
private struct ReminderToolCard: View {
    let title: String
    let dueAt: Date?
    let category: String?
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var categoryColor: Color {
        switch category?.lowercased() {
        case "workout": return .green
        case "hydration": return .cyan
        case "supplement": return .orange
        case "sleep": return .purple
        default: return accentColor
        }
    }

    private var dueText: String {
        guard let d = dueAt else { return "No due date" }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .foregroundColor(categoryColor)
                Text("New reminder")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(categoryColor).tracking(0.4)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(inlineMD(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dueText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            ConfirmFooter(status: status, accentColor: accentColor,
                          confirmLabel: "Add reminder",
                          onConfirm: onConfirm, onCancel: onCancel)
        }
        .padding(14).frame(maxWidth: 290)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

// MARK: - Calendar event
private struct EventToolCard: View {
    let title: String
    let startsAt: Date
    let endsAt: Date
    let notes: String?
    let status: ToolCall.Status
    let accentColor: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var rangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        let t = DateFormatter(); t.timeStyle = .short
        return "\(f.string(from: startsAt)) – \(t.string(from: endsAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.blue)
                Text("New event")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue).tracking(0.4)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(inlineMD(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rangeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                if let n = notes, !n.isEmpty {
                    Text(inlineMD(n))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ConfirmFooter(status: status, accentColor: accentColor,
                          confirmLabel: "Add to calendar",
                          onConfirm: onConfirm, onCancel: onCancel)
        }
        .padding(14).frame(maxWidth: 290)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

// MARK: - Metric chart (auto-execute, reads HealthKitManager)
private struct MetricChartToolCard: View {
    let metric: String
    let days: Int
    let accentColor: Color

    @ObservedObject private var hk = HealthKitManager.shared
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var metricType: HealthMetricType? {
        switch metric.lowercased() {
        case "steps": return .steps
        case "heart_rate", "heart": return .heartRate
        case "sleep": return .sleep
        case "active_energy", "calories": return .activeEnergy
        case "distance": return .distance
        case "hrv": return .hrv
        case "hydration", "water": return .hydration
        default: return nil
        }
    }

    private var color: Color { metricType?.themeColor ?? accentColor }
    private var displayName: String { metricType?.displayName ?? metric.capitalized }
    private var unit: String { metricType?.unit ?? "" }

    private var values: [Double] {
        guard let t = metricType, let summary = hk.metricSummaries[t] else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return summary.history.filter { $0.date >= cutoff }.suffix(days).map { $0.value }
    }
    private var average: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text("\(displayName) · last \(days) days")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text("avg \(format(average)) \(unit)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            if values.isEmpty {
                Text("No data yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                SparkChart(values: values, color: color, dots: true)
                    .frame(height: 64)
            }
        }
        .padding(14).frame(maxWidth: 290)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func format(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 10  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Custom card (auto-execute)
private struct CustomToolCard: View {
    let title: String
    let icon: String
    let colorName: String
    let headline: String?
    let bullets: [String]
    let stats: [ToolCall.Stat]
    let accentColor: Color

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var color: Color {
        switch colorName.lowercased() {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "accent": return accentColor
        default: return accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                Spacer()
            }
            if let headline {
                Text(inlineMD(headline))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, b in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(color).frame(width: 5, height: 5)
                            Text(inlineMD(b))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !stats.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(color).tracking(0.4)
                            Text(s.value)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(isDark ? .white : .black)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: 290)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}
