import Foundation

/// First-photo experiment state machine (Workstream A) — pure logic with
/// injected defaults / clock / sink so it is fully unit-testable.
///
/// Arms:
/// - control (`post_capture_v1`): the existing post-capture behavior
///   (`CameraView.maybeAutoRunFirstOptimize` after capture + save) is untouched.
/// - treatment (`pre_capture_guided_v1`): a dismissible guidance card offers a
///   pre-capture optimize run (trigger `pre_capture_guided`) once the camera is
///   ready and all safety gates pass. The shutter is never blocked; skipping or
///   failing never consumes quota (quota is only consumed by
///   `AutoOptimizeController` on success, as before).
///
/// Terminal states (completed / declined / skipped) persist and permanently
/// end eligibility. A prior undo (`AutoOptimizeController.userUndidKey`)
/// opts the install out forever, matching the existing first-win semantics.
@MainActor
final class FirstPhotoExperiment {
    enum State: String {
        case pending
        case guidanceShown
        case completed
        case declined
        case skipped

        var isTerminal: Bool {
            switch self {
            case .completed, .declined, .skipped: return true
            case .pending, .guidanceShown: return false
            }
        }
    }

    /// Safety gates for starting a pre-capture run. ALL must be safe.
    struct CameraGateInputs {
        var sessionRunning: Bool
        var isBackgrounded: Bool
        var isLensTransitioning: Bool
        var isCapturing: Bool
        var optimizerRunning: Bool

        var allSafe: Bool {
            sessionRunning && !isBackgrounded && !isLensTransitioning
                && !isCapturing && !optimizerRunning
        }
    }

    static let stateKey = "firstPhotoExp.state"
    static let activatedKey = "firstPhotoExp.activated"
    static let firstAppOpenKey = "app.firstAppOpenDate"
    /// The five-minute activation window from the primary business goal.
    static let activationWindow: TimeInterval = 5 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let sink: AnalyticsEventSink?
    private let flags: FeatureFlags
    private let assigner: ExperimentAssigner

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        sink: AnalyticsEventSink? = nil,
        flags: FeatureFlags? = nil,
        assigner: ExperimentAssigner
    ) {
        self.defaults = defaults
        self.now = now
        self.sink = sink
        self.flags = flags ?? FeatureFlags(defaults: defaults)
        self.assigner = assigner
    }

    /// Production wiring: install id = the existing anonymous telemetry id.
    static func live(defaults: UserDefaults = .standard) -> FirstPhotoExperiment {
        FirstPhotoExperiment(
            defaults: defaults,
            sink: Analytics.shared,
            assigner: ExperimentAssigner(
                defaults: defaults,
                installIdProvider: { Analytics.shared.anonId },
                sink: Analytics.shared
            )
        )
    }

    // MARK: - Assignment

    var arm: ExperimentArm { assigner.assignment(for: .firstPhoto) }

    // MARK: - First app open (stored exactly once)

    @discardableResult
    func recordFirstAppOpenIfNeeded() -> Date {
        if let stored = defaults.object(forKey: Self.firstAppOpenKey) as? Date {
            return stored
        }
        let date = now()
        defaults.set(date, forKey: Self.firstAppOpenKey)
        return date
    }

    var firstAppOpenDate: Date? {
        defaults.object(forKey: Self.firstAppOpenKey) as? Date
    }

    func elapsedSinceFirstAppOpen() -> TimeInterval? {
        firstAppOpenDate.map { now().timeIntervalSince($0) }
    }

    // MARK: - State

    var state: State {
        get {
            defaults.string(forKey: Self.stateKey)
                .flatMap(State.init(rawValue:)) ?? .pending
        }
        set { defaults.set(newValue.rawValue, forKey: Self.stateKey) }
    }

    var hasActivated: Bool { defaults.bool(forKey: Self.activatedKey) }

    /// Eligible = experiment active, not terminal, never activated, no prior
    /// activation from before the experiment existed, and no undo opt-out.
    func isEligible(hasPriorActivation: Bool, userUndid: Bool) -> Bool {
        guard flags.firstPhotoExperimentActive else { return false }
        guard !state.isTerminal, !hasActivated else { return false }
        guard !hasPriorActivation, !userUndid else { return false }
        return true
    }

    /// Treatment may start a pre-capture run only when eligible, assigned to
    /// treatment, and every camera gate is safe.
    func canStartPreoptimize(
        gates: CameraGateInputs,
        hasPriorActivation: Bool,
        userUndid: Bool
    ) -> Bool {
        guard arm == .treatment else { return false }
        guard isEligible(hasPriorActivation: hasPriorActivation, userUndid: userUndid)
        else { return false }
        return gates.allSafe
    }

    // MARK: - Lifecycle events (prop keys never contain "photo")

    /// Emits `first_photo_guidance_view` once, on the pending → shown edge.
    func markGuidanceShown() {
        guard state == .pending else { return }
        state = .guidanceShown
        sink?.track("first_photo_guidance_view", props: ["arm": arm.rawValue])
    }

    /// User dismissed the guidance without running. Terminal.
    func markSkipped() {
        guard !state.isTerminal else { return }
        state = .skipped
        sink?.track("first_photo_guidance_skip", props: [
            "arm": arm.rawValue, "reason": "skipped",
        ])
    }

    /// Explicit decline ("No thanks"). Terminal, same skip event family.
    func markDeclined() {
        guard !state.isTerminal else { return }
        state = .declined
        sink?.track("first_photo_guidance_skip", props: [
            "arm": arm.rawValue, "reason": "declined",
        ])
    }

    func markPreoptimizeStarted(runId: String) {
        sink?.track("first_photo_preoptimize_start", props: [
            "arm": arm.rawValue, "run_id": runId,
        ])
    }

    func markPreoptimizeCompleted(runId: String, success: Bool) {
        sink?.track("first_photo_preoptimize_complete", props: [
            "arm": arm.rawValue, "run_id": runId,
            "outcome": success ? "success" : "failed",
        ])
    }

    /// At-most-once per installation: fires `first_photo_activation_complete`
    /// after the first successfully saved capture that was genuinely optimized
    /// at shutter time. Returns true exactly once — the call that records it.
    @discardableResult
    func recordActivationIfNeeded() -> Bool {
        guard !hasActivated else { return false }
        defaults.set(true, forKey: Self.activatedKey)
        state = .completed
        let elapsed = elapsedSinceFirstAppOpen() ?? -1
        sink?.track("first_photo_activation_complete", props: [
            "arm": arm.rawValue,
            "elapsed_sec": "\(Int(elapsed))",
            "within_window": (elapsed >= 0 && elapsed <= Self.activationWindow) ? "1" : "0",
        ])
        return true
    }
}
