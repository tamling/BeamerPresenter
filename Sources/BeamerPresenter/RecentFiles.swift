import Foundation

/// Lightweight "recently opened" list persisted in UserDefaults.
enum RecentFiles {
    private static let key = "recentFilePaths"
    private static let maxCount = 8

    static func load() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ url: URL) {
        var paths = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        if paths.count > maxCount { paths = Array(paths.prefix(maxCount)) }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
