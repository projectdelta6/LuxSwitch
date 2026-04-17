# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LuxSwitch is a macOS menu bar app (SwiftUI) that automatically switches between light and dark mode based on ambient light sensor readings. It runs as a background-only app (`LSUIElement = true`) with no Dock icon.

## Build

Open `LuxSwitch.xcodeproj` in Xcode and build/run. There are no external dependencies — the project uses only system frameworks (SwiftUI, AppKit, Combine, IOKit).

- **Target:** macOS 14.0+ (Sonoma)
- **Swift version:** 5.0
- **Bundle ID:** `com.projectdelta6.LuxSwitch`
- **No tests, linting, or CI** are configured

### App Icon Generation

```bash
pip install Pillow
python generate_icon.py
```

Generates all icon sizes into `LuxSwitch/Assets.xcassets/AppIcon.appiconset/`.

## Architecture

The app is four files with a simple unidirectional flow:

- **`LuxSwitchApp.swift`** — Entry point. Creates a `MenuBarExtra` with a window-style popover. The menu bar icon reflects current mode (sun/moon).
- **`ThemeManager.swift`** — Central `ObservableObject` managing all state. Polls the sensor on a timer, evaluates threshold with hysteresis, toggles system appearance via AppleScript (`NSAppleScript`), persists settings to `UserDefaults`, and restores the user's preferred theme on quit/disable.
- **`AmbientLightSensor.swift`** — Static IOKit HID wrapper that reads the ambient light sensor value in lux. Stateless — just call `AmbientLightSensor.readLux()`.
- **`MenuBarView.swift`** — SwiftUI popover UI. Displays status, permission warnings, and settings controls. Binds to `ThemeManager` via `@EnvironmentObject`.

### Key Design Details

- **System appearance toggling** uses AppleScript via `NSAppleScript` to control System Events, which requires Automation permission. The app detects denial (error -1743) and shows a permission prompt.
- **Hysteresis** prevents rapid toggling: dark mode activates below `threshold - hysteresis`, light mode above `threshold + hysteresis`. Values between are a dead zone.
- **On quit**, the app restores the user's preferred default theme rather than leaving whatever the sensor last set.
