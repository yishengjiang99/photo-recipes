import Foundation
import CoreGraphics

/// Pure on-device Auto Optimize reasoner.
/// Heuristic scene → bundled preset + PhoneTargets. No VLM, no /api/recommend, no .mlmodel (Build 3).
enum LocalAutoOptimizeEngine {

    struct Recommendation: Equatable {
        var recipeId: String
        var reason: String
        var teachWhy: String
        var tips: [String]
        var phoneTargets: PhoneTargets
        var panCue: PanCue?
        var coachOnly: CoachOnly?
        var suggestedLook: CreativeLook?
        var senseSummary: String
    }

    static func recommend(
        signals: LocalSceneSignals,
        preferRecipeId: String?,
        capabilities: DeviceCapabilities
    ) -> Recommendation {
        let recipeId = preferRecipeId.flatMap { BundledPresets.recipe(id: $0)?.id }
            ?? chooseRecipeId(signals)
        let recipe = BundledPresets.recipe(id: recipeId) ?? BundledPresets.sharpFrontToBack
        let targets = buildPhoneTargets(recipeId: recipe.id, signals: signals, capabilities: capabilities)
        let look = suggestLook(signals: signals)
        let (reason, teach) = copy(for: recipe.id, signals: signals)
        let pan = panCue(for: recipe.id)
        let coach = coachOnly(for: recipe.id, signals: signals)

        var tips = recipe.tips
        if signals.brightness01 < 0.28 {
            tips.insert("Low light — brace or use a tripod if shutter drops below 1/60s.", at: 0)
        }
        if signals.isLowAngle {
            tips.insert("Stay low; ultra-wide helps the foreground dominate.", at: 0)
        }

        return Recommendation(
            recipeId: recipe.id,
            reason: reason,
            teachWhy: teach,
            tips: tips,
            phoneTargets: targets,
            panCue: pan,
            coachOnly: coach,
            suggestedLook: look,
            senseSummary: signals.senseSummary
        )
    }

    // MARK: - Scene → recipe map

    static func chooseRecipeId(_ s: LocalSceneSignals) -> String {
        let h = s.sceneNoteHints

        // Explicit photographer intent wins.
        if h.wantsPanning { return "panning-sharp-subject" }
        if h.wantsMotionBlur { return "blur-moving-subjects" }
        if h.wantsHDR { return "hdr-brights-darks" }
        if h.wantsLowAngle || s.isLowAngle { return "get-down-low" }
        if h.wantsLandscapeDoF { return "sharp-front-to-back" }

        // HDR: clipped highlights + crushed shadows or very high contrast.
        if (s.highlightClip01 > 0.04 && s.shadowCrush01 > 0.06) || s.contrast01 > 0.62 {
            return "hdr-brights-darks"
        }

        // Night / very dark → intentional blur / trails when no faces.
        if (h.night || s.brightness01 < 0.18) && s.faceCount == 0 {
            return "blur-moving-subjects"
        }

        // Faces + mid motion cues → keep subject sharp (panning start).
        // Without note keywords, faces prefer stable exposure (landscape DoF path is wrong).
        if s.faceCount > 0 && s.brightness01 > 0.35 {
            // Portrait-ish: still use landscape DoF recipe only if note asked; else get-down-low rarely.
            // Default for faces: sharp front-to-back with face focus + mild +EV (handled in targets).
            return "sharp-front-to-back"
        }

        // Low angle from motion without note.
        if s.isLowAngle {
            return "get-down-low"
        }

        // Default field landscape / deep focus.
        return "sharp-front-to-back"
    }

    // MARK: - PhoneTargets

    static func buildPhoneTargets(
        recipeId: String,
        signals: LocalSceneSignals,
        capabilities: DeviceCapabilities
    ) -> PhoneTargets {
        let focus = focusPoint(signals)
        var shutter: String?
        var exposureSec: Double?
        var iso: String?
        var ev: String?
        var focusMode: String? = "continuous"
        var wb: WhiteBalanceTarget? = .mode("auto")
        var cameraDevice: String?
        var bracket: BracketTarget?
        var lowLightBoost: Bool?
        var videoHDR: Bool?
        var monitorSubject = false
        var creativeLook: CreativeLook?
        var torch: TorchTarget?

        // Base from metering — keep usable phone ranges.
        let bright = signals.brightness01
        let dark = bright < 0.28
        let veryDark = bright < 0.18

        switch recipeId {
        case "blur-moving-subjects":
            if signals.sceneNoteHints.night || veryDark {
                exposureSec = clampExposure(20.0, capabilities)
                iso = isoString(clampISO(50, capabilities))
                shutter = RecipeCameraMapper.formatShutter(exposureSec ?? 20)
                focusMode = "locked"
                ev = "0"
            } else {
                exposureSec = clampExposure(0.5, capabilities)
                iso = isoString(clampISO(50, capabilities))
                shutter = RecipeCameraMapper.formatShutter(exposureSec ?? 0.5)
                focusMode = "locked"
                ev = "0"
            }
            monitorSubject = false

        case "panning-sharp-subject":
            exposureSec = clampExposure(1.0 / 30.0, capabilities)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: false))
            shutter = "1/30s"
            focusMode = focus != nil ? "locked" : "continuous"
            ev = faceEV(signals)
            monitorSubject = true

