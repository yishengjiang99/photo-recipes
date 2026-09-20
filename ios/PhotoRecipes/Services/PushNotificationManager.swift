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
    private let lastServerRegisterOkKey = "push.lastServerRegisterOk"
    private var registerRetryTask: Task<Void, Never>?
    /// Forces at least one /api/push/register attempt after a fresh Allow even if hex matches cache.
    private var forceRegisterAfterAllow = false

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
        guard !didAskPushPermission else {
            // Already prompted once — if authorized, still ensure APNs token → server.
            await ensureRemoteNotificationRegistration(reason: "reask_gate")
            return
        }

        await refreshAuthorizationStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            forceRegisterAfterAllow = true
            requestAPNsDeviceToken(reason: "already_authorized")
            return
        }
        if authorizationStatus == .denied {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            return
        }

        analytics.track(.pushPermissionPromptShown)
        // Mark asked only after we present the system dialog (not before), so a crash
        // mid-prompt can still re-prompt once — but do not re-prompt after Deny/Allow.
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            await refreshAuthorizationStatus()
            if granted {
                analytics.track(.pushPermissionAccepted)
                // Critical path: Allow → request APNs device token → POST /api/push/register.
                forceRegisterAfterAllow = true
                requestAPNsDeviceToken(reason: "permission_accepted")
            } else {
                analytics.track(.pushPermissionDenied)
            }
        } catch {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            analytics.track(.pushPermissionDenied, properties: ["error": error.localizedDescription])
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            await ensureRemoteNotificationRegistration(reason: "refresh_status")
        }
    }

    /// If permission is already granted, (re)request the APNs token and register with the server.
    func ensureRemoteNotificationRegistration(reason: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }
        let serverOk = UserDefaults.standard.bool(forKey: lastServerRegisterOkKey)
        if !serverOk { forceRegisterAfterAllow = true }
        requestAPNsDeviceToken(reason: reason)
    }

    /// Step 1 after Allow: ask iOS for an APNs device token (AppDelegate callbacks deliver it).
    private func requestAPNsDeviceToken(reason: String) {
        #if DEBUG
        print("[Push] registerForRemoteNotifications reason=\(reason)")
        #endif
        // Must be on the main queue; UIApplication rejects otherwise.
        let app = UIApplication.shared
        if Thread.isMainThread {
            app.registerForRemoteNotifications()
        } else {
            DispatchQueue.main.async { app.registerForRemoteNotifications() }
        }
        // Retry a few times — first call after Allow can race before the system is ready.
        registerRetryTask?.cancel()
        registerRetryTask = Task { @MainActor in
            for delayNs in [500_000_000, 2_000_000_000, 5_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if deviceTokenHex != nil,
                   UserDefaults.standard.bool(forKey: lastServerRegisterOkKey),
                   !forceRegisterAfterAllow {
                    return
                }
                #if DEBUG
                print("[Push] retry registerForRemoteNotifications after \(delayNs)ns")
                #endif
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Token

    func didRegisterDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        #if DEBUG
        print("[Push] didRegisterDeviceToken len=\(hex.count)")
        #endif
        Task { await registerTokenWithServer(hex) }
    }

    func didFailToRegister(error: Error) {
        // Always surface — B20 era only logged in DEBUG so TF failures were invisible.
        print("[Push] didFailToRegister: \(error.localizedDescription)")
        // Keep retrying via requestAPNsDeviceToken's scheduled retries.
    }

    private func registerTokenWithServer(_ hex: String) async {
        let defaults = UserDefaults.standard
        let prior = defaults.string(forKey: lastRegisteredTokenKey)
        let serverOk = defaults.bool(forKey: lastServerRegisterOkKey)
        if prior == hex, serverOk, !forceRegisterAfterAllow {
            return
        }
        do {
            try await api.registerPushToken(
                token: hex,
                environment: Self.apnsEnvironment,
                appVersion: Self.appVersion
            )
            defaults.set(hex, forKey: lastRegisteredTokenKey)
            defaults.set(true, forKey: lastServerRegisterOkKey)
            forceRegisterAfterAllow = false
            #if DEBUG
            print("[Push] /api/push/register ok env=\(Self.apnsEnvironment)")
            #endif
        } catch {
            // Do not cache as OK — next launch / retry must hit the server again.
            defaults.set(false, forKey: lastServerRegisterOkKey)
            print("[Push] /api/push/register fail: \(error.localizedDescription)")
            // Soft-retry once after a short delay (network blip / cold start).
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await api.registerPushToken(
                    token: hex,
                    environment: Self.apnsEnvironment,
                    appVersion: Self.appVersion
                )
                defaults.set(hex, forKey: lastRegisteredTokenKey)
                defaults.set(true, forKey: lastServerRegisterOkKey)
                forceRegisterAfterAllow = false
            } catch {
                print("[Push] /api/push/register retry fail: \(error.localizedDescription)")
            }
        }
    }

    /// TestFlight + DEBUG → sandbox; App Store → production.
    /// TF installs use `sandboxReceipt`; CoS contract registers them as sandbox.
    static var apnsEnvironment: String {
        if let override = UserDefaults.standard.string(forKey: "push.apnsEnvironment"),
           override == "sandbox" || override == "production" {
            return override
        }
        #if DEBUG
        return "sandbox"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "sandbox"
        }
        return "production"
        #endif
    }

    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Ensure delegate callbacks (including APNs token) are wired under SwiftUI.
        return true
    }

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

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            await PushNotificationManager.shared.ensureRemoteNotificationRegistration(reason: "become_active")
        }
    }
}
