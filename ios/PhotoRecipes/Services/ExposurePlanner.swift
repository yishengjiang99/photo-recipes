import Foundation

/// Closed-loop exposure planner (Phase 1 of the Auto Optimize upgrade).
///
/// Pure module: **no AVFoundation types in the API** — plain Doubles/Floats
/// in, a plan out. The caller (`SettingsSolver`) supplies the metered
/// exposure product `E_auto` measured from a *converged* auto-exposure state
/// (see `CameraSession.convergeAutoExposure`), so the plan is anchored to the
/// metered light level — not to the tone-mapped probe brightness, which the
/// system AE has already normalized toward mid-gray.
///
/// Math: `E_target = E_auto × 2^targetEV`, then the recipe's priority splits
/// `E_target` into shutter × ISO within the device limits. When clamping
/// makes `E_target` unreachable, the residual (in EV) is reported in
/// `clampMessages` with truthful copy — never a silent miss.
///
/// The shutter/gain split mirrors the reference framework's `plan()`
/// (`scripts/camera-settings/camera_settings_framework.py`): prefer the
/// longest motion-safe shutter (less noise), then add gain.
enum ExposurePlanner {

    // MARK: - Inputs

    /// Device exposure limits (mapped from `DeviceCapabilities` by the caller).
    struct DeviceLimits {
        var minShutterSeconds: Double
        var maxShutterSeconds: Double
        var minISO: Float
        var maxISO: Float
    }

    /// Motion context for the safe-shutter computation.
    struct MotionContext {
        /// Gyro hand-shake magnitude, rad/s.
        var handShakeRadPerSec: Double
        /// Reference frame width, px (the width motion speeds are expressed in).
        var frameWidthPx: Double
        /// Active-format field of view, degrees. Treated as the horizontal
        /// FOV, matching the solver's px/rad conversions.
        var fieldOfViewDegrees: Double
        /// True when the gyro stayed < 0.005 rad/s for ≥ 1.5 s (tripod) —
        /// the shake-derived limits are dropped and the shutter may run to
        /// the device max.
        var isTripodSteady: Bool = false
    }

    /// How the recipe wants `E_target` split into shutter × ISO.
    enum Priority {
        /// Fixed shutter (motion-blur / pan objectives). ISO floats to hold
        /// `E_target`; when ISO clamps, the residual EV is reported instead
        /// of silently missing the exposure.
        case shutter(seconds: Double)
        /// Lowest ISO first: pin ISO, solve shutter from `E_target`
        /// (`shutter = clamp(E_target / iso)`).
        case iso(value: Float)
        /// Longest motion-safe shutter first, then gain. `shutterCapSeconds`
        /// lets the recipe pass its own motion objective (e.g. the solver's
        /// `min(tShake, tMotion)`); it can only *shorten* the shutter — the
        /// planner always also applies the 1/(2f) handheld limit and the gyro
        /// motion limit, and the recipe cap never overrides them. When nil
        /// the planner derives the cap from those two limits alone.
        /// Tripod-steady (`MotionContext.isTripodSteady`) drops the
        /// shake-derived limits: the shutter may run to the device max,
        /// bounded only by the recipe cap.
        case auto(shutterCapSeconds: Double? = nil)
        /// Keep system auto exposure (HDR): no custom shutter/ISO is written;
        /// brackets are relative to the converged `E_auto`.
        case systemAuto
    }

    // MARK: - Output

    struct Plan {
        /// False for `.systemAuto` — the caller must not write custom exposure.
        var useCustomExposure: Bool
        var shutterSeconds: Double
        var iso: Float
        /// The composed offset this plan targets (recipe + face + learned).
        var targetEV: Double
        /// `log2(achieved / E_target)`: + means brighter than target (over),
        /// − means under. Same sign convention as the verify residual.
        var residualEV: Double
        var clamped: Bool
        var clampMessages: [String]
        /// The effective shutter cap applied for `.auto` (nil for other
        /// priorities) — consumed by the verify step via
        /// `SettingsSolver.Solution.shutterCapSeconds`.
        var shutterCapSeconds: Double? = nil
        /// Set when `.shutter` priority had to shorten the recipe's shutter
        /// because min ISO still overexposed it (bright light, no ND): the
        /// shutter the recipe wanted. `shutterSeconds` holds the one used.
        var yieldedFromShutterSeconds: Double? = nil
    }

