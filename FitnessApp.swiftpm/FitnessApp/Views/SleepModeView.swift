import SwiftUI
import UIKit

/// Fullscreen, minimal sleep mode. Pitch black with a large clock + a few
/// subtle live counters. Dims the screen on appear, restores on disappear.
/// Tap the "End sleep session" button to wake — the entire surface is also
/// tappable in case the user is groggy.
public struct SleepModeView: View {
    @ObservedObject private var session = SleepSessionManager.shared
    @ObservedObject private var snore = SnoreDetector.shared
    @AppStorage("sleep_snore_enabled") private var snoreEnabled = true

    @State private var now = Date()
    @State private var savedBrightness: CGFloat = 0
    @State private var completedSession: SleepSession?
    @State private var showEndConfirm = false

    /// Screen auto-blank state. After 30 s of no taps the brightness drops
    /// to effectively 0 and the controls fade out — on OLED iPhones a pure
    /// black screen draws ~0 mW, saving the biggest single chunk of overnight
    /// battery. Tap anywhere to bring everything back.
    @State private var showControls = true
    @State private var idleTimerTask: Task<Void, Never>?
    private static let idleBlankSeconds: UInt64 = 30
    private static let dimBrightness: CGFloat = 0.04
    private static let blankBrightness: CGFloat = 0.0

    private let onClose: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // Pure black background — on OLED, black pixels emit no light.
            // Combined with brightness=0 after the idle timer, the screen
            // costs essentially nothing while the session continues running.
            Color.black.ignoresSafeArea()

            // Visible UI — fades out when controls are hidden so the OLED
            // is uniformly black. Still wired up so tapping anywhere wakes
            // the controls again.
            VStack(spacing: 32) {
                Spacer()

                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 88, weight: .thin, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()
                    .tracking(-2)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: now)

                Text(now, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.5)

                Spacer()

                // Live status row — snore block hidden in battery-saver mode.
                HStack(spacing: 28) {
                    statBlock(title: "TRACKED", value: durationText, icon: "moon.zzz.fill")
                    if snoreEnabled {
                        statBlock(title: "SNORES", value: "\(snore.episodes.count)", icon: "waveform")
                    }
                    statBlock(title: "STILLNESS", value: stillnessText, icon: "figure.stand")
                }
                .padding(.bottom, 18)

                if snoreEnabled {
                    snoreWave.padding(.bottom, 14)
                }

                Text("Tap the screen to wake controls")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 8)

                Button { showEndConfirm = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                        Text("End sleep session")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.bottom, 48)
            }
            .opacity(showControls ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: showControls)
        }
        // Whole surface is tappable — tap anywhere to wake controls.
        .contentShape(Rectangle())
        .onTapGesture { wakeControls() }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = Self.dimBrightness
            if !session.isRunning { session.start(snoreEnabled: snoreEnabled) }
            scheduleIdleBlank()
        }
        .onDisappear {
            UIScreen.main.brightness = savedBrightness
            idleTimerTask?.cancel()
            idleTimerTask = nil
        }
        .onReceive(timer) { _ in now = Date() }
        .confirmationDialog("End sleep session?", isPresented: $showEndConfirm) {
            Button("End and see report") {
                completedSession = session.stop()
            }
            Button("Keep tracking", role: .cancel) {}
        } message: {
            Text("Your sleep stats will be saved.")
        }
        .fullScreenCover(item: $completedSession) { s in
            SleepReportView(session: s, onClose: {
                completedSession = nil
                onClose()
            })
        }
    }

    // MARK: - Auto-blank

    /// Tap-to-wake handler. Restores dim brightness, shows controls, restarts
    /// the idle timer. Also called once on appear so controls are visible
    /// during the initial 30 s.
    private func wakeControls() {
        UIScreen.main.brightness = Self.dimBrightness
        showControls = true
        scheduleIdleBlank()
    }

    private func scheduleIdleBlank() {
        idleTimerTask?.cancel()
        idleTimerTask = Task {
            try? await Task.sleep(nanoseconds: Self.idleBlankSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showControls = false
                UIScreen.main.brightness = Self.blankBrightness
            }
        }
    }

    private var durationText: String {
        guard let started = session.startedAt else { return "—" }
        let secs = Int(now.timeIntervalSince(started))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var stillnessText: String {
        // Live RMS bucket label.
        let r = session.currentRMS
        if r < 15  { return "still" }
        if r < 50  { return "light" }
        return "active"
    }

    private func statBlock(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.3))
        }
    }

    /// Live audio-confidence wave. Each bar opacity tracks `lastConfidence`.
    private var snoreWave: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                let phase = Double(i) / 14.0
                let h = 4 + (snore.lastConfidence * 24 * sin(phase * .pi))
                Capsule()
                    .fill(snore.lastConfidence > 0.5 ? Color.indigo.opacity(0.7) : Color.white.opacity(0.15))
                    .frame(width: 3, height: max(2, h))
                    .animation(.easeOut(duration: 0.4), value: snore.lastConfidence)
            }
        }
        .frame(height: 30)
    }
}
