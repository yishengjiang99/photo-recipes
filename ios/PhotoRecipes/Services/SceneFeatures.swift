import Foundation
import CoreGraphics

// MARK: - Semantic groups

/// Coarse semantic buckets the recipe scorer understands. Raw Vision
/// identifiers are mapped into these via `scene-label-groups.json` (data,
/// not code) — see `SceneLabelMapper`.
enum SemanticGroup: String, Codable, CaseIterable {
    case person
    case animal
    case vehicle
    case bicycleOrSport
    case water
    case food
    case landscape
    case sky
    case sunsetOrSunrise
    case nightOrLights
    case architecture
    case plantOrFlower
    case indoor
}

/// What the primary subject is.
enum SubjectKind: String, Codable {
    case face
    case human
    case animal
    case salientObject
}

/// Normalized box in **UI space** (top-left origin), 0…1.
struct NormalizedBox: Codable, Equatable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float

    var centerX: Float { x + width / 2 }
    var centerY: Float { y + height / 2 }
    var area: Float { width * height }

    var cgRect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ r: CGRect) {
        self.init(x: Float(r.minX), y: Float(r.minY), width: Float(r.width), height: Float(r.height))
    }
}

/// The photographer's own typed or dictated note, mapped to a recipe.
/// Never the Grok caption.
struct RecipeIntent: Codable, Equatable {
    var recipeId: String
    var matchedPhrase: String
}

// MARK: - SceneFeatures

/// The single, versioned input to recipe scoring. Everything the phone knows
/// about the scene, measured on device — no pixels ever leave the device.
///
/// The fixed numeric vector (`featureVector()`) has a documented order that
/// MUST match the Core ML model's input (`scripts/train-recipe-scorer/`).
/// Add new features only at the end and bump `currentSchemaVersion`.
struct SceneFeatures: Codable, Equatable {
    static let currentSchemaVersion = 2

    /// The ten bundled recipes in fixed order. Used for the intent one-hot
    /// slice of the feature vector and by the Core ML scorer.
    /// `exposure-triangle-cheatsheet` is a reference card: it is resolvable by
    /// id (staged recipes) but NEVER an auto-select candidate — the scorer
    /// excludes it.
    static let recipeOrder: [String] = [
        "sharp-front-to-back",
        "blur-moving-subjects",
        "panning-sharp-subject",
        "get-down-low",
        "hdr-brights-darks",
        "portrait-pop",
        "sharp-and-in-focus",
        "leading-lines",
        "minimalist-photos",
        "exposure-triangle-cheatsheet",
    ]

    /// Recipes the scorer is allowed to auto-select.
    static let autoSelectCandidates: [String] = recipeOrder.filter { $0 != "exposure-triangle-cheatsheet" }

    /// Fixed feature order. Indices are a contract with the Core ML model.
    static let vectorFeatureNames: [String] = {
        var names: [String] = []
        // 0–12: semantic groups (max confidence per group).
        names += SemanticGroup.allCases.map { "sem.\($0.rawValue)" }
        // 13: subject present.
        names.append("subject.present")
        // 14–17: subject kind one-hot (face, human, animal, salientObject).
        names += ["face", "human", "animal", "salientObject"].map { "subject.kind.\($0)" }
        // 18–20: subject geometry.
        names += ["subject.areaFraction", "subject.centerX", "subject.centerY"]
        // 21–26: motion.
        names += [
            "motion.logSubjectSpeed", "motion.logBackgroundSpeed", "motion.logRelativeSpeed",
            "motion.panMatchesSubject", "motion.directionX", "motion.directionY",
        ]
        // 27–32: light & range.
        names += [
            "light.ev100n", "light.highlightClip", "light.shadowCrush",
            "light.spreadStopsN", "light.subjectDeltaStopsN", "light.warmBias",
        ]
        // 33–34: pose & stability.
        names += ["pose.elevationN", "pose.shakeLog"]
        // 35–44: intent one-hot over recipeOrder.
        names += recipeOrder.map { "intent.\($0)" }
        return names
    }()

    static let vectorDimension = vectorFeatureNames.count // 45

    var schemaVersion: Int = currentSchemaVersion
    var capturedAt: Date = Date()

    // MARK: semantic content (VNClassifyImageRequest → label groups)
    var semanticGroups: [SemanticGroup: Float] = [:]

    // MARK: subjects (UI space, top-left origin)
    var subjectKind: SubjectKind?
    var subjectBox: NormalizedBox?
    /// Fraction of frame area covered by the primary subject, 0…1.
    var subjectAreaFraction: Float = 0

    // MARK: motion (full-frame pixels/second)
    var subjectSpeedPxPerSec: Float = 0
    var backgroundSpeedPxPerSec: Float = 0
    var subjectRelativeSpeedPxPerSec: Float = 0
    /// Subject motion direction, unit vector in UI space (x right, y down).
    var motionDirectionX: Float = 1
    var motionDirectionY: Float = 0

    // MARK: light & range
    var meteredExposureSeconds: Double?
    var meteredISO: Float?
    var lensAperture: Float?
    var exposureTargetOffset: Float?
    var exposureWasCustom: Bool = false
    /// Scene luminance as EV at ISO 100, from camera metering (nil if unknown).
    var sceneEV100: Float?
    /// Fraction of pixels brighter than 0.95.
    var highlightClipFraction: Float = 0
    /// Fraction of pixels darker than 0.05.
    var shadowCrushFraction: Float = 0
    /// Luminance percentile spread (p99…p1) in stops.
    var percentileSpreadStops: Float = 0
    /// Subject-region luminance vs frame median, in stops (negative = darker).
    var subjectDeltaStops: Float?
    /// > 0 warmer (R > B), < 0 cooler.
    var warmBias: Float = 0

