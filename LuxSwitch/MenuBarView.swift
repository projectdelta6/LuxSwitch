import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var themeManager: ThemeManager

    private static let minHeight: CGFloat = 200
    private static let maxHeight: CGFloat = 600
    private static let defaultHeight: CGFloat = 420

    @AppStorage("panelHeight") private var panelHeight: Double = Self.defaultHeight
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            HStack {
                Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(themeManager.isDarkMode ? .blue : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(themeManager.isDarkMode ? "Dark Mode" : "Light Mode")
                        .font(.headline)

                    if themeManager.isEnabled {
                        if let lux = themeManager.currentLux {
                            Text("\(lux) lux")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else if !themeManager.sensorAvailable {
                            Text("No ambient light sensor detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Reading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: $themeManager.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(themeManager.automationPermission == .denied)
            }
            .padding()

            if themeManager.automationPermission == .denied {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Permission required to change system appearance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Open System Settings") {
                            themeManager.openAutomationSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Retry") {
                            themeManager.retryPermissionCheck()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Settings (scrollable)
            ScrollView {
                Form {
                    Section("Default Theme") {
                        Picker("When auto-switch is off", selection: $themeManager.preferredDarkMode) {
                            Text("Light").tag(false)
                            Text("Dark").tag(true)
                        }

                        Text("Restored when you disable auto-switch or quit the app.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section("Thresholds") {
                        HStack {
                            Text("Threshold")
                            Spacer()
                            TextField("", value: $themeManager.threshold, format: .number)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                            Text("lux")
                        }

                        HStack {
                            Text("Hysteresis")
                            Spacer()
                            TextField("", value: $themeManager.hysteresis, format: .number)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                            Text("lux")
                        }

                        let lower = max(0, themeManager.threshold - themeManager.hysteresis)
                        let upper = themeManager.threshold + themeManager.hysteresis
                        Text("Dark below \(lower) lux, light above \(upper) lux.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section("Polling") {
                        Picker("Poll Interval", selection: $themeManager.pollInterval) {
                            Text("0.5 sec").tag(0.5)
                            Text("1 sec").tag(1.0)
                            Text("2 sec").tag(2.0)
                            Text("5 sec").tag(5.0)
                            Text("10 sec").tag(10.0)
                            Text("30 sec").tag(30.0)
                            Text("60 sec").tag(60.0)
                        }

                        Picker("Transition Delay", selection: $themeManager.transitionDelay) {
                            Text("Off").tag(0)
                            Text("2 sec").tag(2)
                            Text("5 sec").tag(5)
                            Text("10 sec").tag(10)
                            Text("15 sec").tag(15)
                            Text("30 sec").tag(30)
                        }

                        Text("Waits before switching to avoid brief light changes.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section("Schedule") {
                        Toggle("Force Dark Mode on Schedule", isOn: $themeManager.scheduleEnabled)

                        if themeManager.scheduleEnabled {
                            DatePicker("From", selection: $themeManager.scheduleDarkFrom, displayedComponents: .hourAndMinute)

                            DatePicker("Until", selection: $themeManager.scheduleDarkUntil, displayedComponents: .hourAndMinute)

                            Text("Forces dark mode during this time regardless of ambient light.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section("General") {
                        Toggle("Launch at Login", isOn: $themeManager.launchAtLogin)
                        Toggle("Show Lux in Menu Bar", isOn: $themeManager.showLuxInMenuBar)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            // Resize handle
            ResizeHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartHeight == nil {
                                dragStartHeight = panelHeight
                            }
                            let newHeight = (dragStartHeight ?? panelHeight) + value.translation.height
                            panelHeight = min(Self.maxHeight, max(Self.minHeight, newHeight))
                        }
                        .onEnded { _ in
                            dragStartHeight = nil
                        }
                )

            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()

                Button {
                    if let url = URL(string: "https://github.com/projectdelta6/LuxSwitch") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "book")
                        Text("v\(ThemeManager.appVersion)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help("Open LuxSwitch on GitHub")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: panelHeight)
    }
}

struct ResizeHandle: View {
    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            VStack(spacing: 2) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.tertiary)
                        .frame(width: 36, height: 2)
                }
            }
            Spacer()
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
