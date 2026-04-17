import SwiftUI

@main
struct LuxSwitchApp: App {

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(themeManager)
                .environmentObject(updateManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                if let text = themeManager.menuBarText {
                    Text(text)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
