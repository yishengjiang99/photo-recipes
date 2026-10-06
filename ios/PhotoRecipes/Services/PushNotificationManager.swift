import Foundation
import UIKit
import UserNotifications

/// Experiment 1 APNs client: permission after first successful capture
/// (also after first successful Auto Optimize — whichever comes first),
/// token register, foreground/tap → deep link `photo-recipes://auto-optimize`.
/// Never request permission from onboarding / cold open.
///
/// Build 22: gate `registerForRemoteNotifications` until after
/// `application(_:didFinishLaunching:)` (and again on scene active).
/// Build 23: Release/Archive entitlements use `aps-environment=production`
/// (Debug keeps development). TF distribution + development entitlement caused
/// `didFailToRegister` → no device token → never `POST /api/push/register`.
/// Also: sync main-thread token callbacks + `apns_*` push/events observability.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    static let hasCompletedFirstAutoOptimizeKey = "hasCompletedFirstAutoOptimize"
    static let hasCompletedFirstCaptureKey = "hasCompletedFirstCapture"
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
    private var serverRegisterBackoffTask: Task<Void, Never>?
    /// Forces at least one /api/push/register attempt after a fresh Allow even if hex matches cache.
    private var forceRegisterAfterAllow = false
    /// Gate: AppDelegate didFinishLaunching / scene active must flip this before APNs register.
    private var appLaunchReady = false
    private var pendingRegisterReason: String?

    init(api: APIClient = .shared, analytics: PushAnalytics = .shared) {
        self.api = api
        self.analytics = analytics
        super.init()
    }

    func attach(router: CameraRouter) {
        self.router = router
    }

    /// Wire UNUserNotificationCenter only — do NOT request an APNs token here.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus(requestTokenIfAuthorized: false) }
    }

    /// Called from AppDelegate.didFinishLaunching and scenePhase.active.
    func noteAppLaunchReady(reason: String) {
        appLaunchReady = true
        let pending = pendingRegisterReason
        pendingRegisterReason = nil
        Task {
            await refreshAuthorizationStatus(requestTokenIfAuthorized: true)
            if let pending {
                await ensureRemoteNotificationRegistration(reason: pending)
            } else {
                await ensureRemoteNotificationRegistration(reason: reason)
            }
        }
    }

    // MARK: - Flags

    var hasCompletedFirstAutoOptimize: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedFirstAutoOptimizeKey)
    }

    var didAskPushPermission: Bool {
        UserDefaults.standard.bool(forKey: Self.didAskPushPermissionKey)
    }

    private var serverRegisterOk: Bool {
        UserDefaults.standard.bool(forKey: lastServerRegisterOkKey)
    }

    var hasCompletedFirstCapture: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedFirstCaptureKey)
    }

    /// Call after Auto Optimize reaches `.ready` successfully.
    /// Push may also be requested via `noteFirstSuccessfulCapture` (product: after first shutter).
    func noteFirstSuccessfulAutoOptimize() {
        let defaults = UserDefaults.standard
        let wasFirst = !defaults.bool(forKey: Self.hasCompletedFirstAutoOptimizeKey)
        defaults.set(true, forKey: Self.hasCompletedFirstAutoOptimizeKey)
        if wasFirst {
            Task { await maybeAskPushPermission(reason: "first_auto_optimize") }
        } else {
            // Later AOs: if Allow already happened but server never got a token, keep trying.
            Task { await ensureRemoteNotificationRegistration(reason: "post_ao_reregister") }
        }
    }

    /// Call after a successful shutter / `capturePhoto` return (Build 26+ product lock).
    /// Does not run during onboarding. Safe to call every capture — asks at most once.
    func noteFirstSuccessfulCapture() {
        let defaults = UserDefaults.standard
        let wasFirst = !defaults.bool(forKey: Self.hasCompletedFirstCaptureKey)
        defaults.set(true, forKey: Self.hasCompletedFirstCaptureKey)
        if wasFirst {
            Task { await maybeAskPushPermission(reason: "first_capture") }
        } else {
            Task { await ensureRemoteNotificationRegistration(reason: "post_capture_reregister") }
        }
    }

    // MARK: - Permission (not on install/launch / onboarding)

    /// Ask only after first successful capture (or AO), once per install (flag).
    func maybeAskPermissionAfterFirstOptimize() async {
        await maybeAskPushPermission(reason: "legacy_ao_entry")
    }

    /// Shared gate: never prompts on cold open / onboarding.
    func maybeAskPushPermission(reason: String) async {
        guard hasCompletedFirstCapture || hasCompletedFirstAutoOptimize else { return }
        guard !didAskPushPermission else {
            await ensureRemoteNotificationRegistration(reason: "reask_gate")
            return
        }

        print("[Push] maybeAskPushPermission reason=\(reason)")
        await refreshAuthorizationStatus(requestTokenIfAuthorized: false)
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            forceRegisterAfterAllow = true
            syncPushOptIn(true)
            scheduleEngagementLocalNotifications()
            requestAPNsDeviceToken(reason: "already_authorized")
            return
        }
        if authorizationStatus == .denied {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            syncPushOptIn(false)
            return
        }

        analytics.track(.pushPermissionPromptShown)
        // Mark asked only after we present the system dialog (not before).
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            await refreshAuthorizationStatus(requestTokenIfAuthorized: false)
            if granted {
                analytics.track(.pushPermissionAccepted)
                forceRegisterAfterAllow = true
                syncPushOptIn(true)
                scheduleEngagementLocalNotifications()
                // Critical path: Allow → APNs token → POST /api/push/register.
                requestAPNsDeviceToken(reason: "permission_accepted")
            } else {
                analytics.track(.pushPermissionDenied)
                syncPushOptIn(false)
            }
        } catch {
            UserDefaults.standard.set(true, forKey: Self.didAskPushPermissionKey)
            analytics.track(.pushPermissionDenied, properties: ["error": error.localizedDescription])
        }
    }

    func refreshAuthorizationStatus(requestTokenIfAuthorized: Bool = true) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard requestTokenIfAuthorized else { return }
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
        if !serverRegisterOk { forceRegisterAfterAllow = true }
        requestAPNsDeviceToken(reason: reason)
    }

    /// Step 1 after Allow / cold start: ask iOS for an APNs device token.
    private func requestAPNsDeviceToken(reason: String) {
        guard appLaunchReady else {
            print("[Push] defer registerForRemoteNotifications reason=\(reason) (launch not ready)")
            pendingRegisterReason = reason
            return
        }
        print("[Push] registerForRemoteNotifications reason=\(reason)")
        let app = UIApplication.shared
        let fire = { app.registerForRemoteNotifications() }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
        // Retry with backoff — first call after Allow can race; early calls can miss the callback.
        registerRetryTask?.cancel()
        registerRetryTask = Task { @MainActor in
            for delayNs in [500_000_000, 2_000_000_000, 5_000_000_000, 15_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if self.deviceTokenHex != nil, self.serverRegisterOk, !self.forceRegisterAfterAllow {
                    return
                }
                print("[Push] retry registerForRemoteNotifications after \(delayNs)ns reason=\(reason)")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Token

    func didRegisterDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        print("[Push] didRegisterDeviceToken len=\(hex.count) env=\(Self.apnsEnvironment)")
        analytics.track(
            .apnsTokenReceived,
            properties: [
                "tokenLen": "\(hex.count)",
                "environment": Self.apnsEnvironment,
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            ]
        )
        Task { await registerTokenWithServer(hex) }
    }

    func didFailToRegister(error: Error) {
        let msg = error.localizedDescription
        print("[Push] didFailToRegister: \(msg)")
        analytics.track(
            .apnsRegisterFailed,
            properties: [
                "error": String(msg.prefix(200)),
                "environment": Self.apnsEnvironment,
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            ]
        )
        // Retries continue via requestAPNsDeviceToken's scheduled loop.
    }

    private func registerTokenWithServer(_ hex: String) async {
        let defaults = UserDefaults.standard
        let prior = defaults.string(forKey: lastRegisteredTokenKey)
        let serverOk = defaults.bool(forKey: lastServerRegisterOkKey)
        if prior == hex, serverOk, !forceRegisterAfterAllow {
            print("[Push] skip /api/push/register (cached ok)")
            return
        }
        print("[Push] POST /api/push/register env=\(Self.apnsEnvironment) len=\(hex.count)")
        do {
            try await api.registerPushToken(
                token: hex,
                environment: Self.apnsEnvironment,
                appVersion: Self.appVersion
            )
            defaults.set(hex, forKey: lastRegisteredTokenKey)
            defaults.set(true, forKey: lastServerRegisterOkKey)
            forceRegisterAfterAllow = false
            print("[Push] /api/push/register ok env=\(Self.apnsEnvironment)")
            syncPushOptIn(true)
            scheduleEngagementLocalNotifications()
        } catch {
            defaults.set(false, forKey: lastServerRegisterOkKey)
            print("[Push] /api/push/register fail: \(error.localizedDescription)")
            scheduleServerRegisterBackoff(hex: hex)
        }
    }

    private func scheduleServerRegisterBackoff(hex: String) {
        serverRegisterBackoffTask?.cancel()
        serverRegisterBackoffTask = Task { @MainActor in
            for delayNs in [1_500_000_000, 5_000_000_000, 15_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if UserDefaults.standard.bool(forKey: lastServerRegisterOkKey),
                   UserDefaults.standard.string(forKey: lastRegisteredTokenKey) == hex,
                   !forceRegisterAfterAllow {
                    return
                }
                print("[Push] /api/push/register backoff retry after \(delayNs)ns")
                do {
                    try await api.registerPushToken(
                        token: hex,
                        environment: Self.apnsEnvironment,
                        appVersion: Self.appVersion
                    )
                    UserDefaults.standard.set(hex, forKey: lastRegisteredTokenKey)
                    UserDefaults.standard.set(true, forKey: lastServerRegisterOkKey)
                    forceRegisterAfterAllow = false
                    print("[Push] /api/push/register ok (backoff) env=\(Self.apnsEnvironment)")
                    syncPushOptIn(true)
                    scheduleEngagementLocalNotifications()
                    return
                } catch {
                    print("[Push] /api/push/register backoff fail: \(error.localizedDescription)")
                }
            }
            requestAPNsDeviceToken(reason: "register_backoff_exhausted")
        }
    }

    /// Mirror opt-in to server prefs (token register alone does not set pushOptIn).
    private func syncPushOptIn(_ optedIn: Bool) {
        Task {
            do {
                var prefs = APIClient.PushPrefs()
                prefs.pushOptIn = optedIn
                prefs.timezone = TimeZone.current.identifier
                _ = try await api.updatePushPrefs(prefs)
                print("[Push] prefs pushOptIn=\(optedIn) ok")
            } catch {
                print("[Push] prefs pushOptIn=\(optedIn) fail: \(error.localizedDescription)")
            }
        }
    }

    /// Build 25: Release / Archive / TestFlight → `production`; Debug → `sandbox`.
    /// Do NOT use `sandboxReceipt` as APNs env — TF installs have a sandbox *receipt*
    /// but talk to the **production** APNs host (CoS E2E: build 23 registered sandbox wrongly).
    static var apnsEnvironment: String {
        if let override = UserDefaults.standard.string(forKey: "push.apnsEnvironment"),
           override == "sandbox" || override == "production" {
            return override
        }
        #if DEBUG
        return "sandbox"
        #else
        // Release config, App Store, and TestFlight (incl. sandboxReceipt) → production.
        return "production"
        #endif
    }

    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Local engagement (D1 / come-shoot)
    // Works without server cron. Remote come-shoot still runs when tick fires.

    private static let localD1Id = "protune.local.d1_return"
    private static let localGoldenId = "protune.local.golden_hour"
    private static let didScheduleLocalsKey = "push.didScheduleEngagementLocals"

    /// Schedule D1 evening + daily golden-hour locals after Allow.
    /// Idempotent: replaces pending requests with the same ids.
    func scheduleEngagementLocalNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            Task { @MainActor in
                await self.installEngagementLocals(center: center)
            }
        }
    }

    private func installEngagementLocals(center: UNUserNotificationCenter) async {
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.localD1Id,
            Self.localGoldenId,
        ])

        // D1: tomorrow at 18:00 local — "Come shoot tonight"
        var d1 = DateComponents()
        d1.hour = 18
        d1.minute = 0
        let d1Content = UNMutableNotificationContent()
        d1Content.title = "Come shoot tonight"
        d1Content.body = "Golden light is waiting — open ProTune and tap Auto Optimize."
        d1Content.sound = .default
        d1Content.userInfo = [
            "type": "d1_return",
            "deepLink": "photo-recipes://auto-optimize",
        ]
        // Fire once ~24–36h out: next 18:00 if >12h away, else day after.
        let cal = Calendar.current
        let now = Date()
        var fire = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        if fire.timeIntervalSince(now) < 12 * 3600 {
            fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
        }
        let d1Trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(identifier: Self.localD1Id, content: d1Content, trigger: d1Trigger))

        // Daily golden-hour soft nudge at 17:30 (user can clear in Settings).
        var gh = DateComponents()
        gh.hour = 17
        gh.minute = 30
        let ghContent = UNMutableNotificationContent()
        ghContent.title = "Golden hour"
        ghContent.body = "Light is soft right now — open the camera and Auto Optimize a frame."
        ghContent.sound = .default
        ghContent.userInfo = [
            "type": "come_shoot_nudge",
            "deepLink": "photo-recipes://auto-optimize",
        ]
        let ghTrigger = UNCalendarNotificationTrigger(dateMatching: gh, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: Self.localGoldenId, content: ghContent, trigger: ghTrigger))

        UserDefaults.standard.set(true, forKey: Self.didScheduleLocalsKey)
        print("[Push] scheduled local D1 + golden-hour engagement")
        Analytics.shared.track("push_local_scheduled", props: [
            "d1": "1",
            "golden": "1",
        ])
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
        // Mark launch ready BEFORE any deferred registerForRemoteNotifications runs.
        // Sync on main — UIApplicationDelegate is already main-thread.
        MainActor.assumeIsolated {
            PushNotificationManager.shared.noteAppLaunchReady(reason: "did_finish_launching")
            // SKAN install registration + AppsFlyer (only if this build has a dev key).
            Attribution.shared.configure()
            MetaEvents.configure(application: application, launchOptions: launchOptions)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Synchronous on main — avoid Task { @MainActor } race that can drop the token.
        MainActor.assumeIsolated {
            PushNotificationManager.shared.didRegisterDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MainActor.assumeIsolated {
            PushNotificationManager.shared.didFailToRegister(error: error)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        MainActor.assumeIsolated {
            PushNotificationManager.shared.noteAppLaunchReady(reason: "become_active")
            MetaEvents.activateApp()
            MetaEvents.requestTrackingIfNeeded()
        }
    }
}
