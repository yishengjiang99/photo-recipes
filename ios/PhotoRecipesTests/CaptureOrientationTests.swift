import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// Landscape: the UI is portrait-only (the camera chrome is laid out for a
/// portrait phone), and stills take their rotation from how the phone is held.
@MainActor
final class CaptureOrientationTests: XCTestCase {

    func testAppDeclaresPortraitOnly() {
        let iphone = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String]
        XCTAssertEqual(iphone, ["UIInterfaceOrientationPortrait"])
        let ipad = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad") as? [String]
        XCTAssertEqual(ipad, ["UIInterfaceOrientationPortrait"])
    }

    func testCaptureAngleKeepsQuarterTurns() {
        // Portrait, landscape (home/USB-C right), upside down, landscape (left).
        for a: CGFloat in [0, 90, 180, 270] {
            XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: a), a)
        }
    }

    func testCaptureAngleSnapsAndWraps() {
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: 88), 90)
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: 359), 0)
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: 360), 0)
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: -90), 270)
    }

    func testCaptureAngleDefaultsToPortrait() {
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: nil), 90)
        XCTAssertEqual(CameraSession.captureRotationAngle(horizonLevel: .nan), 90)
    }
}
