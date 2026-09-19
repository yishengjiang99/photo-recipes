import SwiftUI
import PhotosUI

/// Field Coach tab — unified Ask (Describe scene | From photo). Quiet surface, no dual neon glow.
struct AskGrokView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                ScrollView {
                    FieldCoachPanel(compact: false)
                        .padding(AppTheme.space4)
                }
            }
            .navigationTitle("Field Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EntitlementBadge(isPro: entitlements.isPro)
                }
            }
        }
    }
}

enum FieldCoachMode: String, CaseIterable, Identifiable {
    case describe
    case photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .describe: return "Describe scene"
        case .photo: return "From photo"
        }
    }
}

struct FieldCoachPanel: View {
    var compact: Bool = false

    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var api: APIClient

    @State private var mode: FieldCoachMode = .describe
    @State private var message = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var result: RecommendResponse?
    @State private var navigateRecipe: Recipe?
    @State private var showPaywallFromQuota = false

    private let suggestions = [
        "Silky waterfall, sharp rocks",
        "Backlit portrait, soft bokeh",
        "City night, handheld",
        "High-contrast landscape HDR"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            header
            segment
            quotaCaption

            if mode == .describe {
                describeBody
            } else {
                photoBody
            }

            if let errorText {
                errorBanner(errorText)
            }

            if let result {
                resultCard(result)
            }
        }
        .padding(AppTheme.space4)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .navigationDestination(item: $navigateRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    selectedImage = ui
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Field Coach")
                    .font(AppTheme.title())
                    .foregroundStyle(AppTheme.ink)
                if !compact {
                    Text("Ask when you’re stuck — text or a quick photo.")
                        .font(AppTheme.bodySm())
                        .foregroundStyle(AppTheme.inkSecondary)
                }
            }
            Spacer()
        }
    }

    private var segment: some View {
        HStack(spacing: 0) {
            ForEach(FieldCoachMode.allCases) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: 6) {
                        if m == .photo {
                            Circle()
                                .fill(AppTheme.vision)
                                .frame(width: 6, height: 6)
                        }
                        Text(m.label)
                            .font(AppTheme.bodySmMedium())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(mode == m ? AppTheme.ink : AppTheme.inkSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                            .fill(mode == m ? AppTheme.surface2 : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private var quotaCaption: some View {
        Group {
            if entitlements.isPro {
                Text("Pro · unlimited Ask")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.success)
            } else if let rem = entitlements.status.asksRemaining {
                Text("Free Peek · \(rem) left today")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            } else {
                Text("Free Peek · daily ask quota")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            }
        }
    }

    private var describeBody: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            FlowSuggestionChips(suggestions: suggestions) { chip in
                message = chip
            }

            TextField("e.g. silky waterfall, keep rocks sharp…", text: $message, axis: .vertical)
                .lineLimit(compact ? 2...4 : 3...5)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.ink)
                .padding(AppTheme.space3)
                .frame(minHeight: compact ? 72 : 88, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .fill(AppTheme.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )

            submitButton(title: isLoading ? "Matching a recipe…" : "Recommend a recipe", enabled: canSubmitDescribe)
        }
    }

    private var photoBody: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: AppTheme.space2) {
                    if let img = selectedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: compact ? 120 : 180)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.inkTertiary)
                        Text("Choose photo")
                            .font(AppTheme.bodySmMedium())
                            .foregroundStyle(AppTheme.inkSecondary)
                        Text("Optional note below — vision matches a field recipe.")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(AppTheme.space4)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(AppTheme.borderStrong)
                )
            }
            .buttonStyle(.plain)

            if selectedImage != nil {
                HStack {
                    Button("Clear photo") {
                        selectedImage = nil
                        pickerItem = nil
                    }
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
                    .frame(minHeight: AppTheme.touchMin)
                    Spacer()
                }
            }

            TextField("Optional scene note…", text: $message, axis: .vertical)
                .lineLimit(1...3)
                .font(AppTheme.bodySm())
                .padding(AppTheme.space3)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                        .fill(AppTheme.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )

            submitButton(
                title: isLoading ? "Matching a recipe…" : "Recommend from photo",
                enabled: selectedImage != nil && !isLoading
            )
        }
    }

    private var canSubmitDescribe: Bool {
        !isLoading && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitButton(title: String, enabled: Bool) -> some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(filled: true, disabled: !enabled))
        .disabled(!enabled)
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space2) {
            Text(text)
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
            if showPaywallFromQuota || text.lowercased().contains("limit") || text.lowercased().contains("upgrade") {
                Button("Upgrade · 7-day trial") {
                    entitlements.showPaywall = true
                }
                .buttonStyle(PrimaryButtonStyle(filled: true))
            }
        }
        .padding(AppTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.surface2)
        )
    }

    @ViewBuilder
    private func resultCard(_ r: RecommendResponse) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack(spacing: 6) {
                if r.vision == true {
                    Circle().fill(AppTheme.vision).frame(width: 6, height: 6)
                }
                Text(r.vision == true ? "From photo" : "Recommendation")
                    .font(AppTheme.overline())
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.inkTertiary)
            }

            let recipe = r.preset ?? BundledPresets.recipe(id: r.presetId ?? "")
            if let recipe {
                Text(recipe.title)
                    .font(AppTheme.displayTitle())
                    .foregroundStyle(AppTheme.ink)
            }

            if let reason = r.reason {
                Text(reason)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
            }

            HStack(spacing: AppTheme.space2) {
                if let recipe {
                    Button {
                        navigateRecipe = recipe
                    } label: {
                        Text("Open recipe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: true))
                }
                Button {
                    result = nil
                    errorText = nil
                } label: {
                    Text("Try another")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private func submit() async {
        errorText = nil
        result = nil
        showPaywallFromQuota = false
        isLoading = true
        defer { isLoading = false }
        let jpeg: Data? = mode == .photo ? selectedImage.flatMap { APIClient.compressForVision($0) } : nil
        do {
            let response = try await api.recommend(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                favorites: Array(entitlements.favoriteIds),
                imageJPEGData: jpeg
            )
            result = response
            await entitlements.refresh()
        } catch let APIError.paywall(payload) {
            errorText = payload.error
            showPaywallFromQuota = true
            entitlements.showPaywall = true
            await entitlements.refresh()
        } catch let APIError.missingKey(msg) {
            errorText = msg
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct FlowSuggestionChips: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chunked(suggestions, size: 2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { chip in
                        Button {
                            onTap(chip)
                        } label: {
                            Text(chip)
                                .font(AppTheme.bodySm())
                                .foregroundStyle(AppTheme.inkSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, 12)
                                .frame(height: AppTheme.chipHeight)
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    Capsule().stroke(AppTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: AppTheme.touchMin)
                    }
                }
            }
        }
    }

    private func chunked(_ arr: [String], size: Int) -> [[String]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
        }
    }
}
