import Foundation
import SwiftUI

@MainActor
final class CameraRouter: ObservableObject {
    enum Tab: Hashable { case camera, library, ask, settings }

    @Published var selectedTab: Tab = .camera
    @Published var stagedRecipeId: String?
    @Published var stagedRecipeTitle: String?
    @Published var pendingApply = false

    func openCamera(staging recipe: Recipe, apply: Bool = true) {
        stagedRecipeId = recipe.id
        stagedRecipeTitle = recipe.title
        pendingApply = apply
        selectedTab = .camera
    }

    func clearStaging() {
        stagedRecipeId = nil
        stagedRecipeTitle = nil
        pendingApply = false
    }
}
