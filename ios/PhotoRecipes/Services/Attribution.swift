import Foundation
import StoreKit
import AppTrackingTransparency
import UIKit
import os
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

/// Install attribution for paid acquisition (X App Install ads), added in 1.2.
///
/// - SKAdNetwork: on first launch we register the install with
///   `updatePostbackConversionValue(0, coarseValue: .low)` (SKAN 4). The system applies
///   SKAdNetwork conversion updates to AdAttributionKit postbacks too. Postback copies go to
///   `NSAdvertisingAttributionReportEndpoint` / `AdAttributionKit.AttributionCopyEndpoint`
///   (Info.plist) → grepawk.com/.well-known/… → server/attribution.ts.
/// - AppsFlyer (AppsFlyerLib, SPM, pinned): enabled only when the build carries a dev key
///   (`AppsFlyerDevKey` in Info.plist ← `APPSFLYER_DEV_KEY` build setting ← GitHub secret).
///   Without a key the SDK is never initialised, no ATT prompt is shown, and nothing leaves
///   the device for attribution.
/// - ATT: asked once, after onboarding (never on the first frame). AppsFlyer `start()` waits
///   up to 60 s for the answer — the same contract as `waitForATTUserAuthorization(timeoutInterval: 60)`,
///   which AppsFlyer 7 deprecated in favour of collecting ATT inside the session-ready listener.
@MainActor
final class Attribution {
    static let shared = Attribution()

    static let appleAppID = "6813991381"
    static let attWaitTimeout: Duration = .seconds(60)

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "attribution")
    private let defaults = UserDefaults.standard

    private enum Key {
        static let skanRegistered = "attribution.skanRegistered"
        static let firstAutoOptimizeLogged = "attribution.firstAutoOptimizeLogged"
    }

    /// True once AppsFlyer has been initialised with a dev key.
    private(set) var isSDKEnabled = false
    private var configured = false
    private var pendingStart = false
    private var sessionGeneration = 0
    /// AppsFlyer drops events logged before `start()`, so hold them until the first start.
    private var didStart = false
    private var queuedEvents: [(name: String, values: [String: Any])] = []

    /// Dev key injected at build time; nil when the secret was absent (`$(APPSFLYER_DEV_KEY)` → "").
    nonisolated static var devKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    // MARK: - Launch

    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    func configure() {
        guard !configured else { return }
        configured = true
        registerInstallForAdNetworkAttribution()

        #if canImport(AppsFlyerLib)
        guard let key = Self.devKey else {
            log.info("AppsFlyer disabled: no APPSFLYER_DEV_KEY in this build")
            return
        }
        let af = AppsFlyerLib.shared()
        af.initialize(devKey: key, appId: Self.appleAppID)
        #if DEBUG
        af.isDebug = true
        #endif
        // Fires on the main queue once per foreground cycle; we decide when to call start().
        af.registerSessionReadyListener { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sessionReady()
            }
        }
        isSDKEnabled = true
        log.info("AppsFlyer configured")
        #endif
    }

    /// SKAN 4 install registration: fine value 0, coarse low, window unlocked. First launch only,
    /// so we never reset a value AppsFlyer's SKAN conversion manager raised later.
    private func registerInstallForAdNetworkAttribution() {
        guard !defaults.bool(forKey: Key.skanRegistered) else { return }
        defaults.set(true, forKey: Key.skanRegistered)
        let log = self.log
        SKAdNetwork.updatePostbackConversionValue(0, coarseValue: .low, lockWindow: false) { error in
            if let error {
                log.error("SKAN register failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("SKAN install registered (fine 0, coarse low)")
            }
        }
    }

    // MARK: - AppsFlyer session start (gated on ATT, max 60 s)

    private func sessionReady() {
        sessionGeneration += 1
        let generation = sessionGeneration
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            startSDK(reason: "att_known")
            return
        }
        pendingStart = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.attWaitTimeout)
            guard let self, self.pendingStart, self.sessionGeneration == generation else { return }
            self.startSDK(reason: "att_timeout")
        }
    }

    private func startSDK(reason: String) {
        pendingStart = false
        #if canImport(AppsFlyerLib)
        guard isSDKEnabled else { return }
        log.info("AppsFlyer start (\(reason, privacy: .public))")
        AppsFlyerLib.shared().start()
        didStart = true
        let queued = queuedEvents
        queuedEvents.removeAll()
        for event in queued {
            AppsFlyerLib.shared().logEvent(event.name, withValues: event.values)
        }
        #endif
    }

    // MARK: - ATT (after onboarding only)

    /// Wait `delay`, then ask for tracking permission once. Never called from onboarding or cold open.
    func requestTrackingAuthorizationAfter(_ delay: Duration) async {
        guard isSDKEnabled else { return }
        try? await Task.sleep(for: delay)
        await requestTrackingAuthorizationIfNeeded()
    }

    func requestTrackingAuthorizationIfNeeded() async {
        guard isSDKEnabled else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            if pendingStart { startSDK(reason: "att_known") }
            return
        }
        // The system silently returns .notDetermined unless the app is active.
        guard UIApplication.shared.applicationState == .active else { return }
        let status = await ATTrackingManager.requestTrackingAuthorization()
        guard status != .notDetermined else { return }
        Analytics.shared.track("att_prompt_result", props: ["status": Self.describe(status)])
        if pendingStart { startSDK(reason: "att_\(Self.describe(status))") }
    }

    nonisolated static func describe(_ status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not_determined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - In-app events

    /// Called for every `auto_optimize_success`; logs AppsFlyer `first_auto_optimize` once per install.
    func noteAutoOptimizeSuccess() {
        guard isSDKEnabled, !defaults.bool(forKey: Key.firstAutoOptimizeLogged) else { return }
        defaults.set(true, forKey: Key.firstAutoOptimizeLogged)
        logEvent("first_auto_optimize", values: [:])
    }

    /// StoreKit purchase from the paywall: free-trial start → `af_start_trial`, paid → `af_subscribe`.
    func notePurchase(product: Product, transaction: Transaction) {
        let currency = product.priceFormatStyle.currencyCode
        let price = NSDecimalNumber(decimal: product.price)
        if Self.isFreeTrial(transaction) {
            logEvent("af_start_trial", values: [
                "af_content_id": product.id,
                "af_currency": currency,
                "af_price": price,
            ])
        } else {
            logEvent("af_subscribe", values: [
                "af_content_id": product.id,
                "af_currency": currency,
                "af_revenue": price,
            ])
        }
    }

    nonisolated static func isFreeTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            guard let offer = transaction.offer else { return false }
            return offer.type == .introductory && offer.paymentMode == .freeTrial
        }
        // iOS 17.0–17.1: our only introductory offers are the 7-day free trials.
        return transaction.offerType == .introductory
    }

    private func logEvent(_ name: String, values: [String: Any]) {
        #if canImport(AppsFlyerLib)
        guard isSDKEnabled else { return }
        guard didStart else {
            queuedEvents.append((name, values))
            return
        }
        AppsFlyerLib.shared().logEvent(name, withValues: values)
        #endif
    }
}
