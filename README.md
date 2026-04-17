# LuxSwitch

A lightweight macOS menu bar app that automatically switches between light and dark mode based on ambient light.

LuxSwitch reads your Mac's ambient light sensor and toggles the system appearance when the light level crosses a configurable threshold — so your display adapts to your environment without you touching a thing.

## Features

- **Automatic theme switching** based on ambient light (lux) readings
- **Configurable threshold and hysteresis** to prevent rapid toggling near the boundary
- **Transition delay** — waits before switching to avoid brief light changes (e.g. clouds, walking past a window)
- **Dark mode schedule** — force dark mode during set hours regardless of ambient light
- **Show lux in menu bar** — optional numeric lux display next to the sun/moon icon
- **Launch at login** — start automatically when you log in
- **Preferred default theme** — restored when auto-switch is disabled or the app quits
- **Clamshell mode aware** — automatically pauses auto-switching when the lid is closed
- **Menu bar only** — no Dock icon, runs quietly in the background

## Requirements

- macOS 14.0+ (Sonoma)
- A Mac with an ambient light sensor (MacBooks, some iMacs)

## How It Works

1. Polls the ambient light sensor at a configurable interval (default: 30 seconds)
2. Compares the lux reading against a threshold with hysteresis:
   - Switches to **light mode** when lux rises above `threshold + hysteresis`
   - Switches to **dark mode** when lux drops below `threshold - hysteresis`
3. Waits for the transition delay (default: 5 seconds) before applying the switch
4. If a dark mode schedule is active, forces dark mode during those hours
5. If the lid is closed (clamshell mode), pauses auto-switching until the sensor is available again
6. On quit or disable, restores your preferred default theme

## Configuration

All settings are accessible from the menu bar popover:

| Setting | Default | Description |
|---|---|---|
| Threshold | 112 lux | The midpoint for light/dark switching (auto-detected per sensor type) |
| Hysteresis | 10 lux | Buffer zone above and below the threshold to prevent flickering |
| Poll Interval | 30 sec | How often the sensor is read (0.5s–60s) |
| Transition Delay | 5 sec | How long to wait before switching, to ignore brief light changes (off–30s) |
| Dark Mode Schedule | Off | Force dark mode between set hours (default 22:00–07:00) |
| Show Lux in Menu Bar | Off | Display the current lux reading next to the menu bar icon |
| Launch at Login | Off | Start LuxSwitch automatically when you log in |
| Default Theme | System current | Theme restored when auto-switch is off or the app quits |

## Building from Source

Open `LuxSwitch.xcodeproj` in Xcode and build/run. The app uses SwiftUI with `MenuBarExtra` and requires no external dependencies.

### Release Build

```bash
./scripts/build-release.sh 1.0.0
```

This creates a universal binary (Intel + Apple Silicon), a `.pkg` installer, and a `.zip` archive in `build/release/output/`.

### App Icon

The app icon is generated programmatically via a Python script:

```bash
pip install Pillow
python generate_icon.py
```

## License

[MIT](LICENSE)
