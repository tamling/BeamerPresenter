import Foundation
import os

/// How the screensaver gets back to the music folder chosen in its options.
///
/// Inside `legacyScreenSaver`'s sandbox it is not documented which way works,
/// so every way is kept and tried: a security-scoped bookmark, a plain
/// bookmark, and the plain path. Each attempt and its outcome is logged in
/// category `scan` ("folder: …"), so the log shows which way this Mac allows.
///
/// Resolving waits on the disk (a share may take seconds to wake), so the
/// screensaver resolves on `queue` and gets the result on the main thread.
/// Any thread may call these functions.
enum FolderAccess {
    /// Serial, so resolutions finish in the order they were asked for.
    private static let queue = DispatchQueue(label: "app.beamerpresenter.AlbumArtworkSaver.folder",
                                             qos: .userInitiated)
    private static let lock = NSLock()
    /// URLs `resolve` started security-scoped access for, not stopped yet; under `lock`.
    private static var accessing: [URL] = []

    /// Stores `url` in `settings` as its path and as a bookmark: a
    /// security-scoped one if the sandbox makes one, else a plain one, else none.
    static func remember(_ url: URL, in settings: inout SaverSettings) {
        let folder = url.standardizedFileURL
        settings.folderPath = folder.path
        settings.folderBookmark = bookmark(for: folder, securityScoped: true)
            ?? bookmark(for: folder, securityScoped: false)
        if settings.folderBookmark == nil {
            Logger.scan.notice("folder: keeping only the path \(folder.path, privacy: .public)")
        }
    }

    /// `resolve(_:)` off the main thread; `deliver` gets its result on the
    /// main thread. A caller that no longer wants the URL must still give it
    /// to `stopAccessing`.
    static func resolve(_ settings: SaverSettings,
                        then deliver: @escaping (_ status: FolderStatus, _ url: URL?) -> Void) {
        queue.async {
            let (status, url) = resolve(settings)
            DispatchQueue.main.async { deliver(status, url) }
        }
    }

    /// The chosen folder, the first way that gives a readable folder: the
    /// bookmark (security-scoped, then plain; a stale one is made anew), then
    /// the path. A security-scoped URL comes back with access started: give it
    /// to `stopAccessing` once it is no longer read. Blocks while the disk
    /// answers; not for the main thread.
    static func resolve(_ settings: SaverSettings) -> (status: FolderStatus, url: URL?) {
        guard settings.folderBookmark != nil || settings.folderPath != nil else {
            Logger.scan.notice("folder: none chosen")
            return (.notChosen, nil)
        }
        if let data = settings.folderBookmark {
            if let url = open(data, securityScoped: true) ?? open(data, securityScoped: false) {
                return (.available, url)
            }
        } else {
            Logger.scan.notice("folder: no bookmark saved")
        }
        if let path = settings.folderPath {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if isReadableFolder(url, via: "path") { return (.available, url) }
        }
        Logger.scan.notice("folder: not reachable")
        return (.unavailable, nil)
    }

    /// Ends the access `resolve` started for `url`; does nothing for a URL
    /// without one, so any URL `resolve` returned may be passed, once.
    static func stopAccessing(_ url: URL) {
        lock.lock()
        let index = accessing.firstIndex(of: url)
        if let index { accessing.remove(at: index) }
        lock.unlock()
        guard index != nil else { return }
        url.stopAccessingSecurityScopedResource()
        Logger.scan.notice("folder: access ended for \(url.path, privacy: .public)")
    }

    // MARK: - Bookmarks

    private static func bookmark(for url: URL, securityScoped: Bool) -> Data? {
        let kind = securityScoped ? "security-scoped" : "plain"
        let options: URL.BookmarkCreationOptions = securityScoped ? .withSecurityScope : []
        do {
            let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            Logger.scan.notice("folder: \(kind, privacy: .public) bookmark created for \(url.path, privacy: .public)")
            return data
        } catch {
            Logger.scan.error("""
                folder: \(kind, privacy: .public) bookmark failed for \(url.path, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return nil
        }
    }

    /// The folder `data` points to, if it resolves to a readable folder. A
    /// disk that is not mounted is not mounted for it: that would hold up the
    /// main thread, and the wall runs from the cache meanwhile.
    private static func open(_ data: Data, securityScoped: Bool) -> URL? {
        let kind = securityScoped ? "security-scoped" : "plain"
        var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        if securityScoped { options.insert(.withSecurityScope) }
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        } catch {
            Logger.scan.error("""
                folder: \(kind, privacy: .public) bookmark failed: \(error.localizedDescription, privacy: .public)
                """)
            return nil
        }
        let started = securityScoped && url.startAccessingSecurityScopedResource()
        if started {
            lock.lock()
            accessing.append(url)
            lock.unlock()
        }
        let access = securityScoped ? (started ? ", access started" : ", access not granted") : ""
        Logger.scan.notice("""
            folder: \(kind, privacy: .public) bookmark resolved to \(url.path, privacy: .public)\
            \(isStale ? " (stale)" : "", privacy: .public)\(access, privacy: .public)
            """)
        guard isReadableFolder(url, via: "\(kind) bookmark") else {
            stopAccessing(url)
            return nil
        }
        if isStale { renew(data, with: url, securityScoped: securityScoped) }
        return url
    }

    /// Saves a fresh bookmark of the same kind, and the folder's path now, in
    /// place of the stale `old`, unless the settings changed meanwhile or no
    /// bookmark can be made (the stale one still resolves).
    private static func renew(_ old: Data, with url: URL, securityScoped: Bool) {
        var saved = SaverSettings.load()
        guard saved.folderBookmark == old, let fresh = bookmark(for: url, securityScoped: securityScoped) else { return }
        saved.folderBookmark = fresh
        saved.folderPath = url.standardizedFileURL.path
        saved.saveFolder()
        Logger.scan.notice("folder: stale bookmark replaced")
    }

    /// True if `url` is a folder that can be listed: in the sandbox, existing is not enough.
    private static func isReadableFolder(_ url: URL, via way: String) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            Logger.scan.notice("folder: \(way, privacy: .public) readable: \(url.path, privacy: .public)")
            return true
        } catch {
            Logger.scan.error("""
                folder: \(way, privacy: .public) unreadable: \(url.path, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return false
        }
    }
}
