import Foundation
import UIKit
import UserNotifications

/// Experiment 1 APNs client: permission after first successful Auto Optimize,
/// token register, foreground/tap → deep link `photo-recipes://auto-optimize`.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    static let hasCompletedFirstAutoOptimizeKey = "hasCompletedFirstAutoOptimize"
    static let didAskPushPermissionKey = "didAskPushPermission"
    static let autoOptimizeURL = URL(string: "photo-recipes://auto-optimize")!

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceTokenHex: String?

    private let api: APIClient
    private let analytics: PushAnalytics
    private weak var router: CameraRouter?

    private let lastRegisteredTokenKey = "push.lastRegisteredToken"

    init(api: APIClient = .shared, analytics: PushAnalytics = .shared) {
        self.api = api
        self.analytics = analytics
        super.init()
    }

    func attach(router: CameraRouter) {
        self.router = router
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Flags

    var hasCompletedFirstAutoOptimize: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedFirstAutoOptimizeKey)
    }

    var didAskPushPermission: Bool {
        UserDefaults.standard.bool(forKey: Self.didAskPushPermissionKey)
    }

    /// Call after Auto Optimize reaches `.ready` successfully.
    func noteFirstSuccessfulAutoOptimize() {
        let defaults = UserDefaults.standard
        let wasFirst = !defaults.bool(forKey: Self.hasCompletedFirstAutoOptimizeKey)
        defaults.set(true, forKey: Self.hasCompletedFirstAutoOptimizeKey)
        if wasFirst {
            Task { await maybeAskPermissionAfterFirstOptimize() }
        }
    }

    // MARK: - Permission (not on install/launch)

    /// Ask only after first successful Auto Optimize, once per install (flag).
    func maybeAskPermissionAfterFirstOptimize() async {
        guard hasCompletedFirstAutoOptimize else { return }
        guard !didAskPushPermission else { return }

        await refreshAuthorizationStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        if authorizationStatus == .denied {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            return
        }

        analytics.track(.pushPermissionPromptShown)
        UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                analytics.track(.pushPermissionAccepted)
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                analytics.track(.pushPermissionDenied)
            }
        } catch {
            analytics.track(.pushPermissionDenied, properties: ["error": error.localizedDescription])
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token

    func didRegisterDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        Task { await registerTokenWithServer(hex) }
    }

    func didFailToRegister(error: Error) {
        #if DEBUG
        print("[Push] register failed: \(error.localizedDescription)")
        #endif
    }

    private func registerTokenWithServer(_ hex: String) async {
        if UserDefaults.standard.string(forKey: lastRegisteredTokenKey) == hex {
            return
        }
        do {
            try await api.registerPushToken(
                token: hex,
                environment: Self.apnsEnvironment,
                appVersion: Self.appVersion
            )
            UserDefaults.standard.set(hex, forKey: lastRegisteredTokenKey)
        } catch {
            // 404/503 fail soft — server may not ship Exp 1 yet.
            #if DEBUG
            print("[Push] register soft fail: \(error.localizedDescription)")
            #endif
        }
    }

    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        // Release / TestFlight / App Store → production APNs.
        // Override locally via UserDefaults if testing sandbox Release builds.
        if let override = UserDefaults.standard.string(forKey: "push.apnsEnvironment"),
           override == "sandbox" || override == "production" {
            return override
        }
        return "production"
        #endif
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Deep link / open

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "photo-recipes" else { return }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        if host == "auto-optimize" || path == "/auto-optimize" || host.isEmpty && path.contains("auto-optimize") {
            openAutoOptimize(fromPush: false)
        }
    }

    func openAutoOptimize(fromPush: Bool) {
        if fromPush {
            analytics.track(.pushOpened, properties: ["deepLink": "auto-optimize"])
            Analytics.shared.track("push_opened", props: ["deepLink": "auto-optimize"])
        }
        router?.openAutoOptimize()
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            Self.shared.openAutoOptimize(fromPush: true)
            completionHandler()
        }
    }
}

/// UIKit bridge for APNs device token callbacks.
final class PhotoRecipesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegisterDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegister(error: error)
        }
    }
}
