import Foundation
import os

extension Logger {
    /// The scanner's log: subsystem = bundle ID, category `scan`.
    static let scan = Logger(subsystem: "app.beamerpresenter.AlbumArtworkSaver", category: "scan")
}

struct ScanSummary: Equatable {
    enum Outcome: String {
        /// Every file listed and read; what is gone from the folder is gone from the cache.
        case complete
        /// Something could not be listed, read or stored: what was read is kept, nothing removed.
        case incomplete
        /// No music folder there (disk not mounted, share asleep): the cache was not touched.
        case unavailable
        /// Another scan holds the cache's lock: nothing was done.
        case busy
        /// Stopped on request: what was read is kept, nothing removed.
        case cancelled
    }

    var outcome: Outcome
    var albums: Int
    var files: Int
    /// Files whose tags this pass read: new and changed ones only.
    var read: Int
    var newAlbums: Int
    var removedAlbums: Int
}

/// One incremental pass over a music folder into a `CoverCache`: lists every
/// `.mp3`, reads the tags of the new and changed ones, writes one cover per new
/// album (and anew when the track it came from changed its picture), and only
/// after a complete pass forgets what is gone. The music folder is only ever read.
///
/// `run` blocks; call it off the main thread.
final class LibraryScanner {
    /// New albums are handed on in batches of this many, and whenever the index is saved.
    private static let reportEvery = 20
    /// The index is saved after every this many files read.
    private static let saveEvery = 200
    /// Listing errors logged one by one; the rest are only counted.
    private static let loggedErrors = 10
    private static let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

    private let root: URL
    private let cache: CoverCache

    init(root: URL, cache: CoverCache) {
        self.root = root
        self.cache = cache
    }

    /// `onNewAlbums` gets the albums whose covers were written for the first
    /// time, `onChangedCovers` those whose covers were written anew; both in
    /// batches, while the scan goes on.
    func run(isCancelled: () -> Bool, onNewAlbums: ([AlbumID]) -> Void,
             onChangedCovers: ([AlbumID]) -> Void = { _ in }) -> ScanSummary {
        let began = Date()
        // 1. No folder: leave the cache alone. Deleting now would empty it
        //    whenever the disk is not mounted.
        guard let folder = Self.existingFolder(root) else {
            Logger.scan.notice("scan: \(self.root.path, privacy: .public) is not reachable; the cache stays as it is")
            return Self.summary(.unavailable, of: cache.loadIndex())
        }
        // 2. One scan per cache, across processes.
        guard cache.tryLock() else {
            Logger.scan.notice("scan: another scan is writing \(self.cache.directory.path, privacy: .public)")
            return Self.summary(.busy, of: cache.loadIndex())
        }
        defer { cache.unlock() }

        // 3. The listing.
        var listing = list(folder, isCancelled: isCancelled)
        let loaded = cache.loadIndex()
        var index = loaded
        if listing.files.isEmpty, !index.files.isEmpty, !listing.cancelled {
            // Most likely the empty mount point of a disk that is not plugged
            // in, not a music library deleted to the last file.
            Logger.scan.notice("scan: \(folder.path, privacy: .public) lists no MP3s; nothing is removed")
            listing.complete = false
        }
        let plan = ScanPlanner.plan(index: index, listing: listing.files)
        Logger.scan.notice("""
            scan: \(listing.files.count, privacy: .public) files in \(folder.path, privacy: .public), \
            \(plan.toRead.count, privacy: .public) to read, \(plan.vanished.count, privacy: .public) gone
            """)

        // 4. Read what is new or changed.
        let listed = listing.files
        var pending: [AlbumID] = []
        var pendingCovers: [AlbumID] = []
        var newAlbums = 0
        var changedCovers = 0
        var read = 0
        var unsaved = 0
        var unreadable = 0
        for path in plan.toRead where !listing.cancelled {
            if isCancelled() {
                listing.cancelled = true
                break
            }
            guard let stamp = listing.files[path] else { continue }
            let url = folder.appendingPathComponent(path, isDirectory: false)
            let result = autoreleasepool {
                ingest(url, path: path, stamp: stamp, isListed: { listed[$0] != nil }, into: &index)
            }
            if case .unreadable = result {
                // Not recorded, so it is read again next time; and since this
                // pass missed a file, it removes nothing.
                listing.complete = false
                unreadable += 1
                if unreadable <= Self.loggedErrors {
                    Logger.scan.error("scan: cannot read \(path, privacy: .public)")
                }
                if Self.existingFolder(root) == nil {
                    Logger.scan.error("scan: \(folder.path, privacy: .public) went away while reading")
                    break
                }
                continue
            }
            if case let .newAlbum(album) = result {
                pending.append(album)
                newAlbums += 1
            }
            if case let .coverChanged(album) = result {
                pendingCovers.append(album)
                changedCovers += 1
            }
            if case .notStored = result { listing.complete = false }
            read += 1
            unsaved += 1
            let saving = unsaved >= Self.saveEvery
            if saving {
                if !save(index) { listing.complete = false }
                unsaved = 0
            }
            if !pending.isEmpty, saving || pending.count >= Self.reportEvery {
                onNewAlbums(pending)
                pending.removeAll()
            }
            if !pendingCovers.isEmpty, saving || pendingCovers.count >= Self.reportEvery {
                onChangedCovers(pendingCovers)
                pendingCovers.removeAll()
            }
        }

        // 5. Forget what is gone, but only after a complete pass, and only if
        //    the folder is still there: a disk that went away during the
        //    listing may have ended it early without an error. The index is
        //    saved before covers are deleted, so it never names a missing cover.
        let stillThere = Self.existingFolder(root)?.path == folder.path
        if !stillThere { Logger.scan.error("scan: \(folder.path, privacy: .public) went away during the scan") }
        let complete = listing.complete && !listing.cancelled && stillThere
        let removed = ScanPlanner.finish(vanished: plan.vanished, listingComplete: complete, at: Date(),
                                         into: &index)
        // 6. Save (unless nothing changed), report, summarise (the lock goes with `defer`).
        let saved = index == loaded || save(index)
        if !pending.isEmpty { onNewAlbums(pending) }
        if !pendingCovers.isEmpty { onChangedCovers(pendingCovers) }
        if saved {
            for album in removed { cache.removeCover(album) }
            if complete { cache.removeOrphanCovers(keeping: Set(index.albums.keys)) }
        }
        let outcome: ScanSummary.Outcome = listing.cancelled ? .cancelled : (complete && saved ? .complete : .incomplete)
        var summary = Self.summary(outcome, of: index)
        summary.read = read
        summary.newAlbums = newAlbums
        summary.removedAlbums = removed.count
        let seconds = Date().timeIntervalSince(began)
        Logger.scan.notice("""
            scan: \(outcome.rawValue, privacy: .public), \(summary.albums, privacy: .public) albums \
            from \(summary.files, privacy: .public) files; read \(read, privacy: .public), \
            \(unreadable, privacy: .public) unreadable, \(newAlbums, privacy: .public) new, \
            \(changedCovers, privacy: .public) covers changed, \
            \(removed.count, privacy: .public) removed, \
            in \(seconds, format: .fixed(precision: 1), privacy: .public) s
            """)
        return summary
    }

