import CoreGraphics
import XCTest
@testable import PhotoRecipes

/// Camera Controls drawer: Looks-grid sections and side-chrome geometry
/// (drawer below the look chip, handle never under the look rail).
final class LooksDrawerLayoutTests: XCTestCase {

    // MARK: - Looks sections

    func testLookSections_captureGradesThenSelfie() {
        let sections = CreativeLookCatalog.lookSections()
        XCTAssertEqual(sections.map(\.title), ["Capture grades", "Selfie"])
        XCTAssertEqual(sections[0].lookIds, CreativeLookCatalog.v1Ids)
        XCTAssertEqual(sections[0].lookIds.count, 14)
        XCTAssertEqual(sections[1].lookIds, CreativeLookCatalog.selfieIds)
        XCTAssertEqual(sections[1].lookIds.count, 5)
    }

    func testLookSections_selfieFirstOnFrontCamera() {
        let sections = CreativeLookCatalog.lookSections(selfieFirst: true)
        XCTAssertEqual(sections.map(\.id), ["selfie", "capture"])
        XCTAssertEqual(sections[0].lookIds, CreativeLookCatalog.selfieIds)
    }

    func testLookSections_coverEveryIdExactlyOnce() {
        for selfieFirst in [false, true] {
            let ids = CreativeLookCatalog.lookSections(selfieFirst: selfieFirst).flatMap(\.lookIds)
            XCTAssertEqual(ids.count, CreativeLookCatalog.allIds.count)
            XCTAssertEqual(Set(ids), Set(CreativeLookCatalog.allIds))
            XCTAssertTrue(CreativeLookCatalog.lookSections(selfieFirst: selfieFirst)
                .first { $0.id == "selfie" }!.lookIds.allSatisfy(CreativeLookCatalog.isSelfie))
            XCTAssertFalse(CreativeLookCatalog.lookSections(selfieFirst: selfieFirst)
                .first { $0.id == "capture" }!.lookIds.contains(where: CreativeLookCatalog.isSelfie))
        }
    }

    // MARK: - Side chrome geometry

    /// iPhone SE / mini (375, compact), 13–16 (390/393), Plus/Pro Max (428/430/440).
    private let phoneWidths: [(CGFloat, Bool)] = [(375, true), (390, false), (393, false), (402, false), (428, false), (430, false), (440, false)]

    func testDrawerWidth_baseValuesAndClamp() {
        XCTAssertEqual(SideChromeLayout.drawerWidth(compact: true, screenWidth: 375), 264)
        XCTAssertEqual(SideChromeLayout.drawerWidth(compact: false, screenWidth: 393), 288)
        // Very narrow: clamped so the open handle stays on screen.
        XCTAssertEqual(SideChromeLayout.drawerWidth(compact: true, screenWidth: 320), 250)
        XCTAssertEqual(SideChromeLayout.drawerWidth(compact: true, screenWidth: 200), SideChromeLayout.minDrawerWidth)
    }

    func testOpenHandle_staysOnScreenOnEveryPhoneWidth() {
        for (w, compact) in phoneWidths + [(320, true)] {
            XCTAssertLessThanOrEqual(
                SideChromeLayout.openHandleTrailingEdge(compact: compact, screenWidth: w),
                w - SideChromeLayout.edgeClearance, "width \(w)")
        }
    }

    func testOpenHandle_wouldOverlapRail_soRailHidesWhileOpen() {
        // The geometry that caused the bug: the handle lands under the rail on phones.
        XCTAssertTrue(SideChromeLayout.openHandleOverlapsRail(compact: true, screenWidth: 375))
        XCTAssertTrue(SideChromeLayout.openHandleOverlapsRail(compact: false, screenWidth: 393))
        // Fix: rail steps aside whenever the drawer is open, shows when closed.
        XCTAssertFalse(SideChromeLayout.showsRail(drawerOpen: true))
        XCTAssertTrue(SideChromeLayout.showsRail(drawerOpen: false))
    }

    func testTopInset_startsBelowMeasuredChrome() {
        // Look chip row pushes the measured chrome below the fixed estimate.
        XCTAssertEqual(SideChromeLayout.topInset(fixedTopChrome: 123, measuredTopChrome: 150), 150 + SideChromeLayout.topGap)
        // Before the first measurement, fall back to the fixed estimate.
        XCTAssertEqual(SideChromeLayout.topInset(fixedTopChrome: 123, measuredTopChrome: 0), 123 + SideChromeLayout.topGap)
    }
}
