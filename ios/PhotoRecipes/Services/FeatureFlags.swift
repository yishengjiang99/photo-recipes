import Foundation

/// Injectable analytics sink so pure-logic services can be unit-tested with a
/// fake instead of the network-backed `Analytics`. `Analytics` conforms below.
///
/// IMPORTANT (telemetry contract): `Analytics.track` drops any prop *key*
/// matching `email|phone|image|photo|base64|gps|token|password`. Never name a
/// prop key containing those substrings (e.g. use `run_id`, `arm`, `elapsed_sec`
/// — never a key containing "photo").
protocol AnalyticsEventSink: AnyObject {
    func track(_ event: String, props: [String: String])
}

extension Analytics: AnalyticsEventSink {}

/// UserDefaults-backed feature flags for the activation / capture-ready /
/// paywall-value / purchase-telemetry-v2 / optimize-timing workstreams.
///
/// - Safe defaults: UI experiments default ON (their *arms* still gate actual
///   behavior), purchase telemetry v2 defaults OFF because it changes when the
///   legacy `purchase_success` event may fire, and the safe-timeout flag
///   defaults OFF (it only selects a bounded-wait constant; it never shortens
///   the AE convergence timeout — see docs/activation-experiments.md).
/// - Kill switches are independent of experiment assignment: flipping a kill
///   switch disables behavior but NEVER clears a persisted assignment, so
///   re-enabling restores the same arm.
struct FeatureFlags {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    // MARK: - Logical flags (task §9)

    var firstPhotoPreoptimizeEnabled: Bool {
        bool("featureFlags.firstPhotoPreoptimizeEnabled", default: true)
    }

    var captureReadyUIEnabled: Bool {
        bool("featureFlags.captureReadyUIEnabled", default: true)
    }

    var paywallValueExperimentEnabled: Bool {
        bool("featureFlags.paywallValueExperimentEnabled", default: true)
    }

    /// Default OFF: when ON, the legacy `purchase_success` event is held to the
    /// same verified + entitlement-activated bar as the v2 events.
    var purchaseTelemetryV2Enabled: Bool {
        bool("featureFlags.purchaseTelemetryV2Enabled", default: false)
    }

    /// Telemetry-only; safe to enable independently of any UI experiment.
    var optimizeStageTimingEnabled: Bool {
        bool("featureFlags.optimizeStageTimingEnabled", default: true)
    }

    /// Selects bounded-wait behavior only. Does NOT shorten AE timeout.
    var optimizeSafeTimeoutEnabled: Bool {
        bool("featureFlags.optimizeSafeTimeoutEnabled", default: false)
    }

    // MARK: - Emergency kill switches

    var firstPhotoExperimentKilled: Bool {
        bool("featureFlags.firstPhotoExperimentKilled", default: false)
    }

    var paywallExperimentKilled: Bool {
        bool("featureFlags.paywallExperimentKilled", default: false)
    }

    // MARK: - Derived activation (flag AND not killed)

    var firstPhotoExperimentActive: Bool {
        firstPhotoPreoptimizeEnabled && !firstPhotoExperimentKilled
    }

    var paywallExperimentActive: Bool {
        paywallValueExperimentEnabled && !paywallExperimentKilled
    }
}