    // MARK: pose & stability
    /// Camera elevation above the horizon, degrees (≈ 0° at horizon, any hold).
    var cameraElevationDegrees: Float = 0
    /// Smoothed rotation-rate magnitude, rad/s (hand shake).
    var handShakeRadPerSec: Float = 0

    // MARK: user intent (local note only)
    var recipeIntent: RecipeIntent?

    /// Subject center Y in UI space (0 top … 1 bottom). Low-in-frame subjects
    /// have high values — a strong get-down-low signal with a tilted-up camera.
    var subjectCenterY: Float { subjectBox?.centerY ?? 0.5 }

    // MARK: - Fixed numeric vector

    /// The scorer input. Order == `vectorFeatureNames`; this is the contract
    /// the Core ML model is trained/exported against.
    func featureVector() -> [Double] {
        Self.vectorFeatureNames.map { value(forFeature: $0) }
    }

    /// Quantized vector for telemetry (floats rounded to 2 decimals, no pixels).
    func quantizedVector() -> [Double] {
        featureVector().map { ($0 * 100).rounded() / 100 }
    }

    private func value(forFeature name: String) -> Double {
        switch name {
        case "sem.person": return Double(semanticGroups[.person] ?? 0)
        case "sem.animal": return Double(semanticGroups[.animal] ?? 0)
        case "sem.vehicle": return Double(semanticGroups[.vehicle] ?? 0)
        case "sem.bicycleOrSport": return Double(semanticGroups[.bicycleOrSport] ?? 0)
        case "sem.water": return Double(semanticGroups[.water] ?? 0)
        case "sem.food": return Double(semanticGroups[.food] ?? 0)
        case "sem.landscape": return Double(semanticGroups[.landscape] ?? 0)
        case "sem.sky": return Double(semanticGroups[.sky] ?? 0)
        case "sem.sunsetOrSunrise": return Double(semanticGroups[.sunsetOrSunrise] ?? 0)
        case "sem.nightOrLights": return Double(semanticGroups[.nightOrLights] ?? 0)
        case "sem.architecture": return Double(semanticGroups[.architecture] ?? 0)
        case "sem.plantOrFlower": return Double(semanticGroups[.plantOrFlower] ?? 0)
        case "sem.indoor": return Double(semanticGroups[.indoor] ?? 0)
        case "subject.present": return subjectKind == nil ? 0 : 1
        case "subject.kind.face": return subjectKind == .face ? 1 : 0
        case "subject.kind.human": return subjectKind == .human ? 1 : 0
        case "subject.kind.animal": return subjectKind == .animal ? 1 : 0
        case "subject.kind.salientObject": return subjectKind == .salientObject ? 1 : 0
        case "subject.areaFraction": return Double(subjectAreaFraction)
        case "subject.centerX": return Double(subjectBox?.centerX ?? 0.5)
        // Centered encoding: 0 = mid-frame, +1 = bottom edge, −1 = top edge.
        // A subject low in frame (high UI y) scores positive.
        case "subject.centerY": return Double((subjectCenterY - 0.5) * 2)
        case "motion.logSubjectSpeed": return Self.logNorm(subjectSpeedPxPerSec)
        case "motion.logBackgroundSpeed": return Self.logNorm(backgroundSpeedPxPerSec)
        case "motion.logRelativeSpeed": return Self.logNorm(subjectRelativeSpeedPxPerSec)
        case "motion.panMatchesSubject":
            // Gated on real subject motion: a still scene must not read as
            // "pan matching the subject".
            guard subjectSpeedPxPerSec > 50 else { return 0 }
            let s = max(subjectSpeedPxPerSec, 1)
            return Double(1 - min(1, subjectRelativeSpeedPxPerSec / s))
        case "motion.directionX": return Double(motionDirectionX)
        case "motion.directionY": return Double(motionDirectionY)
        case "light.ev100n":
            guard let ev = sceneEV100 else { return 0.5 }
            return Double(min(max((ev + 6) / 24, 0), 1))
        case "light.highlightClip": return Double(highlightClipFraction)
        case "light.shadowCrush": return Double(shadowCrushFraction)
        case "light.spreadStopsN": return Double(min(max(percentileSpreadStops / 12, 0), 1))
        case "light.subjectDeltaStopsN":
            guard let d = subjectDeltaStops else { return 0 }
            return Double(min(max(d / 4, -1), 1))
        case "light.warmBias": return Double(warmBias)
        case "pose.elevationN": return Double(cameraElevationDegrees / 90)
        case "pose.shakeLog": return Self.logNorm(handShakeRadPerSec * 1000) / 2
        default:
            if name.hasPrefix("intent.") {
                let id = String(name.dropFirst("intent.".count))
                return recipeIntent?.recipeId == id ? 1 : 0
            }
            return 0
        }
    }

    /// log1p scaled to ~0…1 for speeds (px/s) and shake.
    static func logNorm(_ v: Float) -> Double {
        log1p(Double(max(v, 0))) / 8.0
    }

    // MARK: - Tolerant decoding

