import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var router: CameraRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(CameraRouter.Tab.camera)

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(CameraRouter.Tab.library)

            AskGrokView()
                .tabItem { Label("Coach", systemImage: "text.bubble.fill") }
                .tag(CameraRouter.Tab.ask)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(CameraRouter.Tab.settings)
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.bg, for: .tabBar)
    }
}
