import XCTest
@testable import PhotoRecipes

final class ExperimentAssignmentTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "ExperimentAssignmentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func assigner(installId: String, sink: FakeAnalyticsSink) -> ExperimentAssigner {
        ExperimentAssigner(
            defaults: defaults,
            installIdProvider: { installId },
            sink: sink
        )
    }

    func testBucketIsDeterministic() {
        let a = ExperimentAssignment.bucket(installId: "abc-123", salt: "first_photo_v1")
        let b = ExperimentAssignment.bucket(installId: "abc-123", salt: "first_photo_v1")
        XCTAssertEqual(a, b)
        XCTAssertTrue((0..<100).contains(a))
    }

    func testArmBoundaryIsFiftyFifty() {
        XCTAssertEqual(ExperimentAssignment.arm(forBucket: 0), .treatment)
        XCTAssertEqual(ExperimentAssignment.arm(forBucket: 49), .treatment)
        XCTAssertEqual(ExperimentAssignment.arm(forBucket: 50), .control)
        XCTAssertEqual(ExperimentAssignment.arm(forBucket: 99), .control)
    }

    func testAssignmentStableAcrossLaunchesAndEmittedOnce() {
        let sink = FakeAnalyticsSink()
        let first = assigner(installId: "install-42", sink: sink).assignment(for: .firstPhoto)
        XCTAssertEqual(sink.count("first_photo_experiment_assigned"), 1)

        // A fresh assigner over the same defaults = a new app launch.
        let secondSink = FakeAnalyticsSink()
        let second = assigner(installId: "install-42", sink: secondSink).assignment(for: .firstPhoto)
        XCTAssertEqual(first, second)
        XCTAssertEqual(secondSink.count("first_photo_experiment_assigned"), 0)
    }

    func testDistributionSanityOver1000Installs() {
        var treatment = 0
        for i in 0..<1000 {
            if ExperimentAssignment.arm(installId: "install-\(i)", salt: "first_photo_v1") == .treatment {
                treatment += 1
            }
        }
        // 50/50 ± generous sanity band — catches a broken hash, not noise.
        XCTAssertTrue((400...600).contains(treatment), "treatment count was \(treatment)")
    }

    func testExperimentsAreIndependent() {
        let sink = FakeAnalyticsSink()
        let a = assigner(installId: "install-7", sink: sink)
        _ = a.assignment(for: .firstPhoto)
        XCTAssertNil(a.persistedArm(for: .paywall))
        XCTAssertEqual(sink.count("paywall_experiment_assigned"), 0)
        _ = a.assignment(for: .paywall)
        XCTAssertNotNil(a.persistedArm(for: .paywall))
        XCTAssertEqual(sink.count("paywall_experiment_assigned"), 1)
        // Separate persisted keys: clearing one leaves the other intact.
        defaults.removeObject(forKey: Experiment.firstPhoto.assignmentDefaultsKey)
        XCTAssertNil(a.persistedArm(for: .firstPhoto))
        XCTAssertNotNil(a.persistedArm(for: .paywall))
    }

    func testKillSwitchDoesNotResetAssignment() {
        let sink = FakeAnalyticsSink()
        let a = assigner(installId: "install-99", sink: sink)
        let arm = a.assignment(for: .firstPhoto)

        defaults.set(true, forKey: "featureFlags.firstPhotoExperimentKilled")
        let flags = FeatureFlags(defaults: defaults)
        XCTAssertFalse(flags.firstPhotoExperimentActive)
        // Assignment survives the kill switch untouched…
        XCTAssertEqual(a.assignment(for: .firstPhoto), arm)
        // …and comes back when the switch is released.
        defaults.set(false, forKey: "featureFlags.firstPhotoExperimentKilled")
        XCTAssertTrue(FeatureFlags(defaults: defaults).firstPhotoExperimentActive)
        XCTAssertEqual(a.assignment(for: .firstPhoto), arm)
    }

    func testFlagDefaultsAreSafe() {
        let flags = FeatureFlags(defaults: defaults)
        XCTAssertTrue(flags.firstPhotoPreoptimizeEnabled)
        XCTAssertTrue(flags.captureReadyUIEnabled)
        XCTAssertTrue(flags.paywallValueExperimentEnabled)
        XCTAssertFalse(flags.purchaseTelemetryV2Enabled) // changes legacy success gating — opt-in
        XCTAssertTrue(flags.optimizeStageTimingEnabled)
        XCTAssertFalse(flags.optimizeSafeTimeoutEnabled)
        XCTAssertFalse(flags.firstPhotoExperimentKilled)
        XCTAssertFalse(flags.paywallExperimentKilled)
    }
}
