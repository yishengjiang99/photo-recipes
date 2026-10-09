import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.overlay.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppTheme.space5) {
                        Text(entitlements.paywallMode == .soft
                              ? "Your photo is optimized"
                              : "Free Peek limit reached")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))

                        Text("AI Camera Pro")
                            .font(AppTheme.displayLG())
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(entitlements.paywallMode == .soft
                              ? "Keep the momentum — go Pro for unlimited Auto Optimize and Coach. Free keeps working."
                              : "You've used your free Optimizes for now. Pro unlocks unlimited Auto Optimize.")
                            .font(AppTheme.bodySm())
                            .foregroundStyle(AppTheme.inkSecondary)
                            .multilineTextAlignment(.center)

                        // Annual first — primary
                        if let yearly = storeKit.yearlyProduct {
                            planCard(
                                product: yearly,
                                title: "Yearly",
                                priceLine: displayPrice(yearly) + " / year",
                                saveLine: "≈ $5/mo · save vs monthly",
                                primary: true
                            )
                        } else {
                            placeholderYearly
                        }

                        if let monthly = storeKit.monthlyProduct {
                            planCard(
                                product: monthly,
                                title: "Monthly",
                                priceLine: displayPrice(monthly) + " / month",
                                saveLine: nil,
                                primary: false
                            )
                        } else {
                            placeholderMonthly
                        }

                        if storeKit.products.isEmpty {
                            Button {
                                Task { await storeKit.loadProducts() }
                            } label: {
                                HStack(spacing: 8) {
                                    if storeKit.isLoading { ProgressView().tint(AppTheme.ink) }
                                    Text(storeKit.isLoading ? "Loading plans…" : "Retry loading plans")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false, disabled: storeKit.isLoading))
                            .disabled(storeKit.isLoading)
                        }

                        comparison

                        if let err = storeKit.purchaseError {
                            Text(err)
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppTheme.space3)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                                        .fill(AppTheme.danger.opacity(0.12))
                                )
                        }

                        Button("Restore purchases") {
                            Task {
                                Analytics.shared.track("purchase_restore", props: ["source": "ios_paywall"])
                                await storeKit.restore()
                            }
                        }
                        .font(AppTheme.bodySmMedium())
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(minHeight: AppTheme.touchMin)

                        Text("iOS unlocks Pro via In-App Purchase only (StoreKit 2). Web Stripe does not unlock this build.")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                            .multilineTextAlignment(.center)

                        legal
                    }
                    .padding(AppTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                    .padding(AppTheme.space4)
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Analytics.shared.track("paywall_view", props: entitlements.paywallViewProps) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Soft (post-success) sheet: "Keep using free" stays visible at every detent.
                    Button(entitlements.paywallMode == .soft ? "Keep using free" : "Close") {
                        Analytics.shared.track("paywall_dismiss", props: [
                            "mode": entitlements.paywallMode.rawValue,
                            "paywall_trigger": entitlements.paywallTrigger,
                            "action": entitlements.paywallMode == .soft ? "keep_free" : "close",
                        ])
                        dismiss()
                    }
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(minHeight: AppTheme.touchMin)
                }
            }
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .task { if storeKit.products.isEmpty { await storeKit.loadProducts() } }
        }
    }

    private func planCard(
        product: Product,
        title: String,
        priceLine: String,
        saveLine: String?,
        primary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack {
                Text(title)
                    .font(AppTheme.bodyMedium())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if primary {
                    Text("Best value")
                        .font(AppTheme.caption())
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.accentOnAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.accent))
                }
            }

            if primary {
                Text("7-day free trial")
                    .font(AppTheme.caption())
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.success.opacity(0.15)))
            }

            Text(priceLine)
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)

            if let saveLine {
                Text(saveLine)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            }

            Button {
                Task {
                    let plan = product.id.contains("yearly") ? "yearly" : "monthly"
                    Analytics.shared.track("paywall_plan_select", props: ["plan": plan, "source": "ios_paywall"])
                    Analytics.shared.track("purchase_start", props: ["plan": plan, "source": "storekit"])
                    let ok = await storeKit.purchase(product)
                    if ok {
                        Analytics.shared.track("purchase_success", props: ["plan": plan, "source": "storekit"])
                        dismiss()
                    } else if storeKit.purchaseError != nil {
                        Analytics.shared.track("purchase_fail", props: ["plan": plan, "source": "storekit"])
                    }
                }
            } label: {
                HStack {
                    if storeKit.isPurchasing { ProgressView().tint(primary ? AppTheme.accentOnAccent : AppTheme.ink) }
                    Text("Start free trial")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(filled: primary, disabled: storeKit.isPurchasing))
            .disabled(storeKit.isPurchasing)
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .fill(AppTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(primary ? AppTheme.accent : AppTheme.border, lineWidth: primary ? 1.5 : 1)
                )
        )
    }

    private var placeholderYearly: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack {
                Text("Yearly").font(AppTheme.bodyMedium()).foregroundStyle(AppTheme.ink)
                Spacer()
                Text("Best value")
                    .font(AppTheme.caption()).fontWeight(.bold).foregroundStyle(AppTheme.accentOnAccent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.accent))
            }
            Text("7-day free trial")
                .font(AppTheme.caption()).fontWeight(.semibold).foregroundStyle(AppTheme.success)
            Text("$59.99 / year")
                .font(AppTheme.displayTitle()).foregroundStyle(AppTheme.ink)
            Text("≈ $5/mo · save vs monthly")
                .font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
            Text("Start free trial")
                .frame(maxWidth: .infinity)
                .font(AppTheme.bodyMedium())
                .foregroundStyle(AppTheme.accentOnAccent)
                .frame(minHeight: AppTheme.touchMin)
                .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.accent.opacity(0.55)))
            Text("Loading plans from the App Store…")
                .font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.accent, lineWidth: 1.5)
        )
    }

    private var placeholderMonthly: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            Text("Monthly").font(AppTheme.bodyMedium()).foregroundStyle(AppTheme.ink)
            Text("$7.99 / month").font(AppTheme.displayTitle()).foregroundStyle(AppTheme.ink)
            Text("Start free trial")
                .frame(maxWidth: .infinity)
                .font(AppTheme.bodyMedium())
                .foregroundStyle(AppTheme.ink)
                .frame(minHeight: AppTheme.touchMin)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                        .stroke(AppTheme.borderStrong, lineWidth: 1.5)
                )
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var comparison: some View {
        HStack(alignment: .top, spacing: AppTheme.space4) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Free Peek")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.inkSecondary)
                featureRow("Browse recipes", pro: false)
                featureRow("1 Ask / day", pro: false)
                featureRow("Steps readable", pro: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pro")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.ink)
                featureRow("Browse recipes", pro: true)
                featureRow("Unlimited Ask", pro: true)
                featureRow("Interactive checklist", pro: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.surface2)
        )
    }

    private func featureRow(_ text: String, pro: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(pro ? AppTheme.accent : AppTheme.inkSecondary)
            Text(text)
                .font(AppTheme.caption())
                .foregroundStyle(pro ? AppTheme.ink : AppTheme.inkSecondary)
        }
    }

    private func displayPrice(_ product: Product) -> String {
        product.displayPrice
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Payment is charged to your Apple ID. Subscription renews unless canceled at least 24 hours before the end of the period. Manage in Settings → Apple ID → Subscriptions.")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.inkTertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.accent)
                Link("Privacy Policy", destination: URL(string: "https://photo.grepawk.com/privacy")!)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(minHeight: AppTheme.touchMin)
            Text("Product IDs: \(IAPProductID.yearly) · \(IAPProductID.monthly)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.inkTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
