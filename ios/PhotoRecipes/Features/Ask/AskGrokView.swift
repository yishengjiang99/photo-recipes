import SwiftUI
import PhotosUI

struct AskGrokView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var api: APIClient

    @State private var message = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var result: RecommendResponse?
    @State private var navigateRecipe: Recipe?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        quotaBanner
                        Text("Describe your scene or attach a photo. Grok picks a field recipe.")
                            .foregroundStyle(AppTheme.textSecondary)

                        TextField("e.g. silky waterfall, keep rocks sharp…", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label(
                                    selectedImage == nil ? "Add photo" : "Change photo",
                                    systemImage: "photo.on.rectangle"
                                )
                                .frame(minHeight: 44)
                                .padding(.horizontal, 14)
                                .background(AppTheme.card)
                                .clipShape(Capsule())
                            }
                            if selectedImage != nil {
                                Button("Clear") {
                                    selectedImage = nil
                                    pickerItem = nil
                                }
                                .frame(minHeight: 44)
                            }
                            Spacer()
                        }

                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isLoading { ProgressView().tint(.black) }
                                Text(isLoading ? "Asking…" : "Ask Grok")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(AppTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLoading || (message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil))

                        if let errorText {
                            Text(errorText)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }

                        if let result {
                            resultCard(result)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Ask Grok")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EntitlementBadge(isPro: entitlements.isPro)
                }
            }
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
    }

    private var quotaBanner: some View {
        Group {
            if entitlements.isPro {
                Label("Unlimited Ask Grok & Photo Vision", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.proBadge)
            } else if let rem = entitlements.status.asksRemaining {
                Label("Free Peek: \(rem) ask left today", systemImage: "clock")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .font(.subheadline.weight(.medium))
    }

    @ViewBuilder
    private func resultCard(_ r: RecommendResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(r.vision == true ? "Photo Vision result" : "Recommendation", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            if let reason = r.reason {
                Text(reason).foregroundStyle(AppTheme.textPrimary)
            }
            if let tips = r.tips, !tips.isEmpty {
                ForEach(tips, id: \.self) { t in
                    Text("• \(t)").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
            }
            if let preset = r.preset ?? BundledPresets.recipe(id: r.presetId ?? "") {
                Button {
                    navigateRecipe = preset
                } label: {
                    Text("Open: \(preset.title)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppTheme.accentSecondary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func submit() async {
        errorText = nil
        result = nil
        isLoading = true
        defer { isLoading = false }
        let jpeg: Data? = selectedImage.flatMap { APIClient.compressForVision($0) }
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
            entitlements.showPaywall = true
            await entitlements.refresh()
        } catch let APIError.missingKey(msg) {
            errorText = msg
        } catch {
            errorText = error.localizedDescription
        }
    }
}
