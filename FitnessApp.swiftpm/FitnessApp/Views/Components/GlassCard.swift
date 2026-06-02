import SwiftUI

// Thin passthrough to Apple's native Liquid Glass material.
// No custom borders, glows, or overlays — the system handles specular highlight,
// hairline, and refraction. Tint comes from the user's saved preference.
public struct GlassBackgroundModifier: ViewModifier {
    public var glowColor: Color?         // accepted for source compatibility; ignored
    public var cornerRadius: CGFloat
    public var glowRadius: CGFloat        // accepted for source compatibility; ignored

    @AppStorage("glass_strength") private var glassStrength = "moderate"
    @AppStorage("glass_tint_color") private var glassTintColorHex = "#FFFFFF"
    @AppStorage("glass_tint_strength") private var glassTintStrength = 0.0

    private var glassTintColor: Color { ThemeHelper.color(from: glassTintColorHex) }
    private var tintAlpha: Double { glassTintStrength / 100.0 }

    public func body(content: Content) -> some View {
        content
            .padding()
            .glassEffect(glassEffectStyle(), in: .rect(cornerRadius: cornerRadius))
    }

    private func glassEffectStyle() -> Glass {
        let base: Glass = (glassStrength == "subtle") ? .clear : .regular
        if tintAlpha > 0 {
            return base.tint(glassTintColor.opacity(tintAlpha * 0.15)).interactive()
        }
        return base.interactive()
    }
}

public extension View {
    func glassCard(glowColor: Color? = nil, cornerRadius: CGFloat = 20, glowRadius: CGFloat = 20) -> some View {
        self.modifier(GlassBackgroundModifier(glowColor: glowColor, cornerRadius: cornerRadius, glowRadius: glowRadius))
    }
}

public struct SystemGlassBackground: View {
    public init() {}
    public var body: some View {
        AdaptiveBackground()
    }
}
