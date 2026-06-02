import Foundation

/// One Astra-authored widget pinned to the user's Home. There are two ways
/// the LLM can author a widget:
///
/// 1. **Legacy preset** — pick a `WidgetLayout` (kpi / narrative / list /
///    progress) and fill in headline / body / bullets / metricRef. Renders
///    via the original simple layouts.
///
/// 2. **Composable blocks** — emit a `blocks` array. Each block is one
///    primitive (metric_value, ring, sparkline, mini_bars, comparison, delta,
///    bullets, text, chip_row, quote). Astra picks 2-4 and orders them.
///    When `blocks` is non-nil, the renderer ignores the legacy preset
///    fields and renders the composed list with animations.
public struct AstraWidget: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var icon: String                 // SF Symbol name
    public var colorName: String            // accent | red | orange | yellow | green | blue | indigo | purple | pink | cyan | gray
    public var layout: WidgetLayout
    public var headline: String?            // single short line (kpi value, narrative hook)
    public var body: String?                // longer prose (narrative, progress description)
    public var bullets: [String]            // list layout
    public var metricRef: String?           // optional live binding (see knownMetricRefs)
    public var goalValue: Double?           // progress layout — denominator
    public var blocks: [WidgetBlock]?       // composable mode — when set, supersedes legacy layout fields
    public var createdAt: Date

    public init(id: UUID = UUID(),
                title: String,
                icon: String,
                colorName: String,
                layout: WidgetLayout,
                headline: String? = nil,
                body: String? = nil,
                bullets: [String] = [],
                metricRef: String? = nil,
                goalValue: Double? = nil,
                blocks: [WidgetBlock]? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorName = colorName
        self.layout = layout
        self.headline = headline
        self.body = body
        self.bullets = bullets
        self.metricRef = metricRef
        self.goalValue = goalValue
        self.blocks = blocks
        self.createdAt = createdAt
    }

    /// True when this widget should render through the composable block path.
    public var isComposed: Bool { (blocks?.isEmpty == false) }

    /// Metric refs the widget can bind to for live values. Anything outside
    /// this set is ignored at render time. Keeps the LLM's creativity bounded
    /// to data we can actually surface.
    public static let knownMetricRefs: [String] = [
        "steps", "heart_rate", "active_energy", "resting_energy", "sleep",
        "distance", "hydration", "hrv", "resting_hr", "exercise_minutes",
        "stand_hours", "mindful_minutes", "flights", "vo2_max",
        "walking_speed", "step_length", "body_mass",
        "health_meter", "recovery_score"
    ]
}

public enum WidgetLayout: String, Codable {
    /// Big number with an optional caption beneath. Best for KPIs the user
    /// glances at — current streak, days until goal, sleep hours, etc.
    case kpi
    /// Headline + body paragraph. Best for short narrative observations
    /// ("You've been most consistent on Tuesdays — keep stacking those reps").
    case narrative
    /// Up to 5 bullets. Best for short lists ("This week's wins" / "Watch outs").
    case list
    /// Value + goal + progress bar. Best for ongoing trackers
    /// ("Bedtime consistency: 4 of 7 nights before 11 PM").
    case progress
    /// Sentinel used when the widget is rendered from `blocks` instead of
    /// the legacy preset fields.
    case composed
}

// MARK: - Composable block primitives

/// One primitive in a composed widget. Astra picks 2-4 of these per widget
/// and orders them however she likes — that's where the visual variety
/// comes from compared to the legacy 4-layout preset menu.
public enum WidgetBlock: Codable, Equatable {
    /// Big number — either bound to a live metric (`metricRef`) or a literal
    /// you type into `value`. `unit` defaults to the metric's unit when bound.
    case metricValue(metricRef: String?, value: Double?, label: String?, unit: String?)

    /// Animated progress ring. Fills via `.trim` on appear (0.6s spring).
    /// `metricRef` binds the current value; `goalValue` is the denominator.
    case ring(metricRef: String?, current: Double?, goalValue: Double?, label: String?)

    /// 14-day sparkline of the bound metric's history. Animates draw-in
    /// from left → right over 0.8s.
    case sparkline(metricRef: String, days: Int)

    /// Last N daily bars (default 7). Color-graded against the average so the
    /// user sees which days were above / below normal at a glance.
    case miniBars(metricRef: String, days: Int)

    /// Two-period side-by-side comparison ("Week A vs Week B"). Renders as
    /// twin bars + delta.
    case comparison(metricRef: String, periodADays: Int, periodBDays: Int, labelA: String?, labelB: String?)

