import XCTest
@testable import PhotoRecipes

/// Integration-style XCTest: common inference utterances → iOS apply-path routing.
/// Mirrors server `LOOK_UTTERANCE_MATRIX` / `CREATIVE_LOOK_OVERRIDE_RULES` / `phoneTargets.test.ts`
/// (Build 29 / agentic #131). Do not invent CreativeLook ids.
///
/// Agentic field → iOS method mapping (asserted below):
/// | agentic field | iOS method / property |
/// | phoneTargets.creativeLook | applyPhoneTargets(..., autoApplyLook:) / setActiveLook / activeCreativeLook |
/// | phoneTargets.shutter/ISO/EV/WB/focus/zoom/focusPoint/flash/torch | applyPhoneTargets dials |
/// | panCue | ViewfinderPanCueResolver (down≠L/R) |
/// | coachOnly | NOT applied as phone dials |
/// | top-level creativeLook | fallback via mergeCreativeLook |
final class InferenceApplyPathTests: XCTestCase {

    // MARK: - A. LOOK_UTTERANCE_MATRIX → Recommend + autoApplyLook

    func testLookUtteranceMatrix_coversEveryV1Id() {
        let seen = Set(ApplyFiltersIntent.lookUtteranceMatrix.map(\.id))
        for id in CreativeLookCatalog.allIds {
            XCTAssertTrue(seen.contains(id), "missing matrix coverage for V1 id: \(id)")
        }
        for id in seen {
            XCTAssertTrue(CreativeLookCatalog.isKnown(id), "invented id not in catalog: \(id)")
        }
    }

    func testLookUtteranceMatrix_eachRow_matchesForcedLookRecommendAutoApply() {
        for (utterance, expectedId) in ApplyFiltersIntent.lookUtteranceMatrix {
            XCTAssertTrue(
                ApplyFiltersIntent.matches(utterance),
                "matches false for matrix utterance: \(utterance)"
            )
            let forced = ApplyFiltersIntent.forcedLook(for: utterance)
            XCTAssertEqual(forced?.id, expectedId, "forcedLook id for: \(utterance)")
            XCTAssertEqual(
                forced?.intensity,
                CreativeLookCatalog.defaultIntensity,
                "intensity 0.55 for: \(utterance)"
            )

            let path = ApplyFiltersIntent.resolveApplyPath(utterance)
            XCTAssertTrue(path.matches, utterance)
            XCTAssertEqual(path.forcedLookId, expectedId, utterance)
            XCTAssertEqual(path.method, .runRecommendAutoApplyLook, utterance)
            XCTAssertTrue(path.autoApplyLook, utterance)
            XCTAssertTrue(path.cancelInFlight, utterance)
            XCTAssertEqual(path.iosEntry, "runRecommend(messageOverride:)", utterance)

            let plan = ApplyFiltersIntent.planVoiceEndpoint(utterance)
            guard case .recommend(let override) = plan.action else {
                XCTFail("expected runRecommend for \(utterance)")
                continue
            }
            XCTAssertEqual(override, utterance)

            // mergeCreativeLook + autoApplyLook would set that look (unit-level).
            let merged = ApplyFiltersIntent.mergeCreativeLook(
                response: RecommendResponse(),
                message: utterance
            )
            XCTAssertEqual(merged?.creativeLook?.id, expectedId, "merge for: \(utterance)")
            XCTAssertEqual(
                merged?.creativeLook?.intensity,
                CreativeLookCatalog.defaultIntensity,
                "merge intensity for: \(utterance)"
            )
        }
    }

    func testMakeItCinematicAndWarm_routeRecommendWithForcedLook() {
        let pairs = [
            ("make it cinematic", "blockbuster"),
            ("make it warm", "warmGlow"),
        ]
        for (utterance, id) in pairs {
            XCTAssertTrue(ApplyFiltersIntent.matches(utterance), utterance)
            XCTAssertEqual(ApplyFiltersIntent.forcedLook(for: utterance)?.id, id, utterance)
            let path = ApplyFiltersIntent.resolveApplyPath(utterance)
            XCTAssertEqual(path.method, .runRecommendAutoApplyLook, utterance)
            XCTAssertTrue(path.autoApplyLook, utterance)
        }
    }

