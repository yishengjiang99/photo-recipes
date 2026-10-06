import SwiftUI
import UIKit

/// Celebrate a saved optimized photo with one next action ("Try another photo"), and —
/// only after that value — offer a concrete reminder for tomorrow.
struct PostSaveCard: View {
    struct Model: Identifiable {
        let id = UUID()
        var image: UIImage?
        var recipeTitle: String?
        var settingsCount: Int
        var lookName: String?
        var offerReminder: Bool
    }

    let model: Model
    var onNext: () -> Void
    var onRemind: () -> Void

    private var summary: String {
        var parts: [String] = [model.recipeTitle ?? "Auto Optimize"]
        if model.settingsCount > 0 {
            parts.append("\(model.settingsCount) setting\(model.settingsCount == 1 ? "" : "s") tuned")
        }
        if let look = model.lookName { parts.append(look) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: AppTheme.space3) {
            if let img = model.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text("Saved — optimized")
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)
            Text(summary)
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button(action: onNext) {
                Text("Try another photo")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.accentOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)

            if model.offerReminder {
                Button(action: onRemind) {
                    Text("Remind me tomorrow to polish another")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
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
        .padding(.horizontal, AppTheme.space4)
    }
}

/// Show the celebration on the first saved optimized photo; offer it once more (≥20h later)
/// only if the reminder has not been asked yet.
@MainActor
enum PostSaveCelebration {
    static let countKey = "postSave.cardShownCount"
    static let lastKey = "postSave.cardLastShownAt"

    static var shouldShow: Bool {
        let d = UserDefaults.standard
        let count = d.integer(forKey: countKey)
        if count == 0 { return true }
        guard count < 2, !PushNotificationManager.shared.didAskPushPermission else { return false }
        guard let last = d.object(forKey: lastKey) as? Date else { return true }
        return Date().timeIntervalSince(last) > 20 * 3600
    }

    static func markShown() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: countKey) + 1, forKey: countKey)
        d.set(Date(), forKey: lastKey)
    }
}
