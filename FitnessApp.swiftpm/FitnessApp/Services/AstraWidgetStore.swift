import SwiftUI

/// Persistent store of Astra-authored widgets pinned to Home. Singleton so
/// the Widget Studio tools (Coach) and the WidgetsCard (Home) read from the
/// same source. Storage: a single JSON-encoded blob in UserDefaults — small
/// payloads, infrequent writes, no DB worth the complexity.
@MainActor
public final class AstraWidgetStore: ObservableObject {
    public static let shared = AstraWidgetStore()

    /// Hard cap so Home doesn't sprawl. Astra is told about this in the
    /// system prompt so it can prune via `delete_widget` before adding more.
    public static let maxWidgets = 6

    private static let storageKey = "astra_widgets_v1"

    @Published public private(set) var widgets: [AstraWidget] = []

    private init() {
        load()
    }

    public func add(_ widget: AstraWidget) -> Bool {
        // Replace by id when an update comes through `add` (defensive); else
        // append. Enforce cap by dropping the oldest (createdAt asc) when full.
        if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
            widgets[idx] = widget
        } else {
            if widgets.count >= Self.maxWidgets {
                if let oldest = widgets.sorted(by: { $0.createdAt < $1.createdAt }).first {
                    widgets.removeAll { $0.id == oldest.id }
                }
            }
            widgets.append(widget)
        }
        save()
        return true
    }

    /// Update a widget by id. nil fields preserve existing values so partial
    /// edits (just change the color, just rewrite the body, just swap the
    /// blocks) work cleanly.
    public func update(id: UUID,
                       title: String?,
                       icon: String?,
                       colorName: String?,
                       layout: WidgetLayout?,
                       headline: String?,
                       body: String?,
                       bullets: [String]?,
                       metricRef: String?,
                       goalValue: Double?,
                       blocks: [WidgetBlock]?) -> Bool {
        guard let idx = widgets.firstIndex(where: { $0.id == id }) else { return false }
        var w = widgets[idx]
        if let title { w.title = title }
        if let icon { w.icon = icon }
        if let colorName { w.colorName = colorName }
        // Apply layout first — if switching away from composed, clear orphaned blocks
        // so the widget doesn't render stale block data under a legacy layout.
        if let layout {
            w.layout = layout
            if layout != .composed { w.blocks = nil }
        }
        if let headline { w.headline = headline }
        if let body { w.body = body }
        if let bullets { w.bullets = bullets }
        if let metricRef { w.metricRef = metricRef.isEmpty ? nil : metricRef }
        if let goalValue { w.goalValue = goalValue }
        // Blocks applied after layout: providing blocks always promotes to composed
        // so the renderer doesn't fall through to a mismatched legacy layout.
        if let blocks {
            w.blocks = blocks.isEmpty ? nil : blocks
            if !blocks.isEmpty { w.layout = .composed }
        }
        widgets[idx] = w
        save()
        return true
    }

    public func remove(id: UUID) -> Bool {
        let before = widgets.count
        widgets.removeAll { $0.id == id }
        let removed = widgets.count < before
        if removed { save() }
        return removed
    }

    public func removeAll() {
        widgets.removeAll()
        save()
    }

    /// Find a widget by id string (UUID's uuidString form). Used by tool
    /// argument parsing where ids round-trip through JSON.
    public func widget(idString: String) -> AstraWidget? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return widgets.first { $0.id == uuid }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([AstraWidget].self, from: data) else { return }
        widgets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
