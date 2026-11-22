import Foundation

struct FileStamp: Codable, Equatable {
    var size: Int64
    var modified: Double
}

struct IndexedFile: Codable, Equatable {
    var stamp: FileStamp
    /// `nil` = no usable picture.
    var album: AlbumID?
}

struct IndexedAlbum: Codable, Equatable {
    var fingerprint: UInt64
    var title: String
    var artist: String
}

struct LibraryIndex: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    /// Keyed by path relative to the music folder.
    var files: [String: IndexedFile]
    var albums: [AlbumID: IndexedAlbum]
    var lastCompleteScan: Date?

    init() {
        version = Self.currentVersion
        files = [:]
        albums = [:]
        lastCompleteScan = nil
    }

    var albumIDs: [AlbumID] { albums.keys.sorted() }
}
