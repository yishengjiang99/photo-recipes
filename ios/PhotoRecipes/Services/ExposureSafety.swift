import Foundation

// P0 (TestFlight build 78): front-camera Auto Optimize turned a dim-but-visible
// selfie preview almost black, locked AE/AF, turned the flash on and said
// "Brightened 5 stops". These pure policies are the safety rails that stop that
// class of failure. No AVFoundation types — every rule is unit-tested.

// MARK: - (a) Clamp every custom write to the CURRENT device's active format

/// Clamps a custom shutter/ISO write to the limits of the device that will
/// receive it. Callers pass the live `device.activeFormat` ranges — never the
/// published `DeviceCapabilities`, which lag a camera flip / format change by a
/// main-actor hop (a back-camera 1/16000 s or ISO 50 written to the front
/// camera clamps differently than intended, and the AV call throws on
/// out-of-range values).
enum ExposureClamp {
    struct Result: Equatable {
        var durationSeconds: Double
        var iso: Float
        var clamped: Bool
    }

    static func clamp(
        durationSeconds: Double,
        iso: Float,
        limits: ExposurePlanner.DeviceLimits
    ) -> Result {
        let lo = limits.minShutterSeconds.isFinite && limits.minShutterSeconds > 0 ? limits.minShutterSeconds : 1.0 / 8000
        let hiRaw = limits.maxShutterSeconds.isFinite && limits.maxShutterSeconds > 0 ? limits.maxShutterSeconds : 1.0
        let hi = max(hiRaw, lo)
        let isoLo = limits.minISO.isFinite && limits.minISO > 0 ? limits.minISO : 25
        let isoHiRaw = limits.maxISO.isFinite && limits.maxISO > 0 ? limits.maxISO : 3200
        let isoHi = max(isoHiRaw, isoLo)
        let d0 = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : lo
        let i0 = iso.isFinite && iso > 0 ? iso : isoLo
        let d = min(max(d0, lo), hi)
        let i = min(max(i0, isoLo), isoHi)
        return Result(durationSeconds: d, iso: i, clamped: d != durationSeconds || i != iso)
    }
}

// MARK: - (a) Front camera: EV bias, not custom shutter/ISO, in low light

enum FrontExposurePolicy {
    /// EV100 below which a front-camera scene counts as dim.
    static let dimEV100: Float = 7
    /// Planner residual (stops, − = under) that already means "darker than auto".
    static let maxPlanUnderStops = -0.3
    /// Largest face lift programmed as exposure-target bias on the front camera.
    static let maxBias: Float = 1.0

    /// True when the front camera must stay on system auto exposure (+ EV bias)
    /// instead of a custom shutter/ISO write. The system AE on the front camera
    /// uses long frame durations and ISP gain a custom write can't reach — the
    /// selfie shutter cap (1/60 s) plus the format's max ISO left a dim room
    /// ~5 stops under auto.
    static func useSystemAuto(
        isFront: Bool,
        sceneEV100: Float?,
        planResidualEV: Double?,
        plannedShutterSeconds: Double?,
        meteredShutterSeconds: Double?
    ) -> Bool {
        guard isFront else { return false }
        if let ev = sceneEV100, ev.isFinite, ev < dimEV100 { return true }
        if let r = planResidualEV, r.isFinite, r < maxPlanUnderStops { return true }
        // A shorter shutter than auto metered on a front camera is the
        // "darker than auto" setup even when ISO nominally covers it.
        if let planned = plannedShutterSeconds, let metered = meteredShutterSeconds,
           planned > 0, metered > 0, planned < metered * 0.7 { return true }
        return false
    }

    /// Bias string for the front camera's system-auto path (never negative in the
    /// dark: a selfie should never come out darker than auto).
    static func biasString(targetEV: Double?, dark: Bool) -> String {
        let raw = Float(targetEV ?? 0)
        let lo: Float = dark ? 0 : -maxBias
        let b = min(max(raw.isFinite ? raw : 0, lo), maxBias)
        return String(format: "%+.1f", b)
    }
}

// MARK: - (b) Post-apply darkening guard

/// After AO applies, compare what the frame looks like now with what auto
/// exposure gave before. Darker by more than ~1 stop than intended, or near
/// black → revert to continuous auto, unlock, and say so honestly.
enum ExposureSafetyGuard {
    /// Allowed darkening beyond the plan's own (negative) target, in stops.
    static let maxExtraDarkeningStops = 1.0
    /// Mean preview luma (0…1, gamma-encoded) treated as near-black.
    static let nearBlackLuma = 0.06
    /// `exposureTargetOffset` (custom mode) at or below this is near-black.
    static let nearBlackOffset: Double = -2.5
    /// Approximate display gamma: stops = gamma × log2(luma ratio).
    static let gamma = 2.2

