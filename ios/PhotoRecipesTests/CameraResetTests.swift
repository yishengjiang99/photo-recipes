import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// "Reset camera": one tap back to the app's defaults. Pins what a reset
/// changes (every session lever) and what it keeps (front/back, grid, mirror).
@MainActor
final class CameraResetTests: XCTestCase {

    /// The build-78 P0 state: front camera, AE/AF LOCK, custom exposure,
    /// Cool Blue look owned by AO, flash on, "Portrait Pop" above the shutter.
    private func modified(isFront: Bool = true, showGrid: Bool = false, mirror: Bool = false) -> CameraResetState {
        CameraResetState(
            exposureLocked: true,
            focusLocked: true,
            whiteBalanceLocked: true,
            customExposure: true,
            exposureBias: -2,
            captureMode: .manual,
            focusPoint: CGPoint(x: 0.2, y: 0.8),
            lens: .tele,
            zoomFactor: 2.5,
            lensPosition: 0.1,
            flash: .on,
            torchOn: true,
            lowLightBoostOn: true,
            videoHDROn: true,
            preferredFrameRate: 24,
            subjectAreaMonitoring: true,
            activeLookId: "coolBlue",
            activeLookOwner: .auto,
            lookIntensity: 0.8,
            previewLUTId: "teal",
            hasPendingBracket: true,
            appliedRecipeId: "portrait-pop",
            appliedRecipeTitle: "Portrait Pop",
            clampMessages: ["Zoom 9.00× clamped to 5.00×"],
            applyNotes: ["Look “Cool Blue” @ 80% — baking preview & still."],
            optimizeReason: "Dim face",
            apertureGuidance: "f/1.8 guidance",
            simulatedApertureCoach: "f/2.0 guidance only — phone lens is fixed.",
            isFront: isFront,
            showGrid: showGrid,
            mirrorFrontPhotos: mirror)
    }

    // MARK: - Defaults

    func testDefaults_matchWhatTheAppShips() {
        XCTAssertEqual(CameraDefaults.flash, .off, "flash ships off — never auto")
        XCTAssertEqual(CameraSession.FlashCycle.off, CameraDefaults.flash)
        XCTAssertEqual(CameraDefaults.captureMode, .auto)
        XCTAssertEqual(CameraDefaults.exposureBias, 0)
        XCTAssertEqual(CameraDefaults.zoomFactor, 1)
        XCTAssertEqual(CameraDefaults.lens, .wide)
        XCTAssertEqual(CameraDefaults.pointOfInterest, CGPoint(x: 0.5, y: 0.5))
        XCTAssertFalse(CameraDefaults.lowLightBoost)
        XCTAssertFalse(CameraDefaults.torch)
        XCTAssertEqual(CameraDefaults.lookIntensity, 0.55, accuracy: 1e-9)
        XCTAssertEqual(CameraDefaults.lookIntensity, CreativeLookCatalog.defaultIntensity)
        XCTAssertEqual(CameraDefaults.resetStatusCopy, "Camera reset")
        XCTAssertEqual(CameraDefaults.resetStatusDuration, 1.5, accuracy: 0.01)
    }

    // MARK: - What a reset changes

    func testReset_returnsEverySessionLeverToDefaults() {
        let r = CameraResetPlan.reset(modified())
        // Exposure / focus / WB: continuous auto, nothing locked (AE/AF LOCK gone).
        XCTAssertFalse(r.exposureLocked)
        XCTAssertFalse(r.focusLocked)
        XCTAssertFalse(r.whiteBalanceLocked)
        XCTAssertFalse(r.customExposure)
        XCTAssertEqual(r.exposureBias, 0)
        XCTAssertEqual(r.captureMode, .auto)
        XCTAssertNil(r.focusPoint, "no tap reticle — device POI goes to center")
        // Lens / zoom.
        XCTAssertEqual(r.lens, .wide)
        XCTAssertEqual(r.zoomFactor, 1)
        XCTAssertEqual(r.lensPosition, 0.5)
        // Light.
        XCTAssertEqual(r.flash, .off)
        XCTAssertFalse(r.torchOn)
        XCTAssertFalse(r.lowLightBoostOn)
        XCTAssertFalse(r.videoHDROn)
        XCTAssertNil(r.preferredFrameRate)
        XCTAssertFalse(r.subjectAreaMonitoring)
        // Look: none, intensity default, no owner (AO may choose again).
        XCTAssertNil(r.activeLookId)
        XCTAssertNil(r.activeLookOwner)
        XCTAssertEqual(r.lookIntensity, 0.55, accuracy: 1e-9)
        XCTAssertNil(r.previewLUTId)
        XCTAssertFalse(r.hasPendingBracket)
        // Recipe label above the shutter + status messages.
        XCTAssertNil(r.appliedRecipeId)
        XCTAssertNil(r.appliedRecipeTitle)
        XCTAssertTrue(r.clampMessages.isEmpty)
        XCTAssertTrue(r.applyNotes.isEmpty)
        XCTAssertNil(r.optimizeReason)
        XCTAssertNil(r.apertureGuidance)
        XCTAssertNil(r.simulatedApertureCoach)
        XCTAssertFalse(CameraResetPlan.isModified(r))
    }

