import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// Timing + geometry of the transient applied moment (AppliedFeedback.swift).
final class AppliedFeedbackStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func selfie(reduceMotion: Bool = false, face: CGRect? = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.2)) -> AppliedFeedbackState {
        AppliedFeedbackState(kind: .selfie(lookId: "selfieGlow", reason: .lowLight),
                             startedAt: t0, faceBox: face, reduceMotion: reduceMotion)
    }

    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testSelfiePillCopy() {
        let s = selfie()
        XCTAssertEqual(s.pillTitle, "✨ Selfie · Soft Glow")
        XCTAssertEqual(s.pillDetail, "low light")
        XCTAssertEqual(s.accessibilityAnnouncement, "Selfie · Soft Glow, low light")
        XCTAssertEqual(s.haptic, .soft)
    }

    func testOptimizeKind_glowOnly() {
        let s = AppliedFeedbackState(kind: .optimize, startedAt: t0, faceBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        XCTAssertNil(s.pillTitle)
        XCTAssertFalse(s.showsBracket)
        XCTAssertFalse(s.showsPill(at: at(0.1)))
        XCTAssertEqual(s.haptic, .none, "the dial burst already plays its own haptic")
        XCTAssertEqual(s.totalDuration, AppliedFeedbackState.glowDuration)
    }

    func testPillAutoDismissesAfterTwoSeconds() {
        let s = selfie()
        XCTAssertTrue(s.showsPill(at: at(0)))
        XCTAssertTrue(s.showsPill(at: at(1.99)))
        XCTAssertFalse(s.showsPill(at: at(2.0)))
        XCTAssertFalse(s.isFinished(at: at(1.9)))
        XCTAssertTrue(s.isFinished(at: at(2.0)))
    }

    func testGlowRisesThenFadesWithinSixTenths() {
        let s = selfie()
        XCTAssertEqual(s.glowOpacity(at: at(0)), 0, accuracy: 0.001)
        XCTAssertEqual(s.glowOpacity(at: at(0.15)), 1, accuracy: 0.001)
        XCTAssertGreaterThan(s.glowOpacity(at: at(0.3)), 0)
        XCTAssertEqual(s.glowOpacity(at: at(0.6)), 0)
        XCTAssertEqual(s.glowOpacity(at: at(1.5)), 0)
    }

    func testSweepTravelsOneLap_andIsOffWithReduceMotion() {
        let s = selfie()
        XCTAssertEqual(s.sweepDegrees(at: at(0))!, -90, accuracy: 0.001)
        XCTAssertEqual(s.sweepDegrees(at: at(0.6))!, 270, accuracy: 0.001)
        XCTAssertNil(selfie(reduceMotion: true).sweepDegrees(at: at(0.3)), "Reduce Motion → fade only")
        // Fade still happens with Reduce Motion.
        XCTAssertEqual(selfie(reduceMotion: true).glowOpacity(at: at(0.15)), 1, accuracy: 0.001)
    }

    func testBracketPopsThenFades() {
        let s = selfie()
        XCTAssertEqual(s.bracketOpacity(at: at(0)), 0)
        XCTAssertEqual(s.bracketOpacity(at: at(0.5)), 1)
        XCTAssertEqual(s.bracketOpacity(at: at(AppliedFeedbackState.bracketDelay + AppliedFeedbackState.bracketDuration)), 0)
        XCTAssertGreaterThan(s.bracketScale(at: at(0.1)), 1.0)
        XCTAssertEqual(s.bracketScale(at: at(0.5)), 1.0, accuracy: 0.001)
        XCTAssertEqual(selfie(reduceMotion: true).bracketScale(at: at(0.1)), 1, "no pop with Reduce Motion")
        XCTAssertEqual(selfie(face: nil).bracketOpacity(at: at(0.5)), 0)
    }

    func testBracketRect_mapsFaceAndPads() {
        let size = CGSize(width: 393, height: 852)
        let r = AppliedFeedbackState.bracketRect(
            faceBox: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.2),
            in: size, topInset: 120, bottomInset: 170, drawerOpen: false)
        XCTAssertNotNil(r)
        XCTAssertLessThan(r!.minX, 0.35 * 393)
        XCTAssertGreaterThan(r!.width, 0.3 * 393)
    }

    func testBracketRect_hiddenWhenDrawerOpen() {
        XCTAssertNil(AppliedFeedbackState.bracketRect(
            faceBox: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.2),
            in: CGSize(width: 393, height: 852), topInset: 120, bottomInset: 170, drawerOpen: true))
    }

    func testBracketRect_neverUnderRailOrHandleOrChrome() {
        let size = CGSize(width: 375, height: 667)
        let r = AppliedFeedbackState.bracketRect(
            faceBox: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
            in: size, topInset: 100, bottomInset: 140, drawerOpen: false)!
        XCTAssertGreaterThanOrEqual(r.minX, SideChromeLayout.handleGap + SideChromeLayout.handleSize)
        XCTAssertLessThanOrEqual(r.maxX, SideChromeLayout.railLeadingEdge(screenWidth: 375))
        XCTAssertGreaterThanOrEqual(r.minY, 100)
        XCTAssertLessThanOrEqual(r.maxY, 667 - 140)
    }

    func testBracketRect_dropsWhenFaceSqueezedIntoChrome() {
        // Face entirely behind the look rail → nothing left to frame.
        XCTAssertNil(AppliedFeedbackState.bracketRect(
            faceBox: CGRect(x: 0.92, y: 0.4, width: 0.08, height: 0.05),
            in: CGSize(width: 393, height: 852), topInset: 120, bottomInset: 170, drawerOpen: false))
    }
}
