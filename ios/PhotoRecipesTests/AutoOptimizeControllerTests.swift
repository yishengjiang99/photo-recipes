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

    // MARK: - verifyNotes copy

    func testVerifyNotes_minorResidual() {
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 0.4, iterations: 0, initialError: 0, yieldNote: nil),
            ["A bit bright"])
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: -0.5, iterations: 0, initialError: 0, yieldNote: nil),
            ["A bit dark"])
    }

    func testVerifyNotes_multiStopMissIsExplicit() {
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 1.2, iterations: 0, initialError: 0, yieldNote: nil),
            ["~1 stops too bright"])
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 6, iterations: 0, initialError: 0, yieldNote: nil),
            ["~6 stops too bright"])
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: -2, iterations: 0, initialError: 0, yieldNote: nil),
            ["~2 stops too dark"])
    }

    func testVerifyNotes_yieldNoteFirst() {
        let notes = AutoOptimizeController.verifyNotes(
            residual: 0, iterations: 0, initialError: 0,
            yieldNote: "Bright light: used 1/4000 s instead of 1/30 s — shade or an ND filter keeps the effect.")
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].hasPrefix("Bright light:"))
    }

    func testVerifyNotes_correctedLoop() {
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 0.1, iterations: 2, initialError: -2, yieldNote: nil),
            ["Brightened 2 stops"])
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 0.5, iterations: 1, initialError: 3, yieldNote: nil),
            ["Darkened 3 stops, still a bit bright"])
    }

    func testVerifyNotes_clean() {
        XCTAssertEqual(
            AutoOptimizeController.verifyNotes(
                residual: 0.1, iterations: 0, initialError: 0, yieldNote: nil),
            [])
    }
}
