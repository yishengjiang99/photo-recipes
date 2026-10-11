import CoreGraphics
import Foundation

/// Who set the look that is active on the finder. Auto Optimize only ever
/// replaces an `.auto` look — a look the user picked (drawer / rail / chip /
/// Library) or a forced look (voice APPLY-FILTERS, named look) always wins.
enum LookOwner: String, Equatable {
    /// Auto Optimize (LookSuggester / selfie policy), cloud refine, or a Recommend
    /// response look that was not forced by the utterance.
    case auto
    /// The user picked it by hand this session (drawer grid / intensity slider,
    /// filter rail, suggested-look chip Apply, Library selfie preset).
    case user
    /// `ApplyFiltersIntent.forcedLook` — voice / typed named look (wins last @ 0.55).
    case forced
}

/// Why `SelfieAutoPolicy` picked its look. Raw values are telemetry-safe ids;
/// `copy` is the short reason under the feedback pill.
enum SelfieAutoReason: String, Equatable, CaseIterable {
    case lowLight = "low_light"
    case backlit = "backlit"
    case harshLight = "harsh_light"
    case smallSubject = "small_subject"
    case busyBackground = "busy_background"
    case evenLight = "even_light"

    var copy: String {
        switch self {
        case .lowLight: return "low light"
        case .backlit: return "backlit"
        case .harshLight: return "harsh light"
        case .smallSubject: return "small in frame"
        case .busyBackground: return "busy background"
        case .evenLight: return "even light"
        }
    }
}

/// Selfie-aware Auto Optimize: on the **front** camera with a real face in frame,
/// AO's computed targets are passed through `decide(_:)`, which picks one of the
/// five selfie looks from scene signals and merges that preset's capture light
/// into AO's targets. Pure (no AVFoundation / UIKit) so the whole matrix is unit-tested.
///
/// ## Selection (first match wins; all fields from `SceneFeatures`)
/// | # | Rule | Look | Reason |
/// |---|------|------|--------|
/// | 1 | `sceneEV100 < 5.0`, or EV unknown and `meteredISO ≥ 1250`, or `nightOrLights ≥ 0.5` and `sceneEV100 < 7` | selfieLowLight | low light |
/// | 2 | face ≥ 1 stop under the frame median (`subjectDeltaStops ≤ −1.0`), or ≥ 0.5 stop under with `highlightClipFraction ≥ 0.10` | selfieGlow | backlit |
/// | 3 | face ≥ 0.8 stop over the median (`subjectDeltaStops ≥ +0.8`), or `highlightClipFraction ≥ 0.05` with `percentileSpreadStops ≥ 7` | selfieStudio | harsh light |
/// | 4 | single/duo face (`faceCount ≤ 2`) and face area `< 0.035` of frame | selfiePortrait | small in frame |
/// | 5 | single/duo face, outdoor busy groups (landscape / architecture / vehicle / plantOrFlower / sky ≥ 0.5) and `indoor < 0.5` | selfiePortrait | busy background |
/// | 6 | otherwise | selfieNatural | even light |
///
/// Face gate: `subjectKind == .face`, a finite `subjectBox`, and face area
/// (`subjectAreaFraction`, else box area) `≥ 0.008` (~12 % of frame width) —
/// a distant face in the background is not a selfie. Portrait blur is skipped
/// for 3+ faces (group selfie: the blur would soften the other faces).
///
/// ## Merge precedence (`merge(ao:preset:look:)`)
/// - AO authoritative: shutter / exposureDurationSec / ISO, white balance,
///   focus mode / point / lens position, zoom, frame rate, bracket, HDR, LUT.
/// - EV: AO's `ev` when set; dropped when AO wrote custom shutter/ISO (EV is
///   folded into that solve); otherwise the preset's face lift (+0.2…+0.5).
/// - Front-camera light levers come from the preset: `flash` (Retina Flash,
///   capability-gated in `CameraSession.applyFlash`), `lowLightBoost` (OR'd
///   with AO's), face-weighted AF/AE (`meterOnFace`).
/// - `simulatedAperture` (coach only): AO's, else the preset's.
/// - White-balance hold after AE (Studio Crisp) only when AO set no WB.
/// - `creativeLook` = the selfie id @ AO's look intensity (clamped 0.35…0.8)
///   or 0.55 when AO had none.
///
/// ## Look precedence
/// forced look > user's manual pick this session > selfie choice > AO / server look.
/// No face, a too-small face, or the back camera → AO output unchanged.
enum SelfieAutoPolicy {

    // MARK: Thresholds (documented above; tests pin them)

