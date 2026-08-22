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

    /// File extensions the browser offers to open (presentations + their source).
    static let openableExtensions: Set<String> = ["pdf", "tex"]

    /// Sub-folders and openable files (`.pdf` / `.tex`) directly inside `folder`,
    /// each sorted by name. Used by the favourite folder browser to navigate.
    static func children(of folder: URL) -> (folders: [URL], files: [URL]) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        func byName(_ a: URL, _ b: URL) -> Bool {
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        let folders = contents.filter { isDirectory($0) }.sorted(by: byName)
        let files = contents
            .filter { openableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted(by: byName)
        return (folders, files)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// App identity for the About panel, splash, and menus.
enum AppInfo {
    static let name = "BeamerPresenter"

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "4.1"
    }

    /// e.g. "Version 4.1"
    static var versionLine: String { "Version \(version)" }

    /// e.g. "Build 260621-1901175" — stamped at build time (see BuildInfo).
    static var buildLine: String { "Build \(BuildInfo.id)" }

    static var copyright: String { "© 2026" }
}
