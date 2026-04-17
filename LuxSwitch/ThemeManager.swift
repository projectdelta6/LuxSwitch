import Foundation
import AppKit
import Combine
import ServiceManagement

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
                cancelPendingSwitch()
                restorePreferredTheme()
            }
            restartPolling()
        }
    }

    @Published var threshold: Int {
        didSet {
            UserDefaults.standard.set(threshold, forKey: Keys.threshold)
            UserDefaults.standard.set(true, forKey: Keys.hasCustomisedThresholds)
        }
    }

    @Published var hysteresis: Int {
        didSet {
            UserDefaults.standard.set(hysteresis, forKey: Keys.hysteresis)
            UserDefaults.standard.set(true, forKey: Keys.hasCustomisedThresholds)
        }
    }

    @Published var pollInterval: Int {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval)
            restartPolling()
        }
    }

    @Published var transitionDelay: Int {
        didSet { UserDefaults.standard.set(transitionDelay, forKey: Keys.transitionDelay) }
    }

    @Published var preferredDarkMode: Bool {
        didSet { UserDefaults.standard.set(preferredDarkMode, forKey: Keys.preferredDarkMode) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(launchAtLogin ? "enable" : "disable") launch at login: \(error)")
                // Revert on failure without re-triggering didSet
                let current = SMAppService.mainApp.status == .enabled
                if launchAtLogin != current {
                    launchAtLogin = current
                }
            }
        }
    }

    @Published var showLuxInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showLuxInMenuBar, forKey: Keys.showLuxInMenuBar) }
    }

    @Published var scheduleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(scheduleEnabled, forKey: Keys.scheduleEnabled)
            restartScheduleTimer()
        }
    }

    @Published var scheduleDarkFrom: Date {
        didSet { UserDefaults.standard.set(scheduleDarkFrom.timeIntervalSinceReferenceDate, forKey: Keys.scheduleDarkFrom) }
    }

    @Published var scheduleDarkUntil: Date {
        didSet { UserDefaults.standard.set(scheduleDarkUntil.timeIntervalSinceReferenceDate, forKey: Keys.scheduleDarkUntil) }
    }

    @Published private(set) var currentLux: Int?
    @Published private(set) var isDarkMode: Bool = false
    @Published private(set) var sensorAvailable: Bool = true
    @Published private(set) var automationPermission: PermissionState = .unknown
    @Published private(set) var isInScheduledDarkMode: Bool = false

    /// Text to display in the menu bar (next to the icon)
    var menuBarText: String? {
        guard showLuxInMenuBar, isEnabled, let lux = currentLux else { return nil }
        return "\(lux)"
    }

    enum PermissionState {
        case unknown, granted, denied
    }

    private var timer: Timer?
    private var scheduleTimer: Timer?
    private var delayWorkItem: DispatchWorkItem?
    private var terminationObserver: Any?

    private var hasCalibrated = false

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let threshold = "threshold"
        static let hysteresis = "hysteresis"
        static let pollInterval = "pollInterval"
        static let transitionDelay = "transitionDelay"
        static let preferredDarkMode = "preferredDarkMode"
        static let hasStoredPreference = "hasStoredPreference"
        static let showLuxInMenuBar = "showLuxInMenuBar"
        static let scheduleEnabled = "scheduleEnabled"
        static let scheduleDarkFrom = "scheduleDarkFrom"
        static let scheduleDarkUntil = "scheduleDarkUntil"
        static let hasCustomisedThresholds = "hasCustomisedThresholds"
    }

    private enum Defaults {
        static let pollInterval = 30
        static let transitionDelay = 5

        // Intel HID Manager: raw sensor values (typically 0–100,000+)
        static let thresholdIntel = 50_000
        static let hysteresisIntel = 20_000

        // Apple Silicon Event System: real lux values (typically 0–2,000)
        static let thresholdAppleSilicon = 200
        static let hysteresisAppleSilicon = 80
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.threshold: Defaults.thresholdIntel,
            Keys.hysteresis: Defaults.hysteresisIntel,
            Keys.pollInterval: Defaults.pollInterval,
            Keys.transitionDelay: Defaults.transitionDelay,
            Keys.showLuxInMenuBar: false,
            Keys.scheduleEnabled: false
        ])

        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.threshold = defaults.integer(forKey: Keys.threshold)
        self.hysteresis = defaults.integer(forKey: Keys.hysteresis)
        self.pollInterval = defaults.integer(forKey: Keys.pollInterval)
        self.transitionDelay = defaults.integer(forKey: Keys.transitionDelay)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.showLuxInMenuBar = defaults.bool(forKey: Keys.showLuxInMenuBar)
        self.scheduleEnabled = defaults.bool(forKey: Keys.scheduleEnabled)

        // Load schedule times (default to 22:00–07:00)
        if defaults.object(forKey: Keys.scheduleDarkFrom) != nil {
            self.scheduleDarkFrom = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Keys.scheduleDarkFrom))
            self.scheduleDarkUntil = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Keys.scheduleDarkUntil))
        } else {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            self.scheduleDarkFrom = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
            self.scheduleDarkUntil = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        }

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
        if scheduleEnabled { startScheduleTimer() }

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
        cancelPendingSwitch()
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

    // MARK: - Schedule

    private func restartScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        if scheduleEnabled { startScheduleTimer() }
    }

    private func startScheduleTimer() {
        evaluateSchedule()
        // Check schedule every 60 seconds
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateSchedule()
        }
    }

    private func evaluateSchedule() {
        guard scheduleEnabled, automationPermission == .granted else {
            isInScheduledDarkMode = false
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let fromComponents = calendar.dateComponents([.hour, .minute], from: scheduleDarkFrom)
        let untilComponents = calendar.dateComponents([.hour, .minute], from: scheduleDarkUntil)

        let fromMinutes = (fromComponents.hour ?? 22) * 60 + (fromComponents.minute ?? 0)
        let untilMinutes = (untilComponents.hour ?? 7) * 60 + (untilComponents.minute ?? 0)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)

        let inSchedule: Bool
        if fromMinutes <= untilMinutes {
            // Same-day range (e.g. 09:00–17:00)
            inSchedule = nowMinutes >= fromMinutes && nowMinutes < untilMinutes
        } else {
            // Overnight range (e.g. 22:00–07:00)
            inSchedule = nowMinutes >= fromMinutes || nowMinutes < untilMinutes
        }

        isInScheduledDarkMode = inSchedule
        if inSchedule && !isDarkMode {
            setSystemDarkMode(true)
        } else if !inSchedule && isDarkMode && isEnabled {
            // When leaving schedule, let the sensor take over on next poll
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
            let reading = AmbientLightSensor.read()

            DispatchQueue.main.async {
                self.sensorAvailable = reading != nil
                if let reading {
                    self.currentLux = reading.lux
                    self.calibrateDefaultsIfNeeded(for: reading.sensorType)
                    if self.automationPermission == .granted {
                        self.evaluateThreshold(lux: reading.lux)
                    }
                } else {
                    // Sensor unavailable (e.g. lid closed in clamshell mode)
                    // Cancel any pending switch — we can't trust the last reading
                    self.currentLux = nil
                    self.cancelPendingSwitch()
                }
            }
        }
    }

    // MARK: - Auto-calibrate defaults

    private func calibrateDefaultsIfNeeded(for sensorType: AmbientLightSensor.SensorType) {
        guard !hasCalibrated else { return }
        hasCalibrated = true

        // Don't override if the user has already changed the thresholds
        guard !UserDefaults.standard.bool(forKey: Keys.hasCustomisedThresholds) else { return }

        let newThreshold: Int
        let newHysteresis: Int

        switch sensorType {
        case .eventSystem:
            newThreshold = Defaults.thresholdAppleSilicon
            newHysteresis = Defaults.hysteresisAppleSilicon
        case .hidManager:
            newThreshold = Defaults.thresholdIntel
            newHysteresis = Defaults.hysteresisIntel
        }

        if threshold != newThreshold {
            threshold = newThreshold
        }
        if hysteresis != newHysteresis {
            hysteresis = newHysteresis
        }
    }

    // MARK: - Threshold evaluation

    private func evaluateThreshold(lux: Int) {
        // Don't override the schedule
        if isInScheduledDarkMode { return }

        let upper = threshold + hysteresis
        let lower = max(0, threshold - hysteresis)

        let wantDark: Bool?
        if lux >= upper && isDarkMode {
            wantDark = false
        } else if lux <= lower && !isDarkMode {
            wantDark = true
        } else {
            wantDark = nil
        }

        guard let wantDark else {
            // Lux is in the dead zone — cancel any pending switch
            cancelPendingSwitch()
            return
        }

        scheduleDeferredSwitch(dark: wantDark)
    }

    // MARK: - Transition delay

    private func scheduleDeferredSwitch(dark: Bool) {
        // If there's already a pending switch to the same mode, let it run
        if delayWorkItem != nil { return }

        guard transitionDelay > 0 else {
            setSystemDarkMode(dark)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.delayWorkItem = nil
            self.setSystemDarkMode(dark)
        }
        delayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(transitionDelay), execute: work)
    }

    private func cancelPendingSwitch() {
        delayWorkItem?.cancel()
        delayWorkItem = nil
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
