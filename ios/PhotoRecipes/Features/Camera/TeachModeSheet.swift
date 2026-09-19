import SwiftUI

struct TeachModeSheet: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    let recipeTitle: String?
    let oneLiner: String?
    let tips: [String]
    let diffs: [AutoOptimizeController.DiffLine]
    let verifyWarning: String?
    var coachOnly: CoachOnly? = nil
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space4) {
                    Text(recipeTitle ?? "Custom exposure")
                        .font(AppTheme.displayTitle())
                        .foregroundStyle(AppTheme.ink)

                    if let oneLiner, !oneLiner.isEmpty {
                        Text(oneLiner)
                            .font(AppTheme.body())
                            .foregroundStyle(AppTheme.inkSecondary)
                    }

                    if entitlements.isPro {
                        if let coach = coachOnly { coachBlock(coach) }
                        if !tips.isEmpty {
                            Text("Because")
                                .font(AppTheme.overline())
                                .foregroundStyle(AppTheme.inkTertiary)
                            ForEach(tips.prefix(3), id: \.self) { tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(AppTheme.accent)
                                    Text(tip).font(AppTheme.bodySm()).foregroundStyle(AppTheme.inkSecondary)
                                }
                            }
                        }
                        if !diffs.isEmpty {
                            Text("What we set")
                                .font(AppTheme.overline())
                                .foregroundStyle(AppTheme.inkTertiary)
                            ForEach(diffs) { d in
                                HStack {
                                    Text(d.label).font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(d.before).font(AppTheme.monoSm()).foregroundStyle(AppTheme.diffBefore)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(AppTheme.inkTertiary)
                                    Text(d.after).font(AppTheme.monoSm()).foregroundStyle(AppTheme.diffAfter)
                                    if d.clamped {
                                        Text("clamped").font(AppTheme.overline()).foregroundStyle(AppTheme.tip)
                                    }
                                }
                            }
                        }
                        if let verifyWarning {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Watch out")
                                    .font(AppTheme.overline())
                                    .foregroundStyle(AppTheme.tip)
                                Text(verifyWarning)
                                    .font(AppTheme.bodySm())
                                    .foregroundStyle(AppTheme.inkSecondary)
                            }
                            .padding(AppTheme.space3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.tipBg))
                        }
                    } else {
                        Text(oneLiner ?? "The agent matched a field recipe for this light.")
                            .font(AppTheme.bodySm())
                            .foregroundStyle(AppTheme.inkSecondary)
                        Text("Full teach-mode notes are Pro.")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                        Button("Upgrade · 7-day trial") { entitlements.showPaywall = true }
                            .buttonStyle(PrimaryButtonStyle(filled: true))
                    }
                }
                .padding(AppTheme.space4)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone).foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func coachBlock(_ coach: CoachOnly) -> some View {
        let rows: [(String, String)] = [
            coach.aperture.map { ("Aperture", $0) },
            coach.nd.map { ("ND", $0) },
            coach.tripod.map { ("Tripod", $0 ? "Recommended" : "Optional") },
            coach.notes.map { ("Notes", $0) }
        ].compactMap { $0 }
        if !rows.isEmpty {
            Text("Coach only")
                .font(AppTheme.overline())
                .foregroundStyle(AppTheme.inkTertiary)
            Text("Guidance only — not written to the phone camera API.")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.inkCaption)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0).font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
                        .frame(width: 72, alignment: .leading)
                    Text(row.1).font(AppTheme.bodySm()).foregroundStyle(AppTheme.inkSecondary)
                }
            }
        }
    }
}
