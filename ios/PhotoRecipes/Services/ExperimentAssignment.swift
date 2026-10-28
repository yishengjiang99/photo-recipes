import Foundation

/// Deterministic, persistent, installation-scoped experiment assignment.
///
/// - Bucket = FNV-1a(64) hash of `"<salt>:<installId>"` mod 100. FNV-1a is
///   stable across processes and platforms (unlike Swift's `Hasher`, which is
///   per-process seeded and must never be used for persistent assignment).
/// - 50/50 split: buckets 0..<50 → treatment, 50..<100 → control.
/// - The install id is the existing anonymous telemetry id (no PII), supplied
///   through an injected provider closure so tests don't touch `Analytics`.
/// - Assignment is persisted on first computation and never recomputed;
///   disabling a flag or flipping a kill switch does NOT reset it.
enum ExperimentArm: String {
    case control
    case treatment
}

enum Experiment: String, CaseIterable {
    case firstPhoto
    case paywall

    /// Versioned salt — bump the suffix to intentionally re-randomize.
    var salt: String {
        switch self {
        case .firstPhoto: return "first_photo_v1"
        case .paywall: return "paywall_v1"
        }
    }

    var assignmentDefaultsKey: String {
        switch self {
        case .firstPhoto: return "experiment.firstPhoto.arm"
        case .paywall: return "experiment.paywall.arm"
        }
    }

    var assignedEventName: String {
        switch self {
        case .firstPhoto: return "first_photo_experiment_assigned"
        case .paywall: return "paywall_experiment_assigned"
        }
    }
}

enum ExperimentAssignment {
    /// FNV-1a 64-bit over the UTF-8 bytes of `"<salt>:<installId>"`, mod 100.
    static func bucket(installId: String, salt: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV offset basis
        let prime: UInt64 = 0x0000_0100_0000_01b3 // FNV prime
        for byte in "\(salt):\(installId)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return Int(hash % 100)
    }

    static func arm(forBucket bucket: Int) -> ExperimentArm {
        bucket < 50 ? .treatment : .control
    }

    static func arm(installId: String, salt: String) -> ExperimentArm {
        arm(forBucket: bucket(installId: installId, salt: salt))
    }
}

final class ExperimentAssigner {
    private let defaults: UserDefaults
    private let installIdProvider: () -> String
    private let sink: AnalyticsEventSink?

    init(
        defaults: UserDefaults = .standard,
        installIdProvider: @escaping () -> String,
        sink: AnalyticsEventSink? = nil
    ) {
        self.defaults = defaults
        self.installIdProvider = installIdProvider
        self.sink = sink
    }

    /// The persisted arm for `experiment`, computing + persisting + emitting
    /// the `*_experiment_assigned` event exactly once on first assignment.
    /// Later calls (including after flag/kill-switch flips) return the stored
    /// arm unchanged and emit nothing.
    @discardableResult
    func assignment(for experiment: Experiment) -> ExperimentArm {
        if let raw = defaults.string(forKey: experiment.assignmentDefaultsKey),
           let arm = ExperimentArm(rawValue: raw) {
            return arm
        }
        let installId = installIdProvider()
        let bucket = ExperimentAssignment.bucket(installId: installId, salt: experiment.salt)
        let arm = ExperimentAssignment.arm(forBucket: bucket)
        defaults.set(arm.rawValue, forKey: experiment.assignmentDefaultsKey)
        // Prop keys must not contain "photo" (Analytics key filter) — the
        // experiment is identified by the event name + `exp_version` value.
        sink?.track(experiment.assignedEventName, props: [
            "arm": arm.rawValue,
            "bucket": "\(bucket)",
            "exp_version": experiment.salt,
        ])
        return arm
    }

    /// Test/debug seam: the persisted arm without triggering assignment.
    func persistedArm(for experiment: Experiment) -> ExperimentArm? {
        defaults.string(forKey: experiment.assignmentDefaultsKey)
            .flatMap(ExperimentArm.init(rawValue:))
    }
}
