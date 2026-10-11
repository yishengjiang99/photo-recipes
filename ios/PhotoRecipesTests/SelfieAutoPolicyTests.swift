import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// Selfie-aware Auto Optimize: `SelfieAutoPolicy` selection rules, merge precedence and
/// the look-precedence matrix (front/back × face/no face × forced/user/auto/server look).
final class SelfieAutoPolicyTests: XCTestCase {

    // MARK: Fixtures

    /// Arm's-length selfie: one face ~0.09 of the frame, even indoor light (EV100 8).
    private func selfieFeatures(
        ev: Float? = 8,
        faceArea: Float = 0.09,
        delta: Float? = 0,
        clip: Float = 0.01,
        spread: Float = 5,
        faceCount: Int = 1,
        groups: [SemanticGroup: Float] = [.indoor: 0.7]
    ) -> SceneFeatures {
        var f = SceneFeatures()
        f.isFrontCamera = true
        f.subjectKind = .face
        let side = sqrt(faceArea)
        f.subjectBox = NormalizedBox(x: 0.5 - side / 2, y: 0.3, width: side, height: side)
        f.subjectAreaFraction = faceArea
        f.faceCount = faceCount
        f.sceneEV100 = ev
        f.subjectDeltaStops = delta
        f.highlightClipFraction = clip
        f.percentileSpreadStops = spread
        f.semanticGroups = groups
        f.meteredISO = 200
        return f
    }

    /// AO's Pass 1 solve on the front camera (custom exposure, WB, continuous focus).
    private func aoTargets(look: CreativeLook? = CreativeLook(id: "warmGlow", intensity: 0.45)) -> PhoneTargets {
        PhoneTargets(
            exposureDurationSec: 1.0 / 60,
            iso: "320",
            focusMode: "continuous",
            creativeLook: look
        )
    }

    private func input(
        front: Bool = true,
        features: SceneFeatures? = nil,
        ao: PhoneTargets? = nil,
        active: CreativeLook? = nil,
        owner: LookOwner? = nil
    ) -> SelfieAutoPolicy.Input {
        SelfieAutoPolicy.Input(
            isFrontCamera: front,
            features: features ?? selfieFeatures(),
            aoTargets: ao ?? aoTargets(),
            activeLook: active,
            activeLookOwner: owner)
    }

    private func pickedId(_ f: SceneFeatures) -> String? {
        SelfieAutoPolicy.decide(input(features: f)).choice?.look.id
    }

    // MARK: Selection rules

    func testEvenLight_picksNatural() {
        let c = SelfieAutoPolicy.decide(input()).choice
        XCTAssertEqual(c?.look.id, "selfieNatural")
        XCTAssertEqual(c?.pick.reason, .evenLight)
    }

