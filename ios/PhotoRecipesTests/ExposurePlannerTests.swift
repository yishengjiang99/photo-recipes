import XCTest
@testable import PhotoRecipes

/// Phase 1: the closed-loop exposure planner.
///
/// The planner is anchored to the metered exposure product `E_auto` from a
/// converged AE state — never to the tone-mapped probe brightness. These
/// tests pin that: the same scene tonality at different light levels must
/// produce different exposures.
final class ExposurePlannerTests: XCTestCase {

    private var limits: ExposurePlanner.DeviceLimits!
    private var motion: ExposurePlanner.MotionContext!

    override func setUp() {
        super.setUp()
        limits = ExposurePlanner.DeviceLimits(
            minShutterSeconds: 1.0 / 8000,
            maxShutterSeconds: 1,
            minISO: 50,
            maxISO: 3200
        )
        motion = ExposurePlanner.MotionContext(
            handShakeRadPerSec: 0.01,
            frameWidthPx: 4032,
            fieldOfViewDegrees: 70
        )
    }

    // MARK: - 1d(a): dim indoor vs bright outdoor, same brightness01

    func testDimIndoorVsBrightOutdoor_sameTonality_differentISO() {
        // System AE already normalized both probes toward mid-gray
        // (brightness01 ~0.45 in both) — the light level lives in E_auto.
        // Dim indoor: AE converged at 1/30 s × ISO 1600.
        let dim = ExposurePlanner.plan(
            eAuto: (1.0 / 30) * 1600, targetEV: 0,
            priority: .auto(shutterCapSeconds: 1.0 / 60),
            motion: motion, limits: limits)
        // Bright outdoor: AE converged at 1/2000 s × ISO 50.
        let bright = ExposurePlanner.plan(
            eAuto: (1.0 / 2000) * 50, targetEV: 0,
            priority: .auto(shutterCapSeconds: 1.0 / 60),
            motion: motion, limits: limits)

        XCTAssertGreaterThan(
            dim.iso, bright.iso,
            "same tonality, different light — ISO must follow E_auto")
        XCTAssertEqual(dim.iso, 3200, accuracy: 1)
        XCTAssertEqual(bright.iso, 50, accuracy: 1)
        // Both conserve the metered product (dim hits the max-ISO clamp but
        // still lands exactly on E_target here).
        XCTAssertEqual(
            dim.shutterSeconds * Double(dim.iso), (1.0 / 30) * 1600, accuracy: 0.01)
        XCTAssertEqual(
            bright.shutterSeconds * Double(bright.iso), (1.0 / 2000) * 50, accuracy: 1e-6)
        XCTAssertFalse(dim.clamped)
        XCTAssertFalse(bright.clamped)
    }

    // MARK: - 1d(b): shutter-priority conservation

