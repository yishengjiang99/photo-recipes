import XCTest
@testable import PhotoRecipes

final class ApplyFiltersIntentTests: XCTestCase {

    // MARK: - matches (positives)

    func testMatches_applyBlackAndWhiteFilter() {
        XCTAssertTrue(ApplyFiltersIntent.matches("apply black and white filter"))
    }

    func testMatches_bAndW_shorthand() {
        XCTAssertTrue(ApplyFiltersIntent.matches("B&W"))
        XCTAssertTrue(ApplyFiltersIntent.matches("b&w"))
    }

    func testMatches_blackAndWhite_phrase() {
        XCTAssertTrue(ApplyFiltersIntent.matches("black and white"))
        XCTAssertTrue(ApplyFiltersIntent.matches("Black And White"))
    }

    func testMatches_warm_cinematic_tealOrange() {
        XCTAssertTrue(ApplyFiltersIntent.matches("warm"))
        XCTAssertTrue(ApplyFiltersIntent.matches("make it warm"))
        XCTAssertTrue(ApplyFiltersIntent.matches("cinematic"))
        XCTAssertTrue(ApplyFiltersIntent.matches("make it cinematic"))
        XCTAssertTrue(ApplyFiltersIntent.matches("teal orange"))
        XCTAssertTrue(ApplyFiltersIntent.matches("teal and orange"))
        XCTAssertTrue(ApplyFiltersIntent.matches("teal & orange"))
    }

    func testMatches_explicitApplyPhrases() {
        XCTAssertTrue(ApplyFiltersIntent.matches("apply filter"))
        XCTAssertTrue(ApplyFiltersIntent.matches("apply look"))
        XCTAssertTrue(ApplyFiltersIntent.matches("color grade"))
    }

    // MARK: - matches (negatives — plain scene text)

    func testMatches_negatives_plainSceneText() {
        XCTAssertFalse(ApplyFiltersIntent.matches(""))
        XCTAssertFalse(ApplyFiltersIntent.matches("   "))
        XCTAssertFalse(ApplyFiltersIntent.matches("person standing by a window"))
        XCTAssertFalse(ApplyFiltersIntent.matches("low light indoor cafe"))
        XCTAssertFalse(ApplyFiltersIntent.matches("sunset over the hills"))
        XCTAssertFalse(ApplyFiltersIntent.matches("warming up the lens before the shot"))
    }

    // MARK: - forcedLook B&W → monoInk

    func testForcedLook_blackAndWhite_isMonoInk() {
        let look = ApplyFiltersIntent.forcedLook(for: "black and white")
        XCTAssertEqual(look?.id, "monoInk")
        XCTAssertEqual(look?.intensity, CreativeLookCatalog.defaultIntensity)
    }

