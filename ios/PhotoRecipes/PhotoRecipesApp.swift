import SwiftUI

@main
struct PhotoRecipesApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appModel.entitlements)
                .environmentObject(appModel.api)
                .environmentObject(appModel.storeKit)
                .environmentObject(appModel.cameraRouter)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $appModel.entitlements.showPaywall) {
                    PaywallView()
                        .environmentObject(appModel.entitlements)
                        .environmentObject(appModel.storeKit)
                        .environmentObject(appModel.api)
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

    init() {
        let ents = EntitlementsStore(api: APIClient.shared)
        self.entitlements = ents
        self.storeKit = StoreKitManager(api: APIClient.shared, entitlements: ents)
    }

    func bootstrap() async {
        async let entitlementsRefresh: () = entitlements.refresh()
        async let loadProducts: () = storeKit.loadProducts()
        async let refreshEntitlements: () = storeKit.refreshEntitlementsFromCurrentEntitlements()
        _ = await (entitlementsRefresh, loadProducts, refreshEntitlements)
    }
}