    func testShutterPriority_conservesExposureProduct() {
        // eAuto chosen so the solved ISO stays inside [minISO, maxISO]
        // (no clamping) — conservation only holds on the unclamped path.
        let eAuto = 2.0
        let targetEV = 0.3
        let plan = ExposurePlanner.plan(
            eAuto: eAuto, targetEV: targetEV,
            priority: .shutter(seconds: 1.0 / 30),
            motion: motion, limits: limits)
        let eTarget = eAuto * pow(2, targetEV)
        XCTAssertEqual(plan.shutterSeconds, 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(
            plan.shutterSeconds * Double(plan.iso), eTarget,
            accuracy: eTarget * 0.01, "shutter × ISO must equal E_target within 1%")
        XCTAssertFalse(plan.clamped)
    }

    // MARK: - 1d(c): clamping residual reporting

    func testClamping_reportsResidualEV() {
        // A 20 s "trails"-style target against a 1/3 s device max shutter.
        var shortLimits = limits!
        shortLimits.maxShutterSeconds = 1.0 / 3
        // E_target is 3 stops beyond what max shutter × max ISO can deliver.
        let eAuto = (1.0 / 3) * 3200 * 8
        let plan = ExposurePlanner.plan(
            eAuto: eAuto, targetEV: 0,
            priority: .shutter(seconds: 20),
            motion: motion, limits: shortLimits)

        XCTAssertTrue(plan.clamped)
        XCTAssertEqual(plan.shutterSeconds, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(plan.iso, 3200)
        XCTAssertEqual(plan.residualEV, 3.0, accuracy: 0.01)
        XCTAssertEqual(plan.clampMessages.count, 1)
        XCTAssertEqual(
            plan.clampMessages[0],
            "Max shutter 1/3s on this lens — 3.0 stops short; tripod + Night mode recommended.")
    }

    func testClamping_overexposedAtMinISO() {
        // Blazing scene, fixed 1/2 s shutter: ISO bottoms out, residual < 0.
        let plan = ExposurePlanner.plan(
            eAuto: 10, targetEV: 0,
            priority: .shutter(seconds: 1.0 / 2),
            motion: motion, limits: limits)
        XCTAssertTrue(plan.clamped)
        XCTAssertEqual(plan.iso, 50)
        XCTAssertLessThan(plan.residualEV, 0)
        XCTAssertTrue(
            plan.clampMessages[0].contains("Overexposed"),
            "got: \(plan.clampMessages)")
    }

    // MARK: - 1d(d): face +0.7 EV

    func testFaceEVOffset_scalesExposureByTwoToThePointSeven() {
        let base = ExposurePlanner.plan(
            eAuto: 1.0, targetEV: 0,
            priority: .shutter(seconds: 1.0 / 60),
            motion: motion, limits: limits)
        let face = ExposurePlanner.plan(
            eAuto: 1.0, targetEV: 0.7,
            priority: .shutter(seconds: 1.0 / 60),
            motion: motion, limits: limits)
        let baseE = base.shutterSeconds * Double(base.iso)
        let faceE = face.shutterSeconds * Double(face.iso)
        XCTAssertEqual(
            faceE, baseE * pow(2, 0.7), accuracy: baseE * 1e-6,
            "+0.7 EV must multiply the exposure product by 2^0.7")
        XCTAssertEqual(face.targetEV, 0.7, accuracy: 1e-12)
    }

    // MARK: - 1d(e): motion limit shortens the shutter

    func testMotionLimit_shortensShutter() {
        var still = motion!
        still.handShakeRadPerSec = 0.001
        var shaky = motion!
        shaky.handShakeRadPerSec = 0.5

        // eAuto chosen so neither plan hits the ISO rails (conservation
        // only holds on the unclamped path).
        let pStill = ExposurePlanner.plan(
            eAuto: 0.5, targetEV: 0, priority: .auto(),
            motion: still, limits: limits)
        let pShaky = ExposurePlanner.plan(
            eAuto: 0.5, targetEV: 0, priority: .auto(),
            motion: shaky, limits: limits)

        XCTAssertLessThan(
            pShaky.shutterSeconds, pStill.shutterSeconds,
            "gyro motion must shorten the .auto shutter")
        // Both still conserve E_target (ISO absorbs the difference).
        XCTAssertEqual(
            pShaky.shutterSeconds * Double(pShaky.iso), 0.5, accuracy: 0.01)
        XCTAssertEqual(
            pStill.shutterSeconds * Double(pStill.iso), 0.5, accuracy: 0.01)
    }

    // MARK: - limit helpers

    func testHandheldLimit_oneOverTwoF() {
        // 70° (horizontal) FOV → f_35 ≈ 25.7 mm → 1/(2f) ≈ 1/51 s.
        let hl = ExposurePlanner.handheldLimitSeconds(fieldOfViewDegrees: 70)
        XCTAssertEqual(hl, 1.0 / 51.4, accuracy: 0.002)
    }

    func testMotionLimit_blurBudgetOverOmegaFocalPx() {
        // 1 px budget / (0.01 rad/s × 2879 px) ≈ 0.0347 s at 4032 px / 70°.
        let ml = ExposurePlanner.motionLimitSeconds(
            handShakeRadPerSec: 0.01, frameWidthPx: 4032, fieldOfViewDegrees: 70)
        XCTAssertEqual(ml, 0.0347, accuracy: 0.002)
    }

    // MARK: - priorities

    func testIsoPriority_pinsISO_solvesShutter() {
        let plan = ExposurePlanner.plan(
            eAuto: 2.0, targetEV: 0,
            priority: .iso(value: 100),
            motion: motion, limits: limits)
        XCTAssertEqual(plan.iso, 100)
        XCTAssertEqual(plan.shutterSeconds, 0.02, accuracy: 1e-9)
        XCTAssertFalse(plan.clamped)
    }

    func testSystemAuto_writesNoCustomExposure() {
        let plan = ExposurePlanner.plan(
            eAuto: 2.0, targetEV: 0.3,
            priority: .systemAuto,
            motion: motion, limits: limits)
        XCTAssertFalse(plan.useCustomExposure)
        XCTAssertFalse(plan.clamped)
        XCTAssertTrue(plan.clampMessages.isEmpty)
    }

    func testAuto_recipeCap_overridesDerivedLimits() {
        // The solver passes its own motion objective (min(tShake, tMotion));
        // the planner must honor it instead of deriving its own cap.
        let plan = ExposurePlanner.plan(
            eAuto: 13.333, targetEV: 0,
            priority: .auto(shutterCapSeconds: 0.052),
            motion: motion, limits: limits)
        XCTAssertEqual(plan.shutterSeconds, 0.052, accuracy: 1e-9)
        XCTAssertEqual(plan.shutterSeconds * Double(plan.iso), 13.333, accuracy: 0.01)
    }

    // MARK: - solver integration (targetEV composition + Phase 4 hook)

    private func solverCaps() -> DeviceCapabilities {
        DeviceCapabilities(
            supportsCustomExposure: true,
            supportsExposureTargetBias: true,
            supportsWhiteBalanceLock: true,
            supportsFocusLock: true,
            minExposureSeconds: 1.0 / 8000,
            maxExposureSeconds: 1,
            minISO: 50,
            maxISO: 3200,
            minEV: -2,
            maxEV: 2,
            deviceTypeName: "wide")
    }

    private func solverFeatures() -> SceneFeatures {
        var f = SceneFeatures()
        f.meteredExposureSeconds = 1.0 / 60
        f.meteredISO = 800
        f.sceneEV100 = 4.6
        f.handShakeRadPerSec = 0.01
        return f
    }

    func testSolver_learnedEVOffset_feedsPlanner() {
        // Phase 4 hook: a learned +0.5 EV must flow into the plan and the UI.
        let base = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: solverFeatures(),
            capabilities: solverCaps(),
            context: SettingsSolver.SolveContext(
                frameWidthPx: 1150, fieldOfViewDegrees: 70, currentWBGains: nil))
        let learned = SettingsSolver.solve(
            recipeId: "sharp-front-to-back", features: solverFeatures(),
            capabilities: solverCaps(),
            context: SettingsSolver.SolveContext(
                frameWidthPx: 1150, fieldOfViewDegrees: 70, currentWBGains: nil),
            learnedEVOffset: 0.5)

        XCTAssertEqual(base.targetEV ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(learned.targetEV ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(learned.phoneTargets.ev, "+0.5")
        let baseISO = Float(base.phoneTargets.iso ?? "") ?? -1
        let learnedISO = Float(learned.phoneTargets.iso ?? "") ?? -1
        // Same shutter (motion cap unchanged) → ISO scales by 2^0.5.
        XCTAssertEqual(
            learned.phoneTargets.exposureDurationSec ?? -1,
            base.phoneTargets.exposureDurationSec ?? -2, accuracy: 1e-9)
        XCTAssertEqual(Double(learnedISO) / Double(baseISO), pow(2, 0.5), accuracy: 0.01)
    }

    func testSolver_forceSystemAutoExposure_stripsCustomExposure() {
        // Thermal .critical: rules still pick the recipe, but no custom
        // shutter/ISO is written — system auto stays in charge.
        let sol = SettingsSolver.solve(
            recipeId: "portrait-pop", features: solverFeatures(),
            capabilities: solverCaps(),
            context: SettingsSolver.SolveContext(
                frameWidthPx: 1150, fieldOfViewDegrees: 70, currentWBGains: nil),
            forceSystemAutoExposure: true)
        XCTAssertNil(sol.phoneTargets.exposureDurationSec)
        XCTAssertNil(sol.phoneTargets.iso)
        XCTAssertNil(sol.targetEV)
        XCTAssertTrue(
            sol.clampMessages.contains(where: { $0.contains("system auto") }),
            "got: \(sol.clampMessages)")
        // Non-exposure targets (focus, zoom) still apply.
        XCTAssertEqual(sol.phoneTargets.zoom, 2.0)
    }
}
