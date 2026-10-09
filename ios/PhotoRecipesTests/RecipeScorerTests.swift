import XCTest
@testable import PhotoRecipes

final class RecipeScorerTests: XCTestCase {

    private var scorer: JSONRecipeScorer!

    override func setUp() {
        super.setUp()
        scorer = JSONRecipeScorer()
    }

    // MARK: - helpers

    private func fixture(_ name: String) throws -> SceneFeatures {
        guard let url = Bundle(for: RecipeScorerTests.self)
            .url(forResource: name, withExtension: "json", subdirectory: "Fixtures/scene-features")
        else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture \(name).json missing from test bundle"])
        }
        return try JSONDecoder().decode(SceneFeatures.self, from: Data(contentsOf: url))
    }

    private func expectedTops() throws -> [String: String?] {
        guard let url = Bundle(for: RecipeScorerTests.self)
            .url(forResource: "expected", withExtension: "json", subdirectory: "Fixtures/scene-features")
        else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "expected.json missing from test bundle"])
        }
        let raw = try JSONDecoder().decode([String: String?].self, from: Data(contentsOf: url))
        return raw
    }

    // MARK: - golden fixtures

    /// Every fixture in Fixtures/scene-features/*.json scores its expected top
    /// recipe (or is ambiguous when expected is null).
    func testGoldenFixtures() throws {
        let expected = try expectedTops()
        XCTAssertGreaterThanOrEqual(expected.count, 18, "fixture set looks truncated")
        var failures: [String] = []
        for (name, exp) in expected.sorted(by: { $0.key < $1.key }) {
            let features = try fixture(name)
            let scores = scorer.score(features)
            guard let top = scores.first else {
                failures.append("\(name): no scores")
                continue
            }
            if let exp {
                if top.recipeId != exp {
                    failures.append("\(name): top=\(top.recipeId) p=\(String(format: "%.2f", top.probability)), expected \(exp)")
                }
            } else {
                // Ambiguous: low confidence or thin margin must hold.
                let second = scores.dropFirst().first
                let margin = top.probability - (second?.probability ?? 0)
                if !(top.probability < 0.55 || margin < 0.15) {
                    failures.append("\(name): expected ambiguous, got \(top.recipeId) p=\(String(format: "%.2f", top.probability)) margin=\(String(format: "%.2f", margin))")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "golden fixture failures:\n" + failures.joined(separator: "\n"))
    }

    // MARK: - spec's named cases

    func testUprightPortraitStillDaylight_isNotGetDownLow() throws {
        let features = try fixture("person-standing-daylight")
        let scores = scorer.score(features)
        XCTAssertEqual(scores.first?.recipeId, "portrait-pop")
        let gdl = scores.first(where: { $0.recipeId == "get-down-low" })
        XCTAssertLessThan(gdl?.probability ?? 1, 0.2, "upright portrait must not read as low-angle")
    }

    func testCyclistPanning_isPanning() throws {
        let scores = scorer.score(try fixture("cyclist-panning"))
        XCTAssertEqual(scores.first?.recipeId, "panning-sharp-subject")
    }

    func testWaterfallTripod_isBlur() throws {
        let scores = scorer.score(try fixture("waterfall-tripod"))
        XCTAssertEqual(scores.first?.recipeId, "blur-moving-subjects")
    }

    /// Device report 2026-10-08: a parked car in direct sun, phone held by
    /// hand. Wobble moved subject and background together, which read as a
    /// perfect pan (Panning p≈0.82) and locked 1/30 s in daylight.
    func testParkedCarHandheld_isNotPanningOrBlur() throws {
        let scores = scorer.score(try fixture("parked-car-handheld-sun"))
        let top = try XCTUnwrap(scores.first)
        XCTAssertNotEqual(top.recipeId, "panning-sharp-subject")
        XCTAssertNotEqual(top.recipeId, "blur-moving-subjects")
        let pan = scores.first(where: { $0.recipeId == "panning-sharp-subject" })?.probability ?? 0
        XCTAssertLessThan(pan, 0.3, "handheld wobble must not read as a pan")
    }

    func testHandheldWobble_panMatchIsZero() {
        var f = SceneFeatures()
        f.subjectSpeedPxPerSec = 150
        f.backgroundSpeedPxPerSec = 140
        f.subjectRelativeSpeedPxPerSec = 15
        let i = SceneFeatures.vectorFeatureNames.firstIndex(of: "motion.panMatchesSubject")!
        XCTAssertEqual(f.featureVector()[i], 0)
        // A real sweep still counts.
        f.backgroundSpeedPxPerSec = 1400
        f.subjectSpeedPxPerSec = 1500
        f.subjectRelativeSpeedPxPerSec = 120
        XCTAssertGreaterThan(f.featureVector()[i], 0.9)
    }

    func testSunsetSilhouette_isHDR() throws {
        let scores = scorer.score(try fixture("sunset-silhouette"))
        XCTAssertEqual(scores.first?.recipeId, "hdr-brights-darks")
    }

    func testFlowerLowAngle_isGetDownLow() throws {
        let scores = scorer.score(try fixture("flower-low-angle"))
        XCTAssertEqual(scores.first?.recipeId, "get-down-low")
    }

    func testMountainVista_isSharpFrontToBack() throws {
        let scores = scorer.score(try fixture("mountain-vista"))
        XCTAssertEqual(scores.first?.recipeId, "sharp-front-to-back")
    }

    func testFaceCloseup_isPortraitPop_notSharpFrontToBack() throws {
        let scores = scorer.score(try fixture("face-closeup-daylight"))
        XCTAssertEqual(scores.first?.recipeId, "portrait-pop")
    }

    func testDogPortrait_isSharpAndInFocus() throws {
        let scores = scorer.score(try fixture("dog-portrait"))
        XCTAssertEqual(scores.first?.recipeId, "sharp-and-in-focus")
    }

    // MARK: - cheatsheet is never auto-selected

    func testCheatsheetNeverScored() throws {
        // Sweep every fixture: the reference card must never appear in scores.
        let expected = try expectedTops()
        for name in expected.keys.sorted() {
            let scores = scorer.score(try fixture(name))
            XCTAssertNil(
                scores.first(where: { $0.recipeId == "exposure-triangle-cheatsheet" }),
                "\(name): cheatsheet must never be a scoring candidate"
            )
        }
        // …but it stays resolvable by id (staged recipe path).
        XCTAssertNotNil(BundledPresets.recipe(id: "exposure-triangle-cheatsheet"))
    }

    // MARK: - decision rule

    func testDecide_lowConfidence_showsAlsoTry() throws {
        let features = try fixture("street-mixed") // ambiguous by construction
        let scores = scorer.score(features)
        let decision = RecipeDecider.decide(scores: scores, features: features, stagedRecipeId: nil)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision?.showAlsoTry == true, "ambiguous scene must offer an Also-try chip")
        XCTAssertNotNil(decision?.runnerUp)
    }

    func testDecide_confident_noAlsoTry() throws {
        let features = try fixture("cyclist-panning")
        let scores = scorer.score(features)
        let decision = RecipeDecider.decide(scores: scores, features: features, stagedRecipeId: nil)
        XCTAssertEqual(decision?.showAlsoTry, false)
        XCTAssertNil(decision?.runnerUp)
    }

    func testDecide_stagedRecipe_skipsScoring() throws {
        let features = try fixture("mountain-vista") // would score sharp-front-to-back
        let scores = scorer.score(features)
        let decision = RecipeDecider.decide(scores: scores, features: features, stagedRecipeId: "blur-moving-subjects")
        XCTAssertEqual(decision?.recipeId, "blur-moving-subjects")
        XCTAssertEqual(decision?.wasStaged, true)
        XCTAssertEqual(decision?.probability, 1.0)
    }

    func testDecide_stagedCheatsheet_resolves() throws {
        let features = try fixture("mountain-vista")
        let scores = scorer.score(features)
        let decision = RecipeDecider.decide(
            scores: scores, features: features, stagedRecipeId: "exposure-triangle-cheatsheet")
        XCTAssertEqual(decision?.recipeId, "exposure-triangle-cheatsheet")
    }

    // MARK: - intent bonus

    func testIntentBonus_explicitIntentWins() throws {
        var features = try fixture("mountain-vista") // strong sharp-front-to-back scene
        features.recipeIntent = RecipeIntent(recipeId: "panning-sharp-subject", matchedPhrase: "pan")
        let scores = scorer.score(features)
        XCTAssertEqual(scores.first?.recipeId, "panning-sharp-subject",
                       "explicit user intent must win unless the scene strongly contradicts it")
    }

    // MARK: - explanations

    func testExplanation_waterfall_mentionsWaterAndBlur() throws {
        let features = try fixture("waterfall-tripod")
        let scores = scorer.score(features)
        let top = try XCTUnwrap(scores.first)
        let reason = RecipeExplainer.reason(recipeId: top.recipeId, features: features, topFeatures: top.topFeatures)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("water"), "reason: \(reason)")
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("blur"), "reason: \(reason)")
        let teach = RecipeExplainer.teachWhy(recipeId: top.recipeId, features: features, topFeatures: top.topFeatures)
        XCTAssertTrue(teach.contains("On-device Pass 1"), "teach: \(teach)")
        XCTAssertFalse(teach.contains("Grok"), "explanations must not mention the cloud path")
    }

    func testExplanation_panning_mentionsPan() throws {
        let features = try fixture("cyclist-panning")
        let scores = scorer.score(features)
        let top = try XCTUnwrap(scores.first)
        let reason = RecipeExplainer.reason(recipeId: top.recipeId, features: features, topFeatures: top.topFeatures)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("pan"), "reason: \(reason)")
    }

    func testSenseSummary_includesMeter() throws {
        let features = try fixture("mountain-vista")
        let summary = RecipeExplainer.senseSummary(features: features)
        XCTAssertTrue(summary.contains("Landscape"), "summary: \(summary)")
        XCTAssertTrue(summary.contains("ISO"), "summary: \(summary)")
    }

    // MARK: - softmax sanity

    func testProbabilities_sumToOne() throws {
        for name in ["mountain-vista", "cyclist-panning", "street-mixed"] {
            let scores = scorer.score(try fixture(name))
            let sum = scores.reduce(0) { $0 + $1.probability }
            XCTAssertEqual(sum, 1.0, accuracy: 0.001, "fixture \(name)")
            XCTAssertEqual(scores.count, SceneFeatures.autoSelectCandidates.count)
        }
    }

    // MARK: - look suggester

    func testLookSuggester_faceDaylight_suggestsWarmGlow() throws {
        let features = try fixture("face-closeup-daylight")
        let suggested = LookSuggester.suggest(features: features)
        XCTAssertEqual(suggested?.look.id, "warmGlow")
        XCTAssertGreaterThanOrEqual(suggested?.confidence ?? 0, LookSuggester.autoApplyThreshold)
    }

    func testLookSuggester_nightStreet_suggestsMoodyFilm() throws {
        let features = try fixture("night-traffic-trails")
        let suggested = LookSuggester.suggest(features: features)
        XCTAssertEqual(suggested?.look.id, "moodyFilm")
    }
}
