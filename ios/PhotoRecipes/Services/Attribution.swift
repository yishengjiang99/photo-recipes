import Foundation
import StoreKit
import UIKit
import os

/// Install attribution helpers for paid acquisition (X / Meta App Install ads), added in 1.2.
///
/// - SKAdNetwork: on first launch we register the install with
///   `updatePostbackConversionValue(0, coarseValue: .low)` (SKAN 4). The system applies
///   SKAdNetwork conversion updates to AdAttributionKit postbacks too. Postback copies go to
///   `NSAdvertisingAttributionReportEndpoint` / `AdAttributionKit.AttributionCopyEndpoint`
///   (Info.plist) → grepawk.com/.well-known/… → server/attribution.ts.
/// - Meta App Events (FacebookCore): separate — see `MetaEvents.swift` (ATT + install/purchase).
/// - AppsFlyer was removed; do not re-add without an explicit product decision.
@MainActor
final class Attribution {
    static let shared = Attribution()

    static let appleAppID = "6813991381"

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "attribution")
    private let defaults = UserDefaults.standard

    private enum Key {
        static let skanRegistered = "attribution.skanRegistered"
    }

    private var configured = false

    // MARK: - Launch

    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    func configure() {
        guard !configured else { return }
        configured = true
        registerInstallForAdNetworkAttribution()
    }

    /// SKAN 4 install registration: fine value 0, coarse low, window unlocked. First launch only.
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
}
