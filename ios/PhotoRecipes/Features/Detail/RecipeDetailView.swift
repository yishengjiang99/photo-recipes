import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    let recipe: Recipe
    @State private var selectedVariant: SubVariant?
    @State private var reasonBanner: String?

    private var activeDials: DialSettings {
        selectedVariant?.dials ?? recipe.dials
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let reason = reasonBanner {
                        reasonCard(reason)
                    }
                    dialsSection
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
                    whenToUse
                }
                .padding()
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    entitlements.toggleFavorite(recipe.id)
                } label: {
                    Image(systemName: entitlements.isFavorite(recipe.id) ? "heart.fill" : "heart")
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Page \(recipe.page)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(recipe.blurb)
                .foregroundStyle(AppTheme.textSecondary)
            HStack {
                ForEach(recipe.tags) { tag in
                    Text(tag.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentSecondary.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func reasonCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why this recipe", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera dials")
                .font(.title3.weight(.semibold))
            CameraDialsView(dials: activeDials)
        }
    }

    private func variantsSection(_ variants: [SubVariant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Variants")
                .font(.title3.weight(.semibold))
            ForEach(variants) { v in
                Button {
                    selectedVariant = selectedVariant?.id == v.id ? nil : v
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.label).font(.headline)
                            Text(v.description)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: selectedVariant?.id == v.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding()
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 56)
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(.title3.weight(.semibold))
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28)
                    Text(step)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tips")
                .font(.title3.weight(.semibold))
            let tips = selectedVariant?.tips ?? recipe.tips
            ForEach(tips, id: \.self) { tip in
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gear checklist")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !entitlements.isPro {
                    Button("Pro") { entitlements.showPaywall = true }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.proBadge)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
            }
            Text("Steps stay readable for everyone. Interactive checkmarks are Pro.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            let state = entitlements.checklistState(recipeId: recipe.id)
            ForEach(recipe.equipmentChecklist, id: \.self) { item in
                Button {
                    if entitlements.isPro {
                        entitlements.setChecklistItem(
                            recipeId: recipe.id,
                            item: item,
                            checked: !(state[item] ?? false)
                        )
                    } else {
                        entitlements.showPaywall = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: (state[item] ?? false) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(entitlements.isPro ? AppTheme.accent : AppTheme.textSecondary)
                            .font(.title3)
                        Text(item)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if !entitlements.isPro {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func noteCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(AppTheme.accentSecondary)
            Text(text).foregroundStyle(AppTheme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var whenToUse: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When to use").font(.title3.weight(.semibold))
            Text(recipe.whenToUse).foregroundStyle(AppTheme.textSecondary)
        }
    }
}

struct CameraDialsView: View {
    let dials: DialSettings

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            dialCell("Mode", dials.mode.label)
            if let a = dials.aperture { dialCell("Aperture", a) }
            if let s = dials.shutter { dialCell("Shutter", s) }
            if let i = dials.iso { dialCell("ISO", i) }
            if let e = dials.evBracket { dialCell("EV bracket", e) }
        }
        if let notes = dials.notes {
            Text(notes)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 4)
        }
    }

    private func dialCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1.5)
                )
        )
    }
}
