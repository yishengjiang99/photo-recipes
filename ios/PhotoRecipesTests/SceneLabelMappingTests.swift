import XCTest
@testable import PhotoRecipes

/// Phase 2: Vision scene labels → recipe boosts, alongside the typed note.
/// The user's explicit note intent must always win over label evidence.
final class SceneLabelMappingTests: XCTestCase {

    private func features(
        labels: [SceneLabel],
        highlightClip: Float = 0,
        note: String = ""
    ) -> SceneFeatures {
        var f = SceneFeatures()
        f.sceneLabels = labels
        f.highlightClipFraction = highlightClip
        f.recipeIntent = IntentMatcher.match(note: note)
        return f
    }

    private func label(_ id: String, _ confidence: Float) -> SceneLabel {
        SceneLabel(identifier: id, confidence: confidence)
    }

    // MARK: - mapper unit tests

    func testWaterfallBoostsBlurMovingSubjects() {
        let (boosts, phrases) = SceneLabelRecipeMapper.boosts(
            labels: [label("waterfall", 0.9)], features: SceneFeatures())
        XCTAssertEqual(try! XCTUnwrap(boosts["blur-moving-subjects"]), 0.8, accuracy: 1e-9)
        XCTAssertEqual(phrases["blur-moving-subjects"], ["label.waterfall"])
    }

    func testFireworksBoostsBlurMovingSubjects() {
        let (boosts, phrases) = SceneLabelRecipeMapper.boosts(
            labels: [label("fireworks", 0.85)], features: SceneFeatures())
        XCTAssertEqual(try! XCTUnwrap(boosts["blur-moving-subjects"]), 0.8, accuracy: 1e-9)
        XCTAssertEqual(phrases["blur-moving-subjects"], ["label.fireworks"])
    }

    func testSunsetWithHighlightClippingBoostsHDR() {
        var f = SceneFeatures()
        f.highlightClipFraction = 0.1
        let (boosts, phrases) = SceneLabelRecipeMapper.boosts(
            labels: [label("sunset", 0.8)], features: f)
        XCTAssertEqual(try! XCTUnwrap(boosts["hdr-brights-darks"]), 1.0, accuracy: 1e-9)
        XCTAssertEqual(phrases["hdr-brights-darks"], ["label.sunset"])
    }

    func testSunsetWithoutClipping_noHDRBoost() {
        // Sunset light but no clipped highlights → not an HDR scene.
        let (boosts, _) = SceneLabelRecipeMapper.boosts(
            labels: [label("sunset", 0.8)], features: SceneFeatures())
        XCTAssertNil(boosts["hdr-brights-darks"])
    }

    func testLowConfidenceLabelsIgnored() {
        let (boosts, _) = SceneLabelRecipeMapper.boosts(
            labels: [label("waterfall", 0.2)], features: SceneFeatures())
        XCTAssertTrue(boosts.isEmpty)
    }

    func testBoostsCappedAtMax() {
        // Two waterfall-ish labels must not stack past the cap: the note
        // intent (bonus 3.0) always stays dominant.
        let (boosts, _) = SceneLabelRecipeMapper.boosts(
            labels: [label("waterfall", 0.9), label("waterfalls", 0.9)],
            features: SceneFeatures())
        XCTAssertLessThanOrEqual(boosts["blur-moving-subjects"] ?? 0,
                                 SceneLabelRecipeMapper.maxBoost)
    }

    // MARK: - scorer integration

    func testScorer_labelBoostRaisesTargetRecipe() {
        let scorer = JSONRecipeScorer()
        let without = scorer.score(features(labels: []))
        let with = scorer.score(features(labels: [label("waterfall", 0.95)]))
        let pWithout = without.first(where: { $0.recipeId == "blur-moving-subjects" })?.probability
        let pWith = with.first(where: { $0.recipeId == "blur-moving-subjects" })?.probability
        let before = try! XCTUnwrap(pWithout)
        let after = try! XCTUnwrap(pWith)
        XCTAssertGreaterThan(after, before, "waterfall label must raise blur-moving-subjects")
    }

    func testNoteIntentWinsOverLabels() {
        // Note "portrait" → intent portrait-pop (+3.0) beats the waterfall
        // label boost (+0.8) for blur-moving-subjects.
        let f = features(labels: [label("waterfall", 0.95)], note: "portrait")
        XCTAssertEqual(f.recipeIntent?.recipeId, "portrait-pop")
        let scores = JSONRecipeScorer().score(f)
        XCTAssertEqual(scores.first?.recipeId, "portrait-pop",
                       "explicit note intent must win over scene labels")
    }

    func testLabelEvidenceSurfacedInExplanation() {
        let f = features(labels: [label("waterfall", 0.95)])
        let scores = JSONRecipeScorer().score(f)
        let blur = try! XCTUnwrap(scores.first(where: { $0.recipeId == "blur-moving-subjects" }))
        XCTAssertTrue(blur.topFeatures.contains("label.waterfall"))
        let reason = RecipeExplainer.reason(
            recipeId: "blur-moving-subjects", features: f, topFeatures: blur.topFeatures)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("waterfall"),
                      "reason should mention the waterfall label: \(reason)")
    }
}