        case "hdr-brights-darks":
            // Phone HDR path: mild EV, bracket cue, videoHDR when available.
            exposureSec = nil
            shutter = nil
            iso = nil
            ev = faceEV(signals) ?? "0"
            bracket = BracketTarget(stops: [-2, 0, 2], count: 3)
            videoHDR = true
            focusMode = focus != nil ? "locked" : "continuous"
            lowLightBoost = dark

        case "get-down-low":
            cameraDevice = "ultraWide"
            // Exposure: follow light; keep handshake-safe shutter when possible.
            let sec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = sec
            shutter = RecipeCameraMapper.formatShutter(sec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            ev = faceEV(signals) ?? (bright > 0.7 ? "-0.3" : "0")
            focusMode = focus != nil ? "auto" : "continuous"

        default: // sharp-front-to-back
            let sec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = sec
            shutter = RecipeCameraMapper.formatShutter(sec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            // Hyperfocal-ish: focus ~⅓ into frame if no face/saliency.
            ev = faceEV(signals) ?? (bright > 0.75 ? "-0.3" : "0")
            focusMode = "locked"
            lowLightBoost = dark
        }

        if signals.warmBias > 0.08 {
            wb = .mode("daylight")
        } else if signals.warmBias < -0.08 {
            wb = .mode("cloudy")
        }

        if veryDark && recipeId != "blur-moving-subjects" {
            lowLightBoost = true
            if signals.faceCount > 0 {
                torch = TorchTarget(mode: "off") // avoid deer-in-headlights; boost instead
            }
        }

        // Optional look rides on targets for chip suggest (never silent apply).
        creativeLook = suggestLook(signals: signals)

        return PhoneTargets(
            shutter: shutter,
            exposureDurationSec: exposureSec,
            iso: iso,
            ev: ev,
            whiteBalance: wb,
            focusMode: focusMode,
            zoom: nil,
            focusPoint: focus.map { FocusPointNorm(x: Double($0.x), y: Double($0.y)) },
            lensPosition: nil,
            torch: torch,
            flash: nil,
            lowLightBoost: lowLightBoost,
            videoHDR: videoHDR,
            cameraDevice: cameraDevice,
            frameRate: nil,
            preferFormatHint: nil,
            bracket: bracket,
            monitorSubjectAreaChange: monitorSubject,
            maxPhotoDimensions: nil,
            previewLUT: nil,
            creativeLook: creativeLook,
            simulatedAperture: recipeId == "sharp-front-to-back" ? 11 : nil
        )
    }

    private static func focusPoint(_ s: LocalSceneSignals) -> CGPoint? {
        if let f = s.primaryFaceCenter { return clampNorm(f) }
        if let sal = s.saliencyPoint { return clampNorm(sal) }
        // Hyperfocal shortcut: ~⅓ into frame.
        return CGPoint(x: 0.5, y: 0.62)
    }

