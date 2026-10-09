import XCTest
@testable import PhotoRecipes

@MainActor
final class CoordinateSpacesTests: XCTestCase {

    func testVisionToUI_flipsY() {
        // Vision: bottom-left origin → UI: top-left origin.
        let ui = CoordinateSpaces.visionToUI(CGPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(ui.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(ui.y, 0.7, accuracy: 1e-9)
    }

    func testVisionRectToUI_flipsVertically() {
        let ui = CoordinateSpaces.visionRectToUI(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(ui.minX, 0.1, accuracy: 1e-9)
        // maxY in Vision (0.6) becomes minY in UI (0.4).
        XCTAssertEqual(ui.minY, 0.4, accuracy: 1e-9)
        XCTAssertEqual(ui.width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(ui.height, 0.4, accuracy: 1e-9)
    }

    func testUIToLayerPoint_scalesToSize() {
        let lp = CoordinateSpaces.uiToLayerPoint(CGPoint(x: 0.5, y: 0.5), layerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(lp.x, 100, accuracy: 1e-9)
        XCTAssertEqual(lp.y, 50, accuracy: 1e-9)
    }

    func testClamp01() {
        let c = CoordinateSpaces.clamp01(CGPoint(x: 1.4, y: -0.2))
        XCTAssertEqual(c.x, 1, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0, accuracy: 1e-9)
    }

    func testPreviewLayerConverter_withoutLayer_isIdentity() {
        let converter = PreviewLayerDevicePointConverter(layer: nil)
        let p = CGPoint(x: 0.3, y: 0.6)
        let out = converter.devicePoint(uiNormalized: p)
        XCTAssertEqual(out.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(out.y, p.y, accuracy: 1e-9)
    }

    /// UI → device conversion goes through the injected converter (mocked here);
    /// the session must hand the UI point to the converter, not a device point.
    @MainActor
    func testFocusOnUIPoint_usesConverterAndStoresUIPointForReticle() {
        let session = CameraSession()
        let mock = MockDevicePointConverter()
        session.devicePointConverter = mock

        let ui = CGPoint(x: 0.25, y: 0.75)
        session.focusOnUIPoint(ui, lock: true)

        XCTAssertEqual(mock.receivedUI?.x ?? -1, ui.x, accuracy: 1e-9)
        XCTAssertEqual(mock.receivedUI?.y ?? -1, ui.y, accuracy: 1e-9)
        // The reticle (session.focusPoint) stores the UI point, not the device point.
        XCTAssertEqual(session.focusPoint?.x ?? -1, ui.x, accuracy: 1e-9)
        XCTAssertEqual(session.focusPoint?.y ?? -1, ui.y, accuracy: 1e-9)
    }
}

private final class MockDevicePointConverter: DevicePointConverter {
    var receivedUI: CGPoint?
    var stubDevicePoint = CGPoint(x: 0.7, y: 0.3)

    func devicePoint(uiNormalized: CGPoint) -> CGPoint {
        receivedUI = uiNormalized
        return stubDevicePoint
    }
}
