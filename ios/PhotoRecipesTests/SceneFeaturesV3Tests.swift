import XCTest
@testable import PhotoRecipes

/// Phase 2: SceneFeatures schema v3 — new fields appended at the end,
/// Codable round-trip, tolerant decoding of older (v2) payloads, and the
/// Core ML feature-vector contract staying at 45 dimensions.
final class SceneFeaturesV3Tests: XCTestCase {

    func testSchemaVersionIs4() {
        XCTAssertEqual(SceneFeatures.currentSchemaVersion, 4)
    }

    func testVectorDimensionUnchanged() {
        // v3 fields stay OUT of the Core ML feature vector (model contract).
        XCTAssertEqual(SceneFeatures.vectorDimension, 45)
        XCTAssertEqual(SceneFeatures.vectorFeatureNames.count, 45)
    }

    func testRoundTrip() throws {
        var f = SceneFeatures()
        f.capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        f.gpuStatsFresh = true
        f.gpuStatsSource = "cpu"
        f.lumaHistogram64 = (0..<64).map { _ in 768 }
        f.grayWorldMeanR = 0.5
        f.grayWorldMeanG = 0.48
        f.grayWorldMeanB = 0.45
        f.lumaContrast = 0.2
        f.gradientScores = (0..<13).map { Float($0) * 1000 }
        f.sceneLabels = [
            SceneLabel(identifier: "waterfall", confidence: 0.9),
            SceneLabel(identifier: "valley", confidence: 0.4),
        ]
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SceneFeatures.self, from: data)
        XCTAssertEqual(back, f)
        XCTAssertEqual(back.schemaVersion, 3)
        XCTAssertEqual(back.lumaHistogram64?.count, 64)
        XCTAssertEqual(back.gradientScores?.count, 13)
        XCTAssertEqual(back.sceneLabels?.count, 2)
    }

    func testV2PayloadDecodesWithTolerantDefaults() throws {
        // A schema-v2 payload has none of the v3 keys — decoding must not
        // throw and must leave the v3 fields at their defaults.
        let v2: [String: Any] = [
            "schemaVersion": 2,
            "highlightClipFraction": 0.1,
            "semanticGroups": ["water": 0.8],
        ]
        let data = try JSONSerialization.data(withJSONObject: v2)
        let f = try JSONDecoder().decode(SceneFeatures.self, from: data)
        XCTAssertEqual(f.highlightClipFraction, 0.1, accuracy: 1e-6)
        XCTAssertEqual(f.semanticGroups[.water], 0.8)
        XCTAssertFalse(f.gpuStatsFresh)
        XCTAssertNil(f.gpuStatsSource)
        XCTAssertNil(f.lumaHistogram64)
        XCTAssertNil(f.grayWorldMeanR)
        XCTAssertNil(f.grayWorldMeanG)
        XCTAssertNil(f.grayWorldMeanB)
        XCTAssertNil(f.lumaContrast)
        XCTAssertNil(f.gradientScores)
        XCTAssertNil(f.sceneLabels)
    }

    func testSceneLabelCodable() throws {
        let label = SceneLabel(identifier: "Fireworks", confidence: 0.77)
        let data = try JSONEncoder().encode(label)
        let back = try JSONDecoder().decode(SceneLabel.self, from: data)
        XCTAssertEqual(back, label)
    }
}
