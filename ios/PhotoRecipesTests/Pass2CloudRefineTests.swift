import XCTest
@testable import PhotoRecipes

/// Section B: Pass 2 cloud refine respects the exposure planner.
///
/// The server's absolute shutter/ISO are never applied directly — its
/// exposure is re-anchored to the run's metered `E_auto` (±1 stop),
/// re-planned with the recipe's priority/cap, applied via the normal apply
/// path, and verified with the plan's priority and cap.
final class Pass2CloudRefineTests: XCTestCase {

    /// Metered anchor: 1/60 s × ISO 100 (a typical converged indoor read).
    private let eAuto = (1.0 / 60) * 100

    private func anchor(
        eAuto: Double? = nil,
        priority: ExposurePlanner.Priority? = .shutter(seconds: 1.0 / 120)
    ) -> AutoOptimizeController.Pass2ExposureAnchor {
        AutoOptimizeController.Pass2ExposureAnchor(
            eAuto: eAuto ?? self.eAuto,
            priority: priority,
            motion: ExposurePlanner.MotionContext(
                handShakeRadPerSec: 0.02,
                frameWidthPx: 1920,
                fieldOfViewDegrees: 70,
                isTripodSteady: false),
            limits: ExposurePlanner.DeviceLimits(
                minShutterSeconds: 1.0 / 16000,
                maxShutterSeconds: 1.0,
                minISO: 50,
                maxISO: 3200))
    }

    // MARK: - (a) Server absolutes are never applied directly

