import CoreMedia
import Foundation

/// Test seam for the closed-loop exposure verify (A1).
///
/// Production (`CameraSession`) issues real `setExposureModeCustom` writes;
/// tests inject a fake device. The seam models the four steps the loop needs:
/// issue-write → await sync → settle → read offset.
@MainActor
protocol ExposureWriteClock: AnyObject {
    /// Issues a custom-exposure write. Returns the completion handler's
    /// syncTime, or `.invalid` when the write couldn't be issued.
    func issueWrite(durationSeconds: Double, iso: Float) async -> CMTime
    /// Waits for the meter to reflect a write. Production waits
    /// `2 × max(activeVideoMaxFrameDuration, exposureDuration)`, ≤ 1.2 s.
    func settleAfterWrite(exposureDurationSeconds: Double) async
    /// Meter reading (`exposureTargetOffset`) while custom exposure is held;
    /// nil when it isn't (nothing to verify).
    func readExposureOffset() -> Float?
    /// The currently programmed exposure — the base for correction math.
    func currentExposure() -> (shutterSeconds: Double, iso: Float)
    /// Device limits, for clamping corrections.
    var isoRange: ClosedRange<Float> { get }
    var shutterRange: ClosedRange<Double> { get }
}

/// Closed-loop exposure verify + correct, in testable form (A1/A6).
///
/// The loop behind `CameraSession.verifyExposure`, extracted so unit tests can
/// drive it with a fake `ExposureWriteClock`. Invariants the tests pin:
/// one write per iteration, every read happens after the matching write's
/// sync, and the loop converges without overshooting.
@MainActor
enum ExposureVerifyLoop {

    struct Result {
        /// Final `offset − targetEV`, in stops.
        var residualEV: Double
        /// Correction writes issued.
        var iterations: Int
        /// True when a device limit (or the priority policy) clamped a correction.
        var clamped: Bool
        /// Error measured before any correction, in stops.
        var initialError: Double
        /// False when custom exposure wasn't held — nothing was verified.
        var verified: Bool
    }

    /// The full exposure a correction step writes.
    struct Correction {
        var shutterSeconds: Double
        var iso: Float
        var clamped: Bool
    }

    /// Runs the verify loop against `clock`.
    ///
    /// - Parameters:
    ///   - targetEV: composed exposure offset the plan targets, in stops.
    ///   - priority: recipe priority for the correction policy (A6).
    ///   - shutterCapSeconds: longest shutter the loop may move to under
    ///     `.auto` priority; nil = device limits only.
    ///   - maxIterations: maximum correction writes.
    static func run(
        targetEV: Double,
        priority: ExposurePlanner.Priority?,
        shutterCapSeconds: Double?,
        maxIterations: Int = 2,
        clock: ExposureWriteClock
    ) async -> Result {
        // The write that preceded verify (applyPhoneTargets awaited it, and
        // verifyExposure awaited any in-flight write); the meter still lags
        // ~2 frames after the sync time, so settle before the first read.
        let start = clock.currentExposure()
        await clock.settleAfterWrite(exposureDurationSeconds: start.shutterSeconds)

        var iterations = 0
        var clamped = false
        var error = readStableError(targetEV: targetEV, clock: clock)
        let initialError = error ?? 0
        while let e = error, abs(e) > 0.3, iterations < maxIterations, !Task.isCancelled {
            let current = clock.currentExposure()
            let target = correctionTarget(
                error: e, priority: priority, shutterCapSeconds: shutterCapSeconds,
                currentShutterSeconds: current.shutterSeconds, currentISO: current.iso,
                isoRange: clock.isoRange, shutterRange: clock.shutterRange)
            // No progress possible (already at the limits/policy edge) —
            // don't burn another write on an identical one.
            guard abs(target.shutterSeconds - current.shutterSeconds) > 1e-9
                    || abs(Double(target.iso - current.iso)) > 1e-6 else {
                clamped = true
                break
            }
            _ = await clock.issueWrite(durationSeconds: target.shutterSeconds, iso: target.iso)
            clamped = target.clamped || clamped
            iterations += 1
            await clock.settleAfterWrite(exposureDurationSeconds: target.shutterSeconds)
            error = readStableError(targetEV: targetEV, clock: clock)
        }
        return Result(
            residualEV: error ?? 0, iterations: iterations,
            clamped: clamped, initialError: initialError,
            verified: error != nil)
    }

