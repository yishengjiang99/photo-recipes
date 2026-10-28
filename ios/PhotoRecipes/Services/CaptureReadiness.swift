import Foundation

/// Capture readiness as a DERIVED state (Workstream B) — computed from the
/// camera session + optimizer inputs on every read. There are deliberately no
/// independently mutable booleans here: a single derivation function is the
/// only way to obtain a state, so the UI can never disagree with the pipeline.
enum CaptureReadiness: Equatable {
    case cameraUnavailable
    case cameraStarting
    case ready
    case optimizing
    case optimizedCaptureReady
    case capturing
    case saved
    case recoverableError(String)

    /// The shutter must stay enabled in every state where the camera can
    /// safely capture — including while an optimization is running.
    var shutterEnabled: Bool {
        switch self {
        case .ready, .optimizing, .optimizedCaptureReady, .saved: return true
        case .cameraUnavailable, .cameraStarting, .capturing, .recoverableError:
            return false
        }
    }

    var isOptimizedCaptureReady: Bool { self == .optimizedCaptureReady }
}

struct CaptureReadinessInputs {
    var sessionRunning: Bool
    var sessionStarting: Bool = false
    var optimizerRunning: Bool = false
    var optimizerReady: Bool = false
    /// False when the ready result was invalidated (reset / undo / lens flip /
    /// generation change) after it completed.
    var optimizerResultValid: Bool = false
    var isCapturing: Bool = false
    var justSaved: Bool = false
    var errorMessage: String? = nil
}

enum CaptureReadinessDerivation {
    static func derive(_ i: CaptureReadinessInputs) -> CaptureReadiness {
        if let error = i.errorMessage, !error.isEmpty {
            return .recoverableError(error)
        }
        if i.isCapturing { return .capturing }
        if i.justSaved { return .saved }
        guard i.sessionRunning else {
            return i.sessionStarting ? .cameraStarting : .cameraUnavailable
        }
        if i.optimizerRunning { return .optimizing }
        if i.optimizerReady && i.optimizerResultValid { return .optimizedCaptureReady }
        return .ready
    }
}

// MARK: - Optimize → capture attribution

/// How a capture relates to the most recent optimization run. Only
/// `.afterComplete` counts as an optimized capture: a run whose settings were
/// undone, replaced by manual overrides, or invalidated by a lens flip / reset
/// / generation change before shutter time must NOT be credited.
enum CaptureClassification: String {
    case afterComplete
    case during
    case afterUndo
    case afterFailure
    case afterManualOverride
    case afterLensFlipOrReset
    case none

    var countsAsOptimizedCapture: Bool { self == .afterComplete }
}

struct OptimizeRunContext: Equatable {
    var runId: String
    var cameraGeneration: Int
    /// "front" / "back".
    var lens: String
    var completedAt: Date
}

/// Pure attribution tracker. The controller/view layer feeds it lifecycle
/// facts; it owns no camera state of its own.
struct OptimizeAttribution {
    /// Reuses the existing 30 s capture window
    /// (`AutoOptimizeController.takeRecentRunIdForCapture` /
    /// `scheduleCaptureWindowCheck`), so the new classification agrees with
    /// the legacy `optimize_photo_captured` / `optimize_capture_abandoned`
    /// outcome labels by construction.
    static let window: TimeInterval = 30

    private(set) var activeRun: OptimizeRunContext?
    private(set) var inFlightRunId: String?
    private(set) var invalidation: CaptureClassification?
    private(set) var manualOverrideApplied = false

    mutating func recordRunStarted(runId: String) {
        inFlightRunId = runId
        invalidation = nil
        manualOverrideApplied = false
    }

    mutating func recordRunCompleted(_ run: OptimizeRunContext) {
        activeRun = run
        inFlightRunId = nil
        invalidation = nil
        manualOverrideApplied = false
    }

    mutating func recordRunFailed() {
        inFlightRunId = nil
        activeRun = nil
        invalidation = .afterFailure
    }

    /// reason must be one of `.afterUndo`, `.afterFailure`,
    /// `.afterLensFlipOrReset` — the invalidating lifecycle events.
    mutating func invalidate(reason: CaptureClassification) {
        inFlightRunId = nil
        activeRun = nil
        invalidation = reason
    }

    mutating func recordManualOverride() {
        manualOverrideApplied = true
    }

    /// Classify a shutter press at `date` against the tracked run.
    /// `currentGeneration` / `currentLens` come from the live camera at
    /// capture time; a mismatch means the run's settings no longer apply.
    func classifyCapture(
        at date: Date,
        currentGeneration: Int,
        currentLens: String
    ) -> CaptureClassification {
        if inFlightRunId != nil { return .during }
        if let invalidation { return invalidation }
        guard let run = activeRun else { return .none }
        if manualOverrideApplied { return .afterManualOverride }
        guard run.cameraGeneration == currentGeneration, run.lens == currentLens
        else { return .afterLensFlipOrReset }
        guard date.timeIntervalSince(run.completedAt) <= Self.window
        else { return .none }
        return .afterComplete
    }
}