    func testReset_userAndForcedLookOwnershipAlsoCleared() {
        for owner: LookOwner in [.auto, .user, .forced] {
            var s = modified()
            s.activeLookOwner = owner
            XCTAssertNil(CameraResetPlan.reset(s).activeLookOwner, "\(owner)")
        }
    }

    // MARK: - What a reset keeps

    func testReset_keepsCameraPositionGridAndMirror() {
        for front in [true, false] {
            for grid in [true, false] {
                for mirror in [true, false] {
                    let r = CameraResetPlan.reset(modified(isFront: front, showGrid: grid, mirror: mirror))
                    XCTAssertEqual(r.isFront, front)
                    XCTAssertEqual(r.showGrid, grid)
                    XCTAssertEqual(r.mirrorFrontPhotos, mirror)
                }
            }
        }
    }

    func testReset_isIdempotent() {
        let once = CameraResetPlan.reset(modified())
        XCTAssertEqual(CameraResetPlan.reset(once), once)
    }

    // MARK: - Modified detection

    func testIsModified_eachLeverAloneCounts() {
        let base = CameraResetPlan.reset(modified())
        XCTAssertFalse(CameraResetPlan.isModified(base))
        let mutations: [(String, (inout CameraResetState) -> Void)] = [
            ("aeLock", { $0.exposureLocked = true }),
            ("afLock", { $0.focusLocked = true }),
            ("wbLock", { $0.whiteBalanceLocked = true }),
            ("custom", { $0.customExposure = true }),
            ("bias", { $0.exposureBias = 0.7 }),
            ("mode", { $0.captureMode = .shutter }),
            ("tap", { $0.focusPoint = CGPoint(x: 0.3, y: 0.3) }),
            ("lens", { $0.lens = .ultraWide }),
            ("zoom", { $0.zoomFactor = 2 }),
            ("flash", { $0.flash = .auto }),
            ("torch", { $0.torchOn = true }),
            ("boost", { $0.lowLightBoostOn = true }),
            ("look", { $0.activeLookId = "warmGlow" }),
            ("recipe", { $0.appliedRecipeTitle = "Portrait Pop" }),
            ("status", { $0.applyNotes = ["x"] }),
        ]
        for (name, mutate) in mutations {
            var s = base
            mutate(&s)
            XCTAssertTrue(CameraResetPlan.isModified(s), name)
        }
        // Kept preferences never make the camera "modified".
        var kept = base
        kept.isFront.toggle()
        kept.showGrid.toggle()
        kept.mirrorFrontPhotos.toggle()
        XCTAssertFalse(CameraResetPlan.isModified(kept))
    }

    func testCancelsAllInFlightWork() {
        XCTAssertEqual(CameraResetPlan.cancels, Set(CameraResetPlan.InFlightWork.allCases))
        for w: CameraResetPlan.InFlightWork in [.autoOptimizeRun, .cloudRefine, .voiceIntent,
                                                .recommend, .whiteBalanceLockWait, .selfieLightApply] {
            XCTAssertTrue(CameraResetPlan.cancels.contains(w), w.rawValue)
        }
    }

    // MARK: - CameraSession.resetToDefaults (no device: published state)

