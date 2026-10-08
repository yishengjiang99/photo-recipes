import XCTest
@testable import PhotoRecipes

final class HorizonMonitorTests: XCTestCase {

    func testElevation_portraitLevel_isZero() {
        // Phone upright in portrait, camera on the horizon: gravity = (0, -1, 0).
        XCTAssertEqual(MotionMath.cameraElevationDegrees(gx: 0, gy: -1, gz: 0), 0, accuracy: 0.001)
    }

    func testElevation_landscapeLevel_isZero() {
        // Phone in landscape, camera on the horizon: gravity = (-1, 0, 0).
        XCTAssertEqual(MotionMath.cameraElevationDegrees(gx: -1, gy: 0, gz: 0), 0, accuracy: 0.001)
        XCTAssertEqual(MotionMath.cameraElevationDegrees(gx: 1, gy: 0, gz: 0), 0, accuracy: 0.001)
    }

    func testElevation_portraitTiltedUp35_isPositive35() {
        // Top tilted back 35° so the back camera points 35° above the horizon.
        let rad = 35.0 * Double.pi / 180.0
        let e = MotionMath.cameraElevationDegrees(gx: 0, gy: -cos(rad), gz: -sin(rad))
        XCTAssertEqual(e, 35, accuracy: 0.001)
    }

    func testElevation_pointingStraightUp_is90() {
        // Face-up on a table: gravity = (0, 0, -1), camera points at the sky.
        XCTAssertEqual(MotionMath.cameraElevationDegrees(gx: 0, gy: 0, gz: -1), 90, accuracy: 0.001)
    }

    func testElevation_pointingStraightDown_isMinus90() {
        XCTAssertEqual(MotionMath.cameraElevationDegrees(gx: 0, gy: 0, gz: 1), -90, accuracy: 0.001)
    }

    func testElevation_clampsOutOfRangeGravity() {
        // Noisy sensor values must not produce NaN from asin.
        let e = MotionMath.cameraElevationDegrees(gx: 0, gy: 0, gz: -1.5)
        XCTAssertEqual(e, 90, accuracy: 0.001)
        XCTAssertFalse(e.isNaN)
    }

    func testRotationRateMagnitude() {
        XCTAssertEqual(MotionMath.rotationRateMagnitude(rx: 0.3, ry: 0.4, rz: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MotionMath.rotationRateMagnitude(rx: 0, ry: 0, rz: 0), 0, accuracy: 1e-9)
    }

    func testEMA_converges() {
        var v = 0.0
        for _ in 0..<200 { v = MotionMath.ema(previous: v, sample: 1.0, alpha: 0.2) }
        XCTAssertEqual(v, 1.0, accuracy: 0.01)
    }

    // MARK: - TripodDetector (A2)

    private func history(
        shakes: [Double], spacing: TimeInterval = 1.0 / 30, endingAt now: Date = Date()
    ) -> [(date: Date, shake: Double)] {
        shakes.enumerated().map { i, s in
            (date: now.addingTimeInterval(-Double(shakes.count - 1 - i) * spacing), shake: s)
        }
    }

    func testTripod_sustainedStillness_isSteady() {
        // 2 s of < 0.005 rad/s → steady.
        let now = Date()
        let h = history(shakes: Array(repeating: 0.002, count: 61), endingAt: now)
        XCTAssertTrue(TripodDetector.isSteady(history: h, at: now))
    }

    func testTripod_singleJolt_breaksSteadiness() {
        // One 0.05 rad/s jolt inside the window → not steady.
        let now = Date()
        var shakes = Array(repeating: 0.002, count: 61)
        shakes[30] = 0.05
        let h = history(shakes: shakes, endingAt: now)
        XCTAssertFalse(TripodDetector.isSteady(history: h, at: now))
    }

    func testTripod_shortHistory_isNotSteady() {
        // Only 1 s of stillness — the 1.5 s window isn't covered.
        let now = Date()
        let h = history(shakes: Array(repeating: 0.002, count: 31), endingAt: now)
        XCTAssertFalse(TripodDetector.isSteady(history: h, at: now))
    }

    func testTripod_emptyHistory_isNotSteady() {
        XCTAssertFalse(TripodDetector.isSteady(history: [], at: Date()))
    }

    func testTripod_handheldShake_isNotSteady() {
        // Typical handheld 0.03 rad/s → not steady.
        let now = Date()
        let h = history(shakes: Array(repeating: 0.03, count: 61), endingAt: now)
        XCTAssertFalse(TripodDetector.isSteady(history: h, at: now))
    }
}
