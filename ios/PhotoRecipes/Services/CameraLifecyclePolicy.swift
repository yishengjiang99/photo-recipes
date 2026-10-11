import Foundation
import SwiftUI
import UIKit

/// Pure lifecycle policy for the capture session (and the mic it can share the
/// screen with). Decides whether the camera should be running for a given
/// scene phase, Camera-tab visibility and camera permission. Unit-tested —
/// the views only translate its decision into start/stop calls.
///
/// Rules:
/// - No permission, or Camera tab not on screen → stop.
/// - `.background` → stop (camera + mic must never outlive the foreground).
/// - `.inactive` → keep whatever state we're in. Control Center / Notification
///   Center pulls, the app switcher's first frame and system alerts all pass
///   through `.inactive`; tearing the session down there would flash the
///   preview black for a pull-down. A real backgrounding always reaches
///   `.background`, which stops it.
/// - `.active` → run.
enum CameraLifecyclePolicy {
    enum Phase: Equatable {
        case active, inactive, background

        init(_ phase: ScenePhase) {
            switch phase {
            case .active: self = .active
            case .inactive: self = .inactive
            case .background: self = .background
            @unknown default: self = .background
            }
        }

        init(_ state: UIApplication.State) {
            switch state {
            case .active: self = .active
            case .inactive: self = .inactive
            case .background: self = .background
            @unknown default: self = .background
            }
        }
    }

    enum Decision: Equatable {
        /// Start the session if it isn't running.
        case run
        /// Stop the session (and mic / sensors) if running.
        case stop
        /// Leave the current state alone (transient `.inactive`).
        case keep
    }

    static func decision(
        phase: Phase,
        isCameraTabVisible: Bool,
        permission: CameraSession.AuthState
    ) -> Decision {
        guard permission == .authorized, isCameraTabVisible else { return .stop }
        switch phase {
        case .active: return .run
        case .inactive: return .keep
        case .background: return .stop
        }
    }

    /// Whether the session should be running. `.inactive` keeps the current
    /// state (`isCurrentlyRunning`); it never *starts* the camera.
    static func shouldRun(
        scenePhase: Phase,
        isCameraTabVisible: Bool,
        permission: CameraSession.AuthState,
        isCurrentlyRunning: Bool = false
    ) -> Bool {
        switch decision(phase: scenePhase, isCameraTabVisible: isCameraTabVisible, permission: permission) {
        case .run: return true
        case .stop: return false
        case .keep: return isCurrentlyRunning
        }
    }

    /// Whether voice capture (AVAudioEngine / recorder + AVAudioSession) may
    /// stay live. Mic follows the same rule, except it is never kept in
    /// `.background` and never needs camera permission.
    static func shouldKeepMic(scenePhase: Phase, isCameraTabVisible: Bool) -> Bool {
        isCameraTabVisible && scenePhase != .background
    }

    // MARK: Still look bake vs. backgrounding

    /// Core Image renders the look on the GPU, and iOS doesn't allow GPU work from the
    /// background. A photo that arrives after the app is backgrounded keeps its un-baked JPEG,
    /// the same fallback as any other bake failure.
    static func shouldStartStillBake(appPhase: Phase) -> Bool {
        appPhase != .background
    }

    /// Keep a finished bake only if the app stayed out of the background for the whole bake.
    /// A render that ran into the background may have failed or come out wrong, so the shot
    /// keeps its original JPEG.
    static func keepsStillBake(enteredBackgroundDuringBake: Bool, appPhaseAfter: Phase) -> Bool {
        !enteredBackgroundDuringBake && appPhaseAfter != .background
    }
}

/// Watches for `didEnterBackground` while an async step (the still bake) is in flight.
@MainActor
final class BackgroundEntryWatch {
    private(set) var didEnterBackground = false
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground = true }
        }
    }

    /// Stops watching. Returns whether the app entered the background meanwhile.
    func finish() -> Bool {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        return didEnterBackground
    }
}

/// `UIApplication` background-task assertion: a shot that was mid bake / save when the user
/// left the app still gets finished and written to Photos instead of sitting suspended in
/// memory (and lost if iOS later jettisons the app). Idempotent `end()`. The expiration
/// handler ends it too.
@MainActor
final class BackgroundTaskAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Called on the main thread; the task must end before this returns.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Thread-safe start/stop intent shared between the main actor and the
/// capture session queue. Every `begin()` / `cancel()` bumps the generation,
/// so a start block that was queued (or still awaiting permission /
/// configuration) before a later stop sees a stale token and never calls —
/// or immediately undoes — `startRunning()`.
final class CaptureRunIntent: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var wantsRunning = false

    /// Records "should run" and returns the token for this start attempt.
    func begin() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        wantsRunning = true
        return generation
    }

    /// Records "should stop"; invalidates every outstanding start token.
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        wantsRunning = false
    }

    /// True while `token` is the latest intent and that intent is "run".
    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return wantsRunning && generation == token
    }

    var isRunWanted: Bool {
        lock.lock(); defer { lock.unlock() }
        return wantsRunning
    }
}
