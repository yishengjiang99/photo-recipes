import SwiftUI
import UIKit

/// Transient "it worked" moment after Auto Optimize applies — a soft warm glow
/// sweeping the finder edges (~0.6 s), a face bracket that briefly pops around the
/// detected face (selfie only), a soft haptic, and a short-lived pill
/// ("✨ Selfie · Soft Glow" + "low light") that auto-dismisses after ~2 s while the
/// look chip stays. Pure timing/geometry lives here so it is unit-tested; the views
/// below only read it. Never hit-testable; Reduce Motion → fades only (no sweep, no pop).
struct AppliedFeedbackState: Equatable {
    enum Kind: Equatable {
        /// Selfie-aware AO applied a selfie look (full moment: glow + bracket + pill).
        case selfie(lookId: String, reason: SelfieAutoReason)
        /// Any other AO apply — edge glow only (the dial burst stays the status).
        case optimize
    }

    enum Haptic: Equatable { case none, soft }

    let kind: Kind
    let startedAt: Date
    /// UI-space (top-left origin, 0…1) face box; nil = no bracket.
    let faceBox: CGRect?
    let reduceMotion: Bool

    // Timing (seconds from `startedAt`).
    static let glowDuration: TimeInterval = 0.6
    static let bracketDelay: TimeInterval = 0.08
    static let bracketDuration: TimeInterval = 0.9
    static let pillDuration: TimeInterval = 2.0
    /// Bracket padding around the face box, as a fraction of the box size.
    static let bracketPadding: CGFloat = 0.14
    static let minBracketSide: CGFloat = 44

    init(kind: Kind, startedAt: Date = Date(), faceBox: CGRect? = nil, reduceMotion: Bool = false) {
        self.kind = kind
        self.startedAt = startedAt
        self.faceBox = faceBox
        self.reduceMotion = reduceMotion
    }

    var isSelfie: Bool {
        if case .selfie = kind { return true }
        return false
    }

    var pillTitle: String? {
        guard case .selfie(let id, _) = kind else { return nil }
        return "✨ Selfie · \(CreativeLookCatalog.displayName(for: id))"
    }

    var pillDetail: String? {
        guard case .selfie(_, let reason) = kind else { return nil }
        return reason.copy
    }

    var accessibilityAnnouncement: String? {
        guard let pillTitle else { return nil }
        let title = pillTitle.replacingOccurrences(of: "✨ ", with: "")
        return pillDetail.map { "\(title), \($0)" } ?? title
    }

    var haptic: Haptic { isSelfie ? .soft : .none }

    var showsBracket: Bool { isSelfie && faceBox != nil }

    /// Whole moment length — the state is dropped after this.
    var totalDuration: TimeInterval {
        isSelfie ? max(Self.pillDuration, Self.bracketDelay + Self.bracketDuration) : Self.glowDuration
    }

    func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    func showsPill(at now: Date) -> Bool { pillTitle != nil && elapsed(at: now) < Self.pillDuration }

    func isFinished(at now: Date) -> Bool { elapsed(at: now) >= totalDuration }

    /// Edge glow opacity 0…1: quick rise (first 25 %), ease out to 0 at `glowDuration`.
    func glowOpacity(at now: Date) -> Double {
        let p = elapsed(at: now) / Self.glowDuration
        guard p < 1 else { return 0 }
        if p < 0.25 { return p / 0.25 }
        let out = (p - 0.25) / 0.75
        return max(0, 1 - out * out)
    }

    /// Sweep angle in degrees for the moving highlight; nil with Reduce Motion (fade only).
    func sweepDegrees(at now: Date) -> Double? {
        guard !reduceMotion else { return nil }
        let p = min(1, elapsed(at: now) / Self.glowDuration)
        // Ease-out: starts at the top (−90°) and travels one full lap.
        let eased = 1 - pow(1 - p, 2)
        return -90 + eased * 360
    }

    /// Bracket opacity 0…1 over `bracketDuration` (after `bracketDelay`).
    func bracketOpacity(at now: Date) -> Double {
        guard showsBracket else { return 0 }
        let t = elapsed(at: now) - Self.bracketDelay
        guard t >= 0, t < Self.bracketDuration else { return 0 }
        let p = t / Self.bracketDuration
        if p < 0.2 { return p / 0.2 }
        if p > 0.7 { return max(0, 1 - (p - 0.7) / 0.3) }
        return 1
    }

