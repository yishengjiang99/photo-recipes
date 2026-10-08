import XCTest
import CoreML
@testable import PhotoRecipes

/// Plumbing test for the future trained Core ML scorer: the tiny dummy
/// model in the test bundle must compile, load, and return five
/// probabilities. This is NOT a trained model — see
/// scripts/dev/generate-dummy-scorer-model.py.
final class CoreMLRecipeScorerTests: XCTestCase {

    private func dummyScorer() throws -> CoreMLRecipeScorer {
        guard let url = Bundle(for: CoreMLRecipeScorerTests.self)
            .url(forResource: "DummyScorer", withExtension: "mlmodel")
        else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "DummyScorer.mlmodel missing from test bundle"])
        }
        // Ship the model in source form; compile on the test host.
        let compiled = try MLModel.compileModel(at: url)
        return CoreMLRecipeScorer(modelURL: compiled)
    }

    func testDummyModel_loadsAndReturnsFiveProbabilities() throws {
        let scorer = try dummyScorer()
        let vector = Array(repeating: 0.5, count: SceneFeatures.vectorFeatureNames.count)
        let probs = try XCTUnwrap(scorer.predictProbabilities(vector))
        XCTAssertEqual(probs.count, 5, "expected five class probabilities, got \(probs.count)")
        XCTAssertEqual(probs.reduce(0, +), 1.0, accuracy: 0.01)
        XCTAssertTrue(probs.allSatisfy { $0 >= 0 && $0 <= 1 }, "probabilities out of range: \(probs)")
    }

    func testDummyModel_differentInputs_differentOutputs() throws {
        let scorer = try dummyScorer()
        let a = try XCTUnwrap(scorer.predictProbabilities(Array(repeating: 0.0, count: 45)))
        let b = try XCTUnwrap(scorer.predictProbabilities(Array(repeating: 1.0, count: 45)))
        XCTAssertNotEqual(a, b, "model should respond to its input")
    }

    func testWrongVectorLength_returnsNil() throws {
        let scorer = try dummyScorer()
        XCTAssertNil(scorer.predictProbabilities(Array(repeating: 0.5, count: 44)))
    }

    func testNoBundledModel_fallsBackToJSONScorer() {
        // No RecipeScorer.mlmodelc in the bundle → predict is nil, score()
        // transparently uses the hand-tuned JSON scorer.
        let scorer = CoreMLRecipeScorer()
        XCTAssertNil(scorer.predictProbabilities(Array(repeating: 0.5, count: 45)))
        var features = SceneFeatures()
        features.sceneEV100 = 13
        features.semanticGroups = [.landscape: 0.9]
        let scores = scorer.score(features)
        XCTAssertEqual(scores.count, SceneFeatures.autoSelectCandidates.count)
        XCTAssertEqual(scores.first?.recipeId, "sharp-front-to-back")
    }
}
