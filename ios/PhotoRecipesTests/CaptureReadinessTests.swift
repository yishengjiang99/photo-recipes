import XCTest
@testable import PhotoRecipes

final class CaptureReadinessTests: XCTestCase {

    private func derive(_ i: CaptureReadinessInputs) -> CaptureReadiness {
        CaptureReadinessDerivation.derive(i)
    }

    // MARK: - Derivation table

    func testCameraUnavailableWhenStopped() {
        XCTAssertEqual(derive(.init(sessionRunning: false)), .cameraUnavailable)
    }

    func testCameraStarting() {
        XCTAssertEqual(
            derive(.init(sessionRunning: false, sessionStarting: true)), .cameraStarting)
    }

    func testPlainReady() {
        XCTAssertEqual(derive(.init(sessionRunning: true)), .ready)
    }

    func testOptimizingKeepsShutterEnabled() {
        let s = derive(.init(sessionRunning: true, optimizerRunning: true))
        XCTAssertEqual(s, .optimizing)
        XCTAssertTrue(s.shutterEnabled) // optimize must never block capture
    }

    func testOptimizedCaptureReady() {
        let s = derive(.init(
            sessionRunning: true, optimizerReady: true, optimizerResultValid: true))
        XCTAssertEqual(s, .optimizedCaptureReady)
        XCTAssertTrue(s.isOptimizedCaptureReady)
        XCTAssertTrue(s.shutterEnabled)
    }

    func testInvalidatedResultFallsBackToReady() {
        // Ready phase but the result was reset / undone / lens-flipped.
        XCTAssertEqual(
            derive(.init(sessionRunning: true, optimizerReady: true, optimizerResultValid: false)),
            .ready)
    }

    func testCapturingAndSavedAndErrorPrecedence() {
        XCTAssertEqual(
            derive(.init(sessionRunning: true, optimizerReady: true,
                         optimizerResultValid: true, isCapturing: true)),
            .capturing)
        XCTAssertEqual(derive(.init(sessionRunning: true, justSaved: true)), .saved)
        XCTAssertEqual(
            derive(.init(sessionRunning: true, isCapturing: true, errorMessage: "boom")),
            .recoverableError("boom"))
    }

    func testShutterDisabledStates() {
        XCTAssertFalse(CaptureReadiness.cameraUnavailable.shutterEnabled)
        XCTAssertFalse(CaptureReadiness.cameraStarting.shutterEnabled)
        XCTAssertFalse(CaptureReadiness.capturing.shutterEnabled)
        XCTAssertFalse(CaptureReadiness.recoverableError("x").shutterEnabled)
    }

    // MARK: - Attribution

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func completedAttribution() -> OptimizeAttribution {
        var a = OptimizeAttribution()
        a.recordRunStarted(runId: "run-1")
        a.recordRunCompleted(OptimizeRunContext(
            runId: "run-1", cameraGeneration: 3, lens: "back", completedAt: t0))
        return a
    }

    func testCaptureAfterCompleteWithinWindow() {
        let a = completedAttribution()
        let c = a.classifyCapture(at: t0.addingTimeInterval(10), currentGeneration: 3, currentLens: "back")
        XCTAssertEqual(c, .afterComplete)
        XCTAssertTrue(c.countsAsOptimizedCapture)
    }

    func testWindowExpiryIsNotOptimized() {
        let a = completedAttribution()
        let c = a.classifyCapture(at: t0.addingTimeInterval(31), currentGeneration: 3, currentLens: "back")
        XCTAssertEqual(c, .none)
        XCTAssertFalse(c.countsAsOptimizedCapture)
        XCTAssertEqual(OptimizeAttribution.window, 30) // matches the legacy 30 s window
    }

    func testCaptureDuringRun() {
        var a = OptimizeAttribution()
        a.recordRunStarted(runId: "run-1")
        XCTAssertEqual(
            a.classifyCapture(at: t0, currentGeneration: 3, currentLens: "back"), .during)
    }

    func testUndoInvalidation() {
        var a = completedAttribution()
        a.invalidate(reason: .afterUndo)
        XCTAssertEqual(
            a.classifyCapture(at: t0.addingTimeInterval(2), currentGeneration: 3, currentLens: "back"),
            .afterUndo)
    }

    func testFailureInvalidation() {
        var a = OptimizeAttribution()
        a.recordRunStarted(runId: "run-1")
        a.recordRunFailed()
        XCTAssertEqual(
            a.classifyCapture(at: t0, currentGeneration: 3, currentLens: "back"), .afterFailure)
    }

    func testLensFlipInvalidation() {
        var a = completedAttribution()
        a.invalidate(reason: .afterLensFlipOrReset)
        XCTAssertEqual(
            a.classifyCapture(at: t0.addingTimeInterval(2), currentGeneration: 4, currentLens: "front"),
            .afterLensFlipOrReset)
    }

    func testGenerationOrLensMismatchIsNotCredited() {
        let a = completedAttribution()
        XCTAssertEqual(
            a.classifyCapture(at: t0.addingTimeInterval(2), currentGeneration: 4, currentLens: "back"),
            .afterLensFlipOrReset)
        XCTAssertEqual(
            a.classifyCapture(at: t0.addingTimeInterval(2), currentGeneration: 3, currentLens: "front"),
            .afterLensFlipOrReset)
    }

    func testManualOverrideIsNotCreditedAsOptimized() {
        var a = completedAttribution()
        a.recordManualOverride()
        let c = a.classifyCapture(at: t0.addingTimeInterval(2), currentGeneration: 3, currentLens: "back")
        XCTAssertEqual(c, .afterManualOverride)
        XCTAssertFalse(c.countsAsOptimizedCapture)
    }

    func testNoRunIsNone() {
        let a = OptimizeAttribution()
        XCTAssertEqual(
            a.classifyCapture(at: t0, currentGeneration: 1, currentLens: "back"), .none)
    }
}
