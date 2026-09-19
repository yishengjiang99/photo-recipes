import SwiftUI

/// Color system v2 — Neutral Graphite + Signal Amber (Palette A, confirmed).
/// Source: docs/design-handoff-color-v2.md — viewfinder scrims stay hue-neutral; amber on CTAs only.
enum AppTheme {
    // MARK: - Surfaces (hue-neutral graphite)
    static let bg = Color(hex: 0x111111)
    static let bgElevated = Color(hex: 0x161616)
    static let surface = Color(hex: 0x1C1C1E)
    static let surface2 = Color(hex: 0x2C2C2E)
    static let border = Color(hex: 0x3A3A3C)
    static let borderStrong = Color(hex: 0x545456)

    // MARK: - Ink
    static let ink = Color(hex: 0xF5F5F7)
    static let inkSecondary = Color(hex: 0xC7C7CC)
    static let inkTertiary = Color(hex: 0x8E8E93)
    /// Captions ≥ readable meta
    static let inkCaption = Color(hex: 0xA8A8B3)

    // MARK: - Accent (Signal Amber — single loud CTA / Auto Optimize)
    static let accent = Color(hex: 0xE0A812)
    static let accentSoft = Color(hex: 0xF5C518)
    static let accentMuted = Color(hex: 0xE0A812).opacity(0.16)
    /// Label on filled amber buttons (not white)
    static let accentOnAccent = Color(hex: 0x121212)

    // MARK: - Semantic
    static let vision = Color(hex: 0x7A91A8)
    static let tip = Color(hex: 0xE0A812)
    static let tipBg = Color(hex: 0xE0A812).opacity(0.10)
    static let success = Color(hex: 0x30D158)
    static let warn = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)
    static let overlay = Color.black.opacity(0.72)

    // MARK: - Camera chrome (neutral scrims — no amber wash on preview)
    static let cameraScrim = Color.black.opacity(0.45)
    static let cameraScrimStrong = Color.black.opacity(0.78)
    static let shutterRing = Color(hex: 0xF5F5F7)
    static let shutterCore = accent
    static let recipeBadgeBg = Color(hex: 0xE0A812).opacity(0.18)
    static let aeLock = tip
    /// Viewfinder pan/point chevrons (quiet chrome)
    static let panCue = ink.opacity(0.7)

    // MARK: - Agentic Auto Optimize (design-handoff-agentic-v1)
    static let agentStatusBg = Color.black.opacity(0.55)
    static let agentRunning = accentSoft
    static let agentReady = success
    static let agentWarn = warn
    static let diffBefore = inkTertiary
    static let diffAfter = ink

    // MARK: - Category tints (~14% fill — library only, not on finder)
    static let categoryDoF = Color(hex: 0x5B8DEF)
    static let categoryMotion = Color(hex: 0xFF9F0A)
    static let categoryHDR = Color(hex: 0x8B8DBF)
    static let categoryComposition = Color(hex: 0x64D2FF)

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
            .foregroundStyle(filled ? AppTheme.accentOnAccent : AppTheme.ink)
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
                .foregroundStyle(selected ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
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
