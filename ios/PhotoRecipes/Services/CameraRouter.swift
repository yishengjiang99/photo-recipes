import Foundation
import SwiftUI

@MainActor
final class CameraRouter: ObservableObject {
    enum Tab: Hashable { case camera, library, ask, settings }

    @Published var selectedTab: Tab = .camera
    @Published var stagedRecipeId: String?
    @Published var stagedRecipeTitle: String?
    @Published var pendingApply = false
    /// Optional dial overlay from Recommend JSON (same applyPhoneTargets as AO).
    @Published var stagedPhoneTargets: PhoneTargets?
    /// When true, Camera tab should kick off Auto Optimize (deep link / push).
    @Published var pendingAutoOptimize = false

    func openCamera(staging recipe: Recipe, apply: Bool = true, phoneTargets: PhoneTargets? = nil) {
        stagedRecipeId = recipe.id
        stagedRecipeTitle = recipe.title
        stagedPhoneTargets = phoneTargets
        pendingApply = apply
        selectedTab = .camera
    }

    /// Deep link / push: switch to Camera and stage Auto Optimize.
    func openAutoOptimize() {
        pendingAutoOptimize = true
        selectedTab = .camera
    }

    func clearStaging() {
        stagedRecipeId = nil
        stagedRecipeTitle = nil
        stagedPhoneTargets = nil
        pendingApply = false
    }

    func consumePendingAutoOptimize() -> Bool {
        guard pendingAutoOptimize else { return false }
        pendingAutoOptimize = false
        return true
    }
}
