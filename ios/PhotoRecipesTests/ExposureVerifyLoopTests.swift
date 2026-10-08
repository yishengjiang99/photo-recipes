import CoreMedia
import XCTest
@testable import PhotoRecipes

/// Fake `ExposureWriteClock`: simulates a scene needing a fixed exposure
/// product, so the verify loop's mechanics are unit-testable without a camera.
///
/// Meter model: `offset = log2(programmedProduct / sceneProduct)`.
///
/// POLARITY (A7-resolved): positive offset is reported when the programmed
/// exposure EXCEEDS what the scene needs (positive = overexposed — brighter
/// than target). The loop's correction math (`2^(−error)`) converges under
/// this polarity, which matches the device truth.
@MainActor
final class FakeExposureDevice: ExposureWriteClock {
    /// Exposure product the scene needs for a correct exposure at targetEV 0.
    var sceneProduct: Double
    /// Whether custom exposure is "held" — false makes reads return nil.
    var holdsCustomExposure = true
    /// Scripted offsets, popped in order before the physical model is used
    /// (for exercising the stability gate).
    var scriptedOffsets: [Float] = []

    private(set) var programmedShutter: Double
    private(set) var programmedISO: Float
    private(set) var writeCount = 0
    private(set) var isoHistory: [Float] = []
    private(set) var shutterHistory: [Double] = []
    /// Ordered event log: "write#n" / "sync#n" / "settle" / "read".
    private(set) var events: [String] = []

    let isoRange: ClosedRange<Float>
    let shutterRange: ClosedRange<Double>

    init(
        sceneProduct: Double,
        initialShutter: Double,
        initialISO: Float,
        isoRange: ClosedRange<Float>,
        shutterRange: ClosedRange<Double>
    ) {
        self.sceneProduct = sceneProduct
        self.programmedShutter = initialShutter
        self.programmedISO = initialISO
        self.isoRange = isoRange
        self.shutterRange = shutterRange
    }

    func issueWrite(durationSeconds: Double, iso: Float) async -> CMTime {
        writeCount += 1
        programmedShutter = durationSeconds
        programmedISO = iso
        isoHistory.append(iso)
        shutterHistory.append(durationSeconds)
        events.append("write#\(writeCount)")
        // The sync arrives asynchronously, like the real completion handler:
        // a loop that reads before awaiting the write would log its read
        // between "write#n" and "sync#n", and the ordering test catches it.
        await Task.yield()
        events.append("sync#\(writeCount)")
        return CMTime(seconds: Double(writeCount) * 0.001, preferredTimescale: 1_000_000)
    }

    func settleAfterWrite(exposureDurationSeconds: Double) async {
        events.append("settle")
        // Instant in tests — production sleeps ~2 frames here.
    }

    func readExposureOffset() -> Float? {
        guard holdsCustomExposure else {
            events.append("read(nil)")
            return nil
        }
        events.append("read")
        if !scriptedOffsets.isEmpty { return scriptedOffsets.removeFirst() }
        let product = programmedShutter * Double(programmedISO)
        return Float(log2(product / sceneProduct))
    }

    func currentExposure() -> (shutterSeconds: Double, iso: Float) {
        (programmedShutter, programmedISO)
    }
}

/// A1: the closed-loop verify mechanics — one write per iteration, reads only
/// after the matching sync, convergence without overshoot — driven by the
/// fake `ExposureWriteClock`.
@MainActor
final class ExposureVerifyLoopTests: XCTestCase {

    private func makeDevice(
        sceneShutter: Double = 1 / 8, sceneISO: Float = 800,
        initialShutter: Double = 1 / 8, initialISO: Float = 3200,
        isoRange: ClosedRange<Float> = 50...3200
    ) -> FakeExposureDevice {
        FakeExposureDevice(
            sceneProduct: sceneShutter * Double(sceneISO),
            initialShutter: initialShutter, initialISO: initialISO,
            isoRange: isoRange, shutterRange: 1.0 / 8000...1.0)
    }

    // MARK: - A1: loop mechanics

