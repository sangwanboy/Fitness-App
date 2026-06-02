@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis
import Foundation

/// On-device snore detection using Apple's built-in SoundAnalysis classifier
/// (`SNClassifierIdentifier.version1`, which recognizes 300+ sound labels
/// including "snoring"). Streams audio from the built-in mic, classifies
/// every ~1 s window, and merges nearby positive bursts into snore episodes.
///
/// No Apple entitlement needed beyond `NSMicrophoneUsageDescription` and the
/// `audio` background mode (so the session continues while the screen is off).
@MainActor
public final class SnoreDetector: ObservableObject {
    public static let shared = SnoreDetector()

    @Published public private(set) var isListening = false
    @Published public private(set) var episodes: [SnoreEpisode] = []
    /// 0–1, last classification confidence. Drives the live "wave" UI.
    @Published public private(set) var lastConfidence: Double = 0

    private let audioEngine = AVAudioEngine()
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.tushar.fitnessapp.snoreanalysis")
    private var observer: SnoreObserver?

    // Episode-merge window — bursts within 10 s of each other belong to the
    // same snore episode. Tunable.
    private static let episodeMergeWindow: TimeInterval = 10
    // Threshold for treating a single classification as "snoring".
    private static let positiveThreshold: Double = 0.55

    private var currentEpisodeStart: Date?
    private var currentEpisodePeakConf: Double = 0
    private var lastPositiveAt: Date?

    private init() {}

    /// Start listening. When `analyze == false`, the audio session and engine
    /// still come up (so the `audio` background mode keeps the app alive for
    /// accelerometer sampling), but no `SoundAnalysis` ML pipeline is built —
    /// saves roughly the SoundAnalysis ML cost (~1–2% of an 8h night).
    public func start(analyze: Bool = true) throws {
        guard !isListening else { return }
        episodes = []
        currentEpisodeStart = nil
        currentEpisodePeakConf = 0
        lastPositiveAt = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement,
                                options: [.mixWithOthers, .allowBluetooth])
        try session.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        if analyze {
            let analyzer = SNAudioStreamAnalyzer(format: format)
            streamAnalyzer = analyzer

            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            // Window of 1 second, ~50% overlap — Apple's recommended snore window.
            request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48_000)
            request.overlapFactor  = 0.5

            let obs = SnoreObserver { [weak self] confidence, at in
                Task { @MainActor in self?.handle(confidence: confidence, at: at) }
            }
            self.observer = obs
            try analyzer.add(request, withObserver: obs)

            input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
                self?.analysisQueue.async {
                    self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
        } else {
            // Keepalive-only: install a no-op tap so the engine processes
            // buffers (required for the audio background mode), but never run
            // them through the ML classifier.
            input.installTap(onBus: 0, bufferSize: 8192, format: format) { _, _ in }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    public func stop() {
        guard isListening else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        observer = nil
        // Close any episode left open by the final burst.
        flushOpenEpisode(at: Date())
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isListening = false
        lastConfidence = 0
    }

    private func handle(confidence: Double, at: Date) {
        lastConfidence = confidence
        guard confidence >= Self.positiveThreshold else {
            // No snore now — close any open episode whose last positive is
            // older than the merge window.
            if let last = lastPositiveAt, at.timeIntervalSince(last) > Self.episodeMergeWindow {
                flushOpenEpisode(at: last)
            }
            return
        }
        // Positive snore detection. Start or extend the current episode.
        lastPositiveAt = at
        if currentEpisodeStart == nil {
            currentEpisodeStart = at
            currentEpisodePeakConf = confidence
        } else {
            currentEpisodePeakConf = max(currentEpisodePeakConf, confidence)
        }
    }

    private func flushOpenEpisode(at endAt: Date) {
        guard let start = currentEpisodeStart else { return }
        let ep = SnoreEpisode(startedAt: start, endedAt: endAt, peakConfidence: currentEpisodePeakConf)
        // Only record episodes lasting ≥ 3 s — single isolated bursts are
        // often coughs, throat clears, or other false positives.
        if ep.durationSeconds >= 3 {
            episodes.append(ep)
        }
        currentEpisodeStart = nil
        currentEpisodePeakConf = 0
    }
}

// MARK: - Observer

/// SoundAnalysis observer. Forwards "snoring" confidence + timestamp out via
/// the closure provided at init. Sendable because it's instantiated once
/// per session and never mutated.
private final class SnoreObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let onResult: (Double, Date) -> Void

    init(onResult: @escaping (Double, Date) -> Void) {
        self.onResult = onResult
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let conf = r.classification(forIdentifier: "snoring")?.confidence ?? 0
        onResult(conf, Date())
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("SnoreObserver request failed: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
