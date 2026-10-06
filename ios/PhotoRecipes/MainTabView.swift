import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var router: CameraRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(CameraRouter.Tab.camera)
                // Viewfinder-first: full-bleed preview; destinations live under Camera ···
                .toolbar(.hidden, for: .tabBar)

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(CameraRouter.Tab.library)
                .toolbar(.visible, for: .tabBar)

            AskGrokView()
                .tabItem { Label("Coach", systemImage: "text.bubble.fill") }
                .tag(CameraRouter.Tab.ask)
                .toolbar(.visible, for: .tabBar)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(CameraRouter.Tab.settings)
                .toolbar(.visible, for: .tabBar)
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.bg, for: .tabBar)
        // Observe EntitlementsStore directly — App-level Binding on appModel did not refresh.
        .sheet(isPresented: $entitlements.showPaywall) {
            PaywallView()
                .environmentObject(entitlements)
                .environmentObject(storeKit)
                .environmentObject(api)
                // Soft (post-success) sheet opens at half height so the optimized
                // viewfinder stays visible behind it; hard gate is full height.
                .presentationDetents(entitlements.paywallMode == .soft ? [.medium, .large] : [.large])
        }
    }
}
