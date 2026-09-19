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
                    Label("Ask Grok", systemImage: "sparkles")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.background, for: .tabBar)
    }
}
