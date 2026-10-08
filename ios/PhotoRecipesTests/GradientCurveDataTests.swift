import XCTest
@testable import PhotoRecipes

/// Section C: the gradient debug overlay's data source must expose the full
/// 13-value curve plus the correct argmax index. The SwiftUI view itself
/// can't render on CI — only the data source is tested here.
final class GradientCurveDataTests: XCTestCase {

    private func stats(scores: [Float], gpuMs: Double = 0) -> GPUFrameStats {
        var s = GPUFrameStats()
        s.gradientScores = scores
        s.gpuMs = gpuMs
        return s
    }

    func testGradientArgmaxIndex_picksMaxScore() {
        var s = stats(scores: [Float](repeating: 0.1, count: 13))
        XCTAssertEqual(s.gradientArgmaxIndex, 0, "ties keep the first index")
        s.gradientScores = [0.2, 0.5, 0.9, 0.3, 0.1, 0.4, 0.6, 0.7, 0.8, 0.05, 0.15, 0.25, 0.35]
        XCTAssertEqual(s.gradientArgmaxIndex, 2)
        s.gradientScores = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0.9, 0.8, 0.7]
        XCTAssertEqual(s.gradientArgmaxIndex, 9)
    }

    func testGradientArgmaxIndex_emptyScores_isNil() {
        let s = GPUFrameStats()
        XCTAssertNil(s.gradientArgmaxIndex)
    }

    func testCurveData_exposesThirteenValuesAndArgmax() {
        var scores = [Float](repeating: 0.2, count: 13)
        scores[7] = 1.5 // argmax at index 7
        let data = try! XCTUnwrap(GradientCurveData.from(stats(scores: scores, gpuMs: 1.23)))
        XCTAssertEqual(data.ratios.count, 13)
        XCTAssertEqual(data.normalizedScores.count, 13)
        XCTAssertEqual(data.rawScores.count, 13)
        XCTAssertEqual(data.argmaxIndex, 7)
        XCTAssertEqual(data.rawScores[7], 1.5)
        // Normalized to max = 1.
        XCTAssertEqual(data.normalizedScores[7], 1.0, accuracy: 1e-6)
        XCTAssertEqual(data.normalizedScores.max()!, 1.0, accuracy: 1e-6)
        // Ratios match the shared geomspace table.
        XCTAssertEqual(data.ratios, GPUStatsCore.gradientRatios)
        XCTAssertEqual(data.ratios.first!, 0.25, accuracy: 1e-6)
        XCTAssertEqual(data.ratios.last!, 4.0, accuracy: 1e-6)
        XCTAssertEqual(data.gpuMs, 1.23, accuracy: 1e-9)
    }

    func testCurveData_flatScores_normalizeToZeroes() {
        // max == 0 → no division by zero; scores pass through.
        let data = try! XCTUnwrap(GradientCurveData.from(
            stats(scores: [Float](repeating: 0, count: 13))))
        XCTAssertTrue(data.normalizedScores.allSatisfy { $0 == 0 })
        XCTAssertEqual(data.argmaxIndex, 0)
    }

    func testCurveData_wrongScoreCount_returnsNil() {
        XCTAssertNil(GradientCurveData.from(stats(scores: [0.1, 0.2, 0.3])))
        XCTAssertNil(GradientCurveData.from(stats(scores: [])))
        XCTAssertNil(GradientCurveData.from(stats(scores: [Float](repeating: 0.1, count: 14))))
    }
}
