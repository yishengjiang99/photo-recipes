import SwiftUI

/// Kept for Xcode preview / alternate entry; production uses PhotoRecipesApp → MainTabView.
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environmentObject(EntitlementsStore())
        .environmentObject(APIClient.shared)
        .environmentObject(StoreKitManager(entitlements: EntitlementsStore()))
        .preferredColorScheme(.dark)
}
