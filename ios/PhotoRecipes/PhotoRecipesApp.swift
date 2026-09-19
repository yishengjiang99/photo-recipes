import SwiftUI

@main
struct PhotoRecipesApp: App {
    @UIApplicationDelegateAdaptor(PhotoRecipesAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appModel.entitlements)
                .environmentObject(appModel.api)
                .environmentObject(appModel.storeKit)
                .environmentObject(appModel.cameraRouter)
                .environmentObject(appModel.push)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $appModel.entitlements.showPaywall) {
                    PaywallView()
                        .environmentObject(appModel.entitlements)
                        .environmentObject(appModel.storeKit)
                        .environmentObject(appModel.api)
                }
                .onOpenURL { url in
                    appModel.push.handleOpenURL(url)
                }
                .task {
                    await appModel.bootstrap()
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
        let ents = EntitlementsStore(api: APIClient.shared)
        self.entitlements = ents
        self.storeKit = StoreKitManager(api: APIClient.shared, entitlements: ents)
        push.attach(router: cameraRouter)
        push.configure()
        // Do NOT request notification permission here — only after first successful Auto Optimize.
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
