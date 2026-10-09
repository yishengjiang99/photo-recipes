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

    // MARK: - subjectChangeDecision gate

    private func gate(
        secondsSinceRun: TimeInterval?, isRunning: Bool = false,
        currentRecipeId: String? = "hdr",
        topId: String? = "panning", topProb: Double = 0.7
    ) -> AutoOptimizeController.SubjectChangeDecision {
        let now = Date()
        let lastRun = secondsSinceRun.map { now.addingTimeInterval(-$0) }
        let top = topId.map { RecipeScore(recipeId: $0, probability: topProb, topFeatures: []) }
        return AutoOptimizeController.subjectChangeDecision(
            now: now, lastRunDate: lastRun, isRunning: isRunning,
            currentRecipeId: currentRecipeId, sceneTop: top)
    }

    func testSubjectChange_runningSkips() {
        XCTAssertEqual(gate(secondsSinceRun: 30, isRunning: true), .skip(reason: "running"))
    }

    func testSubjectChange_noResultSkips() {
        XCTAssertEqual(
            gate(secondsSinceRun: 30, currentRecipeId: nil),
            .skip(reason: "no_result"))
    }

    func testSubjectChange_cooldownSkips() {
        XCTAssertEqual(gate(secondsSinceRun: 3), .skip(reason: "cooldown"))
    }

    func testSubjectChange_sameRecipeSkips() {
        XCTAssertEqual(
            gate(secondsSinceRun: 12, topId: "hdr", topProb: 0.9),
            .skip(reason: "same_recipe"))
    }

    func testSubjectChange_lowConfidenceSkips() {
        XCTAssertEqual(
            gate(secondsSinceRun: 12, topId: "panning", topProb: 0.4),
            .skip(reason: "low_confidence"))
    }

    func testSubjectChange_confidentChangeReruns() {
        XCTAssertEqual(
            gate(secondsSinceRun: 12, topId: "panning", topProb: 0.7),
            .rerun)
    }

    // MARK: - resetForCameraFlip

    @MainActor
    private func makeFlipState(
        aoRecipe: String? = "panning-sharp-subject",
        appliedRecipe: String? = "panning-sharp-subject",
        aoLook: String? = "warm-glow", activeLook: String? = "warm-glow",
        phase: AutoOptimizeController.Phase = .ready
    ) -> (AutoOptimizeController, CameraSession) {
        let optimizer = AutoOptimizeController()
        let session = CameraSession()
        optimizer.chosenRecipeId = aoRecipe
        optimizer.autoAppliedLookId = aoLook
        optimizer.verifyWarning = "A bit bright"
        optimizer.phase = phase
        session.appliedRecipeId = appliedRecipe
        session.appliedRecipeTitle = "Panning"
        if let activeLook { session.activeCreativeLook = CreativeLook(id: activeLook) }
        return (optimizer, session)
    }

    @MainActor
    func testFlip_clearsAOState() {
        let (optimizer, session) = makeFlipState()
        optimizer.resetForCameraFlip(session: session)
        XCTAssertNil(optimizer.chosenRecipeId)
        XCTAssertNil(optimizer.verifyWarning)
        XCTAssertNil(optimizer.autoAppliedLookId)
        XCTAssertEqual(optimizer.phase, .idle)
        XCTAssertNil(session.appliedRecipeId)
        XCTAssertNil(session.activeCreativeLook, "AO auto-applied look must not survive the flip")
    }

    @MainActor
    func testFlip_keepsUserAppliedLook() {
        // User picked the look via the Look chip: autoAppliedLookId is nil.
        let (optimizer, session) = makeFlipState(aoLook: nil, activeLook: "user-look")
        optimizer.resetForCameraFlip(session: session)
        XCTAssertEqual(session.activeCreativeLook?.id, "user-look")
    }

    @MainActor
    func testFlip_keepsUserAppliedRecipe() {
        // appliedRecipeId is the user's own pick, not AO's.
        let (optimizer, session) = makeFlipState(
            aoRecipe: "panning-sharp-subject", appliedRecipe: "hdr-brights-darks")
        optimizer.resetForCameraFlip(session: session)
        XCTAssertEqual(session.appliedRecipeId, "hdr-brights-darks")
        XCTAssertNil(optimizer.chosenRecipeId, "AO state still resets")
    }

    @MainActor
    func testFlip_noAOState_noop() {
        let optimizer = AutoOptimizeController()
        let session = CameraSession()
        session.appliedRecipeId = "hdr-brights-darks"
        optimizer.resetForCameraFlip(session: session)
        XCTAssertEqual(session.appliedRecipeId, "hdr-brights-darks", "untouched without AO state")
        XCTAssertEqual(optimizer.phase, .idle)
    }

    @MainActor
    func testFlip_cancelsInFlightRun() {
        let (optimizer, session) = makeFlipState(phase: .verifying("Checking exposure…"))
        optimizer.resetForCameraFlip(session: session)
        XCTAssertEqual(optimizer.phase, .idle, "clear() bumps runGeneration and resets phase")
        XCTAssertNil(optimizer.chosenRecipeId)
    }
}
