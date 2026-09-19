import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }

            AskGrokView()
                .tabItem {
                    Label("Coach", systemImage: "text.bubble.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.bg, for: .tabBar)
    }
}
