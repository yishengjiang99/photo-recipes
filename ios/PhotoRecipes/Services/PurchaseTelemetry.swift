import Foundation

/// Payload builders for paywall / StoreKit funnel events (event contract:
/// docs/telemetry-funnels.md). Pure so they can be unit-tested; props stay
/// `[String: String]` like every other `Analytics.track` call.
enum PurchaseTelemetry {
    /// Wraps an error already reported as `purchase_failed` so the outer catch doesn't double-count.
    struct AlreadyTracked: Error { let underlying: Error }

    static func plan(for productId: String) -> String {
        productId.contains("yearly") ? "yearly" : (productId.contains("monthly") ? "monthly" : "unknown")
    }

    static func baseProps(productId: String, plan: String) -> [String: String] {
        ["plan": plan, "product_id": productId, "source": "storekit"]
    }

    /// `stage`: "purchase" (Product.purchase threw) or "verification" (unverified transaction).
    static func failedProps(error: Error, productId: String, plan: String, stage: String) -> [String: String] {
        let ns = error as NSError
        var p = baseProps(productId: productId, plan: plan)
        p["error_domain"] = ns.domain
        p["error_code"] = "\(ns.code)"
        p["stage"] = stage
        return p
    }

    /// soft | hard | settings | upgrade
    static func paywallType(mode: String, trigger: String) -> String {
        if trigger.hasPrefix("settings") { return "settings" }
        if trigger.contains("upgrade") { return "upgrade" }
        return mode == "soft" ? "soft" : "hard"
    }

    static func dismissProps(
        mode: String,
        trigger: String,
        action: String,
        timeOnScreenMs: Int,
        selectedPlan: String?,
        freeTriesLeft: String
    ) -> [String: String] {
        [
            "source": "ios_sheet",
            "paywall_type": paywallType(mode: mode, trigger: trigger),
            "mode": mode,
            "paywall_trigger": trigger,
            "action": action,
            "time_on_screen_ms": "\(max(0, timeOnScreenMs))",
            "plan": selectedPlan ?? "none",
            "free_tries_left": freeTriesLeft,
        ]
    }
}
