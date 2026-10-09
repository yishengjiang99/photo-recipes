import Foundation
import os.log

// MARK: - Scoring contract

/// One scored recipe: id, calibrated probability, and the feature names that
/// contributed most (used for the explanation text).
struct RecipeScore {
    var recipeId: String
    var probability: Double
    var topFeatures: [String]
}

/// Recipe scoring behind one method. The hand-tuned JSON scorer
/// (`JSONRecipeScorer`) and the future Core ML scorer (`CoreMLRecipeScorer`)
/// both conform, so either can be swapped in.
protocol RecipeScoring {
    /// Scores every auto-select candidate, sorted by probability descending.
    /// `exposure-triangle-cheatsheet` is a reference card and is never a
    /// candidate — it stays resolvable by id (staged recipes) only.
    func score(_ features: SceneFeatures) -> [RecipeScore]
    var candidateIds: [String] { get }
}

// MARK: - Hand-tuned JSON scorer (v1)

/// Interpretable v1: each recipe is a weighted sum over the fixed feature
/// vector, then softmax with a temperature. Weights, temperature and the
/// intent bonus live in `Resources/recipe-scorer-v1.json` (data, not code).
final class JSONRecipeScorer: RecipeScoring {
    struct Model: Decodable {
        var schemaVersion: Int
        var temperature: Double
        var intentBonus: Double
        var featureOrder: [String]
        var recipes: [String: RecipeWeights]
    }

    struct RecipeWeights: Decodable {
        var bias: Double
        var weights: [String: Double]
    }

    let candidateIds = SceneFeatures.autoSelectCandidates

    private let model: Model
    private let featureIndex: [String: Int]
    private let log = Logger(subsystem: "com.ragnus.mvp", category: "RecipeScorer")

    /// Production init — loads the bundled weights.
    init() {
        let loaded = Self.loadModel()
        self.model = loaded
        self.featureIndex = Self.buildIndex(order: loaded.featureOrder)
    }

    /// Test init — inject weights directly.
    init(model: Model) {
        self.model = model
        self.featureIndex = Self.buildIndex(order: model.featureOrder)
    }

    private static func buildIndex(order: [String]) -> [String: Int] {
        if order != SceneFeatures.vectorFeatureNames {
            Logger(subsystem: "com.ragnus.mvp", category: "RecipeScorer")
                .error("recipe-scorer featureOrder does not match SceneFeatures.vectorFeatureNames — Core ML contract broken")
        }
        var idx: [String: Int] = [:]
        for (i, name) in SceneFeatures.vectorFeatureNames.enumerated() { idx[name] = i }
        return idx
    }

