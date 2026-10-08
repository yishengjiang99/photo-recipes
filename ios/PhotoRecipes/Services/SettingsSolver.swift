import Foundation
import CoreGraphics

/// Turns a recipe + measured `SceneFeatures` into concrete `PhoneTargets`.
/// Shutter is solved first from each recipe's objective, then ISO from the
/// metered exposure product so the exposure is correct — never from fixed
/// lookup buckets.
///
/// Metered exposure product: P = t_metered × ISO_metered (the auto-exposure
/// equivalent). Target ISO = P × 2^EV / shutter, clamped to the device range.
/// An EV bias is folded into the ISO here — `applyPhoneTargets` must NOT call
/// `setEV` on top (see `ExposureApplyPolicy`).
enum SettingsSolver {

    /// Extra device context the pure solve needs.
    struct SolveContext {
        /// Reference width (px) the motion speeds are expressed in.
        var frameWidthPx: Double = 1920
        /// Active format field of view, degrees.
        var fieldOfViewDegrees: Double = 70
        /// Current white-balance gains (for HDR bracket consistency).
        var currentWBGains: (red: Double, green: Double, blue: Double)?
        static let `default` = SolveContext()
    }

    struct Solution {
        var phoneTargets: PhoneTargets
        var clampMessages: [String] = []
        /// Composed exposure offset the plan targets (recipe + face + learned),
        /// in stops. Nil when no custom exposure is written (HDR, cheatsheet,
        /// thermal-critical fallback) — the verify loop skips then.
        var targetEV: Double?
        var coachOnly: CoachOnly?
        var panCue: PanCue?
        var apertureGuidance: String?
        var extraTips: [String] = []
    }

    // MARK: - Entry

    static func solve(
        recipeId: String,
        features: SceneFeatures,
        capabilities: DeviceCapabilities,
        context: SolveContext = .default,
        /// Phase 4 hook: residual offset learned from user corrections
        /// (`ExposureOffsetNet`), in stops. Clamped to ±1 EV by the caller.
        learnedEVOffset: Double = 0,
        /// Thermal `.critical`: the rules still pick the recipe (coaching and
        /// tips), but exposure stays on system auto — no custom shutter/ISO.
        forceSystemAutoExposure: Bool = false
    ) -> Solution {
        var solution = solveImpl(
            recipeId: recipeId,
            features: features,
            capabilities: capabilities,
            context: context,
            learnedEVOffset: learnedEVOffset
        )
        if forceSystemAutoExposure {
            solution.phoneTargets.exposureDurationSec = nil
            solution.phoneTargets.shutter = nil
            solution.phoneTargets.iso = nil
            solution.phoneTargets.ev = nil
            solution.targetEV = nil
            solution.clampMessages.append(
                "Thermal state critical — exposure left on system auto.")
        }
        return solution
    }

