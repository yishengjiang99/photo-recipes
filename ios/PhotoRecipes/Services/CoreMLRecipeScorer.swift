import Foundation
import CoreML
import os.log

/// Core ML recipe scorer — the future trained model behind the same
/// `RecipeScoring` protocol as `JSONRecipeScorer`.
///
/// Contract with the training script (`scripts/train-recipe-scorer/`):
/// - Input: one feature per `SceneFeatures.vectorFeatureNames` (45 doubles),
///   in that exact order. New features are appended and bump the schema.
/// - Output: a probability distribution over the auto-select candidates.
/// - The compiled model lives in the app bundle as `RecipeScorer.mlmodelc`
///   (Xcode compiles a bundled `RecipeScorer.mlmodel` automatically).
///
/// No trained model ships yet — until one does, init falls back to nil and
/// `RecipeScorerSelector` keeps the JSON scorer. Nothing here sends pixels
/// anywhere; it scores the numeric feature vector only.
final class CoreMLRecipeScorer: RecipeScoring {
    let candidateIds = SceneFeatures.autoSelectCandidates

    private let model: MLModel?
    private let log = Logger(subsystem: "com.ragnus.mvp", category: "RecipeScorer")

    /// Production init — looks for the compiled model in the app bundle.
    /// Nil model → the selector falls back to `JSONRecipeScorer`.
    init() {
        if let url = Bundle.main.url(forResource: "RecipeScorer", withExtension: "mlmodelc") {
            do {
                self.model = try MLModel(contentsOf: url)
            } catch {
                Logger(subsystem: "com.ragnus.mvp", category: "RecipeScorer")
                    .error("RecipeScorer.mlmodelc failed to load: \(error.localizedDescription, privacy: .public) — falling back to JSON")
                self.model = nil
            }
        } else {
            self.model = nil
        }
    }

    /// Test init — a pre-compiled model URL (e.g. compiled in-test from the
    /// `.mlmodel` in the test bundle via `MLModel.compileModel(at:)`).
    init(modelURL: URL) {
        self.model = try? MLModel(contentsOf: modelURL)
    }

    /// Raw class probabilities over the model's output classes, in
    /// ascending class-label order. Test seam; nil when no model loaded.
    func predictProbabilities(_ vector: [Double]) -> [Double]? {
        guard let model else { return nil }
        guard vector.count == SceneFeatures.vectorFeatureNames.count else {
            log.error("feature vector length \(vector.count) != 45 — model contract broken")
            return nil
        }
        var dict: [String: MLFeatureValue] = [:]
        dict.reserveCapacity(vector.count)
        for (i, v) in vector.enumerated() {
            dict["f\(i)"] = MLFeatureValue(double: v)
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: dict),
              let out = try? model.prediction(from: provider),
              let probs = out.featureValue(for: "classProbability")?.dictionaryValue
        else { return nil }
        // Keys are the class labels (strings); sort for a stable order.
        let sorted = probs.keys.sorted { "\($0)" < "\($1)" }
        return sorted.compactMap { (probs[$0] as? NSNumber)?.doubleValue }
    }

    func score(_ features: SceneFeatures) -> [RecipeScore] {
        let vector = features.featureVector()
        // Map model class labels → candidate recipe ids. A trained model uses
        // the recipe ids as its class labels; unknown labels score zero.
        guard let model,
              let probs = predictProbabilities(vector),
              let classLabels = model.modelDescription.classLabels as? [String],
              classLabels.count == probs.count
        else {
            // No (usable) model — fall back to the hand-tuned JSON scorer.
            return JSONRecipeScorer().score(features)
        }
        var rows: [RecipeScore] = []
        for (label, p) in zip(classLabels, probs) {
            guard candidateIds.contains(label) else { continue }
            rows.append(RecipeScore(recipeId: label, probability: p, topFeatures: []))
        }
        if features.recipeIntent?.recipeId != nil {
            // Keep the intent bonus semantics consistent with the JSON scorer.
            rows = rows.map { row in
                var r = row
                if features.recipeIntent?.recipeId == row.recipeId { r.probability += 0.15 }
                return r
            }
            let sum = max(rows.reduce(0) { $0 + $1.probability }, 1e-9)
            rows = rows.map { var r = $0; r.probability /= sum; return r }
        }
        return rows.sorted { $0.probability > $1.probability }
    }
}

// MARK: - Selector

/// Picks the Pass 1 scorer. JSON v1 is the default; the Core ML model is
/// opt-in via Settings until a trained model ships and proves itself.
enum RecipeScorerSelector {
    static let useCoreMLDefaultsKey = "recipeScorer.useCoreML"

    static var useCoreML: Bool {
        get { UserDefaults.standard.bool(forKey: useCoreMLDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCoreMLDefaultsKey) }
    }

    static func scorer() -> RecipeScoring {
        if useCoreML {
            let ml = CoreMLRecipeScorer()
            // CoreMLRecipeScorer falls back to JSON internally when no model
            // is bundled; still route through it so a future bundled model
            // lights up without an app update to this switch.
            return ml
        }
        return JSONRecipeScorer()
    }
}
