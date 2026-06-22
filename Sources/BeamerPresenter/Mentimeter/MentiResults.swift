import Foundation

/// Remembers Mentimeter result files the user downloaded, so the app can list
/// them for quick "reveal in Finder" / open. Plain paths in UserDefaults.
enum MentiResults {
    private static let key = "mentiResultPaths"
    static let didChange = Notification.Name("MentiResultsDidChange")

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(20)), forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Saved results that still exist on disk, most recent first.
    static func load() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