    func testSession_resetToDefaults_resetsPublishedStateAndKeepsPreferences() {
        let session = CameraSession()
        let mirrorBefore = session.mirrorFrontPhotos
        session.setActiveLook(CreativeLook(id: "coolBlue", intensity: 0.8), owner: .auto)
        session.isFront = true
        session.showGrid = false
        session.exposureLocked = true
        session.focusLocked = true
        session.whiteBalanceLocked = true
        session.evBias = -1.7
        session.captureMode = .manual
        session.focusPoint = CGPoint(x: 0.1, y: 0.9)
        session.selectedLens = .tele
        session.lensPosition = 0.2
        session.flash = .on
        session.torchOn = true
        session.lowLightBoostOn = true
        session.videoHDROn = true
        session.preferredFrameRate = 30
        session.previewLUTId = "lut"
        session.appliedRecipeId = "portrait-pop"
        session.appliedRecipeTitle = "Portrait Pop"
        session.clampMessages = ["clamped"]
        session.optimizeReason = "why"
        session.apertureGuidance = "f/1.8"
        session.simulatedApertureCoach = "coach"
        XCTAssertTrue(session.isModifiedFromDefaults)
        let epoch = session.resetEpoch

        session.resetToDefaults(reason: "test")

        XCTAssertGreaterThan(session.resetEpoch, epoch, "in-flight device work is fenced")
        XCTAssertFalse(session.exposureLocked || session.focusLocked, "AE/AF LOCK badge gone")
        XCTAssertFalse(session.whiteBalanceLocked)
        XCTAssertEqual(session.evBias, 0)
        XCTAssertEqual(session.captureMode, .auto)
        XCTAssertNil(session.focusPoint)
        XCTAssertEqual(session.selectedLens, .wide)
        XCTAssertEqual(session.lensPosition, 0.5)
        XCTAssertEqual(session.flash, .off)
        XCTAssertFalse(session.torchOn)
        XCTAssertFalse(session.lowLightBoostOn)
        XCTAssertFalse(session.videoHDROn)
        XCTAssertNil(session.preferredFrameRate)
        XCTAssertNil(session.activeCreativeLook)
        XCTAssertNil(session.activeLookOwner)
        XCTAssertNil(session.previewLUTId)
        XCTAssertNil(session.pendingBracket)
        XCTAssertNil(session.appliedRecipeId)
        XCTAssertNil(session.appliedRecipeTitle)
        XCTAssertTrue(session.clampMessages.isEmpty)
        XCTAssertTrue(session.applyNotes.isEmpty)
        XCTAssertNil(session.optimizeReason)
        XCTAssertNil(session.apertureGuidance)
        XCTAssertNil(session.simulatedApertureCoach)
        XCTAssertFalse(session.isModifiedFromDefaults)
        // Kept.
        XCTAssertTrue(session.isFront)
        XCTAssertFalse(session.showGrid)
        XCTAssertEqual(session.mirrorFrontPhotos, mirrorBefore)
    }

    // MARK: - AutoOptimizeController.handleUserReset

    func testOptimizer_handleUserReset_dropsRunStateAndSelfieOwnership() {
        let optimizer = AutoOptimizeController()
        optimizer.phase = .ready
        optimizer.verifyWarning = "Custom exposure came out ~2 stops darker — kept auto exposure"
        optimizer.suggestedLook = CreativeLook(id: "coolBlue", intensity: 0.5)
        optimizer.autoAppliedLookId = "coolBlue"
        optimizer.chosenRecipeId = "portrait-pop"
        optimizer.chosenRecipeTitle = "Portrait Pop"
        optimizer.isCloudRefining = true
        optimizer.alsoTryRecipeId = "night"

        optimizer.handleUserReset()

        XCTAssertEqual(optimizer.phase, .idle)
        XCTAssertNil(optimizer.verifyWarning)
        XCTAssertNil(optimizer.suggestedLook)
        XCTAssertNil(optimizer.autoAppliedLookId)
        XCTAssertNil(optimizer.selfieAutoApplied)
        XCTAssertNil(optimizer.chosenRecipeId)
        XCTAssertNil(optimizer.chosenRecipeTitle)
        XCTAssertFalse(optimizer.isCloudRefining)
        XCTAssertNil(optimizer.alsoTryRecipeId)
        XCTAssertEqual(optimizer.applyFeedbackToken, 0)
    }
}
