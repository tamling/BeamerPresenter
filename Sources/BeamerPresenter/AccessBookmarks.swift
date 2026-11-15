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
        trim(&map)   // cap first: only what we keep is worth resolving

        for (path, entry) in map {
            var stale = false
            do {
                let url = try resolve(entry.data, stale: &stale)
                if url.startAccessingSecurityScopedResource() { accessed.append(url) }
                if stale || url.path != path {
                    // The file moved: re-store under its new path and drop the
                    // old key (it must not linger under the dead path).
                    map[path] = nil
                    map[url.path] = Entry(data: bookmarkData(for: url) ?? entry.data,
                                          lastUsed: entry.lastUsed)
                }
            } catch {
                // Prune only what is definitely gone — the error says "no such
                // file" *and* the enclosing folder is there. A share that isn't
                // mounted right now keeps its entry, or one launch off the VPN
                // would throw the remembered grant away.
                let fm = FileManager.default
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                guard isMissing(error), fm.fileExists(atPath: parent) else { continue }
                if fm.fileExists(atPath: path),
                   let data = bookmarkData(for: URL(fileURLWithPath: path)) {
                    // Bookmark broke but the file is still there — re-create it
                    // from the path instead of carrying the dead data forever.
                    map[path] = Entry(data: data, lastUsed: entry.lastUsed)
                } else {
                    map[path] = nil
                }
            }
        }

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

    /// Resolution never mounts a volume or puts up a panel: `restoreAll` runs
    /// before the first window exists, so a bookmark to an absent network
    /// share must fail fast instead of blocking launch on a mount attempt.
    /// Throws the plain attempt's error, which tells the caller whether the
    /// file is gone or merely out of reach.
    private static func resolve(_ data: Data, stale: inout Bool) throws -> URL {
        let options: URL.BookmarkResolutionOptions = [.withoutMounting, .withoutUI]
        if let url = try? URL(resolvingBookmarkData: data,
                              options: options.union(.withSecurityScope),
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return try URL(resolvingBookmarkData: data, options: options,
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Whether resolution failed because the file is gone, rather than because
    /// its volume is away (or the user denied access). Anything unrecognised
    /// counts as "away", keeping the entry.
    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain else { return false }
        return error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError
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
