import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var themeManager: ThemeManager

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

                    if let lux = themeManager.currentLux {
                        Text("\(lux) lux")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(themeManager.sensorAvailable ? "Reading..." : "Sensor unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            // Settings
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
                    HStack {
                        Text("Poll Interval")
                        Spacer()
                        TextField("", value: $themeManager.pollInterval, format: .number)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("sec")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}
