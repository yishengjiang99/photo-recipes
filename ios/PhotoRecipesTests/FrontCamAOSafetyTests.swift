import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// P0 (TestFlight build 78): front-camera Auto Optimize turned a dim-but-visible
/// selfie black, locked AE/AF, turned the flash ON under a non-selfie "Cool Blue"
/// look and claimed "Brightened 5 stops, still a bit dark". These tests pin the
/// safety rails: clamping, the darkening-revert guard, honest copy, restart
/// reset, front flash, and look precedence against the async cloud refine.
@MainActor
final class FrontCamAOSafetyTests: XCTestCase {

    // A typical front (TrueDepth) format vs a back-camera write.
    private let frontLimits = ExposurePlanner.DeviceLimits(
        minShutterSeconds: 1.0 / 14000, maxShutterSeconds: 1.0 / 3,
        minISO: 25, maxISO: 2304)

    // MARK: - (a) Clamping to the CURRENT device's active format

    func testClamp_backCameraValuesClampToFrontFormat() {
        let r = ExposureClamp.clamp(durationSeconds: 1.0 / 16000, iso: 12800, limits: frontLimits)
        XCTAssertEqual(r.durationSeconds, 1.0 / 14000, accuracy: 1e-12)
        XCTAssertEqual(r.iso, 2304)
        XCTAssertTrue(r.clamped)
    }

