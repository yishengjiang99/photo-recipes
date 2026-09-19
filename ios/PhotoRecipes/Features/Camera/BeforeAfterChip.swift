import SwiftUI

struct BeforeAfterChip: View {
    let diffs: [AutoOptimizeController.DiffLine]
    let recipeTitle: String?
    var onTap: () -> Void

    var body: some View {
        if !diffs.isEmpty {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    if let recipeTitle {
                        Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                        Text(recipeTitle)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    ForEach(diffs.prefix(3)) { d in
                        HStack(spacing: 4) {
                            Text(d.label)
                                .font(AppTheme.overline())
                                .foregroundStyle(AppTheme.inkTertiary)
                            Text(d.before)
                                .font(AppTheme.monoSm())
                                .foregroundStyle(AppTheme.diffBefore)
                                .strikethrough()
                            Text("→")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkTertiary)
                            Text(d.after)
                                .font(AppTheme.monoSm())
                                .foregroundStyle(AppTheme.diffAfter)
                            if d.clamped {
                                Text("clamped")
                                    .font(AppTheme.overline())
                                    .foregroundStyle(AppTheme.tip)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.agentStatusBg)
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
