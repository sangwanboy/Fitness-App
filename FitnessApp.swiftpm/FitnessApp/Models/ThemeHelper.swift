import SwiftUI

public struct ThemeHelper {
    public static func color(from hex: String) -> Color {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        
        if cleanHex.count == 6 {
            var rgbValue: UInt64 = 0
            Scanner(string: cleanHex).scanHexInt64(&rgbValue)
            let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = Double(rgbValue & 0x0000FF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        
        return .green // Fallback
    }
}

public struct AdaptiveBackground: View {
    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @AppStorage("bg_style") private var bgStyle = "gradient"
    
    public init() {}
    
    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }
    
    public var body: some View {
        ZStack {
            if bgStyle == "solid" {
                if isDark {
                    Color.black.ignoresSafeArea()
                } else {
                    Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea()
                }
            } else if bgStyle == "gradient" {
                if isDark {
                    Color.black.ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.22), .clear],
                        center: .init(x: 0.5, y: -0.1),
                        startRadius: 0,
                        endRadius: 400
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.12), .clear],
                        center: .init(x: 1.2, y: 1.0),
                        startRadius: 0,
                        endRadius: 450
                    )
                    .ignoresSafeArea()
                } else {
                    Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.16), .clear],
                        center: .init(x: 0.5, y: -0.1),
                        startRadius: 0,
                        endRadius: 400
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.10), .clear],
                        center: .init(x: 1.2, y: 1.0),
                        startRadius: 0,
                        endRadius: 450
                    )
                    .ignoresSafeArea()
                }
            } else { // photo background: painted abstract gradients to mimic a photo without loading an asset
                if isDark {
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.1, green: 0.08, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.35), .clear],
                        center: .init(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: 350
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [Color.purple.opacity(0.35), .clear],
                        center: .init(x: 0.8, y: 0.8),
                        startRadius: 0,
                        endRadius: 400
                    )
                    .ignoresSafeArea()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.95, blue: 0.97), Color(red: 0.94, green: 0.89, blue: 0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [accentColor.opacity(0.40), .clear],
                        center: .init(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: 350
                    )
                    .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [Color.orange.opacity(0.35), .clear],
                        center: .init(x: 0.8, y: 0.8),
                        startRadius: 0,
                        endRadius: 400
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}
