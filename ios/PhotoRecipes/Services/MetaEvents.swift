import AppTrackingTransparency
import FacebookCore
import Foundation
import UIKit

/// Meta (Facebook) App Events integration for ad attribution.
///
/// - Lets a future Meta app-install campaign attribute installs
///   (`activateApp` on every foreground).
/// - Logs a custom `StartTrial` event when a subscription trial begins and a
///   standard `fb_mobile_purchase` event when a subscription payment completes,
///   so campaigns can later optimize toward trial/purchase events.
///
/// The SDK's automatic in-app-purchase event logging is DISABLED
/// (`isAutoLogAppEventsEnabled = false`) because purchases are logged manually
/// (see `logSubscriptionPurchase`) — leaving it on would double-count every
/// StoreKit 2 purchase.
///
/// PRIVACY NOTE: this integration shows an App Tracking Transparency prompt
/// (see `requestTrackingIfNeeded`) and sends install/purchase events to Meta.
/// `configure` still no-ops if Info.plist has `FB_APP_ID_PLACEHOLDER`; the
/// shipping Info.plist carries the real Facebook App ID, so the SDK is active.
/// SKAdNetwork install registration is separate — see `Attribution.swift`.
@MainActor
enum MetaEvents {
    /// True once `configure` has initialized the SDK with a real App ID.
    /// All logging calls are safe no-ops until then.
    private static var isConfigured = false

    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    static func configure(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        guard Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String
            != "FB_APP_ID_PLACEHOLDER"
        else {
            // Real Facebook App ID not configured yet — leave the SDK dormant.
            return
        }
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        // Purchases are logged manually below; keep the SDK's own StoreKit 2
        // observer off so each purchase is counted exactly once.
        Settings.shared.isAutoLogAppEventsEnabled = false
        isConfigured = true
        syncAdvertiserTrackingFlag()
    }

    /// Call from `applicationDidBecomeActive`. This is the install/session
    /// signal Meta uses for attribution.
    ///
    /// IMPORTANT: On first launch (ATT status `.notDetermined`), this does NOT
    /// send the activation event immediately. Instead it requests ATT
    /// authorization first, then sends the event in the completion handler.
    /// Apple requires the ATT prompt to appear before any tracking data is
    /// collected (Guideline 2.1).
    static func activateApp() {
        guard isConfigured else { return }
        guard ATTrackingManager.trackingAuthorizationStatus != .notDetermined else {
            // ATT not yet determined — request it; the activation event
            // fires in the requestTrackingIfNeeded completion handler.
            requestTrackingIfNeeded()
            return
        }
        AppEvents.shared.activateApp()
    }

    /// Shows the App Tracking Transparency prompt on first launch.
    /// Safe to call on every foregrounding — the system only prompts
    /// while the status is `.notDetermined`.
    ///
    /// NOTE: This is intentionally NOT gated behind onboarding completion.
    /// Apple requires the ATT prompt before any tracking data is collected,
    /// and reviewers test on fresh installs without completing onboarding.
    static func requestTrackingIfNeeded() {
        guard isConfigured else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            syncAdvertiserTrackingFlag()
            return
        }
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in
                syncAdvertiserTrackingFlag()
                // ATT now determined — safe to send the activation event.
                AppEvents.shared.activateApp()
            }
        }
    }

    /// Logs a completed subscription payment with a verified StoreKit 2 transaction.
    /// - Trial (introductory offer) → custom `StartTrial` event.
    /// - Paid purchase or renewal → standard `fb_mobile_purchase` event.
    static func logSubscriptionPurchase(
        productId: String,
        price: Decimal,
        currencyCode: String?,
        isTrial: Bool
    ) {
        guard isConfigured else { return }
        let amount = (price as NSDecimalNumber).doubleValue
        let currency = currencyCode ?? "USD"
        if isTrial {
            AppEvents.shared.logEvent(
                AppEvents.Name("StartTrial"),
                parameters: [
                    AppEvents.ParameterName(rawValue: "product_id"): productId,
                    AppEvents.ParameterName(rawValue: "currency"): currency,
                ]
            )
        } else {
            AppEvents.shared.logPurchase(
                amount: amount,
                currency: currency,
                parameters: [AppEvents.ParameterName(rawValue: "product_id"): productId]
            )
        }
    }

    /// Mirrors the device's ATT choice into the SDK's advertiser-tracking flag.
    private static func syncAdvertiserTrackingFlag() {
        Settings.shared.isAdvertiserTrackingEnabled =
            ATTrackingManager.trackingAuthorizationStatus == .authorized
    }
}
