import Foundation
import CoreMotion
import UIKit
import Combine

/// Owns the active sleep tracking session. Coordinates the accelerometer
/// stream + `SnoreDetector` while the user is in sleep mode.
///
/// Flow:
/// 1. `start()` — opens mic, starts snore detector, begins 1 Hz accel sampling.
/// 2. Every 30 s rolling window of accel is collapsed to a single
///    `MotionSample(rms:)`. We don't keep the raw 1 Hz stream — UserDefaults
///    would blow out.
/// 3. `stop()` — closes everything, estimates sleep onset (first 10-min
///    window where median RMS < 20 mg), persists to `SleepSessionStore`,
///    and optionally writes to HealthKit.
///
/// Background continuation: `audio` background mode keeps the app alive
/// while `SnoreDetector` is recording, which means the accelerometer also
/// keeps firing. No special entitlement required.
@MainActor
public final class SleepSessionManager: ObservableObject {
    public static let shared = SleepSessionManager()

    @Published public private(set) var isRunning = false
    @Published public private(set) var startedAt: Date?
    @Published public private(set) var motionSamples: [MotionSample] = []
    @Published public private(set) var currentRMS: Double = 0
    /// Live snore episode count. Mirrored from `SnoreDetector` for the UI.
    @Published public private(set) var liveSnoreCount: Int = 0
    @Published public private(set) var lastError: String?

    private let motionManager = CMMotionManager()
    private var motionWindow: [Double] = []   // raw |a|−1g (mg) within current 30s window
    private var lastMotionFlush: Date?
    private var snoreObservation: AnyCancellable?

    // 30-second aggregate window. Each window collapses to one MotionSample.
    private static let aggregateWindow: TimeInterval = 30
    // Onset detection: first 10-minute span where the median RMS is below
    // this. Conservative — 20 mg is roughly "lying still".
    private static let onsetMaxMedianRMS: Double = 20
    private static let onsetWindowMinutes: Int = 10

    private init() {
        // Mirror snore detector's episode list into our live counter so the
        // sleep mode UI can show "Snores: N" without subscribing directly.
        snoreObservation = SnoreDetector.shared.$episodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eps in
                self?.liveSnoreCount = eps.count
            }
    }

    // MARK: - Lifecycle

    /// Start a session. `snoreEnabled` controls whether on-device snore
    /// detection runs — the AVAudioSession activates either way (required to
    /// keep the app alive in the background via the `audio` background mode),
    /// but with `snoreEnabled = false` no SoundAnalysis ML pipeline is built.
    public func start(snoreEnabled: Bool = true) {
        guard !isRunning else { return }
        lastError = nil
        startedAt = Date()
        motionSamples = []
        motionWindow = []
        lastMotionFlush = Date()
        liveSnoreCount = 0

        // 1 Hz accelerometer — plenty for sleep movement; minimal battery.
        motionManager.accelerometerUpdateInterval = 1.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.consumeAccelerometer(d.acceleration)
        }

        do {
            try SnoreDetector.shared.start(analyze: snoreEnabled)
        } catch {
            lastError = "Mic unavailable: \(error.localizedDescription). Sleep tracking will continue without snore detection."
        }

        // Don't auto-lock the screen — but keep brightness low.
        UIApplication.shared.isIdleTimerDisabled = true
        isRunning = true
    }

    /// End the session. Returns the completed `SleepSession` so the caller
    /// (sleep mode UI) can navigate to the report. Caller is responsible for
    /// calling `persist(_:writeToHealthKit:)` once the user confirms.
    @discardableResult
    public func stop() -> SleepSession? {
        guard isRunning, let started = startedAt else {
            isRunning = false
            return nil
        }
        // Flush any pending motion window.
        flushMotionWindow(at: Date())

        motionManager.stopAccelerometerUpdates()
        SnoreDetector.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        let endedAt = Date()
        let onset = estimateOnset(samples: motionSamples, sessionStart: started)
        let session = SleepSession(
            startedAt: started,
            endedAt: endedAt,
            onsetAt: onset,
            motionSamples: motionSamples,
            snoreEpisodes: SnoreDetector.shared.episodes
        )

        isRunning = false
        startedAt = nil
        return session
    }

    /// Persist + (optionally) write to HealthKit. Called when the user taps
    /// "Save" on the morning report.
    public func persist(_ session: SleepSession, writeToHealthKit: Bool) async {
        SleepSessionStore.shared.add(session)
        SleepFocusDetector.shared.patternDidUpdate()
        if writeToHealthKit {
            _ = await HealthKitManager.shared.writeSleepSession(session)
        }
    }

    // MARK: - Sample aggregation

    private func consumeAccelerometer(_ a: CMAcceleration) {
        // Magnitude of acceleration minus 1 g (the static earth pull). Converted
        // to mg. Stationary phone hovers near 0; movement spikes up.
        let mag = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
        let mg  = abs(mag - 1.0) * 1000
        motionWindow.append(mg)
        // Smoothed live read for UI.
        currentRMS = motionWindow.suffix(5).reduce(0, +) / Double(min(5, motionWindow.count))

        let now = Date()
        if now.timeIntervalSince(lastMotionFlush ?? now) >= Self.aggregateWindow {
            flushMotionWindow(at: now)
        }
    }

    private func flushMotionWindow(at: Date) {
        guard !motionWindow.isEmpty else {
            lastMotionFlush = at
            return
        }
        let rms = sqrt(motionWindow.map { $0 * $0 }.reduce(0, +) / Double(motionWindow.count))
        motionSamples.append(MotionSample(at: at, rms: rms))
        motionWindow.removeAll(keepingCapacity: true)
        lastMotionFlush = at
    }

    // MARK: - Onset estimation

    /// First time we see `onsetWindowMinutes` consecutive 30-s samples whose
    /// median RMS is < `onsetMaxMedianRMS`. Falls back to session start if
    /// the user fell asleep instantly or the heuristic never fires.
    private func estimateOnset(samples: [MotionSample], sessionStart: Date) -> Date {
        let samplesPerWindow = max(1, (Self.onsetWindowMinutes * 60) / Int(Self.aggregateWindow))
        guard samples.count >= samplesPerWindow else { return sessionStart }
        for i in 0...(samples.count - samplesPerWindow) {
            let window = Array(samples[i..<i+samplesPerWindow])
            let sorted = window.map(\.rms).sorted()
            let median = sorted[sorted.count / 2]
            if median < Self.onsetMaxMedianRMS, let first = window.first {
                return first.at
            }
        }
        return sessionStart
    }
}