    /// Single delta chip: "+12% vs last 7 days" with up/down arrow + color.
    case delta(metricRef: String, vsDays: Int)

    /// Up to 5 bulleted lines.
    case bullets([String])

    /// Prose paragraph.
    case text(String)

    /// Small horizontal status chips. Tiny indigo pills, useful for
    /// "Goal hit · Recovery up · Hydration on track".
    case chipRow([String])

    /// Italic motivational quote / Astra-authored aphorism.
    case quote(String)

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case type
        case metricRef = "metric_ref"
        case value, current, goalValue = "goal_value", label, unit
        case days
        case periodADays = "period_a_days", periodBDays = "period_b_days"
        case labelA = "label_a", labelB = "label_b"
        case vsDays = "vs_days"
        case items, text, chips
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metricValue(let mr, let v, let l, let u):
            try c.encode("metric_value", forKey: .type)
            try c.encodeIfPresent(mr, forKey: .metricRef)
            try c.encodeIfPresent(v, forKey: .value)
            try c.encodeIfPresent(l, forKey: .label)
            try c.encodeIfPresent(u, forKey: .unit)
        case .ring(let mr, let cur, let g, let l):
            try c.encode("ring", forKey: .type)
            try c.encodeIfPresent(mr, forKey: .metricRef)
            try c.encodeIfPresent(cur, forKey: .current)
            try c.encodeIfPresent(g, forKey: .goalValue)
            try c.encodeIfPresent(l, forKey: .label)
        case .sparkline(let mr, let d):
            try c.encode("sparkline", forKey: .type)
            try c.encode(mr, forKey: .metricRef)
            try c.encode(d, forKey: .days)
        case .miniBars(let mr, let d):
            try c.encode("mini_bars", forKey: .type)
            try c.encode(mr, forKey: .metricRef)
            try c.encode(d, forKey: .days)
        case .comparison(let mr, let pa, let pb, let la, let lb):
            try c.encode("comparison", forKey: .type)
            try c.encode(mr, forKey: .metricRef)
            try c.encode(pa, forKey: .periodADays)
            try c.encode(pb, forKey: .periodBDays)
            try c.encodeIfPresent(la, forKey: .labelA)
            try c.encodeIfPresent(lb, forKey: .labelB)
        case .delta(let mr, let vs):
            try c.encode("delta", forKey: .type)
            try c.encode(mr, forKey: .metricRef)
            try c.encode(vs, forKey: .vsDays)
        case .bullets(let xs):
            try c.encode("bullets", forKey: .type)
            try c.encode(xs, forKey: .items)
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .chipRow(let xs):
            try c.encode("chip_row", forKey: .type)
            try c.encode(xs, forKey: .chips)
        case .quote(let s):
            try c.encode("quote", forKey: .type)
            try c.encode(s, forKey: .text)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "metric_value":
            self = .metricValue(
                metricRef: try? c.decodeIfPresent(String.self, forKey: .metricRef),
                value: try? c.decodeIfPresent(Double.self, forKey: .value),
                label: try? c.decodeIfPresent(String.self, forKey: .label),
                unit: try? c.decodeIfPresent(String.self, forKey: .unit)
            )
        case "ring":
            self = .ring(
                metricRef: try? c.decodeIfPresent(String.self, forKey: .metricRef),
                current: try? c.decodeIfPresent(Double.self, forKey: .current),
                goalValue: try? c.decodeIfPresent(Double.self, forKey: .goalValue),
                label: try? c.decodeIfPresent(String.self, forKey: .label)
            )
        case "sparkline":
            self = .sparkline(
                metricRef: try c.decode(String.self, forKey: .metricRef),
                days: (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 14
            )
        case "mini_bars":
            self = .miniBars(
                metricRef: try c.decode(String.self, forKey: .metricRef),
                days: (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 7
            )
        case "comparison":
            self = .comparison(
                metricRef: try c.decode(String.self, forKey: .metricRef),
                periodADays: (try? c.decodeIfPresent(Int.self, forKey: .periodADays)) ?? 7,
                periodBDays: (try? c.decodeIfPresent(Int.self, forKey: .periodBDays)) ?? 7,
                labelA: try? c.decodeIfPresent(String.self, forKey: .labelA),
                labelB: try? c.decodeIfPresent(String.self, forKey: .labelB)
            )
        case "delta":
            self = .delta(
                metricRef: try c.decode(String.self, forKey: .metricRef),
                vsDays: (try? c.decodeIfPresent(Int.self, forKey: .vsDays)) ?? 7
            )
        case "bullets":
            self = .bullets((try? c.decodeIfPresent([String].self, forKey: .items)) ?? [])
        case "text":
            self = .text((try? c.decodeIfPresent(String.self, forKey: .text)) ?? "")
        case "chip_row":
            self = .chipRow((try? c.decodeIfPresent([String].self, forKey: .chips)) ?? [])
        case "quote":
            self = .quote((try? c.decodeIfPresent(String.self, forKey: .text)) ?? "")
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown widget block type: \(type)")
        }
    }