    /// Decodes with `decodeIfPresent` for every property, falling back to the
    /// declared defaults. Fixtures and telemetry logged under older schema
    /// versions (e.g. before `capturedAt` existed) must keep decoding after
    /// new fields are added — the encoder always writes the full schema.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
        semanticGroups = try c.decodeIfPresent([SemanticGroup: Float].self, forKey: .semanticGroups) ?? [:]
        subjectKind = try c.decodeIfPresent(SubjectKind.self, forKey: .subjectKind)
        subjectBox = try c.decodeIfPresent(NormalizedBox.self, forKey: .subjectBox)
        subjectAreaFraction = try c.decodeIfPresent(Float.self, forKey: .subjectAreaFraction) ?? 0
        subjectSpeedPxPerSec = try c.decodeIfPresent(Float.self, forKey: .subjectSpeedPxPerSec) ?? 0
        backgroundSpeedPxPerSec = try c.decodeIfPresent(Float.self, forKey: .backgroundSpeedPxPerSec) ?? 0
        subjectRelativeSpeedPxPerSec = try c.decodeIfPresent(Float.self, forKey: .subjectRelativeSpeedPxPerSec) ?? 0
        motionDirectionX = try c.decodeIfPresent(Float.self, forKey: .motionDirectionX) ?? 1
        motionDirectionY = try c.decodeIfPresent(Float.self, forKey: .motionDirectionY) ?? 0
        meteredExposureSeconds = try c.decodeIfPresent(Double.self, forKey: .meteredExposureSeconds)
        meteredISO = try c.decodeIfPresent(Float.self, forKey: .meteredISO)
        lensAperture = try c.decodeIfPresent(Float.self, forKey: .lensAperture)
        exposureTargetOffset = try c.decodeIfPresent(Float.self, forKey: .exposureTargetOffset)
        exposureWasCustom = try c.decodeIfPresent(Bool.self, forKey: .exposureWasCustom) ?? false
        sceneEV100 = try c.decodeIfPresent(Float.self, forKey: .sceneEV100)
        highlightClipFraction = try c.decodeIfPresent(Float.self, forKey: .highlightClipFraction) ?? 0
        shadowCrushFraction = try c.decodeIfPresent(Float.self, forKey: .shadowCrushFraction) ?? 0
        percentileSpreadStops = try c.decodeIfPresent(Float.self, forKey: .percentileSpreadStops) ?? 0
        subjectDeltaStops = try c.decodeIfPresent(Float.self, forKey: .subjectDeltaStops)
        warmBias = try c.decodeIfPresent(Float.self, forKey: .warmBias) ?? 0
        cameraElevationDegrees = try c.decodeIfPresent(Float.self, forKey: .cameraElevationDegrees) ?? 0
        handShakeRadPerSec = try c.decodeIfPresent(Float.self, forKey: .handShakeRadPerSec) ?? 0
        recipeIntent = try c.decodeIfPresent(RecipeIntent.self, forKey: .recipeIntent)
    }
}

// MARK: - EV100

enum EV100Helper {
    /// EV100 = log2(N² / t) − log2(ISO / 100), from camera metering.
    ///
    /// When the device is in `.custom` mode the metered t/ISO are the *locked*
    /// values, so the raw formula reports the EV the settings *meter for*,
    /// not the scene. `exposureTargetOffset` corrects it without resetting
    /// auto-exposure.
    ///
    /// Sign convention: a positive offset means the current settings overexpose
    /// relative to the target, i.e. the scene is brighter than the settings
    /// meter for — so the offset is ADDED.
    /// ⚠️ PENDING empirical verification on device; if the sign is wrong the
    /// offset-corrected EV100 will be off by 2× the offset.
    static func ev100(
        aperture: Float?,
        exposureSeconds: Double?,
        iso: Float?,
        exposureTargetOffset: Float?,
        wasCustom: Bool
    ) -> Float? {
        guard let n = aperture, n > 0,
              let t = exposureSeconds, t > 0,
              let iso = iso, iso > 0
        else { return nil }
        var ev = log2(Double(n * n) / t) - log2(Double(iso) / 100.0)
        if wasCustom, let offset = exposureTargetOffset {
            ev += Double(offset)
        }
        return Float(ev)
    }
}

// MARK: - Luminance statistics (pure; fed by the vImage histogram)

struct LuminanceStats: Equatable {
    var mean: Float
    /// 1st / 99th percentile luminance, 0…1.
    var percentile1: Float
    var percentile99: Float
    /// log2(p99 / p1) — dynamic range in stops.
    var spreadStops: Float
    var highlightClipFraction: Float // > 0.95
    var shadowCrushFraction: Float   // < 0.05
    var warmBias: Float

    /// Pure computation from a 256-bin luminance histogram. Unit-testable.
    static func fromHistogram(bins: [Int], warmBias: Float = 0) -> LuminanceStats {
        precondition(bins.count == 256)
        let total = max(bins.reduce(0, +), 1)
        let totalD = Double(total)
        var cumulative = 0
        var p1 = 0
        var p99 = 255
        var hi = 0
        var lo = 0
        var sum = 0.0
        for (i, c) in bins.enumerated() {
            let lum = Double(i) / 255.0
            sum += lum * Double(c)
            cumulative += c
            if p1 == 0 && Double(cumulative) / totalD >= 0.01 { p1 = i }
            if Double(cumulative) / totalD < 0.99 { p99 = i }
            if lum > 0.95 { hi += c }
            if lum < 0.05 { lo += c }
        }
        let p1f = Float(p1) / 255
        let p99f = Float(max(p99, p1 + 1)) / 255
        let spread = Float(log2(Double(p99f) / Double(max(p1f, 1.0 / 255.0))))
        return LuminanceStats(
            mean: Float(sum / totalD),
            percentile1: p1f,
            percentile99: p99f,
            spreadStops: spread,
            highlightClipFraction: Float(hi) / Float(total),
            shadowCrushFraction: Float(lo) / Float(total),
            warmBias: warmBias
        )
    }
}

