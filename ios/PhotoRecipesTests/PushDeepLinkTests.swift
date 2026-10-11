import XCTest
@testable import PhotoRecipes

/// Lifecycle push tap routing: payload `deepLink` → destination (docs/push-lifecycle.md).
@MainActor
final class PushDeepLinkTests: XCTestCase {
    private func dest(_ s: String?) -> PushNotificationManager.Destination {
        PushNotificationManager.destination(for: s.flatMap(URL.init(string:)))
    }

    func testKnownHosts() {
        XCTAssertEqual(dest("photo-recipes://auto-optimize"), .autoOptimize)
        XCTAssertEqual(dest("photo-recipes://camera"), .camera)
        XCTAssertEqual(dest("photo-recipes://recipes"), .recipes)
        XCTAssertEqual(dest("photo-recipes://paywall"), .paywall)
        XCTAssertEqual(dest("photo-recipes:///recipes"), .recipes)
    }

    func testUnknownOrForeignLinksAreSafe() {
        // Missing link keeps the legacy behavior (Auto Optimize); unknown host → camera.
        XCTAssertEqual(dest(nil), .autoOptimize)
        XCTAssertEqual(dest("photo-recipes://something-else"), .camera)
        XCTAssertEqual(dest("https://evil.example/paywall"), .autoOptimize)
    }

    func testMarketingOptInDefaultsOff() {
        let key = PushNotificationManager.marketingOptInKey
        let prior = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let prior { UserDefaults.standard.set(prior, forKey: key) } }
        XCTAssertFalse(PushNotificationManager.marketingOptIn)
    }
}
