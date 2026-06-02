import SwiftUI

public struct InteractiveButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.95
    public var duration: Double = 0.15
    
    public init(scale: CGFloat = 0.95, duration: Double = 0.15) {
        self.scale = scale
        self.duration = duration
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