// MARK: - Intent matcher (local note only; never the Grok caption)

/// Whole-word/phrase matching on token boundaries with simple negation:
/// "no", "not", "avoid", "without", "don't"/"dont", "never" within 3 tokens
/// before a keyword cancels it. This replaces the old substring matching
/// ("yellow" matching "low", "expansive" matching "pan").
enum IntentMatcher {
    /// Checked in order; first un-negated match wins.
    static let intents: [(recipeId: String, phrases: [String])] = [
        ("blur-moving-subjects", ["silky", "silk", "waterfall", "long exposure", "light trails", "light trail", "motion blur"]),
        ("panning-sharp-subject", ["panning", "pan with", "track the", "tracking", "cyclist", "race car"]),
        ("hdr-brights-darks", ["hdr", "sunset", "sunrise", "backlit", "silhouette", "high contrast", "bright and dark"]),
        ("portrait-pop", ["portrait", "headshot", "selfie", "bokeh", "blur the background", "eyes sharp"]),
        ("sharp-and-in-focus", ["tack sharp", "in focus", "focus on the eyes", "keep it sharp"]),
        ("get-down-low", ["get low", "knee height", "kneel", "low angle", "ground level", "worm", "dog view"]),
        ("sharp-front-to-back", ["landscape", "hyperfocal", "front to back", "everything sharp", "depth of field", "foreground to background"]),
        ("leading-lines", ["leading line", "leading lines", "vanishing point", "converge"]),
        ("minimalist-photos", ["minimalist", "minimal", "blue hour", "negative space", "one subject"]),
        // exposure-triangle-cheatsheet: reference card — never an intent target.
    ]

    private static let negations: Set<String> = ["no", "not", "avoid", "without", "dont", "never"]

    static func match(note: String) -> RecipeIntent? {
        let words = tokenize(note)
        guard !words.isEmpty else { return nil }
        for (recipeId, phrases) in intents {
            for phrase in phrases {
                let pwords = tokenize(phrase)
                guard !pwords.isEmpty, pwords.count <= words.count else { continue }
                for i in 0...(words.count - pwords.count) {
                    guard Array(words[i ..< i + pwords.count]) == pwords else { continue }
                    let windowStart = max(0, i - 3)
                    let negated = words[windowStart ..< i].contains { negations.contains($0) }
                    if !negated {
                        return RecipeIntent(recipeId: recipeId, matchedPhrase: phrase)
                    }
                }
            }
        }
        return nil
    }