    // MARK: Tool args ⇄ block (Gemini round-trip)

    /// Decode one block from Gemini's loose `[String: Any]` arg shape.
    /// Returns nil on malformed inputs so the array filter drops them
    /// instead of failing the whole tool call.
    public static func from(dict: [String: Any]) -> WidgetBlock? {
        guard let type = dict["type"] as? String else { return nil }
        func d(_ k: String) -> Double? {
            if let v = dict[k] as? Double { return v }
            if let v = dict[k] as? Int { return Double(v) }
            if let v = dict[k] as? String { return Double(v) }
            return nil
        }
        func s(_ k: String) -> String? { dict[k] as? String }
        func i(_ k: String) -> Int? {
            if let v = dict[k] as? Int { return v }
            if let v = dict[k] as? Double { return Int(v) }
            return nil
        }
        switch type {
        case "metric_value":
            return .metricValue(metricRef: s("metric_ref"), value: d("value"), label: s("label"), unit: s("unit"))
        case "ring":
            return .ring(metricRef: s("metric_ref"), current: d("current"), goalValue: d("goal_value"), label: s("label"))
        case "sparkline":
            guard let mr = s("metric_ref") else { return nil }
            return .sparkline(metricRef: mr, days: i("days") ?? 14)
        case "mini_bars":
            guard let mr = s("metric_ref") else { return nil }
            return .miniBars(metricRef: mr, days: i("days") ?? 7)
        case "comparison":
            guard let mr = s("metric_ref") else { return nil }
            return .comparison(metricRef: mr,
                               periodADays: i("period_a_days") ?? 7,
                               periodBDays: i("period_b_days") ?? 7,
                               labelA: s("label_a"), labelB: s("label_b"))
        case "delta":
            guard let mr = s("metric_ref") else { return nil }
            return .delta(metricRef: mr, vsDays: i("vs_days") ?? 7)
        case "bullets":
            return .bullets((dict["items"] as? [String]) ?? [])
        case "text":
            return .text(s("text") ?? "")
        case "chip_row":
            return .chipRow((dict["chips"] as? [String]) ?? [])
        case "quote":
            return .quote(s("text") ?? "")
        default:
            return nil
        }
    }

    /// Round-trip the block back to a Gemini-compatible dict for inclusion
    /// in `asFunctionCallPayload`.
    public var asDict: [String: Any] {
        switch self {
        case .metricValue(let mr, let v, let l, let u):
            var d: [String: Any] = ["type": "metric_value"]
            if let mr { d["metric_ref"] = mr }
            if let v { d["value"] = v }
            if let l { d["label"] = l }
            if let u { d["unit"] = u }
            return d
        case .ring(let mr, let cur, let g, let l):
            var d: [String: Any] = ["type": "ring"]
            if let mr { d["metric_ref"] = mr }
            if let cur { d["current"] = cur }
            if let g { d["goal_value"] = g }
            if let l { d["label"] = l }
            return d
        case .sparkline(let mr, let d2):
            return ["type": "sparkline", "metric_ref": mr, "days": d2]
        case .miniBars(let mr, let d2):
            return ["type": "mini_bars", "metric_ref": mr, "days": d2]
        case .comparison(let mr, let pa, let pb, let la, let lb):
            var d: [String: Any] = ["type": "comparison", "metric_ref": mr,
                                     "period_a_days": pa, "period_b_days": pb]
            if let la { d["label_a"] = la }
            if let lb { d["label_b"] = lb }
            return d
        case .delta(let mr, let vs):
            return ["type": "delta", "metric_ref": mr, "vs_days": vs]
        case .bullets(let xs):
            return ["type": "bullets", "items": xs]
        case .text(let s):
            return ["type": "text", "text": s]
        case .chipRow(let xs):
            return ["type": "chip_row", "chips": xs]
        case .quote(let s):
            return ["type": "quote", "text": s]
        }
    }
}
