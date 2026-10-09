import XCTest
@testable import PhotoRecipes

final class SettingsSolverTests: XCTestCase {

    private var caps: DeviceCapabilities!
    private var ctx1150: SettingsSolver.SolveContext!

    override func setUp() {
        super.setUp()
        caps = DeviceCapabilities(
            supportsCustomExposure: true,
            supportsExposureTargetBias: true,
            supportsWhiteBalanceLock: true,
            supportsFocusLock: true,
            minExposureSeconds: 1 / 8000,
            maxExposureSeconds: 1,
            minISO: 50,
            maxISO: 3200,
            minEV: -2,
            maxEV: 2,
            deviceTypeName: "wide"
        )
        // Reference width matching the spec's example numbers
        // (900 px/s → ~0.05 s at 4% blur; 2000 px/s → ~1/30 at 6% streak).
        ctx1150 = SettingsSolver.SolveContext(frameWidthPx: 1150, fieldOfViewDegrees: 70, currentWBGains: nil)
    }

    private func baseFeatures() -> SceneFeatures {
        var f = SceneFeatures()
        f.meteredExposureSeconds = 1 / 60
        f.meteredISO = 800
        f.lensAperture = 1.8
        f.sceneEV100 = 4.6
        f.handShakeRadPerSec = 0.01
        return f
    }

    // MARK: - sharp-front-to-back

    func testSharpFrontToBack_meteredIndoor() {
        // Spec case: metered 1/60 s, ISO 800 indoor.
        // P = 13.33; the solver's t_shake = 1.5 / (0.01 × 2879px) ≈ 0.052 s
        // (frameWidth 4032) — but the recipe cap can only SHORTEN the
        // shutter, so the derived 1/(2f) handheld limit (≈ 1/51 s) binds.
        var ctx = ctx1150!
        ctx.frameWidthPx = 4032
        let sol = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: baseFeatures(),
            capabilities: caps, context: ctx)
        let t = sol.phoneTargets
        let handheld = ExposurePlanner.handheldLimitSeconds(fieldOfViewDegrees: 70)
        XCTAssertEqual(t.exposureDurationSec ?? -1, handheld, accuracy: 0.002)
        XCTAssertEqual(t.iso, "686")
        XCTAssertEqual(t.focusMode, "locked")
        XCTAssertEqual(t.focusPoint?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(t.focusPoint?.y ?? -1, 0.62, accuracy: 0.001)
        XCTAssertTrue(sol.clampMessages.isEmpty, "unexpected clamps: \(sol.clampMessages)")
        XCTAssertEqual(sol.shutterCapSeconds ?? -1, handheld, accuracy: 0.002)
    }

