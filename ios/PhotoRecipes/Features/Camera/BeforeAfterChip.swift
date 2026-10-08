import SwiftUI

struct BeforeAfterChip: View {
    let diffs: [AutoOptimizeController.DiffLine]
    let recipeTitle: String?
    var hasMoreAdvanced: Bool = false
    var onTap: () -> Void
    var onMore: (() -> Void)? = nil
    /// Phase 3 outcome telemetry: fired on expand/collapse with the new state.
    var onToggle: ((Bool) -> Void)? = nil

    @State private var expanded = false

    var body: some View {
        if !diffs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                    onToggle?(expanded)
                } label: {
                    HStack(spacing: 8) {
                        if let recipeTitle {
                            Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                            Text(recipeTitle)
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkSecondary)
                                .lineLimit(1)
                        }
                        if expanded {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(diffs.prefix(5)) { d in
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
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("\(diffs.count) settings updated")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.ink)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.inkTertiary)
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

                if expanded {
                    HStack(spacing: 12) {
                        Button("Tweak") { onTap() }
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.accent)
                        if hasMoreAdvanced, let onMore {
                            Button("More changes") { onMore() }
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkSecondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .accessibilityLabel("\(diffs.count) settings updated. Tap to expand.")
        }
    }
}
