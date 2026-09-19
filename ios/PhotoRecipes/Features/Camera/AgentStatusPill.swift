import SwiftUI

struct AgentStatusPill: View {
    let phase: AutoOptimizeController.Phase
    let verifyWarning: String?
    var onStop: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let copy = verifyWarning ?? phase.statusCopy
        if !copy.isEmpty {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .opacity(phase.isRunning && !reduceMotion ? (pulse ? 0.4 : 1) : 1)
                Text(copy)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                if phase.isRunning, let onStop {
                    Button("Stop", action: onStop)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(AppTheme.agentStatusBg))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(copy)
            .onAppear { startPulseIfNeeded() }
            .onChange(of: phase.isRunning) { _, _ in startPulseIfNeeded() }
        }
    }

    private var dotColor: Color {
        switch phase {
        case .ready: return AppTheme.agentReady
        case .error: return AppTheme.danger
        case .verifying where verifyWarning != nil: return AppTheme.agentWarn
        case .sensing, .reasoning, .applying, .verifying: return AppTheme.agentRunning
        case .idle: return AppTheme.inkTertiary
        }
    }

    private func startPulseIfNeeded() {
        pulse = false
        guard phase.isRunning, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
    }
}