    struct Measurement: Equatable {
        /// Converged auto-exposure product (s × ISO) before the apply.
        var eAutoBefore: Double?
        /// Exposure product read back after the apply.
        var eAfter: Double?
        /// `exposureTargetOffset` read back after the apply (custom mode: how far
        /// the frame sits from the meter's target; − = darker).
        var offsetAfter: Double?
        /// Mean preview luma before / after (0…1), when frames were available.
        var lumaBefore: Double?
        var lumaAfter: Double?
        /// The plan's intended offset vs auto (e.g. −0.3 for a moody recipe).
        var targetEV: Double = 0
    }

    enum Verdict: Equatable {
        case ok
        case revert(darkenedStops: Double, nearBlack: Bool)
    }

    /// Stops between two gamma-encoded luma means (− = darker).
    static func lumaStops(before: Double, after: Double) -> Double? {
        guard before.isFinite, after.isFinite, before > 0.002 else { return nil }
        return gamma * log2(max(after, 0.001) / before)
    }

    static func evaluate(_ m: Measurement) -> Verdict {
        var darkenings: [Double] = []
        if let a = m.eAutoBefore, let b = m.eAfter, a > 0, b > 0, a.isFinite, b.isFinite {
            darkenings.append(log2(b / a))
        }
        if let o = m.offsetAfter, o.isFinite {
            // In custom mode the offset is the frame vs the auto target, already relative.
            darkenings.append(o)
        }
        if let lb = m.lumaBefore, let la = m.lumaAfter, let s = lumaStops(before: lb, after: la) {
            darkenings.append(s)
        }
        let worst = darkenings.min() ?? 0
        let nearBlack = (m.lumaAfter.map { $0 < nearBlackLuma && ($0 < (m.lumaBefore ?? 1)) } ?? false)
            || (m.offsetAfter.map { $0 <= nearBlackOffset } ?? false)
        let allowed = min(m.targetEV.isFinite ? m.targetEV : 0, 0) - maxExtraDarkeningStops
        if nearBlack || worst < allowed {
            return .revert(darkenedStops: worst, nearBlack: nearBlack)
        }
        return .ok
    }

    /// Honest status after a revert — never "Brightened".
    static func revertMessage(_ verdict: Verdict) -> String? {
        guard case .revert(let stops, let nearBlack) = verdict else { return nil }
        if nearBlack {
            return "Too dark here for custom exposure — kept auto exposure"
        }
        let n = max(1, Int(abs(stops).rounded()))
        return "Custom exposure came out ~\(n) \(n == 1 ? "stop" : "stops") darker — kept auto exposure"
    }
}

// MARK: - (c) Session restart never restores a locked / custom exposure

enum SessionRestartPolicy {
    enum ExposureMode: Equatable { case continuousAuto, custom, locked, autoExpose }
    enum FocusMode: Equatable { case continuousAuto, locked, autoFocus }

    struct State: Equatable {
        var exposureMode: ExposureMode
        var focusMode: FocusMode
        var exposureBias: Float
        var exposureLocked: Bool
        var focusLocked: Bool
    }

    /// The state the device is put in on every (re)start, whatever came before:
    /// continuous AE/AF, zero bias, nothing locked.
    static func stateAfterRestart(previous: State) -> State {
        State(exposureMode: .continuousAuto, focusMode: .continuousAuto,
              exposureBias: 0, exposureLocked: false, focusLocked: false)
    }
}

// MARK: - (e) Front flash

enum FrontFlashPolicy {
    /// The flash mode AO may program. Back camera: unchanged. Front camera: the
    /// flash is only ever turned ON for the selfie Low Light look, and only when
    /// the photo output supports a front (Retina) flash. Every other front look —
    /// e.g. a server / LookSuggester "Cool Blue" — gets no flash write.
    static func resolve(
        requested: String?,
        isFront: Bool,
        finalLookId: String?,
        retinaFlashSupported: Bool
    ) -> String? {
        guard isFront else { return requested }
        guard let requested else { return nil }
        let mode = requested.lowercased()
        if mode == "off" { return "off" }
        guard finalLookId == "selfieLowLight", retinaFlashSupported else { return nil }
        return requested
    }
}

// MARK: - (d) Look precedence with the async cloud refine

enum LookPrecedence {
    /// Whether a late (Pass 2 / server) look may be applied after Pass 1.
    /// Front camera: the selfie policy's decision is final — no server look
    /// replaces or fills in after it, unless the look is forced. Back camera:
    /// the existing fill-an-empty-finder rule.
    static func serverLookMayApply(
        isFront: Bool,
        forced: Bool,
        runIsCurrent: Bool,
        activeLookPresent: Bool
    ) -> Bool {
        guard runIsCurrent else { return false }
        if forced { return true }
        if isFront { return false }
        return !activeLookPresent
    }
}