    private static func clampNorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0.05), 0.95), y: min(max(p.y, 0.05), 0.95))
    }

    private static func faceEV(_ s: LocalSceneSignals) -> String? {
        guard s.faceCount > 0 else { return nil }
        // Backlit faces: lift EV when highlights clip and faces present.
        if s.highlightClip01 > 0.05 { return "+0.7" }
        if s.brightness01 < 0.35 { return "+0.3" }
        return "0"
    }

    private static func handshakeSafeShutter(brightness: Double, capabilities: DeviceCapabilities) -> Double {
        let target: Double
        if brightness > 0.75 { target = 1.0 / 500 }
        else if brightness > 0.55 { target = 1.0 / 250 }
        else if brightness > 0.35 { target = 1.0 / 125 }
        else if brightness > 0.22 { target = 1.0 / 60 }
        else { target = 1.0 / 30 }
        return clampExposure(target, capabilities)
    }

    private static func pickISO(forBrightness brightness: Double, capabilities: DeviceCapabilities, preferLow: Bool) -> Float {
        let raw: Float
        if brightness > 0.7 { raw = preferLow ? 50 : 100 }
        else if brightness > 0.45 { raw = 100 }
        else if brightness > 0.28 { raw = 200 }
        else if brightness > 0.18 { raw = 400 }
        else { raw = 800 }
        return clampISO(raw, capabilities)
    }

    private static func clampExposure(_ sec: Double, _ caps: DeviceCapabilities) -> Double {
        min(max(sec, caps.minExposureSeconds), caps.maxExposureSeconds)
    }

    private static func clampISO(_ iso: Float, _ caps: DeviceCapabilities) -> Float {
        min(max(iso, caps.minISO), caps.maxISO)
    }

    private static func isoString(_ iso: Float) -> String { "\(Int(iso.rounded()))" }

    // MARK: - Look suggest (chip only)

    static func suggestLook(signals: LocalSceneSignals) -> CreativeLook? {
        // Prefer specific scene → look matches. goldenHour only for clearly warm late light
        // (was over-suggested: 42/54 telemetry suggestions).
        let h = signals.sceneNoteHints
        let note = (signals.senseSummary + " ").lowercased()

        // Night / very dark → moody film (or coolBlue if cool cast).
        if h.night || signals.brightness01 < 0.22 {
            if signals.warmBias < -0.05 {
                return CreativeLook(id: "coolBlue", intensity: 0.5)
            }
            return CreativeLook(id: "moodyFilm", intensity: CreativeLookCatalog.defaultIntensity)
        }

        // Faces / portrait → warmGlow (skin-friendly), not goldenHour.
        if signals.faceCount > 0 {
            if signals.warmBias < -0.08 {
                return CreativeLook(id: "crispCool", intensity: 0.45)
            }
            return CreativeLook(id: "warmGlow", intensity: 0.45)
        }

        // Explicit cool / overcast steel.
        if signals.warmBias < -0.1 && signals.contrast01 > 0.35 {
            return CreativeLook(id: "crispCool", intensity: CreativeLookCatalog.defaultIntensity)
        }

        // Landscape / deep scene → tealOrange cinematic, not golden by default.
        if h.wantsLandscapeDoF || note.contains("landscape") || note.contains("horizon") {
            if signals.warmBias > 0.18 && signals.brightness01 > 0.4 && signals.brightness01 < 0.75 {
                return CreativeLook(id: "goldenHour", intensity: 0.5)
            }
            return CreativeLook(id: "tealOrange", intensity: 0.5)
        }

        // Food / color pop cues from note.
        if h.food || note.contains("food") || note.contains("meal") || note.contains("dish") {
            return CreativeLook(id: "warmPop", intensity: 0.5)
        }

        // High contrast daylight → blockbuster / loFi, not golden.
        if signals.contrast01 > 0.55 && signals.brightness01 > 0.45 {
            return CreativeLook(id: "blockbuster", intensity: 0.5)
        }

        // True golden hour: strong warm bias + mid brightness (late light), no faces.
        if signals.warmBias > 0.18 && signals.brightness01 > 0.38 && signals.brightness01 < 0.72 {
            return CreativeLook(id: "goldenHour", intensity: CreativeLookCatalog.defaultIntensity)
        }

        // Mild warm daylight → warmPop; mild cool → softDream skip (nil = no look).
        if signals.warmBias > 0.08 && signals.brightness01 > 0.4 {
            return CreativeLook(id: "warmPop", intensity: 0.45)
        }

        return nil
    }

    // MARK: - Copy

    private static func copy(for recipeId: String, signals: LocalSceneSignals) -> (String, String) {
        switch recipeId {
        case "blur-moving-subjects":
            let reason = signals.sceneNoteHints.night || signals.brightness01 < 0.18
                ? "Low light / night — long shutter for trails or silk motion."
                : "Motion in frame — slower shutter to paint intentional blur."
            let teach = "Local AO picked Blur Moving Subjects from metering + scene cues. Tripod if you can; start around the suggested shutter and review."
            return (reason, teach)
        case "panning-sharp-subject":
            return (
                "Moving subject — pan with them at ~1/30s so the background streaks.",
                "Local AO set a panning shutter. Rotate with the subject; review and nudge shutter faster/slower."
            )
        case "hdr-brights-darks":
            return (
                "High contrast / clipped ends — HDR bracket keeps brights and darks.",
                "Local AO saw highlight and shadow extremes. Use the bracket stops or phone HDR; keep the merge natural."
            )
        case "get-down-low":
            return (
                "Low angle — drop to knee height with the widest lens.",
                "Local AO cues Low Angle from orientation / note. Flip the phone if needed so the lens is closest to the ground."
            )
        default:
            return (
                "Deep scene — maximize front-to-back sharpness (hyperfocal ~⅓ in).",
                "Local AO chose Sharp Front to Back from light + saliency. Focus about a third into the frame, then lock."
            )
        }
    }

    private static func panCue(for recipeId: String) -> PanCue? {
        switch recipeId {
        case "panning-sharp-subject":
            return PanCue(direction: "horizontal", note: "Pan with the subject")
        case "get-down-low":
            return PanCue(direction: "down", note: "Drop lower")
        default:
            return nil
        }
    }

    private static func coachOnly(for recipeId: String, signals: LocalSceneSignals) -> CoachOnly? {
        switch recipeId {
        case "sharp-front-to-back":
            return CoachOnly(aperture: "f/11–f/16 (guidance)", nd: nil, tripod: signals.brightness01 < 0.35, notes: "Phone aperture is fixed — use subject distance for DoF.")
        case "blur-moving-subjects":
            return CoachOnly(aperture: nil, nd: signals.brightness01 > 0.6 ? "ND if daytime shutter won’t go slow enough" : nil, tripod: true, notes: "Tripod keeps the static world sharp while motion blurs.")
        case "hdr-brights-darks":
            return CoachOnly(aperture: "lock across brackets", nd: nil, tripod: true, notes: "Tripod so frames align.")
        default:
            return nil
        }
    }
}
