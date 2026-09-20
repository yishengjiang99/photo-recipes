import Foundation
import SwiftUI

@MainActor
final class EntitlementsStore: ObservableObject {
    @Published private(set) var status: SubscriptionStatus = .freePeekDefault
    @Published private(set) var loading = false
    @Published var lastError: String?
    @Published var showPaywall = false

    private let api: APIClient
    private let favoritesKey = "favorites.recipeIds"
    private let checklistKeyPrefix = "checklist."

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