    func testForcedLook_bAndW_variants() {
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "B&W")?.id, "monoInk")
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "apply black and white filter")?.id, "monoInk")
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "b and w")?.id, "monoInk")
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "monochrome")?.id, "monoInk")
    }

    func testForcedLook_plainScene_isNil() {
        let phrases = ["person by a window", "low light cafe", "grab and walk"]
        for phrase in phrases {
            XCTAssertFalse(ApplyFiltersIntent.isBlackAndWhite(phrase), phrase)
            XCTAssertNil(ApplyFiltersIntent.forcedLook(for: phrase), phrase)
        }
    }

    func testForcedLook_namedLooks_mapToCatalogIds() {
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "warm")?.id, "warmGlow")
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "cinematic")?.id, "blockbuster")
        XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: "teal orange")?.id, "tealOrange")
    }

    // MARK: - resolvedLook / mergeCreativeLook (nested preferred)

    func testResolvedLook_prefersNestedPhoneTargets() {
        let nested = CreativeLook(id: "warmGlow", intensity: 0.4)
        let top = CreativeLook(id: "monoInk", intensity: 0.9)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(creativeLook: nested),
            creativeLook: top
        )
        XCTAssertEqual(ApplyFiltersIntent.resolvedLook(from: response)?.id, "warmGlow")
    }

    func testResolvedLook_topLevelAlone() {
        let top = CreativeLook(id: "tealOrange", intensity: 0.55)
        let response = RecommendResponse(creativeLook: top)
        XCTAssertEqual(ApplyFiltersIntent.resolvedLook(from: response)?.id, "tealOrange")
    }

    func testResolvedLook_emptyIdsIgnored() {
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(creativeLook: CreativeLook(id: "", intensity: 0.5)),
            creativeLook: CreativeLook(id: "blockbuster", intensity: 0.5)
        )
        XCTAssertEqual(ApplyFiltersIntent.resolvedLook(from: response)?.id, "blockbuster")
    }

    func testMergeCreativeLook_prefersNestedOverTopLevel() {
        let nested = CreativeLook(id: "warmGlow", intensity: 0.4)
        let top = CreativeLook(id: "monoInk", intensity: 0.9)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(iso: "200", creativeLook: nested),
            creativeLook: top
        )
        let merged = ApplyFiltersIntent.mergeCreativeLook(response: response, message: "warm")
        XCTAssertEqual(merged?.creativeLook?.id, "warmGlow")
        XCTAssertEqual(merged?.iso, "200")
    }

    func testMergeCreativeLook_topLevelAloneStillResolves() {
        let top = CreativeLook(id: "tealOrange", intensity: 0.55)
        let response = RecommendResponse(creativeLook: top)
        let merged = ApplyFiltersIntent.mergeCreativeLook(response: response, message: "teal orange")
        XCTAssertEqual(merged?.creativeLook?.id, "tealOrange")
    }

    func testMergeCreativeLook_bwForcesMonoInkOverWrongNested() {
        let wrong = CreativeLook(id: "warmGlow", intensity: 0.4)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(creativeLook: wrong),
            creativeLook: CreativeLook(id: "warmGlow", intensity: 0.4)
        )
        let merged = ApplyFiltersIntent.mergeCreativeLook(
            response: response,
            message: "black and white"
        )
        XCTAssertEqual(merged?.creativeLook?.id, "monoInk")
        XCTAssertEqual(merged?.creativeLook?.intensity, CreativeLookCatalog.defaultIntensity)
    }

    func testMergeCreativeLook_bwWithEmptyResponseStillForces() {
        let merged = ApplyFiltersIntent.mergeCreativeLook(
            response: RecommendResponse(),
            message: "B&W"
        )
        XCTAssertEqual(merged?.creativeLook?.id, "monoInk")
    }

    // MARK: - Voice final → recommend vs AO + cancel-in-flight

    func testPlanVoiceEndpoint_applyFilters_routesRecommendWithOverride() {
        let plan = ApplyFiltersIntent.planVoiceEndpoint("apply black and white filter")
        XCTAssertTrue(plan.cancelInFlight)
        XCTAssertEqual(
            plan.action,
            .recommend(messageOverride: "apply black and white filter")
        )
    }

    func testPlanVoiceEndpoint_namedLooks_routesRecommend() {
        for phrase in ["B&W", "warm", "cinematic", "teal orange"] {
            let plan = ApplyFiltersIntent.planVoiceEndpoint(phrase)
            XCTAssertTrue(plan.cancelInFlight, phrase)
            guard case .recommend(let override) = plan.action else {
                XCTFail("expected recommend for \(phrase)")
                continue
            }
            XCTAssertEqual(override, phrase)
        }
    }

    func testPlanVoiceEndpoint_plainScene_routesOptimize() {
        let plan = ApplyFiltersIntent.planVoiceEndpoint("person standing by a window")
        XCTAssertTrue(plan.cancelInFlight)
        XCTAssertEqual(plan.action, .optimize)
    }

    func testPlanVoiceEndpoint_empty_noCancelNoAction() {
        let plan = ApplyFiltersIntent.planVoiceEndpoint("   ")
        XCTAssertFalse(plan.cancelInFlight)
        XCTAssertEqual(plan.action, .none)
    }

    func testPlanVoiceEndpoint_newUtteranceAlwaysCancelsWhenNonEmpty() {
        // Contract: latest utterance cancels in-flight Recommend/AO before routing.
        let apply = ApplyFiltersIntent.planVoiceEndpoint("warm")
        let scene = ApplyFiltersIntent.planVoiceEndpoint("low light cafe")
        XCTAssertTrue(apply.cancelInFlight)
        XCTAssertTrue(scene.cancelInFlight)
        XCTAssertNotEqual(apply.action, scene.action)
    }
}
