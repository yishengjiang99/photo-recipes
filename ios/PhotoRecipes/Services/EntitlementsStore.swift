import Foundation
import SwiftUI

@MainActor
final class EntitlementsStore: ObservableObject {
    @Published private(set) var status: SubscriptionStatus = .freePeekDefault
    @Published private(set) var loading = false
    @Published var lastError: String?
    @Published var showPaywall = false
    /// Soft vs hard — soft is a nudge after first AO success; hard is quota gate.
    @Published var paywallMode: PaywallMode = .hard
    @Published var paywallTrigger: String = "unknown"

    enum PaywallMode: String {
        case soft
        case hard
    }

    private let api: APIClient
    private let favoritesKey = "favorites.recipeIds"
    private let checklistKeyPrefix = "checklist."
    private let softNudgeShownKey = "paywall.softNudgeShown"

    @Published var favoriteIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favoriteIds), forKey: favoritesKey)
        }
    }

    init(api: APIClient = .shared) {
        self.api = api
        let stored = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        self.favoriteIds = Set(stored)
    }

    var isPro: Bool { status.pro }

    /// Pro always; free users when server freePhoneTargetsEnabled is on (default true offline).
    var canApplyDials: Bool {
        if isPro { return true }
        return status.freePhoneTargetsEnabled ?? true
    }

    var hasFeltOptimizeValue: Bool {
        UserDefaults.standard.bool(forKey: PushNotificationManager.hasCompletedFirstAutoOptimizeKey)
    }

    private var softNudgeShown: Bool {
        get { UserDefaults.standard.bool(forKey: softNudgeShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: softNudgeShownKey) }
    }

    /// Soft nudge once after first successful Auto Optimize (does not block camera).
    func presentSoftNudgeIfNeeded(trigger: String = "post_first_optimize") {
        guard !isPro else { return }
        guard hasFeltOptimizeValue else { return }
        guard !softNudgeShown else { return }
        softNudgeShown = true
        paywallMode = .soft
        paywallTrigger = trigger
        Analytics.shared.track("paywall_trigger", props: [
            "reason": trigger,
            "mode": "soft",
        ])
        // Let the Optimize result land (~2.5s) before the soft sheet.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !self.isPro else { return }
            self.showPaywall = true
        }
    }

    /// Hard paywall — Free Peek quota exhausted. Skip hard gate until they've felt AO value
    /// unless `force` (explicit Settings / Upgrade taps). Returns true if sheet presented.
    @discardableResult
    func presentHardPaywall(trigger: String, force: Bool = false) -> Bool {
        guard !isPro else { return false }
        if !force && !hasFeltOptimizeValue {
            // Don't hard-gate before first successful Optimize — toast/CTA elsewhere.
            Analytics.shared.track("paywall_trigger", props: [
                "reason": trigger,
                "mode": "deferred_no_value",
            ])
            return false
        }
        paywallMode = .hard
        paywallTrigger = trigger
        showPaywall = true
        Analytics.shared.track("paywall_trigger", props: [
            "reason": trigger,
            "mode": "hard",
        ])
        if trigger == "free_quota" || trigger.contains("quota") {
            Analytics.shared.track("free_quota_hit", props: [
                "trigger": trigger,
            ])
        }
        return true
    }

    func refresh() async {
        loading = true
        lastError = nil
        defer { loading = false }
        do {
            status = try await api.subscriptionStatus()
        } catch {
            lastError = error.localizedDescription
            // Keep last known / free peek default so UI stays usable offline
        }
    }

    func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteIds.contains(id)
    }

    // MARK: - Checklist (Pro-gated interactive)

    func checklistState(recipeId: String) -> [String: Bool] {
        guard let data = UserDefaults.standard.dictionary(forKey: checklistKeyPrefix + recipeId) as? [String: Bool] else {
            return [:]
        }
        return data
    }

    func setChecklistItem(recipeId: String, item: String, checked: Bool) {
        var map = checklistState(recipeId: recipeId)
        map[item] = checked
        UserDefaults.standard.set(map, forKey: checklistKeyPrefix + recipeId)
        objectWillChange.send()
    }

    func applyVerifiedPro(plan: SubscriptionPlan?) {
        status = SubscriptionStatus(
            pro: true,
            unlimited: true,
            status: "active",
            plan: plan,
            email: status.email,
            asksUsedToday: status.asksUsedToday,
            asksLimit: nil,
            asksRemaining: nil,
            freeDailyLimit: status.freeDailyLimit,
            freePhoneTargetsEnabled: status.freePhoneTargetsEnabled,
            stripeConfigured: status.stripeConfigured
        )
    }
}