    /// Overexposure (in EV) tolerated at min ISO before a creative shutter
    /// yields to correct exposure.
    static let overexposureToleranceEV = 0.3

    // MARK: - Safe-shutter limits

    /// 1 / (2 × 35mm-equivalent focal length). The 35mm-equiv focal length is
    /// derived from the (horizontal) field of view against the 36 mm-wide
    /// full-frame reference: `f_35 = 18 / tan(fov/2)`.
    static func handheldLimitSeconds(fieldOfViewDegrees: Double) -> Double {
        let fovRad = max(fieldOfViewDegrees, 1) * .pi / 180
        let focal35mm = 18 / max(tan(fovRad / 2), 1e-6)
        return 1 / (2 * focal35mm)
    }

    /// Slowest shutter keeping hand shake under `blurBudgetPx` px:
    /// `blurBudgetPx / (|ω| × focalLengthPx)` with
    /// `focalLengthPx = (width/2) / tan(fov/2)`.
    ///
    /// A zero/negative gyro reading means the sensor was unavailable — it is
    /// NOT "perfectly still" (that would balloon the cap to many seconds).
    /// `effectiveShakeRadPerSec` substitutes 0.03 rad/s typical handheld.
    static func motionLimitSeconds(
        handShakeRadPerSec: Double,
        frameWidthPx: Double,
        fieldOfViewDegrees: Double,
        blurBudgetPx: Double = 1.0
    ) -> Double {
        let fovRad = max(fieldOfViewDegrees, 1) * .pi / 180
        let focalPx = (frameWidthPx / 2) / max(tan(fovRad / 2), 1e-6)
        let omega = max(effectiveShakeRadPerSec(handShakeRadPerSec), 1e-4)
        return blurBudgetPx / (omega * focalPx)
    }

    /// Nil/unavailable gyro reads as 0 — treat it as 0.03 rad/s typical
    /// handheld, never as zero.
    static func effectiveShakeRadPerSec(_ raw: Double) -> Double {
        let mag = abs(raw)
        return mag > 0 ? mag : 0.03
    }

    // MARK: - Plan

