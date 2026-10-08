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
        /// 0–1 — auto-apply only at/above `lookAutoApplyThreshold`; below → chip suggestion.
        var lookConfidence: Double = 0
        var senseSummary: String
    }

    /// Below this, show the look as a suggestion (Apply / Dismiss) instead of auto-applying.
    static let lookAutoApplyThreshold = 0.6

    static func recommend(
        signals: LocalSceneSignals,
        preferRecipeId: String?,
        capabilities: DeviceCapabilities
    ) -> Recommendation {
        let recipeId = preferRecipeId.flatMap { BundledPresets.recipe(id: $0)?.id }
            ?? chooseRecipeId(signals)
        let recipe = BundledPresets.recipe(id: recipeId) ?? BundledPresets.sharpFrontToBack
        let targets = buildPhoneTargets(recipeId: recipe.id, signals: signals, capabilities: capabilities)
        let scored = scoredLook(signals: signals)
        let look = scored?.look
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
            lookConfidence: scored?.confidence ?? 0,
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
        if h.wantsPortrait || (s.faceCount > 0 && s.brightness01 > 0.35) { return "portrait-pop" }
        if h.wantsLeadingLines { return "leading-lines" }
        if h.wantsMinimalist { return "minimalist-photos" }
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

        // Faces → portrait-pop (eye focus, background blur) instead of landscape DoF.
        if s.faceCount > 0 {
            return "portrait-pop"
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
        let focus0 = focusPoint(signals)
        var focus: CGPoint? = focus0
        var shutter: String?
        var exposureSec: Double?
        var iso: String?
        var ev: String?
        var focusMode: String? = "continuous"
        var wb: WhiteBalanceTarget? = .mode("auto")
        var cameraDevice: String?
        var zoom: Double?
        var simulatedAperture: Double?
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

        case "portrait-pop":
            // CoreML (Vision) faces → single-point focus on the eyes, wide-open blur, 2× zoom.
            focusMode = "locked"
            if let f = signals.primaryFaceCenter {
                focus = clampNorm(eyePoint(f))
            }
            zoom = 2.0
            simulatedAperture = 1.8 // coach-only on fixed phone lenses
            let psec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = psec
            shutter = RecipeCameraMapper.formatShutter(psec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            ev = faceEV(signals) ?? "0"
            torch = veryDark ? TorchTarget(mode: "off") : nil // no deer-in-headlights; boost instead
            lowLightBoost = dark

        case "sharp-and-in-focus":
            // Single-point focus, locked on the subject (eyes for people/pets, saliency otherwise).
            focusMode = "locked"
            let ssec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = ssec
            shutter = RecipeCameraMapper.formatShutter(ssec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            ev = faceEV(signals) ?? (bright > 0.75 ? "-0.3" : "0")

        case "leading-lines":
            // Deep focus so lines stay sharp foreground→background; focus on the main subject.
            focusMode = focus != nil ? "locked" : "continuous"
            simulatedAperture = 11 // coach-only: deep focus keeps lines sharp
            let lsec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = lsec
            shutter = RecipeCameraMapper.formatShutter(lsec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            ev = faceEV(signals) ?? (bright > 0.75 ? "-0.3" : "0")

        case "minimalist-photos":
            // Expose for mood; slight underexposure keeps blue-hour / gloomy scenes moody.
            focusMode = focus != nil ? "locked" : "continuous"
            let msec = handshakeSafeShutter(brightness: bright, capabilities: capabilities)
            exposureSec = msec
            shutter = RecipeCameraMapper.formatShutter(msec)
            iso = isoString(pickISO(forBrightness: bright, capabilities: capabilities, preferLow: true))
            ev = bright < 0.4 ? "-0.3" : "0"

        case "exposure-triangle-cheatsheet":
            // Reference card — no camera changes; coach-only.
            focusMode = "continuous"
            ev = "0"

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
            zoom: zoom,
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
            simulatedAperture: simulatedAperture ?? (recipeId == "sharp-front-to-back" ? 11 : nil)
        )
    }

    private static func focusPoint(_ s: LocalSceneSignals) -> CGPoint? {
        if let f = s.primaryFaceCenter { return clampNorm(f) }
        if let sal = s.saliencyPoint { return clampNorm(sal) }
        // Hyperfocal shortcut: ~⅓ into frame.
        return CGPoint(x: 0.5, y: 0.62)
    }

    /// Eyes sit above the face box center — nudge the Vision face point up so
    /// single-point focus lands on the eyes (portrait-pop / sharp-and-in-focus).
    private static func eyePoint(_ faceCenter: CGPoint) -> CGPoint {
        CGPoint(x: faceCenter.x, y: faceCenter.y - 0.07)
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
        scoredLook(signals: signals)?.look
    }

    /// Look + confidence. Strong, specific evidence (explicit night / food note, faces) scores
    /// high and is auto-applied; generic fallbacks (contrast-only, mild warmth, landscape
    /// styling) score low and are only suggested. goldenHour needs strong warm late light
    /// (was 42/54 telemetry suggestions).
    static func scoredLook(signals: LocalSceneSignals) -> (look: CreativeLook, confidence: Double)? {
        let h = signals.sceneNoteHints
        let note = (signals.senseSummary + " ").lowercased()

        // Night / very dark → moody film (or coolBlue if cool cast).
        if h.night || signals.brightness01 < 0.22 {
            let conf = h.night ? 0.8 : 0.65
            if signals.warmBias < -0.05 {
                return (CreativeLook(id: "coolBlue", intensity: 0.5), conf)
            }
            return (CreativeLook(id: "moodyFilm", intensity: CreativeLookCatalog.defaultIntensity), conf)
        }

        // Faces / portrait → warmGlow (skin-friendly), not goldenHour.
        if signals.faceCount > 0 {
            if signals.warmBias < -0.08 {
                return (CreativeLook(id: "crispCool", intensity: 0.45), 0.7)
            }
            return (CreativeLook(id: "warmGlow", intensity: 0.45), 0.75)
        }

        // Explicit cool / overcast steel.
        if signals.warmBias < -0.1 && signals.contrast01 > 0.35 {
            return (CreativeLook(id: "crispCool", intensity: CreativeLookCatalog.defaultIntensity), 0.6)
        }

        // Landscape / deep scene → tealOrange cinematic, not golden by default.
        if h.wantsLandscapeDoF || note.contains("landscape") || note.contains("horizon") {
            if signals.warmBias > 0.18 && signals.brightness01 > 0.4 && signals.brightness01 < 0.75 {
                return (CreativeLook(id: "goldenHour", intensity: 0.5), 0.7)
            }
            // Stylistic choice, not scene evidence → suggest only.
            return (CreativeLook(id: "tealOrange", intensity: 0.5), 0.5)
        }

        // Food / color pop cues from note.
        if h.food || note.contains("food") || note.contains("meal") || note.contains("dish") {
            return (CreativeLook(id: "warmPop", intensity: 0.5), h.food ? 0.8 : 0.7)
        }

        // High contrast daylight → blockbuster, suggest only (contrast alone is weak evidence).
        if signals.contrast01 > 0.55 && signals.brightness01 > 0.45 {
            return (CreativeLook(id: "blockbuster", intensity: 0.5), 0.45)
        }

        // True golden hour: strong warm bias + mid brightness (late light), no faces.
        if signals.warmBias > 0.18 && signals.brightness01 > 0.38 && signals.brightness01 < 0.72 {
            return (CreativeLook(id: "goldenHour", intensity: CreativeLookCatalog.defaultIntensity), 0.62)
        }

        // Mild warm daylight → warmPop suggestion only.
        if signals.warmBias > 0.08 && signals.brightness01 > 0.4 {
            return (CreativeLook(id: "warmPop", intensity: 0.45), 0.4)
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
        case "portrait-pop":
            return (
                "Face in frame — widest blur, eye focus, 2× zoom for background pop.",
                "Local AO detected a face (Vision, on-device) and moved the focus point to the eyes, lifted exposure for the face, and set 2× zoom. Phone lenses are fixed, so the f/1.8 is coaching — use Portrait mode for real optical blur."
            )
        case "sharp-and-in-focus":
            return (
                "Subject to nail — single-point focus locked on it.",
                "Local AO locked single-point focus on the detected subject (eyes for people). Tap the screen if it picked the wrong element — you are smarter than the camera."
            )
        case "leading-lines":
            return (
                "Lines in the scene — aim them at your subject, deep focus.",
                "Local AO set deep-focus exposure and focused on the main subject. Turn on the thirds grid and place the subject where a line meets a third line."
            )
        case "minimalist-photos":
            return (
                "One simple subject — isolate it, thirds grid, moody exposure.",
                "Local AO exposed for the mood and suggests the thirds grid. If the frame feels busy, reframe until only one thing stands out."
            )
        case "exposure-triangle-cheatsheet":
            return (
                "Reference card — the exposure triangle, no camera changes.",
                "This is the book's cheat sheet: aperture, ISO, shutter speed. Change one, compensate with another. No camera settings were touched."
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
        case "portrait-pop":
            return CoachOnly(aperture: "f/1.8 wide open (guidance — use Portrait mode)", nd: nil, tripod: false, notes: "Zoom 2×, focus on the eyes, verify sharpness by zooming in tight after the shot.")
        case "sharp-and-in-focus":
            return CoachOnly(aperture: "high f-stop for more in focus (guidance)", nd: nil, tripod: false, notes: "Single-point focus locked on the subject — tap to move it if the camera picked the wrong element.")
        case "leading-lines":
            return CoachOnly(aperture: "f/11 deep focus (guidance)", nd: nil, tripod: false, notes: "Turn on the thirds grid; lines should start in the foreground and point at the subject, never out the side.")
        case "minimalist-photos":
            return CoachOnly(aperture: nil, nd: nil, tripod: false, notes: "Thirds grid on; one subject on a third line; blue hour (30 min after sunset) is ideal.")
        case "exposure-triangle-cheatsheet":
            return CoachOnly(aperture: nil, nd: nil, tripod: false, notes: "Reference card — aperture, ISO, shutter speed. Change one, compensate with another.")
        default:
            return nil
        }
    }
}
