import SwiftUI

/// Compact post-optimization confirmation (Workstream B, capture-ready UI).
///
/// Copy rule: say "Settings applied" — never claim the image was "improved",
/// which the app has not independently verified. The banner is non-modal,
/// never blocks the shutter, and is announced to VoiceOver as a status.
struct CaptureReadyBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
            Text("Settings applied — ready for your photo.")
                .font(AppTheme.caption())
        }
        .foregroundStyle(AppTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppTheme.agentStatusBg)
                .overlay(Capsule().stroke(AppTheme.border.opacity(0.7), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Settings applied. Ready for your photo.")
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Dismissible first-photo guidance card (Workstream A, treatment arm).
/// The shutter stays visible and enabled behind this card; both actions are
/// one tap and neither is a paywall.
struct FirstPhotoGuidanceCard: View {
    var onTry: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try Auto Optimize")
                .font(AppTheme.bodySmMedium())
                .foregroundStyle(AppTheme.ink)
            Text("Let the camera read the light and set up this shot before you take it. You can still shoot right away — nothing is locked in.")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.inkSecondary)
            HStack(spacing: 10) {
                Button(action: onTry) {
                    Text("Optimize this shot")
                        .font(AppTheme.caption())
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.accent))
                        .foregroundStyle(AppTheme.accentOnAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Optimize this shot with Auto Optimize")

                Button(action: onSkip) {
                    Text("Skip")
                        .font(AppTheme.caption())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                        .foregroundStyle(AppTheme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip Auto Optimize guidance")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}
