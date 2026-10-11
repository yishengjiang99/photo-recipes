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

    // MARK: - Token upload cache (install ID ↔ token link)

    func testAppUpdateWithSameTokenStillUploads() {
        let token = String(repeating: "ab", count: 32)
        let v14 = PushNotificationManager.registerFingerprint(
            token: token, environment: "production", appVersion: "1.4 (72)", anonId: "anon-1")
        let v15 = PushNotificationManager.registerFingerprint(
            token: token, environment: "production", appVersion: "1.5 (77)", anonId: "anon-1")
        XCTAssertTrue(PushNotificationManager.shouldUploadToken(current: v15, lastFingerprint: v14, lastOk: true, force: false))
        XCTAssertFalse(PushNotificationManager.shouldUploadToken(current: v15, lastFingerprint: v15, lastOk: true, force: false))
    }

    func testNewInstallIdOrLegacyCacheOrFailureUploads() {
        let token = String(repeating: "cd", count: 32)
        let a = PushNotificationManager.registerFingerprint(
            token: token, environment: "production", appVersion: "1.5 (77)", anonId: "anon-1")
        let b = PushNotificationManager.registerFingerprint(
            token: token, environment: "production", appVersion: "1.5 (77)", anonId: "anon-2")
        XCTAssertTrue(PushNotificationManager.shouldUploadToken(current: b, lastFingerprint: a, lastOk: true, force: false))
        // Pre-1.5 (77) installs only cached the raw token: no fingerprint → upload once.
        XCTAssertTrue(PushNotificationManager.shouldUploadToken(current: a, lastFingerprint: nil, lastOk: true, force: false))
        XCTAssertTrue(PushNotificationManager.shouldUploadToken(current: a, lastFingerprint: a, lastOk: false, force: false))
        XCTAssertTrue(PushNotificationManager.shouldUploadToken(current: a, lastFingerprint: a, lastOk: true, force: true))
    }

    func testFingerprintContextMatch() {
        let f = PushNotificationManager.registerFingerprint(
            token: "t", environment: "production", appVersion: "1.5 (77)", anonId: "anon-1")
        XCTAssertTrue(PushNotificationManager.fingerprintMatchesContext(
            f, environment: "production", appVersion: "1.5 (77)", anonId: "anon-1"))
        XCTAssertFalse(PushNotificationManager.fingerprintMatchesContext(
            f, environment: "production", appVersion: "1.5 (78)", anonId: "anon-1"))
        XCTAssertFalse(PushNotificationManager.fingerprintMatchesContext(
            "legacy-token-only", environment: "production", appVersion: "1.5 (77)", anonId: "anon-1"))
    }
}
