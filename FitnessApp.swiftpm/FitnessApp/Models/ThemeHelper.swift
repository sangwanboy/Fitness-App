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

    public init() {}

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    public var body: some View {
        ZStack {
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
        }
    }
}