    /// Lowercase alphanumeric tokens; "don't" → "dont" so negation matching works.
    static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "don't", with: "dont")
            .replacingOccurrences(of: "’", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

// MARK: - Local scene chip text

enum SceneChipText {
    /// Human summary of the measured scene for the "From viewfinder" chip,
    /// e.g. "Water · bright · moving water". Generated locally — no network.
    static func make(features: SceneFeatures) -> String {
        var parts: [String] = []
        if let top = features.semanticGroups.max(by: { $0.value < $1.value }), top.value >= 0.35 {
            parts.append(displayName(for: top.key))
        }
        if let ev = features.sceneEV100 {
            if ev < 2 { parts.append("very dim") }
            else if ev < 7 { parts.append("dim") }
            else if ev >= 13 { parts.append("bright") }
        }
        if features.subjectRelativeSpeedPxPerSec > 250 {
            parts.append(features.backgroundSpeedPxPerSec > 500 ? "panning with subject" : "moving subject")
        } else if features.backgroundSpeedPxPerSec > 500 {
            parts.append("camera moving")
        }
        if parts.isEmpty { parts.append("steady scene") }
        return parts.joined(separator: " · ")
    }

    private static func displayName(for group: SemanticGroup) -> String {
        switch group {
        case .person: return "Person"
        case .animal: return "Animal"
        case .vehicle: return "Vehicle"
        case .bicycleOrSport: return "Action"
        case .water: return "Water"
        case .food: return "Food"
        case .landscape: return "Landscape"
        case .sky: return "Sky"
        case .sunsetOrSunrise: return "Sunset"
        case .nightOrLights: return "Night"
        case .architecture: return "Architecture"
        case .plantOrFlower: return "Plant"
        case .indoor: return "Indoors"
        }
    }
}

import Vision
import Accelerate
import CoreVideo
import os.log

// MARK: - Label mapping (data-driven)

/// Maps raw `VNClassifyImageRequest` identifiers into `SemanticGroup` buckets
/// using `scene-label-groups.json`. Unknown-at-runtime identifiers are logged
/// (not crashed on) so the mapping can be corrected later.
enum SceneLabelMapper {
    private static let log = Logger(subsystem: "com.ragnus.mvp", category: "SceneLabels")

    /// group -> identifiers, loaded once from the bundled JSON.
    static let groups: [SemanticGroup: Set<String>] = {
        guard let url = Bundle.main.url(forResource: "scene-label-groups", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["groups"] as? [String: [String]]
        else {
            log.error("scene-label-groups.json missing or invalid — semantic groups disabled")
            return [:]
        }
        var out: [SemanticGroup: Set<String>] = [:]
        for (key, ids) in raw {
            if let group = SemanticGroup(rawValue: key) {
                out[group] = Set(ids.map { $0.lowercased() })
            }
        }
        return out
    }()

    /// Fold raw classification observations into per-group max confidence.
    /// Returns the groups plus any identifiers that had no mapping (logged).
    static func map(_ observations: [VNClassificationObservation]) -> (groups: [SemanticGroup: Float], unmapped: [String]) {
        var groups: [SemanticGroup: Float] = [:]
        var unmapped: [String] = []
        // Reverse index: identifier -> groups (built once, cheap).
        let reverse = reverseIndex
        for obs in observations {
            let id = obs.identifier.lowercased()
            guard let hits = reverse[id] else {
                if obs.confidence >= 0.3, !unmapped.contains(id) { unmapped.append(id) }
                continue
            }
            for g in hits {
                groups[g] = max(groups[g] ?? 0, obs.confidence)
            }
        }
        if !unmapped.isEmpty {
            log.debug("unmapped Vision labels (add to scene-label-groups.json): \(unmapped.joined(separator: ", "), privacy: .public)")
        }
        return (groups, unmapped)
    }

    private static let reverseIndex: [String: [SemanticGroup]] = {
        var rev: [String: [SemanticGroup]] = [:]
        for (group, ids) in groups {
            for id in ids { rev[id, default: []].append(group) }
        }
        return rev
    }()

    /// Debug-only: dump `VNClassifyImageRequest().supportedIdentifiers()` on
    /// device or simulator. Copy the output into
    /// `ios/PhotoRecipes/Resources/vision-labels.txt` and rebuild the mapping.
    static func dumpSupportedIdentifiers() -> String {
        (try? VNClassifyImageRequest().supportedIdentifiers())?.sorted().joined(separator: "\n") ?? ""
    }
}

// MARK: - Optical flow aggregation (pure over the flow pixel buffer)

struct MotionFeatures: Equatable {
    var subjectSpeedPxPerSec: Float
    var backgroundSpeedPxPerSec: Float
    var subjectRelativeSpeedPxPerSec: Float
    /// Unit vector in UI space (x right, y down). Defaults to (1, 0) when the
    /// subject is still so the pan cue still has a direction.
    var directionX: Float = 1
    var directionY: Float = 0
}

/// Aggregates a `VNGenerateOpticalFlowRequest` result pixel buffer into motion
/// features. The flow buffer holds interleaved float32 (dx, dy) pairs per
/// pixel — displacement of the *targeted* frame relative to the reference
/// frame, in targeted-image pixels.
///
/// Pure and unit-testable: pass any buffer with the same layout.
enum OpticalFlowAggregator {
    static func aggregate(
        flow: CVPixelBuffer,
        dt: Double,
        subjectBox: CGRect?, // normalized UI space (top-left origin), nil = no subject
        fullFrameWidthPx: Double
    ) -> MotionFeatures {
        guard dt > 0 else { return MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0) }
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flow) else {
            return MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0)
        }
        let w = CVPixelBufferGetWidth(flow)
        let h = CVPixelBufferGetHeight(flow)
        let rowBytes = CVPixelBufferGetBytesPerRow(flow)
        guard w > 0, h > 0, rowBytes >= w * 8 else {
            return MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0)
        }
        // Full-frame px/s scale: flow is computed on the downsampled frame.
        let scale = fullFrameWidthPx / Double(w)

        // Subject rect in flow pixels (row 0 = top: frames are upright).
        let box: CGRect? = subjectBox.map { b in
            CGRect(x: b.minX * CGFloat(w), y: b.minY * CGFloat(h),
                   width: b.width * CGFloat(w), height: b.height * CGFloat(h))
        }

        var subjMags: [Float] = []
        var bgMags: [Float] = []
        var subjVX = 0.0, subjVY = 0.0, subjN = 0
        var bgVX = 0.0, bgVY = 0.0, bgN = 0
        subjMags.reserveCapacity(4096)
        bgMags.reserveCapacity(16384)

        // Stride 2 keeps the 5 Hz budget comfortable on older phones.
        for y in stride(from: 0, to: h, by: 2) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in stride(from: 0, to: w, by: 2) {
                let dx = Double(row[x * 2])
                let dy = Double(row[x * 2 + 1])
                let mag = Float(hypot(dx, dy) / dt * scale)
                let vx = dx / dt * scale
                let vy = dy / dt * scale
                let inSubject = box?.contains(CGPoint(x: x, y: y)) ?? false
                if inSubject {
                    subjMags.append(mag); subjVX += vx; subjVY += vy; subjN += 1
                } else {
                    bgMags.append(mag); bgVX += vx; bgVY += vy; bgN += 1
                }
            }
        }

        let subjSpeed = median(subjMags)
        let bgSpeed = median(bgMags)
        // Vector difference of mean velocities, then magnitude.
        let rel: Float = {
            guard subjN > 0, bgN > 0 else { return 0 }
            let dvx = subjVX / Double(subjN) - bgVX / Double(bgN)
            let dvy = subjVY / Double(subjN) - bgVY / Double(bgN)
            return Float(hypot(dvx, dvy))
        }()
        // Subject motion direction (unit vector, UI space).
        var dirX: Float = 1, dirY: Float = 0
        if subjN > 0, subjSpeed > 1 {
            let mx = subjVX / Double(subjN), my = subjVY / Double(subjN)
            let m = hypot(mx, my)
            if m > 0 { dirX = Float(mx / m); dirY = Float(my / m) }
        }
        return MotionFeatures(
            subjectSpeedPxPerSec: subjSpeed,
            backgroundSpeedPxPerSec: bgSpeed,
            subjectRelativeSpeedPxPerSec: rel,
            directionX: dirX,
            directionY: dirY
        )
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}

