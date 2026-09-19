import SwiftUI

/// Look chip states from design-handoff-capabilities-comms-v1 §3.
/// Suggested = Apply / Dismiss (never silent look apply). Active = clear × · tap → Looks tab.
struct LookChip: View {
    enum Mode: Equatable {
        case suggested(CreativeLook)
        case active(CreativeLook)
    }

    let mode: Mode
    var onApply: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var onOpenLooks: (() -> Void)? = nil

    var body: some View {
        switch mode {
        case .suggested(let look):
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.tip)
                Text("Look · \(look.displayName) · \(Self.intensityLabel(look.resolvedIntensity))")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Button("Apply") { onApply?() }
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.accent)
                Button("Dismiss") { onDismiss?() }
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(chipBackground(stroke: AppTheme.tip.opacity(0.55)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Suggested look \(look.displayName)")

        case .active(let look):
            Button { onOpenLooks?() } label: {
                HStack(spacing: 8) {
                    Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                    Text("\(look.displayName) · \(Self.intensityLabel(look.resolvedIntensity))")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Button {
                        onClear?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.inkSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear look")
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(chipBackground(stroke: AppTheme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Active look \(look.displayName). Opens Looks.")
        }
    }

    private func chipBackground(stroke: Color) -> some View {
        Capsule()
            .fill(AppTheme.agentStatusBg)
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }

    static func intensityLabel(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
