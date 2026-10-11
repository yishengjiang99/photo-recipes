import CoreGraphics
import Foundation

// "Reset camera" (build 80 follow-up to the #165 P0): one tap returns the live
// camera to the app's shipping defaults. The rules live here, free of
// AVFoundation, so what a reset changes — and what it must keep — is
// unit-tested. `CameraSession.resetToDefaults(reason:)` is the device-backed
// entry point; it extends the #165 restart reset (`resetToContinuousAuto`).

/// The app's shipping camera defaults (what a fresh install / first start shows).
enum CameraDefaults {
    /// `CameraSession.flash` ships `.off` (never auto) — the user opts in.
    static let flash: CameraSession.FlashCycle = .off
    static let captureMode: CameraSession.CaptureMode = .auto
    static let exposureBias: Float = 0
    /// 1× on the wide lens (`bestDevice` picks the wide-angle camera).
    static let zoomFactor: Double = 1
    static let lens: CameraSession.LensChoice = .wide
    /// Neutral manual-focus slider position (focus itself goes back to continuous AF).
    static let lensPosition: Double = 0.5
    /// Focus + exposure point of interest — the frame center.
    static let pointOfInterest = CGPoint(x: 0.5, y: 0.5)
    /// `AVCaptureDevice.automaticallyEnablesLowLightBoostWhenAvailable` defaults to false.
    static let lowLightBoost = false
    static let videoHDR = false
    static let torch = false
    /// Creative Look intensity default (0.55).
    static let lookIntensity: Double = CreativeLookCatalog.defaultIntensity

    /// Transient status shown after a reset.
    static let resetStatusCopy = "Camera reset"
    static let resetStatusDuration: TimeInterval = 1.5
}

/// The camera state a reset looks at. "Session" fields are the active
/// capture state and go back to `CameraDefaults`; "kept" fields are the
/// user's position and preferences, which a reset never touches.
struct CameraResetState: Equatable {
    // MARK: Session state (reset)
    var exposureLocked: Bool
    var focusLocked: Bool
    var whiteBalanceLocked: Bool
    /// Custom shutter/ISO is programmed (device in `.custom` exposure).
    var customExposure: Bool
    var exposureBias: Float
    var captureMode: CameraSession.CaptureMode
    /// UI-space reticle; nil = no tap point (center metering).
    var focusPoint: CGPoint?
    var lens: CameraSession.LensChoice
    var zoomFactor: Double
    var lensPosition: Double
    var flash: CameraSession.FlashCycle
    var torchOn: Bool
    var lowLightBoostOn: Bool
    var videoHDROn: Bool
    var preferredFrameRate: Double?
    var subjectAreaMonitoring: Bool
    var activeLookId: String?
    var activeLookOwner: LookOwner?
    var lookIntensity: Double
    var previewLUTId: String?
    var hasPendingBracket: Bool
    var appliedRecipeId: String?
    var appliedRecipeTitle: String?
    var clampMessages: [String]
    var applyNotes: [String]
    var optimizeReason: String?
    var apertureGuidance: String?
    var simulatedApertureCoach: String?

    // MARK: Kept (position + preferences)
    var isFront: Bool
    var showGrid: Bool
    var mirrorFrontPhotos: Bool
}

enum CameraResetPlan {
    /// In-flight work a reset cancels before it writes the defaults, so nothing
    /// lands on the device afterwards.
    enum InFlightWork: String, CaseIterable {
        /// Auto Optimize run (incl. its exposure verify loop).
        case autoOptimizeRun
        /// Pass 2 cloud refine.
        case cloudRefine
        /// Voice-driven Recommend / AO task.
        case voiceIntent
        /// Recommend SSE in flight.
        case recommend
        /// `lockWhiteBalanceAfterExposureSettles` waiting for AE to settle.
        case whiteBalanceLockWait
        /// A selfie look's capture-light apply (`applySelfiePreset`).
        case selfieLightApply
    }

    /// A reset cancels every kind of in-flight work.
    static let cancels: Set<InFlightWork> = Set(InFlightWork.allCases)

    /// The state after a reset: every session field at its default, every
    /// kept field untouched.
    static func reset(_ s: CameraResetState) -> CameraResetState {
        var r = s
        r.exposureLocked = false
        r.focusLocked = false
        r.whiteBalanceLocked = false
        r.customExposure = false
        r.exposureBias = CameraDefaults.exposureBias
        r.captureMode = CameraDefaults.captureMode
        r.focusPoint = nil
        r.lens = CameraDefaults.lens
        r.zoomFactor = CameraDefaults.zoomFactor
        r.lensPosition = CameraDefaults.lensPosition
        r.flash = CameraDefaults.flash
        r.torchOn = CameraDefaults.torch
        r.lowLightBoostOn = CameraDefaults.lowLightBoost
        r.videoHDROn = CameraDefaults.videoHDR
        r.preferredFrameRate = nil
        r.subjectAreaMonitoring = false
        r.activeLookId = nil
        r.activeLookOwner = nil // AO / selfie policy may choose a look again
        r.lookIntensity = CameraDefaults.lookIntensity
        r.previewLUTId = nil
        r.hasPendingBracket = false
        r.appliedRecipeId = nil
        r.appliedRecipeTitle = nil
        r.clampMessages = []
        r.applyNotes = []
        r.optimizeReason = nil
        r.apertureGuidance = nil
        r.simulatedApertureCoach = nil
        // isFront / showGrid / mirrorFrontPhotos: kept.
        return r
    }

    /// True when anything a reset would change differs from the defaults.
    static func isModified(_ s: CameraResetState) -> Bool {
        reset(s) != s
    }
}