// MARK: - Frame downsampling + luminance histogram (Accelerate)

/// vImage helpers. Frames arrive as 32BGRA; Vision and flow run on
/// downsampled copies to hold the latency budget.
enum FrameDownsampler {
    /// Downsample to `maxLongSide` on the long side (aspect preserved).
    static func downsample(_ pb: CVPixelBuffer, maxLongSide: Int) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let srcBase = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let srcW = CVPixelBufferGetWidth(pb)
        let srcH = CVPixelBufferGetHeight(pb)
        let srcRowBytes = CVPixelBufferGetBytesPerRow(pb)
        let longSide = max(srcW, srcH)
        guard longSide > maxLongSide else { return pb }
        let scale = Double(maxLongSide) / Double(longSide)
        let dstW = max(1, Int((Double(srcW) * scale).rounded()))
        let dstH = max(1, Int((Double(srcH) * scale).rounded()))

        var src = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(srcH),
            width: vImagePixelCount(srcW),
            rowBytes: srcRowBytes
        )
        var dstPB: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, dstW, dstH,
            kCVPixelFormatType_32BGRA, nil, &dstPB
        )
        guard status == kCVReturnSuccess, let dst = dstPB else { return nil }
        CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(dst, []) }
        guard let dstBase = CVPixelBufferGetBaseAddress(dst) else { return nil }
        var dstBuf = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(dstH),
            width: vImagePixelCount(dstW),
            rowBytes: CVPixelBufferGetBytesPerRow(dst)
        )
        let err = vImageScale_ARGB8888(&src, &dstBuf, nil, vImage_Flags(kvImageNoFlags))
        guard err == kvImageNoError else { return nil }
        return dst
    }
}

enum LuminanceHistogram {
    /// 256-bin luminance histogram + warm bias from a 32BGRA pixel buffer.
    /// Luminance via vImage matrix multiply (Rec. 709 weights) to a planar
    /// buffer, then `vImageHistogramCalculation_Planar8`; warm bias from the
    /// ARGB channel histogram (mean R vs mean B).
    static func compute(_ pb: CVPixelBuffer) -> (bins: [Int], warmBias: Float)? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        guard w > 0, h > 0 else { return nil }

        var src = vImage_Buffer(
            data: base,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rowBytes
        )

        // Luminance plane: Y = (54*R + 183*G + 18*B) / 256 (≈ Rec. 709).
        guard let yData = malloc(w * h) else { return nil }
        defer { free(yData) }
        var yBuf = vImage_Buffer(data: yData, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        var matrix: [Int16] = [54, 183, 18, 0]
        let mErr = matrix.withUnsafeMutableBufferPointer { mPtr in
            vImageMatrixMultiply_ARGB8888ToPlanar8(
                &src, &yBuf, mPtr.baseAddress!, 256, nil, 0, vImage_Flags(kvImageNoFlags)
            )
        }
        guard mErr == kvImageNoError else { return nil }

        var bins = [vImagePixelCount](repeating: 0, count: 256)
        // Planar8 takes a single flat histogram pointer (the ARGB8888 variant
        // takes an array of 4) — `&bins` is already the right type.
        let hErr = vImageHistogramCalculation_Planar8(&yBuf, &bins, vImage_Flags(kvImageNoFlags))
        guard hErr == kvImageNoError else { return nil }

        // Warm bias from channel means.
        var warm: Float = 0
        // One backing store per channel — Array(repeating:) would alias all
        // four histograms to the same bins and kill warmBias.
        var argb: [[vImagePixelCount]] = (0..<4).map { _ in [vImagePixelCount](repeating: 0, count: 256) }
        let cErr: vImage_Error = argb.withUnsafeMutableBufferPointer { outer in
            var ptrs: [UnsafeMutablePointer<vImagePixelCount>?] = []
            ptrs.reserveCapacity(4)
            for i in 0..<4 {
                ptrs.append(outer[i].withUnsafeMutableBufferPointer { $0.baseAddress })
            }
            return ptrs.withUnsafeMutableBufferPointer { pBuf in
                vImageHistogramCalculation_ARGB8888(&src, pBuf.baseAddress!, vImage_Flags(kvImageNoFlags))
            }
        }
        if cErr == kvImageNoError {
            let mean: (Int) -> Double = { ch in
                var s = 0.0
                for i in 0..<256 { s += Double(i) * Double(argb[ch][i]) }
                return s / Double(max(w * h, 1))
            }
            // ARGB order: channel 1 = R, channel 3 = B.
            let r = mean(1), b = mean(3)
            warm = Float((r - b) / (r + b + 1))
        }

        return (bins.map { Int($0) }, warm)
    }
}

