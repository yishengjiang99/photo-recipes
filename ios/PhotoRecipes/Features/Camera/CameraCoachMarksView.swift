import SwiftUI

/// First-run coach marks ≤3 (AO → chips → ···). Replay via Settings → Show camera tips.
struct CameraCoachMarksView: View {
    @Binding var step: Int
    var onFinished: () -> Void

    private let copy: [(title: String, body: String)] = [
        (
            "Auto Optimize",
            "Point at the shot. We set shutter, ISO, EV, WB, and focus."
        ),
        (
            "Before → after",
            "See exactly what changed. Tap to tweak."
        ),
        (
            "Controls",
            "Light, lens, capture tools, and Looks live here — so the finder stays clear."
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture { advance() }

            VStack(spacing: AppTheme.space4) {
                Spacer()
                VStack(alignment: .leading, spacing: AppTheme.space3) {
                    Text("Field tip \(step + 1) of \(copy.count)")
                        .font(AppTheme.overline())
                        .foregroundStyle(AppTheme.inkTertiary)
                    Text(copy[step].title)
                        .font(AppTheme.displayTitle())
                        .foregroundStyle(AppTheme.ink)
                    Text(copy[step].body)
                        .font(AppTheme.body())
                        .foregroundStyle(AppTheme.inkSecondary)
                    HStack {
                        Button("Skip") { finish() }
                            .font(AppTheme.bodySm())
                            .foregroundStyle(AppTheme.inkSecondary)
                        Spacer()
                        Button(step == copy.count - 1 ? "Got it" : "Next") { advance() }
                            .font(AppTheme.bodySmMedium())
                            .foregroundStyle(AppTheme.accentOnAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(AppTheme.accent))
                    }
                }
                .padding(AppTheme.space4)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusLg)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )
                .padding(.horizontal, AppTheme.space4)
                .padding(.bottom, 120)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func advance() {
        if step < copy.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() { onFinished() }
}

enum CameraCoachMarksStore {
    static let seenKey = "camera.coachMarks.seen"
    static let replayKey = "camera.coachMarks.replay"

    static var shouldShow: Bool {
        if UserDefaults.standard.bool(forKey: replayKey) { return true }
        if UserDefaults.standard.bool(forKey: seenKey) { return false }
        // Optional heuristic: skip if already optimized once.
        if UserDefaults.standard.bool(forKey: PushNotificationManager.hasCompletedFirstAutoOptimizeKey) {
            return false
        }
        return true
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
        UserDefaults.standard.set(false, forKey: replayKey)
    }

    static func requestReplay() {
        UserDefaults.standard.set(true, forKey: replayKey)
    }
}
