import Foundation

/// Canonical purchase-lifecycle telemetry (Workstreams C/D), gated by
/// `purchase_telemetry_v2_enabled`.
///
/// Contract highlights:
/// - `purchase_success` is emitted ONLY from
///   `recordVerifiedAndActivated(...)` — i.e. after StoreKit verification has
///   succeeded AND the entitlement is active. There is no other code path in
///   this type that can emit it.
/// - Verified transaction ids are deduplicated against a bounded persisted
///   set, so relaunch / restore replays cannot double-count a purchase.
/// - Renewals and restores are reported through `recordRestore` /
///   restore-result events, never as `purchase_success`.
/// - No receipts, JWS payloads, or payment details are ever logged — only
///   ids, product ids, and categorical outcomes.
///
/// All prop keys avoid the Analytics key filter (no "photo"/"token"/…).
@MainActor
final class PurchaseTelemetryV2 {
    static let dedupeKey = "purchaseTelemetryV2.verifiedTransactionIds"
    static let maxDedupedTransactions = 200

    private let defaults: UserDefaults
    private let sink: AnalyticsEventSink?
    private let enabled: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        sink: AnalyticsEventSink?,
        enabled: @escaping () -> Bool
    ) {
        self.defaults = defaults
        self.sink = sink
        self.enabled = enabled
    }

    static func live(defaults: UserDefaults = .standard) -> PurchaseTelemetryV2 {
        let flags = FeatureFlags(defaults: defaults)
        return PurchaseTelemetryV2(
            defaults: defaults,
            sink: Analytics.shared,
            enabled: { flags.purchaseTelemetryV2Enabled }
        )
    }

    var isEnabled: Bool { enabled() }

    private func emit(_ event: String, props: [String: String]) {
        guard enabled() else { return }
        sink?.track(event, props: props)
    }

    // MARK: - Attempt lifecycle

    /// Opens an attempt and returns its id. Emits nothing itself — the legacy
    /// `purchase_start` remains the single start event (now carrying the
    /// attempt id via the caller's props) so dashboards don't double-count.
    func beginAttempt() -> String { UUID().uuidString }

    func recordCancelled(attemptId: String, source: String) {
        emit("purchase_cancelled", props: [
            "purchase_attempt_id": attemptId,
            "cancellation_source": source,
        ])
    }

    /// Ask-to-Buy / SCA pending — NOT a failure.
    func recordPending(attemptId: String, productId: String) {
        emit("purchase_pending", props: [
            "purchase_attempt_id": attemptId,
            "product_id": productId,
        ])
    }

    func recordFailed(attemptId: String, errorCategory: String) {
        emit("purchase_failed", props: [
            "purchase_attempt_id": attemptId,
            "error_category": errorCategory,
        ])
    }

    // MARK: - Verified success (the only purchase_success path)

    /// Emits `purchase_verified`, `entitlement_activated`, then
    /// `purchase_success` — in that order — exactly once per transaction id.
    /// Returns false (and emits nothing) when the transaction was already
    /// recorded, so duplicate StoreKit callbacks cannot double-count.
    @discardableResult
    func recordVerifiedAndActivated(
        attemptId: String,
        transactionId: String,
        productId: String,
        environment: String,
        entitlementType: String,
        activationSource: String
    ) -> Bool {
        guard enabled() else { return false }
        var seen = defaults.stringArray(forKey: Self.dedupeKey) ?? []
        guard !seen.contains(transactionId) else { return false }
        seen.append(transactionId)
        if seen.count > Self.maxDedupedTransactions {
            seen = Array(seen.suffix(Self.maxDedupedTransactions))
        }
        defaults.set(seen, forKey: Self.dedupeKey)

        emit("purchase_verified", props: [
            "purchase_attempt_id": attemptId,
            "transaction_id": transactionId,
            "product_id": productId,
            "environment": environment,
        ])
        emit("entitlement_activated", props: [
            "entitlement_type": entitlementType,
            "activation_source": activationSource,
            "transaction_id": transactionId,
            "product_id": productId,
        ])
        emit("purchase_success", props: [
            "purchase_attempt_id": attemptId,
            "transaction_id": transactionId,
            "product_id": productId,
            "entitlement_type": entitlementType,
            "telemetry_v": "2",
        ])
        return true
    }

    // MARK: - Restore

    func recordRestore(result: String, verifiedEntitlementCount: Int) {
        emit("purchase_restore", props: [
            "result": result,
            "verified_entitlement_count": "\(verifiedEntitlementCount)",
            "telemetry_v": "2",
        ])
    }
}

// MARK: - Paywall value proof (Workstream C)

/// Genuine value proof for the `paywall_value_v1` arm: the recipe and applied
/// settings summary of the user's REAL last saved optimized capture, recorded
/// by CameraView at save time. There is deliberately no before/after pair —
/// the app never persisted an un-optimized baseline, so none is fabricated.
/// The saved image itself lives in the user's Photos library; this model
/// carries only its factual summary (never sent as an analytics prop value
/// beyond the categorical `paywall_value_proof_shown` event).
struct PaywallValueProof: Equatable {
    var recipeTitle: String?
    var appliedSettingsSummary: String
    var settingsCount: Int
    var savedAt: Date

    static let recipeTitleKey = "paywallProof.recipeTitle"
    static let summaryKey = "paywallProof.settingsSummary"
    static let countKey = "paywallProof.settingsCount"
    static let savedAtKey = "paywallProof.savedAt"

    static func record(
        defaults: UserDefaults = .standard,
        recipeTitle: String?,
        appliedSettingsSummary: String,
        settingsCount: Int,
        savedAt: Date = Date()
    ) {
        defaults.set(recipeTitle, forKey: recipeTitleKey)
        defaults.set(appliedSettingsSummary, forKey: summaryKey)
        defaults.set(settingsCount, forKey: countKey)
        defaults.set(savedAt, forKey: savedAtKey)
    }

    /// Nil when no optimized capture has ever been saved on this install —
    /// the paywall then falls back to the control UI, unchanged.
    static func load(defaults: UserDefaults = .standard) -> PaywallValueProof? {
        guard let savedAt = defaults.object(forKey: savedAtKey) as? Date,
              let summary = defaults.string(forKey: summaryKey), !summary.isEmpty
        else { return nil }
        return PaywallValueProof(
            recipeTitle: defaults.string(forKey: recipeTitleKey),
            appliedSettingsSummary: summary,
            settingsCount: defaults.integer(forKey: countKey),
            savedAt: savedAt
        )
    }
}
