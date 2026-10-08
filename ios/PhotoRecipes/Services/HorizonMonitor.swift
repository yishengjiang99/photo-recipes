import Foundation
import CoreMotion
import Combine

/// Pure, unit-testable device-motion math (no CoreMotion types in the signatures).
enum MotionMath {
    /// Camera elevation angle in degrees, derived from the gravity vector.
    ///
    /// The back camera's optical axis is device −Z. Elevation is the angle of
    /// that axis above the horizon plane:
    ///   elevation = asin(−gz), with g the unit gravity vector.
    ///
    /// ≈ 0° when the camera points at the horizon in any hold (portrait or
    /// landscape), +90° straight up, −90° straight down. Replaces the old
    /// Euler-pitch heuristic, which read ≈ 90° for a normally-held portrait
    /// phone and misclassified ordinary shots as "low angle".
    static func cameraElevationDegrees(gx: Double, gy: Double, gz: Double) -> Double {
        let clamped = min(max(-gz, -1), 1)
        return asin(clamped) * 180 / .pi
    }

    /// Rotation-rate magnitude in rad/s — the raw hand-shake signal.
    static func rotationRateMagnitude(rx: Double, ry: Double, rz: Double) -> Double {
        (rx * rx + ry * ry + rz * rz).squareRoot()
    }

    /// One EMA step for smoothing the shake signal.
    static func ema(previous: Double, sample: Double, alpha: Double) -> Double {
        previous + alpha * (sample - previous)
    }
}

@MainActor
final class HorizonMonitor: ObservableObject {
    @Published var rollDegrees: Double = 0
    /// Attitude pitch in degrees — kept for the level indicator; NOT used for
    /// low-angle heuristics anymore (see `cameraElevationDegrees`).
    @Published var pitchDegrees: Double = 0
    /// Camera elevation above the horizon in degrees. ≈ 0° at the horizon in
    /// any hold; positive when pointed up. Drives get-down-low detection.
    @Published var cameraElevationDegrees: Double = 0
    /// Smoothed rotation-rate magnitude (rad/s) — hand-shake estimate for the
    /// Auto Optimize settings solver.
    @Published var handShakeRadPerSec: Double = 0
    @Published var isLevel = true
    @Published var isAvailable = false

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var shakeEMA: Double = 0
    /// EMA weight per 30 Hz sample (≈ 0.6 s time constant).
    private let shakeAlpha = 0.2

    func start() {
        guard motion.isDeviceMotionAvailable else { isAvailable = false; return }
        isAvailable = true
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let roll = data.attitude.roll * 180 / .pi
            let pitch = data.attitude.pitch * 180 / .pi
            let g = data.gravity
            let elevation = MotionMath.cameraElevationDegrees(gx: g.x, gy: g.y, gz: g.z)
            let r = data.rotationRate
            let shake = MotionMath.rotationRateMagnitude(rx: r.x, ry: r.y, rz: r.z)
            let smoothed = MotionMath.ema(previous: self.shakeEMA, sample: shake, alpha: self.shakeAlpha)
            self.shakeEMA = smoothed
            Task { @MainActor in
                self.rollDegrees = roll
                self.pitchDegrees = pitch
                self.cameraElevationDegrees = elevation
                self.handShakeRadPerSec = smoothed
                self.isLevel = abs(roll) < 1.0
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        shakeEMA = 0
    }
}