    func testLowLight_byEV_picksLowLight() {
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 4.5))).choice
        XCTAssertEqual(c?.look.id, "selfieLowLight")
        XCTAssertEqual(c?.pick.reason, .lowLight)
    }

    func testLowLight_thresholdIsStrict() {
        XCTAssertEqual(pickedId(selfieFeatures(ev: SelfieAutoPolicy.lowLightEV100)), "selfieNatural")
        XCTAssertEqual(pickedId(selfieFeatures(ev: SelfieAutoPolicy.lowLightEV100 - 0.01)), "selfieLowLight")
    }

    func testLowLight_byISOFallback_whenEVUnknown() {
        var f = selfieFeatures(ev: nil)
        f.meteredISO = 1600
        XCTAssertEqual(pickedId(f), "selfieLowLight")
        f.meteredISO = 400
        XCTAssertEqual(pickedId(f), "selfieNatural")
    }

    func testLowLight_nightGroupBelowEV7() {
        XCTAssertEqual(pickedId(selfieFeatures(ev: 6.5, groups: [.nightOrLights: 0.8])), "selfieLowLight")
        XCTAssertEqual(pickedId(selfieFeatures(ev: 9, groups: [.nightOrLights: 0.8])), "selfieNatural")
    }

    func testLowLight_beatsBacklight() {
        XCTAssertEqual(pickedId(selfieFeatures(ev: 3, delta: -2)), "selfieLowLight")
    }

    func testBacklit_picksGlow() {
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 11, delta: -1.4))).choice
        XCTAssertEqual(c?.look.id, "selfieGlow")
        XCTAssertEqual(c?.pick.reason, .backlit)
    }

    func testSoftBacklitWithClippedSky_picksGlow() {
        XCTAssertEqual(pickedId(selfieFeatures(ev: 12, delta: -0.6, clip: 0.15)), "selfieGlow")
        XCTAssertEqual(pickedId(selfieFeatures(ev: 12, delta: -0.6, clip: 0.02)), "selfieNatural")
    }

    func testHarshOnFace_picksStudio() {
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 14, delta: 1.0))).choice
        XCTAssertEqual(c?.look.id, "selfieStudio")
        XCTAssertEqual(c?.pick.reason, .harshLight)
    }

    func testHarshContrastyFrame_picksStudio() {
        XCTAssertEqual(pickedId(selfieFeatures(ev: 14, delta: 0, clip: 0.08, spread: 8)), "selfieStudio")
        XCTAssertEqual(pickedId(selfieFeatures(ev: 14, delta: 0, clip: 0.08, spread: 6)), "selfieNatural")
    }

    func testSmallFace_picksPortrait() {
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(faceArea: 0.02))).choice
        XCTAssertEqual(c?.look.id, "selfiePortrait")
        XCTAssertEqual(c?.pick.reason, .smallSubject)
    }

    func testBusyOutdoorBackground_picksPortrait() {
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 11, groups: [.architecture: 0.7]))).choice
        XCTAssertEqual(c?.look.id, "selfiePortrait")
        XCTAssertEqual(c?.pick.reason, .busyBackground)
    }

    func testBusyGroupIndoors_staysNatural() {
        XCTAssertEqual(pickedId(selfieFeatures(groups: [.architecture: 0.7, .indoor: 0.8])), "selfieNatural")
    }

    func testGroupSelfie_neverPortraitBlur() {
        XCTAssertEqual(pickedId(selfieFeatures(faceArea: 0.02, faceCount: 3)), "selfieNatural")
        XCTAssertEqual(pickedId(selfieFeatures(faceCount: 4, groups: [.landscape: 0.9])), "selfieNatural")
    }

    func testEveryPickIsAKnownSelfieLookWithAPreset() {
        let cases: [SceneFeatures] = [
            selfieFeatures(), selfieFeatures(ev: 2), selfieFeatures(delta: -2),
            selfieFeatures(delta: 1.2), selfieFeatures(faceArea: 0.02),
        ]
        var seen = Set<String>()
        for f in cases {
            guard let id = pickedId(f) else { return XCTFail("no pick") }
            XCTAssertTrue(CreativeLookCatalog.isSelfie(id))
            XCTAssertNotNil(SelfiePresets.preset(lookId: id))
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, 5, "every selfie look is reachable")
    }

    // MARK: Face gate

    func testNoFace_unchanged() {
        var f = selfieFeatures()
        f.subjectKind = .salientObject
        XCTAssertEqual(SelfieAutoPolicy.decide(input(features: f)), .unchanged(.noFace))
        f.subjectKind = nil
        f.subjectBox = nil
        XCTAssertEqual(SelfieAutoPolicy.decide(input(features: f)), .unchanged(.noFace))
    }

    func testTinyBackgroundFace_unchanged() {
        XCTAssertEqual(
            SelfieAutoPolicy.decide(input(features: selfieFeatures(faceArea: 0.004))),
            .unchanged(.faceTooSmall))
    }

    func testFaceAreaFallsBackToBoxArea() {
        var f = selfieFeatures(faceArea: 0.09)
        f.subjectAreaFraction = 0
        XCTAssertEqual(SelfieAutoPolicy.faceArea(f), 0.09, accuracy: 0.001)
    }

    func testBackCamera_unchanged() {
        XCTAssertEqual(SelfieAutoPolicy.decide(input(front: false)), .unchanged(.backCamera))
    }

    // MARK: Look precedence matrix

    func testPrecedenceMatrix() {
        struct Row {
            let front: Bool
            let face: Bool
            let active: CreativeLook?
            let owner: LookOwner?
            let aoLook: CreativeLook?
            let expect: String // "unchanged" | "keep:<id>" | "apply:<id>"
        }
        let mono = CreativeLook(id: "monoInk", intensity: 1)
        let drawer = CreativeLook(id: "softDream", intensity: 0.6)
        let warm = CreativeLook(id: "warmGlow", intensity: 0.45)
        let server = CreativeLook(id: "tealOrange", intensity: 0.5)
        let rows: [Row] = [
            Row(front: false, face: true, active: nil, owner: nil, aoLook: warm, expect: "unchanged"),
            Row(front: false, face: true, active: mono, owner: .forced, aoLook: warm, expect: "unchanged"),
            Row(front: true, face: false, active: nil, owner: nil, aoLook: warm, expect: "unchanged"),
            Row(front: true, face: false, active: drawer, owner: .user, aoLook: nil, expect: "unchanged"),
            Row(front: true, face: true, active: nil, owner: nil, aoLook: warm, expect: "apply:selfieNatural"),
            Row(front: true, face: true, active: nil, owner: nil, aoLook: server, expect: "apply:selfieNatural"),
            Row(front: true, face: true, active: nil, owner: nil, aoLook: nil, expect: "apply:selfieNatural"),
            // Forced (voice / named look) wins.
            Row(front: true, face: true, active: mono, owner: .forced, aoLook: warm, expect: "keep:monoInk"),
            // Manual drawer / rail / chip pick wins.
            Row(front: true, face: true, active: drawer, owner: .user, aoLook: warm, expect: "keep:softDream"),
            Row(front: true, face: true, active: CreativeLook(id: "selfieGlow"), owner: .user, aoLook: nil, expect: "keep:selfieGlow"),
            // A previous AO / server look is replaced (selfie wins on front).
            Row(front: true, face: true, active: server, owner: .auto, aoLook: warm, expect: "apply:selfieNatural"),
        ]
        for (i, row) in rows.enumerated() {
            var f = selfieFeatures()
            if !row.face { f.subjectKind = .salientObject }
            let d = SelfieAutoPolicy.decide(input(
                front: row.front, features: f, ao: aoTargets(look: row.aoLook),
                active: row.active, owner: row.owner))
            let got: String = {
                switch d {
                case .unchanged: return "unchanged"
                case .keepLook(let id, _, _): return "keep:\(id)"
                case .apply(let c): return "apply:\(c.look.id)"
                }
            }()
            XCTAssertEqual(got, row.expect, "row \(i)")
        }
    }

    func testServerNonSelfieLook_isRecordedAsReplaced() {
        let c = SelfieAutoPolicy.decide(input(ao: aoTargets(look: CreativeLook(id: "tealOrange")))).choice
        XCTAssertEqual(c?.replacedLookId, "tealOrange")
        let none = SelfieAutoPolicy.decide(input(ao: aoTargets(look: nil))).choice
        XCTAssertNil(none?.replacedLookId)
    }

    // MARK: Intensity

    func testIntensity_inheritsAOClamped_or055() {
        XCTAssertEqual(SelfieAutoPolicy.decide(input(ao: aoTargets(look: nil))).choice?.look.intensity, 0.55)
        XCTAssertEqual(SelfieAutoPolicy.decide(input(ao: aoTargets(look: CreativeLook(id: "warmGlow", intensity: 0.45)))).choice?.look.intensity, 0.45)
        XCTAssertEqual(SelfieAutoPolicy.decide(input(ao: aoTargets(look: CreativeLook(id: "warmGlow", intensity: 1)))).choice?.look.intensity, SelfieAutoPolicy.maxIntensity)
        XCTAssertEqual(SelfieAutoPolicy.decide(input(ao: aoTargets(look: CreativeLook(id: "warmGlow", intensity: 0.1)))).choice?.look.intensity, SelfieAutoPolicy.minIntensity)
    }

    // MARK: Merge precedence

    func testMerge_aoExposureAndWBAuthoritative_presetLightApplied() {
        var ao = aoTargets(look: nil)
        ao.whiteBalance = .temperatureTint(temperature: 5200, tint: 0)
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 3), ao: ao)).choice!
        XCTAssertEqual(c.look.id, "selfieLowLight")
        XCTAssertEqual(c.targets.exposureDurationSec, 1.0 / 60)
        XCTAssertEqual(c.targets.iso, "320")
        XCTAssertNil(c.targets.ev, "EV folded into AO's custom solve — preset EV dropped")
        XCTAssertEqual(c.targets.whiteBalance, ao.whiteBalance)
        XCTAssertEqual(c.targets.flash, "on")
        XCTAssertEqual(c.targets.lowLightBoost, true)
        XCTAssertEqual(c.targets.focusMode, "continuous")
        XCTAssertEqual(c.targets.creativeLook?.id, "selfieLowLight")
        XCTAssertTrue(c.meterOnFace)
    }

    func testMerge_presetEVWhenAOLeftSystemAuto() {
        let ao = PhoneTargets(focusMode: "continuous")
        let c = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 11, delta: -1.5), ao: ao)).choice!
        XCTAssertEqual(c.look.id, "selfieGlow")
        XCTAssertEqual(c.targets.ev, "+0.5")
        XCTAssertEqual(c.targets.flash, "auto")
    }

    func testMerge_aoEVKept() {
        let ao = PhoneTargets(ev: "-0.3")
        let c = SelfieAutoPolicy.decide(input(ao: ao)).choice!
        XCTAssertEqual(c.targets.ev, "-0.3")
    }

    func testMerge_neverTorchOrLensSwitchOnFront() {
        var ao = aoTargets(look: nil)
        ao.cameraDevice = "tele"
        ao.torch = TorchTarget(mode: "on", level: 0.5)
        let c = SelfieAutoPolicy.decide(input(ao: ao)).choice!
        XCTAssertNil(c.targets.cameraDevice)
        XCTAssertNil(c.targets.torch)
    }

    func testStudioWBHold_onlyWhenAOSetNoWB() {
        let harsh = selfieFeatures(ev: 14, delta: 1.0)
        XCTAssertEqual(SelfieAutoPolicy.decide(input(features: harsh, ao: aoTargets(look: nil))).choice?.lockWhiteBalanceAfterAE, true)
        var ao = aoTargets(look: nil)
        ao.whiteBalance = .temperatureTint(temperature: 5600, tint: 0)
        XCTAssertEqual(SelfieAutoPolicy.decide(input(features: harsh, ao: ao)).choice?.lockWhiteBalanceAfterAE, false)
    }

    func testApplyTargets_stripLookAndMoveApertureToCoach() {
        let d = SelfieAutoPolicy.decide(input(features: selfieFeatures(faceArea: 0.02), ao: aoTargets(look: nil)))
        XCTAssertEqual(d.choice?.look.id, "selfiePortrait")
        let applied = AutoOptimizeController.selfieApplyTargets(d, aoTargets: aoTargets(look: nil))
        XCTAssertNil(applied.targets.creativeLook, "look is set once via setActiveLook, not via applyPhoneTargets")
        XCTAssertNil(applied.targets.simulatedAperture)
        XCTAssertEqual(applied.apertureCoach, "f/2.0 guidance only — phone lens is fixed.")
        // Back camera: AO's targets pass through untouched.
        let ao = aoTargets()
        let back = AutoOptimizeController.selfieApplyTargets(.unchanged(.backCamera), aoTargets: ao)
        XCTAssertEqual(back.targets, ao)
        XCTAssertNil(back.apertureCoach)
    }

    // MARK: Still bake

    func testChosenLook_bakesFaceRetouchOnStill() {
        for f in [selfieFeatures(), selfieFeatures(ev: 2), selfieFeatures(delta: -2), selfieFeatures(delta: 1.2), selfieFeatures(faceArea: 0.02)] {
            let c = SelfieAutoPolicy.decide(input(features: f)).choice!
            let retouch = SelfiePresets.retouch(lookId: c.look.id, intensity: c.look.resolvedIntensity)
            XCTAssertNotNil(retouch)
            XCTAssertTrue(retouch!.hasFaceSteps, "\(c.look.id) must bake face retouch at \(c.look.resolvedIntensity)")
        }
    }

    // MARK: Pass 2 server look

    func testServerLook_neverReplacesSelfieOnFront() {
        let teal = CreativeLook(id: "tealOrange", intensity: 0.5)
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(teal, selfieLookId: "selfieGlow", activeLook: nil))
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(teal, selfieLookId: "selfieGlow", activeLook: CreativeLook(id: "selfieGlow")))
        // No selfie this run → existing rule: fill an empty finder only.
        XCTAssertEqual(SelfieAutoPolicy.resolveServerLook(teal, selfieLookId: nil, activeLook: nil), teal)
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(teal, selfieLookId: nil, activeLook: CreativeLook(id: "warmGlow")))
        XCTAssertNil(SelfieAutoPolicy.resolveServerLook(CreativeLook(id: "notALook"), selfieLookId: nil, activeLook: nil))
    }

    // MARK: Telemetry

    func testTelemetry_applyAndForcedOverride_noPII() {
        let applied = SelfieAutoPolicy.decide(input(features: selfieFeatures(ev: 3), ao: aoTargets(look: CreativeLook(id: "warmGlow"))))
        let p = SelfieAutoPolicy.telemetryProps(applied, trigger: "voice", runId: "r1")
        XCTAssertEqual(p?["look_id"], "selfieLowLight")
        XCTAssertEqual(p?["reason"], "low_light")
        XCTAssertEqual(p?["forced_override"], "0")
        XCTAssertEqual(p?["replaced_look"], "1")
        XCTAssertEqual(p?["trigger"], "voice")

        let kept = SelfieAutoPolicy.decide(input(active: CreativeLook(id: "monoInk"), owner: .forced))
        let k = SelfieAutoPolicy.telemetryProps(kept, trigger: "manual", runId: "r2")
        XCTAssertEqual(k?["forced_override"], "1")
        XCTAssertEqual(k?["kept_owner"], "forced")
        XCTAssertEqual(k?["look_id"], "selfieNatural")

        XCTAssertNil(SelfieAutoPolicy.telemetryProps(.unchanged(.noFace), trigger: "manual", runId: "r3"))

        // Only ids / booleans / short enums — no coordinates, no face geometry.
        for props in [p!, k!] {
            XCTAssertEqual(Set(props.keys), ["look_id", "reason", "forced_override", "kept_owner", "replaced_look", "trigger", "run_id"])
            for v in props.values { XCTAssertLessThan(v.count, 64) }
        }
    }
}
