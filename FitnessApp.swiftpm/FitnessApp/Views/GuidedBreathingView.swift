import SwiftUI
import UIKit

// MARK: - GuidedBreathingView

/// Full-screen breathing session modal. Presented as a .sheet from DashboardView
/// (via the Breathe chip in the predictions/actions row) or from the AI Coach.
public struct GuidedBreathingView: View {
    @ObservedObject private var manager = BreathingSessionManager.shared

    @AppStorage("theme_mode")    private var themeMode     = "dark"
    @AppStorage("accent_color")  private var accentColorHex = "#30D158"
    @AppStorage("custom_breath_in")   private var customBreathIn   = 4.0
    @AppStorage("custom_breath_hold") private var customBreathHold = 0.0
    @AppStorage("custom_breath_out")  private var customBreathOut  = 6.0

    @State private var selectedId: String = "box"
    @State private var showCustomEditor = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Orb animation state — driven by phase changes, not per-tick progress
    @State private var orbScale: CGFloat = 0.7
    @State private var rippleTrigger: Int = 0   // increment to fire a ripple burst

    private var isDark: Bool { themeMode == "dark" }
    private var accentColor: Color { ThemeHelper.color(from: accentColorHex) }

    private var protocols: [BreathingProtocol] {
        manager.currentProtocols
    }

    private var selectedProtocol: BreathingProtocol {
        protocols.first { $0.id == selectedId } ?? .box
    }

    public init() {}

    public var body: some View {
        ZStack {
            // Background — darkens during active session for focus
            AdaptiveBackground()
                .overlay(
                    Color.black
                        .opacity(manager.isRunning ? 0.5 : 0)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.6), value: manager.isRunning)
                )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar area
                HStack {
                    Button {
                        if manager.isRunning { manager.stopSession() }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Breathe")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)

                    Spacer()

                    // Custom ratios editor button (only for custom protocol)
                    if selectedId == "custom" {
                        Button { showCustomEditor = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        // 1. Protocol picker
                        if !manager.isRunning {
                            protocolPicker
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // 2. Breathing circle
                        breathingCircle
                            .padding(.top, manager.isRunning ? 24 : 0)

                        // 3. Controls
                        controlsSection

                        // 4. Session history dots
                        if !manager.todaySessions.isEmpty {
                            sessionHistoryRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: manager.isRunning)
                }
            }
        }
        .sheet(isPresented: $showCustomEditor) {
            CustomRatioEditorView(
                inSec: customBreathIn,
                holdSec: customBreathHold,
                outSec: customBreathOut,
                onSave: { inS, holdS, outS in
                    manager.setCustomRatios(inSec: inS, holdSec: holdS, outSec: outS)
                    showCustomEditor = false
                },
                onDismiss: { showCustomEditor = false }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Protocol Picker

    private var protocolPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a protocol")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(protocols) { proto in
                        ProtocolCard(
                            proto: proto,
                            isSelected: selectedId == proto.id,
                            onTap: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedId = proto.id
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Breathing Circle

    private var breathingCircle: some View {
        let proto = manager.isRunning ? manager.selectedProtocol : selectedProtocol
        let color = proto.color
        let phase = manager.isRunning ? manager.currentPhase : .inhale

        return ZStack {
            // ── Ripple rings (inhale only, not shown when reduce-motion is on) ──
            if !reduceMotion && manager.isRunning {
                ForEach(0..<3, id: \.self) { i in
                    RippleRing(color: color, trigger: rippleTrigger, delay: Double(i) * 0.35)
                }
            }

            // ── Soft outer glow halo (blurred, breathes with the orb) ──
            // orbScale is driven by withAnimation in onChange, so no extra .animation needed.
            if !reduceMotion {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.38), color.opacity(0.10), .clear],
                            center: .center,
                            startRadius: 60,
                            endRadius: 140
                        )
                    )
                    .frame(width: 280, height: 280)
                    .blur(radius: 22)
                    .scaleEffect(orbScale * 1.12)
            }

            // ── Second softer halo layer for depth ──
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.09))
                    .frame(width: 248, height: 248)
                    .blur(radius: 10)
                    .scaleEffect(orbScale * 1.06)
            }

