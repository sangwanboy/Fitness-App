import SwiftUI

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Home card that renders the user's pinned Astra widgets. Wide. Empty
/// state hidden by the existing empty-card rule (`hasData("widgets")`).
/// Tap a widget → bottom sheet with full body + "Remove" / "Ask Astra"
/// actions.
public struct WidgetsCard: View {
    @ObservedObject private var store = AstraWidgetStore.shared
    @ObservedObject private var hk = HealthKitManager.shared

    /// Parent callback to switch into Coach after queuing a follow-up prompt
    /// (e.g. "remove this widget"). Mirrors how PredictionsCard hands off.
    public var onAskAstra: (() -> Void)? = nil

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var selectedWidget: AstraWidget? = nil

    public init(onAskAstra: (() -> Void)? = nil) {
        self.onAskAstra = onAskAstra
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.widgets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white.opacity(0.25))
                    Text("No widgets yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Ask Astra to pin a widget to your Home.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(store.widgets.enumerated()), id: \.element.id) { idx, widget in
                        Group {
                            if widget.isInteractive {
                                // Interactive widgets (checklist / action buttons): no
                                // outer navigate-button, so the inner controls receive
                                // taps directly. A tap on the tile background still opens
                                // the detail sheet (for delete / refine).
                                AstraWidgetTile(widget: widget, hk: hk, onCoachPrompt: handleCoachPrompt)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedWidget = widget }
                            } else {
                                Button(action: { selectedWidget = widget }) {
                                    AstraWidgetTile(widget: widget, hk: hk, onCoachPrompt: handleCoachPrompt)
                                }
                                .buttonStyle(TilePressStyle())
                            }
                        }
                        .accessibilityLabel(widget.title)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.spring(response: 0.38, dampingFraction: 0.82).delay(Double(idx) * 0.05), value: store.widgets.count)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .sheet(item: $selectedWidget) { widget in
            WidgetDetailSheet(widget: widget,
                              onRemove: { store.remove(id: widget.id); selectedWidget = nil },
                              onAskAstra: { prompt in
                                  ChatPrefillBus.shared.queue(prompt)
                                  selectedWidget = nil
                                  onAskAstra?()
                              })
        }
    }

    /// Queue a follow-up prompt to Astra and hop to the Coach tab. Wired into
    /// every interactive widget's `coach_prompt` action buttons.
    private func handleCoachPrompt(_ prompt: String) {
        ChatPrefillBus.shared.queue(prompt)
        onAskAstra?()
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("ASTRA STUDIO")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            Spacer()
            Text("\(store.widgets.count)/\(AstraWidgetStore.maxWidgets)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
    }
}

// MARK: - One widget tile

struct AstraWidgetTile: View {
    let widget: AstraWidget
    @ObservedObject var hk: HealthKitManager
    var onCoachPrompt: (String) -> Void = { _ in }

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var color: Color { toolColor(name: widget.colorName) }

    /// Live widgets get a subtle pulsing icon. Static widgets stay still.
    private var iconShouldPulse: Bool {
        if widget.isComposed { return widget.metricRef != nil || (widget.blocks ?? []).contains(where: { hasLiveBinding($0) }) }
        return widget.metricRef != nil
    }

