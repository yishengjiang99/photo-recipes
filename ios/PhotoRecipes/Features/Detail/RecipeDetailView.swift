import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var router: CameraRouter
    let recipe: Recipe
    @State private var selectedVariant: SubVariant?
    @State private var reasonBanner: String?

    private var activeDials: DialSettings {
        selectedVariant?.dials ?? recipe.dials
    }

    private var primaryTag: TechniqueTag? { recipe.tags.first }

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space5) {
                    hero
                    if let reason = reasonBanner {
                        reasonCard(reason)
                    }
                    whenToUse
                    dialsSection

            Button {
                router.openCamera(staging: recipe, apply: true)
            } label: {
                Label("Apply to Camera", systemImage: "camera.fill")
            }
            .buttonStyle(PrimaryButtonStyle(filled: true))
                    if let variants = recipe.subVariants, !variants.isEmpty {
                        variantsSection(variants)
                    }
                    stepsSection
                    tipsSection
                    checklistSection
                    if let tip = recipe.phoneTip {
                        noteCard(title: "Phone tip", text: tip)
                    }
                    if let tip = recipe.advancedTip {
                        noteCard(title: "Advanced", text: tip)
                    }
                }
                .padding(AppTheme.space4)
                .padding(.bottom, AppTheme.space6)
            }
        }
        .onAppear { Analytics.shared.track("recipe_open", props: ["recipe_id": recipe.id, "source": "ios"]) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    entitlements.toggleFavorite(recipe.id)
                } label: {
                    Image(systemName: entitlements.isFavorite(recipe.id) ? "heart.fill" : "heart")
                        .foregroundStyle(entitlements.isFavorite(recipe.id) ? AppTheme.accent : AppTheme.inkSecondary)
                        .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
                }
                .accessibilityLabel("Favorite")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack(spacing: AppTheme.space2) {
                if let tag = primaryTag {
                    let tint = AppTheme.categoryTint(for: tag)
                    Text(tag.label)
                        .font(AppTheme.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.18))
                        .clipShape(Capsule())
                }
                Text("Book p.\(recipe.page)")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            }

            Text(recipe.title)
                .font(AppTheme.displayXL())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(recipe.blurb)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.inkSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recipe.gear) { g in
                        GearTextChip(label: g.label)
                    }
                }
            }
        }
    }

    private func reasonCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHY THIS RECIPE")
                .font(AppTheme.overline())
                .tracking(0.8)
                .foregroundStyle(AppTheme.inkTertiary)
            Text(text)
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.ink)
        }
        .padding(AppTheme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.accentMuted)
        )
    }

    private var whenToUse: some View {
        VStack(alignment: .leading, spacing: AppTheme.space2) {
            Label("When to use", systemImage: "scope")
                .font(AppTheme.title())
                .foregroundStyle(AppTheme.ink)
            Text(recipe.whenToUse)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.inkSecondary)
        }
    }

    private var dialsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack {
                Text("Recommended dials")
                    .font(AppTheme.title())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("Educational · simulated")
                    .font(AppTheme.overline())
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.inkTertiary)
            }
            CameraDialsView(dials: activeDials)
                .padding(AppTheme.space3)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .fill(AppTheme.surface2)
                )
        }
    }

    private func variantsSection(_ variants: [SubVariant]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            Text("Variants")
                .font(AppTheme.title())
                .foregroundStyle(AppTheme.ink)
            ForEach(variants) { v in
                Button {
                    selectedVariant = selectedVariant?.id == v.id ? nil : v
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.label)
                                .font(AppTheme.bodyMedium())
                                .foregroundStyle(AppTheme.ink)
                            Text(v.description)
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: selectedVariant?.id == v.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedVariant?.id == v.id ? AppTheme.accent : AppTheme.inkTertiary)
                    }
                    .padding(AppTheme.space4)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                            .fill(AppTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                                    .stroke(
                                        selectedVariant?.id == v.id ? AppTheme.borderStrong : AppTheme.border,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 56)
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            Text("Steps")
                .font(AppTheme.title())
                .foregroundStyle(AppTheme.ink)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: AppTheme.space3) {
                    Text("\(idx + 1)")
                        .font(AppTheme.bodySmMedium())
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.accentMuted))
                    Text(step)
                        .font(AppTheme.body())
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var tipsSection: some View {
        let tips = selectedVariant?.tips ?? recipe.tips
        return VStack(alignment: .leading, spacing: AppTheme.space2) {
            Text("TIPS")
                .font(AppTheme.overline())
                .tracking(0.8)
                .foregroundStyle(AppTheme.tip)
            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tip)
                        .padding(.top, 2)
                    Text(tip)
                        .font(AppTheme.bodySm())
                        .foregroundStyle(AppTheme.inkSecondary)
                }
            }
        }
        .padding(AppTheme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.tipBg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.tip.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// SoftGate: first item clear; rest visible with progressive fade (~last 40%); solid Upgrade bar.
    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Field checklist")
                .font(AppTheme.title())
                .foregroundStyle(AppTheme.ink)
                .padding(.bottom, AppTheme.space3)

            let items = recipe.equipmentChecklist
            let state = entitlements.checklistState(recipeId: recipe.id)

            if entitlements.isPro {
                ForEach(items, id: \.self) { item in
                    checklistRow(item: item, checked: state[item] ?? false, locked: false)
                }
            } else {
                softGateChecklist(items: items)
            }
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private func softGateChecklist(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = items.first {
                checklistRow(item: first, checked: false, locked: true, interactive: false)
                    .padding(.bottom, AppTheme.space2)
            }

            if items.count > 1 {
                let rest = Array(items.dropFirst())
                ZStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rest, id: \.self) { item in
                            checklistRow(item: item, checked: false, locked: true, interactive: false)
                        }
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.55),
                                .init(color: .black.opacity(0.35), location: 0.78),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Solid upgrade bar — not muddy full-lock overlay
                    VStack(spacing: AppTheme.space2) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkSecondary)
                            Text("Interactive checks + unlimited Ask")
                                .font(AppTheme.bodySm())
                                .foregroundStyle(AppTheme.inkSecondary)
                            Spacer()
                        }
                        Button {
                            entitlements.showPaywall = true
                        } label: {
                            Text("Upgrade · 7-day trial")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: true))
                    }
                    .padding(AppTheme.space3)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                            .fill(AppTheme.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                    )
                }
            } else {
                Button {
                    entitlements.showPaywall = true
                } label: {
                    Text("Upgrade · 7-day trial")
                }
                .buttonStyle(PrimaryButtonStyle(filled: true))
                .padding(.top, AppTheme.space2)
            }
        }
    }

    private func checklistRow(item: String, checked: Bool, locked: Bool, interactive: Bool = true) -> some View {
        Button {
            guard interactive else {
                if locked { entitlements.showPaywall = true }
                return
            }
            if entitlements.isPro {
                entitlements.setChecklistItem(
                    recipeId: recipe.id,
                    item: item,
                    checked: !checked
                )
            } else {
                entitlements.showPaywall = true
            }
        } label: {
            HStack(spacing: AppTheme.space3) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? AppTheme.accent : AppTheme.inkTertiary)
                    .font(.title3)
                Text(item)
                    .font(AppTheme.body())
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 10)
            .frame(minHeight: AppTheme.touchMin)
        }
        .buttonStyle(.plain)
        .disabled(!interactive && !locked)
    }

    private func noteCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AppTheme.overline())
                .tracking(0.8)
                .foregroundStyle(AppTheme.inkTertiary)
            Text(text)
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .padding(AppTheme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}

struct CameraDialsView: View {
    let dials: DialSettings

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.space3) {
            dialCell("Mode", dials.mode.label, focus: true)
            if let a = dials.aperture { dialCell("Aperture", a, focus: false) }
            if let s = dials.shutter { dialCell("Shutter", s, focus: false) }
            if let i = dials.iso { dialCell("ISO", i, focus: false) }
            if let e = dials.evBracket { dialCell("EV bracket", e, focus: false) }
        }
        if let notes = dials.notes {
            Text(notes)
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
                .padding(.top, AppTheme.space2)
        }
    }

    private func dialCell(_ label: String, _ value: String, focus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(AppTheme.overline())
                .tracking(0.8)
                .foregroundStyle(AppTheme.inkTertiary)
            Text(value)
                .font(AppTheme.monoSm())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.space3)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(focus ? AppTheme.borderStrong : AppTheme.border, lineWidth: focus ? 1.5 : 1)
                )
        )
    }
}
