import Foundation
import AppKit

final class UpdateManager: ObservableObject {

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var downloadProgress: Double = 0

    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case readyToInstall
        case error(String)
    }

    private static let releasesURL = URL(string: "https://api.github.com/repos/projectdelta6/LuxSwitch/releases/latest")!
    private var downloadedAppURL: URL?
    private var downloadTask: URLSessionDownloadTask?

    // MARK: - Public

    func checkForUpdates() {
        guard state != .checking && state != .downloading else { return }
        state = .checking

        let request = URLRequest(url: Self.releasesURL, cachePolicy: .reloadIgnoringLocalCacheData)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleCheckResponse(data: data, response: response, error: error)
            }
        }.resume()
    }

    func downloadAndInstall() {
        guard state == .updateAvailable, let zipURL = findZipAssetURL() else { return }
        state = .downloading
        downloadProgress = 0

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        let task = session.downloadTask(with: zipURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.handleDownloadComplete(tempURL: tempURL, error: error)
            }
        }

        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        // Keep the observation alive by storing it (released when task completes)
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        downloadTask = task
        task.resume()
    }

    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    func dismissUpdate() {
        state = .idle
        latestVersion = nil
        releaseURL = nil
        cleanup()
    }

    // MARK: - Check response

    private func handleCheckResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            state = .error("Network error: \(error.localizedDescription)")
            return
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String else {
            state = .error("Could not parse release info.")
            return
        }

        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        latestVersion = remoteVersion
        releaseURL = URL(string: htmlURL)

        // Store assets for later download
        if let assets = json["assets"] as? [[String: Any]] {
            cachedAssets = assets
        }

        if isNewer(remote: remoteVersion, local: ThemeManager.appVersion) {
            state = .updateAvailable
        } else {
            state = .upToDate
        }
    }

    private var cachedAssets: [[String: Any]] = []

    private func findZipAssetURL() -> URL? {
        for asset in cachedAssets {
            guard let name = asset["name"] as? String,
                  name.hasSuffix(".zip"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { continue }
            return url
        }
        return nil
    }

    // MARK: - Version comparison

    private func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, localParts.count)

        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: - Download & install

    private func handleDownloadComplete(tempURL: URL?, error: Error?) {
        downloadTask = nil

        if let error {
            state = .error("Download failed: \(error.localizedDescription)")
            return
        }

        guard let tempURL else {
            state = .error("Download failed: no file received.")
            return
        }

        do {
            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("LuxSwitch-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            // Unzip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", tempURL.path, extractDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                state = .error("Failed to extract update.")
                return
            }

            // Find the .app inside
            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                state = .error("No app found in download.")
                return
            }

            downloadedAppURL = appBundle
            state = .readyToInstall
            installUpdate()
        } catch {
            state = .error("Extract error: \(error.localizedDescription)")
        }
    }

    private func installUpdate() {
        guard let newAppURL = downloadedAppURL else { return }
        let currentAppURL = Bundle.main.bundleURL

        do {
            // Move current app to trash
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: currentAppURL, resultingItemURL: &trashedURL)

            // Move new app to the same location
            try FileManager.default.moveItem(at: newAppURL, to: currentAppURL)

            // Relaunch
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", currentAppURL.path]
            try process.run()

            // Give the new instance a moment to start, then quit this one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            state = .error("Install failed: \(error.localizedDescription)")
        }
    }

    private func cleanup() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadedAppURL = nil
        cachedAssets = []
        downloadProgress = 0
    }
}