    // MARK: - Listing

    private struct Listing {
        /// Relative path → stamp, for every `.mp3` listed.
        var files: [String: FileStamp] = [:]
        /// False once anything could not be listed: then nothing may be deleted.
        var complete = true
        var cancelled = false
    }

    private func list(_ folder: URL, isCancelled: () -> Bool) -> Listing {
        var listing = Listing()
        var errors = 0
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) { url, error in
            errors += 1
            if errors <= Self.loggedErrors {
                Logger.scan.error("""
                    scan: cannot list \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)
                    """)
            }
            return true  // list the rest; the pass just will not count as complete
        }
        guard let enumerator else {
            Logger.scan.error("scan: cannot list \(folder.path, privacy: .public)")
            listing.complete = false
            return listing
        }
        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        let keys = Set(Self.keys)
        var unlisted = 0
        for case let url as URL in enumerator {
            if isCancelled() {
                listing.cancelled = true
                break
            }
            guard url.pathExtension.lowercased() == "mp3" else { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else {
                unlisted += 1
                continue
            }
            guard values.isRegularFile == true else { continue }
            let path = url.path
            guard let size = values.fileSize, let modified = values.contentModificationDate,
                  path.hasPrefix(prefix)
            else {
                unlisted += 1
                continue
            }
            listing.files[String(path.dropFirst(prefix.count))] =
                FileStamp(size: Int64(size), modifiedAt: modified)
        }
        if errors > 0 || unlisted > 0 {
            Logger.scan.error("""
                scan: \(errors, privacy: .public) listing errors, \(unlisted, privacy: .public) files \
                without size or date; nothing is removed this time
                """)
            listing.complete = false
        }
        return listing
    }

    // MARK: - Reading one file

