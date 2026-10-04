import Foundation

/// Keeps user-granted file/folder access alive across launches.
///
/// Every opened presentation (plus its folder) and every favourite folder is
/// stored as a bookmark — security-scoped where the system grants one — in the
/// app's config folder (`~/Library/Application Support/BeamerPresenter/
/// bookmarks.json`). At launch the bookmarks are resolved and access is
/// re-established, so macOS doesn't ask again for locations the user already
/// granted (e.g. after a drag & drop from Downloads, or an app restart).
///
/// The list is capped to the most recently used entries: security scopes are
/// a limited kernel resource, so the app never holds more than `maxEntries`
/// open at once.
enum AccessBookmarks {
    private static let maxEntries = 40

    /// The app's config folder, created on demand.
    static var configDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BeamerPresenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var file: URL { configDir.appendingPathComponent("bookmarks.json") }

    private struct Entry: Codable {
        var data: Data
        var lastUsed: Date
    }

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

    /// Re-establishes access to everything remembered (newest first, capped);
    /// prunes dead entries and refreshes stale or broken-but-recreatable ones.
    /// Call once early at launch.
    static func restoreAll() {
        var map = loadMap()

        for (path, entry) in map {
            var stale = false
            if let url = resolve(entry.data, stale: &stale) {
                if url.startAccessingSecurityScopedResource() { accessed.append(url) }
                if stale || url.path != path {
                    // The file moved: re-store under its new path and drop the
                    // old key (it must not linger under the dead path).
                    map[path] = nil
                    map[url.path] = Entry(data: bookmarkData(for: url) ?? entry.data,
                                          lastUsed: entry.lastUsed)
                }
            } else if FileManager.default.fileExists(atPath: path) {
                // Bookmark broke but the file is still there — re-create it
                // from the path instead of carrying the dead data forever.
                let url = URL(fileURLWithPath: path)
                if let data = bookmarkData(for: url) {
                    map[path] = Entry(data: data, lastUsed: entry.lastUsed)
                } else {
                    map[path] = nil
                }
            } else {
                map[path] = nil
            }
        }

        trim(&map)
        saveMap(map)
    }

    // MARK: - Bookmark plumbing

    private static func store(_ url: URL, into map: inout [String: Entry]) {
        guard let data = bookmarkData(for: url) else { return }
        map[url.path] = Entry(data: data, lastUsed: Date())
        trim(&map)
    }

    /// Security-scoped where available (sandbox), plain otherwise — both keep
    /// working, resolution tries the scoped flavour first.
    private static func bookmarkData(for url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope],
                               includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
    }

    private static func resolve(_ data: Data, stale: inout Bool) -> URL? {
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return try? URL(resolvingBookmarkData: data, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Keeps only the most recently used entries.
    private static func trim(_ map: inout [String: Entry]) {
        guard map.count > maxEntries else { return }
        let drop = map.sorted { $0.value.lastUsed < $1.value.lastUsed }
            .prefix(map.count - maxEntries)
        drop.forEach { map[$0.key] = nil }
    }

    private static func loadMap() -> [String: Entry] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        if let map = try? JSONDecoder().decode([String: Entry].self, from: data) {
            return map
        }
        // Migrate the v4.8 format (plain path → bookmark data).
        if let old = try? JSONDecoder().decode([String: Data].self, from: data) {
            return old.mapValues { Entry(data: $0, lastUsed: Date()) }
        }
        return [:]
    }

    private static func saveMap(_ map: [String: Entry]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
