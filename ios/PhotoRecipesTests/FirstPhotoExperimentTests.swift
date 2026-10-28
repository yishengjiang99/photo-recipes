import XCTest
@testable import PhotoRecipes

@MainActor
final class FirstPhotoExperimentTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var sink: FakeAnalyticsSink!
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        suite = "FirstPhotoExperimentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        sink = FakeAnalyticsSink()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func experiment(installId: String = "test-install-1") -> FirstPhotoExperiment {
        let now = clock
        return FirstPhotoExperiment(
            defaults: defaults,
            now: { now },
            sink: sink,
            assigner: ExperimentAssigner(
                defaults: defaults,
                installIdProvider: { installId },
                sink: sink
            )
        )
    }

    private var safeGates: FirstPhotoExperiment.CameraGateInputs {
        .init(sessionRunning: true, isBackgrounded: false, isLensTransitioning: false,
              isCapturing: false, optimizerRunning: false)
    }

    // MARK: - Eligibility

    func testEligibleWhenFresh() {
        XCTAssertTrue(experiment().isEligible(hasPriorActivation: false, userUndid: false))
    }

    func testPriorActivationBlocks() {
        XCTAssertFalse(experiment().isEligible(hasPriorActivation: true, userUndid: false))
    }

    func testUndoOptOutBlocks() {
        XCTAssertFalse(experiment().isEligible(hasPriorActivation: false, userUndid: true))
    }

    func testKillSwitchBlocks() {
        defaults.set(true, forKey: "featureFlags.firstPhotoExperimentKilled")
        XCTAssertFalse(experiment().isEligible(hasPriorActivation: false, userUndid: false))
    }

    func testTerminalStatesBlock() {
        let e = experiment()
        e.markSkipped()
        XCTAssertFalse(e.isEligible(hasPriorActivation: false, userUndid: false))
        XCTAssertEqual(e.state, .skipped)
        XCTAssertEqual(sink.count("first_photo_guidance_skip"), 1)
        XCTAssertEqual(sink.last("first_photo_guidance_skip")?["reason"], "skipped")
    }

    func testDeclinedIsTerminalWithReason() {
        let e = experiment()
        e.markDeclined()
        XCTAssertEqual(e.state, .declined)
        XCTAssertEqual(sink.last("first_photo_guidance_skip")?["reason"], "declined")
        XCTAssertFalse(e.isEligible(hasPriorActivation: false, userUndid: false))
    }

    // MARK: - Pre-capture gates

    func testControlArmCannotStartEvenWithSafeGates() {
        let e = experiment(installId: installId(wanting: .control, for: .firstPhoto))
        XCTAssertFalse(e.canStartPreoptimize(gates: safeGates, hasPriorActivation: false, userUndid: false))
    }

    func testTreatmentStartsWhenAllGatesSafe() {
        let e = experiment(installId: installId(wanting: .treatment, for: .firstPhoto))
        XCTAssertTrue(e.canStartPreoptimize(gates: safeGates, hasPriorActivation: false, userUndid: false))
    }

    func testEachUnsafeGateBlocks() {
        let id = installId(wanting: .treatment, for: .firstPhoto)
        let mutations: [(inout FirstPhotoExperiment.CameraGateInputs) -> Void] = [
            { $0.sessionRunning = false },
            { $0.isBackgrounded = true },
            { $0.isLensTransitioning = true },
            { $0.isCapturing = true },
            { $0.optimizerRunning = true },
        ]
        for mutate in mutations {
            var gates = safeGates
            mutate(&gates)
            XCTAssertFalse(
                experiment(installId: id).canStartPreoptimize(
                    gates: gates, hasPriorActivation: false, userUndid: false))
        }
    }

    // MARK: - Guidance + activation semantics

    func testGuidanceViewEmittedOnce() {
        let e = experiment()
        e.markGuidanceShown()
        e.markGuidanceShown()
        XCTAssertEqual(sink.count("first_photo_guidance_view"), 1)
        XCTAssertEqual(e.state, .guidanceShown)
    }

    func testFirstAppOpenStoredOnce() {
        let e = experiment()
        let first = e.recordFirstAppOpenIfNeeded()
        clock = clock.addingTimeInterval(3600)
        XCTAssertEqual(e.recordFirstAppOpenIfNeeded(), first)
    }

    func testActivationAtMostOnceAndWithinWindow() {
        let e = experiment()
        e.recordFirstAppOpenIfNeeded()
        clock = clock.addingTimeInterval(120) // 2 minutes after first open
        XCTAssertTrue(e.recordActivationIfNeeded())
        XCTAssertFalse(e.recordActivationIfNeeded())
        XCTAssertEqual(sink.count("first_photo_activation_complete"), 1)
        XCTAssertEqual(sink.last("first_photo_activation_complete")?["within_window"], "1")
        XCTAssertEqual(sink.last("first_photo_activation_complete")?["elapsed_sec"], "120")
        XCTAssertEqual(e.state, .completed)
    }

    func testActivationOutsideWindowRecordedHonestly() {
        let e = experiment()
        e.recordFirstAppOpenIfNeeded()
        clock = clock.addingTimeInterval(3600)
        XCTAssertTrue(e.recordActivationIfNeeded())
        XCTAssertEqual(sink.last("first_photo_activation_complete")?["within_window"], "0")
    }

    func testPreoptimizePairCarriesRunId() {
        let e = experiment()
        e.markPreoptimizeStarted(runId: "run-1")
        e.markPreoptimizeCompleted(runId: "run-1", success: true)
        XCTAssertEqual(sink.last("first_photo_preoptimize_start")?["run_id"], "run-1")
        XCTAssertEqual(sink.last("first_photo_preoptimize_complete")?["outcome"], "success")
    }

    /// Contract: no emitted prop key may contain a substring the Analytics
    /// layer filters out (photo/email/phone/image/base64/gps/token/password).
    func testNoFilteredPropKeys() {
        let e = experiment()
        e.markGuidanceShown()
        e.markPreoptimizeStarted(runId: "r")
        e.markPreoptimizeCompleted(runId: "r", success: false)
        e.recordActivationIfNeeded()
        let banned = ["email", "phone", "image", "photo", "base64", "gps", "token", "password"]
        for key in sink.allPropKeys {
            for word in banned {
                XCTAssertFalse(key.contains(word), "prop key \(key) contains banned substring \(word)")
            }
        }
    }
}