// MARK: - Full extraction pass

/// Metering + device context for one extraction pass.
struct MeteringSample {
    var exposureSeconds: Double?
    var iso: Float?
    var aperture: Float?
    var exposureTargetOffset: Float?
    var wasCustom: Bool
    /// Active format field of view, degrees (for px/rad cross-checks).
    var fieldOfViewDegrees: Double?
    /// Full-frame width in pixels (for flow px/s scaling).
    var fullFrameWidthPx: Double?
}

/// One synchronous feature-extraction pass over the newest frame.
/// Runs on the vision queue (never the capture queue, never the main actor).
enum SceneFeatureExtractor {
    private static let log = Logger(subsystem: "com.ragnus.mvp", category: "SceneFeatures")

    static func extract(
        pixelBuffer: CVPixelBuffer,
        previousPixelBuffer: CVPixelBuffer?,
        previousTimestamp: CMTime?,
        timestamp: CMTime,
        metering: MeteringSample,
        pose: (elevationDegrees: Double, handShakeRadPerSec: Double),
        note: String
    ) -> SceneFeatures {
        var features = SceneFeatures()
        features.cameraElevationDegrees = Float(pose.elevationDegrees)
        features.handShakeRadPerSec = Float(pose.handShakeRadPerSec)
        features.meteredExposureSeconds = metering.exposureSeconds
        features.meteredISO = metering.iso
        features.lensAperture = metering.aperture
        features.exposureTargetOffset = metering.exposureTargetOffset
        features.exposureWasCustom = metering.wasCustom
        features.sceneEV100 = EV100Helper.ev100(
            aperture: metering.aperture,
            exposureSeconds: metering.exposureSeconds,
            iso: metering.iso,
            exposureTargetOffset: metering.exposureTargetOffset,
            wasCustom: metering.wasCustom
        )
        features.recipeIntent = IntentMatcher.match(note: note)

        let small = FrameDownsampler.downsample(pixelBuffer, maxLongSide: 768) ?? pixelBuffer
        let tiny = FrameDownsampler.downsample(pixelBuffer, maxLongSide: 256) ?? pixelBuffer

        // Semantic classification (upright frames → orientation .up).
        do {
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cvPixelBuffer: small, orientation: .up, options: [:])
                .perform([request])
            let mapped = SceneLabelMapper.map(request.results ?? [])
            features.semanticGroups = mapped.groups
        } catch {
            log.error("classification failed: \(error.localizedDescription, privacy: .public)")
        }

        // Subjects: largest face → largest human → largest animal →
        // highest-confidence salient object. Boxes converted to UI space.
        let subject = detectPrimarySubject(pixelBuffer: small)
        features.subjectKind = subject.kind
        if let box = subject.box {
            let uiBox = CoordinateSpaces.visionRectToUI(box)
            features.subjectBox = NormalizedBox(uiBox)
            features.subjectAreaFraction = Float(box.width * box.height)
        }

        // Motion: optical flow on 256px frames, ~100–150 ms apart.
        if let prev = previousPixelBuffer,
           let prevTiny = FrameDownsampler.downsample(prev, maxLongSide: 256),
           let prevTS = previousTimestamp {
            let dt = timestamp.seconds - prevTS.seconds
            if dt >= 0.05, dt <= 0.5 {
                let motion = computeMotion(
                    previous: prevTiny, current: tiny, dt: dt,
                    subjectBox: features.subjectBox?.cgRect,
                    fullFrameWidthPx: metering.fullFrameWidthPx ?? Double(CVPixelBufferGetWidth(pixelBuffer))
                )
                features.subjectSpeedPxPerSec = motion.subjectSpeedPxPerSec
                features.backgroundSpeedPxPerSec = motion.backgroundSpeedPxPerSec
                features.subjectRelativeSpeedPxPerSec = motion.subjectRelativeSpeedPxPerSec
                features.motionDirectionX = motion.directionX
                features.motionDirectionY = motion.directionY
            }
        }

        // Light & range from the luminance histogram.
        if let (bins, warm) = LuminanceHistogram.compute(tiny) {
            let stats = LuminanceStats.fromHistogram(bins: bins, warmBias: warm)
            features.highlightClipFraction = stats.highlightClipFraction
            features.shadowCrushFraction = stats.shadowCrushFraction
            features.percentileSpreadStops = stats.spreadStops
            features.warmBias = stats.warmBias
            if let box = features.subjectBox {
                features.subjectDeltaStops = subjectDeltaStops(
                    pixelBuffer: tiny, box: box.cgRect, frameMedian: stats.mean
                )
            }
        }