    /// Splits `E_target = E_auto × 2^targetEV` into shutter × ISO per `priority`.
    ///
    /// - Parameters:
    ///   - eAuto: metered exposure product from the converged AE state
    ///     (`exposureSeconds × iso`).
    ///   - targetEV: fully composed offset in stops — recipe EV offset + face
    ///     EV offset + `learnedEVOffset` (the Phase 4 hook, folded in by the
    ///     caller, i.e. `SettingsSolver`).
    static func plan(
        eAuto: Double,
        targetEV: Double,
        priority: Priority,
        motion: MotionContext,
        limits: DeviceLimits
    ) -> Plan {
        let eTarget = max(eAuto, 1e-9) * pow(2, targetEV)
        switch priority {
        case .systemAuto:
            return Plan(
                useCustomExposure: false, shutterSeconds: 0, iso: 0,
                targetEV: targetEV, residualEV: 0,
                clamped: false, clampMessages: []
            )
        case .shutter(let seconds):
            var shutter = clamp(
                seconds,
                min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            let iso = clamp(
                Float(eTarget / shutter), min: limits.minISO, max: limits.maxISO)
            // Correct exposure is a hard constraint; the creative shutter is a
            // soft objective. A phone has no aperture or ND, so when even min
            // ISO overexposes at the recipe's shutter, shorten the shutter to
            // the slowest correctly exposed one. Never lengthen it to fix
            // underexposure — that stays a reported residual.
            var wantedShutter: Double? = nil
            let overEV = log2(max(shutter * Double(iso), 1e-12) / eTarget)
            if overEV > overexposureToleranceEV {
                wantedShutter = shutter
                shutter = clamp(
                    eTarget / Double(iso),
                    min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            }
            var plan = finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits)
            if let wanted = wantedShutter {
                plan.yieldedFromShutterSeconds = wanted
                plan.clampMessages.append(
                    "Bright light: used \(RecipeCameraMapper.formatShutter(shutter))" +
                    " instead of \(RecipeCameraMapper.formatShutter(wanted))" +
                    " — shade or an ND filter keeps the effect.")
            }
            return plan
        case .iso(let value):
            let iso = clamp(value, min: limits.minISO, max: limits.maxISO)
            let shutter = clamp(
                eTarget / Double(iso),
                min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            return finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits)
        case .auto(let cap):
            let handheldLimit = handheldLimitSeconds(
                fieldOfViewDegrees: motion.fieldOfViewDegrees)
            let gyroLimit = motionLimitSeconds(
                handShakeRadPerSec: motion.handShakeRadPerSec,
                frameWidthPx: motion.frameWidthPx,
                fieldOfViewDegrees: motion.fieldOfViewDegrees)
            let safeCap: Double
            var tripodNote: String? = nil
            if motion.isTripodSteady {
                // Tripod: drop the shake-derived limits — the recipe's own
                // motion cap and the device max shutter still bound the
                // exposure.
                let derivedCap = min(handheldLimit, gyroLimit)
                safeCap = min(cap ?? .infinity, limits.maxShutterSeconds)
                if safeCap > derivedCap {
                    tripodNote = "Tripod detected — long shutter"
                }
            } else {
                // The recipe cap can only shorten the shutter: it never
                // overrides the derived handheld/motion limits.
                safeCap = min(min(cap ?? .infinity, handheldLimit), gyroLimit)
            }
            var shutter = min(
                safeCap, max(eTarget / Double(limits.minISO), limits.minShutterSeconds))
            shutter = clamp(
                shutter, min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            let iso = clamp(
                Float(eTarget / shutter), min: limits.minISO, max: limits.maxISO)
            var plan = finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits, shutterCapSeconds: safeCap)
            if let note = tripodNote { plan.clampMessages.append(note) }
            return plan
        }
    }

    // MARK: - Private

    private static func finish(
        shutter: Double,
        iso: Float,
        eTarget: Double,
        targetEV: Double,
        limits: DeviceLimits,
        shutterCapSeconds: Double? = nil
    ) -> Plan {
        let achieved = shutter * Double(iso)
        // + means the achieved exposure is BRIGHTER than target (over).
        let residual = log2(max(achieved, 1e-12) / eTarget)
        var messages: [String] = []
        var clamped = false
        if abs(residual) > 0.05 {
            clamped = true
            messages.append(clampMessage(
                residualEV: residual, shutter: shutter, iso: iso, limits: limits))
        }
        return Plan(
            useCustomExposure: true, shutterSeconds: shutter, iso: iso,
            targetEV: targetEV, residualEV: residual,
            clamped: clamped, clampMessages: messages,
            shutterCapSeconds: shutterCapSeconds)
    }

    /// Truthful copy for unreachable targets — the UI must say what couldn't
    /// be reached, not silently underexpose.
    ///
    /// Sign convention (matches the verify residual): + means the achieved
    /// exposure is brighter than target (over), − means under.
    private static func clampMessage(
        residualEV: Double,
        shutter: Double,
        iso: Float,
        limits: DeviceLimits
    ) -> String {
        let stops = String(format: "%.1f", abs(residualEV))
        if residualEV > 0 {
            // Overexposed: achieved E exceeds the target.
            if iso <= limits.minISO {
                return "Overexposed ~\(stops) stops at min ISO — scene too bright for this shutter."
            }
            return "Overexposed ~\(stops) stops at the fastest shutter — scene too bright."
        }
        // Underexposed: E_target unreachable from below.
        if shutter >= limits.maxShutterSeconds {
            return "Max shutter \(RecipeCameraMapper.formatShutter(limits.maxShutterSeconds))" +
                " on this lens — \(stops) stops short; tripod + Night mode recommended."
        }
        return "Underexposed at max ISO — add light or accept a darker frame."
    }

    private static func clamp<T: Comparable>(_ v: T, min: T, max: T) -> T {
        Swift.min(Swift.max(v, min), max)
    }
}