    private enum Ingested {
        case recorded
        case newAlbum(AlbumID)
        /// The album's cover was written anew from this file's changed picture.
        case coverChanged(AlbumID)
        /// The cover could not be written; the file stays unknown and is read again next time.
        case notStored
        /// The file could not be read; nothing was recorded, so it is read again next time.
        case unreadable
    }

    /// `isListed` tells whether a path is in this pass's listing.
    private func ingest(_ url: URL, path: String, stamp: FileStamp, isListed: (String) -> Bool,
                        into index: inout LibraryIndex) -> Ingested {
        let tag: Data?
        switch TagFileReader.read(at: url) {
        case let .tag(data): tag = data
        case .noTag: tag = nil
        case .unreadable: return .unreadable
        }
        guard let tags = tag.flatMap(ID3Reader.parse), let picture = tags.picture else {
            // No cover: remembered, so the file is not read again until it changes.
            _ = ScanPlanner.record(path: path, stamp: stamp, album: nil, info: nil, into: &index)
            return .recorded
        }
        let fingerprint = Fingerprint.fnv1a64(picture)
        let album = AlbumKey.make(album: tags.album, albumArtist: tags.albumArtist, artist: tags.artist,
                                  pictureFingerprint: fingerprint)
        switch ScanPlanner.coverPlan(path: path, album: album, fingerprint: fingerprint, in: index,
                                     isListed: isListed) {
        case let .join(existing):
            // A further track of a known album, or a known picture: no image work.
            _ = ScanPlanner.record(path: path, stamp: stamp, album: existing, info: nil, into: &index)
            return .recorded
        case let .adopt(existing):
            // Takes over from the gone track the cover came from; same picture, no image work.
            ScanPlanner.setCover(of: existing, source: path, fingerprint: fingerprint, into: &index)
            _ = ScanPlanner.record(path: path, stamp: stamp, album: existing, info: nil, into: &index)
            return .recorded
        case let .replace(existing):
            guard let jpeg = CoverImageProcessor.makeSquareJPEG(from: picture) else {
                // The new picture cannot be read: the old cover stays.
                _ = ScanPlanner.record(path: path, stamp: stamp, album: existing, info: nil, into: &index)
                return .recorded
            }
            // Written over the old cover atomically: a wall sees the old one or the new one.
            guard store(jpeg, for: existing, from: path) else { return .notStored }
            ScanPlanner.setCover(of: existing, source: path, fingerprint: fingerprint, into: &index)
            _ = ScanPlanner.record(path: path, stamp: stamp, album: existing, info: nil, into: &index)
            Logger.scan.notice("""
                scan: the cover of \(existing, privacy: .public) changed with \(path, privacy: .public)
                """)
            return .coverChanged(existing)
        case .new:
            guard let jpeg = CoverImageProcessor.makeSquareJPEG(from: picture) else {
                _ = ScanPlanner.record(path: path, stamp: stamp, album: nil, info: nil, into: &index)
                return .recorded
            }
            guard store(jpeg, for: album, from: path) else { return .notStored }
            let info = IndexedAlbum(fingerprint: fingerprint, title: tags.album ?? "",
                                    artist: tags.albumArtist ?? tags.artist ?? "", source: path)
            let recorded = ScanPlanner.record(path: path, stamp: stamp, album: album, info: info, into: &index)
            return recorded.isNew ? .newAlbum(album) : .recorded
        }
    }

    /// Writes `album`'s cover, made from the file at `path`; false (and
    /// logged) if it cannot be written.
    private func store(_ jpeg: Data, for album: AlbumID, from path: String) -> Bool {
        do {
            try cache.writeCover(jpeg, for: album)
            return true
        } catch {
            Logger.scan.error("""
                scan: cannot write the cover of \(path, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return false
        }
    }

    // MARK: - Helpers

    private func save(_ index: LibraryIndex) -> Bool {
        do {
            try cache.saveIndex(index)
            return true
        } catch {
            Logger.scan.error("scan: cannot save the index: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The folder at `url` with symbolic links resolved, as the enumerator
    /// reports paths; nil when there is no folder there.
    private static func existingFolder(_ url: URL) -> URL? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue
        else { return nil }
        let resolved = url.withUnsafeFileSystemRepresentation { path -> String? in
            guard let path, let real = realpath(path, nil) else { return nil }
            defer { free(real) }
            return String(cString: real)
        }
        return resolved.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func summary(_ outcome: ScanSummary.Outcome, of index: LibraryIndex) -> ScanSummary {
        ScanSummary(outcome: outcome, albums: index.albums.count, files: index.files.count, read: 0,
                    newAlbums: 0, removedAlbums: 0)
    }
}
