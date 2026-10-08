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
        /// `min(tShake, tMotion)`); when nil the planner derives the cap from
        /// the 1/(2f) handheld rule and the gyro motion limit.
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
        /// `log2(E_target / achieved)`: + means under, − means over.
        var residualEV: Double
        var clamped: Bool
        var clampMessages: [String]
    }

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
    static func motionLimitSeconds(
        handShakeRadPerSec: Double,
        frameWidthPx: Double,
        fieldOfViewDegrees: Double,
        blurBudgetPx: Double = 1.0
    ) -> Double {
        let fovRad = max(fieldOfViewDegrees, 1) * .pi / 180
        let focalPx = (frameWidthPx / 2) / max(tan(fovRad / 2), 1e-6)
        let omega = max(abs(handShakeRadPerSec), 1e-4)
        return blurBudgetPx / (omega * focalPx)
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
            let shutter = clamp(
                seconds,
                min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            let iso = clamp(
                Float(eTarget / shutter), min: limits.minISO, max: limits.maxISO)
            return finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits)
        case .iso(let value):
            let iso = clamp(value, min: limits.minISO, max: limits.maxISO)
            let shutter = clamp(
                eTarget / Double(iso),
                min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            return finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits)
        case .auto(let cap):
            let derivedCap = min(
                handheldLimitSeconds(fieldOfViewDegrees: motion.fieldOfViewDegrees),
                motionLimitSeconds(
                    handShakeRadPerSec: motion.handShakeRadPerSec,
                    frameWidthPx: motion.frameWidthPx,
                    fieldOfViewDegrees: motion.fieldOfViewDegrees)
            )
            let safeCap = cap ?? derivedCap
            var shutter = min(
                safeCap, max(eTarget / Double(limits.minISO), limits.minShutterSeconds))
            shutter = clamp(
                shutter, min: limits.minShutterSeconds, max: limits.maxShutterSeconds)
            let iso = clamp(
                Float(eTarget / shutter), min: limits.minISO, max: limits.maxISO)
            return finish(
                shutter: shutter, iso: iso, eTarget: eTarget,
                targetEV: targetEV, limits: limits)
        }
    }

    // MARK: - Private

    private static func finish(
        shutter: Double,
        iso: Float,
        eTarget: Double,
        targetEV: Double,
        limits: DeviceLimits
    ) -> Plan {
        let achieved = shutter * Double(iso)
        let residual = log2(eTarget / max(achieved, 1e-12))
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
            clamped: clamped, clampMessages: messages)
    }

    /// Truthful copy for unreachable targets — the UI must say what couldn't
    /// be reached, not silently underexpose.
    private static func clampMessage(
        residualEV: Double,
        shutter: Double,
        iso: Float,
        limits: DeviceLimits
    ) -> String {
        let stops = String(format: "%.1f", abs(residualEV))
        if residualEV > 0 {
            // Underexposed: E_target unreachable from below.
            if shutter >= limits.maxShutterSeconds {
                return "Max shutter \(RecipeCameraMapper.formatShutter(limits.maxShutterSeconds))" +
                    " on this lens — \(stops) stops short; tripod + Night mode recommended."
            }
            return "Underexposed at max ISO — add light or accept a darker frame."
        }
        // Overexposed: E_target unreachable from above.
        if iso <= limits.minISO {
            return "Overexposed ~\(stops) stops at min ISO — scene too bright for this shutter."
        }
        return "Overexposed ~\(stops) stops at the fastest shutter — scene too bright."
    }

    private static func clamp<T: Comparable>(_ v: T, min: T, max: T) -> T {
        Swift.min(Swift.max(v, min), max)
    }
}
