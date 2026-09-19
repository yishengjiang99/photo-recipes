import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.accent)
                        Text("Photo Recipes Pro")
                            .font(.largeTitle.bold())
                        Text("Unlimited Ask Grok & Photo Vision, plus interactive field checklists.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.textSecondary)

                        trialBadge

                        // Yearly = primary CTA
                        if let yearly = storeKit.yearlyProduct {
                            planButton(
                                product: yearly,
                                title: "Yearly — Best value",
                                subtitle: displayPrice(yearly) + " / year",
                                primary: true
                            )
                        } else {
                            placeholderYearly
                        }

                        if let monthly = storeKit.monthlyProduct {
                            planButton(
                                product: monthly,
                                title: "Monthly",
                                subtitle: displayPrice(monthly) + " / month",
                                primary: false
                            )
                        } else {
                            placeholderMonthly
                        }

                        Text("iOS unlocks Pro via In-App Purchase only (StoreKit 2). Web Stripe subscriptions are separate and do not unlock the App Store build.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        if let err = storeKit.purchaseError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        Button("Restore purchases") {
                            Task { await storeKit.restore() }
                        }
                        .frame(minHeight: 44)
                        .foregroundStyle(AppTheme.accentSecondary)

                        legal
                    }
                    .padding()
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.frame(minHeight: 44)
                }
            }
            .task { await storeKit.loadProducts() }
        }
    }

    private var trialBadge: some View {
        Text("7-day free trial")
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.proBadge)
            .foregroundStyle(.black)
            .clipShape(Capsule())
    }

    private func planButton(product: Product, title: String, subtitle: String, primary: Bool) -> some View {
        Button {
            Task {
                let ok = await storeKit.purchase(product)
                if ok { dismiss() }
            }
        } label: {
            VStack(spacing: 4) {
                if storeKit.isPurchasing { ProgressView().tint(primary ? .black : .white) }
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline)
                if primary {
                    Text("Primary plan").font(.caption2.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 8)
            .background(primary ? AppTheme.accent : AppTheme.card)
            .foregroundStyle(primary ? .black : AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(primary ? Color.clear : AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .disabled(storeKit.isPurchasing)
    }

    private var placeholderYearly: some View {
        VStack(spacing: 4) {
            Text("Yearly — Best value").font(.headline)
            Text("$59.99 / year").font(.subheadline)
            Text("Primary plan").font(.caption2.weight(.bold))
            Text("Configure product in App Store Connect / StoreKit config")
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding()
        .background(AppTheme.accent.opacity(0.5))
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var placeholderMonthly: some View {
        VStack(spacing: 4) {
            Text("Monthly").font(.headline)
            Text("$7.99 / month").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func displayPrice(_ product: Product) -> String {
        product.displayPrice
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Payment is charged to your Apple ID. Subscription renews unless canceled at least 24 hours before the end of the period. Manage in Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Text("Product IDs: \(IAPProductID.yearly) · \(IAPProductID.monthly)")
                .font(.caption2.monospaced())
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