    /// Bracket scale: pops 1.12 → 1.0 in the first ~0.22 s; constant 1 with Reduce Motion.
    func bracketScale(at now: Date) -> Double {
        guard !reduceMotion else { return 1 }
        let t = elapsed(at: now) - Self.bracketDelay
        guard t > 0 else { return 1.12 }
        let p = min(1, t / 0.22)
        return 1.12 - 0.12 * (1 - pow(1 - p, 3))
    }

    /// Screen rect for the face bracket, or nil when it must not draw: drawer open
    /// (the bracket never sits under the drawer), no face, or too little room after
    /// keeping clear of the drawer handle (left), the look rail (right, per
    /// `SideChromeLayout`) and the top / bottom chrome.
    static func bracketRect(
        faceBox: CGRect?,
        in size: CGSize,
        topInset: CGFloat,
        bottomInset: CGFloat,
        drawerOpen: Bool
    ) -> CGRect? {
        guard !drawerOpen, let box = faceBox,
              box.width > 0, box.height > 0,
              box.minX.isFinite, box.minY.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        var r = CGRect(x: box.minX * size.width, y: box.minY * size.height,
                       width: box.width * size.width, height: box.height * size.height)
        r = r.insetBy(dx: -r.width * bracketPadding, dy: -r.height * bracketPadding)
        let minX = SideChromeLayout.handleGap + SideChromeLayout.handleSize + 4
        let maxX = SideChromeLayout.railLeadingEdge(screenWidth: size.width) - 4
        let minY = topInset
        let maxY = size.height - bottomInset
        let clamped = CGRect(
            x: max(r.minX, minX), y: max(r.minY, minY),
            width: min(r.maxX, maxX) - max(r.minX, minX),
            height: min(r.maxY, maxY) - max(r.minY, minY))
        guard clamped.width >= minBracketSide, clamped.height >= minBracketSide else { return nil }
        return clamped
    }
}

// MARK: - Views

/// Edge glow + face bracket. Purely decorative: never hit-testable, hidden from VoiceOver
/// (the pill carries the announcement).
struct AppliedFeedbackOverlay: View {
    let state: AppliedFeedbackState
    let bracketRect: CGRect?

    static let warm = Color(red: 1.0, green: 0.80, blue: 0.52)
    static let warmDeep = Color(red: 0.98, green: 0.62, blue: 0.30)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { ctx in
            let now = ctx.date
            ZStack {
                edgeGlow(now: now)
                if let rect = bracketRect {
                    FaceBracketShape()
                        .stroke(Self.warm, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: Self.warmDeep.opacity(0.6), radius: 6)
                        .frame(width: rect.width, height: rect.height)
                        .scaleEffect(state.bracketScale(at: now))
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(state.bracketOpacity(at: now))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func edgeGlow(now: Date) -> some View {
        let opacity = state.glowOpacity(at: now)
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        ZStack {
            // Soft warm wash hugging the edges.
            shape
                .stroke(Self.warm.opacity(0.55), lineWidth: 10)
                .blur(radius: 10)
            if let deg = state.sweepDegrees(at: now) {
                // Shimmer: a bright arc travelling once around the frame.
                shape
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Self.warm, location: 0.06),
                                .init(color: .white.opacity(0.9), location: 0.1),
                                .init(color: Self.warmDeep.opacity(0.8), location: 0.16),
                                .init(color: .clear, location: 0.26),
                                .init(color: .clear, location: 1),
                            ]),
                            center: .center,
                            angle: .degrees(deg)
                        ),
                        lineWidth: 5
                    )
                    .blur(radius: 3)
            }
        }
        .opacity(opacity)
    }
}

/// Four rounded corner ticks (camera-style face bracket).
struct FaceBracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.22
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

/// The short-lived status pill. Takes the AgentStatusPill's slot (one primary status).
struct AppliedFeedbackPill: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTheme.bodySmMedium())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppTheme.agentStatusBg)
                .overlay(
                    Capsule().stroke(
                        LinearGradient(
                            colors: [AppliedFeedbackOverlay.warm.opacity(0.9), AppliedFeedbackOverlay.warmDeep.opacity(0.5)],
                            startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1)
                )
                .shadow(color: AppliedFeedbackOverlay.warmDeep.opacity(0.35), radius: 8)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

enum AppliedFeedbackHaptics {
    @MainActor
    static func play(_ haptic: AppliedFeedbackState.Haptic) {
        switch haptic {
        case .none: break
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        }
    }
}
