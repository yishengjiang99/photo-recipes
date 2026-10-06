import SwiftUI
import UIKit

/// Persistent post-optimize controls: press-and-hold before/after + Undo.
/// Optimized result is shown by default; holding reveals the unstyled original preview.
struct OptimizeResultRow: View {
    var canCompare: Bool
    @Binding var comparing: Bool
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if canCompare {
                Text(comparing ? "Before" : "Hold to compare")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(comparing ? AppTheme.accentMuted : AppTheme.agentStatusBg)
                            .overlay(Capsule().stroke(AppTheme.border.opacity(0.7), lineWidth: 1))
                    )
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !comparing else { return }
                                comparing = true
                                UISelectionFeedbackGenerator().selectionChanged()
                                Analytics.shared.track("optimize_compare", props: ["source": "hold"])
                            }
                            .onEnded { _ in comparing = false }
                    )
                    .accessibilityLabel("Hold to compare with the original")
                    .accessibilityAddTraits(.isButton)
            }

            Button(action: onUndo) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2.weight(.semibold))
                    Text("Undo")
                }
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.agentStatusBg)
                        .overlay(Capsule().stroke(AppTheme.border.opacity(0.7), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo Auto Optimize")
        }
    }
}

/// First-capture auto-run eligibility (funnel proposal: guided first win, once per install).
@MainActor
enum FirstWinAutoRun {
    static let attemptedKey = "autoOptimize.firstCaptureAutoRunAttempted"
    /// Reserved for a future Settings opt-out.
    static let optOutKey = "autoOptimize.autoRunOptOut"

    static var isEligible: Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: PushNotificationManager.hasCompletedFirstAutoOptimizeKey) { return false }
        if d.bool(forKey: attemptedKey) { return false }
        if d.bool(forKey: AutoOptimizeController.userUndidKey) { return false }
        if d.bool(forKey: optOutKey) { return false }
        return true
    }

    static func markAttempted() {
        UserDefaults.standard.set(true, forKey: attemptedKey)
    }
}