    private static func loadModel() -> Model {
        let log = Logger(subsystem: "com.ragnus.mvp", category: "RecipeScorer")
        if let url = Bundle.main.url(forResource: "recipe-scorer-v1", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let model = try? JSONDecoder().decode(Model.self, from: data) {
            return model
        }
        log.error("recipe-scorer-v1.json missing or invalid — falling back to uniform priors")
        return Model(
            schemaVersion: 1,
            temperature: 1.0,
            intentBonus: 4.0,
            featureOrder: SceneFeatures.vectorFeatureNames,
            recipes: Dictionary(
                uniqueKeysWithValues: SceneFeatures.autoSelectCandidates.map {
                    ($0, RecipeWeights(bias: $0 == "sharp-front-to-back" ? 0.2 : -0.5, weights: [:]))
                }
            )
        )
    }

    func score(_ features: SceneFeatures) -> [RecipeScore] {
        let x = features.featureVector()
        // Phase 2: Vision scene labels contribute alongside the typed note.
        // Label boosts are capped at 1.0 < intentBonus 4.0, so an explicit
        // note always wins over label evidence.
        let labelEvidence = SceneLabelRecipeMapper.boosts(
            labels: features.sceneLabels ?? [], features: features)
        var rows: [(id: String, logit: Double, top: [String])] = []
        for id in candidateIds {
            guard let rw = model.recipes[id] else { continue }
            var z = rw.bias
            var contribs: [(String, Double)] = []
            contribs.reserveCapacity(rw.weights.count)
            for (name, w) in rw.weights {
                guard let i = featureIndex[name], i < x.count else { continue }
                let c = w * x[i]
                z += c
                contribs.append((name, c))
            }
            if features.recipeIntent?.recipeId == id {
                z += model.intentBonus
            }
            if let lb = labelEvidence.boosts[id] {
                z += lb
            }
            var top = contribs
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map { $0.0 }
            top += labelEvidence.phrases[id] ?? []
            rows.append((id, z, top))
        }
        let temperature = max(model.temperature, 0.05)
        let maxLogit = rows.map { $0.logit }.max() ?? 0
        let exps = rows.map { exp(($0.logit - maxLogit) / temperature) }
        let sum = max(exps.reduce(0, +), 1e-9)
        let scored = zip(rows, exps)
            .map { RecipeScore(recipeId: $0.0.id, probability: $0.1 / sum, topFeatures: $0.0.top) }
            .sorted { $0.probability > $1.probability }
        return SelfieRecipeBias.apply(scored, features: features)
    }
}

// MARK: - Selfie bias (front camera)

/// Front camera = selfie. Drops recipes that make no sense at arm's length
/// and favours `portrait-pop` when a face is in frame. A typed-note intent
/// always survives; staged recipes bypass scoring entirely (RecipeDecider).
enum SelfieRecipeBias {
    /// Never auto-selected on the front camera.
    static let excluded: Set<String> = [
        "sharp-front-to-back", "get-down-low",
        "panning-sharp-subject", "blur-moving-subjects",
    ]
    /// Probability multiplier for `portrait-pop` when a face is detected.
    static let faceBoost = 4.0

    static func apply(_ scores: [RecipeScore], features: SceneFeatures) -> [RecipeScore] {
        guard features.isFrontCamera else { return scores }
        let intentId = features.recipeIntent?.recipeId
        var rows = scores.filter { !excluded.contains($0.recipeId) || $0.recipeId == intentId }
        guard !rows.isEmpty else { return scores }
        let hasFace = features.subjectKind == .face || (features.faceCount ?? 0) > 0
        if hasFace, intentId == nil {
            rows = rows.map { row in
                var r = row
                if r.recipeId == "portrait-pop" { r.probability *= faceBoost }
                return r
            }
        }
        let sum = max(rows.reduce(0) { $0 + $1.probability }, 1e-9)
        return rows
            .map { var r = $0; r.probability /= sum; return r }
            .sorted { $0.probability > $1.probability }
    }
}

// MARK: - Scene-label → recipe boosts (Phase 2)

/// Maps raw Vision classification labels (`SceneFeatures.sceneLabels`) to
/// additive recipe boosts, used alongside the typed-note intent.
///
/// Examples: waterfall/fireworks → blur-moving-subjects (long-exposure
/// subjects); sunset/sunrise + clipped highlights → hdr-brights-darks
/// (bracket the range). Food → the warmPop *look* is already handled by
/// `LookSuggester` — no recipe boost needed there.
///
/// The user's explicit note intent always wins: boosts are capped at 1.0,
/// well below the intent bonus (3.0) in `JSONRecipeScorer`.
enum SceneLabelRecipeMapper {
    static let maxBoost = 1.0
    /// Minimum label confidence to count as evidence.
    static let minConfidence: Float = 0.3

