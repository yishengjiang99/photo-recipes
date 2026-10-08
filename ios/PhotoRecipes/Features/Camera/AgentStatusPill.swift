import SwiftUI

struct AgentStatusPill: View {
    let phase: AutoOptimizeController.Phase
    let verifyWarning: String?
    /// When set, shown instead of phase.statusCopy / verifyWarning pairing.
    var statusOverride: String? = nil
    /// True while Recommend (or Ask) SSE is in flight — pulse even if AO phase is idle.
    var isBusy: Bool = false
    var onStop: (() -> Void)? = nil
    /// When set, tapping the pill opens the detail (exposure/teach). EV numbers
    /// stay in the detail, never on the finder.
    var onTapDetail: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var effectiveRunning: Bool { isBusy || phase.isRunning }

    var body: some View {
        let copy = {
            if let statusOverride, !statusOverride.isEmpty { return statusOverride }
            return verifyWarning ?? phase.statusCopy
        }()
        if !copy.isEmpty {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .opacity(effectiveRunning && !reduceMotion ? (pulse ? 0.4 : 1) : 1)
                Text(copy)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                if effectiveRunning, let onStop {
                    Button("Stop", action: onStop)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkSecondary)
                }
                if onTapDetail != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(AppTheme.agentStatusBg))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(copy)
            .accessibilityHint(onTapDetail != nil ? "Opens details" : "")
            .onTapGesture {
                onTapDetail?()
            }
            .onAppear { startPulseIfNeeded() }
            .onChange(of: effectiveRunning) { _, _ in startPulseIfNeeded() }
        }
    }

    private var dotColor: Color {
        if isBusy { return AppTheme.agentRunning }
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
        guard effectiveRunning, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
    }
}