    // MARK: - B. apply filters — matches, forcedLook nil; missing look error; with look → autoApply

    func testApplyFilters_matchesButForcedLookNil() {
        for phrase in ["apply filters", "apply filter"] {
            XCTAssertTrue(ApplyFiltersIntent.matches(phrase), phrase)
            XCTAssertNil(ApplyFiltersIntent.forcedLook(for: phrase), phrase)
            let path = ApplyFiltersIntent.resolveApplyPath(phrase)
            XCTAssertTrue(path.matches, phrase)
            XCTAssertNil(path.forcedLookId, phrase)
            XCTAssertEqual(path.method, .runRecommendAutoApplyLook, phrase)
            XCTAssertTrue(path.autoApplyLook, phrase)
        }
    }

    func testApplyFilters_missingCreativeLook_reportsErrorPath() {
        let response = RecommendResponse()
        XCTAssertTrue(
            ApplyFiltersIntent.reportsMissingLook(message: "apply filters", response: response)
        )
        XCTAssertEqual(
            ApplyFiltersIntent.missingLookMessage,
            "No look returned — try again (server should send a creativeLook)"
        )
    }

    func testApplyFilters_withServerLook_autoApplyLookNoError() {
        let look = CreativeLook(id: "tealOrange", intensity: 0.55)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(creativeLook: look)
        )
        XCTAssertFalse(
            ApplyFiltersIntent.reportsMissingLook(message: "apply filters", response: response)
        )
        let merged = ApplyFiltersIntent.mergeCreativeLook(
            response: response,
            message: "apply filters"
        )
        XCTAssertEqual(merged?.creativeLook?.id, "tealOrange")
        // Path still Recommend + autoApplyLook (server/model supplies look).
        let path = ApplyFiltersIntent.resolveApplyPath("apply filters")
        XCTAssertEqual(path.method, .runRecommendAutoApplyLook)
        XCTAssertTrue(path.autoApplyLook)
    }

    func testApplyFilters_topLevelLookFallback_viaMergeCreativeLook() {
        let top = CreativeLook(id: "softDream", intensity: 0.55)
        let response = RecommendResponse(creativeLook: top)
        let merged = ApplyFiltersIntent.mergeCreativeLook(
            response: response,
            message: "apply filters"
        )
        XCTAssertEqual(merged?.creativeLook?.id, "softDream")
        XCTAssertEqual(ApplyFiltersIntent.resolvedLook(from: response)?.id, "softDream")
    }

    // MARK: - C. Controls — matches false → AO / applyPhoneTargets dials only

    /// Control utterances (no look words) → matches false, runOptimize, forcedLook nil.
    /// When Recommend/AO returns phoneTargets, iOS applies dials via applyPhoneTargets
    /// (autoApplyLook: false on AO path) — never forcedLook.
    func testControls_matchFalse_routeOptimize_noForcedLook() {
        let controls = [
            "slower shutter",
            "lock focus",
            "zoom 2x",
            "EV +0.7",
            "daylight white balance",
            "ultra wide",
            "torch on",
            "flash off",
            "bracket three stops",
            "monitor subject area change",
        ]
        for utterance in controls {
            XCTAssertFalse(ApplyFiltersIntent.matches(utterance), utterance)
            XCTAssertNil(ApplyFiltersIntent.forcedLook(for: utterance), utterance)
            let path = ApplyFiltersIntent.resolveApplyPath(utterance)
            XCTAssertFalse(path.matches, utterance)
            XCTAssertNil(path.forcedLookId, utterance)
            XCTAssertEqual(path.method, .runOptimize, utterance)
            XCTAssertFalse(path.autoApplyLook, utterance)
            XCTAssertEqual(path.iosEntry, "runOptimize", utterance)
        }
    }

    func testControls_phoneTargetsJSON_mapsToDials_notCreativeLook() throws {
        // Fixture: control-style RecommendResponse — dials only, no creativeLook required.
        let json = """
        {
          "phoneTargets": {
            "shutter": "1/30",
            "iso": "200",
            "ev": "+0.7",
            "whiteBalance": "daylight",
            "focusMode": "locked",
            "zoom": 2,
            "focusPoint": { "x": 0.5, "y": 0.5 },
            "flash": "off",
            "torch": { "mode": "on", "level": 0.5 },
            "cameraDevice": "ultraWide",
            "bracket": { "stops": [-1, 0, 1], "count": 3 },
            "monitorSubjectAreaChange": true
          },
          "panCue": { "direction": "down", "note": "Drop lower" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendResponse.self, from: json)
        let t = try XCTUnwrap(response.phoneTargets)
        XCTAssertEqual(t.shutter, "1/30")
        XCTAssertEqual(t.iso, "200")
        XCTAssertEqual(t.ev, "+0.7")
        if case .mode(let m) = t.whiteBalance {
            XCTAssertEqual(m, "daylight")
        } else {
            XCTFail("expected whiteBalance mode daylight")
        }
        XCTAssertEqual(t.focusMode, "locked")
        XCTAssertEqual(t.zoom, 2)
        XCTAssertEqual(t.focusPoint?.x, 0.5)
        XCTAssertEqual(t.flash, "off")
        XCTAssertEqual(t.torch?.mode, "on")
        XCTAssertEqual(t.cameraDevice, "ultraWide")
        XCTAssertEqual(t.bracket?.stops, [-1, 0, 1])
        XCTAssertEqual(t.monitorSubjectAreaChange, true)
        XCTAssertNil(t.creativeLook)
        XCTAssertNil(response.creativeLook)

        // Dial key names documented for applyPhoneTargets (not coachOnly).
        for key in ["shutter", "iso", "ev", "whiteBalance", "focusMode", "zoom",
                    "focusPoint", "flash", "torch", "cameraDevice", "bracket",
                    "monitorSubjectAreaChange"] {
            XCTAssertTrue(
                ApplyFiltersIntent.phoneTargetDialKeyNames.contains(key),
                "missing dial key: \(key)"
            )
        }

        // panCue → ViewfinderPanCueResolver (down ≠ L/R)
        let cue = ViewfinderPanCueResolver.resolve(
            recipeId: nil,
            agentPhase: .ready,
            agentStatus: nil,
            agentPanCue: response.panCue
        )
        XCTAssertEqual(cue?.down, true)
        XCTAssertEqual(cue?.left, false)
        XCTAssertEqual(cue?.right, false)
    }

    // MARK: - D. No look words → creativeLook not required

    func testNoLookWords_sceneUtterances_noCreativeLookRequired() {
        let scenes = [
            "person by a window",
            "low light cafe",
            "sunset over hills",
            "silky waterfall",
            "person standing by a window",
        ]
        for utterance in scenes {
            XCTAssertFalse(ApplyFiltersIntent.matches(utterance), utterance)
            XCTAssertNil(ApplyFiltersIntent.forcedLook(for: utterance), utterance)
            let path = ApplyFiltersIntent.resolveApplyPath(utterance)
            XCTAssertEqual(path.method, .runOptimize, utterance)
            XCTAssertFalse(
                ApplyFiltersIntent.reportsMissingLook(
                    message: utterance,
                    response: RecommendResponse()
                ),
                utterance
            )
        }
    }

    // MARK: - E. coachOnly never AV write

    func testCoachOnly_parsedSeparately_neverBecomesDials() throws {
        let json = """
        {
          "phoneTargets": {
            "shutter": "1/60",
            "iso": "100"
          },
          "coachOnly": {
            "aperture": "f/1.8",
            "nd": "ND8",
            "tripod": true,
            "notes": "Use a tripod for this shutter"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendResponse.self, from: json)
        XCTAssertEqual(response.phoneTargets?.shutter, "1/60")
        XCTAssertEqual(response.phoneTargets?.iso, "100")
        XCTAssertNil(response.phoneTargets?.creativeLook)

        let coach = try XCTUnwrap(response.coachOnly)
        XCTAssertEqual(coach.aperture, "f/1.8")
        XCTAssertEqual(coach.nd, "ND8")
        XCTAssertEqual(coach.tripod, true)
        XCTAssertEqual(coach.notes, "Use a tripod for this shutter")

        // coachOnly keys are not PhoneTargets CodingKeys / dial names.
        for key in ApplyFiltersIntent.coachOnlyKeyNames {
            XCTAssertFalse(
                ApplyFiltersIntent.phoneTargetDialKeyNames.contains(key),
                "coachOnly key \(key) must not be an applyPhoneTargets dial"
            )
        }

        // Encoding PhoneTargets must not smuggle aperture/nd/tripod.
        let encoded = try JSONEncoder().encode(response.phoneTargets!)
        let obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNil(obj?["aperture"])
        XCTAssertNil(obj?["nd"])
        XCTAssertNil(obj?["tripod"])
        XCTAssertNil(obj?["notes"])
    }

    // MARK: - F. Empty AO vs non-empty Recommend routing

    func testRouting_empty_noAction_nonEmptyLook_recommend() {
        let empty = ApplyFiltersIntent.resolveApplyPath("   ")
        XCTAssertEqual(empty.method, .none)
        XCTAssertFalse(empty.cancelInFlight)
        XCTAssertEqual(empty.iosEntry, "none")

        let look = ApplyFiltersIntent.resolveApplyPath("warm glow")
        XCTAssertEqual(look.method, .runRecommendAutoApplyLook)
        XCTAssertEqual(look.iosEntry, "runRecommend(messageOverride:)")
        XCTAssertTrue(look.autoApplyLook)
        XCTAssertEqual(look.forcedLookId, "warmGlow")
    }

    func testRouting_nonEmptyScene_optimize_notRecommendForFilters() {
        let path = ApplyFiltersIntent.resolveApplyPath("person by a window")
        XCTAssertEqual(path.method, .runOptimize)
        XCTAssertEqual(path.iosEntry, "runOptimize")
        XCTAssertFalse(path.autoApplyLook)
    }

    // MARK: - C (cancel/replace): warm → monoInk forcedLook replace

    func testCancelReplace_warmThenMonoInk_forcedLookWins() {
        let warmFirst = ApplyFiltersIntent.planVoiceEndpoint("warm")
        XCTAssertTrue(warmFirst.cancelInFlight)
        guard case .recommend = warmFirst.action else {
            return XCTFail("warm → recommend")
        }

        // New APPLY-FILTERS utterance cancels prior in-flight and replaces look.
        let bw = ApplyFiltersIntent.planVoiceEndpoint("B&W")
        XCTAssertTrue(bw.cancelInFlight)
        guard case .recommend(let override) = bw.action else {
            return XCTFail("B&W → recommend")
        }
        XCTAssertEqual(override, "B&W")

        let wrongNested = CreativeLook(id: "warmGlow", intensity: 0.9)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(iso: "200", creativeLook: wrongNested),
            creativeLook: wrongNested
        )
        let merged = ApplyFiltersIntent.mergeCreativeLook(response: response, message: "B&W")
        XCTAssertEqual(merged?.creativeLook?.id, "monoInk")
        XCTAssertEqual(merged?.creativeLook?.intensity, CreativeLookCatalog.defaultIntensity)
        XCTAssertEqual(merged?.iso, "200")

        // warm → monoInk replace via forcedLook on resolve path
        let replace = ApplyFiltersIntent.resolveApplyPath("B&W")
        XCTAssertEqual(replace.forcedLookId, "monoInk")
        XCTAssertEqual(replace.method, .runRecommendAutoApplyLook)
        XCTAssertTrue(replace.cancelInFlight)
    }

    // MARK: - Nested vs top-level + intensity contract

    func testMerge_nestedPreferred_forcedLookAlwaysWinsLast() {
        let nested = CreativeLook(id: "warmGlow", intensity: 0.4)
        let top = CreativeLook(id: "tealOrange", intensity: 0.9)
        let response = RecommendResponse(
            phoneTargets: PhoneTargets(creativeLook: nested),
            creativeLook: top
        )
        XCTAssertEqual(ApplyFiltersIntent.resolvedLook(from: response)?.id, "warmGlow")

        let noForce = ApplyFiltersIntent.mergeCreativeLook(
            response: response,
            message: "apply filters"
        )
        XCTAssertEqual(noForce?.creativeLook?.id, "warmGlow")

        let forced = ApplyFiltersIntent.mergeCreativeLook(
            response: response,
            message: "cinematic"
        )
        XCTAssertEqual(forced?.creativeLook?.id, "blockbuster")
        XCTAssertEqual(forced?.creativeLook?.intensity, 0.55)
    }

    func testDefaultIntensity_is055() {
        XCTAssertEqual(CreativeLookCatalog.defaultIntensity, 0.55)
    }
}
