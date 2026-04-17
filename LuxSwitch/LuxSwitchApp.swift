import SwiftUI

@main
struct LuxSwitchApp: App {

    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(themeManager)
        } label: {
            Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
