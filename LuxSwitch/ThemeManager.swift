import Foundation
import AppKit
import Combine

final class ThemeManager: ObservableObject {

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            if isEnabled {
                // Save current system theme as the user's preferred default
                refreshSystemAppearance()
                preferredDarkMode = isDarkMode
            } else {
                // Restore user's preferred theme
                restorePreferredTheme()
            }
            restartPolling()
        }
    }

    @Published var threshold: Int {
        didSet { UserDefaults.standard.set(threshold, forKey: Keys.threshold) }
    }

    @Published var hysteresis: Int {
        didSet { UserDefaults.standard.set(hysteresis, forKey: Keys.hysteresis) }
    }

    @Published var pollInterval: Int {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval)
            restartPolling()
        }
    }

    @Published var preferredDarkMode: Bool {
        didSet { UserDefaults.standard.set(preferredDarkMode, forKey: Keys.preferredDarkMode) }
    }

    @Published private(set) var currentLux: Int?
    @Published private(set) var isDarkMode: Bool = false
    @Published private(set) var sensorAvailable: Bool = true
    @Published private(set) var automationPermission: PermissionState = .unknown

    enum PermissionState {
        case unknown, granted, denied
    }

    private var timer: Timer?
    private var terminationObserver: Any?

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let threshold = "threshold"
        static let hysteresis = "hysteresis"
        static let pollInterval = "pollInterval"
        static let preferredDarkMode = "preferredDarkMode"
        static let hasStoredPreference = "hasStoredPreference"
    }

    private enum Defaults {
        static let threshold = 50_000
        static let hysteresis = 20_000
        static let pollInterval = 30
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.threshold: Defaults.threshold,
            Keys.hysteresis: Defaults.hysteresis,
            Keys.pollInterval: Defaults.pollInterval
        ])

        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.threshold = defaults.integer(forKey: Keys.threshold)
        self.hysteresis = defaults.integer(forKey: Keys.hysteresis)
        self.pollInterval = defaults.integer(forKey: Keys.pollInterval)

        // Load saved preferred theme, or capture current system theme as default
        if defaults.bool(forKey: Keys.hasStoredPreference) {
            self.preferredDarkMode = defaults.bool(forKey: Keys.preferredDarkMode)
        } else {
            let currentlyDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            self.preferredDarkMode = currentlyDark
            defaults.set(true, forKey: Keys.hasStoredPreference)
            defaults.set(currentlyDark, forKey: Keys.preferredDarkMode)
        }

        refreshSystemAppearance()
        checkAutomationPermission()
        if automationPermission == .denied {
            isEnabled = false
        }
        if isEnabled { startPolling() }

        // Restore preferred theme when the app quits
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppQuit()
        }
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public

    func refreshSystemAppearance() {
        isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func retryPermissionCheck() {
        let wasDenied = automationPermission == .denied
        checkAutomationPermission()
        if wasDenied && automationPermission == .granted {
            isEnabled = true
        }
    }

    // MARK: - App lifecycle

    private func handleAppQuit() {
        guard isEnabled, automationPermission == .granted else { return }
        restorePreferredTheme()
    }

    private func restorePreferredTheme() {
        guard automationPermission == .granted else { return }
        if isDarkMode != preferredDarkMode {
            setSystemDarkMode(preferredDarkMode)
        }
    }

    // MARK: - Permission check

    private func checkAutomationPermission() {
        let source = """
            tell application "System Events"
                tell appearance preferences
                    return dark mode
                end tell
            end tell
        """
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            if errorNumber == -1743 {
                automationPermission = .denied
                print("Automation permission denied. Grant access in System Settings > Privacy & Security > Automation.")
            } else {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                print("AppleScript permission check error: \(message)")
                automationPermission = .denied
            }
        } else {
            automationPermission = .granted
        }
    }

    // MARK: - Polling

    private func restartPolling() {
        stopPolling()
        if isEnabled { startPolling() }
    }

    private func startPolling() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(pollInterval), repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let lux = AmbientLightSensor.readLux()

            DispatchQueue.main.async {
                self.sensorAvailable = lux != nil
                if let lux {
                    self.currentLux = lux
                    if self.automationPermission == .granted {
                        self.evaluateThreshold(lux: lux)
                    }
                }
            }
        }
    }

    // MARK: - Threshold evaluation

    private func evaluateThreshold(lux: Int) {
        let upper = threshold + hysteresis
        let lower = max(0, threshold - hysteresis)

        if lux >= upper && isDarkMode {
            setSystemDarkMode(false)
        } else if lux <= lower && !isDarkMode {
            setSystemDarkMode(true)
        }
    }

    private func setSystemDarkMode(_ dark: Bool) {
        let source = """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to \(dark)
                end tell
            end tell
        """
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            print("AppleScript error: \(message)")
            if errorNumber == -1743 {
                automationPermission = .denied
            }
        } else {
            isDarkMode = dark
            automationPermission = .granted
        }
    }
}
