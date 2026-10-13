import XCTest
@testable import PhotoRecipes

final class PurchaseTelemetryTests: XCTestCase {
    func testFailedPropsCarryDomainCodeAndProduct() {
        let err = NSError(domain: "SKErrorDomain", code: 2)
        let p = PurchaseTelemetry.failedProps(error: err, productId: IAPProductID.yearly, plan: "yearly", stage: "purchase")
        XCTAssertEqual(p["error_domain"], "SKErrorDomain")
        XCTAssertEqual(p["error_code"], "2")
        XCTAssertEqual(p["product_id"], IAPProductID.yearly)
        XCTAssertEqual(p["plan"], "yearly")
        XCTAssertEqual(p["source"], "storekit")
    }

    func testPaywallTypeMapping() {
        XCTAssertEqual(PurchaseTelemetry.paywallType(mode: "soft", trigger: "post_first_optimize"), "soft")
        XCTAssertEqual(PurchaseTelemetry.paywallType(mode: "soft", trigger: "push"), "soft")
        XCTAssertEqual(PurchaseTelemetry.paywallType(mode: "hard", trigger: "free_quota"), "hard")
        XCTAssertEqual(PurchaseTelemetry.paywallType(mode: "hard", trigger: "settings_upgrade"), "settings")
        XCTAssertEqual(PurchaseTelemetry.paywallType(mode: "hard", trigger: "upgrade_top"), "upgrade")
    }

    func testDismissProps() {
        let p = PurchaseTelemetry.dismissProps(mode: "hard", trigger: "free_quota", action: "close",
                                               timeOnScreenMs: 4200, selectedPlan: nil, freeTriesLeft: "0")
        XCTAssertEqual(p["paywall_type"], "hard")
        XCTAssertEqual(p["time_on_screen_ms"], "4200")
        XCTAssertEqual(p["plan"], "none")
        XCTAssertEqual(p["free_tries_left"], "0")
        XCTAssertEqual(p["paywall_trigger"], "free_quota")
    }
}
