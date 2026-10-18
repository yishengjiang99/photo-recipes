import XCTest
@testable import PhotoRecipes

/// Post-onboarding landing (PhotoRecipesApp's OnboardingView completion):
/// finishing onboarding routes via CameraRouter.openCamera(), so a brand-new
/// user's first session ends on the camera tab — even if something staged a
/// different tab during first launch — without staging a recipe or
/// auto-starting Auto Optimize.
@MainActor
final class OnboardingLandingTests: XCTestCase {
    func testCameraIntentLandsOnCameraTabFromAnyTab() {
        let router = CameraRouter()
        for tab in [CameraRouter.Tab.library, .ask, .settings] {
            router.selectedTab = tab
            router.openCamera()
            XCTAssertEqual(router.selectedTab, .camera, "from \(tab)")
        }
    }

    func testCameraIntentStagesNothing() {
        let router = CameraRouter()
        router.openCamera()
        XCTAssertEqual(router.selectedTab, .camera)
        XCTAssertFalse(router.pendingAutoOptimize)
        XCTAssertFalse(router.pendingApply)
        XCTAssertNil(router.stagedRecipeId)
        XCTAssertNil(router.stagedRecipeTitle)
        XCTAssertNil(router.stagedPhoneTargets)
    }
}