    func testLoopConvergesOnDimSceneWithoutOvershoot() async {
        // Dim interior: the scene needs 1/8 s × ISO 800 at targetEV 0.
        // The pre-verify apply left us 2 stops over (1/8 s × ISO 3200).
        let device = makeDevice()
        _ = await device.issueWrite(durationSeconds: 1 / 8, iso: 3200)

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: .auto(shutterCapSeconds: 1 / 8),
            shutterCapSeconds: 1 / 8, maxIterations: 3, clock: device)

        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.initialError, 2.0, accuracy: 1e-6)
        XCTAssertEqual(result.iterations, 1, "exact log-space correction converges in one write")
        XCTAssertFalse(result.clamped)
        XCTAssertLessThanOrEqual(abs(result.residualEV), 0.3)
        XCTAssertEqual(device.programmedISO, 800, accuracy: 0.5)
        XCTAssertEqual(device.programmedShutter, 1 / 8, accuracy: 1e-9)
        // No overshoot: ISO approached 800 monotonically, never dipped below it.
        XCTAssertTrue(
            device.isoHistory.allSatisfy { $0 >= 800 },
            "ISO must not overshoot below the converged value: \(device.isoHistory)")
    }

    func testOneWritePerIterationAndReadsAfterMatchingSync() async {
        // ISO range capped at 400 forces a clamped first correction and a
        // second iteration: 2 loop writes (+ the pre-verify one).
        let device = makeDevice(isoRange: 50...400)
        _ = await device.issueWrite(durationSeconds: 1 / 8, iso: 3200)

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: .auto(shutterCapSeconds: 1 / 8),
            shutterCapSeconds: 1 / 8, maxIterations: 3, clock: device)

        XCTAssertEqual(result.iterations, 2)
        XCTAssertTrue(result.clamped, "first correction hit the ISO cap")
        // The shutter cap (1/8 s) blocks the full correction: the −1.0 EV
        // residual is reported, not hidden.
        XCTAssertEqual(result.residualEV, -1.0, accuracy: 1e-6)
        // Exactly one write per loop iteration (the pre-verify write is extra).
        XCTAssertEqual(device.writeCount, result.iterations + 1)

        // Every read happens after the sync of the latest write before it —
        // a read observing a write whose sync hasn't arrived fails here.
        var awaitingSync = false
        for event in device.events {
            if event.hasPrefix("write#") { awaitingSync = true }
            else if event.hasPrefix("sync#") { awaitingSync = false }
            else if event == "read" {
                XCTAssertFalse(awaitingSync, "read before the matching sync in \(device.events)")
            }
        }
    }

    func testNoCorrectionWhenWithinTolerance() async {
        // ~0.09 EV off — inside the 0.3 EV deadband.
        let device = makeDevice(initialISO: 853)
        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: nil, shutterCapSeconds: nil,
            maxIterations: 2, clock: device)

        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.iterations, 0)
        XCTAssertEqual(device.writeCount, 0, "no write when already within tolerance")
        XCTAssertLessThanOrEqual(abs(result.residualEV), 0.3)
    }

    func testVerifiedFalseWhenCustomExposureNotHeld() async {
        let device = makeDevice()
        device.holdsCustomExposure = false

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: nil, shutterCapSeconds: nil,
            maxIterations: 2, clock: device)

        XCTAssertFalse(result.verified)
        XCTAssertEqual(result.iterations, 0)
        XCTAssertEqual(device.writeCount, 0)
    }

    func testStabilityGate_disagreementUsesLatestReading() async {
        // First two readings disagree by > 0.1 EV (meter still moving) —
        // the latest wins: error 2.5, not the 2.25 average.
        let device = makeDevice()
        device.scriptedOffsets = [2.0, 2.5]

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: nil, shutterCapSeconds: nil,
            maxIterations: 3, clock: device)

        XCTAssertEqual(result.initialError, 2.5, accuracy: 1e-6)
        XCTAssertTrue(result.verified)
        XCTAssertLessThanOrEqual(abs(result.residualEV), 0.3)
    }

    func testStabilityGate_agreementAcceptsAverage() async {
        // Readings within 0.1 EV — accepted, and inside the deadband.
        let device = makeDevice()
        device.scriptedOffsets = [0.04, 0.06]

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: nil, shutterCapSeconds: nil,
            maxIterations: 2, clock: device)

        XCTAssertEqual(result.initialError, 0.05, accuracy: 1e-6)
        XCTAssertEqual(result.iterations, 0)
    }

    // MARK: - A6: priority-respecting corrections

    func testShutterPriority_neverMovesShutterWhenISOClamps() {
        // 2 stops over with ISO already at max: ISO clamps, shutter (the
        // creative objective) must NOT move.
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: .shutter(seconds: 1 / 250),
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 250, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 250, accuracy: 1e-12)
        XCTAssertEqual(c.iso, 3200)
        XCTAssertTrue(c.clamped, "residual must be reported, not silently missed")
    }

    func testShutterPriority_isoOnlyWhenUnclamped() {
        let c = ExposureVerifyLoop.correctionTarget(
            error: 1.0, priority: .shutter(seconds: 1 / 250),
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 250, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 250, accuracy: 1e-12)
        XCTAssertEqual(c.iso, 1600, accuracy: 0.5)
        XCTAssertFalse(c.clamped)
    }

    func testRun_shutterPriorityEndToEnd_shutterNeverMoves() async {
        // Scene needs less light than min ISO allows at the locked 1/250 s:
        // ISO clamps at 50 and the loop must report the residual without
        // ever touching the shutter.
        let device = FakeExposureDevice(
            sceneProduct: (1 / 250) * 25, // below min ISO — unreachable
            initialShutter: 1 / 250, initialISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)

        let result = await ExposureVerifyLoop.run(
            targetEV: 0, priority: .shutter(seconds: 1 / 250),
            shutterCapSeconds: nil, maxIterations: 2, clock: device)

        XCTAssertTrue(result.verified)
        XCTAssertTrue(result.clamped)
        XCTAssertTrue(
            device.shutterHistory.allSatisfy { abs($0 - 1 / 250) < 1e-12 },
            "shutter-priority: the shutter is the creative objective — never moved: \(device.shutterHistory)")
        XCTAssertEqual(device.programmedISO, 50)
        XCTAssertGreaterThan(abs(result.residualEV), 0.3, "residual reported, not hidden")
    }

    func testAutoPriority_shutterNeverExceedsShutterCap() {
        // ISO maxed, correction wants a longer shutter, but the recipe's
        // motion cap is 1/60 s.
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: .auto(shutterCapSeconds: 1 / 60),
            shutterCapSeconds: 1 / 60,
            currentShutterSeconds: 1 / 125, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 60, accuracy: 1e-9)
        XCTAssertTrue(c.clamped)
    }

    func testAutoPriority_nilCapFallsBackToDeviceLimits() {
        // No cap: historical behavior — shutter moves within device limits.
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: .auto(shutterCapSeconds: nil),
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 125, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 31.25, accuracy: 1e-9)
        XCTAssertFalse(c.clamped)
    }

    func testNilPriority_keepsLegacyISOFirstThenShutter() {
        // Documented choice: with no creative shutter objective to protect,
        // a clamped ISO falls back to the shutter within device limits.
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: nil,
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 125, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 31.25, accuracy: 1e-9)
        XCTAssertEqual(c.iso, 3200)
        XCTAssertFalse(c.clamped)
    }

    func testIsoPriority_clampedISOFallsBackToShutter() {
        let c = ExposureVerifyLoop.correctionTarget(
            error: -2.0, priority: .iso(value: 3200),
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 125, currentISO: 3200,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 31.25, accuracy: 1e-9)
        XCTAssertFalse(c.clamped)
    }

    func testSystemAuto_neverWrites() {
        let c = ExposureVerifyLoop.correctionTarget(
            error: 1.0, priority: .systemAuto,
            shutterCapSeconds: nil,
            currentShutterSeconds: 1 / 60, currentISO: 400,
            isoRange: 50...3200, shutterRange: 1.0 / 8000...1.0)
        XCTAssertEqual(c.shutterSeconds, 1 / 60, accuracy: 1e-12)
        XCTAssertEqual(c.iso, 400)
        XCTAssertTrue(c.clamped)
    }

    // MARK: - A6: solver interface

    func testSolution_priorityFieldsDefaultToNil() {
        let solution = SettingsSolver.Solution(phoneTargets: PhoneTargets())
        XCTAssertNil(solution.priority, "populated by the solver-side worker, not here")
        XCTAssertNil(solution.shutterCapSeconds, "populated by the solver-side worker, not here")
    }
}
