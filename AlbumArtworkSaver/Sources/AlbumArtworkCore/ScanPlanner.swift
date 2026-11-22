import Foundation

struct ScanPlan: Equatable {
    var toRead: [String]
    var vanished: [String]
}

/// What a track with a picture, just read, asks of the album covers.
enum CoverPlan: Equatable {
    /// The track joins this album; its cover stays as it is.
    case join(AlbumID)
    /// The track becomes the album's cover source; its picture is the cover already.
    case adopt(AlbumID)
    /// The track is (or becomes) the album's cover source, and its picture is
    /// another: the cover is made anew from it.
    case replace(AlbumID)
    /// A new album, its cover made from this track.
    case new
}

enum ScanPlanner {
    static func plan(index: LibraryIndex, listing: [String: FileStamp]) -> ScanPlan {
        var toRead: [String] = []
        for (path, stamp) in listing where index.files[path]?.stamp != stamp {
            toRead.append(path)
        }
        var vanished: [String] = []
        for path in index.files.keys where listing[path] == nil {
            vanished.append(path)
        }
        return ScanPlan(toRead: toRead.sorted(), vanished: vanished.sorted())
    }

    /// `id` if known, else an album with the same picture fingerprint, else `nil`.
    static func existingAlbum(id: AlbumID, fingerprint: UInt64, in index: LibraryIndex) -> AlbumID? {
        if index.albums[id] != nil { return id }
        return index.albums.filter { $0.value.fingerprint == fingerprint }.keys.sorted().first
    }

    /// What reading the track at `path`, of album `id`, with a picture of
    /// `fingerprint`, does to the covers. The cover comes from the album's
    /// source track: when that track changes its picture, the cover changes.
    /// A source that `isListed` no longer finds (renamed, ripped again) hands
    /// over to the next track of the album that is read. Unknown albums join
    /// an album with the same picture, or are new.
    static func coverPlan(path: String, album id: AlbumID, fingerprint: UInt64, in index: LibraryIndex,
                          isListed: (String) -> Bool) -> CoverPlan {
        if let known = index.albums[id] {
            let isSource = known.source.map { $0 == path || !isListed($0) } ?? true
            guard isSource else { return .join(id) }
            if known.fingerprint != fingerprint { return .replace(id) }
            return known.source == path ? .join(id) : .adopt(id)
        }
        if let twin = existingAlbum(id: id, fingerprint: fingerprint, in: index) { return .join(twin) }
        return .new
    }

    /// Makes the track at `path`, with a picture of `fingerprint`, the source
    /// of `album`'s cover; does nothing for an album the index does not know.
    static func setCover(of album: AlbumID, source path: String, fingerprint: UInt64,
                         into index: inout LibraryIndex) {
        guard index.albums[album] != nil else { return }
        index.albums[album]?.source = path
        index.albums[album]?.fingerprint = fingerprint
    }

    /// Records a parsed file. The first track of an album provides its cover; later tracks
    /// (and byte-identical pictures under another ID) join the existing album.
    static func record(path: String, stamp: FileStamp, album: AlbumID?, info: IndexedAlbum?,
                       into index: inout LibraryIndex) -> (album: AlbumID?, isNew: Bool) {
        var resolved: AlbumID?
        var isNew = false
        if let album {
            if let info {
                if let existing = existingAlbum(id: album, fingerprint: info.fingerprint, in: index) {
                    resolved = existing
                } else {
                    index.albums[album] = info
                    resolved = album
                    isNew = true
                }
            } else if index.albums[album] != nil {
                resolved = album
            }
        }
        index.files[path] = IndexedFile(stamp: stamp, album: resolved)
        return (resolved, isNew)
    }

    static func finish(vanished: [String], listingComplete: Bool, at date: Date,
                       into index: inout LibraryIndex) -> [AlbumID] {
        guard listingComplete else { return [] }
        for path in vanished { index.files[path] = nil }
        let referenced = Set(index.files.values.compactMap(\.album))
        let orphans = index.albums.keys.filter { !referenced.contains($0) }.sorted()
        for id in orphans { index.albums[id] = nil }
        index.lastCompleteScan = date
        return orphans
    }
}
