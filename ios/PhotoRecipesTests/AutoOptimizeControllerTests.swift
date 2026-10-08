import XCTest
@testable import PhotoRecipes

final class AutoOptimizeControllerTests: XCTestCase {

    // MARK: - pinnedRecipeId

    func testPinnedRecipeId_aoOwnPickDoesNotPin() {
        // AO's previous pick fed back as applied → nil (scoring runs).
        XCTAssertNil(
            AutoOptimizeController.pinnedRecipeId(
                staged: nil, applied: "panning", aoChosen: "panning"))
    }

    func testPinnedRecipeId_userStagedWins() {
        XCTAssertEqual(
            AutoOptimizeController.pinnedRecipeId(
                staged: "blur", applied: "panning", aoChosen: "panning"),
            "blur")
    }

    func testPinnedRecipeId_userAppliedRecipePins() {
        // A recipe the user applied (not AO's pick) still pins the run.
        XCTAssertEqual(
            AutoOptimizeController.pinnedRecipeId(
                staged: nil, applied: "hdr", aoChosen: "panning"),
            "hdr")
    }

    func testPinnedRecipeId_nothingSet() {
        XCTAssertNil(
            AutoOptimizeController.pinnedRecipeId(
                staged: nil, applied: nil, aoChosen: nil))
    }
}
