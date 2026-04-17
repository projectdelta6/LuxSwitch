import SwiftUI

@main
struct LuxSwitchApp: App {

    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(themeManager)
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
