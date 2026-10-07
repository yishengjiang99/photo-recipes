import SwiftUI

@main
struct PhotoRecipesApp: App {
    @UIApplicationDelegateAdaptor(PhotoRecipesAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnboardingStore.completedKey) private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environmentObject(appModel.entitlements)
            .environmentObject(appModel.api)
            .environmentObject(appModel.storeKit)
            .environmentObject(appModel.cameraRouter)
            .environmentObject(appModel.push)
            .preferredColorScheme(.dark)
            // Paywall sheet is on MainTabView so it observes EntitlementsStore.
            .onOpenURL { url in
                appModel.push.handleOpenURL(url)
            }
            .task {
                await appModel.bootstrap()
            }
            // ATT: MetaEvents.requestTrackingIfNeeded on becomeActive (after onboarding).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    appModel.push.noteAppLaunchReady(reason: "scene_active")
                    // Backup ATT trigger: the AppDelegate's applicationDidBecomeActive
                    // may not fire reliably on iOS 27. The scenePhase is the
                    // SwiftUI-equivalent signal.
                    MetaEvents.requestTrackingIfNeeded()
                }
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let api = APIClient.shared
    let entitlements: EntitlementsStore
    let storeKit: StoreKitManager
    let cameraRouter = CameraRouter()
    let push = PushNotificationManager.shared

    init() {
        // Before Analytics mints an anon id: installs that already have one (or finished
        // onboarding) predate the welcome window and keep the standard daily pool.
        let d = UserDefaults.standard
        FreeOptimizeQuota().ensureInstallDate(
            existingUser: d.string(forKey: "telemetry.anonId") != nil
                || d.bool(forKey: OnboardingStore.completedKey)
        )
        Analytics.shared.bootstrap()
        let ents = EntitlementsStore(api: APIClient.shared)
        self.entitlements = ents
        self.storeKit = StoreKitManager(api: APIClient.shared, entitlements: ents)
        push.attach(router: cameraRouter)
        push.configure()
        // Do NOT request notification permission here — only after first successful capture
        // (and legacy first Auto Optimize). Never from onboarding / cold open.
    }

    func bootstrap() async {
        async let entitlementsRefresh: () = entitlements.refresh()
        async let loadProducts: () = storeKit.loadProducts()
        async let refreshEntitlements: () = storeKit.refreshEntitlementsFromCurrentEntitlements()
        _ = await (entitlementsRefresh, loadProducts, refreshEntitlements)
        // If already authorized from a prior grant, re-register token (no prompt).
        await push.refreshAuthorizationStatus()
    }
}
