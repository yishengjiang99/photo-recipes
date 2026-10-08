import XCTest
@testable import PhotoRecipes

/// The exposure seam: when custom shutter/ISO is written in one apply,
/// `setEV` must NOT be called afterwards — the EV bias is folded into the
/// ISO solve instead (and `setEV` itself never leaves `.custom`).
final class ExposureSeamTests: XCTestCase {

    func testEVSkippedAfterCustomExposure() {
        // Typical solver output: shutter + ISO + a folded EV bias.
        let bias = ExposureApplyPolicy.evBiasToProgram(evRaw: "+0.7", wroteCustomExposure: true)
        XCTAssertNil(bias, "setEV must not be called after setCustom in one apply")
    }

    func testEVProgrammedWhenExposureStillAutomatic() {
        // HDR path: no custom exposure → bias is programmed directly.
        XCTAssertEqual(ExposureApplyPolicy.evBiasToProgram(evRaw: "+0.7", wroteCustomExposure: false), 0.7)
        XCTAssertEqual(ExposureApplyPolicy.evBiasToProgram(evRaw: "-0.3", wroteCustomExposure: false), -0.3)
    }

    func testEVSkippedWhenNoEVRequested() {
        XCTAssertNil(ExposureApplyPolicy.evBiasToProgram(evRaw: nil, wroteCustomExposure: false))
    }

    func testWroteCustomExposureHelper() {
        XCTAssertTrue(ExposureApplyPolicy.wroteCustomExposure(shutter: 1 / 60, iso: 400, supported: true))
        XCTAssertTrue(ExposureApplyPolicy.wroteCustomExposure(shutter: nil, iso: 400, supported: true))
        XCTAssertTrue(ExposureApplyPolicy.wroteCustomExposure(shutter: 1 / 60, iso: nil, supported: true))
        XCTAssertFalse(ExposureApplyPolicy.wroteCustomExposure(shutter: nil, iso: nil, supported: true))
        // Unsupported hardware: nothing custom was (or could be) written.
        XCTAssertFalse(ExposureApplyPolicy.wroteCustomExposure(shutter: 1 / 60, iso: 400, supported: false))
    }
}
