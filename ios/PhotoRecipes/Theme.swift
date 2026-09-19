import SwiftUI

/// Design handoff v1 — “Darkroom field notes” tokens (same hexes as docs/design-handoff-v1.md §4).
enum AppTheme {
    // MARK: - Surfaces
    static let bg = Color(hex: 0x0C0C0F)
    static let bgElevated = Color(hex: 0x121216)
    static let surface = Color(hex: 0x16161C)
    static let surface2 = Color(hex: 0x1E1E26)
    static let border = Color(hex: 0x2A2A33)
    static let borderStrong = Color(hex: 0x3F3F4A)

    // MARK: - Ink
    static let ink = Color(hex: 0xF5F5F7)
    static let inkSecondary = Color(hex: 0xC4C4CC)
    static let inkTertiary = Color(hex: 0x8B8B96)
    /// Captions ≥ #a8a8b3 per contrast rule
    static let inkCaption = Color(hex: 0xA8A8B3)

    // MARK: - Accent (single loud rose CTA)
    static let accent = Color(hex: 0xF43F5E)
    static let accentSoft = Color(hex: 0xFB7185)
    static let accentMuted = Color(hex: 0xF43F5E).opacity(0.14)

    // MARK: - Semantic
    static let vision = Color(hex: 0x8B7CF6)
    static let tip = Color(hex: 0xE7B549)
    static let tipBg = Color(hex: 0xE7B549).opacity(0.08)
    static let success = Color(hex: 0x34D399)
    static let danger = Color(hex: 0xF87171)
    static let overlay = Color.black.opacity(0.72)

    // MARK: - Camera chrome (design-handoff-camera-v1)
    static let cameraScrim = Color.black.opacity(0.45)
    static let cameraScrimStrong = Color.black.opacity(0.72)
    static let shutterRing = Color(hex: 0xF5F5F7)
    static let shutterCore = accent
    static let recipeBadgeBg = Color(hex: 0xF43F5E).opacity(0.18)
    static let aeLock = tip

    // MARK: - Agentic Auto Optimize (design-handoff-agentic-v1)
    static let agentStatusBg = Color.black.opacity(0.55)
    static let agentRunning = Color(hex: 0xFB7185)
    static let agentReady = Color(hex: 0x34D399)
    static let agentWarn = Color(hex: 0xE7B549)
    static let diffBefore = Color(hex: 0x8B8B96)
    static let diffAfter = Color(hex: 0xF5F5F7)

    // MARK: - Category tints (~18% fill)
    static let categoryDoF = Color(hex: 0x5B8DEF)
    static let categoryMotion = Color(hex: 0xF59E0B)
    static let categoryHDR = Color(hex: 0xA78BFA)
    static let categoryComposition = Color(hex: 0x2DD4BF)

    // MARK: - Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusPill: CGFloat = 999

    // MARK: - Space scale
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48
    static let space8: CGFloat = 64
    static let touchMin: CGFloat = 44
    static let chipHeight: CGFloat = 36

    // MARK: - Legacy aliases (existing call sites)
    static let background = bg
    static let card = surface
    static let cardBorder = border
    static let textPrimary = ink
    static let textSecondary = inkSecondary
    static let accentSecondary = vision
    static let proBadge = tip
    static let freeBadge = borderStrong

    // MARK: - Typography roles (New York / Georgia serif + SF UI)
    static func displayXL() -> Font {
        .system(size: 36, weight: .regular, design: .serif)
    }

    static func displayLG() -> Font {
        .system(size: 28, weight: .regular, design: .serif)
    }

    static func displayTitle() -> Font {
        .system(size: 22, weight: .regular, design: .serif)
    }

    static func title() -> Font {
        .system(size: 20, weight: .semibold, design: .default)
    }

    static func body() -> Font {
        .system(size: 16, weight: .regular, design: .default)
    }

    static func bodyMedium() -> Font {
        .system(size: 16, weight: .medium, design: .default)
    }

    static func bodySm() -> Font {
        .system(size: 14, weight: .regular, design: .default)
    }

    static func bodySmMedium() -> Font {
        .system(size: 14, weight: .medium, design: .default)
    }

    static func caption() -> Font {
        .system(size: 12, weight: .medium, design: .default)
    }

    static func overline() -> Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    static func monoBody() -> Font {
        .system(size: 16, weight: .semibold, design: .monospaced)
    }

    static func monoSm() -> Font {
        .system(size: 14, weight: .semibold, design: .monospaced)
    }

    static func categoryTint(for tag: TechniqueTag) -> Color {
        switch tag {
        case .depthOfField: return categoryDoF
        case .motion: return categoryMotion
        case .hdr: return categoryHDR
        case .composition: return categoryComposition
        }
    }

    static func categoryTint(for tags: [TechniqueTag]) -> Color {
        guard let first = tags.first else { return accent }
        return categoryTint(for: first)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct EntitlementBadge: View {
    let isPro: Bool
    var quiet: Bool = true

    var body: some View {
        Text(isPro ? "Pro" : "Free Peek")
            .font(AppTheme.caption())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isPro ? Color.black : AppTheme.inkSecondary)
            .background(
                Capsule().fill(isPro ? AppTheme.success : Color.clear)
            )
            .overlay(
                Capsule().stroke(isPro ? Color.clear : AppTheme.borderStrong, lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled: Bool = true
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.bodyMedium())
            .foregroundStyle(filled ? Color.white : AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: AppTheme.touchMin)
            .padding(.horizontal, AppTheme.space4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .fill(filled ? AppTheme.accent.opacity(disabled ? 0.45 : (configuration.isPressed ? 0.85 : 1)) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .stroke(filled ? Color.clear : AppTheme.borderStrong, lineWidth: 1.5)
            )
            .opacity(disabled ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.bodySmMedium())
                .padding(.horizontal, 14)
                .frame(height: AppTheme.chipHeight)
                .foregroundStyle(selected ? Color.white : AppTheme.inkSecondary)
                .background(
                    Capsule().fill(selected ? AppTheme.accent : Color.clear)
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.touchMin)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GearTextChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AppTheme.caption())
            .foregroundStyle(AppTheme.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}