    private static func solveImpl(
        recipeId: String,
        features: SceneFeatures,
        capabilities: DeviceCapabilities,
        context: SolveContext,
        learnedEVOffset: Double
    ) -> Solution {
        // Reference card — no camera changes, coach only.
        if recipeId == "exposure-triangle-cheatsheet" {
            return Solution(
                phoneTargets: PhoneTargets(),
                coachOnly: CoachOnly(
                    aperture: nil, nd: nil, tripod: false,
                    notes: "Reference card — aperture, ISO, shutter speed. Change one, compensate with another."
                )
            )
        }

        let fovRad = context.fieldOfViewDegrees * .pi / 180
        let focalPx = (context.frameWidthPx / 2) / max(tan(fovRad / 2), 1e-6)
        let shake = max(Double(features.handShakeRadPerSec), 1e-4)
        /// Slowest shutter that keeps hand shake under ~1.5 px at full resolution.
        let tShake = 1.5 / (shake * focalPx)
        /// Shutter that freezes subject motion to ~1.5 px.
        let relSpeed = Double(features.subjectRelativeSpeedPxPerSec)
        let tMotion: Double = relSpeed > 50 ? 1.5 / relSpeed : .infinity
        let ev100 = features.sceneEV100
        let isDim = (ev100 ?? 99) < 7
        let isVeryDim = (ev100 ?? 99) < 2

        var targets = PhoneTargets()
        var messages: [String] = []
        var tips: [String] = []

        if isDim {
            tips.append("Low light — brace or use a tripod if shutter drops below 1/60s.")
        }
        if tShake < 1 / 60 {
            tips.append("Hand shake limits the shutter to ~\(RecipeCameraMapper.formatShutter(tShake)) — brace or use a tripod.")
        }

        /// Shared exposure solve via `ExposurePlanner`: `E_target` from the
        /// converged metered product, split into shutter × ISO by the
        /// recipe's priority. Shutter and ISO are never chosen independently
        /// of the metered exposure.
        func planExposure(
            priority: ExposurePlanner.Priority,
            targetEV: Double
        ) -> ExposurePlanner.Plan {
            let eAuto = (features.meteredExposureSeconds ?? 1 / 60)
                * Double(features.meteredISO ?? 100)
            let motion = ExposurePlanner.MotionContext(
                handShakeRadPerSec: max(Double(features.handShakeRadPerSec), 1e-4),
                frameWidthPx: context.frameWidthPx,
                fieldOfViewDegrees: context.fieldOfViewDegrees)
            let limits = ExposurePlanner.DeviceLimits(
                minShutterSeconds: capabilities.minExposureSeconds,
                maxShutterSeconds: capabilities.maxExposureSeconds,
                minISO: capabilities.minISO,
                maxISO: capabilities.maxISO)
            let plan = ExposurePlanner.plan(
                eAuto: eAuto, targetEV: targetEV, priority: priority,
                motion: motion, limits: limits, learnedEVOffset: learnedEVOffset)
            messages.append(contentsOf: plan.clampMessages)
            return plan
        }

        func setExposure(plan: ExposurePlanner.Plan) {
            targets.exposureDurationSec = plan.shutterSeconds
            targets.shutter = RecipeCameraMapper.formatShutter(plan.shutterSeconds)
            targets.iso = "\(Int(plan.iso.rounded()))"
            // Folded into the ISO above — applyPhoneTargets must skip setEV.
            targets.ev = String(format: "%+.1f", plan.targetEV)
        }

        let faceEV = Self.faceEVBias(features: features)
        let subjectCenter = features.subjectBox.map { CGPoint(x: CGFloat($0.centerX), y: CGFloat($0.centerY)) }

        switch recipeId {
        case "sharp-front-to-back":
            // Objective: longest motion-safe shutter first, then gain — so
            // ISO stays minimal. (.auto with the recipe's motion cap.)
            let shutter = min(tShake, tMotion)
            let ev: Float = features.highlightClipFraction > 0.02 ? -0.3 : 0
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(ev) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "locked"
            targets.focusPoint = FocusPointNorm(
                x: Double(subjectCenter?.x ?? 0.5), y: Double(subjectCenter?.y ?? 0.62))
            targets.whiteBalance = .mode("auto")
            if isVeryDim { targets.lowLightBoost = true }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: "f/11–f/16 (guidance)", nd: nil,
                    tripod: tShake < 1 / 200,
                    notes: "Phone aperture is fixed — use subject distance for DoF."
                ),
                apertureGuidance: "f/11–f/16 (guidance)", extraTips: tips
            )

