import XCTest
@testable import PhotoRecipes

final class SceneSensorTests: XCTestCase {

    func testHysteresis_enterAtPointFive() {
        var h = SemanticHysteresis()
        // Below enter threshold → not active.
        XCTAssertNil(h.filter([.water: 0.49])[.water])
        // At/above 0.5 → active.
        XCTAssertEqual(h.filter([.water: 0.5])[.water], 0.5)
        XCTAssertTrue(h.active.contains(.water))
    }

    func testHysteresis_staysActiveUntilPointThreeFive() {
        var h = SemanticHysteresis()
        _ = h.filter([.water: 0.9])
        XCTAssertTrue(h.active.contains(.water))
        // Dips to 0.4 → still active (exit is 0.35).
        XCTAssertEqual(h.filter([.water: 0.4])[.water], 0.4)
        XCTAssertTrue(h.active.contains(.water))
        // At 0.34 → exits.
        XCTAssertNil(h.filter([.water: 0.34])[.water])
        XCTAssertFalse(h.active.contains(.water))
    }

    func testHysteresis_independentPerGroup() {
        var h = SemanticHysteresis()
        let out = h.filter([.water: 0.8, .person: 0.2])
        XCTAssertNotNil(out[.water])
        XCTAssertNil(out[.person])
    }

    func testSnapshot_ageIsInfinityWithNoData() async {
        let sensor = SceneSensor()
        let snap = await sensor.current()
        XCTAssertTrue(snap.age.isInfinite)
    }

    func testRefreshNow_withoutFrames_returnsNil() async {
        let sensor = SceneSensor()
        let metering = MeteringSample(
            exposureSeconds: 1 / 60, iso: 100, aperture: 1.8,
            exposureTargetOffset: nil, wasCustom: false,
            fieldOfViewDegrees: 70, fullFrameWidthPx: 1920
        )
        let result = await sensor.refreshNow(metering: metering, note: "")
        XCTAssertNil(result)
    }

    func testIngestAndVisibilityLifecycle() async {
        let sensor = SceneSensor()
        await sensor.start()
        await sensor.setVisible(true)
        await sensor.setVisible(false)
        await sensor.stop()
        // No crash = lifecycle is sound.
    }
}
