import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @State private var selectedTag: TechniqueTag?
    @State private var showFavoritesOnly = false

    private var filtered: [Recipe] {
        BundledPresets.all.filter { recipe in
            if showFavoritesOnly && !entitlements.isFavorite(recipe.id) { return false }
            if let tag = selectedTag, !recipe.tags.contains(tag) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.space5) {
                        headerRow
                        titleBlock
                        FieldCoachPanel(compact: true)
                        filterRow
                        LazyVStack(spacing: AppTheme.space4) {
                            ForEach(filtered) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCard(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Educational dials · not a camera controller. Shoot safely.")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, AppTheme.space2)
                            .padding(.bottom, AppTheme.space6)
                    }
                    .padding(.horizontal, AppTheme.space4)
                    .padding(.top, AppTheme.space3)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: AppTheme.space3) {
            HStack(spacing: AppTheme.space2) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Camera - Auto Recipes")
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                    Text("Field presets · 30 Recipes book")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
            Spacer()
            EntitlementBadge(isPro: entitlements.isPro)
            if !entitlements.isPro {
                Button {
                    entitlements.showPaywall = true
                } label: {
                    Text("Upgrade")
                        .font(AppTheme.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accentOnAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
                .frame(minHeight: AppTheme.touchMin)
            }
            Button {
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                    .foregroundStyle(showFavoritesOnly ? AppTheme.accent : AppTheme.inkSecondary)
                    .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showFavoritesOnly ? "Show all" : "Favorites only")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.space2) {
            Text("Recipe library")
                .font(AppTheme.displayLG())
                .foregroundStyle(AppTheme.ink)
            Text("Shoot checklists + dials. Ask when you’re stuck.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.space2) {
                FilterChip(title: "All", selected: selectedTag == nil && !showFavoritesOnly) {
                    selectedTag = nil
                }
                ForEach(BundledPresets.allTags) { tag in
                    FilterChip(title: tag.label, selected: selectedTag == tag) {
                        selectedTag = tag
                        showFavoritesOnly = false
                    }
                }
                FilterChip(title: "Favorites", selected: showFavoritesOnly) {
                    showFavoritesOnly = true
                    selectedTag = nil
                }
            }
        }
    }
}

struct RecipeCard: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    let recipe: Recipe

    private var primaryTag: TechniqueTag? { recipe.tags.first }
    private var railColor: Color {
        if let t = primaryTag { return AppTheme.categoryTint(for: t) }
        return AppTheme.accent
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(railColor.opacity(0.85))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: AppTheme.space3) {
                HStack(alignment: .center, spacing: AppTheme.space2) {
                    if let tag = primaryTag {
                        Text(tag.label.uppercased())
                            .font(AppTheme.overline())
                            .tracking(0.8)
                            .foregroundStyle(railColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(railColor.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    Text("p.\(recipe.page)")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                    Spacer()
                    Button {
                        entitlements.toggleFavorite(recipe.id)
                    } label: {
                        Image(systemName: entitlements.isFavorite(recipe.id) ? "heart.fill" : "heart")
                            .foregroundStyle(entitlements.isFavorite(recipe.id) ? AppTheme.accent : AppTheme.inkSecondary)
                            .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                    }
                    .buttonStyle(.plain)
                }

                Text(recipe.title)
                    .font(AppTheme.displayTitle())
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recipe.blurb)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(alignment: .firstTextBaseline, spacing: AppTheme.space3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KEY SETTING")
                            .font(AppTheme.overline())
                            .tracking(0.8)
                            .foregroundStyle(AppTheme.inkTertiary)
                        Text(recipe.keySetting)
                            .font(AppTheme.monoBody())
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    FlowGearChips(gear: recipe.gear)
                }
            }
            .padding(AppTheme.space4)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

/// Simple wrapping gear chips without a custom Layout (iOS 17-safe HStack wrap via wrapping view).
struct FlowGearChips: View {
    let gear: [GearItem]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(chunked(Array(gear.prefix(4)), size: 2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { g in
                        GearTextChip(label: shortLabel(g))
                    }
                }
            }
        }
    }

    private func shortLabel(_ g: GearItem) -> String {
        switch g {
        case .wideAngle: return "Wide"
        case .remote: return "Remote"
        default: return g.label
        }
    }

    private func chunked<T>(_ arr: [T], size: Int) -> [[T]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
        }
    }
}