        case "blur-moving-subjects":
            // Objective: t = targetBlurPx / subjectRelativeSpeed, ~4% frame width
            // of motion streak. Steady camera required.
            let targetBlurPx = 0.04 * context.frameWidthPx
            var shutter: Double
            if relSpeed > 1 {
                shutter = targetBlurPx / relSpeed
            } else {
                shutter = capabilities.maxExposureSeconds
                messages.append("No subject motion measured — using the longest shutter; re-aim at moving water or traffic.")
            }
            shutter = clamp(shutter, min: 1 / 250, max: capabilities.maxExposureSeconds)
            // Shutter priority: the blur streak is the recipe's objective —
            // hold it, report the residual when ISO clamps.
            let plan = planExposure(
                priority: .shutter(seconds: shutter),
                targetEV: learnedEVOffset)
            setExposure(plan: plan)
            // Lock focus on the static scene: the subject if it is static,
            // else frame center.
            let staticPoint: CGPoint = {
                if Double(features.subjectSpeedPxPerSec) < 50, let c = subjectCenter { return c }
                return CGPoint(x: 0.5, y: 0.45)
            }()
            targets.focusMode = "locked"
            targets.focusPoint = FocusPointNorm(x: Double(staticPoint.x), y: Double(staticPoint.y))
            let ndNote: String? = messages.contains(where: { $0.contains("Overexposed") })
                ? "ND filter — scene too bright for silky blur at base ISO" : nil
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: nil, nd: ndNote, tripod: true,
                    notes: "Tripod keeps the static world sharp while motion blurs."
                ),
                extraTips: tips
            )

        case "panning-sharp-subject":
            // Objective: t = targetStreakPx / cameraPanSpeed, ~6% frame width
            // of background streak. Unknown pan speed → 1/30.
            let panSpeed = Double(features.backgroundSpeedPxPerSec)
            let targetStreakPx = 0.06 * context.frameWidthPx
            var shutter = panSpeed > 50 ? targetStreakPx / panSpeed : 1 / 30
            shutter = clamp(shutter, min: 1 / 125, max: 1 / 8)
            // Shutter priority at 1/30 s (or the pan-derived streak): the pan
            // blur is the recipe's objective — hold it, report the residual.
            let plan = planExposure(
                priority: .shutter(seconds: shutter),
                targetEV: Double(faceEV) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "continuous"
            let c = subjectCenter ?? CGPoint(x: 0.5, y: 0.5)
            targets.focusPoint = FocusPointNorm(x: Double(c.x), y: Double(c.y))
            targets.monitorSubjectAreaChange = true
            let dir: String = abs(features.motionDirectionX) >= abs(features.motionDirectionY)
                ? "horizontal" : "vertical"
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: nil, nd: nil, tripod: false,
                    notes: "Rotate your body at the same speed as the subject."
                ),
                panCue: PanCue(direction: dir, note: "Pan with the subject"),
                extraTips: tips
            )

        case "hdr-brights-darks":
            // No custom exposure: auto with the exposure point on the subject.
            // Bracket stops from the measured percentile spread.
            let spread = features.percentileSpreadStops
            let stop: Double = spread > 10 ? 2 : spread >= 7 ? 1.3 : 1
            targets.bracket = BracketTarget(stops: [-stop, 0, stop], count: 3)
            targets.videoHDR = true
            targets.focusMode = "auto"
            let c = subjectCenter ?? CGPoint(x: 0.5, y: 0.5)
            targets.focusPoint = FocusPointNorm(x: Double(c.x), y: Double(c.y))
            // setEV is safe here: no custom exposure was written.
            targets.ev = String(format: "%+.1f", faceEV)
            if let gains = context.currentWBGains {
                targets.whiteBalance = .gains(redGain: gains.red, greenGain: gains.green, blueGain: gains.blue)
            }
            if isVeryDim { targets.lowLightBoost = true }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                coachOnly: CoachOnly(
                    aperture: "lock across brackets", nd: nil, tripod: true,
                    notes: "Tripod so frames align."
                ),
                extraTips: tips
            )

        case "get-down-low":
            // As sharp-front-to-back, then switch to the ultra-wide.
            let shutter = min(tShake, tMotion)
            let ev: Float = features.highlightClipFraction > 0.02 ? -0.3 : 0
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(ev) + learnedEVOffset)
            setExposure(plan: plan)
            targets.cameraDevice = "ultraWide"
            targets.focusMode = "auto"
            let c = subjectCenter ?? CGPoint(x: 0.5, y: 0.7)
            targets.focusPoint = FocusPointNorm(x: Double(c.x), y: Double(c.y))
            targets.whiteBalance = .mode("auto")
            if isVeryDim { targets.lowLightBoost = true }
            messages.append("Exposure re-checked after the ultra-wide switch (verify read-back).")
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: nil, nd: nil, tripod: false,
                    notes: "Widest angle; the foreground becomes the main subject."
                ),
                panCue: PanCue(direction: "down", note: "Drop lower"),
                extraTips: tips
            )

        case "portrait-pop":
            // Face → exposure point on the face/eyes, locked focus, 2× zoom.
            let shutter = min(tShake, tMotion)
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(faceEV) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "locked"
            targets.focusPoint = FocusPointNorm(x: Double(eyePoint(features: features).x),
                                                y: Double(eyePoint(features: features).y))
            targets.zoom = 2.0
            targets.simulatedAperture = 1.8 // coach-only on fixed phone lenses
            if isVeryDim {
                targets.torch = TorchTarget(mode: "off") // no deer-in-headlights; boost instead
                targets.lowLightBoost = true
            } else if isDim {
                targets.lowLightBoost = true
            }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: "f/1.8 wide open (guidance — use Portrait mode)",
                    nd: nil, tripod: false,
                    notes: "Zoom 2×, focus on the eyes, verify sharpness by zooming in tight after the shot."
                ),
                extraTips: tips
            )

        case "sharp-and-in-focus":
            // Single-point focus locked on the subject (eyes for people).
            let shutter = min(tShake, tMotion)
            let ev: Float = features.highlightClipFraction > 0.02 ? -0.3 : faceEV
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(ev) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "locked"
            let p = eyePoint(features: features)
            targets.focusPoint = FocusPointNorm(x: Double(p.x), y: Double(p.y))
            if isVeryDim { targets.lowLightBoost = true }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: "high f-stop for more in focus (guidance)",
                    nd: nil, tripod: false,
                    notes: "Single-point focus locked on the subject — tap to move it if the camera picked the wrong element."
                ),
                extraTips: tips
            )

        case "leading-lines":
            // Deep focus so lines stay sharp foreground → background.
            let shutter = min(tShake, tMotion)
            let ev: Float = features.highlightClipFraction > 0.02 ? -0.3 : faceEV
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(ev) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "locked"
            let c = subjectCenter ?? CGPoint(x: 0.5, y: 0.5)
            targets.focusPoint = FocusPointNorm(x: Double(c.x), y: Double(c.y))
            targets.simulatedAperture = 11 // coach-only: deep focus keeps lines sharp
            if isVeryDim { targets.lowLightBoost = true }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: "f/11 deep focus (guidance)", nd: nil, tripod: false,
                    notes: "Turn on the thirds grid; lines should start in the foreground and point at the subject."
                ),
                apertureGuidance: "f/11 (guidance)", extraTips: tips
            )

        case "minimalist-photos":
            // Expose for mood: slight underexposure keeps blue-hour scenes moody.
            let shutter = min(tShake, tMotion)
            let ev: Float = (features.sceneEV100 ?? 99) < 8 ? -0.3 : faceEV
            let plan = planExposure(
                priority: .auto(shutterCapSeconds: shutter),
                targetEV: Double(ev) + learnedEVOffset)
            setExposure(plan: plan)
            targets.focusMode = "locked"
            let c = subjectCenter ?? CGPoint(x: 0.5, y: 0.5)
            targets.focusPoint = FocusPointNorm(x: Double(c.x), y: Double(c.y))
            if isVeryDim { targets.lowLightBoost = true }
            return Solution(
                phoneTargets: targets, clampMessages: messages,
                targetEV: plan.targetEV,
                coachOnly: CoachOnly(
                    aperture: nil, nd: nil, tripod: false,
                    notes: "Thirds grid on; one subject on a third line; blue hour (30 min after sunset) is ideal."
                ),
                extraTips: tips
            )

        default:
            // Unknown id — treat as sharp-front-to-back (server fallback agrees).
            var fallback = solve(recipeId: "sharp-front-to-back", features: features,
                                 capabilities: capabilities, context: context,
                                 learnedEVOffset: learnedEVOffset)
            fallback.extraTips = tips + fallback.extraTips
            return fallback
        }
    }

    // MARK: - helpers

    /// Focus point for eye-critical recipes: nudge the face-box center up to
    /// the eyes; otherwise the subject center; otherwise frame center.
    static func eyePoint(features: SceneFeatures) -> CGPoint {
        if features.subjectKind == .face, let box = features.subjectBox {
            return CoordinateSpaces.clamp01(CGPoint(x: CGFloat(box.centerX), y: CGFloat(box.centerY) - 0.07))
        }
        if let box = features.subjectBox {
            return CGPoint(x: CGFloat(box.centerX), y: CGFloat(box.centerY))
        }
        return CGPoint(x: 0.5, y: 0.5)
    }

    /// +EV when the face region is > 1.5 stops darker than the frame median
    /// (backlit face), folded into the ISO solve — never via `setEV`.
    static func faceEVBias(features: SceneFeatures) -> Float {
        guard features.subjectKind == .face else { return 0 }
        if let d = features.subjectDeltaStops, d < -1.5 { return 0.7 }
        if features.highlightClipFraction > 0.05 { return 0.7 }
        if (features.sceneEV100 ?? 99) < 8 { return 0.3 }
        return 0
    }

    private static func clamp<T: Comparable>(_ v: T, min: T, max: T) -> T {
        Swift.min(Swift.max(v, min), max)
    }
}
