import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let cardBorder = Color.white.opacity(0.08)
    static let accent = Color(red: 0.95, green: 0.55, blue: 0.20)
    static let accentSecondary = Color(red: 0.35, green: 0.65, blue: 0.95)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let proBadge = Color(red: 0.85, green: 0.65, blue: 0.20)
    static let freeBadge = Color.white.opacity(0.25)
}

struct EntitlementBadge: View {
    let isPro: Bool
    var body: some View {
        Text(isPro ? "Pro" : "Free Peek")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isPro ? AppTheme.proBadge : AppTheme.freeBadge)
            .foregroundStyle(isPro ? .black : .white)
            .clipShape(Capsule())
    }
}
