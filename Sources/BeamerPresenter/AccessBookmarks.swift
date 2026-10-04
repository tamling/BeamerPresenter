import Foundation

/// Keeps user-granted file/folder access alive across launches.
///
/// Every opened presentation (plus its folder) and every favourite folder is
/// stored as a bookmark — security-scoped where the system grants one — in the
/// app's config folder (`~/Library/Application Support/BeamerPresenter/
/// bookmarks.json`). At launch the bookmarks are resolved and access is
/// re-established, so macOS doesn't ask again for locations the user already
/// granted (e.g. after a drag & drop from Downloads, or an app restart).
enum AccessBookmarks {
    /// The app's config folder, created on demand.
    static var configDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BeamerPresenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var file: URL { configDir.appendingPathComponent("bookmarks.json") }

    /// URLs whose security scope we opened this run (kept so the scope stays
    /// alive for the app's lifetime; macOS closes it on exit).
    private static var accessed: [URL] = []

    /// Remembers access to `url` — and, for a file, to its folder, which also
    /// covers the sibling `.tex` / `.nav` / `.pptx` the notes readers touch.
    static func remember(_ url: URL) {
        var map = loadMap()
        store(url, into: &map)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if !isDir.boolValue {
            store(url.deletingLastPathComponent(), into: &map)
        }
        saveMap(map)
    }

    /// Re-establishes access to everything remembered; prunes dead entries.
    /// Call once early at launch.
    static func restoreAll() {
        var map = loadMap()
        var changed = false
        for (path, data) in map {
            var stale = false
            if let url = resolve(data, stale: &stale) {
                if url.startAccessingSecurityScopedResource() { accessed.append(url) }
                if stale { store(url, into: &map); changed = true }
            } else if !FileManager.default.fileExists(atPath: path) {
                map[path] = nil
                changed = true
            }
        }
        if changed { saveMap(map) }
    }

    // MARK: - Bookmark plumbing

    /// Security-scoped where available (sandbox), plain otherwise — both keep
    /// working, resolution tries the scoped flavour first.
    private static func store(_ url: URL, into map: inout [String: Data]) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope],
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil))
            ?? (try? url.bookmarkData())
        if let data { map[url.path] = data }
    }

    private static func resolve(_ data: Data, stale: inout Bool) -> URL? {
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return try? URL(resolvingBookmarkData: data, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private static func loadMap() -> [String: Data] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private static func saveMap(_ map: [String: Data]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
