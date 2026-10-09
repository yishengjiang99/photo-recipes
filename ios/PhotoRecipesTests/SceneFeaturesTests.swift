import XCTest
import CoreVideo
@testable import PhotoRecipes

final class SceneFeaturesTests: XCTestCase {

    // MARK: - Label mapping consistency

    /// Every identifier in scene-label-groups.json must exist in vision-labels.txt.
    func testLabelMappingIdentifiersExistInDump() throws {
        guard let jsonURL = Bundle.main.url(forResource: "scene-label-groups", withExtension: "json") else {
            XCTFail("scene-label-groups.json missing from app bundle — check project.yml resources")
            return
        }
        guard let txtURL = Bundle.main.url(forResource: "vision-labels", withExtension: "txt") else {
            XCTFail("vision-labels.txt missing from app bundle — check project.yml resources")
            return
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        let groups = json?["groups"] as? [String: [String]] ?? [:]
        XCTAssertFalse(groups.isEmpty, "no groups decoded from scene-label-groups.json")

        let dumpLines = try String(contentsOf: txtURL, encoding: .utf8)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let dump = Set(dumpLines)
        XCTAssertGreaterThan(dump.count, 100, "vision-labels.txt looks truncated")

        var missing: [String] = []
        for (group, ids) in groups {
            for id in ids where !dump.contains(id.lowercased()) {
                missing.append("\(group): \(id)")
            }
        }
        XCTAssertTrue(missing.isEmpty, "identifiers missing from vision-labels.txt: \(missing.joined(separator: ", "))")

        // Every SemanticGroup must have a mapping.
        for group in SemanticGroup.allCases {
            XCTAssertNotNil(groups[group.rawValue], "no mapping for SemanticGroup.\(group.rawValue)")
        }
    }

    func testDebugDumpHelperProducesSortedLines() {
        // Runs the real Vision API on simulator/device; on CI it must at least
        // not crash and return *something* (possibly empty on some runtimes).
        let dump = SceneLabelMapper.dumpSupportedIdentifiers()
        XCTAssertNotNil(dump)
    }

    // MARK: - Feature vector contract

    func testFeatureVectorDimensionMatchesContract() {
        XCTAssertEqual(SceneFeatures.vectorDimension, 45)
        XCTAssertEqual(SceneFeatures.vectorFeatureNames.count, SceneFeatures().featureVector().count)
        // No duplicate feature names.
        XCTAssertEqual(Set(SceneFeatures.vectorFeatureNames).count, SceneFeatures.vectorFeatureNames.count)
    }

    func testCheatsheetExcludedFromAutoSelect() {
        XCTAssertEqual(SceneFeatures.recipeOrder.count, 10)
        XCTAssertFalse(SceneFeatures.autoSelectCandidates.contains("exposure-triangle-cheatsheet"))
        XCTAssertFalse(SceneFeatures.autoSelectCandidates.contains("get-down-low"))
        XCTAssertEqual(SceneFeatures.autoSelectCandidates.count, 8)
    }

    func testIntentOneHotSlice() {
        var f = SceneFeatures()
        f.recipeIntent = RecipeIntent(recipeId: "panning-sharp-subject", matchedPhrase: "pan")
        let v = f.featureVector()
        let idx = SceneFeatures.vectorFeatureNames.firstIndex(of: "intent.panning-sharp-subject")!
        XCTAssertEqual(v[idx], 1)
        XCTAssertEqual(v[SceneFeatures.vectorFeatureNames.firstIndex(of: "intent.blur-moving-subjects")!], 0)
    }

    // MARK: - EV100

    func testEV100_daylight() {
        // f/1.8, 1/60s, ISO 100 → log2(1.8²·60) ≈ 7.60.
        let ev = EV100Helper.ev100(aperture: 1.8, exposureSeconds: 1 / 60, iso: 100,
                                   exposureTargetOffset: nil, wasCustom: false)
        XCTAssertEqual(ev ?? -1, 7.603, accuracy: 0.01)
    }

    func testEV100_customModeAppliesOffset() {
        let base = EV100Helper.ev100(aperture: 1.8, exposureSeconds: 1 / 60, iso: 100,
                                     exposureTargetOffset: nil, wasCustom: false)!
        let corrected = EV100Helper.ev100(aperture: 1.8, exposureSeconds: 1 / 60, iso: 100,
                                          exposureTargetOffset: 1.0, wasCustom: true)!
        XCTAssertEqual(corrected, base + 1.0, accuracy: 0.001)
    }

    func testEV100_ignoresOffsetInAutoMode() {
        let a = EV100Helper.ev100(aperture: 1.8, exposureSeconds: 1 / 60, iso: 100,
                                  exposureTargetOffset: 1.0, wasCustom: false)!
        let b = EV100Helper.ev100(aperture: 1.8, exposureSeconds: 1 / 60, iso: 100,
                                  exposureTargetOffset: nil, wasCustom: false)!
        XCTAssertEqual(a, b, accuracy: 0.0001)
    }

    func testEV100_nilOnBadInput() {
        XCTAssertNil(EV100Helper.ev100(aperture: nil, exposureSeconds: 1 / 60, iso: 100, exposureTargetOffset: nil, wasCustom: false))
        XCTAssertNil(EV100Helper.ev100(aperture: 1.8, exposureSeconds: 0, iso: 100, exposureTargetOffset: nil, wasCustom: false))
    }

    // MARK: - Histogram percentiles

    func testHistogram_uniformMidGray() {
        var bins = [Int](repeating: 0, count: 256)
        bins[128] = 10_000
        let s = LuminanceStats.fromHistogram(bins: bins)
        XCTAssertEqual(s.mean, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(s.spreadStops, 0, accuracy: 0.05)
        XCTAssertEqual(s.highlightClipFraction, 0, accuracy: 0.001)
        XCTAssertEqual(s.shadowCrushFraction, 0, accuracy: 0.001)
    }

    func testHistogram_bimodalSpreadAndClips() {
        var bins = [Int](repeating: 0, count: 256)
        bins[10] = 5_000   // crushed shadows (< 0.05)
        bins[245] = 5_000  // clipped highlights (> 0.95)
        let s = LuminanceStats.fromHistogram(bins: bins)
        XCTAssertEqual(s.shadowCrushFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.highlightClipFraction, 0.5, accuracy: 0.001)
        // p99 ≈ 244/255, p1 = 10/255 → ~4.6 stops.
        XCTAssertEqual(s.spreadStops, Float(log2(244.0 / 10.0)), accuracy: 0.1)
    }

    // MARK: - Optical flow aggregation

    func testFlow_uniformPan() {
        // Whole frame pans right: 5 px over 0.1 s on a 64px-wide flow frame,
        // scaled to a 640px full frame → 500 px/s background, no subject.
        let flow = makeFlowBuffer(w: 64, h: 64) { _, _ in (5, 0) }
        let m = OpticalFlowAggregator.aggregate(flow: flow, dt: 0.1, subjectBox: nil, fullFrameWidthPx: 640)
        XCTAssertEqual(m.backgroundSpeedPxPerSec, 500, accuracy: 5)
        XCTAssertEqual(m.subjectSpeedPxPerSec, 0, accuracy: 0.001)
        XCTAssertEqual(m.subjectRelativeSpeedPxPerSec, 0, accuracy: 0.001)
    }

    func testFlow_movingBoxOnStillBackground() {
        let box = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let flow = makeFlowBuffer(w: 64, h: 64) { x, y in
            box.contains(CGPoint(x: CGFloat(x) / 64.0, y: CGFloat(y) / 64.0)) ? (4, 0) : (0, 0)
        }
        let m = OpticalFlowAggregator.aggregate(flow: flow, dt: 0.1, subjectBox: box, fullFrameWidthPx: 640)
        XCTAssertEqual(m.subjectSpeedPxPerSec, 400, accuracy: 10)
        XCTAssertEqual(m.backgroundSpeedPxPerSec, 0, accuracy: 1)
        XCTAssertEqual(m.subjectRelativeSpeedPxPerSec, 400, accuracy: 10)
        XCTAssertEqual(m.directionX, 1, accuracy: 0.05)
        XCTAssertEqual(m.directionY, 0, accuracy: 0.05)
    }

    func testFlow_subjectAndBackgroundBothMoving() {
        // Subject moves right at 4px/dt, background pans right at 2px/dt:
        // relative speed isolates the subject's own motion.
        let box = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let flow = makeFlowBuffer(w: 64, h: 64) { x, y in
            box.contains(CGPoint(x: CGFloat(x) / 64.0, y: CGFloat(y) / 64.0)) ? (4, 0) : (2, 0)
        }
        let m = OpticalFlowAggregator.aggregate(flow: flow, dt: 0.1, subjectBox: box, fullFrameWidthPx: 640)
        XCTAssertEqual(m.subjectRelativeSpeedPxPerSec, 200, accuracy: 10)
        XCTAssertEqual(m.backgroundSpeedPxPerSec, 200, accuracy: 10)
    }

    func testFlow_zeroDt_returnsZero() {
        let flow = makeFlowBuffer(w: 16, h: 16) { _, _ in (9, 9) }
        let m = OpticalFlowAggregator.aggregate(flow: flow, dt: 0, subjectBox: nil, fullFrameWidthPx: 160)
        XCTAssertEqual(m.backgroundSpeedPxPerSec, 0, accuracy: 0.001)
    }

    // MARK: - Intent matcher

    func testIntent_yellowFlowerBackground_isNil() {
        // Old substring bugs: "yellow" ⊃ "low", "background" ⊃ "ground".
        XCTAssertNil(IntentMatcher.match(note: "A yellow flower in the background"))
    }

    func testIntent_avoidMotionBlur_isNil() {
        XCTAssertNil(IntentMatcher.match(note: "avoid motion blur"))
        XCTAssertNil(IntentMatcher.match(note: "no long exposure please"))
        XCTAssertNil(IntentMatcher.match(note: "don't blur the background"))
    }

    func testIntent_silkyWaterfall_isBlur() {
        let r = IntentMatcher.match(note: "silky waterfall")
        XCTAssertEqual(r?.recipeId, "blur-moving-subjects")
    }

    func testIntent_panWithCyclist_isPanning() {
        let r = IntentMatcher.match(note: "pan with the cyclist")
        XCTAssertEqual(r?.recipeId, "panning-sharp-subject")
    }

    func testIntent_getLowKneeHeight_isNotAnIntent() {
        XCTAssertNil(IntentMatcher.match(note: "get low, knee height"))
    }

    func testIntent_sunsetSilhouette_isHDR() {
        XCTAssertEqual(IntentMatcher.match(note: "sunset silhouette")?.recipeId, "hdr-brights-darks")
    }

    func testIntent_portraitBlurBackground_isPortraitPop() {
        XCTAssertEqual(IntentMatcher.match(note: "blur the background, eyes sharp")?.recipeId, "portrait-pop")
    }

    func testIntent_emptyNote_isNil() {
        XCTAssertNil(IntentMatcher.match(note: "   "))
    }

    // MARK: - Scene chip text

    func testSceneChipText_waterBrightMoving() {
        var f = SceneFeatures()
        f.semanticGroups = [.water: 0.9]
        f.sceneEV100 = 14
        f.subjectRelativeSpeedPxPerSec = 900
        f.backgroundSpeedPxPerSec = 50
        XCTAssertEqual(SceneChipText.make(features: f), "Water · bright · moving subject")
    }

    // MARK: - helpers

    /// Synthetic optical-flow buffer: interleaved float32 (dx, dy) per pixel,
    /// displacement of the targeted frame in flow-frame pixels.
    private func makeFlowBuffer(w: Int, h: Int, fill: (Int, Int) -> (Float, Float)) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, w, h,
            kCVPixelFormatType_TwoComponent32Float, nil, &pb
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: Float.self)
        let rowFloats = CVPixelBufferGetBytesPerRow(buf) / 4
        for y in 0..<h {
            for x in 0..<w {
                let (dx, dy) = fill(x, y)
                base[y * rowFloats + x * 2] = dx
                base[y * rowFloats + x * 2 + 1] = dy
            }
        }
        return buf
    }
}