    static let minFaceArea: Float = 0.008
    static let smallFaceArea: Float = 0.035
    static let lowLightEV100: Float = 5.0
    static let lowLightISOFallback: Float = 1250
    static let nightGroupMin: Float = 0.5
    static let nightEV100Ceiling: Float = 7.0
    static let backlitDeltaStops: Float = -1.0
    static let backlitSoftDeltaStops: Float = -0.5
    static let backlitClipFraction: Float = 0.10
    static let harshDeltaStops: Float = 0.8
    static let harshClipFraction: Float = 0.05
    static let harshSpreadStops: Float = 7.0
    static let busyGroupMin: Float = 0.5
    static let maxPortraitFaces = 2
    static let minIntensity = 0.35
    static let maxIntensity = 0.8

    static let busyGroups: [SemanticGroup] = [.landscape, .architecture, .vehicle, .plantOrFlower, .sky]

    struct Input: Equatable {
        var isFrontCamera: Bool
        var features: SceneFeatures
        /// AO's computed targets (Pass 1 solve, `creativeLook` = AO's look if any).
        var aoTargets: PhoneTargets
        var activeLook: CreativeLook?
        var activeLookOwner: LookOwner?
    }

    struct Pick: Equatable {
        var lookId: String
        var reason: SelfieAutoReason
    }

    struct Choice: Equatable {
        var pick: Pick
        var look: CreativeLook
        /// AO targets merged with the preset (creativeLook = `look`).
        var targets: PhoneTargets
        var meterOnFace: Bool
        var lockWhiteBalanceAfterAE: Bool
        /// The non-selfie AO / server look the choice replaced (nil = none).
        var replacedLookId: String?
        /// UI-space face box for the feedback bracket.
        var faceBox: CGRect?
    }

    enum SkipReason: String, Equatable {
        case backCamera = "back_camera"
        case noFace = "no_face"
        case faceTooSmall = "face_too_small"
    }

    enum Decision: Equatable {
        /// Leave AO's output exactly as computed.
        case unchanged(SkipReason)
        /// Front + face, but a forced / user look owns the finder — keep it.
        /// `wouldPick` is what the policy would have chosen (telemetry only).
        case keepLook(lookId: String, owner: LookOwner, wouldPick: Pick)
        case apply(Choice)

        var choice: Choice? {
            if case .apply(let c) = self { return c }
            return nil
        }
    }

    // MARK: Decide

    static func decide(_ input: Input) -> Decision {
        guard input.isFrontCamera else { return .unchanged(.backCamera) }
        let f = input.features
        guard f.subjectKind == .face, let box = f.subjectBox,
              box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            return .unchanged(.noFace)
        }
        let area = faceArea(f)
        guard area >= minFaceArea else { return .unchanged(.faceTooSmall) }

        let pick = pickLook(f, faceArea: area)

        if let active = input.activeLook, let owner = input.activeLookOwner, owner != .auto {
            return .keepLook(lookId: active.id, owner: owner, wouldPick: pick)
        }