    func testClamp_longShutterAndLowISOClampIntoRange() {
        let r = ExposureClamp.clamp(durationSeconds: 1.0, iso: 10, limits: frontLimits)
        XCTAssertEqual(r.durationSeconds, 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(r.iso, 25)
        XCTAssertTrue(r.clamped)
    }

    func testClamp_inRangeUntouched_andNonFiniteSanitized() {
        let ok = ExposureClamp.clamp(durationSeconds: 1.0 / 60, iso: 400, limits: frontLimits)
        XCTAssertEqual(ok.durationSeconds, 1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(ok.iso, 400)
        XCTAssertFalse(ok.clamped)
        let bad = ExposureClamp.clamp(durationSeconds: .nan, iso: .infinity, limits: frontLimits)
        XCTAssertTrue(bad.durationSeconds.isFinite)
        XCTAssertTrue(bad.iso.isFinite)
        XCTAssertGreaterThanOrEqual(bad.durationSeconds, frontLimits.minShutterSeconds)
        XCTAssertLessThanOrEqual(bad.iso, frontLimits.maxISO)
    }

    func testFrontPolicy_dimFrontPrefersSystemAuto() {
        XCTAssertTrue(FrontExposurePolicy.useSystemAuto(
            isFront: true, sceneEV100: 3.4, planResidualEV: 0,
            plannedShutterSeconds: 1.0 / 60, meteredShutterSeconds: 1.0 / 60))
        // Plan already under auto, even in brighter light.
        XCTAssertTrue(FrontExposurePolicy.useSystemAuto(
            isFront: true, sceneEV100: 9, planResidualEV: -0.8,
            plannedShutterSeconds: 1.0 / 60, meteredShutterSeconds: 1.0 / 60))
        // Shorter shutter than auto metered.
        XCTAssertTrue(FrontExposurePolicy.useSystemAuto(
            isFront: true, sceneEV100: 9, planResidualEV: 0,
            plannedShutterSeconds: 1.0 / 60, meteredShutterSeconds: 1.0 / 15))
        // Bright front scene with a reachable plan → custom allowed.
        XCTAssertFalse(FrontExposurePolicy.useSystemAuto(
            isFront: true, sceneEV100: 10, planResidualEV: 0,
            plannedShutterSeconds: 1.0 / 120, meteredShutterSeconds: 1.0 / 120))
        // Back camera never takes this path.
        XCTAssertFalse(FrontExposurePolicy.useSystemAuto(
            isFront: false, sceneEV100: 2, planResidualEV: -3,
            plannedShutterSeconds: 1.0 / 60, meteredShutterSeconds: 1.0 / 4))
    }

    func testFrontPolicy_biasNeverNegativeInTheDark() {
        XCTAssertEqual(FrontExposurePolicy.biasString(targetEV: -0.3, dark: true), "+0.0")
        XCTAssertEqual(FrontExposurePolicy.biasString(targetEV: 0.3, dark: true), "+0.3")
        XCTAssertEqual(FrontExposurePolicy.biasString(targetEV: 3, dark: true), "+1.0")
        XCTAssertEqual(FrontExposurePolicy.biasString(targetEV: -0.3, dark: false), "-0.3")
    }

    func testCompensatedEAuto_unconvergedDarkReadIsLiftedBack() {
        // Converged → unchanged.
        XCTAssertEqual(ExposurePlanner.compensatedEAuto(product: 200, exposureTargetOffset: 0.1), 200, accuracy: 1e-9)
        XCTAssertEqual(ExposurePlanner.compensatedEAuto(product: 200, exposureTargetOffset: nil), 200, accuracy: 1e-9)
        // AE still ramping up from a black custom write: 2 stops under → ×4.
        XCTAssertEqual(ExposurePlanner.compensatedEAuto(product: 50, exposureTargetOffset: -2), 200, accuracy: 1e-9)
        // Clamped to ±4 stops.
        XCTAssertEqual(ExposurePlanner.compensatedEAuto(product: 1, exposureTargetOffset: -8), 16, accuracy: 1e-9)
    }

    // MARK: - Verify loop never corrects the wrong way

    func testVerifyLoop_underexposedNeverShortensShutterBelowCurrent() {
        // Build 78 shape: 1/8 s metered by auto, ISO already maxed, motion cap 1/60.
        // The old `.auto` branch returned min(want, cap) = 1/60 — a "brighten"
        // step that cut the exposure 3 stops.
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: .auto(shutterCapSeconds: 1.0 / 60),
            shutterCapSeconds: 1.0 / 60,
            currentShutterSeconds: 1.0 / 8, currentISO: 2304,
            isoRange: 25...2304, shutterRange: 1.0 / 14000...1.0 / 3)
        XCTAssertGreaterThanOrEqual(c.shutterSeconds, 1.0 / 8 - 1e-12)
        XCTAssertGreaterThanOrEqual(c.iso, 2304)
    }

    func testNeverAgainstError() {
        XCTAssertEqual(ExposureVerifyLoop.neverAgainstError(1.0 / 60, current: 1.0 / 8, error: -2), 1.0 / 8)
        XCTAssertEqual(ExposureVerifyLoop.neverAgainstError(1.0 / 4, current: 1.0 / 8, error: 2), 1.0 / 8)
        XCTAssertEqual(ExposureVerifyLoop.neverAgainstError(1.0 / 4, current: 1.0 / 8, error: -2), 1.0 / 4)
    }

    // MARK: - (b) Darkening-revert guard

    func testGuard_build78ScenarioReverts() {
        // Auto: 1/8 s × ISO 1600 (dim room). AO: 1/60 s × ISO 2304, meter −5 EV,
        // preview luma 0.28 → 0.03.
        let v = ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: (1.0 / 8) * 1600,
            eAfter: (1.0 / 60) * 2304,
            offsetAfter: -5,
            lumaBefore: 0.28, lumaAfter: 0.03,
            targetEV: 0.3))
        guard case .revert(let stops, let nearBlack) = v else {
            return XCTFail("build 78 must revert, got \(v)")
        }
        XCTAssertTrue(nearBlack)
        XCTAssertLessThan(stops, -2)
    }

    func testGuard_productAloneOverOneStopDarkerReverts() {
        let v = ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: 200, eAfter: 60, offsetAfter: nil,
            lumaBefore: nil, lumaAfter: nil, targetEV: 0))
        XCTAssertNotEqual(v, .ok)
    }

    func testGuard_lumaAloneOverOneStopDarkerReverts() {
        // EV-bias path (no custom write): only the measured preview luma.
        let v = ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: nil, eAfter: nil, offsetAfter: nil,
            lumaBefore: 0.40, lumaAfter: 0.20, targetEV: 0))
        XCTAssertNotEqual(v, .ok)
    }

    func testGuard_brighterOrIntendedDarkerIsOK() {
        XCTAssertEqual(ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: 200, eAfter: 240, offsetAfter: 0.1,
            lumaBefore: 0.30, lumaAfter: 0.33, targetEV: 0.3)), .ok)
        // A moody recipe asking −0.3 that lands −1.0 is within tolerance (−1.3).
        XCTAssertEqual(ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: 200, eAfter: 100, offsetAfter: -0.2,
            lumaBefore: nil, lumaAfter: nil, targetEV: -0.3)), .ok)
        // …but −1.6 is not.
        XCTAssertNotEqual(ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: 200, eAfter: 66, offsetAfter: nil,
            lumaBefore: nil, lumaAfter: nil, targetEV: -0.3)), .ok)
        // Nothing measured → never a spurious revert.
        XCTAssertEqual(ExposureSafetyGuard.evaluate(.init()), .ok)
    }

    func testGuard_nearBlackOffsetRevertsEvenWithoutLuma() {
        XCTAssertEqual(ExposureSafetyGuard.evaluate(.init(
            eAutoBefore: nil, eAfter: nil, offsetAfter: -3,
            lumaBefore: nil, lumaAfter: nil, targetEV: 0)),
            .revert(darkenedStops: -3, nearBlack: true))
    }

    func testRevertMessage_isHonest() {
        let black = ExposureSafetyGuard.revertMessage(.revert(darkenedStops: -5, nearBlack: true))
        XCTAssertEqual(black, "Too dark here for custom exposure — kept auto exposure")
        let two = ExposureSafetyGuard.revertMessage(.revert(darkenedStops: -2.2, nearBlack: false))
        XCTAssertEqual(two, "Custom exposure came out ~2 stops darker — kept auto exposure")
        XCTAssertNil(ExposureSafetyGuard.revertMessage(.ok))
        for m in [black, two].compactMap({ $0 }) {
            XCTAssertFalse(m.contains("Brightened"))
        }
    }

    // MARK: - Honest verify status (no false "Brightened 5 stops")

    func testVerifyNotes_build78_noFalseBrightenedClaim() {
        // Initial −5, one ISO step barely moved it: −4.6 remaining.
        let notes = AutoOptimizeController.verifyNotes(
            residual: -4.6, iterations: 1, initialError: -5, yieldNote: nil)
        XCTAssertEqual(notes, ["~5 stops too dark"])
        XCTAssertFalse(notes.joined().contains("Brightened"))
    }

    func testVerifyNotes_claimsOnlyMeasuredCorrection() {
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(residual: -2, iterations: 2, initialError: -5, yieldNote: nil),
            ["Brightened 3 stops, still ~2 stops too dark"])
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(residual: -0.5, iterations: 2, initialError: -3, yieldNote: nil),
            ["Brightened 3 stops, still a bit dark"])
        // A correction that went the wrong way is never called "Brightened".
        let wrong = AutoOptimizeController.verifyNotes(residual: -3, iterations: 1, initialError: -2, yieldNote: nil)
        XCTAssertEqual(wrong, ["~3 stops too dark"])
    }

    // MARK: - (c) Restart reset

    func testRestart_neverRestoresLockedOrCustomExposure() {
        let previous: [SessionRestartPolicy.State] = [
            .init(exposureMode: .custom, focusMode: .locked, exposureBias: 0.7, exposureLocked: true, focusLocked: true),
            .init(exposureMode: .locked, focusMode: .autoFocus, exposureBias: -1, exposureLocked: true, focusLocked: false),
            .init(exposureMode: .continuousAuto, focusMode: .continuousAuto, exposureBias: 0, exposureLocked: false, focusLocked: false),
        ]
        for p in previous {
            let s = SessionRestartPolicy.stateAfterRestart(previous: p)
            XCTAssertEqual(s.exposureMode, .continuousAuto)
            XCTAssertEqual(s.focusMode, .continuousAuto)
            XCTAssertEqual(s.exposureBias, 0)
            XCTAssertFalse(s.exposureLocked)
            XCTAssertFalse(s.focusLocked)
        }
    }

    // MARK: - (e) Front flash

    func testFrontFlash_nonSelfieLookNeverTurnsFlashOn() {
        XCTAssertNil(FrontFlashPolicy.resolve(
            requested: "on", isFront: true, finalLookId: "coolBlue", retinaFlashSupported: true))
        XCTAssertNil(FrontFlashPolicy.resolve(
            requested: "auto", isFront: true, finalLookId: nil, retinaFlashSupported: true))
        XCTAssertNil(FrontFlashPolicy.resolve(
            requested: "auto", isFront: true, finalLookId: "selfieGlow", retinaFlashSupported: true))
    }

    func testFrontFlash_lowLightSelfieOnlyWithRetinaFlash() {
        XCTAssertEqual(FrontFlashPolicy.resolve(
            requested: "on", isFront: true, finalLookId: "selfieLowLight", retinaFlashSupported: true), "on")
        XCTAssertNil(FrontFlashPolicy.resolve(
            requested: "on", isFront: true, finalLookId: "selfieLowLight", retinaFlashSupported: false))
        XCTAssertEqual(FrontFlashPolicy.resolve(
            requested: "off", isFront: true, finalLookId: "coolBlue", retinaFlashSupported: true), "off")
        // Back camera unchanged.
        XCTAssertEqual(FrontFlashPolicy.resolve(
            requested: "on", isFront: false, finalLookId: "coolBlue", retinaFlashSupported: false), "on")
    }

    // MARK: - (d) Selfie decision + precedence with the async refine

    private func dimCloseUpSelfie(kind: SubjectKind = .face, area: Float = 0.45) -> SceneFeatures {
        var f = SceneFeatures()
        f.isFrontCamera = true
        f.subjectKind = kind
        let side = sqrt(area)
        f.subjectBox = NormalizedBox(x: 0.5 - side / 2, y: 0.5 - side / 2, width: side, height: side)
        f.subjectAreaFraction = area
        f.faceCount = kind == .face ? 1 : 0
        f.sceneEV100 = 6 // EV estimate a touch high…
        f.meteredISO = 1600 // …but the front camera is at ISO 1600: low light.
        f.meteredExposureSeconds = 1.0 / 15
        f.subjectDeltaStops = 0
        f.semanticGroups = [.indoor: 0.8]
        return f
    }

    private func decide(_ f: SceneFeatures) -> SelfieAutoPolicy.Decision {
        SelfieAutoPolicy.decide(.init(
            isFrontCamera: true, features: f,
            aoTargets: PhoneTargets(ev: "+0.3", focusMode: "continuous",
                                    creativeLook: CreativeLook(id: "coolBlue", intensity: 0.4)),
            activeLook: nil, activeLookOwner: nil))
    }

    func testDimFaceFillingFrame_picksLowLight() {
        let c = decide(dimCloseUpSelfie()).choice
        XCTAssertEqual(c?.look.id, "selfieLowLight")
        XCTAssertEqual(c?.pick.reason, .lowLight)
        XCTAssertEqual(c?.replacedLookId, "coolBlue")
    }

    func testCloseUpHumanWithoutFaceRect_stillSelfie() {
        // Face detector missed the overflowing face; Vision saw the upper body.
        XCTAssertEqual(decide(dimCloseUpSelfie(kind: .human, area: 0.5)).choice?.look.id, "selfieLowLight")
        // A small human in the background is not a selfie.
        XCTAssertEqual(decide(dimCloseUpSelfie(kind: .human, area: 0.05)), .unchanged(.noFace))
    }

    func testLateServerLook_neverOverridesOnFront() {
        let cool = CreativeLook(id: "coolBlue", intensity: 0.4)
        // Selfie applied this run.
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(
            cool, selfieLookId: "selfieLowLight", activeLook: CreativeLook(id: "selfieLowLight"),
            isFrontCamera: true))
        // Even when Pass 1 left the finder empty (no face found), front never
        // takes a late server look.
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(
            cool, selfieLookId: nil, activeLook: nil, isFrontCamera: true))
        // Back camera keeps the fill-an-empty-finder rule.
        XCTAssertEqual(SelfieAutoPolicy.resolveServerLook(
            cool, selfieLookId: nil, activeLook: nil, isFrontCamera: false), cool)
    }

    func testPrecedenceOrdering_pass1ThenAsyncRefine() {
        // Pass 1: selfie policy decides; Pass 2 lands later on the same run.
        let pass1 = decide(dimCloseUpSelfie())
        let selfieId = pass1.choice?.look.id
        XCTAssertEqual(selfieId, "selfieLowLight")
        let late = SelfieAutoPolicy.resolveServerLook(
            CreativeLook(id: "coolBlue", intensity: 0.4),
            selfieLookId: selfieId, activeLook: pass1.choice?.look, isFrontCamera: true)
        XCTAssertNil(late, "selfie decision is final on front")
        // Generic rule: stale run never applies; forced always may.
        XCTAssertFalse(LookPrecedence.serverLookMayApply(isFront: false, forced: false, runIsCurrent: false, activeLookPresent: false))
        XCTAssertTrue(LookPrecedence.serverLookMayApply(isFront: true, forced: true, runIsCurrent: true, activeLookPresent: true))
        XCTAssertFalse(LookPrecedence.serverLookMayApply(isFront: true, forced: false, runIsCurrent: true, activeLookPresent: false))
        XCTAssertFalse(LookPrecedence.serverLookMayApply(isFront: false, forced: false, runIsCurrent: true, activeLookPresent: true))
        XCTAssertTrue(LookPrecedence.serverLookMayApply(isFront: false, forced: false, runIsCurrent: true, activeLookPresent: false))
    }

    func testPass2IntentTargets_frontStripsFlashFocusZoomLook() {
        let server = PhoneTargets(
            exposureDurationSec: 1.0 / 500, iso: "3200", ev: "+0.5",
            focusMode: "locked", zoom: 2.0, flash: "on",
            creativeLook: CreativeLook(id: "coolBlue", intensity: 0.4))
        let front = AutoOptimizeController.pass2IntentTargets(from: server, isFrontCamera: true)
        XCTAssertNil(front.flash)
        XCTAssertNil(front.focusMode)
        XCTAssertNil(front.zoom)
        XCTAssertNil(front.creativeLook)
        XCTAssertNil(front.exposureDurationSec)
        XCTAssertNil(front.iso)
        XCTAssertNil(front.ev)
        // Back camera keeps non-exposure intent.
        let back = AutoOptimizeController.pass2IntentTargets(from: server)
        XCTAssertEqual(back.flash, "on")
        XCTAssertEqual(back.zoom, 2.0)
    }

    // MARK: - Close-up face retry mapping

    func testPaddedFaceRetry_unpad() {
        let s = PaddedFaceRetry.scale
        let off = (1 - s) / 2
        // The whole original frame in the canvas maps back to the unit rect.
        let full = PaddedFaceRetry.unpad(CGRect(x: off, y: off, width: s, height: s))
        XCTAssertEqual(full?.minX ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(full?.width ?? -1, 1, accuracy: 1e-9)
        // A face overflowing the frame is clipped to it.
        let over = PaddedFaceRetry.unpad(CGRect(x: off - 0.05, y: off, width: s + 0.1, height: s))
        XCTAssertEqual(over?.minX ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(over?.maxX ?? -1, 1, accuracy: 1e-9)
        // Entirely in the padding → nil.
        XCTAssertNil(PaddedFaceRetry.unpad(CGRect(x: 0, y: 0, width: off * 0.9, height: off * 0.9)))
    }
}
