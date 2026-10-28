import Foundation

/// Monotonic clock seam — durations must never use wall-clock time (NTP steps
/// and timezone changes would corrupt latency percentiles).
protocol MonotonicClock {
    /// Nanoseconds from an arbitrary monotonic origin.
    func nowNanoseconds() -> UInt64
}

struct SystemMonotonicClock: MonotonicClock {
    func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

/// Auto Optimize pipeline stages (Workstream E), in pipeline order.
enum OptimizeStage: String, CaseIterable {
    case requested
    case cameraReadyWait
    case meteringPrep
    case aeConvergence
    case inference
    case apply
    case verify
    case complete
    case fallback
}

/// Structured per-stage timing for one optimize run.
///
/// Emits (all gated by `optimize_stage_timing_enabled` at the call site via
/// the injected `enabled` closure):
/// - `optimize_stage_complete` per finished stage, with `stage` + `duration_ms`
/// - `optimize_latency_summary` once from `finish(outcome:)`, with the total
///   and one `stage_<name>_ms` prop per measured stage
/// - `optimize_fallback` from `recordFallback(reason:)`
///
/// Analytics failure is non-blocking by construction: the sink is the
/// existing soft-fail `Analytics` (or a test fake).
final class OptimizeStageTimer {
    private let clock: MonotonicClock
    private let sink: AnalyticsEventSink?
    private let enabled: () -> Bool
    private let runId: String
    private let trigger: String
    private let lens: String

    private var runStartNs: UInt64?
    private var stageStartNs: [OptimizeStage: UInt64] = [:]
    private(set) var stageDurationsMs: [OptimizeStage: Int] = [:]
    private var didFinish = false

    init(
        clock: MonotonicClock = SystemMonotonicClock(),
        sink: AnalyticsEventSink?,
        enabled: @escaping () -> Bool,
        runId: String,
        trigger: String,
        lens: String
    ) {
        self.clock = clock
        self.sink = sink
        self.enabled = enabled
        self.runId = runId
        self.trigger = trigger
        self.lens = lens
    }

    func beginRun() {
        runStartNs = clock.nowNanoseconds()
        beginStage(.requested)
    }

    func beginStage(_ stage: OptimizeStage) {
        stageStartNs[stage] = clock.nowNanoseconds()
    }

    /// Ends a stage: records its duration and emits `optimize_stage_complete`.
    /// Ending a stage that was never begun is a no-op. If `next` is given, that
    /// stage begins at the same instant (no unmeasured gap).
    func endStage(_ stage: OptimizeStage, next: OptimizeStage? = nil) {
        let now = clock.nowNanoseconds()
        if let start = stageStartNs[stage] {
            stageStartNs[stage] = nil
            let ms = Int((now &- start) / 1_000_000)
            stageDurationsMs[stage] = ms
            if enabled() {
                sink?.track("optimize_stage_complete", props: [
                    "run_id": runId,
                    "trigger": trigger,
                    "lens": lens,
                    "stage": stage.rawValue,
                    "duration_ms": "\(ms)",
                ])
            }
        }
        if let next { stageStartNs[next] = now }
    }

    func recordFallback(reason: String) {
        guard enabled() else { return }
        sink?.track("optimize_fallback", props: [
            "run_id": runId,
            "trigger": trigger,
            "lens": lens,
            "reason": reason,
        ])
    }

    /// Terminal summary — emits at most once per timer.
    func finish(outcome: String) {
        guard !didFinish else { return }
        didFinish = true
        endStage(.requested)
        guard enabled(), let start = runStartNs else { return }
        let totalMs = Int((clock.nowNanoseconds() &- start) / 1_000_000)
        var props: [String: String] = [
            "run_id": runId,
            "trigger": trigger,
            "lens": lens,
            "outcome": outcome,
            "total_ms": "\(totalMs)",
            "duration_ms": "\(totalMs)",
        ]
        for (stage, ms) in stageDurationsMs where stage != .requested {
            props["stage_\(stage.rawValue)_ms"] = "\(ms)"
        }
        sink?.track("optimize_latency_summary", props: props)
    }
}

// MARK: - AE convergence diagnostics

/// Diagnostic props for `ae_converge_timeout`. Every value must come from a
/// real signal at the emission site — pass nil for anything unavailable and it
/// is reported as "unknown", never fabricated.
enum AEDiagnostics {
    static func timeoutProps(
        lens: String,
        phaseAtTimeout: String,
        wasLensSwitching: Bool?,
        wasCaptureInFlight: Bool,
        exposureLocked: Bool?
    ) -> [String: String] {
        [
            "lens": lens,
            "phase_at_timeout": phaseAtTimeout,
            "was_lens_switching": wasLensSwitching.map { $0 ? "1" : "0" } ?? "unknown",
            "was_capture_in_flight": wasCaptureInFlight ? "1" : "0",
            "exposure_locked": exposureLocked.map { $0 ? "1" : "0" } ?? "unknown",
        ]
    }
}

// MARK: - Missing-metering diagnostics

/// Why `ao_metering_missing` fired (Workstream E). The solver's fallback site
/// only knows which metered values were absent, so classification is limited
/// to what that absence pattern proves; deeper causes (unsupported capability
/// vs transient state) need device signals the solver does not have today and
/// are deliberately not guessed.
enum MeteringMissingReason: String {
    case missingInput
    case unsupportedCapability
    case metadataUnavailable
    case transientState
    case internalError

    static func classify(hasExposureSeconds: Bool, hasISO: Bool) -> MeteringMissingReason {
        switch (hasExposureSeconds, hasISO) {
        case (false, false): return .missingInput
        case (true, false), (false, true): return .metadataUnavailable
        case (true, true): return .internalError // unreachable at the call site
        }
    }
}
