import Foundation
import CoreMotion
import Combine

@MainActor
final class HorizonMonitor: ObservableObject {
    @Published var rollDegrees: Double = 0
    @Published var isLevel = true
    @Published var isAvailable = false

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    func start() {
        guard motion.isDeviceMotionAvailable else { isAvailable = false; return }
        isAvailable = true
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let data else { return }
            let roll = data.attitude.roll * 180 / .pi
            Task { @MainActor in
                self?.rollDegrees = roll
                self?.isLevel = abs(roll) < 1.0
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}
