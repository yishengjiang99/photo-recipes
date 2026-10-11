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
    /// token|environment|appVersion|anonId of the last successful /api/push/register.
    static let lastRegisterFingerprintKey = "push.lastRegisterFingerprint"
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
        cancelD1IfUserReturned()
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

    /// True only when the last successful register was for this app version + install ID
    /// (an app update keeps the APNs token, so token equality alone is not enough).
    private var serverRegisterOk: Bool {
        guard UserDefaults.standard.bool(forKey: lastServerRegisterOkKey),
              let last = UserDefaults.standard.string(forKey: Self.lastRegisterFingerprintKey)
        else { return false }
        return Self.fingerprintMatchesContext(
            last, environment: Self.apnsEnvironment, appVersion: Self.appVersion, anonId: Analytics.shared.anonId)
    }

    nonisolated static func registerFingerprint(
        token: String, environment: String, appVersion: String, anonId: String
    ) -> String {
        [token, environment, appVersion, anonId].joined(separator: "|")
    }

    nonisolated static func fingerprintMatchesContext(
        _ fingerprint: String, environment: String, appVersion: String, anonId: String
    ) -> Bool {
        let parts = fingerprint.components(separatedBy: "|")
        return parts.count == 4 && parts[1] == environment && parts[2] == appVersion && parts[3] == anonId
    }

    /// Upload unless the exact same token + environment + version + install ID already succeeded.
    /// Before 1.5 (77) the cache keyed on the token only, so an update from 1.4 never re-registered
    /// and the server never linked the 1.5 install ID to the token.
    nonisolated static func shouldUploadToken(
        current: String, lastFingerprint: String?, lastOk: Bool, force: Bool
    ) -> Bool {
        force || !lastOk || lastFingerprint != current
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
        // Funnel proposal: no system prompt here — the reminder is *offered* after the first
        // saved optimized photo (PostSaveCard → requestReminderPermission).
        // If Allow already happened but server never got a token, keep trying.
        Task { await ensureRemoteNotificationRegistration(reason: wasFirst ? "first_ao_reregister" : "post_ao_reregister") }
    }

    /// Call after a successful shutter / `capturePhoto` return (Build 26+ product lock).
    /// Does not run during onboarding. Safe to call every capture — asks at most once.
    func noteFirstSuccessfulCapture() {
        let defaults = UserDefaults.standard
        let wasFirst = !defaults.bool(forKey: Self.hasCompletedFirstCaptureKey)
        defaults.set(true, forKey: Self.hasCompletedFirstCaptureKey)
        Task { await ensureRemoteNotificationRegistration(reason: wasFirst ? "first_capture_reregister" : "post_capture_reregister") }
    }

    // MARK: - Permission (not on install/launch / onboarding)

    /// User tapped "Remind me tomorrow" after a saved optimized photo — the only place
    /// the system notification prompt is shown (ask after value, with a concrete benefit).
    func requestReminderPermission(source: String) async {
        Analytics.shared.track("reminder_offer_accept", props: ["source": source])
        await maybeAskPushPermission(reason: source)
    }

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
        let fingerprint = Self.registerFingerprint(
            token: hex, environment: Self.apnsEnvironment, appVersion: Self.appVersion, anonId: Analytics.shared.anonId)
        if !Self.shouldUploadToken(
            current: fingerprint,
            lastFingerprint: defaults.string(forKey: Self.lastRegisterFingerprintKey),
            lastOk: defaults.bool(forKey: lastServerRegisterOkKey),
            force: forceRegisterAfterAllow
        ) {
            print("[Push] skip /api/push/register (same token, version and install ID)")
            return
        }
        print("[Push] POST /api/push/register env=\(Self.apnsEnvironment) len=\(hex.count)")
        do {
            try await api.registerPushToken(
                token: hex,
                environment: Self.apnsEnvironment,
                appVersion: Self.appVersion,
                timezone: TimeZone.current.identifier,
                anonId: Analytics.shared.anonId
            )
            defaults.set(hex, forKey: lastRegisteredTokenKey)
            defaults.set(fingerprint, forKey: Self.lastRegisterFingerprintKey)
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
                let fingerprint = Self.registerFingerprint(
                    token: hex, environment: Self.apnsEnvironment, appVersion: Self.appVersion,
                    anonId: Analytics.shared.anonId)
                if !Self.shouldUploadToken(
                    current: fingerprint,
                    lastFingerprint: UserDefaults.standard.string(forKey: Self.lastRegisterFingerprintKey),
                    lastOk: UserDefaults.standard.bool(forKey: lastServerRegisterOkKey),
                    force: forceRegisterAfterAllow
                ) {
                    return
                }
                print("[Push] /api/push/register backoff retry after \(delayNs)ns")
                do {
                    try await api.registerPushToken(
                        token: hex,
                        environment: Self.apnsEnvironment,
                        appVersion: Self.appVersion,
                        timezone: TimeZone.current.identifier,
                        anonId: Analytics.shared.anonId
                    )
                    UserDefaults.standard.set(hex, forKey: lastRegisteredTokenKey)
                    UserDefaults.standard.set(fingerprint, forKey: Self.lastRegisterFingerprintKey)
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
                // Device is the source of truth for promotional consent (Settings toggle).
                prefs.marketingOptIn = Self.marketingOptIn
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

    // MARK: - Promotional consent (Guideline 4.5.4)

    static let marketingOptInKey = "push.marketingOptIn"

    /// Explicit in-app opt-in for promotional pushes (re-engagement, offers, feature news).
    /// Off by default. Feature pushes (tips about something you started) only need permission.
    static var marketingOptIn: Bool {
        UserDefaults.standard.bool(forKey: marketingOptInKey)
    }

    /// Settings → Notifications → "Tips & offers". Mirrors to the server (soft-fail; re-synced
    /// on every token registration so the server can never hold a stale "yes").
    func setMarketingOptIn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.marketingOptInKey)
        analytics.track(on ? .marketingOptIn : .marketingOptOut, properties: ["source": "settings"])
        Analytics.shared.track(on ? "push_marketing_opt_in" : "push_marketing_opt_out", props: ["source": "settings"])
        Task {
            var prefs = APIClient.PushPrefs()
            prefs.marketingOptIn = on
            prefs.timezone = TimeZone.current.identifier
            _ = try? await api.updatePushPrefs(prefs)
        }
    }

    // MARK: - Local engagement (D1 / come-shoot)
    // Works without server cron. Remote come-shoot still runs when tick fires.

    private static let localD1Id = "protune.local.d1_return"
    private static let localGoldenId = "protune.local.golden_hour"
    private static let didScheduleLocalsKey = "push.didScheduleEngagementLocals"
    /// D1 reminder is sent once per install; this records when it was scheduled.
    private static let localD1ScheduledAtKey = "push.localD1ScheduledAt"
    private static let localD1EverScheduledKey = "push.localD1EverScheduled"

    /// Schedule D1 evening + daily golden-hour locals after Allow.
    /// Idempotent: replaces pending requests with the same ids. D1 is scheduled once per install.
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
        let defaults = UserDefaults.standard
        center.removePendingNotificationRequests(withIdentifiers: [Self.localGoldenId])

        let cal = Calendar.current
        let now = Date()
        var scheduledD1 = false
        if !defaults.bool(forKey: Self.localD1EverScheduledKey) {
            center.removePendingNotificationRequests(withIdentifiers: [Self.localD1Id])
            // D1: one useful prompt, deep-linked to Camera (no golden-light promise).
            let d1Content = UNMutableNotificationContent()
            d1Content.title = "Ready for another quick polish?"
            d1Content.body = "Open Camera and get an optimized result in one tap."
            d1Content.sound = .default
            d1Content.userInfo = [
                "type": "d1_return",
                "deepLink": "photo-recipes://auto-optimize",
            ]
            // Fire once ~24–36h out: next 18:00 if >12h away, else day after.
            var fire = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            if fire.timeIntervalSince(now) < 12 * 3600 {
                fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
            }
            let d1Trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            do {
                try await center.add(UNNotificationRequest(identifier: Self.localD1Id, content: d1Content, trigger: d1Trigger))
                defaults.set(true, forKey: Self.localD1EverScheduledKey)
                defaults.set(now, forKey: Self.localD1ScheduledAtKey)
                scheduledD1 = true
                let hours = Int(fire.timeIntervalSince(now) / 3600)
                Analytics.shared.track("notification_scheduled", props: [
                    "campaign_id": "d1_return",
                    "delay_bucket": hours < 24 ? "12-24h" : "24-36h",
                    "delay_hours": "\(hours)",
                ])
            } catch {
                print("[Push] D1 local schedule failed: \(error.localizedDescription)")
            }
        }

        // Weekly (Saturday) golden-hour soft nudge at 17:30. Was daily; the lifecycle caps
        // (≤1/day, ≤3/week across all pushes — docs/push-lifecycle.md) rule out a daily repeat.
        var gh = DateComponents()
        gh.weekday = 7
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

        let firstGolden = !defaults.bool(forKey: Self.didScheduleLocalsKey)
        defaults.set(true, forKey: Self.didScheduleLocalsKey)
        print("[Push] scheduled local engagement d1=\(scheduledD1) golden=1")
        if firstGolden {
            Analytics.shared.track("notification_scheduled", props: [
                "campaign_id": "golden_hour_weekly",
                "delay_bucket": "sat_1730",
            ])
        }
        Analytics.shared.track("push_local_scheduled", props: [
            "d1": scheduledD1 ? "1" : "0",
            "golden": "1",
        ])
    }

    /// "Cancel if the user returns first": the app came back to the foreground ≥3h after the
    /// D1 reminder was scheduled and before it fired → drop it (once-per-install, not re-armed).
    func cancelD1IfUserReturned() {
        let defaults = UserDefaults.standard
        guard let at = defaults.object(forKey: Self.localD1ScheduledAtKey) as? Date else { return }
        guard Date().timeIntervalSince(at) >= 3 * 3600 else { return }
        defaults.removeObject(forKey: Self.localD1ScheduledAtKey)
        let id = Self.localD1Id
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            guard requests.contains(where: { $0.identifier == id }) else { return }
            center.removePendingNotificationRequests(withIdentifiers: [id])
            Task { @MainActor in
                Analytics.shared.track("notification_cancelled", props: [
                    "campaign_id": "d1_return",
                    "reason": "user_returned",
                ])
            }
        }
    }

    // MARK: - Deep link / open

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "photo-recipes" else { return }
        route(Self.destination(for: url))
    }

    /// Deep-link destinations a push (or URL) may open. Unknown → camera.
    enum Destination: String, Equatable {
        case autoOptimize = "auto-optimize"
        case camera
        case recipes
        case paywall
    }

    /// `photo-recipes://<host>` or `photo-recipes:///<path>` → destination (pure, unit-tested).
    nonisolated static func destination(for url: URL?) -> Destination {
        guard let url, url.scheme == "photo-recipes" else { return .autoOptimize }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = host.isEmpty ? path : host
        if key.contains("auto-optimize") { return .autoOptimize }
        return Destination(rawValue: key) ?? .camera
    }

    private func route(_ dest: Destination) {
        switch dest {
        case .autoOptimize: router?.openAutoOptimize()
        case .camera: router?.openCamera()
        case .recipes: router?.openLibrary()
        case .paywall: router?.openPaywall()
        }
    }

    /// Tap on a remote/local notification: open tracking (send id + campaign) then deep link.
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let campaign = (userInfo["segment"] as? String) ?? (userInfo["type"] as? String) ?? "unknown"
        let sendId = userInfo["sendId"] as? String
        let link = (userInfo["deepLink"] as? String).flatMap(URL.init(string:))
        let dest = Self.destination(for: link)
        var props: [String: String] = ["campaign_id": campaign, "deepLink": dest.rawValue]
        if let sendId, sendId.count <= 64 { props["send_id"] = sendId }
        Analytics.shared.track("notification_opened", props: props)
        Analytics.shared.track("push_opened", props: props)
        var pushProps: [String: String] = ["deepLink": dest.rawValue, "campaign": campaign]
        if let sendId, sendId.count <= 64 { pushProps["sendId"] = sendId }
        analytics.track(.pushOpened, properties: pushProps)
        route(dest)
    }

    func openAutoOptimize(fromPush: Bool, campaign: String? = nil) {
        if fromPush {
            Analytics.shared.track("notification_opened", props: [
                "campaign_id": campaign ?? "unknown",
            ])
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
        let userInfo = response.notification.request.content.userInfo
        // Only plain property-list values cross the actor hop.
        var info: [String: String] = [:]
        for key in ["type", "segment", "sendId", "deepLink"] {
            if let v = userInfo[key] as? String { info[key] = v }
        }
        Task { @MainActor in
            Self.shared.handleNotificationTap(userInfo: info)
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
            // SKAN install registration (Meta App Events configure follows).
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
