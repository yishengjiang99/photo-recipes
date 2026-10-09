import XCTest
@testable import PhotoRecipes

/// Regression for TestFlight 1.4 (71): `ControlsPanelView` rendered
/// `formatShutter(session.exposureSeconds)` while the capture session was still starting,
/// `exposureSeconds` was NaN (`CMTimeGetSeconds` of an invalid CMTime) and
/// `Int((1.0 / seconds).rounded())` trapped ("Double value cannot be converted to Int
/// because it is either infinite or NaN").
final class CameraValueGuardTests: XCTestCase {

    func testFormatShutterNeverTrapsOnNonFiniteOrNonPositive() {
        for bad in [Double.nan, -.nan, .infinity, -.infinity, 0, -0.0, -1, -1.0 / 60] {
            XCTAssertEqual(RecipeCameraMapper.formatShutter(bad), RecipeCameraMapper.unknownReadout, "\(bad)")
        }
    }

    func testFormatShutterTinyAndHugeValuesDoNotTrap() {
        // 1 / tiny overflows to +inf; must not reach Int(...).
        XCTAssertTrue(RecipeCameraMapper.formatShutter(Double.leastNonzeroMagnitude).hasPrefix("1/"))
        XCTAssertTrue(RecipeCameraMapper.formatShutter(1e-300).hasPrefix("1/"))
        XCTAssertEqual(RecipeCameraMapper.formatShutter(Double.greatestFiniteMagnitude).last, "s")
    }

    func testFormatShutterNormalValuesUnchanged() {
        XCTAssertEqual(RecipeCameraMapper.formatShutter(1.0 / 60), "1/60s")
        XCTAssertEqual(RecipeCameraMapper.formatShutter(1.0 / 8000), "1/8000s")
        XCTAssertEqual(RecipeCameraMapper.formatShutter(0.5), "1/2s")
        XCTAssertEqual(RecipeCameraMapper.formatShutter(1), "1.0s")
        XCTAssertEqual(RecipeCameraMapper.formatShutter(2.5), "2.5s")
    }

    func testFormatISO() {
        XCTAssertEqual(RecipeCameraMapper.formatISO(100), "100")
        XCTAssertEqual(RecipeCameraMapper.formatISO(399.6), "400")
        for bad: Float in [.nan, .infinity, -.infinity, 0, -50, .greatestFiniteMagnitude] {
            XCTAssertEqual(RecipeCameraMapper.formatISO(bad), RecipeCameraMapper.unknownReadout, "\(bad)")
        }
    }

    func testSafeRoundedInt() {
        XCTAssertEqual(CameraValues.safeRoundedInt(29.6), 30)
        XCTAssertEqual(CameraValues.safeRoundedInt(-2.4), -2)
        XCTAssertNil(CameraValues.safeRoundedInt(.nan))
        XCTAssertNil(CameraValues.safeRoundedInt(.infinity))
        XCTAssertNil(CameraValues.safeRoundedInt(-.infinity))
        XCTAssertNil(CameraValues.safeRoundedInt(1e300))
    }

    func testPublishSanitizersKeepLastGoodValue() {
        XCTAssertEqual(CameraValues.exposure(.nan, fallback: 1.0 / 125), 1.0 / 125)
        XCTAssertEqual(CameraValues.exposure(.infinity, fallback: 0), 1.0 / 60)
        XCTAssertEqual(CameraValues.exposure(0, fallback: .nan), 1.0 / 60)
        XCTAssertEqual(CameraValues.exposure(1.0 / 30, fallback: 1.0 / 60), 1.0 / 30)
        XCTAssertEqual(CameraValues.iso(.nan, fallback: 200), 200)
        XCTAssertEqual(CameraValues.iso(-1, fallback: .nan), 100)
        XCTAssertEqual(CameraValues.iso(800, fallback: 100), 800)
        XCTAssertEqual(CameraValues.evBias(.nan, fallback: 0.7), 0.7)
        XCTAssertEqual(CameraValues.evBias(.infinity, fallback: .nan), 0)
        XCTAssertEqual(CameraValues.evBias(-1.3, fallback: 0), -1.3)
    }

    func testSanitizedCapabilitiesReplaceNonFiniteBounds() {
        var c = DeviceCapabilities.unknown
        c.minExposureSeconds = .nan
        c.maxExposureSeconds = .infinity
        c.minISO = .nan
        c.maxISO = 3200
        c.minEV = -.infinity
        c.maxEV = 8
        let s = CameraValues.sanitized(c)
        let u = DeviceCapabilities.unknown
        XCTAssertEqual(s.minExposureSeconds, u.minExposureSeconds)
        XCTAssertEqual(s.maxExposureSeconds, u.maxExposureSeconds)
        XCTAssertEqual(s.minISO, u.minISO)
        XCTAssertEqual(s.maxISO, 3200)
        XCTAssertEqual(s.minEV, u.minEV)
        XCTAssertEqual(s.maxEV, 8)
        // Valid capabilities pass through untouched.
        XCTAssertEqual(CameraValues.sanitized(u), u)
    }

    @MainActor
    func testSessionReadoutsBeforeSessionRunsAreRenderable() {
        // No device yet: readouts must be finite and the readout line must not trap.
        let session = CameraSession()
        session.refreshReadouts()
        XCTAssertTrue(session.exposureSeconds.isFinite && session.exposureSeconds > 0)
        XCTAssertTrue(session.iso.isFinite && session.iso > 0)
        XCTAssertFalse(session.readoutLine.isEmpty)
        XCTAssertEqual(RecipeCameraMapper.formatShutter(session.exposureSeconds), "1/60s")
    }

    func testMapperClampNoteWithHugeISODoesNotTrap() {
        var caps = DeviceCapabilities.unknown
        caps.supportsCustomExposure = true
        let dials = DialSettings(mode: .manual, aperture: nil, shutter: nil,
                                 iso: "ISO 99999999999999999999999", evBracket: nil, notes: nil)
        let mapped = RecipeCameraMapper.map(dials: dials, capabilities: caps)
        XCTAssertEqual(mapped.iso, caps.maxISO)
    }
}
