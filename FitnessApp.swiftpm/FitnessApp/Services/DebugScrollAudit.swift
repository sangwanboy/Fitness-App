#if DEBUG
import UIKit

/// Runtime tripwire for the "app wiggles left-right while scrolling" class of
/// bug: a vertical UIScrollView whose contentSize.width exceeds its viewport
/// re-enables horizontal drag. SwiftUI's vertical ScrollView should always
/// report contentSize.width == bounds.width, so any overshoot here is a laid-
/// out child that escaped the screen width. Logs offenders with the exact
/// overshoot so the culprit is identifiable from the console (intentional
/// horizontal scrollers — carousels, code blocks — also print; tell them
/// apart by their small height and expected location).
enum DebugScrollAudit {
    static func start() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in audit() }
    }

    private static func audit() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        var found: [String] = []
        walk(window, into: &found)
        // Silent when clean — only offenders print, so the console stays
        // usable during normal debugging.
        found.forEach { print("SCROLL-AUDIT OFFENDER \($0)") }
    }

    private static func walk(_ view: UIView, into found: inout [String]) {
        if let sv = view as? UIScrollView {
            let overshootX = sv.contentSize.width - sv.bounds.width
            if overshootX > 0.5 {
                found.append(String(
                    format: "+%.1fpt (content %.1f×%.1f, bounds %.1f×%.1f) %@ | path: %@",
                    overshootX,
                    sv.contentSize.width, sv.contentSize.height,
                    sv.bounds.width, sv.bounds.height,
                    String(describing: type(of: sv)), path(of: sv)))
            }
        }
        view.subviews.forEach { walk($0, into: &found) }
    }

    private static func path(of view: UIView) -> String {
        var parts: [String] = []
        var v: UIView? = view.superview
        while let cur = v {
            parts.append(String(describing: type(of: cur)))
            v = cur.superview
        }
        return parts.prefix(6).joined(separator: " < ")
    }
}
#endif
