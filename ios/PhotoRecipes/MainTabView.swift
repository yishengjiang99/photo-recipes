import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
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
    }
}
