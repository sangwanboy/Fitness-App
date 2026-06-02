import Foundation
@preconcurrency import Intents
import Combine

/// Surfaces whether the user is currently in an iOS Focus mode (Sleep,
/// Do Not Disturb, etc.) using `INFocusStatusCenter`. iOS doesn't expose
/// *which* focus is active — only whether *any* is active. We combine that
/// with a time-of-day check against the user's learned bedtime window to
/// infer "Sleep Focus".
///
/// Permission: requires `NSFocusStatusUsageDescription` in Info.plist and a
/// one-time user grant (`requestAuthorization`). No Apple entitlement
/// approval needed — it's an end-user permission, not an entitlement.
@MainActor
public final class SleepFocusDetector: ObservableObject {
    public static let shared = SleepFocusDetector()

    /// nil = not authorized / unknown. true/false = current focus state.
    @Published public private(set) var isInFocus: Bool? = nil
    /// True when the current time falls inside the user's typical bedtime
    /// window (median bedtime – 30 min through median wake + 30 min).
    @Published public private(set) var isWithinBedtimeWindow: Bool = false
    /// True when isInFocus AND isWithinBedtimeWindow — our best guess that
    /// iOS Sleep Focus is currently active.
    @Published public private(set) var sleepFocusLikely: Bool = false

    private var timer: Timer?
    private var patternCache: SleepPattern?

    private init() {}

    /// Idempotent — call from app launch. Requests focus authorization (the
    /// user sees a system sheet the first time) and starts a 60-sec poll
    /// loop. No-op if already started.
    public func start() {
        if timer != nil { return }
        Task { @MainActor in
            await requestAuthorization()
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force a refresh now — used by the Home tracking card to get fresh
    /// state when the user opens the app or pulls to refresh.
    public func refresh() {
        let center = INFocusStatusCenter.default
        if center.authorizationStatus == .authorized {
            isInFocus = center.focusStatus.isFocused
        } else {
            isInFocus = nil
        }
        let pattern = patternCache ?? SleepPatternAnalyzer.compute(from: SleepSessionStore.shared.sessions)
        patternCache = pattern
        isWithinBedtimeWindow = computeIsWithinBedtimeWindow(pattern: pattern, now: Date())
        sleepFocusLikely = (isInFocus == true) && isWithinBedtimeWindow
    }

    /// Recompute the cached pattern after a session ends. Otherwise the
    /// bedtime window stays stale until the next 60-sec tick.
    public func patternDidUpdate() {
        patternCache = SleepPatternAnalyzer.compute(from: SleepSessionStore.shared.sessions)
        refresh()
    }

    private func requestAuthorization() async {
        // Apple's INFocusStatusCenter authorization API uses a completion
        // handler — wrap it in async.
        await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { _ in
                continuation.resume()
            }
        }
    }

    /// True when current time is inside the user's typical bedtime window.
    /// Window = median bedtime − 30m through median wake + 30m. When there
    /// isn't enough history, default to 22:00–08:00.
    private func computeIsWithinBedtimeWindow(pattern: SleepPattern, now: Date) -> Bool {
        let (startH, startM, endH, endM): (Int, Int, Int, Int)
        if pattern.hasEnoughHistory,
           let bh = pattern.typicalBedtimeHour, let bm = pattern.typicalBedtimeMinute,
           let wh = pattern.typicalWakeHour, let wm = pattern.typicalWakeMinute {
            (startH, startM, endH, endM) = (bh, bm, wh, wm)
        } else {
            // Conservative default — most users sleep within this window.
            (startH, startM, endH, endM) = (22, 0, 8, 0)
        }

        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMinutes = startH * 60 + startM - 30      // 30-min lead
        let endMinutes   = endH * 60 + endM + 30          // 30-min trail

        if startMinutes < endMinutes {
            return nowMinutes >= startMinutes && nowMinutes <= endMinutes
        } else {
            // Window wraps midnight (the normal case: 22:30 → 08:30).
            return nowMinutes >= startMinutes || nowMinutes <= endMinutes
        }
    }
}