    func testPass2PlansExposureFromEAutoNotServerAbsolutes() throws {
        // Server wants 1/500 s @ ISO 3200 — nothing like the metered scene.
        let targets = PhoneTargets(exposureDurationSec: 1.0 / 500, iso: "3200")
        let plan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: targets, anchor: anchor()))

        // The planner's output — not the server's absolutes — is what gets applied.
        XCTAssertNotEqual(plan.shutterSeconds, 1.0 / 500, accuracy: 1e-9)
        XCTAssertNotEqual(plan.iso, 3200)
        // Fixed-shutter recipe priority: the recipe's shutter is kept, ISO
        // holds the (±1-clamped) server delta: E_auto × 2 → ISO 400 @ 1/120 s.
        XCTAssertEqual(plan.shutterSeconds, 1.0 / 120, accuracy: 1e-9)
        XCTAssertEqual(plan.iso, 400, accuracy: 0.5)
        XCTAssertEqual(plan.shutterSeconds * Double(plan.iso), eAuto * 2, accuracy: 0.01)

        // And the intent path strips every exposure key — the server's
        // absolutes cannot leak through the intent apply either.
        let intent = AutoOptimizeController.pass2IntentTargets(from: targets)
        XCTAssertNil(intent.shutter)
        XCTAssertNil(intent.exposureDurationSec)
        XCTAssertNil(intent.iso)
        XCTAssertNil(intent.ev)
    }

    func testPass2IntentTargetsKeepNonExposureLevers() {
        let wb = WhiteBalanceTarget.temperatureTint(temperature: 5600, tint: nil)
        let targets = PhoneTargets(
            exposureDurationSec: 1.0 / 500, iso: "3200", ev: "+0.5",
            whiteBalance: wb, focusMode: "locked", zoom: 2.0)
        let intent = AutoOptimizeController.pass2IntentTargets(from: targets)
        XCTAssertNil(intent.exposureDurationSec)
        XCTAssertNil(intent.iso)
        XCTAssertNil(intent.ev)
        XCTAssertEqual(intent.whiteBalance, wb)
        XCTAssertEqual(intent.focusMode, "locked")
        XCTAssertEqual(intent.zoom, 2.0)
    }

    func testPass2ExposurePlanNilWithoutAnchorOrExposure() {
        let withExposure = PhoneTargets(exposureDurationSec: 1.0 / 500, iso: "3200")
        // No anchor (e.g. manual Teach-sheet refine) → intent only.
        XCTAssertNil(AutoOptimizeController.pass2ExposurePlan(targets: withExposure, anchor: nil))
        // Zero/negative anchor → no plan.
        XCTAssertNil(AutoOptimizeController.pass2ExposurePlan(
            targets: withExposure, anchor: anchor(eAuto: 0)))
        // No usable server exposure → intent only.
        XCTAssertNil(AutoOptimizeController.pass2ExposurePlan(
            targets: PhoneTargets(), anchor: anchor()))
        // System-auto priority (HDR) → never writes custom exposure.
        XCTAssertNil(AutoOptimizeController.pass2ExposurePlan(
            targets: withExposure, anchor: anchor(priority: .systemAuto)))
        XCTAssertNil(AutoOptimizeController.pass2ExposurePlan(
            targets: withExposure, anchor: anchor(priority: nil)))
    }

    // MARK: - (b) Server EV delta clamped to ±1 stop

    func testPass2ServerEVDeltaClampedToPlusMinusOne() throws {
        // +2 stops over the anchor → clamped to +1.
        let over = PhoneTargets(exposureDurationSec: 1.0 / 120, iso: "800") // 4× E_auto
        let overPlan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: over, anchor: anchor()))
        XCTAssertEqual(overPlan.targetEV, 1.0, accuracy: 1e-9)

        // −2 stops under the anchor → clamped to −1.
        let under = PhoneTargets(exposureDurationSec: 1.0 / 240, iso: "100") // E_auto/4
        let underPlan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: under, anchor: anchor()))
        XCTAssertEqual(underPlan.targetEV, -1.0, accuracy: 1e-9)

        // A bare EV bias (no absolutes) is already relative — passes through…
        let evOnly = PhoneTargets(ev: "+0.5")
        let evPlan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: evOnly, anchor: anchor()))
        XCTAssertEqual(evPlan.targetEV, 0.5, accuracy: 1e-9)

        // …and is clamped too when out of range.
        let evBig = PhoneTargets(ev: "+2.5")
        let evBigPlan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: evBig, anchor: anchor()))
        XCTAssertEqual(evBigPlan.targetEV, 1.0, accuracy: 1e-9)

        // Shutter string form parses the same as the numeric field.
        let strForm = PhoneTargets(shutter: "1/120", iso: "800")
        let strPlan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: strForm, anchor: anchor()))
        XCTAssertEqual(strPlan.targetEV, 1.0, accuracy: 1e-9)
    }

    // MARK: - (c) Gate truth table

    func testCloudRefineGateTruthTable() {
        typealias G = AutoOptimizeController.CloudRefineGate
        func gate(_ pending: Bool, _ enabled: Bool, _ trigger: String) -> G {
            AutoOptimizeController.cloudRefineGate(
                isFirstSuccessPending: pending, cloudRefineEnabled: enabled, trigger: trigger)
        }

        // The first successful optimize stays local-only — even with the toggle on.
        XCTAssertEqual(gate(true, true, "manual"), .skip(reason: "first_win_local"))
        XCTAssertEqual(gate(true, false, "manual"), .skip(reason: "first_win_local"))

        // Toggle off → disabled (and only then).
        XCTAssertEqual(gate(false, false, "manual"), .skip(reason: "disabled"))

        // auto_first_capture never triggers a cloud call.
        XCTAssertEqual(gate(false, true, "auto_first_capture"), .skip(reason: "auto_first_capture"))

        // Happy paths.
        XCTAssertEqual(gate(false, true, "manual"), .allow)
        XCTAssertEqual(gate(false, true, "subject_change"), .allow)
    }

    // MARK: - (d) verifyExposure runs after the Pass 2 apply

    @MainActor
    func testPass2VerifyRunsAfterApply() async throws {
        let priority: ExposurePlanner.Priority? = .shutter(seconds: 1.0 / 120)
        let plan = try XCTUnwrap(AutoOptimizeController.pass2ExposurePlan(
            targets: PhoneTargets(exposureDurationSec: 1.0 / 500, iso: "3200"),
            anchor: anchor(priority: priority)))

        var events: [String] = []
        var applied: (shutter: Double, iso: Float)?
        var verified: (targetEV: Double, priority: ExposurePlanner.Priority?, cap: Double?)?
        let result = await AutoOptimizeController.applyPass2Exposure(
            plan: plan,
            priority: priority,
            apply: { durationSeconds, iso in
                events.append("apply")
                applied = (durationSeconds, iso)
                return true
            },
            verify: { targetEV, p, cap in
                events.append("verify")
                verified = (targetEV, p, cap)
                return CameraSession.ExposureVerifyResult(
                    residualEV: 0.1, iterations: 1, clamped: false,
                    initialError: 0.4, verified: true)
            })

        // Verify is invoked, and only after the apply.
        XCTAssertEqual(events, ["apply", "verify"])

        // The planner's output — not the server's absolutes — is what gets applied.
        let got = try XCTUnwrap(applied)
        XCTAssertEqual(got.shutter, plan.shutterSeconds, accuracy: 1e-12)
        XCTAssertEqual(got.iso, plan.iso)
        XCTAssertNotEqual(got.shutter, 1.0 / 500, accuracy: 1e-9)
        XCTAssertNotEqual(got.iso, 3200)

        // Verify runs with the plan's priority and shutter cap.
        let v = try XCTUnwrap(verified)
        XCTAssertEqual(v.targetEV, plan.targetEV, accuracy: 1e-12)
        XCTAssertNotNil(v.priority)
        XCTAssertEqual(v.cap, plan.shutterCapSeconds)
        XCTAssertEqual(try XCTUnwrap(result).residualEV, 0.1, accuracy: 1e-12)
    }

    @MainActor
    func testPass2VerifySkippedWhenPlanNeedsNoCustomExposure() async throws {
        let sysAutoPlan = ExposurePlanner.plan(
            eAuto: eAuto, targetEV: 0, priority: .systemAuto,
            motion: ExposurePlanner.MotionContext(
                handShakeRadPerSec: 0.02, frameWidthPx: 1920,
                fieldOfViewDegrees: 70, isTripodSteady: false),
            limits: ExposurePlanner.DeviceLimits(
                minShutterSeconds: 1.0 / 16000, maxShutterSeconds: 1.0,
                minISO: 50, maxISO: 3200))
        XCTAssertFalse(sysAutoPlan.useCustomExposure)

        var applyCalled = false
        let result = await AutoOptimizeController.applyPass2Exposure(
            plan: sysAutoPlan,
            priority: .systemAuto,
            apply: { _, _ in applyCalled = true; return true },
            verify: { _, _, _ in
                XCTFail("verify must not run when the plan needs no custom exposure")
                return CameraSession.ExposureVerifyResult(
                    residualEV: 0, iterations: 0, clamped: false,
                    initialError: 0, verified: false)
            })
        XCTAssertFalse(applyCalled)
        XCTAssertNil(result)
    }
}
