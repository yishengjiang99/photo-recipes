import Foundation

enum SubscriptionPlan: String, Codable, Hashable {
    case monthly
    case yearly
}

struct SubscriptionStatus: Codable, Hashable {
    var pro: Bool
    /// Owner/device/admin allowlist — unlimited Ask without requiring Pro IAP
    var unlimited: Bool?
    var status: String
    var plan: SubscriptionPlan?
    var email: String?
    var asksUsedToday: Int
    var asksLimit: Int?
    var asksRemaining: Int?
    var freeDailyLimit: Int?
    var stripeConfigured: Bool

    static let freePeekDefault = SubscriptionStatus(
        pro: false,
        unlimited: false,
        status: "inactive",
        plan: nil,
        email: nil,
        asksUsedToday: 0,
        asksLimit: 5,
        asksRemaining: 5,
        freeDailyLimit: 5,
        stripeConfigured: false
    )

    var badgeTitle: String {
        pro ? "Pro" : "Free Peek"
    }
}

struct PaywallPayload: Codable, Hashable {
    var error: String?
    var code: String?
    var asksUsedToday: Int?
    var asksLimit: Int?
    var upgrade: UpgradeInfo?

    struct UpgradeInfo: Codable, Hashable {
        var product: String?
        var monthlyCents: Int?
        var yearlyCents: Int?
        var trialDays: Int?
    }
}

struct HealthResponse: Codable, Hashable {
    var ok: Bool
    var hasKey: Bool?
    var stripe: Bool?
    var vision: Bool?
    var stt: Bool?
    var describeScene: Bool?
}
