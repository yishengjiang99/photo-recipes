import CoreGraphics

/// Pure geometry for the Camera tab's side chrome: the slide-out Controls drawer
/// (left, panel + attached handle) and the right-edge look rail. Kept free of
/// SwiftUI so the overlap rules are unit-tested.
enum SideChromeLayout {
    /// Drawer handle (circle button) size and its gap from the panel.
    static let handleSize: CGFloat = 56
    static let handleGap: CGFloat = 6
    /// Look rail: 40pt buttons + 6pt horizontal padding each side, 8pt from the edge.
    static let railWidth: CGFloat = 52
    static let railTrailingPad: CGFloat = 8
    /// Minimum clear space kept between the open handle and the screen edge.
    static let edgeClearance: CGFloat = 8
    /// Space between the bottom of the top chrome (status / look chip) and the drawer.
    static let topGap: CGFloat = 8
    static let minDrawerWidth: CGFloat = 220

    /// Drawer panel width. 264 compact / 288 regular, clamped so the open handle
    /// always stays fully on screen on narrow phones.
    static func drawerWidth(compact: Bool, screenWidth: CGFloat) -> CGFloat {
        let base: CGFloat = compact ? 264 : 288
        let fit = screenWidth - handleGap - handleSize - edgeClearance
        return max(minDrawerWidth, min(base, fit))
    }

    /// x of the open handle's right edge (drawer is pinned to the leading edge).
    static func openHandleTrailingEdge(compact: Bool, screenWidth: CGFloat) -> CGFloat {
        drawerWidth(compact: compact, screenWidth: screenWidth) + handleGap + handleSize
    }

    /// x of the look rail's left edge.
    static func railLeadingEdge(screenWidth: CGFloat) -> CGFloat {
        screenWidth - railTrailingPad - railWidth
    }

    /// True when an open drawer's handle would sit under the look rail. Holds on
    /// every iPhone width (SE/mini 375 compact: 326 > 315; 393: 350 > 333), which
    /// is why the rail steps aside whenever the drawer is open.
    static func openHandleOverlapsRail(compact: Bool, screenWidth: CGFloat) -> Bool {
        openHandleTrailingEdge(compact: compact, screenWidth: screenWidth) > railLeadingEdge(screenWidth: screenWidth)
    }

    /// The rail hides while the drawer is open: the Looks tab covers the same
    /// looks, and the handle never ends up under it on any width.
    static func showsRail(drawerOpen: Bool) -> Bool { !drawerOpen }

    /// Top inset for the side chrome: below the *measured* top chrome (flash row,
    /// status pill, look chip) so the drawer never covers the look chip — the one
    /// primary status (Build 28) stays readable and tappable. Falls back to the
    /// fixed estimate before the first measurement.
    static func topInset(fixedTopChrome: CGFloat, measuredTopChrome: CGFloat) -> CGFloat {
        max(fixedTopChrome, measuredTopChrome) + topGap
    }
}
