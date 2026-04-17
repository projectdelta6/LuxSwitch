# LuxSwitch

A lightweight macOS menu bar app that automatically switches between light and dark mode based on ambient light.

LuxSwitch reads your Mac's ambient light sensor and toggles the system appearance when the light level crosses a configurable threshold — so your display adapts to your environment without you touching a thing.

## Features

- **Automatic theme switching** based on ambient light (lux) readings
- **Configurable threshold and hysteresis** to prevent rapid toggling near the boundary
- **Adjustable polling interval** to balance responsiveness and efficiency
- **Preferred default theme** — restored when auto-switch is disabled or the app quits
- **Menu bar only** — no Dock icon, runs quietly in the background
- Displays current lux reading and mode (sun/moon icon) in the menu bar

## Requirements

- macOS 13.0+
- A Mac with an ambient light sensor (MacBooks, some iMacs)
- **Automation permission** — LuxSwitch uses AppleScript to toggle System Events appearance preferences. On first launch, macOS will prompt you to grant access in **System Settings > Privacy & Security > Automation**.

## How It Works

1. Polls the ambient light sensor at a configurable interval (default: 30 seconds)
2. Compares the lux reading against a threshold with hysteresis:
   - Switches to **light mode** when lux rises above `threshold + hysteresis`
   - Switches to **dark mode** when lux drops below `threshold - hysteresis`
3. On quit or disable, restores your preferred default theme

## Configuration

All settings are accessible from the menu bar popover:

| Setting | Default | Description |
|---|---|---|
| Threshold | 50,000 lux | The midpoint for light/dark switching |
| Hysteresis | 20,000 lux | Buffer zone above and below the threshold to prevent flickering |
| Poll Interval | 30 sec | How often the sensor is read |
| Default Theme | System current | Theme restored when auto-switch is off or the app quits |

## Building

Open `LuxSwitch.xcodeproj` in Xcode and build/run. The app uses SwiftUI with `MenuBarExtra` and requires no external dependencies.

### App Icon

The app icon is generated programmatically via a Python script:

```bash
pip install Pillow
python generate_icon.py
```

This produces all required icon sizes in the asset catalog.

## License

MIT
