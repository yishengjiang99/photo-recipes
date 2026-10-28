import XCTest
@testable import PhotoRecipes

@MainActor
final class PurchaseTelemetryV2Tests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var sink: FakeAnalyticsSink!
    private var v2Enabled = true

    override func setUp() {
        super.setUp()
        suite = "PurchaseTelemetryV2Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        sink = FakeAnalyticsSink()
        v2Enabled = true
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func v2() -> PurchaseTelemetryV2 {
        let enabled = v2Enabled
        return PurchaseTelemetryV2(
            defaults: defaults, sink: sink, enabled: { enabled })
    }

    private func recordVerified(_ v: PurchaseTelemetryV2, txn: String = "txn-1") -> Bool {
        v.recordVerifiedAndActivated(
            attemptId: "attempt-1", transactionId: txn,
            productId: "com.ragnus.mvp.pro.yearly", environment: "Sandbox",
            entitlementType: "pro", activationSource: "purchase")
    }

    func testSuccessEmittedOnlyAfterVerifiedAndActivated_InOrder() {
        let v = v2()
        XCTAssertTrue(recordVerified(v))
        let verifiedIdx = sink.index(of: "purchase_verified")
        let activatedIdx = sink.index(of: "entitlement_activated")
        let successIdx = sink.index(of: "purchase_success")
        XCTAssertNotNil(verifiedIdx)
        XCTAssertNotNil(activatedIdx)
        XCTAssertNotNil(successIdx)
        XCTAssertTrue(verifiedIdx! < activatedIdx! && activatedIdx! < successIdx!)
        XCTAssertEqual(sink.last("purchase_success")?["transaction_id"], "txn-1")
        XCTAssertEqual(sink.last("purchase_success")?["telemetry_v"], "2")
    }

    func testDuplicateTransactionIsDeduped() {
        let v = v2()
        XCTAssertTrue(recordVerified(v))
        XCTAssertFalse(recordVerified(v)) // relaunch / duplicate callback replay
        XCTAssertEqual(sink.count("purchase_success"), 1)
        XCTAssertEqual(sink.count("purchase_verified"), 1)
    }

    func testDedupeSetIsBounded() {
        let v = v2()
        for i in 0..<(PurchaseTelemetryV2.maxDedupedTransactions + 5) {
            _ = recordVerified(v, txn: "txn-\(i)")
        }
        let stored = defaults.stringArray(forKey: PurchaseTelemetryV2.dedupeKey) ?? []
        XCTAssertEqual(stored.count, PurchaseTelemetryV2.maxDedupedTransactions)
    }

    func testFlagOffEmitsNothing() {
        v2Enabled = false
        let v = v2()
        XCTAssertFalse(recordVerified(v))
        v.recordCancelled(attemptId: "a", source: "user")
        v.recordPending(attemptId: "a", productId: "p")
        v.recordFailed(attemptId: "a", errorCategory: "storekit_error")
        v.recordRestore(result: "entitled", verifiedEntitlementCount: 1)
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testCancelPendingFailedAreDistinct() {
        let v = v2()
        v.recordCancelled(attemptId: "a1", source: "user")
        v.recordPending(attemptId: "a2", productId: "com.ragnus.mvp.pro.monthly")
        v.recordFailed(attemptId: "a3", errorCategory: "unverified")
        XCTAssertEqual(sink.count("purchase_cancelled"), 1)
        XCTAssertEqual(sink.last("purchase_cancelled")?["cancellation_source"], "user")
        XCTAssertEqual(sink.count("purchase_pending"), 1)
        XCTAssertEqual(sink.last("purchase_pending")?["product_id"], "com.ragnus.mvp.pro.monthly")
        XCTAssertEqual(sink.count("purchase_failed"), 1)
        XCTAssertEqual(sink.last("purchase_failed")?["error_category"], "unverified")
        XCTAssertEqual(sink.count("purchase_success"), 0) // none of these is a success
    }

    func testRestoreIsNotASuccess() {
        let v = v2()
        v.recordRestore(result: "entitled", verifiedEntitlementCount: 2)
        XCTAssertEqual(sink.count("purchase_restore"), 1)
        XCTAssertEqual(sink.last("purchase_restore")?["verified_entitlement_count"], "2")
        XCTAssertEqual(sink.count("purchase_success"), 0)
    }

    func testAttemptIdsAreUnique() {
        let v = v2()
        XCTAssertNotEqual(v.beginAttempt(), v.beginAttempt())
    }

    // MARK: - Paywall value proof

    func testProofLoadsOnlyAfterRealRecord() {
        XCTAssertNil(PaywallValueProof.load(defaults: defaults))
        PaywallValueProof.record(
            defaults: defaults,
            recipeTitle: "Golden Hour",
            appliedSettingsSummary: "3 settings applied by Auto Optimize",
            settingsCount: 3,
            savedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let proof = PaywallValueProof.load(defaults: defaults)
        XCTAssertEqual(proof?.recipeTitle, "Golden Hour")
        XCTAssertEqual(proof?.settingsCount, 3)
    }
}