    /// Returns recipe id → boost, plus the label phrases that fired (as
    /// synthetic `label.*` feature names for the explanation copy).
    static func boosts(
        labels: [SceneLabel],
        features: SceneFeatures
    ) -> (boosts: [String: Double], phrases: [String: [String]]) {
        var boosts: [String: Double] = [:]
        var phrases: [String: [String]] = [:]
        func add(_ recipeId: String, _ amount: Double, phrase: String) {
            boosts[recipeId] = min((boosts[recipeId] ?? 0) + amount, maxBoost)
            phrases[recipeId, default: []].append(phrase)
        }
        for label in labels where label.confidence >= minConfidence {
            let id = label.identifier.lowercased()
            if id.contains("waterfall") || id.contains("fireworks") {
                add("blur-moving-subjects", 0.8,
                    phrase: id.contains("waterfall") ? "label.waterfall" : "label.fireworks")
            }
            if id.contains("sunset") || id.contains("sunrise"),
               features.highlightClipFraction > 0.02 {
                add("hdr-brights-darks", 1.0, phrase: "label.sunset")
            }
        }
        return (boosts, phrases)
    }
}

// MARK: - Decision

/// The scored outcome Auto Optimize acts on.
struct RecipeDecision {
    var recipeId: String
    var recipeTitle: String
    /// All candidate scores, sorted descending.
    var scores: [RecipeScore]
    var probability: Double
    var runnerUp: RecipeScore?
    /// Show the runner-up as an "Also try" chip (one-tap switch).
    var showAlsoTry: Bool
    var reason: String
    var teachWhy: String
    var senseSummary: String
    var wasStaged: Bool
}

enum RecipeDecider {
    /// Applies the decision rule:
    /// - staged recipe (`preferStagedRecipeId`) skips scoring entirely (as today);
    /// - otherwise the top recipe wins; when its probability < 0.55 or the
    ///   margin over second place < 0.15, the runner-up is offered as "Also try".
    static func decide(
        scores: [RecipeScore],
        features: SceneFeatures,
        stagedRecipeId: String?
    ) -> RecipeDecision? {
        if let staged = stagedRecipeId.flatMap({ BundledPresets.recipe(id: $0) }) {
            let topFeatures = scores.first(where: { $0.recipeId == staged.id })?.topFeatures ?? []
            return RecipeDecision(
                recipeId: staged.id,
                recipeTitle: staged.title,
                scores: scores,
                probability: 1.0,
                runnerUp: nil,
                showAlsoTry: false,
                reason: RecipeExplainer.reason(recipeId: staged.id, features: features, topFeatures: topFeatures),
                teachWhy: RecipeExplainer.teachWhy(recipeId: staged.id, features: features, topFeatures: topFeatures),
                senseSummary: RecipeExplainer.senseSummary(features: features),
                wasStaged: true
            )
        }
        guard let top = scores.first else { return nil }
        let second = scores.dropFirst().first
        let margin = top.probability - (second?.probability ?? 0)
        let showAlsoTry = top.probability < 0.55 || margin < 0.15
        let title = BundledPresets.recipe(id: top.recipeId)?.title ?? top.recipeId
        return RecipeDecision(
            recipeId: top.recipeId,
            recipeTitle: title,
            scores: scores,
            probability: top.probability,
            runnerUp: showAlsoTry ? second : nil,
            showAlsoTry: showAlsoTry && second != nil,
            reason: RecipeExplainer.reason(recipeId: top.recipeId, features: features, topFeatures: top.topFeatures),
            teachWhy: RecipeExplainer.teachWhy(recipeId: top.recipeId, features: features, topFeatures: top.topFeatures),
            senseSummary: RecipeExplainer.senseSummary(features: features),
            wasStaged: false
        )
    }
}

// MARK: - Explanations from contributing features

/// Builds `reason` / `teachWhy` / `senseSummary` from the top contributing
/// features instead of hard-coded copy.
enum RecipeExplainer {
    /// feature name -> human phrase. Dynamic features (light level, shake)
    /// are resolved by `phrase(for:value:)`.
    private static let phrases: [String: String] = [
        "sem.person": "a person in frame",
        "sem.animal": "an animal subject",
        "sem.vehicle": "a vehicle",
        "sem.bicycleOrSport": "fast action",
        "sem.water": "moving water",
        "sem.food": "food",
        "sem.landscape": "a deep landscape",
        "sem.sky": "open sky",
        "sem.sunsetOrSunrise": "sunset light",
        "sem.nightOrLights": "night lights",
        "sem.architecture": "strong architecture",
        "sem.plantOrFlower": "a low plant",
        "sem.indoor": "an indoor scene",
        "subject.present": "a clear subject",
        "subject.kind.face": "a face in frame",
        "subject.kind.human": "a person",
        "subject.kind.animal": "an animal",
        "subject.kind.salientObject": "a clear subject",
        "subject.areaFraction": "a close subject",
        "subject.centerY": "subject low in the frame",
        "motion.logSubjectSpeed": "subject motion",
        "motion.logBackgroundSpeed": "camera motion",
        "motion.logRelativeSpeed": "the subject moving against the background",
        "motion.panMatchesSubject": "your pan matching the subject",
        "light.highlightClip": "clipped highlights",
        "light.shadowCrush": "crushed shadows",
        "light.spreadStopsN": "wide dynamic range",
        "light.subjectDeltaStopsN": "a backlit subject",
        "light.warmBias": "warm light",
        "pose.elevationN": "camera tilted up",
        // Phase 2 label evidence (synthetic names from SceneLabelRecipeMapper).
        "label.waterfall": "a waterfall",
        "label.fireworks": "fireworks",
        "label.sunset": "sunset light",
    ]

