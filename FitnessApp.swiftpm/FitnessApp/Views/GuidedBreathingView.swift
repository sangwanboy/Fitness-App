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
        let progress = manager.isRunning ? manager.phaseProgress : 0.0
        let currentPhaseIndex = manager.isRunning
            ? (proto.activePhases.firstIndex(where: { $0.phase == phase }) ?? 0)
            : 0
        let currentDuration = manager.isRunning
            ? (proto.activePhases.first(where: { $0.phase == phase })?.duration ?? 1)
            : proto.inhaleSec

        let countdownSecs = manager.isRunning
            ? max(0, Int(ceil(currentDuration * (1.0 - progress))))
            : Int(proto.inhaleSec)

        // Circle scale: expand on inhale (1.0), contract on exhale (0.6), hold at current
        let circleScale: Double = {
            guard manager.isRunning else { return 0.7 }
            switch phase {
            case .inhale:
                return 0.6 + 0.4 * progress
            case .hold1:
                return 1.0
            case .exhale:
                return 1.0 - 0.4 * progress
            case .hold2:
                return 0.6
            }
        }()

        return ZStack {
            // Outer pulsing glow ring
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 260, height: 260)
                .scaleEffect(manager.isRunning ? (0.85 + 0.30 * circleScale) : 0.9)
                .animation(
                    manager.isRunning
                        ? .easeInOut(duration: manager.selectedProtocol.activePhases.first(where: { $0.phase == phase })?.duration ?? 1)
                        : .easeInOut(duration: 2).repeatForever(autoreverses: true),
                    value: circleScale
                )

            // Middle frosted glass circle
            Circle()
                .frame(width: 200, height: 200)
                .glassEffect(.regular, in: .circle)
                .scaleEffect(circleScale)
                .animation(
                    .easeInOut(duration: currentDuration * (1.0 - progress)),
                    value: circleScale
                )

            // Inner content: phase label + countdown
            VStack(spacing: 6) {
                if manager.isRunning {
                    Image(systemName: phase.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(color)
                        .transition(.scale.combined(with: .opacity))
                        .id("phase_icon_\(phase.rawValue)_\(currentPhaseIndex)")

                    Text(phase.label)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(isDark ? .white : .black)
                        .transition(.opacity)
                        .id("phase_label_\(phase.rawValue)_\(currentPhaseIndex)")

                    Text("\(countdownSecs)")
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeInOut(duration: 0.3), value: countdownSecs)
                } else {
                    Image(systemName: proto.icon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(color.opacity(0.8))

                    Text("Ready")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: manager.isRunning)
            .animation(.easeInOut(duration: 0.25), value: phase)
        }
        .frame(height: 280)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Start / stop button
            Button {
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
                .background(
                    manager.isRunning
                        ? Color.red.opacity(0.85)
                        : (selectedProtocol.color)
                )
                .clipShape(.rect(cornerRadius: 16))
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
