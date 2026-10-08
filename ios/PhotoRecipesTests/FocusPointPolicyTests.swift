import XCTest
@testable import PhotoRecipes

/// Part 0.1: Auto Optimize's apply path must never change the exposure point
/// of interest. `convergeAutoExposure` resets it to frame center and
/// `verifyExposure` meters there — if `applyPhoneTargets` moved it to the
/// face/subject after custom exposure was written, the correction could
/// cancel the backlit +0.7 EV (or double it to +1.4).
///
/// CameraSession is final and needs a capture device, so the test pins the
/// policy seam that `applyPhoneTargets` passes to
/// `focusOnUIPoint(_:lock:setsExposurePoint:)` (same pattern as
/// `ExposureApplyPolicy` in ExposureSeamTests).
final class FocusPointPolicyTests: XCTestCase {

    func testAutoOptimizeApplyPathNeverMovesExposurePoint() {
        XCTAssertFalse(
            FocusPointPolicy.setsExposurePoint(for: .autoOptimizeApply),
            "applyPhoneTargets must move focus only — the exposure point stays where convergeAutoExposure put it"
        )
    }

    func testTapToFocusKeepsHistoricalBehavior() {
        XCTAssertTrue(
            FocusPointPolicy.setsExposurePoint(for: .tapToFocus),
            "tap-to-focus must keep setting both focus and exposure points"
        )
    }

    func testManualControlKeepsHistoricalBehavior() {
        XCTAssertTrue(
            FocusPointPolicy.setsExposurePoint(for: .manualControl),
            "manual controls must keep setting both focus and exposure points"
        )
    }
}
