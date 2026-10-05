import XCTest
@testable import PhotoRecipes

final class ViewfinderPanCueTests: XCTestCase {

    func testPanCue_down_doesNotShowLeftRightChevrons() {
        let cue = ViewfinderPanCueResolver.resolve(
            recipeId: "get-down-low",
            agentPhase: .ready,
            agentStatus: nil,
            agentPanCue: PanCue(direction: "down", note: "Drop lower")
        )
        XCTAssertNotNil(cue)
        XCTAssertEqual(cue?.left, false)
        XCTAssertEqual(cue?.right, false)
        XCTAssertEqual(cue?.down, true)
        XCTAssertEqual(cue?.caption, "Drop lower")
    }

    func testPanCue_lowerAlias_setsDownOnly() {
        let cue = ViewfinderPanCueResolver.resolve(
            recipeId: nil,
            agentPhase: .ready,
            agentStatus: nil,
            agentPanCue: PanCue(direction: "lower", note: "Drop lower")
        )
        XCTAssertEqual(cue?.down, true)
        XCTAssertEqual(cue?.left, false)
        XCTAssertEqual(cue?.right, false)
    }

    func testPanCue_either_setsLeftAndRight() {
        let cue = ViewfinderPanCueResolver.resolve(
            recipeId: "panning-sharp-subject",
            agentPhase: .ready,
            agentStatus: nil,
            agentPanCue: PanCue(direction: "either", note: "Pan with the subject")
        )
        XCTAssertEqual(cue?.left, true)
        XCTAssertEqual(cue?.right, true)
        XCTAssertEqual(cue?.down, false)
    }

    func testPanCue_horizontal_setsLeftAndRight() {
        let cue = ViewfinderPanCueResolver.resolve(
            recipeId: nil,
            agentPhase: .sensing("…"),
            agentStatus: nil,
            agentPanCue: PanCue(direction: "horizontal", note: "Pan with the subject")
        )
        XCTAssertEqual(cue?.left, true)
        XCTAssertEqual(cue?.right, true)
    }

    func testRecipe_getDownLow_chromeTitle_isShort() {
        let recipe = BundledPresets.recipe(id: "get-down-low")
        XCTAssertEqual(recipe?.chromeTitle, "Low Angle")
        XCTAssertFalse(recipe!.chromeTitle.lowercased().contains("shake"))
        XCTAssertFalse(recipe!.chromeTitle.lowercased().contains("perspective"))
    }

    func testChromeTitle_fromStoredMarketingTitle() {
        let short = Recipe.chromeTitle(
            forStoredTitle: "Shake Up Your Perspective by Getting Down Low",
            id: "get-down-low"
        )
        XCTAssertEqual(short, "Low Angle")
    }

    func testChromeTitle_panningAndHdr() {
        XCTAssertEqual(BundledPresets.recipe(id: "panning-sharp-subject")?.chromeTitle, "Panning")
        XCTAssertEqual(BundledPresets.recipe(id: "hdr-brights-darks")?.chromeTitle, "HDR")
    }
}
