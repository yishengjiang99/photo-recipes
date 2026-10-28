import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var shownAt = Date()
    @State private var selectedPlan: String?
    @State private var dismissTracked = false
    @State private var didEmitProofShown = false

    /// Stable id for this paywall presentation (contract: paywall_view /
    /// paywall_plan_select / purchase_start carry `paywall_id`).
    private var paywallId: String {
        "\(entitlements.paywallMode.rawValue)_\(entitlements.paywallTrigger)"
    }

    private var paywallAssigner: ExperimentAssigner {
        ExperimentAssigner(
            defaults: .standard,
            installIdProvider: { Analytics.shared.anonId },
            sink: Analytics.shared
        )
    }

    /// Treatment arm of the paywall value experiment (independent of the
    /// first-photo experiment; assignment persists across flag flips).
    private var isValueArm: Bool {
        guard FeatureFlags().paywallExperimentActive else { return false }
        return paywallAssigner.assignment(for: .paywall) == .treatment
    }

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

                        valueProofSection

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
                                await storeKit.restore()
                                // Exactly one purchase_restore per tap: v2
                                // (with result + entitlement count) when the
                                // v2 flag is on, the legacy event otherwise.
                                let v2Restore = PurchaseTelemetryV2.live()
                                if v2Restore.isEnabled {
                                    v2Restore.recordRestore(
                                        result: entitlements.isPro ? "entitled" : "no_entitlement",
                                        verifiedEntitlementCount: storeKit.purchasedProductIDs.count
                                    )
                                } else {
                                    Analytics.shared.track("purchase_restore", props: ["source": "ios_paywall"])
                                }
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
            .onAppear {
                shownAt = Date()
                selectedPlan = nil
                dismissTracked = false
                var props = entitlements.paywallViewProps
                if FeatureFlags().paywallExperimentActive {
                    props["experiment_arm"] = paywallAssigner.assignment(for: .paywall).rawValue
                    props["paywall_id"] = paywallId
                }
                Analytics.shared.track("paywall_view", props: props)
            }
            // Swipe-down / programmatic close: still emit paywall_dismiss once.
            .onDisappear { trackDismiss(action: "swipe") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Soft (post-success) sheet: "Keep using free" stays visible at every detent.
                    Button(entitlements.paywallMode == .soft ? "Keep using free" : "Close") {
                        trackDismiss(action: entitlements.paywallMode == .soft ? "keep_free" : "close")
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

    /// paywall_dismiss — once per presentation (button or swipe).
    private func trackDismiss(action: String) {
        guard !dismissTracked else { return }
        dismissTracked = true
        let q = FreeOptimizeQuota()
        let triesLeft = entitlements.isPro
            ? "unlimited"
            : "\(q.remaining(serverDailyLimit: entitlements.status.freeDailyLimit))"
        Analytics.shared.track("paywall_dismiss", props: PurchaseTelemetry.dismissProps(
            mode: entitlements.paywallMode.rawValue,
            trigger: entitlements.paywallTrigger,
            action: action,
            timeOnScreenMs: Int(Date().timeIntervalSince(shownAt) * 1000),
            selectedPlan: selectedPlan,
            freeTriesLeft: triesLeft
        ))
    }

    /// Genuine value proof for the treatment arm: the user's real last saved
    /// optimized result (recipe + settings actually applied). No fabricated
    /// before/after — no baseline image was ever persisted. Falls back to the
    /// control layout (renders nothing) when no proof exists.
    @ViewBuilder
    private var valueProofSection: some View {
        if isValueArm, let proof = PaywallValueProof.load() {
            VStack(alignment: .leading, spacing: AppTheme.space2) {
                Text("Your optimized result")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.ink)
                if let title = proof.recipeTitle {
                    Text(title)
                        .font(AppTheme.bodySm())
                        .foregroundStyle(AppTheme.ink)
                }
                Text(proof.appliedSettingsSummary)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkSecondary)
                Text("Pro keeps Auto Optimize unlimited, so every shot can be set up like this.")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.space4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .fill(AppTheme.surface2)
            )
            .onAppear {
                guard !didEmitProofShown else { return }
                didEmitProofShown = true
                Analytics.shared.track("paywall_value_proof_shown", props: ["arm": "treatment"])
            }
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
                    selectedPlan = plan
                    // cancelled / pending / failed are also tracked in
                    // StoreKitManager.purchase (purchase_cancelled,
                    // purchase_pending, purchase_failed) via PurchaseTelemetry.
                    let v2 = PurchaseTelemetryV2.live()
                    let attemptId = v2.beginAttempt()
                    Analytics.shared.track("paywall_plan_select", props: [
                        "plan": plan, "source": "ios_paywall",
                        "product_id": product.id, "paywall_id": paywallId,
                    ])
                    Analytics.shared.track("purchase_start", props: [
                        "plan": plan, "source": "storekit",
                        "product_id": product.id, "paywall_id": paywallId,
                        "purchase_attempt_id": attemptId,
                    ])
                    let ok = await storeKit.purchase(product)
                    switch storeKit.lastPurchaseOutcome {
                    case .verified(let transactionId, let activated)?:
                        if v2.isEnabled {
                            // Canonical v2 success — emitted only here, only
                            // after verification + entitlement activation.
                            v2.recordVerifiedAndActivated(
                                attemptId: attemptId,
                                transactionId: transactionId,
                                productId: product.id,
                                environment: storeKit.lastVerifiedEnvironment ?? "unknown",
                                entitlementType: "pro",
                                activationSource: "purchase"
                            )
                            if activated { dismissTracked = true; dismiss() }
                        } else if ok {
                            Analytics.shared.track("purchase_success", props: ["plan": plan, "source": "storekit"])
                            dismissTracked = true // converted, not a dismiss
                            dismiss()
                        }
                    case .cancelled?, .pending?:
                        // Tracked once, inside StoreKitManager.purchase via
                        // PurchaseTelemetry (purchase_cancelled / purchase_pending).
                        // The v2 emitter is NOT called here — on current main
                        // that would double-emit the same event names.
                        break
                    case .unverified?:
                        // purchase_failed (stage: verification) already tracked
                        // in StoreKitManager; legacy purchase_fail kept.
                        Analytics.shared.track("purchase_fail", props: ["plan": plan, "source": "storekit"])
                    default:
                        if ok {
                            // Outcome surface unavailable — preserve legacy behavior.
                            if !v2.isEnabled {
                                Analytics.shared.track("purchase_success", props: ["plan": plan, "source": "storekit"])
                            }
                            dismissTracked = true // converted, not a dismiss
                            dismiss()
                        } else if storeKit.purchaseError != nil {
                            Analytics.shared.track("purchase_fail", props: ["plan": plan, "source": "storekit"])
                        }
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
