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
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        tagFilter
                        LazyVStack(spacing: 14) {
                            ForEach(filtered) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCard(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Photo Recipes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EntitlementBadge(isPro: entitlements.isPro)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFavoritesOnly.toggle()
                    } label: {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(showFavoritesOnly ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(showFavoritesOnly ? "Show all" : "Favorites only")
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagChip(title: "All", selected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(BundledPresets.allTags) { tag in
                    TagChip(title: tag.label, selected: selectedTag == tag) {
                        selectedTag = tag
                    }
                }
            }
        }
    }
}

struct TagChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selected ? AppTheme.accent : AppTheme.card)
                .foregroundStyle(selected ? .black : AppTheme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

struct RecipeCard: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("p.\(recipe.page)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Button {
                    entitlements.toggleFavorite(recipe.id)
                } label: {
                    Image(systemName: entitlements.isFavorite(recipe.id) ? "heart.fill" : "heart")
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Text(recipe.blurb)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)
            HStack {
                ForEach(recipe.tags) { tag in
                    Text(tag.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentSecondary.opacity(0.25))
                        .clipShape(Capsule())
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(recipe.gear.prefix(4)) { g in
                        Image(systemName: g.systemImage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            Text(recipe.dials.mode.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}