            // ── Main orb: gradient fill + glass frost ──
            ZStack {
                // Richer gradient base
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.opacity(0.55),
                                color.opacity(0.22),
                                color.opacity(0.06)
                            ],
                            center: UnitPoint(x: 0.38, y: 0.32),
                            startRadius: 8,
                            endRadius: 105
                        )
                    )
                    .frame(width: 210, height: 210)

                // Glass frost overlay on top
                Circle()
                    .frame(width: 210, height: 210)
                    .glassEffect(.regular, in: .circle)

                // Subtle inner specular highlight
                if !reduceMotion {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.18), .clear],
                                center: UnitPoint(x: 0.35, y: 0.28),
                                startRadius: 0,
                                endRadius: 72
                            )
                        )
                        .frame(width: 210, height: 210)
                        .blendMode(.plusLighter)
                }
            }
            .scaleEffect(orbScale)

            // ── Inner content: phase icon + label + countdown ──
            // Countdown is isolated in BreathingCountdownView so phaseProgress
            // ticks (20 Hz) only re-evaluate that leaf node, not the whole orb.
            VStack(spacing: 6) {
                if manager.isRunning {
                    Image(systemName: phase.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(color)
                        .id("phase_icon_\(phase.rawValue)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.75)),
                            removal: .opacity.combined(with: .scale(scale: 1.2))
                        ))

                    Text(phase.label)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                        .id("phase_label_\(phase.rawValue)")
                        .transition(.opacity)
                        .contentTransition(.opacity)

                    BreathingCountdownView(manager: manager, isDark: isDark)
                } else {
                    Image(systemName: proto.icon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(color.opacity(0.8))

                    Text("Ready")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: manager.isRunning)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: phase)
        }
        .frame(height: 300)
        // Drive orbScale and ripple from phase/running changes
        .onChange(of: phase) { _, newPhase in
            guard manager.isRunning else { return }
            let dur: Double
            switch newPhase {
            case .inhale:
                dur = manager.selectedProtocol.activePhases.first(where: { $0.phase == .inhale })?.duration ?? 4
            case .hold1:
                dur = manager.selectedProtocol.activePhases.first(where: { $0.phase == .hold1 })?.duration ?? 2
            case .exhale:
                dur = manager.selectedProtocol.activePhases.first(where: { $0.phase == .exhale })?.duration ?? 6
            case .hold2:
                dur = manager.selectedProtocol.activePhases.first(where: { $0.phase == .hold2 })?.duration ?? 2
            }
            let spring: Animation = {
                switch newPhase {
                case .inhale:  return .spring(response: dur * 0.85, dampingFraction: 0.72)
                case .hold1, .hold2: return .spring(response: 0.55, dampingFraction: 0.85)
                case .exhale:  return .spring(response: dur * 0.88, dampingFraction: 0.68)
                }
            }()
            let target: CGFloat = (newPhase == .inhale || newPhase == .hold1) ? 1.0 : 0.6
            withAnimation(spring) { orbScale = target }
            if newPhase == .inhale && !reduceMotion { rippleTrigger += 1 }
        }
        .onChange(of: manager.isRunning) { _, running in
            if running {
                // Session just started — set initial scale for the first inhale
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { orbScale = 0.62 }
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { orbScale = 0.7 }
            }
        }
        .onAppear {
            orbScale = manager.isRunning
                ? ((manager.currentPhase == .inhale || manager.currentPhase == .hold1) ? 1.0 : 0.6)
                : 0.7
        }
    }

    // MARK: - Ripple Ring Helper

    /// A single expanding+fading ring that fires when `trigger` changes.
    private struct RippleRing: View {
        let color: Color
        let trigger: Int
        let delay: Double

        @State private var scale: CGFloat = 0.55
        @State private var opacity: Double = 0.0

        var body: some View {
            Circle()
                .strokeBorder(color.opacity(opacity), lineWidth: 1.5)
                .frame(width: 210, height: 210)
                .scaleEffect(scale)
                .onChange(of: trigger) { _, _ in
                    // Reset to starting state immediately (no animation), then expand+fade
                    scale = 0.55
                    opacity = 0.0
                    withAnimation(.easeOut(duration: 2.2).delay(delay)) {
                        scale = 1.65
                        opacity = 0.0
                    }
                    // Kick opacity up at the very start of this ripple's window
                    withAnimation(.easeIn(duration: 0.15).delay(delay)) {
                        opacity = 0.45
                    }
                }
        }
    }

    // MARK: - Countdown Leaf View
    // Isolated so that phaseProgress ticks (20 Hz) only invalidate this node.

    private struct BreathingCountdownView: View {
        @ObservedObject var manager: BreathingSessionManager
        let isDark: Bool

        private var countdownSecs: Int {
            let proto = manager.selectedProtocol
            let phase = manager.currentPhase
            let duration = proto.activePhases.first(where: { $0.phase == phase })?.duration ?? 1
            return max(0, Int(ceil(duration * (1.0 - manager.phaseProgress))))
        }

        var body: some View {
            Text("\(countdownSecs)")
                .font(.system(size: 42, weight: .thin, design: .rounded))
                .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.3), value: countdownSecs)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Start / stop button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if manager.isRunning {
                    manager.stopSession()
                } else {
                    manager.startSession(protocol: selectedProtocol)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(manager.isRunning ? "End Session" : "Start Session")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .glassEffect(
                    .regular.tint(manager.isRunning ? Color.red.opacity(0.55) : selectedProtocol.color.opacity(0.55)).interactive(),
                    in: .rect(cornerRadius: 16)
                )
                .animation(.easeInOut(duration: 0.25), value: manager.isRunning)
            }
            .buttonStyle(.plain)

            // Cycle count + elapsed time
            if manager.isRunning {
                HStack(spacing: 24) {
                    VStack(spacing: 3) {
                        Text("\(manager.cycleCount)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(isDark ? .white : .black)
                            .contentTransition(.numericText())
                        Text("Cycles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }

                    Divider()
                        .frame(height: 32)
                        .opacity(0.3)

                    VStack(spacing: 3) {
                        Text(formatElapsed(manager.sessionSeconds))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(isDark ? .white : .black)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("Elapsed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .glassCard(cornerRadius: 16)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Show protocol summary when idle
                protocolSummaryRow
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.isRunning)
    }

    private var protocolSummaryRow: some View {
        let proto = selectedProtocol
        return HStack(spacing: 6) {
            ForEach(proto.activePhases, id: \.phase.rawValue) { item in
                VStack(spacing: 3) {
                    Text("\(Int(item.duration))s")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                    Text(item.phase.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                if item.phase != proto.activePhases.last?.phase {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Session History Row

    private var sessionHistoryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's sessions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(manager.todaySessions) { record in
                        SessionDot(record: record)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Helpers

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Protocol Card

private struct ProtocolCard: View {
    let proto: BreathingProtocol
    let isSelected: Bool
    let onTap: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(proto.color.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: proto.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(proto.color)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(proto.color)
                    }
                }

                Text(proto.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)

                Text(ratioLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(proto.color)

                Text(proto.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("~\(proto.estimatedMinutes) min")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
            .padding(14)
            .frame(width: 152)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? proto.color.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var ratioLabel: String {
        let parts: [Double] = [proto.inhaleSec, proto.hold1Sec, proto.exhaleSec, proto.hold2Sec]
            .filter { $0 > 0 }
        return parts.map { String(Int($0)) }.joined(separator: "-")
    }
}

// MARK: - Session Dot

private struct SessionDot: View {
    let record: BreathingSessionRecord

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ThemeHelper.color(from: record.colorHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.protocolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                Text("\(record.cycleCount) cycles · \(formatDuration(record.durationSeconds))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

// MARK: - Custom Ratio Editor

private struct CustomRatioEditorView: View {
    @State private var inSec: Double
    @State private var holdSec: Double
    @State private var outSec: Double

    let onSave: (Double, Double, Double) -> Void
    let onDismiss: () -> Void

    @AppStorage("theme_mode") private var themeMode = "dark"
    private var isDark: Bool { themeMode == "dark" }

    init(inSec: Double, holdSec: Double, outSec: Double,
         onSave: @escaping (Double, Double, Double) -> Void,
         onDismiss: @escaping () -> Void) {
        _inSec   = State(initialValue: inSec)
        _holdSec = State(initialValue: holdSec)
        _outSec  = State(initialValue: outSec)
        self.onSave    = onSave
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 18) {
                    ratioSlider(label: "Inhale", value: $inSec, range: 1...15)
                    ratioSlider(label: "Hold",   value: $holdSec, range: 0...15)
                    ratioSlider(label: "Exhale", value: $outSec, range: 1...15)
                }
                .padding(20)
                .glassCard(cornerRadius: 18)

                // Live preview
                HStack(spacing: 6) {
                    Text("Ratio")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                    Text(ratioPreview)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("· ~\(estimatedMinutes) min session")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isDark ? .white.opacity(0.45) : .black.opacity(0.45))
                }
                .padding(.horizontal, 4)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(AdaptiveBackground())
            .navigationTitle("Custom Ratio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(inSec, holdSec, outSec) }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var ratioPreview: String {
        let parts = [inSec, holdSec, outSec].filter { $0 > 0 }
        return parts.map { String(Int($0)) }.joined(separator: "-")
    }

    private var estimatedMinutes: Int {
        let cycle = inSec + holdSec + outSec
        return max(1, Int((5 * cycle / 60.0).rounded()))
    }

    @ViewBuilder
    private func ratioSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                Spacer()
                Text("\(Int(value.wrappedValue))s")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: value, in: range, step: 1) {
                Text(label)
            }
            .tint(.orange)
        }
    }
}