    private func hasLiveBinding(_ block: WidgetBlock) -> Bool {
        switch block {
        case .metricValue(let mr, _, _, _): return (mr ?? "").isEmpty == false
        case .ring(let mr, _, _, _):        return (mr ?? "").isEmpty == false
        case .sparkline, .miniBars, .comparison, .delta: return true
        default: return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: widget.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .symbolEffect(.pulse.byLayer, options: iconShouldPulse ? .repeating : .nonRepeating, value: iconShouldPulse)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(widget.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                if widget.isComposed, let blocks = widget.blocks {
                    composedContent(blocks: blocks)
                } else {
                    content
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private func composedContent(blocks: [WidgetBlock]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ComposedBlockView(block: block, color: color, hk: hk,
                                  widgetID: widget.id, onCoachPrompt: onCoachPrompt)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widget.layout {
        case .kpi:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayHeadline)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                if let unit = liveUnit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
            if let body = widget.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.75))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .narrative:
            if let h = widget.headline, !h.isEmpty {
                Text(h)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let b = widget.body, !b.isEmpty {
                Text(b)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.78) : .black.opacity(0.78))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .list:
            ForEach(Array(widget.bullets.prefix(5).enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(bullet)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .progress:
            let liveVal = liveMetricValue
            let value: Double = liveVal ?? Double(widget.headline ?? "") ?? 0
            let goal = max(widget.goalValue ?? 1, 0.001)
            let pct = min(value / goal, 1.0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatNum(value))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text("/ \(formatNum(goal))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                if let unit = liveUnit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 5)
            if let b = widget.body, !b.isEmpty {
                Text(b)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .composed:
            // Composed widgets are dispatched above via `composedContent` —
            // never reached here, but the switch must be exhaustive.
            EmptyView()
        }
    }

    // MARK: - Live metric binding

    /// Headline shown in kpi layout — prefers the LLM's literal copy, but
    /// falls through to the live HK value when `metric_ref` is set and the
    /// LLM left headline blank.
    private var displayHeadline: String {
        if let h = widget.headline, !h.isEmpty { return h }
        if let v = liveMetricValue { return formatNum(v) }
        return "—"
    }

    /// Unit suffix when this widget is bound to a live HK metric.
    private var liveUnit: String? {
        guard let m = metricType(for: widget.metricRef) else { return nil }
        return m.unit
    }

    /// Resolve `widget.metricRef` to a current HK value. Returns nil for
    /// non-metric refs (health_meter / recovery_score handled separately).
    private var liveMetricValue: Double? {
        guard let ref = widget.metricRef?.lowercased(), !ref.isEmpty else { return nil }
        switch ref {
        case "health_meter":
            return hk.predictions?.healthMeter.map { Double($0.score) }
        case "recovery_score":
            return hk.predictions?.recovery.map { Double($0.score) }
        default:
            guard let t = metricType(for: ref) else { return nil }
            return hk.metricSummaries[t]?.currentValue
        }
    }

    private func metricType(for ref: String?) -> HealthMetricType? {
        guard let ref = ref?.lowercased() else { return nil }
        switch ref {
        case "steps":               return .steps
        case "heart_rate":          return .heartRate
        case "active_energy":       return .activeEnergy
        case "resting_energy":      return .restingEnergy
        case "sleep":               return .sleep
        case "distance":            return .distance
        case "hydration":           return .hydration
        case "hrv":                 return .hrv
        case "resting_hr":          return .restingHeartRate
        case "exercise_minutes":    return .exerciseMinutes
        case "stand_hours":         return .standHours
        case "mindful_minutes":     return .mindfulMinutes
        case "flights":             return .flightsClimbed
        case "vo2_max":             return .vo2Max
        case "walking_speed":       return .walkingSpeed
        case "step_length":         return .walkingStepLength
        case "body_mass":           return .bodyMass
        default: return nil
        }
    }

    private func formatNum(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.1fk", v / 1000) }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

// MARK: - Detail sheet

private struct WidgetDetailSheet: View {
    let widget: AstraWidget
    let onRemove: () -> Void
    let onAskAstra: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    private var color: Color { toolColor(name: widget.colorName) }

    @ObservedObject private var hk = HealthKitManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(color.opacity(0.18)).frame(width: 44, height: 44)
                        Image(systemName: widget.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(widget.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(isDark ? .white : .black)
                        Text(widget.layout.rawValue.capitalized + (widget.metricRef.map { " · live \($0)" } ?? ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                    Spacer()
                }

                AstraWidgetTile(widget: widget, hk: hk, onCoachPrompt: { onAskAstra($0) })

                VStack(spacing: 10) {
                    Button {
                        onAskAstra("Update the \"\(widget.title)\" widget on my Home — refine the wording or layout.")
                    } label: {
                        actionRow(icon: "wand.and.stars", color: .indigo,
                                  title: "Refine in Coach",
                                  subtitle: "Ask Astra to rewrite or change the layout")
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAskAstra("Pin a new widget to Home related to my \(widget.title.lowercased()) — make it different and useful.")
                    } label: {
                        actionRow(icon: "plus.square.on.square", color: .purple,
                                  title: "Ask for another one",
                                  subtitle: "Let Astra design a companion widget")
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        actionRow(icon: "trash.fill", color: .red,
                                  title: "Remove widget",
                                  subtitle: "Astra can pin a new one any time")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(AdaptiveBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func actionRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.indigo)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Composable block renderer + shared helpers

/// Top-level dispatcher for one block inside a composed widget. Delegates
/// to a per-block view; the wrapper exists so the parent tile can iterate
/// `ForEach` without a giant switch inline.
struct ComposedBlockView: View {
    let block: WidgetBlock
    let color: Color
    @ObservedObject var hk: HealthKitManager
    var widgetID: UUID = UUID()
    var onCoachPrompt: (String) -> Void = { _ in }

    var body: some View {
        switch block {
        case .metricValue(let mr, let v, let l, let u):
            MetricValueBlockView(metricRef: mr, value: v, label: l, unit: u,
                                 color: color, hk: hk)
        case .ring(let mr, let cur, let g, let l):
            RingBlockView(metricRef: mr, current: cur, goalValue: g, label: l,
                          color: color, hk: hk)
        case .sparkline(let mr, let d):
            SparklineBlockView(metricRef: mr, days: d, color: color, hk: hk)
        case .miniBars(let mr, let d):
            MiniBarsBlockView(metricRef: mr, days: d, color: color, hk: hk)
        case .comparison(let mr, let pa, let pb, let la, let lb):
            ComparisonBlockView(metricRef: mr, periodA: pa, periodB: pb,
                                labelA: la, labelB: lb, color: color, hk: hk)
        case .delta(let mr, let vs):
            DeltaBlockView(metricRef: mr, vsDays: vs, color: color, hk: hk)
        case .bullets(let items):
            BulletsBlockView(items: items, color: color)
        case .text(let s):
            TextBlockView(text: s)
        case .chipRow(let chips):
            ChipRowBlockView(chips: chips, color: color)
        case .quote(let s):
            QuoteBlockView(text: s, color: color)
        case .checklist(let items):
            ChecklistBlockView(widgetID: widgetID, items: items, color: color)
        case .buttonRow(let btns):
            ButtonRowBlockView(buttons: btns, color: color, onCoachPrompt: onCoachPrompt)
        }
    }
}

// MARK: - Interactive blocks (checklist + action buttons)

/// Tappable to-do checklist. Reads live item state from the store so a tap
/// reflects immediately and persists across launches.
private struct ChecklistBlockView: View {
    let widgetID: UUID
    let items: [ChecklistItem]
    let color: Color

    @ObservedObject private var store = AstraWidgetStore.shared
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    /// Prefer the live items from the store (so a toggle updates instantly and
    /// persists); fall back to the passed-in snapshot for confirm-card previews
    /// where the widget isn't in the store yet.
    private var liveItems: [ChecklistItem] {
        if let w = store.widgets.first(where: { $0.id == widgetID }), let blocks = w.blocks {
            for b in blocks { if case .checklist(let its) = b { return its } }
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(liveItems) { item in
                Button {
                    store.toggleChecklistItem(widgetID: widgetID, itemID: item.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(item.done ? color : (isDark ? .white.opacity(0.4) : .black.opacity(0.4)))
                        Text(item.text)
                            .font(.system(size: 12, weight: .regular))
                            .strikethrough(item.done, color: isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                            .foregroundColor(item.done
                                ? (isDark ? .white.opacity(0.4) : .black.opacity(0.4))
                                : (isDark ? .white.opacity(0.85) : .black.opacity(0.85)))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: liveItems)
    }
}

/// Row of Astra-authored action buttons. Each does something real: send a
/// follow-up prompt to the Coach, or log water to Apple Health.
private struct ButtonRowBlockView: View {
    let buttons: [WidgetButton]
    let color: Color
    let onCoachPrompt: (String) -> Void

    @State private var loggedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 6) {
            ForEach(buttons) { btn in
                Button {
                    perform(btn)
                } label: {
                    HStack(spacing: 6) {
                        if let icon = btn.icon, !icon.isEmpty {
                            Image(systemName: loggedIDs.contains(btn.id) ? "checkmark" : icon)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(loggedIDs.contains(btn.id) ? "Logged" : btn.label)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform(_ btn: WidgetButton) {
        switch btn.action {
        case "log_water":
            let ml = Double(btn.value ?? "250") ?? 250
            Task {
                let ok = await HealthKitManager.shared.logMetricValue(type: .hydration, value: ml / 1000.0)
                if ok { withAnimation { _ = loggedIDs.insert(btn.id) } }
            }
        case "coach_prompt":
            onCoachPrompt(btn.value ?? btn.label)
        default:
            // Unknown action — still do something useful rather than nothing.
            onCoachPrompt(btn.value ?? btn.label)
        }
    }
}

/// Maps a widget `metric_ref` string to the live HK value + unit + 30-day
/// history. Shared by every block that binds to live data so the lookup
/// logic lives in one place. MainActor because all the HK reads it does
/// touch the @MainActor `HealthKitManager` singleton.
@MainActor
enum WidgetMetric {
    static func metricType(for ref: String?) -> HealthMetricType? {
        guard let ref = ref?.lowercased() else { return nil }
        switch ref {
        case "steps":               return .steps
        case "heart_rate":          return .heartRate
        case "active_energy":       return .activeEnergy
        case "resting_energy":      return .restingEnergy
        case "sleep":               return .sleep
        case "distance":            return .distance
        case "hydration":           return .hydration
        case "hrv":                 return .hrv
        case "resting_hr":          return .restingHeartRate
        case "exercise_minutes":    return .exerciseMinutes
        case "stand_hours":         return .standHours
        case "mindful_minutes":     return .mindfulMinutes
        case "flights":             return .flightsClimbed
        case "vo2_max":             return .vo2Max
        case "walking_speed":       return .walkingSpeed
        case "step_length":         return .walkingStepLength
        case "body_mass":           return .bodyMass
        default: return nil
        }
    }

    static func currentValue(ref: String?, hk: HealthKitManager) -> Double? {
        guard let ref = ref?.lowercased(), !ref.isEmpty else { return nil }
        switch ref {
        case "health_meter":  return hk.predictions?.healthMeter.map { Double($0.score) }
        case "recovery_score": return hk.predictions?.recovery.map { Double($0.score) }
        default:
            guard let t = metricType(for: ref) else { return nil }
            return hk.metricSummaries[t]?.currentValue
        }
    }

    static func unit(ref: String?) -> String? {
        guard let t = metricType(for: ref) else { return nil }
        return t.unit
    }

    /// Last N daily values (oldest → newest, zero-filled for empty days).
    static func history(ref: String?, days: Int, hk: HealthKitManager) -> [Double] {
        guard let t = metricType(for: ref) else { return [] }
        guard let h = hk.metricSummaries[t]?.history else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for v in h {
            byDay[cal.startOfDay(for: v.date), default: 0] += v.value
        }
        var out: [Double] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            out.append(byDay[d] ?? 0)
        }
        return out
    }

    static func formatNum(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.1fk", v / 1000) }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

// MARK: Number that ramps from 0 → target on appear

private struct RampingNumber: View {
    let target: Double
    let font: Font
    let color: Color
    var unit: String? = nil
    var unitColor: Color = .gray.opacity(0.6)

    @State private var displayed: Double = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(WidgetMetric.formatNum(displayed))
                .font(font)
                .foregroundColor(color)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(unitColor)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                displayed = target
            }
        }
        .onChange(of: target) { _, newTarget in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                displayed = newTarget
            }
        }
    }
}

// MARK: - metric_value block

private struct MetricValueBlockView: View {
    let metricRef: String?
    let value: Double?
    let label: String?
    let unit: String?
    let color: Color
    @ObservedObject var hk: HealthKitManager

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    private var resolvedValue: Double {
        if let v = value { return v }
        return WidgetMetric.currentValue(ref: metricRef, hk: hk) ?? 0
    }
    private var resolvedUnit: String? {
        unit ?? WidgetMetric.unit(ref: metricRef)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label, !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }
            RampingNumber(target: resolvedValue,
                          font: .system(size: 26, weight: .bold, design: .rounded),
                          color: isDark ? .white : .black,
                          unit: resolvedUnit,
                          unitColor: isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
    }
}

// MARK: - ring block

private struct RingBlockView: View {
    let metricRef: String?
    let current: Double?
    let goalValue: Double?
    let label: String?
    let color: Color
    @ObservedObject var hk: HealthKitManager

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var fillProgress: CGFloat = 0

    private var resolvedCurrent: Double {
        current ?? WidgetMetric.currentValue(ref: metricRef, hk: hk) ?? 0
    }
    private var resolvedGoal: Double {
        max(goalValue ?? 1, 0.001)
    }
    private var target: CGFloat {
        CGFloat(min(resolvedCurrent / resolvedGoal, 1.0))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 7)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: fillProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(target * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.75))
                }
                Text("\(WidgetMetric.formatNum(resolvedCurrent)) / \(WidgetMetric.formatNum(resolvedGoal))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(isDark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.1)) {
                fillProgress = target
            }
        }
        .onChange(of: target) { _, newTarget in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                fillProgress = newTarget
            }
        }
    }
}

// MARK: - sparkline block

private struct SparklineBlockView: View {
    let metricRef: String
    let days: Int
    let color: Color
    @ObservedObject var hk: HealthKitManager

    @State private var drawProgress: CGFloat = 0

    private var values: [Double] {
        let v = WidgetMetric.history(ref: metricRef, days: days, hk: hk)
        return v.isEmpty ? Array(repeating: 0, count: max(days, 1)) : v
    }

    var body: some View {
        GeometryReader { geo in
            let maxV = values.max() ?? 1
            let minV = values.min() ?? 0
            let range = max(maxV - minV, 0.0001)
            let w = geo.size.width
            let h = geo.size.height
            let pts: [CGPoint] = values.enumerated().map { (i, v) in
                CGPoint(x: w * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: h - h * CGFloat((v - minV) / range))
            }
            let smoothCurve = Path.smoothLine(through: pts)
            let fillPath: Path = {
                guard let first = pts.first, let last = pts.last else { return Path() }
                var p = smoothCurve
                p.addLine(to: CGPoint(x: last.x, y: h))
                p.addLine(to: CGPoint(x: first.x, y: h))
                p.closeSubpath()
                return p
            }()
            ZStack {
                // baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(color.opacity(0.12), lineWidth: 1)

                // area fill under smooth curve
                fillPath
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .mask(Rectangle().frame(width: w * drawProgress, height: h).offset(x: -w * (1 - drawProgress) / 2))

                // smooth line with draw-in animation
                smoothCurve
                    .trim(from: 0, to: drawProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 36)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { drawProgress = 1 }
        }
    }
}

// MARK: - mini_bars block

private struct MiniBarsBlockView: View {
    let metricRef: String
    let days: Int
    let color: Color
    @ObservedObject var hk: HealthKitManager

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var heightScale: CGFloat = 0

    private var values: [Double] {
        WidgetMetric.history(ref: metricRef, days: days, hk: hk)
    }
    private var nonZero: [Double] { values.filter { $0 > 0 } }
    private var avg: Double { nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count) }
    private var maxV: Double { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                let frac = CGFloat(v / maxV)
                let aboveAvg = v > avg && avg > 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(v == 0 ? Color.gray.opacity(0.2)
                          : (aboveAvg ? color : color.opacity(0.55)))
                    .frame(height: max(2, 32 * frac * heightScale))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(idx) * 0.04), value: heightScale)
            }
        }
        .frame(height: 32)
        .onAppear { heightScale = 1 }
    }
}

// MARK: - comparison block

private struct ComparisonBlockView: View {
    let metricRef: String
    let periodA: Int
    let periodB: Int
    let labelA: String?
    let labelB: String?
    let color: Color
    @ObservedObject var hk: HealthKitManager

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    @State private var animatedScale: CGFloat = 0

    private var values: [Double] {
        WidgetMetric.history(ref: metricRef, days: periodA + periodB, hk: hk)
    }
    private var sumA: Double {
        Array(values.suffix(periodA)).reduce(0, +) / Double(max(periodA, 1))
    }
    private var sumB: Double {
        Array(values.prefix(periodB)).reduce(0, +) / Double(max(periodB, 1))
    }
    private var pct: Double {
        guard sumB > 0 else { return 0 }
        return (sumA - sumB) / sumB * 100
    }

    var body: some View {
        HStack(spacing: 14) {
            barPair(value: sumA, label: labelA ?? "Recent", emphasised: true)
            barPair(value: sumB, label: labelB ?? "Prior", emphasised: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(pct >= 0 ? "+\(String(format: "%.0f", pct))%" : "\(String(format: "%.0f", pct))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(pct >= 0 ? .green : .red)
                Text("vs")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
            }
        }
        .frame(height: 40)
        .onAppear { animatedScale = 1 }
    }

    private func barPair(value: Double, label: String, emphasised: Bool) -> some View {
        let maxV = max(max(sumA, sumB), 1)
        let frac = CGFloat(value / maxV) * animatedScale
        return VStack(alignment: .leading, spacing: 3) {
            Text(WidgetMetric.formatNum(value))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(emphasised ? color : (isDark ? .white.opacity(0.7) : .black.opacity(0.7)))
                .monospacedDigit()
            Capsule()
                .fill(emphasised ? color : color.opacity(0.4))
                .frame(width: 36 * max(frac, 0.05), height: 6)
                .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(emphasised ? 0.05 : 0.15), value: animatedScale)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
    }
}

// MARK: - delta chip block

private struct DeltaBlockView: View {
    let metricRef: String
    let vsDays: Int
    let color: Color
    @ObservedObject var hk: HealthKitManager

    private var values: [Double] {
        WidgetMetric.history(ref: metricRef, days: vsDays + 1, hk: hk)
    }
    private var current: Double {
        WidgetMetric.currentValue(ref: metricRef, hk: hk) ?? values.last ?? 0
    }
    private var baseline: Double {
        let prior = Array(values.dropLast()).filter { $0 > 0 }
        guard !prior.isEmpty else { return 0 }
        return prior.reduce(0, +) / Double(prior.count)
    }
    private var pct: Double {
        guard baseline > 0 else { return 0 }
        return (current - baseline) / baseline * 100
    }

    var body: some View {
        let up = pct >= 0
        HStack(spacing: 4) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
            Text("\(up ? "+" : "")\(String(format: "%.0f", pct))% vs last \(vsDays)d")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(up ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((up ? Color.green : Color.red).opacity(0.12))
        )
    }
}

// MARK: - bullets / text / chips / quote

private struct BulletsBlockView: View {
    let items: [String]
    let color: Color
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(color).frame(width: 4, height: 4).padding(.top, 6)
                    Text(b)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct TextBlockView: View {
    let text: String
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(isDark ? .white.opacity(0.78) : .black.opacity(0.78))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChipRowBlockView: View {
    let chips: [String]
    let color: Color
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                    Text(c)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
        }
    }
}

private struct QuoteBlockView: View {
    let text: String
    let color: Color
    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle().fill(color.opacity(0.5)).frame(width: 2)
            Text("“\(text)”")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