    func testSharpFrontToBack_highlightClip_appliesMinusEV() {
        var f = baseFeatures()
        f.highlightClipFraction = 0.05
        let sol = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: f,
            capabilities: caps, context: ctx1150)
        // EV −0.3 folded into the ISO solve (not a setEV call).
        XCTAssertEqual(sol.phoneTargets.ev, "-0.3")
    }

    // MARK: - blur-moving-subjects

    func testBlur_waterfall900pxPerSec_aboutPointZeroFive() {
        var f = baseFeatures()
        f.meteredExposureSeconds = 1 / 60
        f.meteredISO = 100
        f.sceneEV100 = 13
        f.subjectRelativeSpeedPxPerSec = 900
        let sol = SettingsSolver.solve(
            recipeId: "blur-moving-subjects", features: f,
            capabilities: caps, context: ctx1150)
        // t = 0.04 × 1150 / 900 ≈ 0.051 s wanted, but sceneEV100=13
        // overexposes at min ISO — the shutter yields to the slowest
        // correctly-exposed one (E_auto/ISO_min ≈ 0.033 s).
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 0.0333, accuracy: 0.01)
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("Bright light") }),
            "expected the shutter-yield message, got: \(sol.clampMessages)")
        XCTAssertEqual(sol.phoneTargets.focusMode, "locked")
    }

    func testBlur_brightDaylight_isoClampsAtMin_andNDNote() {
        var f = baseFeatures()
        f.meteredExposureSeconds = 1 / 500
        f.meteredISO = 100
        f.sceneEV100 = 15
        f.subjectRelativeSpeedPxPerSec = 900
        let sol = SettingsSolver.solve(
            recipeId: "blur-moving-subjects", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.iso, "50", "ISO must clamp at minimum")
        // E_auto = 1/500 × 100 = 0.2 → at ISO 50 the correct shutter is 1/250.
        // The ~0.05 s blur shutter would be ~3.7 stops over, so it yields.
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 1.0 / 250, accuracy: 1e-6)
        XCTAssertEqual(sol.residualEV ?? 99, 0, accuracy: 0.05, "must be correctly exposed")
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("Bright light") }),
            "expected the shutter-yield message, got: \(sol.clampMessages)")
        XCTAssertTrue(
            sol.coachOnly?.nd?.contains("ND") == true,
            "expected the ND coach note, got: \(sol.coachOnly?.nd ?? "nil")")
    }

    func testBlur_noMotion_usesMaxShutterWithNote() {
        var f = baseFeatures()
        f.subjectRelativeSpeedPxPerSec = 0
        let sol = SettingsSolver.solve(
            recipeId: "blur-moving-subjects", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("No subject motion") }),
            "got: \(sol.clampMessages)")
        // Handheld: never a full-second guess.
        XCTAssertLessThanOrEqual(sol.phoneTargets.exposureDurationSec ?? 99, 0.25 + 1e-9)
    }

    func testPanning_directSun_shutterYieldsToCorrectExposure() {
        // The device report: Panning picked in direct sun, 1/30 s locked at
        // min ISO, frame ~7 stops over and "A bit bright" with no fix.
        var f = baseFeatures()
        f.meteredExposureSeconds = 1.0 / 4000
        f.meteredISO = 50
        f.sceneEV100 = 15
        f.backgroundSpeedPxPerSec = 0
        let sol = SettingsSolver.solve(
            recipeId: "panning-sharp-subject", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.iso, "50")
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 1.0 / 4000, accuracy: 1e-7)
        XCTAssertEqual(sol.residualEV ?? 99, 0, accuracy: 0.05)
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("Bright light") }),
            "got: \(sol.clampMessages)")
    }

    // MARK: - panning-sharp-subject

    func testPanning_pan2000pxPerSec_aboutOneThirtieth() {
        var f = baseFeatures()
        f.backgroundSpeedPxPerSec = 2000
        f.subjectSpeedPxPerSec = 1900
        f.subjectRelativeSpeedPxPerSec = 100
        f.motionDirectionX = 1
        f.motionDirectionY = 0.1
        f.subjectKind = .human
        f.subjectBox = NormalizedBox(x: 0.35, y: 0.3, width: 0.3, height: 0.4)
        let sol = SettingsSolver.solve(
            recipeId: "panning-sharp-subject", features: f,
            capabilities: caps, context: ctx1150)
        // t = 0.06 × 1150 / 2000 ≈ 0.0345 s ≈ 1/30.
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 1 / 30, accuracy: 0.005)
        XCTAssertEqual(sol.phoneTargets.focusMode, "continuous")
        XCTAssertEqual(sol.phoneTargets.monitorSubjectAreaChange, true)
        XCTAssertEqual(sol.panCue?.direction, "horizontal")
        // Focus on the subject box center.
        XCTAssertEqual(sol.phoneTargets.focusPoint?.x ?? -1, 0.5, accuracy: 0.01)
        XCTAssertEqual(sol.phoneTargets.focusPoint?.y ?? -1, 0.5, accuracy: 0.01)
    }

    func testPanning_unknownPanSpeed_fallsBackToOneThirtieth() {
        var f = baseFeatures()
        f.backgroundSpeedPxPerSec = 0
        let sol = SettingsSolver.solve(
            recipeId: "panning-sharp-subject", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 1 / 30, accuracy: 0.001)
    }

    // MARK: - hdr-brights-darks

    func testHDR_bracketStopsFromSpread() {
        for (spread, expected) in [(11.0, 2.0), (8.0, 1.3), (5.0, 1.0)] {
            var f = baseFeatures()
            f.percentileSpreadStops = Float(spread)
            let sol = SettingsSolver.solve(
                recipeId: "hdr-brights-darks", features: f,
                capabilities: caps, context: ctx1150)
            let stops = sol.phoneTargets.bracket?.stops ?? []
            XCTAssertEqual(stops.count, 3, "spread \(spread)")
            XCTAssertEqual(stops[0], -expected, accuracy: 0.01, "spread \(spread)")
            XCTAssertEqual(stops[2], expected, accuracy: 0.01, "spread \(spread)")
        }
    }

    func testHDR_noCustomExposure_videoHDR() {
        var f = baseFeatures()
        f.percentileSpreadStops = 9
        let sol = SettingsSolver.solve(
            recipeId: "hdr-brights-darks", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertNil(sol.phoneTargets.exposureDurationSec, "HDR must not lock exposure")
        XCTAssertNil(sol.phoneTargets.iso)
        XCTAssertEqual(sol.phoneTargets.videoHDR, true)
        // EV programs via setEV here (no custom exposure written) — still solved, not bucketed.
        XCTAssertNotNil(sol.phoneTargets.ev)
    }

    func testHDR_wbGainsLockedFromContext() {
        var ctx = ctx1150!
        ctx.currentWBGains = (1.2, 1.0, 1.5)
        var f = baseFeatures()
        f.percentileSpreadStops = 8
        let sol = SettingsSolver.solve(
            recipeId: "hdr-brights-darks", features: f,
            capabilities: caps, context: ctx)
        if case .gains(let r, let g, let b)? = sol.phoneTargets.whiteBalance {
            XCTAssertEqual(r ?? -1, 1.2, accuracy: 0.001)
            XCTAssertEqual(g ?? -1, 1.0, accuracy: 0.001)
            XCTAssertEqual(b ?? -1, 1.5, accuracy: 0.001)
        } else {
            XCTFail("expected WB gains lock, got \(String(describing: sol.phoneTargets.whiteBalance))")
        }
    }

    // MARK: - get-down-low

    func testGetDownLow_switchesToUltraWide() {
        var f = baseFeatures()
        f.cameraElevationDegrees = 30
        let sol = SettingsSolver.solve(
            recipeId: "get-down-low", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.cameraDevice, "ultraWide")
        XCTAssertEqual(sol.panCue?.direction, "down")
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("ultra-wide") }),
            "expected the ultra-wide re-clamp note, got: \(sol.clampMessages)")
    }

    // MARK: - portrait-pop / sharp-and-in-focus

    func testPortraitPop_eyeFocusZoomAndTorchOffInDark() {
        var f = baseFeatures()
        f.subjectKind = .face
        f.subjectBox = NormalizedBox(x: 0.3, y: 0.2, width: 0.4, height: 0.45)
        f.sceneEV100 = 1
        let sol = SettingsSolver.solve(
            recipeId: "portrait-pop", features: f,
            capabilities: caps, context: ctx1150)
        let t = sol.phoneTargets
        XCTAssertEqual(t.zoom, 2.0)
        XCTAssertEqual(t.focusMode, "locked")
        // Eyes sit above the face-box center.
        XCTAssertLessThan(t.focusPoint?.y ?? 1, 0.425 + 0.001)
        XCTAssertEqual(t.torch?.mode, "off")
        XCTAssertEqual(t.lowLightBoost, true)
    }

    func testFaceEVBias_backlitFace() {
        var f = baseFeatures()
        f.subjectKind = .face
        f.subjectBox = NormalizedBox(x: 0.3, y: 0.2, width: 0.4, height: 0.45)
        f.subjectDeltaStops = -2.0
        let sol = SettingsSolver.solve(
            recipeId: "sharp-and-in-focus", features: f,
            capabilities: caps, context: ctx1150)
        // +0.7 folded into the solve (targets.ev), never a setEV-after-custom call.
        XCTAssertEqual(sol.phoneTargets.ev, "+0.7")
    }

    func testEyePoint_nudgesAboveFaceCenter() {
        var f = SceneFeatures()
        f.subjectKind = .face
        f.subjectBox = NormalizedBox(x: 0.4, y: 0.3, width: 0.2, height: 0.2)
        let p = SettingsSolver.eyePoint(features: f)
        XCTAssertEqual(p.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.33, accuracy: 0.001)
    }

    // MARK: - cheatsheet

    func testCheatsheet_noCameraChanges() {
        let sol = SettingsSolver.solve(
            recipeId: "exposure-triangle-cheatsheet", features: baseFeatures(),
            capabilities: caps, context: ctx1150)
        let t = sol.phoneTargets
        XCTAssertNil(t.shutter)
        XCTAssertNil(t.exposureDurationSec)
        XCTAssertNil(t.iso)
        XCTAssertNil(t.ev)
        XCTAssertNil(t.focusPoint)
        XCTAssertNil(t.cameraDevice)
        XCTAssertTrue(sol.clampMessages.isEmpty)
        XCTAssertTrue(sol.coachOnly?.notes?.contains("Reference card") == true)
    }

    // MARK: - minimalist / leading-lines

    func testMinimalist_moodyUnderexposure() {
        var f = baseFeatures()
        f.sceneEV100 = 5
        let sol = SettingsSolver.solve(
            recipeId: "minimalist-photos", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.ev, "-0.3")
        XCTAssertTrue(sol.coachOnly?.notes?.contains("Thirds grid") == true)
    }

    func testLeadingLines_deepFocusCoach() {
        let sol = SettingsSolver.solve(
            recipeId: "leading-lines", features: baseFeatures(),
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.simulatedAperture, 11)
    }

    // MARK: - unknown recipe falls back

    func testUnknownRecipe_fallsBackToSharpFrontToBack() {
        let sol = SettingsSolver.solve(
            recipeId: "no-such-recipe", features: baseFeatures(),
            capabilities: caps, context: ctx1150)
        XCTAssertNotNil(sol.phoneTargets.exposureDurationSec)
    }

    // MARK: - A4: missing metering falls back to system auto

    func testMissingMetering_fallsBackToSystemAuto() {
        // No metered anchor — never solve from fixed 1/60 s × ISO 100 guesses.
        var f = baseFeatures()
        f.meteredExposureSeconds = nil
        f.meteredISO = nil
        let sol = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: f,
            capabilities: caps, context: ctx1150)
        // No custom exposure is written: verify skips (targetEV nil) and no
        // dial targets are produced.
        XCTAssertNil(sol.targetEV)
        XCTAssertNil(sol.phoneTargets.exposureDurationSec)
        XCTAssertNil(sol.phoneTargets.iso)
        XCTAssertNil(sol.phoneTargets.shutter)
        XCTAssertNil(sol.shutterCapSeconds)
        XCTAssertNil(sol.residualEV)
        XCTAssertTrue(
            sol.clampMessages.contains("Couldn't read the light — left on auto"),
            "got: \(sol.clampMessages)")
        // Non-exposure targets still solve (focus locks on the subject).
        XCTAssertEqual(sol.phoneTargets.focusMode, "locked")
    }

    func testMissingMetering_eitherValueMissing() {
        // Either value missing is enough to trigger the fallback.
        var f = baseFeatures()
        f.meteredISO = nil
        let sol = SettingsSolver.solve(
            recipeId: "portrait-pop", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertNil(sol.targetEV)
        XCTAssertNil(sol.phoneTargets.exposureDurationSec)
        XCTAssertTrue(
            sol.clampMessages.contains("Couldn't read the light — left on auto"))
    }

    // MARK: - A2: tripod relaxation at the solver level

    func testTripodSteady_allowsLongShutter() {
        // Dim indoor scene on a tripod: the shake-derived limits drop, so the
        // plan runs to the longest shutter the light needs (E_target at min
        // ISO), with a truthful message.
        var f = baseFeatures()
        f.isTripodSteady = true
        let sol = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: f,
            capabilities: caps, context: ctx1150)
        // E_target = 13.33 → 0.267 s at min ISO 50 (device max 1 s not hit).
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 0.267, accuracy: 0.01)
        XCTAssertEqual(sol.phoneTargets.iso, "50")
        XCTAssertEqual(sol.shutterCapSeconds ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertTrue(
            sol.clampMessages.contains("Tripod detected — long shutter"),
            "got: \(sol.clampMessages)")
    }

    func testTripodSteady_subjectMotionStillCaps() {
        // Tripod + moving subject: the recipe's motion objective still caps
        // the shutter (freeze the subject), even though shake is dropped.
        var f = baseFeatures()
        f.isTripodSteady = true
        f.subjectRelativeSpeedPxPerSec = 500 // tMotion = 1.5/500 = 0.003 s
        let sol = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: f,
            capabilities: caps, context: ctx1150)
        XCTAssertEqual(sol.phoneTargets.exposureDurationSec ?? -1, 0.003, accuracy: 0.001)
    }
}
