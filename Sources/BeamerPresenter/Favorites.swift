import Foundation

/// Persisted list of favourite *folders* that hold presentations, shown on the
/// welcome screen for quick access. Stored as plain paths in UserDefaults.
enum Favorites {
    private static let key = "favoriteFolderPaths"

    /// Posted whenever the list changes so an open welcome screen can refresh.
    static let didChange = Notification.Name("FavoritesDidChange")

    /// Favourite folders that still exist, in saved order.
    static func load() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { isDirectory($0) }
    }

    @discardableResult
    static func add(_ url: URL) -> Bool {
        guard isDirectory(url) else { return false }
        var paths = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(paths, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    static func remove(_ url: URL) {
        let paths = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { $0 != url.path }
        UserDefaults.standard.set(paths, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// PDFs directly inside a favourite folder, sorted by name.
    static func pdfs(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// App identity for the About panel, splash, and menus.
enum AppInfo {
    static let name = "BeamerPresenter"
    static let author = "Timo Amling"
    static let releaseDate = "2026-06-17"

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.0"
    }

    /// e.g. "Version 1.0 · 2026-06-17"
    static var versionLine: String { "Version \(version) · \(releaseDate)" }

    static var copyright: String { "© 2026 \(author)" }
}