    private static let actions: [String: String] = [
        "sharp-front-to-back": "deep focus for front-to-back sharpness",
        "blur-moving-subjects": "slow shutter for silky blur",
        "panning-sharp-subject": "pan with the subject so the background streaks",
        "get-down-low": "drop to knee height with the ultra-wide",
        "hdr-brights-darks": "bracket the brights and darks",
        "portrait-pop": "eye focus with a soft background",
        "sharp-and-in-focus": "single-point focus locked on the subject",
        "leading-lines": "deep focus with the subject on a line",
        "minimalist-photos": "moody exposure on one subject",
        "exposure-triangle-cheatsheet": "reference card — no camera changes",
    ]

    private static let teachTips: [String: String] = [
        "sharp-front-to-back": "Focus about a third into the frame, then lock — the hyperfocal shortcut.",
        "blur-moving-subjects": "Brace the phone or use a tripod: the static world must stay sharp while motion blurs.",
        "panning-sharp-subject": "Rotate your body at the subject's speed; review and nudge the shutter faster or slower.",
        "get-down-low": "Flip the phone upside down so the lens is closest to the ground.",
        "hdr-brights-darks": "Keep the phone still across the bracket; merge naturally in post.",
        "portrait-pop": "Focus landed on the eyes; use Portrait mode for real optical blur.",
        "sharp-and-in-focus": "Tap the screen if it picked the wrong element — you are smarter than the camera.",
        "leading-lines": "Place the subject where a line meets a third line.",
        "minimalist-photos": "One subject, one message — reframe until only one thing stands out.",
        "exposure-triangle-cheatsheet": "Aperture, ISO, shutter speed: change one, compensate with another.",
    ]

    static func reason(recipeId: String, features: SceneFeatures, topFeatures: [String]) -> String {
        let action = actions[recipeId] ?? "balanced exposure"
        var contributors = topFeatures.compactMap { phrase(for: $0, value: features) }
        if contributors.isEmpty {
            // Fall back to the strongest measured signals.
            contributors = fallbackContributors(features: features)
        }
        let lead = contributors.prefix(2).joined(separator: " and ")
        return "\(cap(lead)) → \(action)."
    }

    static func teachWhy(recipeId: String, features: SceneFeatures, topFeatures: [String]) -> String {
        let title = BundledPresets.recipe(id: recipeId)?.title ?? recipeId
        let contributors = topFeatures.compactMap { phrase(for: $0, value: features) }
        let detail = contributors.isEmpty
            ? "measured light, motion and subject on device"
            : contributors.prefix(3).joined(separator: ", ")
        let tip = teachTips[recipeId] ?? ""
        return "On-device Pass 1 chose \(title) from \(detail) — no cloud involved. \(tip)"
            .trimmingCharacters(in: .whitespaces)
    }

    static func senseSummary(features: SceneFeatures) -> String {
        var summary = SceneChipText.make(features: features)
        if let t = features.meteredExposureSeconds, let iso = features.meteredISO {
            summary += String(format: " · meter %@ · ISO %.0f", RecipeCameraMapper.formatShutter(t), iso)
        }
        return summary
    }