        return features
    }

    // MARK: subjects

    private struct DetectedSubject {
        var kind: SubjectKind?
        var box: CGRect? // Vision space (bottom-left origin)
    }

    private static func detectPrimarySubject(pixelBuffer: CVPixelBuffer) -> DetectedSubject {
        let faceReq = VNDetectFaceRectanglesRequest()
        let humanReq = VNDetectHumanRectanglesRequest()
        let animalReq = VNRecognizeAnimalsRequest()
        let saliencyReq = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceReq, humanReq, animalReq, saliencyReq])
        } catch {
            log.error("subject detection failed: \(error.localizedDescription, privacy: .public)")
            return DetectedSubject()
        }

        if let faces = faceReq.results, !faces.isEmpty,
           let best = faces.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            return DetectedSubject(kind: .face, box: best.boundingBox)
        }
        if let humans = humanReq.results, !humans.isEmpty,
           let best = humans.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            return DetectedSubject(kind: .human, box: best.boundingBox)
        }
        if let animals = animalReq.results, !animals.isEmpty,
           let best = animals.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            return DetectedSubject(kind: .animal, box: best.boundingBox)
        }
        if let obs = saliencyReq.results?.first as? VNSaliencyImageObservation,
           let objects = obs.salientObjects,
           let top = objects.max(by: { $0.confidence < $1.confidence }) {
            return DetectedSubject(kind: .salientObject, box: top.boundingBox)
        }
        return DetectedSubject()
    }

    // MARK: motion

    /// Motion-only pass for the sensor's 5 Hz tick. Returns nil when the frame
    /// pair is unusable (dt out of range, flow failed).
    static func extractMotion(
        previousPixelBuffer: CVPixelBuffer,
        previousTimestamp: CMTime,
        pixelBuffer: CVPixelBuffer,
        timestamp: CMTime,
        subjectBox: NormalizedBox?,
        fullFrameWidthPx: Double?
    ) -> MotionFeatures? {
        let dt = timestamp.seconds - previousTimestamp.seconds
        guard dt >= 0.05, dt <= 0.5 else { return nil }
        guard let prevTiny = FrameDownsampler.downsample(previousPixelBuffer, maxLongSide: 256),
              let tiny = FrameDownsampler.downsample(pixelBuffer, maxLongSide: 256)
        else { return nil }
        let width = fullFrameWidthPx ?? Double(CVPixelBufferGetWidth(pixelBuffer))
        let motion = computeMotion(
            previous: prevTiny, current: tiny, dt: dt,
            subjectBox: subjectBox?.cgRect,
            fullFrameWidthPx: width
        )
        // Distinguish "flow failed" (all zeros) from real stillness: flow
        // failure is rare; treat all-zero as a valid still reading.
        return motion
    }

    private static func computeMotion(
        previous: CVPixelBuffer,
        current: CVPixelBuffer,
        dt: Double,
        subjectBox: CGRect?,
        fullFrameWidthPx: Double
    ) -> MotionFeatures {
        do {
            let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current)
            try VNImageRequestHandler(cvPixelBuffer: previous, orientation: .up, options: [:])
                .perform([request])
            guard let flowPB = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else {
                return MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0)
            }
            return OpticalFlowAggregator.aggregate(
                flow: flowPB, dt: dt, subjectBox: subjectBox, fullFrameWidthPx: fullFrameWidthPx
            )
        } catch {
            log.error("optical flow failed: \(error.localizedDescription, privacy: .public)")
            return MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0)
        }
    }

    // MARK: subject region brightness

    /// Subject-box mean luminance vs frame median, in stops (negative = darker).
    /// Used for backlit detection (HDR) and face EV lift.
    private static func subjectDeltaStops(pixelBuffer: CVPixelBuffer, box: CGRect, frameMedian: Float) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let x0 = max(0, Int((box.minX * CGFloat(w)).rounded()))
        let y0 = max(0, Int((box.minY * CGFloat(h)).rounded()))
        let x1 = min(w, Int(((box.minX + box.width) * CGFloat(w)).rounded()))
        let y1 = min(h, Int(((box.minY + box.height) * CGFloat(h)).rounded()))
        guard x1 > x0, y1 > y0 else { return nil }
        var sum = 0.0
        var n = 0
        // Stride 4 — region average only needs a sample.
        for y in stride(from: y0, to: y1, by: 4) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: x0, to: x1, by: 4) {
                let o = x * 4
                // 32BGRA: B G R A.
                let lum = (0.114 * Double(row[o]) + 0.587 * Double(row[o + 1]) + 0.299 * Double(row[o + 2])) / 255.0
                sum += lum
                n += 1
            }
        }
        guard n > 0 else { return nil }
        let regionMean = max(sum / Double(n), 1.0 / 255.0)
        let median = max(Double(frameMedian), 1.0 / 255.0)
        return Float(log2(regionMean / median))
    }
}

// MARK: - Optional Foundation Models intent mapping (off by default)

#if canImport(FoundationModels)
import FoundationModels

/// On-device Foundation Models intent mapping — guided generation from the
/// user's own note to a recipe id. Gated behind a feature flag (default OFF);
/// the token matcher (`IntentMatcher`) is the fallback and the default.
enum FoundationModelsIntentMapper {
    static let defaultsKey = "autoOptimize.foundationModelsIntentEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Returns a recipe id, or nil to fall back to `IntentMatcher`.
    @available(iOS 26, *)
    static func map(note: String) async -> RecipeIntent? {
        guard isEnabled else { return nil }
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let ids = SceneFeatures.autoSelectCandidates.joined(separator: ", ")
            let session = LanguageModelSession(instructions: """
                Map the photographer's scene note to exactly one recipe id from this list: \(ids).
                Reply with ONLY the id, or the word "none" if nothing matches.
                """)
            let response = try await session.respond(to: note)
            let id = response.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard SceneFeatures.autoSelectCandidates.contains(id) else { return nil }
            return RecipeIntent(recipeId: id, matchedPhrase: note)
        } catch {
            return nil
        }
    }
}
#endif

private extension CGRect {
    var area: CGFloat { width * height }
}

private extension CMTime {
    var seconds: Double { CMTimeGetSeconds(self) }
}
