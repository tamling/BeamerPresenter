import Foundation

struct ScanPlan: Equatable {
    var toRead: [String]
    var vanished: [String]
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
