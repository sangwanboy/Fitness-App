import Foundation

/// One completed sleep tracking session. Recorded by `SleepSessionManager`
/// while the user is in sleep mode, then persisted to UserDefaults and (when
/// the user confirms) written to HealthKit as `HKCategoryValueSleepAnalysis`
/// samples.
public struct SleepSession: Codable, Identifiable {
    public let id: UUID
    public let startedAt: Date          // when "Start Tracking" was tapped
    public let endedAt: Date            // when the session ended
    public let onsetAt: Date            // estimated time user fell asleep
    public let motionSamples: [MotionSample]
    public let snoreEpisodes: [SnoreEpisode]

    public init(id: UUID = UUID(),
                startedAt: Date,
                endedAt: Date,
                onsetAt: Date,
                motionSamples: [MotionSample],
                snoreEpisodes: [SnoreEpisode]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.onsetAt = onsetAt
        self.motionSamples = motionSamples
        self.snoreEpisodes = snoreEpisodes
    }

    public var totalDurationSeconds: Double { endedAt.timeIntervalSince(onsetAt) }
    public var inBedSeconds: Double { endedAt.timeIntervalSince(startedAt) }
    public var onsetLatencySeconds: Double { onsetAt.timeIntervalSince(startedAt) }

    public var totalSnoreSeconds: Double {
        snoreEpisodes.reduce(0) { $0 + $1.durationSeconds }
    }

    /// 0–100 score. 0 = perfectly still. 100 = constant motion.
    /// Computed from share of post-onset motion samples above the "micro"
    /// movement threshold.
    public var restlessnessScore: Int {
        let post = motionSamples.filter { $0.at >= onsetAt }
        guard !post.isEmpty else { return 0 }
        let active = post.filter { $0.rms > 15 }.count
        return min(100, Int((Double(active) / Double(post.count)) * 100))
    }

    /// Crude motion-only stage attribution. Each motion sample is bucketed
    /// based on RMS into awake/light/deep. Not REM/core — no HR to do that.
    public var stageBreakdown: StageBreakdown {
        let post = motionSamples.filter { $0.at >= onsetAt }
        guard !post.isEmpty else { return StageBreakdown(awake: 0, light: 0, deep: 0) }
        let secPer = totalDurationSeconds / Double(post.count)
        var awake = 0.0, light = 0.0, deep = 0.0
        for s in post {
            switch s.kind {
            case .gross:     awake += secPer
            case .micro:     light += secPer
            case .stillness: deep  += secPer
            }
        }
        return StageBreakdown(awake: awake, light: light, deep: deep)
    }
}

public struct StageBreakdown: Codable {
    public let awake: Double  // seconds
    public let light: Double
    public let deep: Double

    public var total: Double { awake + light + deep }
    public func percent(_ s: Double) -> Int {
        total > 0 ? Int((s / total) * 100) : 0
    }
}

/// Single accelerometer aggregate over a short window (default 30 s).
public struct MotionSample: Codable {
    public let at: Date
    public let rms: Double        // milli-g (mg), RMS of |accel|
    public let kind: MotionKind

    public init(at: Date, rms: Double) {
        self.at = at
        self.rms = rms
        // Bucketing thresholds calibrated empirically — iPhone on/near
        // mattress. Tune via real data after deployment.
        if rms > 50         { self.kind = .gross }
        else if rms > 15    { self.kind = .micro }
        else                { self.kind = .stillness }
    }
}

public enum MotionKind: String, Codable {
    case stillness   // deep / very still
    case micro       // light movements (toss/roll)
    case gross       // wake-class movement
}

/// A snoring episode detected via `SoundAnalysis`. Bursts within 10 s of
/// each other are merged into one episode by `SnoreDetector`.
public struct SnoreEpisode: Codable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let peakConfidence: Double  // 0–1

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, peakConfidence: Double) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.peakConfidence = peakConfidence
    }

    public var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }
}

/// Persistent store for completed sleep sessions. Singleton; backed by
/// UserDefaults blob. Latest first.
@MainActor
public final class SleepSessionStore: ObservableObject {
    public static let shared = SleepSessionStore()
    private static let storageKey = "sleep_sessions_v1"
    private static let maxStored = 30

    @Published public private(set) var sessions: [SleepSession] = []

    private init() { load() }

    public var mostRecent: SleepSession? { sessions.first }

    public func add(_ s: SleepSession) {
        sessions.insert(s, at: 0)
        if sessions.count > Self.maxStored {
            sessions = Array(sessions.prefix(Self.maxStored))
        }
        save()
    }

    public func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SleepSession].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
