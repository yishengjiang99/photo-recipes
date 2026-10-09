import Foundation
import StoreKit

/// Product IDs — must match App Store Connect + Products.storekit exactly.
enum IAPProductID {
    static let monthly = "com.ragnus.mvp.pro.monthly"
    static let yearly = "com.ragnus.mvp.pro.yearly"
    static let all: Set<String> = [monthly, yearly]

    static func plan(for productId: String) -> SubscriptionPlan? {
        switch productId {
        case monthly: return .monthly
        case yearly: return .yearly
        default: return nil
        }
    }
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?
    @Published private(set) var isPurchasing = false

    /// Result of the most recent /api/iap/verify round (server-side Pro, not just local StoreKit).
    private var serverConfirmedPro = false
    private var lastSyncError: String?
    private var updatesTask: Task<Void, Never>?
    private let api: APIClient
    private let entitlements: EntitlementsStore

    init(api: APIClient = .shared, entitlements: EntitlementsStore) {
        self.api = api
        self.entitlements = entitlements
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        api.paywallRecovery = { [weak self] in
            await self?.recoverFromServerPaywall() ?? .notEntitled
        }
    }

    /// Server said 402 — re-verify current App Store entitlements so a subscriber isn't gated as Free Peek.
    func recoverFromServerPaywall() async -> APIClient.PaywallRecovery {
        serverConfirmedPro = false
        lastSyncError = nil
        await refreshEntitlementsFromCurrentEntitlements()
        if purchasedProductIDs.isEmpty { return .notEntitled }
        if serverConfirmedPro { return .synced }
        return .syncFailed(lastSyncError ?? "server did not confirm Pro")
    }

    deinit {
        updatesTask?.cancel()
    }

    var yearlyProduct: Product? {
        products.first { $0.id == IAPProductID.yearly }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == IAPProductID.monthly }
    }

    /// Loads both subscriptions. StoreKit returns an EMPTY array (no error) when products are not yet
    /// available to this storefront/sandbox, so retry with backoff and surface a message instead of
    /// leaving the paywall stuck on disabled placeholders.
    func loadProducts() async {
        if isLoading { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        let delays: [UInt64] = [0, 1, 2, 4]
        var lastError: Error?
        for delay in delays {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            if Task.isCancelled { return }
            do {
                let loaded = try await Product.products(for: IAPProductID.all)
                if !loaded.isEmpty {
                    products = loaded.sorted { lhs, rhs in
                        if lhs.id == IAPProductID.yearly { return true }
                        if rhs.id == IAPProductID.yearly { return false }
                        return lhs.price < rhs.price
                    }
                    if loaded.count < IAPProductID.all.count {
                        print("[IAP] partial products: \(loaded.map(\.id))")
                    }
                    return
                }
                lastError = nil
            } catch {
                lastError = error
            }
        }
        if let lastError {
            purchaseError = "Could not load subscriptions: \(lastError.localizedDescription). Tap Retry."
        } else {
            purchaseError = "Subscriptions are not available from the App Store right now. Tap Retry."
        }
    }

    var productsUnavailable: Bool { products.isEmpty && !isLoading }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let jws = verification.jwsRepresentation
                await syncEntitlement(
                    signedTransaction: jws,
                    productId: product.id,
                    transaction: transaction
                )
                await transaction.finish()
                purchasedProductIDs.insert(product.id)
                MetaEvents.logSubscriptionPurchase(
                    productId: product.id,
                    price: product.price,
                    currencyCode: product.priceFormatStyle.currencyCode,
                    isTrial: transaction.offerType == .introductory
                )
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlementsFromCurrentEntitlements()
            await entitlements.refresh()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                await syncEntitlement(
                    signedTransaction: update.jwsRepresentation,
                    productId: transaction.productID,
                    transaction: transaction
                )
                await transaction.finish()
                purchasedProductIDs.insert(transaction.productID)
                // Refunds/revocations are not purchases — don't log them to Meta.
                if transaction.revocationDate == nil {
                    logMetaRenewal(productId: transaction.productID)
                }
            } catch {
                // Ignore unverified updates
            }
        }
    }

    /// Logs subscription renewals (and other out-of-band subscription payments)
    /// to Meta. Looks up the StoreKit product for price/currency; skips silently
    /// if the product isn't loaded.
    private func logMetaRenewal(productId: String) {
        guard let product = products.first(where: { $0.id == productId }) else { return }
        MetaEvents.logSubscriptionPurchase(
            productId: productId,
            price: product.price,
            currencyCode: product.priceFormatStyle.currencyCode,
            isTrial: false
        )
    }

    func refreshEntitlementsFromCurrentEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard IAPProductID.all.contains(transaction.productID) else { continue }
                ids.insert(transaction.productID)
                await syncEntitlement(
                    signedTransaction: result.jwsRepresentation,
                    productId: transaction.productID,
                    transaction: transaction
                )
            } catch {
                continue
            }
        }
        purchasedProductIDs = ids
        if ids.isEmpty { entitlements.clearVerifiedPro() }
    }

    private func syncEntitlement(
        signedTransaction: String,
        productId: String,
        transaction: Transaction
    ) async {
        guard let plan = IAPProductID.plan(for: productId) else { return }
        do {
            let res = try await api.verifyIAP(
                signedTransaction: signedTransaction,
                productId: productId,
                plan: plan
            )
            // Fail closed: only trust explicit pro from verified server payload.
            if res.pro == true {
                serverConfirmedPro = true
                entitlements.applyVerifiedPro(plan: plan)
            }
            await entitlements.refresh()
        } catch {
            lastSyncError = error.localizedDescription
            print("[IAP] server verify failed: \(error.localizedDescription)")
            // Refunded / lapsed transactions arrive via Transaction.updates too — never grant on those.
            let live = transaction.revocationDate == nil
                && (transaction.expirationDate.map { $0 > Date() } ?? true)
            guard live else { return }
            // Verified StoreKit transaction — grant Pro locally; retry server on next launch
            entitlements.applyVerifiedPro(plan: plan)
            purchaseError = "Purchased; server sync pending: \(error.localizedDescription)"
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