    /// Dynamic phrases for value-dependent features; static table otherwise.
    /// Synthetic `label.*` names resolve straight from the table.
    private static func phrase(for feature: String, value features: SceneFeatures) -> String? {
        if feature.hasPrefix("label.") { return phrases[feature] }
        let x = features.featureVector()
        guard let i = SceneFeatures.vectorFeatureNames.firstIndex(of: feature) else { return nil }
        let v = x[i]
        switch feature {
        case "light.ev100n":
            if v < 0.25 { return "low light" }
            if v > 0.75 { return "bright light" }
            return nil
        case "pose.shakeLog":
            return v < 0.2 ? "a steady camera" : "visible hand shake"
        case "pose.elevationN":
            return v > 0.15 ? "camera tilted up" : nil
        case "motion.logSubjectSpeed":
            return v > 0.3 ? phrases[feature] : nil
        default:
            return phrases[feature]
        }
    }

    private static func fallbackContributors(features: SceneFeatures) -> [String] {
        var out: [String] = []
        if let top = features.semanticGroups.max(by: { $0.value < $1.value }), top.value >= 0.35,
           let phrase = phrases["sem.\(top.key.rawValue)"] {
            out.append(phrase)
        }
        if let ev = features.sceneEV100 {
            out.append(ev < 7 ? "low light" : ev >= 13 ? "bright light" : "soft light")
        }
        if features.subjectRelativeSpeedPxPerSec > 250 { out.append("subject motion") }
        return out.isEmpty ? ["the measured scene"] : out
    }

    private static func cap(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}

// MARK: - Look suggestion (ported from the v1 heuristic scorer)

/// Suggests a Creative Look with a confidence. ≥ `autoApplyThreshold` the
/// controller auto-applies it; below that it becomes an Apply/Dismiss chip.
/// Same behavior contract as the previous heuristic scorer.
enum LookSuggester {
    static let autoApplyThreshold = 0.6

    static func suggest(features: SceneFeatures) -> (look: CreativeLook, confidence: Double)? {
        let groups = features.semanticGroups
        let night = (groups[.nightOrLights] ?? 0) >= 0.5
        let ev = features.sceneEV100
        let dark = (ev ?? 99) < 7
        let veryDark = (ev ?? 99) < 3
        let hasFace = features.subjectKind == .face
        let warm = features.warmBias
        let landscape = (groups[.landscape] ?? 0) >= 0.5
        let food = (groups[.food] ?? 0) >= 0.5
        let spread = features.percentileSpreadStops

        // Night / very dark → moody film (or coolBlue if cool cast).
        if night || veryDark {
            let conf = night ? 0.8 : 0.65
            if warm < -0.05 {
                return (CreativeLook(id: "coolBlue", intensity: 0.5), conf)
            }
            return (CreativeLook(id: "moodyFilm", intensity: CreativeLookCatalog.defaultIntensity), conf)
        }

        // Faces → warmGlow (skin-friendly), not goldenHour.
        if hasFace {
            if warm < -0.08 {
                return (CreativeLook(id: "crispCool", intensity: 0.45), 0.7)
            }
            return (CreativeLook(id: "warmGlow", intensity: 0.45), 0.75)
        }

        // Explicit cool / overcast steel.
        if warm < -0.1 && spread > 4 {
            return (CreativeLook(id: "crispCool", intensity: CreativeLookCatalog.defaultIntensity), 0.6)
        }

        // Landscape / deep scene → tealOrange cinematic, not golden by default.
        if landscape {
            if warm > 0.18, let ev, ev > 9, ev < 14 {
                return (CreativeLook(id: "goldenHour", intensity: 0.5), 0.7)
            }
            return (CreativeLook(id: "tealOrange", intensity: 0.5), 0.5)
        }

        // Food / color pop cues.
        if food {
            return (CreativeLook(id: "warmPop", intensity: 0.5), 0.7)
        }

        // High contrast daylight → blockbuster, suggest only.
        if spread > 7 && !dark {
            return (CreativeLook(id: "blockbuster", intensity: 0.5), 0.45)
        }

        // True golden hour: strong warm bias + mid light, no faces.
        if warm > 0.18, let ev, ev > 8.5, ev < 12 {
            return (CreativeLook(id: "goldenHour", intensity: CreativeLookCatalog.defaultIntensity), 0.62)
        }

        // Mild warm daylight → warmPop suggestion only.
        if warm > 0.08 && !dark {
            return (CreativeLook(id: "warmPop", intensity: 0.45), 0.4)
        }

        return nil
    }
}
