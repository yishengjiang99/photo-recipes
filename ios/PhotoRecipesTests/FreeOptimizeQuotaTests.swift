import XCTest
@testable import PhotoRecipes

final class FreeOptimizeQuotaTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        suite = "FreeOptimizeQuotaTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func quota() -> FreeOptimizeQuota {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = clock
        return FreeOptimizeQuota(defaults: defaults, now: { now }, calendar: cal)
    }

    func testNewInstallGetsTenSuccessfulUsesInFirst24h() {
        quota().ensureInstallDate(existingUser: false)
        XCTAssertTrue(quota().inWelcomeWindow)
        XCTAssertEqual(quota().remaining(serverDailyLimit: 5), 10)
        for _ in 0..<10 { quota().recordSuccess() }
        XCTAssertEqual(quota().remaining(serverDailyLimit: 5), 0)
        XCTAssertEqual(quota().successfulUsesTotal, 10)
    }

    func testAfterWelcomeWindowFallsBackToDailyLimit() {
        quota().ensureInstallDate(existingUser: false)
        clock = clock.addingTimeInterval(3 * 24 * 3600)
        XCTAssertFalse(quota().inWelcomeWindow)
        XCTAssertEqual(quota().remaining(serverDailyLimit: 5), 5)
        quota().recordSuccess()
        XCTAssertEqual(quota().remaining(serverDailyLimit: 5), 4)
        XCTAssertEqual(quota().dayIndex, 3)
    }

    func testExistingUserIsBackdatedAndKeepsDailyPool() {
        quota().ensureInstallDate(existingUser: true)
        XCTAssertFalse(quota().inWelcomeWindow)
        XCTAssertEqual(quota().remaining(serverDailyLimit: nil), FreeOptimizeQuota.defaultDailyLimit)
    }

    func testProSuccessDoesNotConsumeFreePool() {
        quota().ensureInstallDate(existingUser: true)
        quota().recordSuccess(countsAgainstFree: false)
        XCTAssertEqual(quota().remaining(serverDailyLimit: 5), 5)
        XCTAssertEqual(quota().successfulUsesTotal, 1)
    }
}
