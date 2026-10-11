import XCTest
import SwiftUI
@testable import PhotoRecipes

/// Lifecycle rules behind "camera stays on in the background" (TF 74).
final class CameraLifecyclePolicyTests: XCTestCase {
    typealias Policy = CameraLifecyclePolicy

    // MARK: decision / shouldRun

    func testActive_visible_authorized_runs() {
        XCTAssertEqual(Policy.decision(phase: .active, isCameraTabVisible: true, permission: .authorized), .run)
        XCTAssertTrue(Policy.shouldRun(scenePhase: .active, isCameraTabVisible: true, permission: .authorized))
    }

    func testBackground_alwaysStops_evenIfRunning() {
        XCTAssertEqual(Policy.decision(phase: .background, isCameraTabVisible: true, permission: .authorized), .stop)
        XCTAssertFalse(Policy.shouldRun(scenePhase: .background, isCameraTabVisible: true,
                                        permission: .authorized, isCurrentlyRunning: true))
    }

    func testInactive_keepsCurrentState_neverStartsCamera() {
        // Control Center / Notification Center pull: don't flash the preview off…
        XCTAssertEqual(Policy.decision(phase: .inactive, isCameraTabVisible: true, permission: .authorized), .keep)
        XCTAssertTrue(Policy.shouldRun(scenePhase: .inactive, isCameraTabVisible: true,
                                       permission: .authorized, isCurrentlyRunning: true))
        // …but `.inactive` alone never turns a stopped camera on.
        XCTAssertFalse(Policy.shouldRun(scenePhase: .inactive, isCameraTabVisible: true,
                                        permission: .authorized, isCurrentlyRunning: false))
    }

    func testOtherTab_neverRuns_inAnyPhase() {
        for phase: Policy.Phase in [.active, .inactive, .background] {
            XCTAssertEqual(Policy.decision(phase: phase, isCameraTabVisible: false, permission: .authorized), .stop, "\(phase)")
            XCTAssertFalse(Policy.shouldRun(scenePhase: phase, isCameraTabVisible: false,
                                            permission: .authorized, isCurrentlyRunning: true), "\(phase)")
        }
    }

    func testWithoutPermission_neverRuns() {
        for permission: CameraSession.AuthState in [.notDetermined, .denied, .restricted] {
            for phase: Policy.Phase in [.active, .inactive, .background] {
                XCTAssertFalse(Policy.shouldRun(scenePhase: phase, isCameraTabVisible: true,
                                                permission: permission, isCurrentlyRunning: true),
                               "\(permission) \(phase)")
            }
        }
    }

    func testPhaseMapping() {
        XCTAssertEqual(Policy.Phase(ScenePhase.active), .active)
        XCTAssertEqual(Policy.Phase(ScenePhase.inactive), .inactive)
        XCTAssertEqual(Policy.Phase(ScenePhase.background), .background)
    }

    // MARK: mic

    func testMic_stopsInBackground_andOffTab_keptOnInactive() {
        XCTAssertFalse(Policy.shouldKeepMic(scenePhase: .background, isCameraTabVisible: true))
        XCTAssertFalse(Policy.shouldKeepMic(scenePhase: .active, isCameraTabVisible: false))
        XCTAssertTrue(Policy.shouldKeepMic(scenePhase: .inactive, isCameraTabVisible: true))
        XCTAssertTrue(Policy.shouldKeepMic(scenePhase: .active, isCameraTabVisible: true))
    }

    // MARK: CaptureRunIntent (start/stop race guard)

    func testRunIntent_stopInvalidatesInFlightStart() {
        let intent = CaptureRunIntent()
        let token = intent.begin()
        XCTAssertTrue(intent.isCurrent(token))
        // App backgrounds while start() is awaiting permission/configuration.
        intent.cancel()
        XCTAssertFalse(intent.isCurrent(token), "late start must not startRunning()")
        XCTAssertFalse(intent.isRunWanted)
    }

    func testRunIntent_newerStartSupersedesOlder_noDoubleStart() {
        let intent = CaptureRunIntent()
        let first = intent.begin()
        let second = intent.begin()
        XCTAssertFalse(intent.isCurrent(first))
        XCTAssertTrue(intent.isCurrent(second))
    }

    func testRunIntent_restartAfterStop_isCurrent() {
        let intent = CaptureRunIntent()
        _ = intent.begin()
        intent.cancel()
        let resumed = intent.begin()
        XCTAssertTrue(intent.isCurrent(resumed))
        XCTAssertTrue(intent.isRunWanted)
    }

    func testRunIntent_isThreadSafe() {
        let intent = CaptureRunIntent()
        DispatchQueue.concurrentPerform(iterations: 1_000) { i in
            if i % 2 == 0 { _ = intent.begin() } else { intent.cancel() }
        }
        intent.cancel()
        XCTAssertFalse(intent.isRunWanted)
        let t = intent.begin()
        XCTAssertTrue(intent.isCurrent(t))
    }

    // MARK: still look bake vs. backgrounding

    func testStillBake_startsUnlessBackgrounded() {
        XCTAssertTrue(Policy.shouldStartStillBake(appPhase: .active))
        XCTAssertTrue(Policy.shouldStartStillBake(appPhase: .inactive), "Control Center pull keeps the bake")
        XCTAssertFalse(Policy.shouldStartStillBake(appPhase: .background), "no GPU work from the background")
    }

    func testStillBake_droppedIfItRanIntoTheBackground() {
        XCTAssertTrue(Policy.keepsStillBake(enteredBackgroundDuringBake: false, appPhaseAfter: .active))
        XCTAssertTrue(Policy.keepsStillBake(enteredBackgroundDuringBake: false, appPhaseAfter: .inactive))
        XCTAssertFalse(Policy.keepsStillBake(enteredBackgroundDuringBake: true, appPhaseAfter: .active),
                       "backgrounded and back mid-bake → original JPEG")
        XCTAssertFalse(Policy.keepsStillBake(enteredBackgroundDuringBake: false, appPhaseAfter: .background))
    }

    func testPhase_fromApplicationState() {
        XCTAssertEqual(Policy.Phase(UIApplication.State.active), .active)
        XCTAssertEqual(Policy.Phase(UIApplication.State.inactive), .inactive)
        XCTAssertEqual(Policy.Phase(UIApplication.State.background), .background)
    }
}
