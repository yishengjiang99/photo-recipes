import XCTest
@testable import PhotoRecipes

final class OptimizeStageTimerTests: XCTestCase {
    private var sink: FakeAnalyticsSink!
    private var clock: FakeMonotonicClock!
    private var timingEnabled = true

    override func setUp() {
        super.setUp()
        sink = FakeAnalyticsSink()
        clock = FakeMonotonicClock()
        timingEnabled = true
    }

    private func timer() -> OptimizeStageTimer {
        let enabled = timingEnabled
        return OptimizeStageTimer(
            clock: clock, sink: sink, enabled: { enabled },
            runId: "run-1", trigger: "manual", lens: "back")
    }

    func testStageDurationFromMonotonicClock() {
        let t = timer()
        t.beginRun()
        t.beginStage(.aeConvergence)
        clock.advance(milliseconds: 250)
        t.endStage(.aeConvergence)
        XCTAssertEqual(sink.last("optimize_stage_complete")?["stage"], "aeConvergence")
        XCTAssertEqual(sink.last("optimize_stage_complete")?["duration_ms"], "250")
        XCTAssertEqual(t.stageDurationsMs[.aeConvergence], 250)
    }

    func testLatencySummaryTotalsAndStageBreakdown() {
        let t = timer()
        t.beginRun()
        t.beginStage(.aeConvergence)
        clock.advance(milliseconds: 100)
        t.endStage(.aeConvergence, next: .inference)
        clock.advance(milliseconds: 50)
        t.endStage(.inference, next: .apply)
        clock.advance(milliseconds: 30)
        t.endStage(.apply, next: .verify)
        clock.advance(milliseconds: 20)
        t.endStage(.verify)
        t.finish(outcome: "ready")
        let summary = sink.last("optimize_latency_summary")
        XCTAssertEqual(summary?["total_ms"], "200")
        XCTAssertEqual(summary?["stage_aeConvergence_ms"], "100")
        XCTAssertEqual(summary?["stage_inference_ms"], "50")
        XCTAssertEqual(summary?["stage_apply_ms"], "30")
        XCTAssertEqual(summary?["stage_verify_ms"], "20")
        XCTAssertEqual(summary?["outcome"], "ready")
    }

    func testFinishEmitsAtMostOnce() {
        let t = timer()
        t.beginRun()
        clock.advance(milliseconds: 10)
        t.finish(outcome: "ready")
        t.finish(outcome: "ready")
        XCTAssertEqual(sink.count("optimize_latency_summary"), 1)
    }

    func testFallbackEvent() {
        let t = timer()
        t.beginRun()
        t.recordFallback(reason: "ae_converge_timeout")
        XCTAssertEqual(sink.count("optimize_fallback"), 1)
        XCTAssertEqual(sink.last("optimize_fallback")?["reason"], "ae_converge_timeout")
    }

    func testDisabledSuppressesEventsButStillMeasures() {
        timingEnabled = false
        let t = timer()
        t.beginRun()
        t.beginStage(.apply)
        clock.advance(milliseconds: 40)
        t.endStage(.apply)
        t.recordFallback(reason: "x")
        t.finish(outcome: "ready")
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertEqual(t.stageDurationsMs[.apply], 40)
    }

    func testEndingUnbegunStageIsNoOp() {
        let t = timer()
        t.beginRun()
        t.endStage(.verify)
        XCTAssertNil(t.stageDurationsMs[.verify])
        XCTAssertEqual(sink.count("optimize_stage_complete"), 0)
    }

    // MARK: - Diagnostics helpers

    func testMeteringMissingClassification() {
        XCTAssertEqual(
            MeteringMissingReason.classify(hasExposureSeconds: false, hasISO: false),
            .missingInput)
        XCTAssertEqual(
            MeteringMissingReason.classify(hasExposureSeconds: true, hasISO: false),
            .metadataUnavailable)
        XCTAssertEqual(
            MeteringMissingReason.classify(hasExposureSeconds: false, hasISO: true),
            .metadataUnavailable)
    }

    func testAEDiagnosticsUnknownsAreNotFabricated() {
        let props = AEDiagnostics.timeoutProps(
            lens: "front", phaseAtTimeout: "sensing",
            wasLensSwitching: nil, wasCaptureInFlight: false, exposureLocked: nil)
        XCTAssertEqual(props["lens"], "front")
        XCTAssertEqual(props["was_lens_switching"], "unknown")
        XCTAssertEqual(props["exposure_locked"], "unknown")
        XCTAssertEqual(props["was_capture_in_flight"], "0")
    }
}