    /// Meter read with a stability gate: two consecutive readings must agree
    /// within 0.1 EV before the read is accepted; on disagreement the latest
    /// reading wins (the meter is still converging — the loop re-checks after
    /// the next settle anyway).
    private static func readStableError(targetEV: Double, clock: ExposureWriteClock) -> Double? {
        guard let first = clock.readExposureOffset() else { return nil }
        guard let second = clock.readExposureOffset() else { return Double(first) - targetEV }
        if abs(Double(second - first)) <= 0.1 {
            return (Double(first) + Double(second)) / 2 - targetEV
        }
        return Double(second) - targetEV
    }

    /// One correction step for `error` (`offset − targetEV`, in stops).
    ///
    /// A6 policy:
    /// - `.shutter`: the shutter is the recipe's creative objective — ISO
    ///   only. When ISO clamps, clamp it and report the residual (`clamped`);
    ///   the shutter is never touched.
    /// - `.auto`: ISO first; when ISO clamps the shutter may move but never
    ///   beyond `shutterCapSeconds` (the recipe's motion cap; nil = device
    ///   limits, i.e. the historical behavior).
    /// - `.iso` / nil: historical ISO-first-then-shutter — when ISO clamps,
    ///   move the shutter within device limits to hold the exposure product.
    ///   Documented choice: with no creative shutter objective to protect,
    ///   holding the exposure via shutter beats leaving a residual.
    /// - `.systemAuto`: never write (verify only runs on custom exposure);
    ///   report clamped.
    ///
    /// Sign convention: `factor = 2^(−error)` is kept exactly as the Phase 1
    /// code had it. The device polarity of `exposureTargetOffset` is owned by
    /// the A7 sign-convention fix — do not flip the sign here.
    static func correctionTarget(
        error: Double,
        priority: ExposurePlanner.Priority?,
        shutterCapSeconds: Double?,
        currentShutterSeconds: Double,
        currentISO: Float,
        isoRange: ClosedRange<Float>,
        shutterRange: ClosedRange<Double>
    ) -> Correction {
        // A7 owns the sign convention; kept as Phase 1 wrote it.
        let factor = pow(2.0, -error)
        let wantISO = currentISO * Float(factor)
        let clampedISO = min(max(wantISO, isoRange.lowerBound), isoRange.upperBound)
        let isoClamped = clampedISO != wantISO

        switch priority {
        case .shutter:
            return Correction(
                shutterSeconds: currentShutterSeconds, iso: clampedISO,
                clamped: isoClamped)
        case .auto:
            guard isoClamped else {
                return Correction(
                    shutterSeconds: currentShutterSeconds, iso: clampedISO,
                    clamped: false)
            }
            let cap = min(shutterCapSeconds ?? .infinity, shutterRange.upperBound)
            let wantShutter = currentShutterSeconds * factor
            let finalShutter = min(max(min(wantShutter, cap), shutterRange.lowerBound), shutterRange.upperBound)
            return Correction(
                shutterSeconds: finalShutter, iso: clampedISO,
                clamped: finalShutter != wantShutter)
        case .iso, nil:
            guard isoClamped else {
                return Correction(
                    shutterSeconds: currentShutterSeconds, iso: clampedISO,
                    clamped: false)
            }
            let wantShutter = currentShutterSeconds * factor
            let finalShutter = min(max(wantShutter, shutterRange.lowerBound), shutterRange.upperBound)
            return Correction(
                shutterSeconds: finalShutter, iso: clampedISO,
                clamped: finalShutter != wantShutter)
        case .systemAuto:
            return Correction(
                shutterSeconds: currentShutterSeconds, iso: currentISO,
                clamped: true)
        }
    }
}