        guard let preset = SelfiePresets.preset(lookId: pick.lookId) else {
            return .unchanged(.noFace) // unreachable: every pick id is in SelfiePresets
        }
        let aoLook = input.aoTargets.creativeLook
        let look = CreativeLook(id: pick.lookId, intensity: intensity(from: aoLook))
        let merged = merge(ao: input.aoTargets, preset: preset, look: look)
        let replaced: String? = {
            guard let id = aoLook?.id, !id.isEmpty, !CreativeLookCatalog.isSelfie(id) else { return nil }
            return id
        }()
        return .apply(Choice(
            pick: pick,
            look: look,
            targets: merged,
            meterOnFace: preset.meterOnFace,
            lockWhiteBalanceAfterAE: preset.lockWhiteBalanceAfterAE && input.aoTargets.whiteBalance == nil,
            replacedLookId: replaced,
            faceBox: box.cgRect
        ))
    }

    static func faceArea(_ f: SceneFeatures) -> Float {
        if f.subjectAreaFraction > 0, f.subjectAreaFraction.isFinite { return f.subjectAreaFraction }
        return f.subjectBox.map { $0.area } ?? 0
    }

    /// Scene signals → selfie look (table in the type doc).
    static func pickLook(_ f: SceneFeatures, faceArea area: Float) -> Pick {
        let ev = f.sceneEV100.flatMap { $0.isFinite ? $0 : nil }
        let night = (f.semanticGroups[.nightOrLights] ?? 0) >= nightGroupMin
        let lowLight: Bool = {
            if let ev {
                return ev < lowLightEV100 || (night && ev < nightEV100Ceiling)
            }
            if let iso = f.meteredISO, iso.isFinite, iso >= lowLightISOFallback { return true }
            return night
        }()
        if lowLight { return Pick(lookId: "selfieLowLight", reason: .lowLight) }

        let delta = f.subjectDeltaStops.flatMap { $0.isFinite ? $0 : nil }
        if let delta {
            if delta <= backlitDeltaStops
                || (delta <= backlitSoftDeltaStops && f.highlightClipFraction >= backlitClipFraction) {
                return Pick(lookId: "selfieGlow", reason: .backlit)
            }
        }
        let faceHot = (delta ?? 0) >= harshDeltaStops
        let harshFrame = f.highlightClipFraction >= harshClipFraction
            && f.percentileSpreadStops >= harshSpreadStops
            && (delta ?? 0) > backlitSoftDeltaStops
        if faceHot || harshFrame { return Pick(lookId: "selfieStudio", reason: .harshLight) }

        let fewFaces = (f.faceCount ?? 1) <= maxPortraitFaces
        if fewFaces {
            if area < smallFaceArea { return Pick(lookId: "selfiePortrait", reason: .smallSubject) }
            let busy = busyGroups.contains { (f.semanticGroups[$0] ?? 0) >= busyGroupMin }
            let indoor = (f.semanticGroups[.indoor] ?? 0) >= busyGroupMin
            if busy && !indoor { return Pick(lookId: "selfiePortrait", reason: .busyBackground) }
        }
        return Pick(lookId: "selfieNatural", reason: .evenLight)
    }

    /// AO's look intensity clamped into a tasteful selfie range; 0.55 when AO had none.
    static func intensity(from aoLook: CreativeLook?) -> Double {
        guard let v = aoLook?.intensity, v.isFinite, v > 0 else { return CreativeLookCatalog.defaultIntensity }
        return min(max(v, minIntensity), maxIntensity)
    }

    /// Merge precedence documented on the type.
    static func merge(ao: PhoneTargets, preset: SelfiePresets.Preset, look: CreativeLook) -> PhoneTargets {
        var t = ao
        let p = preset.targets
        let aoCustomExposure = ao.exposureDurationSec != nil || ao.shutter != nil || ao.iso != nil
        if ao.ev == nil, !aoCustomExposure { t.ev = p.ev }
        if let flash = p.flash { t.flash = flash }
        if p.lowLightBoost == true || ao.lowLightBoost == true { t.lowLightBoost = true }
        if t.simulatedAperture == nil { t.simulatedAperture = p.simulatedAperture }
        if t.focusMode == nil, t.focusPoint == nil, t.lensPosition == nil { t.focusMode = p.focusMode }
        // Front camera: never a torch or lens switch (SettingsSolver already strips; belt and braces).
        t.torch = nil
        t.cameraDevice = nil
        t.creativeLook = look
        return t
    }

    // MARK: Cloud refine (Pass 2)

    /// Server look from Pass 2: on a run where the selfie policy applied, a
    /// non-selfie server look never replaces the selfie choice (selfie wins on
    /// front). Returns the look to apply, or nil to keep the current one.
    static func resolveServerLook(_ server: CreativeLook?, selfieLookId: String?, activeLook: CreativeLook?) -> CreativeLook? {
        guard let server, !server.id.isEmpty, CreativeLookCatalog.isKnown(server.id) else { return nil }
        if selfieLookId != nil, !CreativeLookCatalog.isSelfie(server.id) { return nil }
        // Existing rule: only fill an empty finder (never stack on Pass 1's look).
        guard activeLook == nil else { return nil }
        return server
    }

    // MARK: Telemetry (`selfie_auto`, no PII: ids + booleans only)

    static func telemetryProps(_ decision: Decision, trigger: String, runId: String) -> [String: String]? {
        switch decision {
        case .unchanged:
            return nil
        case .keepLook(_, let owner, let wouldPick):
            return [
                "look_id": wouldPick.lookId,
                "reason": wouldPick.reason.rawValue,
                "forced_override": "1",
                "kept_owner": owner.rawValue,
                "replaced_look": "0",
                "trigger": trigger,
                "run_id": runId,
            ]
        case .apply(let c):
            return [
                "look_id": c.pick.lookId,
                "reason": c.pick.reason.rawValue,
                "forced_override": "0",
                "kept_owner": "",
                "replaced_look": c.replacedLookId == nil ? "0" : "1",
                "trigger": trigger,
                "run_id": runId,
            ]
        }
    }
}

/// What selfie-aware AO applied on a run — drives the transient feedback moment.
struct SelfieAutoApplied: Equatable {
    var lookId: String
    var reason: SelfieAutoReason
    /// UI-space (top-left origin, 0…1) face box at decision time.
    var faceBox: CGRect?
    var runId: String
}
