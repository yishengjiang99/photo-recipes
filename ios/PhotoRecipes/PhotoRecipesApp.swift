import SwiftUI

@main
struct PhotoRecipesApp: App {
    @UIApplicationDelegateAdaptor(PhotoRecipesAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnboardingStore.completedKey) private var hasCompletedOnboarding = false
    /// True when onboarding finished in this launch (ATT asks sooner than for returning users).
    @State private var finishedOnboardingThisLaunch = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        finishedOnboardingThisLaunch = true
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
            // App Tracking Transparency: only after onboarding, never on the first frame.
            // No-op when the build has no AppsFlyer dev key.
            .task(id: hasCompletedOnboarding) {
                guard hasCompletedOnboarding else { return }
                await Attribution.shared.requestTrackingAuthorizationAfter(
                    finishedOnboardingThisLaunch ? .seconds(1) : .seconds(3)
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    appModel.push.noteAppLaunchReady(reason: "scene_active")
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
